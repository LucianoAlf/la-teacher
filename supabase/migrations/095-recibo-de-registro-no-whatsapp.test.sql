-- 095 — ensaio descartavel do recibo canonico de registro.
--
-- Este arquivo nao abre/fecha transacao: scripts/rodar-teste-sql.mjs e o dono
-- do BEGIN/ROLLBACK. As fixtures usam identificadores de transacao para nunca
-- depender de dados reais.

create temporary table _fabio_095_res (
  caso text,
  ok boolean,
  detalhe text
) on commit drop;

create or replace function pg_temp.checar_095(
  p_caso text,
  p_ok boolean,
  p_detalhe text
) returns void
language plpgsql
as $function$
begin
  insert into _fabio_095_res(caso, ok, detalhe)
  values (p_caso, coalesce(p_ok, false), p_detalhe);
end
$function$;

do $function$
declare
  v_tag text := 'z95_' || txid_current()::text;
  v_unidade_id uuid := gen_random_uuid();
  v_auth_professor uuid := gen_random_uuid();
  v_auth_estranho uuid := gen_random_uuid();
  v_usuario_id integer;
  v_usuario_estranho_id integer;
  v_professor_id integer;
  v_professor_estranho_id integer;
  v_aluno_id integer;
  v_turma_id integer;
  v_individual_id integer;
  v_raiz_id uuid;
  v_fatia_id uuid;
  v_devolutiva_id uuid;
  v_confirmacao jsonb;
  v_claim_legado jsonb;
  v_claim_antes jsonb;
  v_claim jsonb;
  v_claim_replay_saida jsonb;
  v_conclusao jsonb;
  v_conclusao_lease_errado jsonb;
  v_falha_lease_errado jsonb;
  v_conclusao_lease_vencido jsonb;
  v_falha_lease_vencido jsonb;
  v_audio_1 jsonb;
  v_audio_2 jsonb;
  v_agenda jsonb;
  v_edicao jsonb;
  v_estado_antes_lease_errado jsonb;
  v_estado_apos_conclusao_lease_errado jsonb;
  v_estado_apos_falha_lease_errado jsonb;
  v_estado_antes_lease_vencido jsonb;
  v_estado_apos_conclusao_lease_vencido jsonb;
  v_estado_apos_falha_lease_vencido jsonb;
  v_notificacao_id uuid;
  v_lease_token uuid;
  v_recibo text := 'ZZRECIBO095_' || txid_current()::text;
  v_path text := 'teste-095/' || txid_current()::text || '/audio.ogg';
  v_notificacoes_recibo integer := 0;
  v_notificacoes_legado integer := 0;
  v_claim_antes_devolutivas integer := 0;
  v_claim_replay integer := 0;
  v_mensagens_contexto integer := 0;
  v_contexto_apos_conclusao_lease_errado integer := 0;
  v_contexto_apos_falha_lease_errado integer := 0;
  v_contexto_apos_conclusao_lease_vencido integer := 0;
  v_contexto_apos_falha_lease_vencido integer := 0;
  v_agenda_tem_rascunho boolean := false;
  v_edicao_app_autenticada boolean := false;
  v_audio_replay_mesmo_id boolean := false;
  v_recibo_sem_sucesso_silencioso boolean := false;
  v_estranho_bloqueado boolean := false;
  v_legacy_oferta_bloqueada boolean := false;
  v_colisao_legado_coexiste boolean := false;
  v_porta_legada_funciona boolean := false;
  v_def text;
