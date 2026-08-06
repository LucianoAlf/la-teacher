-- Teste da 043 — a fila que o worker le, e o que ele consegue ler dela
--
-- O passo que mais importa e "o que a fila lista, o worker CONSEGUE
-- reivindicar": a clausula daqui espelha a do claim, e espelho que se desloca
-- nao levanta erro — so passa a mentir. Ele compara as duas de verdade, sobre
-- as mesmas linhas, em vez de reler o SQL.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000000430', 'ZZTESTE unidade 043 com contato', 'ZZTESTE043'),
  ('00000000-0000-4000-8000-000000000431', 'ZZTESTE unidade 043 SEM contato', 'ZZTESTE043B')
on conflict (id) do nothing;

insert into public.unidade_contato_comercial (unidade_id, nome, whatsapp)
values ('00000000-0000-4000-8000-000000000430', 'ZZTESTE Comercial 043', '5521900000043')
on conflict (unidade_id) do nothing;

insert into public.usuarios (id, nome, email, auth_user_id) values
  (-43901, 'ZZTESTE Usuario 043', 'zzteste-043@exemplo.invalido',
   '00000000-0000-4000-8000-000000043901');
insert into public.professores (id, nome, usuario_id) values (-43001, 'ZZTESTE Professor 043', -43901);

insert into public.leads (id, unidade_id, whatsapp, status) values
  (-43001, '00000000-0000-4000-8000-000000000430', '5521999430001', 'novo'),
  (-43002, '00000000-0000-4000-8000-000000000431', '5521999430002', 'novo');
insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id)
values
  (-43001, -43001, 'ZZTESTE Com Contato 043', '00000000-0000-4000-8000-000000000430',
   current_date+1, '10:00', 'experimental_agendada', -43001),
  (-43002, -43002, 'ZZTESTE Sem Contato 043', '00000000-0000-4000-8000-000000000431',
   current_date+1, '11:00', 'experimental_agendada', -43001);
insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, categoria, professor_id, cancelada)
values
  (-43001, -943001, '00000000-0000-4000-8000-000000000430', current_date+1,
   (current_date+1 + time '10:00') at time zone 'America/Sao_Paulo', 'experimental', -43001, false),
  (-43002, -943002, '00000000-0000-4000-8000-000000000431', current_date+1,
   (current_date+1 + time '11:00') at time zone 'America/Sao_Paulo', 'experimental', -43001, false);
insert into public.lead_experimental_aulas (lead_experimental_id, aula_local_id, estado, casado_por)
values (-43001, -43001, 'vinculado', 'chave_natural'),
       (-43002, -43002, 'vinculado', 'chave_natural');

create temp table _ids(quem text, registro_id uuid) on commit drop;

-- Duas confirmacoes reais: uma em unidade com comercial, outra sem.
do $$
declare v_vinc bigint; v_reg uuid;
begin
  select id into v_vinc from lead_experimental_aulas where lead_experimental_id=-43001;
  select public.fn_registrar_experimental_interno(v_vinc, 'acordes', 'foi otimo',
           'seguir', 'CONVERSAO QUENTE') into v_reg;
  insert into _ids values ('com_contato', v_reg);
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000043901"}', true);
  perform public.app_confirmar_registro_experimental(v_reg, null);
  reset role;

  select id into v_vinc from lead_experimental_aulas where lead_experimental_id=-43002;
  select public.fn_registrar_experimental_interno(v_vinc, 'a','b','c','d') into v_reg;
  insert into _ids values ('sem_contato', v_reg);
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000043901"}', true);
  perform public.app_confirmar_registro_experimental(v_reg, null);
  reset role;
end $$;

create temp table _fila(j jsonb) on commit drop;
insert into _fila select public.fabio_avisos_comerciais_pendentes(50);

-- ── A fila enxerga os dois casos ──────────────────────────────────────────
insert into _res select 'o aviso recem-confirmado aparece na fila', '1',
  (select count(*)::text from jsonb_array_elements((select j from _fila)) a
     join _ids i on i.registro_id::text = a->>'registro_id'
    where i.quem='com_contato');

insert into _res select 'o rastro sem destinatario tambem aparece', '1',
  (select count(*)::text from jsonb_array_elements((select j from _fila)) a
     join _ids i on i.registro_id::text = a->>'registro_id'
    where i.quem='sem_contato');

insert into _res select 'o sem-destinatario vem DEPOIS do trabalho de verdade', 'depois',
  (select case when
      (select min(ord) from jsonb_array_elements((select j from _fila)) with ordinality t(a,ord)
         join _ids i on i.registro_id::text = t.a->>'registro_id' where i.quem='sem_contato')
      >
      (select min(ord) from jsonb_array_elements((select j from _fila)) with ordinality t(a,ord)
         join _ids i on i.registro_id::text = t.a->>'registro_id' where i.quem='com_contato')
    then 'depois' else 'ANTES — unidade sem cadastro empurra trabalho pra fora do lote' end);

-- ── ESPELHO: tudo que a fila lista, o claim aceita ────────────────────────
-- (exceto o sem-destinatario, que por definicao nao tem pra quem ir)
do $$
declare a jsonb; v_out jsonb; v_falhas integer := 0; v_testados integer := 0;
begin
  for a in select value from jsonb_array_elements((select j from _fila)) loop
    if a->>'status' = 'pulada_sem_destinatario' then continue; end if;
    v_testados := v_testados + 1;
    select public.fabio_claim_aviso_comercial((a->>'registro_id')::uuid) into v_out;
    if (v_out->>'claimed')::boolean is not true then
      v_falhas := v_falhas + 1;
    end if;
  end loop;
  insert into _res values ('a fila nao lista nada que o claim recuse', '0', v_falhas::text);
  insert into _res values ('e a comparacao rodou sobre linha de verdade', 'sim',
    case when v_testados > 0 then 'sim' else 'NAO — o laco rodou vazio, nao provou nada' end);
