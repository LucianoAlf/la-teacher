-- Teste da 047 — a experimental se distingue, e a aula comum nao muda
--
-- Metade do teste e sobre o que NAO mudou. Esta migration mexe no payload da
-- agenda inteira, que e a tela mais usada do app: se ela quebrar a aula comum
-- pra marcar a experimental, o conserto e pior que o defeito.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000000470', 'ZZTESTE unidade 047', 'ZZTESTE047')
on conflict (id) do nothing;
insert into public.usuarios (id, nome, email, auth_user_id) values
  (-47901, 'ZZTESTE Dono 047', 'zz-dono-047@exemplo.invalido', '00000000-0000-4000-8000-000000047901');
insert into public.professores (id, nome, usuario_id) values (-47001, 'ZZTESTE Professor 047', -47901);
insert into public.alunos (id, nome, unidade_id) values
  (-47001, 'ZZTESTE Aluno Comum 047', '00000000-0000-4000-8000-000000000470');
insert into public.leads (id, unidade_id, whatsapp, status) values
  (-47001, '00000000-0000-4000-8000-000000000470', '5521999470001', 'novo'),
  (-47002, '00000000-0000-4000-8000-000000000470', '5521999470002', 'novo');
insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id)
values
  (-47001, -47001, 'ZZTESTE Helena 047',      '00000000-0000-4000-8000-000000000470',
   current_date, '16:00', 'experimental_agendada', -47001),
  (-47002, -47002, 'ZZTESTE Sem Vinculo 047', '00000000-0000-4000-8000-000000000470',
   current_date, '17:00', 'experimental_agendada', -47001);

insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, data_hora_fim, tipo,
   categoria, curso_nome, turma_nome, professor_id, cancelada)
values
  -- aula COMUM: o controle. Se ela mudar, a agenda inteira mudou.
  (-47001, -947001, '00000000-0000-4000-8000-000000000470', current_date,
   (current_date + time '15:00') at time zone 'America/Sao_Paulo',
   (current_date + time '16:00') at time zone 'America/Sao_Paulo',
   'turma', 'regular', 'ZZTESTE Canto', 'ZZTESTE T1', -47001, false),
  -- experimental COM vinculo: o caso feliz
  (-47002, -947002, '00000000-0000-4000-8000-000000000470', current_date,
   (current_date + time '16:00') at time zone 'America/Sao_Paulo',
   (current_date + time '17:00') at time zone 'America/Sao_Paulo',
   'individual', 'experimental', 'ZZTESTE Canto', null, -47001, false),
  -- experimental SEM vinculo: o reconciliador ainda nao casou. Precisa
  -- aparecer como experimental E com vinculo nulo — sao coisas diferentes.
  (-47003, -947003, '00000000-0000-4000-8000-000000000470', current_date,
   (current_date + time '17:00') at time zone 'America/Sao_Paulo',
   (current_date + time '18:00') at time zone 'America/Sao_Paulo',
   'individual', 'experimental', 'ZZTESTE Canto', null, -47001, false);

insert into public.aula_alunos_emusys
  (id, aula_emusys_id, unidade_id, aluno_chave, aluno_id, aluno_nome, aluno_nome_normalizado)
values
  (-47001, -47001, '00000000-0000-4000-8000-000000000470', 'zz-47001', -47001,
   'ZZTESTE Aluno Comum 047', 'zzteste aluno comum 047'),
  (-47002, -47002, '00000000-0000-4000-8000-000000000470', 'zz-47002', null,
   'ZZTESTE Helena 047', 'zzteste helena 047'),
  (-47003, -47003, '00000000-0000-4000-8000-000000000470', 'zz-47003', null,
   'ZZTESTE Sem Vinculo 047', 'zzteste sem vinculo 047');

insert into public.lead_experimental_aulas (lead_experimental_id, aula_local_id, estado, casado_por)
values (-47001, -47002, 'vinculado', 'chave_natural');

create temp table _ag(j jsonb) on commit drop;
do $$
declare v_out jsonb;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000047901"}',true);
  select public.app_minha_agenda_sessao(current_date) into v_out;
  reset role;
  insert into _ag values (v_out);
end $$;

create temp table _s(aula_id integer, j jsonb) on commit drop;
insert into _s
select (a->>'aula_id_ancora')::integer, a
  from jsonb_array_elements((select j from _ag)) a;

-- ── A aula COMUM nao mudou ────────────────────────────────────────────────
insert into _res select 'a aula comum nao vira experimental', 'false',
  (select coalesce(j->>'experimental','(ausente)') from _s where aula_id=-47001);
insert into _res select 'e nao ganha vinculo do nada', 'nulo',
  (select case when j->>'vinculo_id' is null then 'nulo' else 'GANHOU' end
     from _s where aula_id=-47001);
insert into _res select 'a aula comum mantem o roster', '1',
  (select coalesce(j->>'n_alunos','(ausente)') from _s where aula_id=-47001);
insert into _res select 'e mantem o nome do curso', 'ZZTESTE Canto',
  (select coalesce(j->>'curso','(ausente)') from _s where aula_id=-47001);
insert into _res select 'e mantem a hora', '15:00',
  (select coalesce(j->>'hora','(ausente)') from _s where aula_id=-47001);

-- ── A experimental COM vinculo ────────────────────────────────────────────
insert into _res select 'a experimental se declara experimental', 'true',
  (select coalesce(j->>'experimental','(ausente)') from _s where aula_id=-47002);
insert into _res select 'e traz o vinculo pra abrir a ficha', 'tem vinculo',
  (select case when j->>'vinculo_id' is not null then 'tem vinculo' else 'SEM VINCULO' end
     from _s where aula_id=-47002);
insert into _res select 'o vinculo apontado e o certo', 'sim',
  (select case when (j->>'vinculo_id')::bigint
                  = (select id from lead_experimental_aulas where lead_experimental_id=-47001)
               then 'sim' else 'APONTOU OUTRO' end
     from _s where aula_id=-47002);
insert into _res select 'e traz o nome de quem vem', 'ZZTESTE Helena 047',
  (select coalesce(j->>'experimental_nome','(ausente)') from _s where aula_id=-47002);

-- ── A experimental SEM vinculo ────────────────────────────────────────────
-- Duas coisas diferentes que a tela precisa distinguir: "nao e experimental"
-- e "e experimental mas ainda nao da pra registrar".
insert into _res select 'sem vinculo, ainda se declara experimental', 'true',
  (select coalesce(j->>'experimental','(ausente)') from _s where aula_id=-47003);
insert into _res select 'sem vinculo, o vinculo vem nulo', 'nulo',
  (select case when j->>'vinculo_id' is null then 'nulo' else 'INVENTOU' end
     from _s where aula_id=-47003);

-- ── Vinculo cancelado nao conta ───────────────────────────────────────────
-- O vinculo tem historia: quando a experimental e remarcada, o antigo fica
-- cancelado_em. Apontar pro cancelado abriria a ficha da aula que nao houve.
do $$
declare v_out jsonb;
begin
  update lead_experimental_aulas set cancelado_em = now()
   where lead_experimental_id = -47001;
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000047901"}',true);
  select public.app_minha_agenda_sessao(current_date) into v_out;
  reset role;
  insert into _res
  select 'vinculo cancelado nao e apontado', 'nulo',
         (select case when a->>'vinculo_id' is null then 'nulo' else 'APONTOU O CANCELADO' end
            from jsonb_array_elements(v_out) a where (a->>'aula_id_ancora')::integer = -47002);
end $$;

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
