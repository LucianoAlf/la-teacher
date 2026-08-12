-- O trecho executavel remotamente e um contrato de catalogo: nao cria fixtures
-- nem chama portas que escrevem em public. O bloco Docker no fim deste arquivo
-- fica comentado de proposito e o mutante o extrai para um PostgreSQL efemero.

create temporary table pg_temp._fabio_20260812163000_res (
  caso text,
  ok boolean,
  detalhe text
) on commit drop;

create or replace function pg_temp.checar_20260812163000(
  p_caso text,
  p_ok boolean,
  p_detalhe text
) returns void
language plpgsql
as $function$
begin
  insert into pg_temp._fabio_20260812163000_res(caso, ok, detalhe)
  values (p_caso, coalesce(p_ok, false), p_detalhe);
end
$function$;

do $function$
declare
  v_enqueue regprocedure := to_regprocedure(
    'public.fn_enfileirar_registro_recibo(uuid,integer)'
  );
  v_claim regprocedure := to_regprocedure(
    'public.fabio_claim_registro_recibo(integer,integer)'
  );
  v_enqueue_def text;
  v_claim_def text;
  v_enqueue_norm text;
  v_claim_norm text;
  v_enqueue_definer boolean := false;
  v_claim_definer boolean := false;
  v_enqueue_config text := '';
  v_claim_config text := '';
