-- Teste da 060 — o reconciliador passa a rodar
--
-- Testar cron parece bobagem até lembrar que o defeito QUE ESTE ARQUIVO
-- CONSERTA foi exatamente este: uma função pronta, testada, com mutante, e
-- nada que a chamasse. O que precisa ser verdade não é "a função funciona"
-- (a 033/034 já provam isso) — é "existe um job ATIVO, no horário certo,
-- apontando pra função certa".
--
-- Por isso os passos olham as quatro coisas que podem estar erradas sem que
-- ninguém perceba: existir, estar ativo, chamar a função certa, e no ritmo
-- combinado. Job inativo é o mais traiçoeiro: ele aparece na lista.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

insert into _res select 'o job existe', '1',
  (select count(*)::text from cron.job where jobname = 'reconciliar-experimental-aulas');

insert into _res select 'o job esta ativo', 'true',
  (select active::text from cron.job where jobname = 'reconciliar-experimental-aulas');

insert into _res select 'chama a funcao certa', 'sim',
  (select case when command ilike '%fn_reconciliar_experimental_aulas%' then 'sim' else command end
     from cron.job where jobname = 'reconciliar-experimental-aulas');

-- O ritmo importa: os três sync-metadados terminam em :10 do quarto de hora,
-- e reconciliar antes deles é reconciliar contra espelho velho.
insert into _res select 'roda depois dos tres sync-metadados', '12,27,42,57 * * * *',
  (select schedule from cron.job where jobname = 'reconciliar-experimental-aulas');

-- A janela: 7 dias. Menor que isso e a experimental de sexta só casa na quinta.
insert into _res select 'a janela e de 7 dias', 'sim',
  (select case when command ~ '\(\s*7\s*,' then 'sim' else command end
     from cron.job where jobname = 'reconciliar-experimental-aulas');

-- E o principal: RODAR o comando do job resolve o que estava parado.
-- Mede o mesmo universo que o painel do professor enxerga.
create temp table _antes(n int) on commit drop;
insert into _antes
select count(*) from public.lead_experimentais le
 where le.status = 'experimental_agendada'
   and le.data_experimental between current_date and current_date + 7
   and not exists (select 1 from public.lead_experimental_aulas v
                    where v.lead_experimental_id = le.id
                      and v.substituido_em is null and v.estado = 'vinculado');

do $$
declare v_cmd text;
begin
  select command into v_cmd from cron.job where jobname = 'reconciliar-experimental-aulas';
  execute v_cmd;
end $$;

-- Antes de rodar havia experimental sem vínculo (senão o passo abaixo não
-- prova nada); depois de rodar, sobram menos.
insert into _res select 'havia experimental sem vinculo antes', 'true',
  (select (n > 0)::text from _antes);

insert into _res select 'rodar o job reduz o buraco', 'true',
  (select ((select count(*) from public.lead_experimentais le
             where le.status='experimental_agendada'
               and le.data_experimental between current_date and current_date + 7
               and not exists (select 1 from public.lead_experimental_aulas v
                                where v.lead_experimental_id = le.id
                                  and v.substituido_em is null and v.estado='vinculado'))
            < (select n from _antes))::text);

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
