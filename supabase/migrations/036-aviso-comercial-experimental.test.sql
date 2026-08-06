-- Teste da 036 — destinatario resolvido por unidade; ausencia fica VISIVEL
--
-- Duas coisas alem do plano, porque o plano deixava sem carrasco:
--   * as asercoes de permissao (revoke/grant sem teste e convencao, nao regra)
--   * o escopo das asercoes de lease preso ao REGISTRO do ensaio, nao a um
--     "order by criado_em desc limit 1" solto — que mede o mundo, nao a rodada.
--
-- Nenhum prontuario real vira bancada: tudo ZZTESTE, ids negativos.

create temp table _res(passo text, esperado text, obtido text) on commit drop;
-- Os ids dos registros do ensaio, pra toda asercao falar da rodada sob teste.
create temp table _reg(quem text, registro_id uuid, notificacao_id uuid) on commit drop;

insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000000360', 'ZZTESTE unidade 036 com contato', 'ZZTESTE036'),
  ('00000000-0000-4000-8000-000000000361', 'ZZTESTE unidade 036 SEM contato', 'ZZTESTE036B')
on conflict (id) do nothing;

insert into public.unidade_contato_comercial (unidade_id, nome, whatsapp)
values ('00000000-0000-4000-8000-000000000360', 'ZZTESTE Comercial', '5521900000036');

insert into public.professores (id, nome) values (-36001, 'ZZTESTE Professor 036');

insert into public.leads (id, unidade_id, whatsapp, status) values
  (-36001, '00000000-0000-4000-8000-000000000360', '5521999360001', 'novo'),
  (-36002, '00000000-0000-4000-8000-000000000361', '5521999360002', 'novo');

insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id)
values
  (-36001, -36001, 'ZZTESTE Com Contato', '00000000-0000-4000-8000-000000000360', current_date+1, '10:00', 'experimental_agendada', -36001),
  (-36002, -36002, 'ZZTESTE Sem Contato', '00000000-0000-4000-8000-000000000361', current_date+1, '11:00', 'experimental_agendada', -36001);

insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, categoria, professor_id, cancelada)
values
  (-36001, -936001, '00000000-0000-4000-8000-000000000360', current_date+1,
   (current_date+1 + time '10:00') at time zone 'America/Sao_Paulo', 'experimental', -36001, false),
  (-36002, -936002, '00000000-0000-4000-8000-000000000361', current_date+1,
   (current_date+1 + time '11:00') at time zone 'America/Sao_Paulo', 'experimental', -36001, false);

insert into public.lead_experimental_aulas (lead_experimental_id, aula_local_id, estado, casado_por)
values (-36001, -36001, 'vinculado', 'chave_natural'),
       (-36002, -36002, 'vinculado', 'chave_natural');

-- ── Com contato: aviso enfileirado pro numero da unidade ───────────────────
do $$
declare v_vinc bigint; v_reg uuid; v_not uuid;
begin
  select id into v_vinc from lead_experimental_aulas where lead_experimental_id=-36001;
  select public.fn_registrar_experimental_interno(v_vinc, 'aula boa', 'foi muito bem',
           'seguir no violao', 'SEGREDO COMERCIAL') into v_reg;
  select (public.fabio_claim_aviso_comercial(v_reg)->>'notificacao_id')::uuid into v_not;
  insert into _reg values ('com_contato', v_reg, v_not);

  insert into _res select 'destinatario resolvido pela unidade', '5521900000036',
    coalesce(destinatario_whatsapp,'(nulo)') from fabio_notificacoes where id=v_not;
  insert into _res select 'destinatario_tipo comercial', 'comercial',
    destinatario_tipo from fabio_notificacoes where id=v_not;
  insert into _res select 'professor_id nulo em aviso comercial', 'nulo',
    case when professor_id is null then 'nulo' else 'PREENCHIDO' end
    from fabio_notificacoes where id=v_not;
  -- aqui a leitura de conversao DEVE aparecer: o destinatario e o circulo interno
  insert into _res select 'aviso ao comercial carrega a leitura', 'sim',
    case when corpo like '%SEGREDO COMERCIAL%' then 'sim' else 'nao' end
    from fabio_notificacoes where id=v_not;
end $$;