begin
  if v_enqueue is null or v_claim is null then
    perform pg_temp.checar_20260812163000(
      'portas de recibo existem',
      false,
      'fn_enfileirar_registro_recibo ou fabio_claim_registro_recibo ausente'
    );
    return;
  end if;

  select pg_get_functiondef(v_enqueue) into v_enqueue_def;
  select pg_get_functiondef(v_claim) into v_claim_def;
  select
    p.prosecdef,
    coalesce(array_to_string(p.proconfig, E'\n'), '')
    into v_enqueue_definer, v_enqueue_config
    from pg_proc p
   where p.oid = v_enqueue;
  select
    p.prosecdef,
    coalesce(array_to_string(p.proconfig, E'\n'), '')
    into v_claim_definer, v_claim_config
    from pg_proc p
   where p.oid = v_claim;

  v_enqueue_norm := lower(regexp_replace(v_enqueue_def, '[[:space:]]+', ' ', 'g'));
  v_claim_norm := lower(regexp_replace(v_claim_def, '[[:space:]]+', ' ', 'g'));

  perform pg_temp.checar_20260812163000(
    'enqueue do recibo nao e executavel por papeis de API',
    not has_function_privilege(
      'anon', 'public.fn_enfileirar_registro_recibo(uuid,integer)', 'EXECUTE'
    )
      and not has_function_privilege(
        'authenticated', 'public.fn_enfileirar_registro_recibo(uuid,integer)', 'EXECUTE'
      )
      and not has_function_privilege(
        'service_role', 'public.fn_enfileirar_registro_recibo(uuid,integer)', 'EXECUTE'
      ),
    'anon=' || has_function_privilege(
      'anon', 'public.fn_enfileirar_registro_recibo(uuid,integer)', 'EXECUTE'
    )::text
      || ', authenticated=' || has_function_privilege(
        'authenticated', 'public.fn_enfileirar_registro_recibo(uuid,integer)', 'EXECUTE'
      )::text
      || ', service_role=' || has_function_privilege(
        'service_role', 'public.fn_enfileirar_registro_recibo(uuid,integer)', 'EXECUTE'
      )::text
  );

  perform pg_temp.checar_20260812163000(
    'claim do recibo e exclusivo do service_role',
    not has_function_privilege(
      'anon', 'public.fabio_claim_registro_recibo(integer,integer)', 'EXECUTE'
    )
      and not has_function_privilege(
        'authenticated', 'public.fabio_claim_registro_recibo(integer,integer)', 'EXECUTE'
      )
      and has_function_privilege(
        'service_role', 'public.fabio_claim_registro_recibo(integer,integer)', 'EXECUTE'
      ),
    'anon=' || has_function_privilege(
      'anon', 'public.fabio_claim_registro_recibo(integer,integer)', 'EXECUTE'
    )::text
      || ', authenticated=' || has_function_privilege(
        'authenticated', 'public.fabio_claim_registro_recibo(integer,integer)', 'EXECUTE'
      )::text
      || ', service_role=' || has_function_privilege(
        'service_role', 'public.fabio_claim_registro_recibo(integer,integer)', 'EXECUTE'
      )::text
  );

  perform pg_temp.checar_20260812163000(
    'as duas portas internas usam SECURITY DEFINER com search_path explicito',
    v_enqueue_definer
      and v_claim_definer
      and position('search_path=pg_catalog, public' in v_enqueue_config) > 0
      and position('search_path=pg_catalog, public' in v_claim_config) > 0,
    jsonb_build_object(
      'enqueue_definer', v_enqueue_definer,
      'enqueue_config', v_enqueue_config,
      'claim_definer', v_claim_definer,
      'claim_config', v_claim_config
    )::text
  );

  perform pg_temp.checar_20260812163000(
    'origem app e NULL ficam fora do WhatsApp pela mesma guarda null-safe',
    position('if v_registro.origem is distinct from ''whatsapp'' then' in v_enqueue_norm) > 0
      and position('when v_registro.origem = ''app'' then ''origem_app''' in v_enqueue_norm) > 0
      and position('else ''origem_nao_whatsapp''' in v_enqueue_norm) > 0
      and ('app'::text is distinct from 'whatsapp')
      and (null::text is distinct from 'whatsapp'),
    jsonb_build_object(
      'definicao_tem_is_distinct_from',
        position('if v_registro.origem is distinct from ''whatsapp'' then' in v_enqueue_norm) > 0,
      'app_bloqueada', 'app'::text is distinct from 'whatsapp',
      'null_bloqueada', null::text is distinct from 'whatsapp'
    )::text
  );

  perform pg_temp.checar_20260812163000(
    'somente WhatsApp confirmado e elegivel e o enqueue e idempotente',
    position(
      'if v_registro.confirmado_em is null or v_registro.status not in (''gravado_emusys'', ''confirmado'') then'
      in v_enqueue_norm
    ) > 0
      and position('insert into public.fabio_notificacoes(' in v_enqueue_norm) > 0
      and position(
        'on conflict (professor_id, tipo, referencia_tipo, referencia_id, canal) where tipo = ''registro_recibo'' and referencia_tipo = ''registro_aula'' and canal = ''whatsapp'' do nothing returning id into v_notificacao_id;'
        in v_enqueue_norm
      ) > 0
      and position('''ja_enfileirado'', v_notificacao_id is null' in v_enqueue_norm) > 0,
    jsonb_build_object(
      'elegibilidade', position(
        'if v_registro.confirmado_em is null or v_registro.status not in (''gravado_emusys'', ''confirmado'') then'
        in v_enqueue_norm
      ) > 0,
      'on_conflict_do_nothing', position(
        'on conflict (professor_id, tipo, referencia_tipo, referencia_id, canal) where tipo = ''registro_recibo'' and referencia_tipo = ''registro_aula'' and canal = ''whatsapp'' do nothing returning id into v_notificacao_id;'
        in v_enqueue_norm
      ) > 0
    )::text
  );

  perform pg_temp.checar_20260812163000(
    'claim aceita somente raiz WhatsApp confirmada e preserva a cerca de devolutivas',
    position('and raiz.origem = ''whatsapp''' in v_claim_norm) > 0
      and position('and raiz.confirmado_em is not null' in v_claim_norm) > 0
      and position('and raiz.status in (''gravado_emusys'', ''confirmado'')' in v_claim_norm) > 0
      and position('and not exists (' in v_claim_norm) > 0
      and position('and public.fn_presenca_declarada(alvo.campos) = ''presente''' in v_claim_norm) > 0
      and position('and (d.id is null or d.status not in (''gerada'', ''oferecida''))' in v_claim_norm) > 0
      and position('for update of n skip locked' in v_claim_norm) > 0,
    jsonb_build_object(
      'origem_whatsapp', position('and raiz.origem = ''whatsapp''' in v_claim_norm) > 0,
      'devolutivas', position('and not exists (' in v_claim_norm) > 0,
      'skip_locked', position('for update of n skip locked' in v_claim_norm) > 0
    )::text
  );
end
$function$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._fabio_20260812163000_res where not ok),
  'detalhe', coalesce((
    select json_agg(json_build_object(
      'passo', caso,
      'esperado', 'true',
      'obtido', detalhe
    ) order by caso)
      from pg_temp._fabio_20260812163000_res
     where not ok
  ), '[]'::json)
) as resumo;