begin
  if to_regprocedure('public.fabio_claim_registro_recibo(integer,integer)') is null
     or to_regprocedure('public.fabio_registro_recibo_dados(integer,uuid)') is null
     or to_regprocedure('public.fabio_concluir_registro_recibo(uuid,uuid,text,text)') is null
     or to_regprocedure('public.fabio_falhar_registro_recibo(uuid,uuid,text)') is null
     or to_regprocedure('public.app_atualizar_devolutiva_rascunho(uuid,text,text,text,text)') is null then
    perform pg_temp.checar_095(
      '095 define as portas do recibo e a porta autenticada do app',
      false,
      'funcoes 095 ausentes'
    );
    return;
  end if;

  perform pg_temp.checar_095(
    'recibo e exclusivo do service_role',
    not has_function_privilege('anon', 'public.fabio_claim_registro_recibo(integer,integer)', 'EXECUTE')
      and not has_function_privilege('authenticated', 'public.fabio_claim_registro_recibo(integer,integer)', 'EXECUTE')
      and has_function_privilege('service_role', 'public.fabio_claim_registro_recibo(integer,integer)', 'EXECUTE')
      and not has_function_privilege('anon', 'public.fabio_concluir_registro_recibo(uuid,uuid,text,text)', 'EXECUTE')
      and not has_function_privilege('authenticated', 'public.fabio_concluir_registro_recibo(uuid,uuid,text,text)', 'EXECUTE')
      and has_function_privilege('service_role', 'public.fabio_concluir_registro_recibo(uuid,uuid,text,text)', 'EXECUTE')
      and not has_function_privilege('anon', 'public.fabio_falhar_registro_recibo(uuid,uuid,text)', 'EXECUTE')
      and not has_function_privilege('authenticated', 'public.fabio_falhar_registro_recibo(uuid,uuid,text)', 'EXECUTE')
    and has_function_privilege('service_role', 'public.fabio_falhar_registro_recibo(uuid,uuid,text)', 'EXECUTE')
      and not has_function_privilege('anon', 'public.fabio_registro_recibo_dados(integer,uuid)', 'EXECUTE')
      and not has_function_privilege('authenticated', 'public.fabio_registro_recibo_dados(integer,uuid)', 'EXECUTE')
      and has_function_privilege('service_role', 'public.fabio_registro_recibo_dados(integer,uuid)', 'EXECUTE'),
    'ACL das portas fabio_* do recibo'
  );

  select pg_get_functiondef('public.app_atualizar_devolutiva_rascunho(uuid,text,text,text,text)'::regprocedure)
    into v_def;
  perform pg_temp.checar_095(
    'wrapper app resolve professor por auth e chama somente o nucleo auditado',
    v_def ilike '%auth.uid()%' and v_def ilike '%fabio_atualizar_devolutiva_rascunho%',
    left(coalesce(v_def, ''), 500)
  );
  perform pg_temp.checar_095(
    'wrapper app e autenticada, nao uma porta fabio do navegador',
    has_function_privilege('authenticated', 'public.app_atualizar_devolutiva_rascunho(uuid,text,text,text,text)', 'EXECUTE')
      and not has_function_privilege('anon', 'public.app_atualizar_devolutiva_rascunho(uuid,text,text,text,text)', 'EXECUTE')
      and not has_function_privilege('authenticated', 'public.fabio_atualizar_devolutiva_rascunho(integer,uuid,text,text,text,text,text)', 'EXECUTE'),
    'ACL do wrapper e do nucleo'
  );

  insert into public.unidades(id, nome, codigo)
  values (v_unidade_id, v_tag || '_unidade', v_tag || '_unidade');

  insert into public.usuarios(nome, email, unidade_id, perfil, auth_user_id, ativo)
  values (v_tag || '_usuario', v_tag || '@example.invalid', v_unidade_id, 'professor', v_auth_professor, true)
  returning id into v_usuario_id;
  insert into public.professores(nome, ativo, usuario_id)
  values (v_tag || '_professor', true, v_usuario_id)
  returning id into v_professor_id;

  insert into public.usuarios(nome, email, unidade_id, perfil, auth_user_id, ativo)
  values (v_tag || '_usuario_estranho', v_tag || '_estranho@example.invalid', v_unidade_id, 'professor', v_auth_estranho, true)
  returning id into v_usuario_estranho_id;
  insert into public.professores(nome, ativo, usuario_id)
  values (v_tag || '_professor_estranho', true, v_usuario_estranho_id)
  returning id into v_professor_estranho_id;

  insert into public.alunos(nome, unidade_id, professor_atual_id)
  values (v_tag || '_aluno', v_unidade_id, v_professor_id)
  returning id into v_aluno_id;

  insert into public.aulas_emusys(
    emusys_id, unidade_id, professor_id, data_aula, data_hora_inicio,
    data_hora_fim, tipo, curso_nome, turma_nome, cancelada
  ) values (
    950000000 + (txid_current() % 100000000)::integer,
    v_unidade_id, v_professor_id, current_date - 1,
    (current_date - 1)::timestamp at time zone 'America/Sao_Paulo',
    ((current_date - 1)::timestamp at time zone 'America/Sao_Paulo') + interval '50 minutes',
    'turma', 'Contrato 095', v_tag || '_turma', false
  ) returning id into v_turma_id;
  insert into public.aulas_emusys(
    emusys_id, unidade_id, professor_id, data_aula, data_hora_inicio,
    data_hora_fim, tipo, curso_nome, turma_nome, cancelada
  ) values (
    960000000 + (txid_current() % 100000000)::integer,
    v_unidade_id, v_professor_id, current_date - 1,
    (current_date - 1)::timestamp at time zone 'America/Sao_Paulo',
    ((current_date - 1)::timestamp at time zone 'America/Sao_Paulo') + interval '50 minutes',
    'individual', 'Contrato 095', v_tag || '_turma', false
  ) returning id into v_individual_id;

  insert into public.aula_alunos_emusys(
    id, aula_emusys_id, unidade_id, aluno_chave, aluno_id, aluno_nome, aluno_nome_normalizado
  ) values
    (-9000000000000000000::bigint + txid_current(), v_turma_id, v_unidade_id,
     v_tag || '_turma_' || v_aluno_id, v_aluno_id, v_tag || '_aluno', v_tag || '_aluno'),
    (-8900000000000000000::bigint + txid_current(), v_individual_id, v_unidade_id,
     v_tag || '_individual_' || v_aluno_id, v_aluno_id, v_tag || '_aluno', v_tag || '_aluno');

  insert into public.fabio_registros_aula(
    aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos,
    texto_consolidado, status, origem
  ) values (
    v_turma_id, v_unidade_id, v_professor_id, null, null, 'C',
    jsonb_build_object('objetivo', 'Ler a partitura', 'atividades', 'Leitura guiada', 'repertorio', 'Tema comum'),
    null, 'aguardando_confirmacao', 'app'
  ) returning id into v_raiz_id;
  insert into public.fabio_registros_aula(
    aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos,
    texto_consolidado, status, origem
  ) values (
    v_turma_id, v_unidade_id, v_professor_id, v_aluno_id, v_raiz_id, 'C',
    jsonb_build_object('progresso', 'Leu quatro sistemas'),
    null, 'aguardando_confirmacao', 'app'
  ) returning id into v_fatia_id;

  -- Uma notificacao legada ja referencia o mesmo registro e canal. O recibo
  -- precisa entrar ao lado dela, nao ser engolido pela chave da 018.
  insert into public.fabio_notificacoes(
    professor_id, tipo, categoria, canal, titulo, corpo, destinatario_tipo,
    status, tentativas, referencia_tipo, referencia_id
  ) values (
    v_professor_id, 'outro', 'informativa', 'whatsapp',
    'Notificacao legada 095', 'Legado que divide a referencia do recibo.', 'professor',
    'enviada', 0, 'registro_aula', v_raiz_id::text
  );
  begin
    v_claim_legado := public.fabio_claim_notificacao_por_referencia(
      v_professor_id, 'outro', 'informativa', 'whatsapp',
      'Tentativa legada 095', 'registro_aula', v_raiz_id::text, 'Legado 095'
    );
    v_porta_legada_funciona := coalesce((v_claim_legado ->> 'ok')::boolean, false)
      and coalesce((v_claim_legado ->> 'claimed')::boolean, true) = false;
  exception when others then
    v_porta_legada_funciona := false;
  end;

  perform set_config('request.jwt.claim.sub', v_auth_professor::text, true);
  select public.app_minha_agenda_sessao(current_date - 1) into v_agenda;
  v_agenda_tem_rascunho := exists (
    select 1
      from jsonb_array_elements(coalesce(v_agenda, '[]'::jsonb)) sessao
     where (sessao ->> 'aula_id_ancora')::integer = v_turma_id
       and coalesce((sessao ->> 'tem_rascunho')::boolean, false)
       and exists (
         select 1 from jsonb_array_elements(coalesce(sessao -> 'alunos', '[]'::jsonb)) aluno
          where (aluno ->> 'aluno_id')::integer = v_aluno_id
            and coalesce((aluno ->> 'tem_rascunho')::boolean, false)
       )
  );

  v_confirmacao := public.fn_confirmar_registro_core(
    v_professor_id, v_auth_professor, v_raiz_id, 'novo'
  );
  select position('recibo_nao_enfileirado' in lower(pg_get_functiondef(
           'public.fn_confirmar_registro_core(integer,uuid,uuid,text)'::regprocedure
         ))) = 0
     and position('fn_enfileirar_registro_recibo' in pg_get_functiondef(
           'public.fn_confirmar_registro_core(integer,uuid,uuid,text)'::regprocedure
         )) > 0
     and position('exception when others' in lower(pg_get_functiondef(
           'public.fn_confirmar_registro_core(integer,uuid,uuid,text)'::regprocedure
         ))) = 0
    into v_recibo_sem_sucesso_silencioso;
  select count(*) into v_notificacoes_recibo
    from public.fabio_notificacoes n
   where n.professor_id = v_professor_id
     and n.tipo = 'registro_recibo'
     and n.referencia_tipo = 'registro_aula'
     and n.referencia_id = v_raiz_id::text
     and n.canal = 'whatsapp';
  select count(*) into v_notificacoes_legado
    from public.fabio_notificacoes n
   where n.professor_id = v_professor_id
     and n.tipo = 'outro'
     and n.referencia_tipo = 'registro_aula'
     and n.referencia_id = v_raiz_id::text
     and n.canal = 'whatsapp';
  v_colisao_legado_coexiste := v_notificacoes_recibo = 1 and v_notificacoes_legado = 1;

  select id into v_devolutiva_id
    from public.fabio_devolutivas
   where registro_fatia_id = v_fatia_id;

  select public.fabio_claim_registro_recibo() into v_claim_antes;
  v_claim_antes_devolutivas := coalesce(jsonb_array_length(v_claim_antes -> 'itens'), 0);

  update public.fabio_devolutivas
     set status = 'gerada',
         texto_normal = 'Texto rascunho 095',
         texto_apoio_casa = 'Apoio em casa 095',
         destinatario = 'responsavel',
         destinatario_nome = 'Familia 095',
         atualizado_em = now()
   where id = v_devolutiva_id;

  v_legacy_oferta_bloqueada := not exists (
    select 1
      from jsonb_array_elements(public.fabio_devolutivas_a_oferecer(500)) grupo,
           jsonb_array_elements(grupo -> 'devolutivas') devolutiva
     where (devolutiva ->> 'id')::uuid = v_devolutiva_id
  );

  v_edicao := public.app_atualizar_devolutiva_rascunho(
    v_devolutiva_id, 'Texto revisado 095', 'Apoio revisado 095', 'ajuste de tom', v_tag || '_acao'
  );
  v_edicao_app_autenticada := v_edicao ->> 'codigo' = 'devolutiva_atualizada'
    and exists (
      select 1 from public.fabio_devolutiva_edicoes e
       where e.devolutiva_id = v_devolutiva_id
         and e.professor_id = v_professor_id
         and e.canal = 'app'
    );

  perform set_config('request.jwt.claim.sub', v_auth_estranho::text, true);
  begin
    perform public.app_atualizar_devolutiva_rascunho(
      v_devolutiva_id, 'Tentativa estranha', 'Tentativa estranha', 'sem posse', v_tag || '_acao_estranha'
    );
  exception when others then
    v_estranho_bloqueado := position('devolutiva_nao_pertence_ao_professor' in sqlerrm) > 0;
  end;
  perform set_config('request.jwt.claim.sub', v_auth_professor::text, true);

  v_audio_1 := public.app_enfileirar_audio(v_turma_id, v_path, 1, null);
  v_audio_2 := public.app_enfileirar_audio(v_turma_id, v_path, 1, null);
  v_audio_replay_mesmo_id := (v_audio_1 ->> 'audio_id') = (v_audio_2 ->> 'audio_id')
    and (select count(*) from public.fabio_fila_audios f
         where f.professor_id = v_professor_id and f.storage_path = v_path) = 1;

  select public.fabio_claim_registro_recibo() into v_claim;
  v_notificacao_id := nullif(v_claim -> 'itens' -> 0 ->> 'notificacao_id', '')::uuid;
  v_lease_token := nullif(v_claim ->> 'lease_token', '')::uuid;
  if v_notificacao_id is not null and v_lease_token is not null then
    select to_jsonb(n) into v_estado_antes_lease_errado
      from public.fabio_notificacoes n where n.id = v_notificacao_id;
    v_conclusao_lease_errado := public.fabio_concluir_registro_recibo(
      v_notificacao_id, gen_random_uuid(), v_recibo || '_lease_errado', 'Recibo invalido'
    );
    select to_jsonb(n) into v_estado_apos_conclusao_lease_errado
      from public.fabio_notificacoes n where n.id = v_notificacao_id;
    select count(*) into v_contexto_apos_conclusao_lease_errado
      from public.fabio_chat_mensagens m
     where m.professor_id = v_professor_id
       and m.wa_message_id = v_recibo || '_lease_errado';

    v_falha_lease_errado := public.fabio_falhar_registro_recibo(
      v_notificacao_id, gen_random_uuid(), 'Falha com lease errado'
    );
    select to_jsonb(n) into v_estado_apos_falha_lease_errado
      from public.fabio_notificacoes n where n.id = v_notificacao_id;
    select count(*) into v_contexto_apos_falha_lease_errado
      from public.fabio_chat_mensagens m
     where m.professor_id = v_professor_id
       and m.wa_message_id = v_recibo || '_lease_errado';

    update public.fabio_notificacoes
       set lease_expira_em = now() - interval '1 second'
     where id = v_notificacao_id;
    select to_jsonb(n) into v_estado_antes_lease_vencido
      from public.fabio_notificacoes n where n.id = v_notificacao_id;
    v_conclusao_lease_vencido := public.fabio_concluir_registro_recibo(
      v_notificacao_id, v_lease_token, v_recibo || '_lease_vencido', 'Recibo vencido'
    );
    select to_jsonb(n) into v_estado_apos_conclusao_lease_vencido
      from public.fabio_notificacoes n where n.id = v_notificacao_id;
    select count(*) into v_contexto_apos_conclusao_lease_vencido
      from public.fabio_chat_mensagens m
     where m.professor_id = v_professor_id
       and m.wa_message_id = v_recibo || '_lease_vencido';

    v_falha_lease_vencido := public.fabio_falhar_registro_recibo(
      v_notificacao_id, v_lease_token, 'Falha com lease vencido'
    );
    select to_jsonb(n) into v_estado_apos_falha_lease_vencido
      from public.fabio_notificacoes n where n.id = v_notificacao_id;
    select count(*) into v_contexto_apos_falha_lease_vencido
      from public.fabio_chat_mensagens m
     where m.professor_id = v_professor_id
       and m.wa_message_id = v_recibo || '_lease_vencido';

    select public.fabio_claim_registro_recibo() into v_claim;
    v_notificacao_id := nullif(v_claim -> 'itens' -> 0 ->> 'notificacao_id', '')::uuid;
    v_lease_token := nullif(v_claim ->> 'lease_token', '')::uuid;
  end if;
  if v_notificacao_id is not null and v_lease_token is not null then
    v_conclusao := public.fabio_concluir_registro_recibo(
      v_notificacao_id, v_lease_token, v_recibo, 'Recibo canonico 095'
    );
  end if;

  select count(*) into v_mensagens_contexto
    from public.fabio_chat_mensagens m
   where m.professor_id = v_professor_id
     and m.role = 'fabio'
     and m.channel = 'whatsapp'
     and m.wa_message_id = v_recibo;

  select public.fabio_claim_registro_recibo() into v_claim_replay_saida;
  v_claim_replay := coalesce(jsonb_array_length(v_claim_replay_saida -> 'itens'), 0);

  perform pg_temp.checar_095(
    'confirmacao deve enfileirar um unico recibo por registro',
    v_notificacoes_recibo = 1,
    jsonb_build_object('confirmacao', v_confirmacao, 'notificacoes', v_notificacoes_recibo)::text
  );
  perform pg_temp.checar_095(
    'recibo deve coexistir com notificacao legada da mesma referencia e canal',
    v_colisao_legado_coexiste,
    jsonb_build_object('recibos', v_notificacoes_recibo, 'legadas', v_notificacoes_legado)::text
  );
  perform pg_temp.checar_095(
    'porta legada por referencia continua usando a chave legada',
    v_porta_legada_funciona,
    coalesce(v_claim_legado::text, '<NULL>')
  );
  perform pg_temp.checar_095(
    'recibo espera todos os rascunhos exigidos',
    v_claim_antes_devolutivas = 0,
    coalesce(v_claim_antes::text, '<NULL>')
  );
  perform pg_temp.checar_095(
    'ofertador legado nao concorre com recibo pendente',
    v_legacy_oferta_bloqueada,
    'devolutiva=' || coalesce(v_devolutiva_id::text, '<NULL>')
  );
  perform pg_temp.checar_095(
    'recibo enviado nao pode ser reivindicado de novo',
    v_claim_replay = 0 and coalesce(v_conclusao ->> 'ok', 'false') = 'true',
    jsonb_build_object('conclusao', v_conclusao, 'replay', v_claim_replay)::text
  );
  perform pg_temp.checar_095(
    'recibo enviado deve espelhar uma unica saida no contexto',
    v_mensagens_contexto = 1,
    'mensagens=' || v_mensagens_contexto::text
  );
  perform pg_temp.checar_095(
    'falha no enqueue do recibo nao pode virar confirmacao silenciosa',
    v_recibo_sem_sucesso_silencioso,
    'fn_confirmar_registro_core nao pode engolir recibo_nao_enfileirado'
  );
  perform pg_temp.checar_095(
    'agenda deve expor rascunho aguardando confirmacao no slot e alvo corretos',
    v_agenda_tem_rascunho,
    coalesce(v_agenda::text, '<NULL>')
  );
  perform pg_temp.checar_095(
    'wrapper app deve resolver professor por auth e auditar a edicao no nucleo',
    v_edicao_app_autenticada and v_estranho_bloqueado,
    jsonb_build_object('edicao', v_edicao, 'estranho_bloqueado', v_estranho_bloqueado)::text
  );
  perform pg_temp.checar_095(
    'replay do mesmo storage_path deve devolver o mesmo audio_id',
    v_audio_replay_mesmo_id,
    jsonb_build_object('primeiro', v_audio_1, 'segundo', v_audio_2)::text
  );
  perform pg_temp.checar_095(
    'concluir com lease errado nao altera notificacao nem contexto',
    coalesce(v_conclusao_lease_errado ->> 'codigo', '') = 'lease_invalido'
      and v_estado_apos_conclusao_lease_errado = v_estado_antes_lease_errado
      and v_contexto_apos_conclusao_lease_errado = 0,
    jsonb_build_object('resultado', v_conclusao_lease_errado, 'contexto', v_contexto_apos_conclusao_lease_errado)::text
  );
  perform pg_temp.checar_095(
    'falhar com lease errado nao altera notificacao nem contexto',
    coalesce(v_falha_lease_errado ->> 'codigo', '') = 'lease_invalido'
      and v_estado_apos_falha_lease_errado = v_estado_antes_lease_errado
      and v_contexto_apos_falha_lease_errado = 0,
    jsonb_build_object('resultado', v_falha_lease_errado, 'contexto', v_contexto_apos_falha_lease_errado)::text
  );
  perform pg_temp.checar_095(
    'concluir com lease vencido nao altera notificacao nem contexto',
    coalesce(v_conclusao_lease_vencido ->> 'codigo', '') = 'lease_invalido'
      and v_estado_apos_conclusao_lease_vencido = v_estado_antes_lease_vencido
      and v_contexto_apos_conclusao_lease_vencido = 0,
    jsonb_build_object('resultado', v_conclusao_lease_vencido, 'contexto', v_contexto_apos_conclusao_lease_vencido)::text
  );
  perform pg_temp.checar_095(
    'falhar com lease vencido nao altera notificacao nem contexto',
    coalesce(v_falha_lease_vencido ->> 'codigo', '') = 'lease_invalido'
      and v_estado_apos_falha_lease_vencido = v_estado_antes_lease_vencido
      and v_contexto_apos_falha_lease_vencido = 0,
    jsonb_build_object('resultado', v_falha_lease_vencido, 'contexto', v_contexto_apos_falha_lease_vencido)::text
  );
end
$function$;

select json_build_object(
  'falhas', (select count(*) from _fabio_095_res where not ok),
  'detalhe', coalesce((select json_agg(json_build_object(
    'passo', caso,
    'esperado', 'true',
    'obtido', detalhe
  ) order by caso) from _fabio_095_res where not ok), '[]'::json)
) as resumo;
