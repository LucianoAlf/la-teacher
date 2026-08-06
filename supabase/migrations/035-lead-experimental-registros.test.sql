-- Teste da 035 — a RPC e o unico caminho, e ela deriva o que nao se digita
--
-- O teste roda como service_role, onde auth.uid() e nulo. Montagem de cenario
-- usa a funcao INTERNA; a guarda de posse se testa forjando request.jwt.claims
-- (padrao do Supabase) pra cada usuario ZZTESTE.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000000350', 'ZZTESTE unidade 035',  'ZZTESTE035'),
  ('00000000-0000-4000-8000-000000000351', 'ZZTESTE unidade 035b', 'ZZTESTE035B')
on conflict (id) do nothing;

insert into public.usuarios (id, nome, email, auth_user_id) values
  (-35901, 'ZZTESTE Usuario Dono',    'zzteste-dono-35@exemplo.invalido',
   '00000000-0000-4000-8000-000000035901'),
  (-35902, 'ZZTESTE Usuario Intruso', 'zzteste-intruso-35@exemplo.invalido',
   '00000000-0000-4000-8000-000000035902');

insert into public.professores (id, nome, usuario_id) values
  (-35001, 'ZZTESTE Professor Dono',    -35901),
  (-35002, 'ZZTESTE Professor Intruso', -35902);

insert into public.leads (id, unidade_id, whatsapp, status) values
  (-35001, '00000000-0000-4000-8000-000000000350', '5521999350001', 'novo'),
  (-35002, '00000000-0000-4000-8000-000000000350', '5521999350002', 'novo'),
  (-35003, '00000000-0000-4000-8000-000000000350', '5521999350003', 'novo'),
  (-35004, '00000000-0000-4000-8000-000000000350', '5521999350004', 'novo'),
  (-35005, '00000000-0000-4000-8000-000000000350', '5521999350005', 'novo');

insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id)
values
  (-35001, -35001, 'ZZTESTE Registra ok', '00000000-0000-4000-8000-000000000350', current_date+1, '10:00', 'experimental_agendada', -35001),
  (-35002, -35002, 'ZZTESTE Faltou',      '00000000-0000-4000-8000-000000000350', current_date+1, '11:00', 'experimental_faltou',    -35001),
  (-35003, -35003, 'ZZTESTE Pendente',    '00000000-0000-4000-8000-000000000350', current_date+1, '12:00', 'experimental_agendada', -35001),
  -- pendente COM aula: exercita a trava de estado de verdade (mata M3). Sem
  -- este caso, o bloqueio vinha do join vazio, nao da trava.
  (-35004, -35004, 'ZZTESTE Pendente com aula', '00000000-0000-4000-8000-000000000350', current_date+1, '16:00', 'experimental_agendada', -35001),
  -- aula SEM professor: com usuario tambem sem professor, a comparacao de
  -- posse vira `null is distinct from null` = FALSE e passaria (mata M6)
  (-35005, -35005, 'ZZTESTE Aula sem professor', '00000000-0000-4000-8000-000000000350', current_date+1, '17:00', 'experimental_agendada', null);

insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, categoria, professor_id, cancelada)
values
  (-35001, -935001, '00000000-0000-4000-8000-000000000350', current_date+1,
   (current_date+1 + time '10:00') at time zone 'America/Sao_Paulo', 'experimental', -35001, false),
  (-35002, -935002, '00000000-0000-4000-8000-000000000350', current_date+1,
   (current_date+1 + time '11:00') at time zone 'America/Sao_Paulo', 'experimental', -35001, false),
  (-35004, -935004, '00000000-0000-4000-8000-000000000350', current_date+1,
   (current_date+1 + time '16:00') at time zone 'America/Sao_Paulo', 'experimental', -35001, false),
  -- aula SEM professor: existe em producao (professor_id e nullable)
  (-35005, -935005, '00000000-0000-4000-8000-000000000350', current_date+1,
   (current_date+1 + time '17:00') at time zone 'America/Sao_Paulo', 'experimental', null, false);