/* 20260812163000-DOCKER-DML-TESTS-INICIO
do $docker$
declare
  v_unidade uuid := '00000000-0000-0000-0000-000000000001';
  v_professor integer := 701;
  v_aula integer := 1701;
  v_audio_app uuid := '00000000-0000-0000-0000-000000000101';
  v_raiz_app uuid;
  v_registro_sem_audio uuid;
  v_raiz_whatsapp uuid := '00000000-0000-0000-0000-000000000201';
  v_fatia_whatsapp uuid := '00000000-0000-0000-0000-000000000202';
  v_raiz_whatsapp_bloqueada uuid := '00000000-0000-0000-0000-000000000211';
  v_fatia_whatsapp_bloqueada uuid := '00000000-0000-0000-0000-000000000212';
  v_raiz_app_historica uuid := '00000000-0000-0000-0000-000000000221';
  v_raiz_origem_nula uuid := '00000000-0000-0000-0000-000000000231';
  v_criado jsonb;
  v_recibo jsonb;
  v_recibo_repetido jsonb;
  v_recibo_nulo jsonb;
  v_claim jsonb;
  v_notificacoes_app integer;
  v_origens_app_validas boolean;
  v_raiz_sem_audio_app boolean;
  v_so_um_recibo_whatsapp boolean;
  v_claim_so_whatsapp boolean;
  v_app_historica_sem_lease boolean;
begin
  insert into public.aulas_emusys (id, professor_id, unidade_id, cancelada)
  values (v_aula, v_professor, v_unidade, false);
  insert into public.aula_alunos_emusys (aula_emusys_id, aluno_id)
  values (v_aula, 17001);
  insert into public.fabio_fila_audios (
    id, professor_id, aula_id, unidade_id, origem, status, erro_tipo
  ) values (
    v_audio_app, v_professor, v_aula, v_unidade, 'app', 'transcrito', 'transitorio'
  );

  v_criado := public.fabio_criar_registro(jsonb_build_object(
    'aula_id', v_aula,
    'professor_id', v_professor,
    'audio_id', v_audio_app::text,
    'origem', 'whatsapp',
    'tronco', jsonb_build_object('campos', jsonb_build_object('tema', 'forjado')),
    'fatias', jsonb_build_array(jsonb_build_object(
      'aluno_id', 17001,
      'campos', jsonb_build_object('presenca', 'presente')
    ))
  ));
  v_raiz_app := (v_criado ->> 'registro_id')::uuid;

  select bool_and(r.origem = 'app')
    into v_origens_app_validas
    from public.fabio_registros_aula r
   where r.audio_id = v_audio_app;
  perform pg_temp.checar_20260812163000(
    'fila app vence payload whatsapp na raiz e na fatia',
    coalesce(v_origens_app_validas, false)
      and (select count(*) = 2 from public.fabio_registros_aula where audio_id = v_audio_app)
      and (select status = 'normalizado' from public.fabio_fila_audios where id = v_audio_app),
    jsonb_build_object(
      'origens', coalesce((
        select jsonb_agg(origem order by parent_id nulls first)
          from public.fabio_registros_aula where audio_id = v_audio_app
      ), '[]'::jsonb),
      'fila_status', (select status from public.fabio_fila_audios where id = v_audio_app)
    )::text
  );

  update public.fabio_registros_aula
     set status = 'gravado_emusys', confirmado_em = now()
   where id = v_raiz_app;
  select public.fn_enfileirar_registro_recibo(v_raiz_app, v_professor)
    into v_recibo;
  select count(*) into v_notificacoes_app
    from public.fabio_notificacoes
   where referencia_id = v_raiz_app::text;
  perform pg_temp.checar_20260812163000(
    'registro normalizado da fila app bloqueia recibo WhatsApp',
    coalesce((v_recibo ->> 'skipped')::boolean, false)
      and v_recibo ->> 'motivo' = 'origem_app'
      and v_notificacoes_app = 0,
    coalesce(v_recibo, '{}'::jsonb)::text
  );

  v_criado := public.fabio_criar_registro(jsonb_build_object(
    'aula_id', v_aula,
    'professor_id', v_professor,
    'origem', 'whatsapp',
    'tronco', jsonb_build_object('campos', '{}'::jsonb)
  ));
  v_registro_sem_audio := (v_criado ->> 'registro_id')::uuid;
  select origem = 'app' into v_raiz_sem_audio_app
    from public.fabio_registros_aula
   where id = v_registro_sem_audio;
  perform pg_temp.checar_20260812163000(
    'sem audio a origem segura permanece app',
    coalesce(v_raiz_sem_audio_app, false),
    coalesce((select origem from public.fabio_registros_aula where id = v_registro_sem_audio), 'NULL')
  );

  insert into public.fabio_registros_aula (
    id, aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos,
    texto_consolidado, status, origem, confirmado_em
  ) values
    (v_raiz_whatsapp, v_aula, v_unidade, v_professor, null, null, 'C', '{}'::jsonb,
     '', 'gravado_emusys', 'whatsapp', now()),
    (v_fatia_whatsapp, v_aula, v_unidade, v_professor, 17001, v_raiz_whatsapp, 'C',
     jsonb_build_object('presenca', 'presente'), '', 'gravado_emusys', 'whatsapp', now()),
    (v_raiz_whatsapp_bloqueada, v_aula, v_unidade, v_professor, null, null, 'C', '{}'::jsonb,
     '', 'gravado_emusys', 'whatsapp', now()),
    (v_fatia_whatsapp_bloqueada, v_aula, v_unidade, v_professor, 17001,
     v_raiz_whatsapp_bloqueada, 'C', jsonb_build_object('presenca', 'presente'), '',
     'gravado_emusys', 'whatsapp', now()),
    (v_raiz_app_historica, v_aula, v_unidade, v_professor, null, null, 'C', '{}'::jsonb,
     '', 'gravado_emusys', 'app', now()),
    (v_raiz_origem_nula, v_aula, v_unidade, v_professor, null, null, 'C', '{}'::jsonb,
     '', 'gravado_emusys', null, now());
  insert into public.fabio_devolutivas (registro_fatia_id, status)
  values (v_fatia_whatsapp, 'gerada');

  select public.fn_enfileirar_registro_recibo(v_raiz_whatsapp, v_professor)
    into v_recibo;
  select public.fn_enfileirar_registro_recibo(v_raiz_whatsapp, v_professor)
    into v_recibo_repetido;
  select public.fn_enfileirar_registro_recibo(v_raiz_origem_nula, v_professor)
    into v_recibo_nulo;
  insert into public.fabio_notificacoes (
    professor_id, tipo, categoria, canal, titulo, corpo, destinatario_tipo,
    status, tentativas, lease_expira_em, referencia_tipo, referencia_id
  ) values
    (v_professor, 'registro_recibo', 'informativa', 'whatsapp', 'historico app', '',
     'professor', 'processando', 0, now() - interval '1 minute', 'registro_aula',
     v_raiz_app_historica::text),
    (v_professor, 'registro_recibo', 'informativa', 'whatsapp', 'aguarda devolutiva', '',
     'professor', 'processando', 0, now() - interval '1 minute', 'registro_aula',
     v_raiz_whatsapp_bloqueada::text);

  select count(*) = 1 into v_so_um_recibo_whatsapp
    from public.fabio_notificacoes
   where professor_id = v_professor
     and referencia_id = v_raiz_whatsapp::text
     and tipo = 'registro_recibo'
     and canal = 'whatsapp';
  perform pg_temp.checar_20260812163000(
    'WhatsApp confirmado cria um unico recibo e NULL bloqueia',
    coalesce(v_recibo ->> 'notificacao_id', '') <> ''
      and coalesce((v_recibo_repetido ->> 'ja_enfileirado')::boolean, false)
      and coalesce((v_recibo_nulo ->> 'skipped')::boolean, false)
      and v_recibo_nulo ->> 'motivo' = 'origem_nao_whatsapp'
      and coalesce(v_so_um_recibo_whatsapp, false),
    jsonb_build_object(
      'primeiro', v_recibo,
      'repetido', v_recibo_repetido,
      'origem_nula', v_recibo_nulo,
      'qtd_whatsapp', (select count(*) from public.fabio_notificacoes
        where referencia_id = v_raiz_whatsapp::text and tipo = 'registro_recibo')
    )::text
  );

  select public.fabio_claim_registro_recibo(20, v_professor) into v_claim;
  select jsonb_array_length(coalesce(v_claim -> 'itens', '[]'::jsonb)) = 1
      and v_claim -> 'itens' -> 0 ->> 'registro_id' = v_raiz_whatsapp::text
    into v_claim_so_whatsapp;
  select status = 'processando' and lease_token is null
    into v_app_historica_sem_lease
    from public.fabio_notificacoes
   where referencia_id = v_raiz_app_historica::text;
  perform pg_temp.checar_20260812163000(
    'claim pega somente WhatsApp pronto e ignora app historico',
    coalesce(v_claim_so_whatsapp, false)
      and coalesce(v_app_historica_sem_lease, false)
      and (select lease_token is null from public.fabio_notificacoes
             where referencia_id = v_raiz_whatsapp_bloqueada::text),
    jsonb_build_object(
      'claim', v_claim,
      'app_historica', (select jsonb_build_object('status', status, 'lease_token', lease_token)
        from public.fabio_notificacoes where referencia_id = v_raiz_app_historica::text),
      'whatsapp_bloqueado', (select jsonb_build_object('status', status, 'lease_token', lease_token)
        from public.fabio_notificacoes where referencia_id = v_raiz_whatsapp_bloqueada::text)
    )::text
  );
end
$docker$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._fabio_20260812163000_res where not ok),
  'detalhe', coalesce((
    select json_agg(json_build_object(
      'passo', caso,
      'esperado', 'true',
      'obtido', detalhe
    ) order by caso)
      from pg_temp._fabio_20260812163000_res
     where not ok
  ), '[]'::json)
) as resumo;
20260812163000-DOCKER-DML-TESTS-FIM */
