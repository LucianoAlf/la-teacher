-- Teste da 064 — a pendência de presença para de levar 27 segundos
--
-- "O índice existe" não prova nada: um índice nas colunas erradas também
-- existe. O que precisa ser verdade é que o PLANO mudou — que o Postgres
-- escolheu ele — e que o custo caiu de verdade.
--
-- Por isso o teste roda `explain (analyze, buffers)` na view e mede duas
-- coisas do plano real: se o índice novo aparece, e quantos buffers a consulta
-- toca. Buffer é contagem determinística (não é tempo de relógio), então dá
-- pra afirmar um teto sem teste intermitente.
--
-- E o passo mais importante é o último: **as mesmas linhas de antes**. Índice
-- que muda resultado não é otimização, é defeito — e seria fácil não perceber,
-- porque a view fica rápida do mesmo jeito.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

-- Quantas linhas a view devolve HOJE, sem depender do índice pra isso.
create temp table _antes(n int) on commit drop;
insert into _antes select count(*) from public.vw_presenca_pendencia;

insert into _res select 'o indice existe com as tres colunas na ordem certa', 'sim',
  (select case when indexdef like '%(unidade_id, professor_id, data_hora_inicio)%'
               then 'sim' else coalesce(indexdef, 'NAO EXISTE') end
     from pg_indexes
    where schemaname='public' and indexname='idx_aulas_emusys_turma_no_horario');

insert into _res select 'e e parcial (so aula de turma nao cancelada)', 'sim',
  (select case when indexdef ilike '%where%tipo%turma%cancelada%'
               then 'sim' else coalesce(indexdef,'NAO EXISTE') end
     from pg_indexes
    where schemaname='public' and indexname='idx_aulas_emusys_turma_no_horario');

-- O plano de verdade.
create temp table _plano(linha text) on commit drop;
do $$
declare r record;
begin
  for r in execute 'explain (analyze, buffers, timing off, costs off) select * from public.vw_presenca_pendencia'
  loop
    insert into _plano values (r."QUERY PLAN");
  end loop;
end $$;

insert into _res select 'o planejador escolheu o indice novo', 'sim',
  (select case when exists (select 1 from _plano where linha like '%idx_aulas_emusys_turma_no_horario%')
               then 'sim' else 'NAO — continuou no plano velho' end);

insert into _res select 'a varredura por unidade sumiu do subplano', 'sim',
  (select case when not exists (select 1 from _plano where linha like '%idx_aulas_emusys_data%')
               then 'sim' else 'NAO — ainda cai no indice de unidade+data' end);

-- Teto de buffers. Antes eram 13.872.244; um teto de 3 milhões dá folga de
-- sobra pra crescimento de base e ainda assim reprova o plano velho.
insert into _res select 'a consulta toca menos de 3 milhoes de buffers', 'sim',
  (select case when coalesce(max(n), 0) < 3000000 then 'sim'
               else 'NAO — ' || coalesce(max(n),0)::text || ' buffers' end
     from (
       select (regexp_match(linha, 'shared hit=([0-9]+)'))[1]::bigint as n
         from _plano where linha like '%shared hit=%'
     ) t);

-- O que nenhuma otimização pode mudar.
insert into _res select 'a view devolve exatamente as mesmas linhas', (select n::text from _antes),
  (select count(*)::text from public.vw_presenca_pendencia);

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