-- ── O claim e claim de verdade: lease, token e tentativas ─────────────────
-- Preso ao id da rodada: "o mais recente da fila" acertaria por sorte.
insert into _res
select 'aviso nasce com lease vivo', 'sim',
       coalesce((select case when n.lease_token is not null and n.lease_expira_em > now()
                             then 'sim' else 'nao' end
                   from fabio_notificacoes n join _reg g on g.notificacao_id = n.id
                  where g.quem='com_contato'), '(nenhum)');
insert into _res
select 'aviso nasce com tentativas=1', '1',
       coalesce((select n.tentativas::text
                   from fabio_notificacoes n join _reg g on g.notificacao_id = n.id
                  where g.quem='com_contato'), '(nenhum)');

-- ── Lease VIVO nao e roubado por uma segunda chamada ───────────────────────
do $$
declare v_out jsonb;
begin
  select public.fabio_claim_aviso_comercial((select registro_id from _reg where quem='com_contato'))
    into v_out;
  insert into _res values ('lease vivo nao e reclamado de novo', 'false', (v_out->>'claimed'));
end $$;

-- ── Sem contato: fica VISIVEL como pulada_sem_destinatario ─────────────────
do $$
declare v_vinc bigint; v_reg uuid; v_not uuid;
begin
  select id into v_vinc from lead_experimental_aulas where lead_experimental_id=-36002;
  select public.fn_registrar_experimental_interno(v_vinc, 'a','b','c','d') into v_reg;
  select (public.fabio_claim_aviso_comercial(v_reg)->>'notificacao_id')::uuid into v_not;
  insert into _reg values ('sem_contato', v_reg, v_not);

  insert into _res values ('sem contato devolve null', 'null', coalesce(v_not::text, 'null'));
  insert into _res select 'sem contato deixa RASTRO na fila', 'pulada_sem_destinatario',
    coalesce((select status from fabio_notificacoes
               where referencia_tipo='lead_experimental_registro'
                 and referencia_id=v_reg::text), '(nenhum)');
  insert into _res select 'o rastro diz POR QUE', 'sem_contato_comercial_na_unidade',
    coalesce((select motivo_pulada from fabio_notificacoes
               where referencia_tipo='lead_experimental_registro'
                 and referencia_id=v_reg::text), '(nenhum)');
end $$;

-- Repetir sem contato nao empilha rastro: a idempotencia e do indice.
do $$
begin
  perform public.fabio_claim_aviso_comercial((select registro_id from _reg where quem='sem_contato'));
  insert into _res select 'repetir sem contato nao empilha rastro', '1',
    (select count(*)::text from fabio_notificacoes
      where referencia_tipo='lead_experimental_registro'
        and referencia_id=(select registro_id from _reg where quem='sem_contato')::text);
end $$;

-- ── Rastro de "sem destinatario" e RETOMADO quando o contato aparece ───────
insert into public.unidade_contato_comercial (unidade_id, nome, whatsapp)
values ('00000000-0000-4000-8000-000000000361', 'ZZTESTE Comercial Tardio', '5521900000361');

do $$
declare v_reg uuid; v_out jsonb;
begin
  select registro_id into v_reg from _reg where quem='sem_contato';
  select public.fabio_claim_aviso_comercial(v_reg) into v_out;
  insert into _res values ('pulada_sem_destinatario e retomada apos cadastro', 'true',
    coalesce(v_out->>'claimed','(nulo)'));
  insert into _res select 'retomada pega o numero recem-cadastrado', '5521900000361',
    coalesce(destinatario_whatsapp,'(nulo)') from fabio_notificacoes
    where referencia_tipo='lead_experimental_registro' and referencia_id=v_reg::text;
  insert into _res select 'a retomada nao criou linha nova', '1',
    (select count(*)::text from fabio_notificacoes
      where referencia_tipo='lead_experimental_registro' and referencia_id=v_reg::text);
end $$;

-- ── CHECK impede aviso sem destinatario nenhum ─────────────────────────────
do $$
begin
  begin
    insert into fabio_notificacoes
      (professor_id, destinatario_tipo, tipo, categoria, corpo, canal, status)
    values (null, 'comercial', 'outro', 'informativa', 'x', 'whatsapp', 'processando');
    insert into _res values ('aviso sem destinatario rejeitado', 'rejeitado', 'ACEITOU');
  exception when check_violation then
    insert into _res values ('aviso sem destinatario rejeitado', 'rejeitado', 'rejeitado');
  end;