insert into public.lead_experimental_aulas (lead_experimental_id, aula_local_id, estado, casado_por)
values (-35001, -35001, 'vinculado', 'chave_natural'),
       (-35002, -35002, 'faltou',    'chave_natural'),
       (-35003, null,   'pendente',  null),
       (-35004, -35004, 'pendente',  'chave_natural'),
       (-35005, -35005, 'vinculado', 'chave_natural');

-- ── Registra e deriva unidade/professor do vinculo ─────────────────────────
do $$
declare v_vinc bigint; v_reg uuid;
begin
  select id into v_vinc from lead_experimental_aulas where lead_experimental_id=-35001;
  select public.fn_registrar_experimental_interno(
           v_vinc, 'Trabalhou acordes basicos', 'Ele pegou rapido, se divertiu',
           'Comecar por musica que ele gosta', 'Mae perguntou preco 2x — quente')
    into v_reg;
  insert into _res select 'unidade derivada do vinculo', '00000000-0000-4000-8000-000000000350',
    unidade_id::text from lead_experimental_registros where id=v_reg;
  insert into _res select 'professor derivado do vinculo', '-35001',
    professor_id::text from lead_experimental_registros where id=v_reg;
  insert into _res select 'nasce aguardando confirmacao', 'aguardando_confirmacao',
    status from lead_experimental_registros where id=v_reg;
end $$;

-- ── Segunda chamada EDITA o vigente, nao estoura nem duplica ───────────────
do $$
declare v_vinc bigint; v_reg uuid;
begin
  select id into v_vinc from lead_experimental_aulas where lead_experimental_id=-35001;
  begin
    select public.fn_registrar_experimental_interno(
             v_vinc, 'TEXTO EDITADO', 'idem', 'idem', 'idem') into v_reg;
    insert into _res values ('2a chamada nao estoura', 'ok', 'ok');
  exception when unique_violation then
    insert into _res values ('2a chamada nao estoura', 'ok', 'ESTOUROU unique_violation');
  end;
end $$;

insert into _res
select '2a chamada mantem 1 registro vigente', '1',
       (select count(*)::text from lead_experimental_registros r
          join lead_experimental_aulas v on v.id=r.vinculo_id
         where v.lead_experimental_id=-35001 and r.status <> 'descartado');
insert into _res
select '2a chamada gravou o texto novo', 'TEXTO EDITADO',
       (select r.anotacao_pedagogica from lead_experimental_registros r
          join lead_experimental_aulas v on v.id=r.vinculo_id
         where v.lead_experimental_id=-35001 and r.status <> 'descartado');

-- ── Travas de estado ───────────────────────────────────────────────────────
do $$
declare v_vinc bigint;
begin
  select id into v_vinc from lead_experimental_aulas where lead_experimental_id=-35002;
  begin
    perform public.fn_registrar_experimental_interno(v_vinc, 'a','b','c','d');
    insert into _res values ('faltou nao aceita registro', 'bloqueado', 'ACEITOU');
  exception when others then
    insert into _res values ('faltou nao aceita registro', 'bloqueado', 'bloqueado');
  end;

  select id into v_vinc from lead_experimental_aulas where lead_experimental_id=-35003;
  begin
    perform public.fn_registrar_experimental_interno(v_vinc, 'a','b','c','d');
    insert into _res values ('pendente sem aula nao aceita registro', 'bloqueado', 'ACEITOU');
  exception when others then
    insert into _res values ('pendente sem aula nao aceita registro', 'bloqueado', 'bloqueado');
  end;

  -- Pendente COM aula: aqui a TRAVA DE ESTADO e que precisa barrar. No caso
  -- acima o bloqueio vinha do join vazio, e a trava nunca era exercitada.
  select id into v_vinc from lead_experimental_aulas where lead_experimental_id=-35004;
  begin
    perform public.fn_registrar_experimental_interno(v_vinc, 'a','b','c','d');
    insert into _res values ('pendente COM aula: trava de estado barra', 'bloqueado', 'ACEITOU');
  exception when others then
    insert into _res values ('pendente COM aula: trava de estado barra', 'bloqueado',
      case when sqlerrm like '%experimental_sem_aula_vinculada%' then 'bloqueado'
           else 'bloqueado por outro motivo: '||sqlerrm end);
  end;
