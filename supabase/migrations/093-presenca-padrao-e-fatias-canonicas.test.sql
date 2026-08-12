-- Contrato RED/GREEN da 093. O runner é o dono de BEGIN/ROLLBACK e verifica,
-- em conexão separada, que o ensaio não deixa linhas ou esquema alterados.

create temporary table _fabio_093_res(
  caso text,
  ok boolean,
  detalhe text
) on commit drop;

create or replace function pg_temp.checar_093(
  p_caso text,
  p_ok boolean,
  p_detalhe text
) returns void
language plpgsql
as $function$
begin
  insert into _fabio_093_res values (p_caso, coalesce(p_ok, false), p_detalhe);
end
$function$;

do $function$
declare
  v_professor_id integer;
  v_professor_estranho_id integer;
  v_usuario_id integer;
  v_unidade_id uuid;
  v_unidade_estranha_id uuid;
  v_auth_user_id uuid;
  v_aluno_a integer;
  v_aluno_b integer;
  v_tag text := 'z93' || (txid_current() % 100000000)::text;
  v_turma_nome_app text := 'ZZTESTE093_APP_' || txid_current()::text;
  v_emusys_base integer := 800000000 + (txid_current() % 100000000)::integer;
  v_roster_base bigint := -9000000000000000000::bigint + txid_current() * 10;
  v_inicio timestamptz := date_trunc('hour', now()) - interval '1 day' + interval '9 minutes';
  v_turma_app integer;
  v_individual_app_a integer;
  v_individual_app_b integer;
  v_turma_wa integer;
  v_individual_wa_a integer;
  v_individual_wa_b integer;
  v_turma_estranha integer;
  v_fatia_fora_da_sessao integer;
  v_raiz_app uuid;
  v_fatia_app_a uuid;
  v_fatia_app_b uuid;
  v_raiz_wa uuid;
  v_fatia_wa_a uuid;
  v_fatia_wa_b uuid;
  v_campos_tronco jsonb := jsonb_build_object(
    'objetivo', 'Consolidar leitura musical',
    'atividades', 'Leitura e execução guiada',
    'repertorio', 'Tema comum',
    'dever_casa', 'Praticar a leitura',
    'observacoes', 'Ritmo estável'
  );
  v_dedup jsonb;
  v_app jsonb;
  v_wa jsonb;
  v_criado jsonb;
  v_raiz_criada uuid;
  v_historico jsonb;
  v_def_app text;
  v_def_wa text;
  v_presencas_antes integer;
  v_inseguro jsonb;
  v_audio_valido uuid;
  v_audio_estranho uuid;