end $$;

-- ── O ramo de excecao NAO e porta: so vale pro formato exato (mata M7) ─────
-- Linha com o status de excecao mas em OUTRO formato (tipo professor, sem
-- professor_id) tem que ser rejeitada. Sem este passo, estreitar o CHECK nao
-- teria carrasco e o mutante M7 sobreviveria.
do $$
begin
  begin
    insert into fabio_notificacoes
      (professor_id, destinatario_tipo, tipo, categoria, corpo, canal, status)
    values (null, 'professor', 'outro', 'informativa', 'x', 'whatsapp',
            'pulada_sem_destinatario');
    insert into _res values ('excecao nao vira porta p/ outro formato', 'rejeitado', 'ACEITOU');
  exception when check_violation then
    insert into _res values ('excecao nao vira porta p/ outro formato', 'rejeitado', 'rejeitado');
  end;
end $$;

-- E o rastro legitimo (comercial, sem professor, sem telefone) CONTINUA aceito
-- — senao "estreitar" viraria "proibir", e a ausencia voltaria a ser invisivel.
do $$
begin
  begin
    insert into fabio_notificacoes
      (professor_id, destinatario_tipo, tipo, categoria, corpo, canal, status,
       referencia_tipo, referencia_id)
    values (null, 'comercial', 'outro', 'informativa', 'x', 'whatsapp',
            'pulada_sem_destinatario', 'zzteste_036', 'formato-legitimo');
    insert into _res values ('rastro legitimo de ausencia continua aceito', 'aceito', 'aceito');
  exception when check_violation then
    insert into _res values ('rastro legitimo de ausencia continua aceito', 'aceito', 'REJEITOU');
  end;
end $$;

-- ── Aviso de PROFESSOR sem professor_id continua impossivel ───────────────
-- professor_id deixou de ser NOT NULL nesta migration. Sem esta asercao, a
-- unica coisa segurando o formato antigo teria sido removida em silencio.
do $$
begin
  begin
    insert into fabio_notificacoes
      (professor_id, destinatario_tipo, tipo, categoria, corpo, canal, status)
    values (null, 'professor', 'outro', 'informativa', 'x', 'whatsapp', 'processando');
    insert into _res values ('aviso de professor sem professor_id rejeitado', 'rejeitado', 'ACEITOU');
  exception when check_violation then
    insert into _res values ('aviso de professor sem professor_id rejeitado', 'rejeitado', 'rejeitado');
  end;
end $$;

-- ── Permissao: o telefone do comercial nao e do app ───────────────────────
-- O plano trazia os revoke/grant mas nenhuma asercao. Fronteira sem carrasco
-- e convencao, nao regra — some no primeiro refactor sem ninguem ver.
insert into _res select 'authenticated nao le os contatos comerciais', 'sem privilegio',
  case when has_table_privilege('authenticated','public.unidade_contato_comercial','select')
       then 'LE — telefone do comercial exposto ao app' else 'sem privilegio' end;
insert into _res select 'anon nao le os contatos comerciais', 'sem privilegio',
  case when has_table_privilege('anon','public.unidade_contato_comercial','select')
       then 'LE' else 'sem privilegio' end;
insert into _res select 'authenticated nao enfileira aviso comercial', 'sem privilegio',
  case when has_function_privilege('authenticated',
         'public.fabio_claim_aviso_comercial(uuid,integer)','execute')
       then 'EXECUTA — professor dispara aviso em nome do Fabio' else 'sem privilegio' end;
insert into _res select 'service_role enfileira (e o worker)', 'executa',
  case when has_function_privilege('service_role',
         'public.fabio_claim_aviso_comercial(uuid,integer)','execute')
       then 'executa' else 'NAO EXECUTA — o aviso nunca sai' end;

-- ── Os tres contatos da casa entraram ─────────────────────────────────────
insert into _res select 'contato do Recreio e a Daiana', 'Daiana|5521968060404',
  coalesce((select c.nome||'|'||c.whatsapp from unidade_contato_comercial c
              join unidades u on u.id=c.unidade_id where u.codigo='REC'), '(nenhum)');
insert into _res select 'as tres unidades da casa tem contato', '3',
  (select count(*)::text from unidade_contato_comercial c
     join unidades u on u.id=c.unidade_id where u.codigo in ('CG','BARRA','REC'));

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