end $$;

-- ── AUTORIZACAO: professor errado e BARRADO ────────────────────────────────
-- Prova os DOIS lados. Provar so que o intruso e barrado deixaria passar uma
-- implementacao que barra todo mundo (inclusive o dono) — falso-verde.
do $$
declare v_vinc bigint;
begin
  select id into v_vinc from lead_experimental_aulas where lead_experimental_id=-35001;

  begin
    perform set_config('request.jwt.claims',
      '{"sub":"00000000-0000-4000-8000-000000035901"}', true);
    perform public.app_registrar_experimental(v_vinc, 'dono escreveu','b','c','d');
    insert into _res values ('professor dono da aula consegue registrar', 'ok', 'ok');
  exception when others then
    insert into _res values ('professor dono da aula consegue registrar', 'ok', 'BARROU: '||sqlerrm);
  end;

  begin
    perform set_config('request.jwt.claims',
      '{"sub":"00000000-0000-4000-8000-000000035902"}', true);
    perform public.app_registrar_experimental(v_vinc, 'INTRUSO ESCREVEU','b','c','d');
    insert into _res values ('professor de OUTRA aula e barrado', 'barrado',
      'ESCREVEU — qualquer logado registra qualquer aula');
  exception when others then
    insert into _res values ('professor de OUTRA aula e barrado', 'barrado', 'barrado');
  end;

  perform set_config('request.jwt.claims', null, true);
end $$;

-- ── Usuario SEM professor vinculado, em aula SEM professor ─────────────────
-- O caso que so o mutante revelou: sem a guarda `v_prof is null`, o codigo
-- segue e compara `v_prof_aula is distinct from v_prof`. Com os dois nulos
-- isso da FALSE e a escrita PASSA — qualquer sessao sem professor vinculado
-- registraria em aula orfa. A guarda tem que barrar ANTES da comparacao.
do $$
declare v_vinc bigint;
begin
  select id into v_vinc from lead_experimental_aulas where lead_experimental_id=-35005;
  begin
    -- sem claim nenhum: fn_professor_do_usuario() devolve null
    perform set_config('request.jwt.claims', null, true);
    perform public.app_registrar_experimental(v_vinc, 'ORFAO ESCREVEU','b','c','d');
    insert into _res values ('sessao sem professor nao registra em aula orfa', 'barrado',
      'ESCREVEU — null is distinct from null e false');
  exception when others then
    insert into _res values ('sessao sem professor nao registra em aula orfa', 'barrado', 'barrado');
  end;
end $$;

insert into _res
select 'aula orfa segue sem registro', '0',
       (select count(*)::text from lead_experimental_registros r
          join lead_experimental_aulas v on v.id=r.vinculo_id
         where v.lead_experimental_id=-35005);

insert into _res
select 'texto do intruso NAO entrou', 'dono escreveu',
       (select r.anotacao_pedagogica from lead_experimental_registros r
          join lead_experimental_aulas v on v.id=r.vinculo_id
         where v.lead_experimental_id=-35001 and r.status <> 'descartado');

-- ── Escrita direta na tabela e negada por PERMISSAO ────────────────────────
insert into _res
select 'authenticated nao escreve direto na tabela', 'sem privilegio',
       case when has_table_privilege('authenticated','public.lead_experimental_registros','insert')
             or has_table_privilege('authenticated','public.lead_experimental_registros','update')
            then 'ESCREVE — fronteira e convencao, nao permissao'
            else 'sem privilegio' end;
insert into _res
select 'anon nao le a tabela', 'sem privilegio',
       case when has_table_privilege('anon','public.lead_experimental_registros','select')
            then 'LE' else 'sem privilegio' end;
insert into _res
select 'authenticated nao executa a funcao interna', 'sem privilegio',
       case when has_function_privilege('authenticated',
              'public.fn_registrar_experimental_interno(bigint,text,text,text,text,text)','execute')
            then 'EXECUTA — contorna a guarda de posse' else 'sem privilegio' end;

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