begin
  if to_regprocedure('public.fn_materializar_presenca_padrao(uuid,integer)') is null
     or to_regprocedure('public.fn_remover_campos_comuns_da_fatia(jsonb,jsonb)') is null then
    perform pg_temp.checar_093(
      '093 define as duas funcoes internas canonicas',
      false,
      'fn_materializar_presenca_padrao/fn_remover_campos_comuns_da_fatia ausentes'
    );
    return;
  end if;

  perform pg_temp.checar_093(
    'ausente e a ausencia explicita canonica do contrato vivo',
    public.fn_presenca_declarada(jsonb_build_object('presenca', 'ausente')) = 'ausente'
      and public.fn_presenca_declarada(jsonb_build_object('presenca', 'faltou')) = 'nao_informada',
    'ausente deve ser aceito; faltou nao e uma grafia persistivel'
  );

  perform pg_temp.checar_093(
    'funcoes internas nao sao executaveis por papeis da API',
    not has_function_privilege('anon', 'public.fn_materializar_presenca_padrao(uuid,integer)', 'EXECUTE')
      and not has_function_privilege('authenticated', 'public.fn_materializar_presenca_padrao(uuid,integer)', 'EXECUTE')
      and not has_function_privilege('service_role', 'public.fn_materializar_presenca_padrao(uuid,integer)', 'EXECUTE')
      and not has_function_privilege('anon', 'public.fn_remover_campos_comuns_da_fatia(jsonb,jsonb)', 'EXECUTE')
      and not has_function_privilege('authenticated', 'public.fn_remover_campos_comuns_da_fatia(jsonb,jsonb)', 'EXECUTE')
      and not has_function_privilege('service_role', 'public.fn_remover_campos_comuns_da_fatia(jsonb,jsonb)', 'EXECUTE'),
    'ACL das duas funcoes internas'
  );
  perform pg_temp.checar_093(
    'criador do registro e exclusivo do service_role',
    not has_function_privilege('anon', 'public.fabio_criar_registro(jsonb)', 'EXECUTE')
      and not has_function_privilege('authenticated', 'public.fabio_criar_registro(jsonb)', 'EXECUTE')
      and has_function_privilege('service_role', 'public.fabio_criar_registro(jsonb)', 'EXECUTE'),
    'ACL fabio_criar_registro'
  );

  v_dedup := public.fn_remover_campos_comuns_da_fatia(
    v_campos_tronco,
    jsonb_build_object(
      'objetivo', '  CONSOLIDAR LEITURA MUSICAL  ',
      'atividades', 'Execução individual',
      'repertorio', ' tema comum ',
      'dever_casa', '   ',
      'observacoes', 'RITMO ESTÁVEL',
      'presenca', 'ausente'
    )
  );
  perform pg_temp.checar_093(
    'dedupe compara campos pedagogicos por lower e btrim sem apagar ausencia',
    v_dedup = jsonb_build_object('atividades', 'Execução individual', 'presenca', 'ausente'),
    coalesce(v_dedup::text, '<NULL>')
  );

  -- Todo o cenário abaixo nasce nesta transação; o teste não lê professor,
  -- aluno, turma nem unidade de produção para formar as fixtures.
  v_unidade_id := gen_random_uuid();
  v_unidade_estranha_id := gen_random_uuid();
  v_auth_user_id := gen_random_uuid();
  insert into public.unidades(id, nome, codigo)
  values (v_unidade_id, v_tag || '_unidade', v_tag || '_unidade');
  insert into public.unidades(id, nome, codigo)
  values (v_unidade_estranha_id, v_tag || '_outra', v_tag || '_outra');
  insert into public.usuarios(nome, email, unidade_id, perfil, auth_user_id, ativo)
  values (v_tag || '_usuario', lower(v_tag) || '@example.invalid', v_unidade_id, 'professor', v_auth_user_id, true)
  returning id into v_usuario_id;
  insert into public.professores(nome, ativo, usuario_id)
  values (v_tag || '_professor', true, v_usuario_id)
  returning id into v_professor_id;
  insert into public.professores(nome, ativo)
  values (v_tag || '_estranho', true)
  returning id into v_professor_estranho_id;
  insert into public.alunos(nome, unidade_id, professor_atual_id)
  values (v_tag || '_aluno_a', v_unidade_id, v_professor_id)
  returning id into v_aluno_a;
  insert into public.alunos(nome, unidade_id, professor_atual_id)
  values (v_tag || '_aluno_b', v_unidade_id, v_professor_id)
  returning id into v_aluno_b;

  insert into public.aulas_emusys(
    emusys_id, unidade_id, professor_id, data_aula, data_hora_inicio,
    data_hora_fim, tipo, curso_nome, turma_nome, cancelada
  ) values (
    v_emusys_base + 1, v_unidade_id, v_professor_id, v_inicio::date, v_inicio,
    v_inicio + interval '50 minutes', 'turma', 'Contrato 093', v_turma_nome_app, false
  ) returning id into v_turma_app;
  insert into public.aulas_emusys(emusys_id, unidade_id, professor_id, data_aula, data_hora_inicio, data_hora_fim, tipo, curso_nome, turma_nome, cancelada)
  values (v_emusys_base + 2, v_unidade_id, v_professor_id, v_inicio::date, v_inicio, v_inicio + interval '50 minutes', 'individual', 'Contrato 093', v_turma_nome_app, false)
  returning id into v_individual_app_a;
  insert into public.aulas_emusys(emusys_id, unidade_id, professor_id, data_aula, data_hora_inicio, data_hora_fim, tipo, curso_nome, turma_nome, cancelada)
  values (v_emusys_base + 3, v_unidade_id, v_professor_id, v_inicio::date, v_inicio, v_inicio + interval '50 minutes', 'individual', 'Contrato 093', v_turma_nome_app, false)
  returning id into v_individual_app_b;
  insert into public.aulas_emusys(emusys_id, unidade_id, professor_id, data_aula, data_hora_inicio, data_hora_fim, tipo, curso_nome, turma_nome, cancelada)
  values (v_emusys_base + 4, v_unidade_id, v_professor_id, (v_inicio + interval '1 hour')::date, v_inicio + interval '1 hour', v_inicio + interval '1 hour 50 minutes', 'turma', 'Contrato 093', v_tag || '_wa', false)
  returning id into v_turma_wa;
  insert into public.aulas_emusys(emusys_id, unidade_id, professor_id, data_aula, data_hora_inicio, data_hora_fim, tipo, curso_nome, turma_nome, cancelada)
  values (v_emusys_base + 5, v_unidade_id, v_professor_id, (v_inicio + interval '1 hour')::date, v_inicio + interval '1 hour', v_inicio + interval '1 hour 50 minutes', 'individual', 'Contrato 093', v_tag || '_wa', false)
  returning id into v_individual_wa_a;
  insert into public.aulas_emusys(emusys_id, unidade_id, professor_id, data_aula, data_hora_inicio, data_hora_fim, tipo, curso_nome, turma_nome, cancelada)
  values (v_emusys_base + 6, v_unidade_id, v_professor_id, (v_inicio + interval '1 hour')::date, v_inicio + interval '1 hour', v_inicio + interval '1 hour 50 minutes', 'individual', 'Contrato 093', v_tag || '_wa', false)
  returning id into v_individual_wa_b;
  insert into public.aulas_emusys(emusys_id, unidade_id, professor_id, data_aula, data_hora_inicio, data_hora_fim, tipo, curso_nome, turma_nome, cancelada)
  values (v_emusys_base + 7, v_unidade_estranha_id, v_professor_estranho_id, (v_inicio + interval '2 hours')::date, v_inicio + interval '2 hours', v_inicio + interval '2 hours 50 minutes', 'turma', 'Contrato 093', v_tag || '_estranha', false)
  returning id into v_turma_estranha;
  insert into public.aulas_emusys(emusys_id, unidade_id, professor_id, data_aula, data_hora_inicio, data_hora_fim, tipo, curso_nome, turma_nome, cancelada)
  values (v_emusys_base + 8, v_unidade_id, v_professor_id, (v_inicio + interval '3 hours')::date, v_inicio + interval '3 hours', v_inicio + interval '3 hours 50 minutes', 'individual', 'Contrato 093', v_tag || '_fora', false)
  returning id into v_fatia_fora_da_sessao;

  insert into public.aula_alunos_emusys(
    id, aula_emusys_id, unidade_id, aluno_chave, aluno_id, aluno_nome, aluno_nome_normalizado
  )
  select v_roster_base + row_number() over (), x.aula_id, v_unidade_id,
         v_tag || '_' || x.aula_id || '_' || x.aluno_id, x.aluno_id,
         case when x.aluno_id = v_aluno_a then v_tag || '_aluno_a' else v_tag || '_aluno_b' end,
         v_tag || '_aluno'
    from (values
      (v_turma_app, v_aluno_a), (v_turma_app, v_aluno_b),
      (v_individual_app_a, v_aluno_a), (v_individual_app_b, v_aluno_b),
      (v_turma_wa, v_aluno_a), (v_turma_wa, v_aluno_b),
      (v_individual_wa_a, v_aluno_a), (v_individual_wa_b, v_aluno_b),
      (v_fatia_fora_da_sessao, v_aluno_a)
    ) as x(aula_id, aluno_id);

  insert into public.fabio_fila_audios(
    professor_id, unidade_id, aula_id, storage_path, status, origem
  ) values (
    v_professor_id, v_unidade_id, v_turma_app,
    'teste-093/' || v_tag || '/valido.m4a', 'transcrito', 'app'
  ) returning id into v_audio_valido;
  insert into public.fabio_fila_audios(
    professor_id, unidade_id, aula_id, storage_path, status, origem
  ) values (
    v_professor_estranho_id, v_unidade_estranha_id, v_turma_estranha,
    'teste-093/' || v_tag || '/estranho.m4a', 'transcrito', 'whatsapp'
  ) returning id into v_audio_estranho;

  begin
    v_inseguro := public.fabio_criar_registro(jsonb_build_object(
      'aula_id', v_turma_estranha, 'professor_id', v_professor_id,
      'molde', 'C', 'origem', 'whatsapp', 'tronco', jsonb_build_object('campos', v_campos_tronco), 'fatias', '[]'::jsonb
    ));
    delete from public.fabio_registros_aula where id = (v_inseguro ->> 'registro_id')::uuid;
    perform pg_temp.checar_093('criador recusa ancora de outro professor', false, coalesce(v_inseguro::text, '<NULL>'));
  exception when others then
    perform pg_temp.checar_093('criador recusa ancora de outro professor', position('aula_nao_pertence_ao_professor' in sqlerrm) > 0, sqlerrm);
  end;
  begin
    v_inseguro := public.fabio_criar_registro(jsonb_build_object(
      'aula_id', v_turma_app, 'professor_id', v_professor_id,
      'molde', 'C', 'origem', 'whatsapp', 'tronco', jsonb_build_object('campos', v_campos_tronco),
      'fatias', jsonb_build_array(jsonb_build_object('aula_id', v_turma_estranha, 'aluno_id', v_aluno_a, 'campos', '{}'::jsonb))
    ));
    delete from public.fabio_registros_aula where id = (v_inseguro ->> 'registro_id')::uuid;
    perform pg_temp.checar_093('criador recusa fatia de outro professor', false, coalesce(v_inseguro::text, '<NULL>'));
  exception when others then
    perform pg_temp.checar_093('criador recusa fatia de outro professor', position('fatia_aula_nao_pertence_ao_professor' in sqlerrm) > 0, sqlerrm);
  end;
  begin
    v_inseguro := public.fabio_criar_registro(jsonb_build_object(
      'aula_id', v_turma_app, 'professor_id', v_professor_id,
      'molde', 'C', 'origem', 'whatsapp', 'tronco', jsonb_build_object('campos', v_campos_tronco),
      'fatias', jsonb_build_array(jsonb_build_object('aula_id', v_fatia_fora_da_sessao, 'aluno_id', v_aluno_a, 'campos', '{}'::jsonb))
    ));
    delete from public.fabio_registros_aula where id = (v_inseguro ->> 'registro_id')::uuid;
    perform pg_temp.checar_093('criador recusa fatia fora da sessao', false, coalesce(v_inseguro::text, '<NULL>'));
  exception when others then
    perform pg_temp.checar_093('criador recusa fatia fora da sessao', position('fatia_aula_fora_da_sessao' in sqlerrm) > 0, sqlerrm);
  end;
  begin
    v_inseguro := public.fabio_criar_registro(jsonb_build_object(
      'aula_id', v_turma_app, 'professor_id', v_professor_id,
      'audio_id', v_audio_estranho, 'molde', 'C', 'origem', 'whatsapp',
      'tronco', jsonb_build_object('campos', v_campos_tronco), 'fatias', '[]'::jsonb
    ));
    delete from public.fabio_registros_aula where id = (v_inseguro ->> 'registro_id')::uuid;
    update public.fabio_fila_audios set status = 'transcrito' where id = v_audio_estranho;
    perform pg_temp.checar_093('criador recusa audio de outro professor aula e unidade', false, coalesce(v_inseguro::text, '<NULL>'));
  exception when others then
    perform pg_temp.checar_093(
      'criador recusa audio de outro professor aula e unidade',
      position('audio_id_invalido' in sqlerrm) > 0
        and not exists (select 1 from public.fabio_registros_aula where audio_id = v_audio_estranho)
        and (select status from public.fabio_fila_audios where id = v_audio_estranho) = 'transcrito',
      sqlerrm
    );
  end;

  insert into public.aluno_presenca(
    aluno_id, professor_id, unidade_id, data_aula, aula_emusys_id,
    status, status_presenca, respondido_por
  ) values (
    v_aluno_a, v_professor_id, v_unidade_id, v_inicio::date, v_individual_app_a,
    'ausente', 'falta', 'manual'
  );

  insert into public.fabio_registros_aula(
    aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos,
    texto_consolidado, status, origem
  ) values (
    v_turma_app, v_unidade_id, v_professor_id, null, null, 'C', v_campos_tronco,
    null, 'aguardando_confirmacao', 'app'
  ) returning id into v_raiz_app;
  insert into public.fabio_registros_aula(
    aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos,
    texto_consolidado, status, origem
  ) values (
    v_turma_app, v_unidade_id, v_professor_id, v_aluno_a, v_raiz_app, 'C',
    '{}'::jsonb, null, 'aguardando_confirmacao', 'app'
  )
  returning id into v_fatia_app_a;
  insert into public.fabio_registros_aula(
    aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos,
    texto_consolidado, status, origem
  ) values (
    v_turma_app, v_unidade_id, v_professor_id, v_aluno_b, v_raiz_app, 'C',
    jsonb_build_object('presenca', 'ausente'), null, 'aguardando_confirmacao', 'app'
  )
  returning id into v_fatia_app_b;

  insert into public.fabio_registros_aula(
    aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos,
    texto_consolidado, status, origem
  ) values (
    v_turma_wa, v_unidade_id, v_professor_id, null, null, 'C', v_campos_tronco,
    null, 'aguardando_confirmacao', 'whatsapp'
  ) returning id into v_raiz_wa;
  insert into public.fabio_registros_aula(
    aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos,
    texto_consolidado, status, origem
  ) values (
    v_turma_wa, v_unidade_id, v_professor_id, v_aluno_a, v_raiz_wa, 'C',
    '{}'::jsonb, null, 'aguardando_confirmacao', 'whatsapp'
  )
  returning id into v_fatia_wa_a;
  insert into public.fabio_registros_aula(
    aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos,
    texto_consolidado, status, origem
  ) values (
    v_turma_wa, v_unidade_id, v_professor_id, v_aluno_b, v_raiz_wa, 'C',
    jsonb_build_object('presenca', 'ausente'), null, 'aguardando_confirmacao', 'whatsapp'
  )
  returning id into v_fatia_wa_b;

  perform public.fn_atualizar_fatia_core(
    v_professor_id,
    v_fatia_app_a,
    null,
    jsonb_build_object(
      'objetivo', '  CONSOLIDAR LEITURA MUSICAL ',
      'repertorio', ' tema comum ',
      'dever_casa', 'Praticar a leitura',
      'observacoes', 'ritmo estável'
    )
  );
  perform pg_temp.checar_093(
    'updater nao persiste campos individuais iguais ao tronco',
    not ((select campos from public.fabio_registros_aula where id = v_fatia_app_a) ? 'objetivo')
      and not ((select campos from public.fabio_registros_aula where id = v_fatia_app_a) ? 'repertorio')
      and not ((select campos from public.fabio_registros_aula where id = v_fatia_app_a) ? 'dever_casa')
      and not ((select campos from public.fabio_registros_aula where id = v_fatia_app_a) ? 'observacoes'),
    coalesce((select campos::text from public.fabio_registros_aula where id = v_fatia_app_a), '<NULL>')
  );

  v_criado := public.fabio_criar_registro(jsonb_build_object(
    'aula_id', v_turma_app,
    'professor_id', v_professor_id,
    'audio_id', v_audio_valido,
    'molde', 'C',
    'origem', 'app',
    'tronco', jsonb_build_object('campos', v_campos_tronco),
    'fatias', jsonb_build_array(jsonb_build_object(
      'aula_id', v_individual_app_a,
      'aluno_id', v_aluno_a,
      'campos', jsonb_build_object(
        'objetivo', 'CONSOLIDAR LEITURA MUSICAL',
        'repertorio', ' Tema comum ',
        'dever_casa', 'praticar a leitura',
        'observacoes', 'RITMO ESTÁVEL'
      )
    ))
  ));
  v_raiz_criada := (v_criado ->> 'registro_id')::uuid;
  perform pg_temp.checar_093(
    'normalizador nao cria fatia com campos iguais ao tronco',
    not exists (
      select 1 from public.fabio_registros_aula f
       where f.parent_id = v_raiz_criada
         and (f.campos ?| array['objetivo', 'repertorio', 'dever_casa', 'observacoes'])
    ),
    coalesce(v_criado::text, '<NULL>')
  );
  perform pg_temp.checar_093(
    'audio valido do professor e da aula segue o fluxo normal',
    (select status from public.fabio_fila_audios where id = v_audio_valido) = 'normalizado'
      and (select audio_id from public.fabio_registros_aula where id = v_raiz_criada) = v_audio_valido,
    coalesce(v_criado::text, '<NULL>')
  );

  select count(*) into v_presencas_antes
    from public.aluno_presenca
   where aula_emusys_id in (v_turma_app, v_turma_wa);
  perform pg_temp.checar_093(
    'rascunho nao emite presenca antes da confirmacao',
    v_presencas_antes = 0,
    format('presencas_antes=%s', v_presencas_antes)
  );
  perform pg_temp.checar_093(
    'rascunho preserva presenca nao declarada ate a confirmacao',
    not ((select campos from public.fabio_registros_aula where id = v_fatia_app_a) ? 'presenca')
      and not ((select campos from public.fabio_registros_aula where id = v_fatia_wa_a) ? 'presenca'),
    jsonb_build_object(
      'app', (select campos from public.fabio_registros_aula where id = v_fatia_app_a),
      'whatsapp', (select campos from public.fabio_registros_aula where id = v_fatia_wa_a)
    )::text
  );
  perform pg_temp.checar_093(
    'normalizador tambem mantem presenca nao declarada no rascunho',
    not exists (
      select 1 from public.fabio_registros_aula f
       where f.parent_id = v_raiz_criada and f.campos ? 'presenca'
    ),
    coalesce(v_criado::text, '<NULL>')
  );

  perform set_config('request.jwt.claim.sub', v_auth_user_id::text, true);
  v_app := public.app_confirmar_registro(v_raiz_app, 'novo');
  v_wa := public.fabio_confirmar_registro(v_professor_id, v_raiz_wa, 'novo');

  perform pg_temp.checar_093(
    'confirmacao app materializa presente somente depois do rascunho',
    (select campos ->> 'presenca' from public.fabio_registros_aula where id = v_fatia_app_a) = 'presente',
    coalesce((select campos::text from public.fabio_registros_aula where id = v_fatia_app_a), '<NULL>')
  );
  perform pg_temp.checar_093(
    'ausente explicito prevalece sobre o padrao na confirmacao app',
    (select campos ->> 'presenca' from public.fabio_registros_aula where id = v_fatia_app_b) = 'ausente',
    coalesce((select campos::text from public.fabio_registros_aula where id = v_fatia_app_b), '<NULL>')
  );
  perform pg_temp.checar_093(
    'confirmacao whatsapp produz a mesma presenca canonica',
    (select campos ->> 'presenca' from public.fabio_registros_aula where id = v_fatia_wa_a) = 'presente'
      and (select campos ->> 'presenca' from public.fabio_registros_aula where id = v_fatia_wa_b) = 'ausente'
      and coalesce(v_app ->> 'gravadas', '') = coalesce(v_wa ->> 'gravadas', ''),
    jsonb_build_object('app', v_app, 'whatsapp', v_wa)::text
  );
  perform pg_temp.checar_093(
    'fonte forte manual no gemeo continua protegida',
    (select status_presenca from public.aluno_presenca
      where aula_emusys_id = v_individual_app_a and aluno_id = v_aluno_a) = 'falta'
      and (select respondido_por from public.aluno_presenca
      where aula_emusys_id = v_individual_app_a and aluno_id = v_aluno_a) = 'manual',
    coalesce((select jsonb_build_object('status', status_presenca, 'fonte', respondido_por)::text
      from public.aluno_presenca where aula_emusys_id = v_individual_app_a and aluno_id = v_aluno_a), '<NULL>')
  );

  update public.fabio_registros_aula
     set campos = campos || jsonb_build_object('repertorio', '  TEMA COMUM ')
   where id = v_fatia_app_a;
  v_historico := public.app_historico_turma(v_turma_nome_app, 10);
  perform pg_temp.checar_093(
    'historico nao projeta repertorio individual legado igual ao tronco',
    not exists (
      select 1
        from jsonb_array_elements(coalesce(v_historico -> 'sessoes', '[]'::jsonb)) s
        cross join lateral jsonb_array_elements(coalesce(s -> 'repertorio_por_aluno', '[]'::jsonb)) rp
       where lower(btrim(coalesce(rp ->> 'repertorio', ''))) = lower(btrim(coalesce(s ->> 'repertorio_turma', '')))
    ),
    coalesce(v_historico::text, '<NULL>')
  );

  select pg_get_functiondef('public.app_confirmar_registro(uuid,text)'::regprocedure) into v_def_app;
  select pg_get_functiondef('public.fabio_confirmar_registro(integer,uuid,text)'::regprocedure) into v_def_wa;
  perform pg_temp.checar_093(
    'app e whatsapp atravessam o mesmo core de confirmacao',
    v_def_app ilike '%fn_confirmar_registro_core%'
      and v_def_wa ilike '%fn_confirmar_registro_core%'
      and pg_get_functiondef('public.fn_confirmar_registro_core(integer,uuid,uuid,text)'::regprocedure)
            ilike '%fabio_emitir_presenca_por_registro_e_devolutiva%',
    'delegacao e ordem no core'
  );
end
$function$;

select json_build_object(
  'falhas', (select count(*) from _fabio_093_res where not coalesce(ok, false)),
  'detalhe', coalesce((select json_agg(json_build_object(
    'passo', caso,
    'esperado', 'ok',
    'obtido', coalesce(detalhe, '<NULL>')
  )) from _fabio_093_res where not coalesce(ok, false)), '[]'::json)
) as resumo;