end $$;

-- ── O conteudo so sai pra quem esta com o lease ───────────────────────────
create temp table _envio(quem text, j jsonb) on commit drop;

do $$
declare v_claim jsonb; v_reg uuid;
begin
  select registro_id into v_reg from _ids where quem='com_contato';
  -- devolve pra fila e reivindica de novo, pra ter o token na mao
  update fabio_notificacoes set lease_expira_em = now() - interval '1 minute'
   where referencia_tipo='lead_experimental_registro' and referencia_id = v_reg::text;
  select public.fabio_claim_aviso_comercial(v_reg) into v_claim;

  insert into _envio values ('com_token', public.fabio_aviso_comercial_para_envio(
    (v_claim->>'notificacao_id')::uuid, (v_claim->>'lease_token')::uuid));
  insert into _envio values ('token_errado', public.fabio_aviso_comercial_para_envio(
    (v_claim->>'notificacao_id')::uuid, '00000000-0000-4000-8000-000000000999'::uuid));
end $$;

insert into _res select 'com o lease na mao, o worker le o aviso', 'true',
  (select j->>'ok' from _envio where quem='com_token');
insert into _res select 'e recebe o numero do comercial', '5521900000043',
  (select coalesce(j->>'destinatario','(nulo)') from _envio where quem='com_token');
insert into _res select 'e o corpo com a leitura de conversao', 'sim',
  (select case when (j->>'corpo') like '%CONVERSAO QUENTE%' then 'sim' else 'nao' end
     from _envio where quem='com_token');
insert into _res select 'o nome do aluno vai no corpo', 'sim',
  (select case when (j->>'corpo') like '%ZZTESTE Com Contato 043%' then 'sim' else 'nao' end
     from _envio where quem='com_token');

insert into _res select 'com token errado, nao ve conteudo nenhum', 'false',
  (select j->>'ok' from _envio where quem='token_errado');
insert into _res select 'e nem vaza o corpo por engano', 'sem corpo',
  (select case when j ? 'corpo' then 'VAZOU O CORPO' else 'sem corpo' end
     from _envio where quem='token_errado');

-- Linha com lease VIVO nao pode aparecer na fila: outro worker a veria, tentaria
-- reivindicar e levaria recusa. Fila que mostra o que nao da pra fazer e fila
-- que mente — e sem este passo o espelho passava por sorte, porque nenhuma
-- linha da fixture chegava a ter lease vivo na hora da varredura.
insert into _res select 'linha com lease VIVO nao aparece na fila', '0',
  (select count(*)::text from jsonb_array_elements(public.fabio_avisos_comerciais_pendentes(50)) a
     join _ids i on i.registro_id::text = a->>'registro_id'
    where i.quem='com_contato');

-- ── Enviada sai da fila, e nao volta a ser legivel ────────────────────────
do $$
declare v_claim jsonb; v_reg uuid;
begin
  select registro_id into v_reg from _ids where quem='com_contato';
  select jsonb_build_object('id', id, 'tok', lease_token) into v_claim
    from fabio_notificacoes
   where referencia_tipo='lead_experimental_registro' and referencia_id = v_reg::text;
  perform public.fabio_marcar_notificacao_enviada(
    (v_claim->>'id')::uuid, (v_claim->>'tok')::uuid, 'ZZTESTE-recibo');
  -- MESMO token, DEPOIS de entregue. fabio_marcar_notificacao_enviada nao
  -- limpa lease_token nem lease_expira_em (conferido no corpo dela), entao
  -- quem acabou de entregar continua com um token valido na mao. Se a leitura
  -- nao olhar o status, esse worker rele o corpo e entrega de novo — e o
  -- comercial recebe a mesma devolutiva duas vezes.
  insert into _envio values ('depois_de_enviada', public.fabio_aviso_comercial_para_envio(
    (v_claim->>'id')::uuid, (v_claim->>'tok')::uuid));
end $$;

insert into _res select 'entregue nao volta a ser lida, nem com o token certo', 'false',
  (select j->>'ok' from _envio where quem='depois_de_enviada');
insert into _res select 'e o corpo da entregue nao sai de novo', 'sem corpo',
  (select case when j ? 'corpo' then 'VAZOU — reenvio ao comercial' else 'sem corpo' end
     from _envio where quem='depois_de_enviada');

insert into _res select 'aviso enviado sai da fila', '0',
  (select count(*)::text from jsonb_array_elements(public.fabio_avisos_comerciais_pendentes(50)) a
     join _ids i on i.registro_id::text = a->>'registro_id'
    where i.quem='com_contato');

insert into _res select 'e o claim tambem nao o retoma', 'false',
  (select public.fabio_claim_aviso_comercial((select registro_id from _ids where quem='com_contato'))->>'claimed');

-- ── Permissao ─────────────────────────────────────────────────────────────
insert into _res select 'authenticated nao le a fila comercial', 'sem privilegio',
  case when has_function_privilege('authenticated',
         'public.fabio_avisos_comerciais_pendentes(integer)','execute')
       then 'LE — fila interna exposta ao app' else 'sem privilegio' end;
insert into _res select 'authenticated nao le o corpo do aviso', 'sem privilegio',
  case when has_function_privilege('authenticated',
         'public.fabio_aviso_comercial_para_envio(uuid,uuid)','execute')
       then 'LE — leitura de conversao no app' else 'sem privilegio' end;
insert into _res select 'anon nao le a fila comercial', 'sem privilegio',
  case when has_function_privilege('anon',
         'public.fabio_avisos_comerciais_pendentes(integer)','execute')
       then 'LE' else 'sem privilegio' end;

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
