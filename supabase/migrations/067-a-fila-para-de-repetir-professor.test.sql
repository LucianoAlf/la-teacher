-- 067 (teste) — a fila para de repetir professor
--
-- O passo que dá nome à migration é "a fila NAO repete professor". Ele nasceu de
-- um defeito que passou pelos 10 passos da 065 e pelos 5 mutantes dela: nenhum
-- perguntava se a mesma pessoa aparecia duas vezes. Quem denunciou foi a tela,
-- mostrando "38 professores afetados" em cima de uma fila de 60 linhas.
--
-- Lição embutida aqui: teste de agregação precisa de um passo sobre a CHAVE, não
-- só sobre os números. Somar certo por linha errada continua somando certo.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

do $$
declare v_erro text := 'nao levantou';
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  begin perform public.app_coordenacao_em_aberto(7, null);
  exception when others then v_erro := sqlerrm; end;
  insert into _res values ('sem identidade a RPC recusa', 'sim',
    case when v_erro like '%apenas_admin%' then 'sim' else 'NAO — ' || v_erro end);
end $$;

do $$
declare v_uid uuid;
begin
  select u.auth_user_id into v_uid
    from public.la_teacher_coordenacao c
    join public.usuarios u on u.id = c.usuario_id
   where u.auth_user_id is not null and coalesce(u.ativo, true) limit 1;
  insert into _res values ('ancora: ha coordenador com login', 'sim',
    case when v_uid is null then 'NAO' else 'sim' end);
  if v_uid is not null then
    perform set_config('request.jwt.claim.sub', v_uid::text, true);
  end if;
end $$;

create temp table _saida on commit drop as
  select public.app_coordenacao_em_aberto(7, null) as j;

-- ─── O PASSO DESTA MIGRATION ────────────────────────────────────────────────
-- Âncora: sem professor multi-unidade na janela, o defeito não teria como
-- aparecer e o passo passaria verde sem medir nada.
insert into _res select 'ancora: ha professor em mais de uma unidade na janela', 'sim',
  (select case when count(*) > 0 then 'sim'
               else 'NAO — ninguem multi-unidade, o passo abaixo nao prova nada' end
     from (select professor_id
             from public.vw_presenca_pendencia
            where data_aula >= current_date - 7 and data_aula < current_date
            group by professor_id
           having count(distinct unidade_id) > 1) t);

insert into _res select 'a fila NAO repete professor', 'sim',
  (select case when count(*) = count(distinct (x->>'professor_id')::int) then 'sim'
               else 'NAO — ' || count(*)::text || ' linhas para '
                    || count(distinct (x->>'professor_id')::int)::text || ' professores' end
     from _saida, lateral jsonb_array_elements(j->'professores') x);

insert into _res select 'a fila tem exatamente 1 linha por professor do resumo',
  (select j->'resumo'->>'professores' from _saida),
  (select jsonb_array_length(j->'professores')::text from _saida);

insert into _res select 'quem e multi-unidade traz as duas na lista', 'sim',
  (select case
     when count(*) = 0 then 'NAO — nenhum multi-unidade na fila'
     when bool_and(x->>'unidades' like '%, %') then 'sim'
     else 'NAO — veio so uma unidade' end
     from _saida, lateral jsonb_array_elements(j->'professores') x
    where (x->>'professor_id')::int in (
      select professor_id from public.vw_presenca_pendencia
       where data_aula >= current_date - 7 and data_aula < current_date
       group by professor_id having count(distinct unidade_id) > 1));

-- Somar por pessoa não pode perder aula: o total das linhas tem que bater com
-- o resumo, que sai direto da view.
insert into _res select 'somar as linhas devolve o total do resumo',
  (select j->'resumo'->>'sem_lancamento' from _saida),
  (select coalesce(sum((x->>'em_aberto')::int), 0)::text
     from _saida, lateral jsonb_array_elements(j->'professores') x);

-- ─── O que a 065 já garantia e não pode regredir ────────────────────────────
insert into _res select 'o resumo bate com a view',
  (select count(*)::text from public.vw_presenca_pendencia
    where data_aula >= current_date - 7 and data_aula < current_date),
  (select j->'resumo'->>'sem_lancamento' from _saida);

insert into _res select 'ancora: ha valores distintos de em_aberto', 'sim',
  (select case when count(distinct (x->>'em_aberto')::int) >= 2 then 'sim'
               else 'NAO — todos empatados' end
     from _saida, lateral jsonb_array_elements(j->'professores') x);

insert into _res select 'a fila desce por urgencia', 'sim',
  (select case when bool_and(ok) then 'sim' else 'NAO — fila fora de ordem' end
     from (
       select (x->>'em_aberto')::int
              <= lag((x->>'em_aberto')::int, 1, 2147483647) over (order by ord) as ok
         from _saida, lateral jsonb_array_elements(j->'professores')
              with ordinality t(x, ord)
     ) s);

create temp table _unid on commit drop as
  select unidade_id from public.vw_presenca_pendencia
   where data_aula >= current_date - 7 and data_aula < current_date limit 1;

create temp table _saida_unid on commit drop as
  select public.app_coordenacao_em_aberto(7, (select unidade_id from _unid)) as j;

insert into _res select 'filtrar por unidade devolve menos que o total', 'sim',
  (select case
     when (u.j->'resumo'->>'sem_lancamento')::int = 0 then 'NAO — filtro zerou tudo'
     when (u.j->'resumo'->>'sem_lancamento')::int
          < (t.j->'resumo'->>'sem_lancamento')::int then 'sim'
     else 'NAO — filtro nao filtrou' end
     from _saida_unid u, _saida t);

insert into _res select 'ancora: ha aula de hoje na pendencia', 'sim',
  (select case when count(*) > 0 then 'sim' else 'NAO' end
     from public.vw_presenca_pendencia where data_aula = current_date);

insert into _res select 'a aula de HOJE nao entra na cobranca',
  (select count(*)::text from public.vw_presenca_pendencia
    where data_aula >= current_date - 7 and data_aula < current_date),
  (select j->'resumo'->>'sem_lancamento' from _saida);

insert into _res select 'anon NAO executa a RPC do painel', 'sim',
  (select case when has_function_privilege('anon',
       'public.app_coordenacao_em_aberto(int, uuid)', 'execute')
     then 'NAO — anon pode executar' else 'sim' end);

insert into _res select 'authenticated executa a RPC do painel', 'sim',
  (select case when has_function_privilege('authenticated',
       'public.app_coordenacao_em_aberto(int, uuid)', 'execute')
     then 'sim' else 'NAO' end);

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
