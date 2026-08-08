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
--
-- A primeira versão deste passo media o buraco DA PRODUÇÃO antes e depois, e
-- exigia que diminuísse. Passou no dia em que foi escrita — havia 12
-- experimentais sem vínculo — e virou vermelho permanente no dia seguinte,
-- quando o próprio job fechou o buraco: o que sobra em produção é justamente
-- o que ele NÃO consegue casar. Teste que precisa de uma pendência viva pra
-- passar é um teste que se auto-destrói ao consertar o problema.
--
-- Agora a pendência é fabricada aqui: um lead e a aula dele, casáveis pela
-- chave natural, sem vínculo nenhum. Não depende do estado de produção, e
-- prova a mesma coisa — o comando do job, e não outra coisa, cria o vínculo.
insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000000600', 'ZZTESTE unidade 060', 'ZZTESTE060')
on conflict (id) do nothing;

insert into public.professores (id, nome, telefone_whatsapp, ativo) values
  (-60001, 'ZZTESTE Prof 060', '5521991110601', true);

insert into public.leads (id, unidade_id, whatsapp, status)
values (-60001, '00000000-0000-4000-8000-000000000600', '5521991116001', 'novo');

insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id)
values (-60001, -60001, 'ZZTESTE Aluno 060', '00000000-0000-4000-8000-000000000600',
        (now() at time zone 'America/Sao_Paulo')::date + 2, '19:00',
        'experimental_agendada', -60001);

insert into public.aulas_emusys
  (id, emusys_id, unidade_id, professor_id, data_aula, data_hora_inicio, categoria, cancelada)
values (-60001, -960001, '00000000-0000-4000-8000-000000000600', -60001,
        (now() at time zone 'America/Sao_Paulo')::date + 2,
        (((now() at time zone 'America/Sao_Paulo')::date + 2) + time '19:00')
          at time zone 'America/Sao_Paulo',
        'experimental', false);

-- A pendência tem que existir ANTES, senão o passo de depois não prova nada.
insert into _res select 'a fixture comeca sem vinculo', '0',
  (select count(*)::text from public.lead_experimental_aulas
    where lead_experimental_id = -60001);

do $$
declare v_cmd text;
begin
  select command into v_cmd from cron.job where jobname = 'reconciliar-experimental-aulas';
  execute v_cmd;
end $$;

insert into _res select 'rodar o comando do job cria o vinculo', 'vinculado',
  (select coalesce(v.estado, 'CONTINUOU SEM VINCULO')
     from public.lead_experimental_aulas v
    where v.lead_experimental_id = -60001 and v.substituido_em is null);

insert into _res select 'e o vinculo aponta pra aula certa', '-60001',
  (select coalesce(v.aula_local_id::text, 'NENHUMA')
     from public.lead_experimental_aulas v
    where v.lead_experimental_id = -60001 and v.substituido_em is null);

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
