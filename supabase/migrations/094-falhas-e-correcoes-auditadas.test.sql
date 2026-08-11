-- Contrato RED/GREEN da 094. O runner abre e fecha a transação; todas as
-- fixtures abaixo são exclusivas desta transação e não dependem de dados vivos.

create temporary table _fabio_094_res(
  caso text,
  ok boolean,
  detalhe text
) on commit drop;

create or replace function pg_temp.checar_094(
  p_caso text,
  p_ok boolean,
  p_detalhe text
) returns void
language plpgsql
as $function$
begin
  insert into _fabio_094_res values (p_caso, coalesce(p_ok, false), p_detalhe);
end
$function$;

do $function$
declare
  v_tag text := 'z94' || txid_current()::text;
  v_unidade_id uuid := gen_random_uuid();
  v_unidade_estranha_id uuid := gen_random_uuid();
  v_auth_user_id uuid := gen_random_uuid();
  v_usuario_id integer;
  v_professor_id integer;
  v_professor_estranho_id integer;
  v_aluno_id integer;
  v_aula_id integer;
  v_aula_estranha_id integer;
  v_registro_id uuid;
  v_registro_estranho_id uuid;
  v_registro_tronco_id uuid;
  v_registro_fatia_id uuid;
  v_devolutiva_id uuid;
  v_devolutiva_estranha_id uuid;
  v_audio_id uuid;
  v_audio_replay_terminal_id uuid;
  v_tentativas_antes integer;
  v_tentativas_depois integer;
  v_presencas_antes integer;
  v_presencas_depois integer;
  v_notificacoes_antes integer;
  v_notificacoes_depois integer;
  v_auditoria_registro integer;
  v_auditoria_devolutiva integer;
  v_auditoria_registro_antes_null_canal integer;
  v_auditoria_devolutiva_antes_null_canal integer;
  v_campos_registro_antes_null_canal jsonb;
  v_texto_normal_antes_null_canal text;
  v_texto_apoio_antes_null_canal text;
  v_recusou_canal_nulo_registro boolean := false;
  v_recusou_canal_nulo_devolutiva boolean := false;
  v_resultado jsonb;
  v_resultado_replay jsonb;
  v_erro_replay text;
  v_ctid_registro text;
  v_ctid_devolutiva text;
  v_recusou_acao_nula_registro boolean := false;
  v_recusou_acao_nula_devolutiva boolean := false;
  v_def_retry text;
  v_config text[];
  v_emusys_base integer := 700000000 + (txid_current() % 100000000)::integer;
  v_campos_antes jsonb := jsonb_build_object(
    'objetivo', 'Ler a partitura',
    'atividades', 'Leitura guiada',
    'observacoes', 'Conseguiu ler o quadro sistema decorado'
  );
begin
  if to_regprocedure('public.fabio_marcar_audio_erro_terminal(uuid,text,text)') is null
     or to_regprocedure('public.fabio_corrigir_registro_confirmado(integer,uuid,jsonb,text,text,text)') is null
     or to_regprocedure('public.fabio_atualizar_devolutiva_rascunho(integer,uuid,text,text,text,text,text)') is null
     or to_regclass('public.fabio_registro_correcoes') is null
     or to_regclass('public.fabio_devolutiva_edicoes') is null
     or to_regclass('public.fabio_correcoes_acoes') is null then
    perform pg_temp.checar_094(
      '094 define marcador terminal, portas auditadas e ledger de acoes',
      false,
      'marcador/RPCs/tabelas/ledger da 094 ausentes'
    );
    return;
  end if;

  perform pg_temp.checar_094(
    'estado terminal e tipo semantico existem na fila',
    exists (
      select 1 from pg_constraint c
       where c.conrelid = 'public.fabio_fila_audios'::regclass
         and pg_get_constraintdef(c.oid) ilike '%erro_terminal%'
         and pg_get_constraintdef(c.oid) ilike '%semantico_terminal%'
    ),
    'constraint de status/tipo da fila'
  );

  perform pg_temp.checar_094(
    'as tres portas 094 sao exclusivas do service_role',
    not has_function_privilege('anon', 'public.fabio_marcar_audio_erro_terminal(uuid,text,text)', 'EXECUTE')
      and not has_function_privilege('authenticated', 'public.fabio_marcar_audio_erro_terminal(uuid,text,text)', 'EXECUTE')
      and has_function_privilege('service_role', 'public.fabio_marcar_audio_erro_terminal(uuid,text,text)', 'EXECUTE')
      and not has_function_privilege('anon', 'public.fabio_corrigir_registro_confirmado(integer,uuid,jsonb,text,text,text)', 'EXECUTE')
      and not has_function_privilege('authenticated', 'public.fabio_corrigir_registro_confirmado(integer,uuid,jsonb,text,text,text)', 'EXECUTE')
      and has_function_privilege('service_role', 'public.fabio_corrigir_registro_confirmado(integer,uuid,jsonb,text,text,text)', 'EXECUTE')
      and not has_function_privilege('anon', 'public.fabio_atualizar_devolutiva_rascunho(integer,uuid,text,text,text,text,text)', 'EXECUTE')
      and not has_function_privilege('authenticated', 'public.fabio_atualizar_devolutiva_rascunho(integer,uuid,text,text,text,text,text)', 'EXECUTE')
      and has_function_privilege('service_role', 'public.fabio_atualizar_devolutiva_rascunho(integer,uuid,text,text,text,text,text)', 'EXECUTE')
      and not has_table_privilege('anon', 'public.fabio_correcoes_acoes', 'SELECT, INSERT, UPDATE')
      and not has_table_privilege('authenticated', 'public.fabio_correcoes_acoes', 'SELECT, INSERT, UPDATE'),
    'ACL das portas 094'
  );
  perform pg_temp.checar_094(
    'fn_fabio_retry_fila e exclusiva do service_role',
    not has_function_privilege('anon', 'public.fn_fabio_retry_fila()', 'EXECUTE')
      and not has_function_privilege('authenticated', 'public.fn_fabio_retry_fila()', 'EXECUTE')
      and has_function_privilege('service_role', 'public.fn_fabio_retry_fila()', 'EXECUTE'),
    'ACL de public.fn_fabio_retry_fila()'
  );

  select proconfig into v_config
    from pg_proc
   where oid = 'public.fabio_corrigir_registro_confirmado(integer,uuid,jsonb,text,text,text)'::regprocedure;
  perform pg_temp.checar_094(
    'correcao de registro usa search_path fixo',
    v_config @> array['search_path=pg_catalog, public'],
    coalesce(array_to_string(v_config, ','), '<NULL>')
  );
  perform pg_temp.checar_094(
    'API de correcao exige chave de acao e remove assinaturas sem chave',
    to_regprocedure('public.fabio_corrigir_registro_confirmado(integer,uuid,jsonb,text,text)') is null
      and to_regprocedure('public.fabio_atualizar_devolutiva_rascunho(integer,uuid,text,text,text,text)') is null
      and coalesce(obj_description(
        'public.fabio_corrigir_registro_confirmado(integer,uuid,jsonb,text,text,text)'::regprocedure,
        'pg_proc'
      ), '') ilike '%p_acao_id%',
    'assinaturas antigas ou contrato da chave de acao'
  );
  perform pg_temp.checar_094(
    'ledger de correcao tem unicidade por tipo e chave de acao',
    exists (
      select 1
        from pg_constraint c
       where c.conrelid = 'public.fabio_correcoes_acoes'::regclass
         and c.contype = 'u'
         and pg_get_constraintdef(c.oid) = 'UNIQUE (tipo, acao_id)'
    ),
    'constraint UNIQUE (tipo, acao_id)'
  );

  insert into public.unidades(id, nome, codigo)
  values
    (v_unidade_id, v_tag || '_unidade', v_tag || '_unidade'),
    (v_unidade_estranha_id, v_tag || '_outra', v_tag || '_outra');

  insert into public.usuarios(nome, email, unidade_id, perfil, auth_user_id, ativo)
  values (v_tag || '_usuario', lower(v_tag) || '@example.invalid', v_unidade_id, 'professor', v_auth_user_id, true)
  returning id into v_usuario_id;

  insert into public.professores(nome, ativo, usuario_id)
  values (v_tag || '_professor', true, v_usuario_id)
  returning id into v_professor_id;
  insert into public.professores(nome, ativo)
  values (v_tag || '_professor_estranho', true)
  returning id into v_professor_estranho_id;

  insert into public.alunos(nome, unidade_id, professor_atual_id)
  values (v_tag || '_aluno', v_unidade_id, v_professor_id)
  returning id into v_aluno_id;

  insert into public.aulas_emusys(
    emusys_id, unidade_id, professor_id, data_aula, data_hora_inicio,
    data_hora_fim, tipo, curso_nome, turma_nome, cancelada, anotacoes_fabio
  ) values (
    v_emusys_base + 1, v_unidade_id, v_professor_id, current_date - 1,
    date_trunc('hour', now()) - interval '1 day', date_trunc('hour', now()) - interval '1 day' + interval '50 minutes',
    'individual', 'Contrato 094', v_tag || '_turma', false, 'Observacao anterior'
  ) returning id into v_aula_id;
  insert into public.aulas_emusys(
    emusys_id, unidade_id, professor_id, data_aula, data_hora_inicio,
    data_hora_fim, tipo, curso_nome, turma_nome, cancelada
  ) values (
    v_emusys_base + 2, v_unidade_estranha_id, v_professor_estranho_id, current_date - 1,
    date_trunc('hour', now()) - interval '1 day', date_trunc('hour', now()) - interval '1 day' + interval '50 minutes',
    'individual', 'Contrato 094', v_tag || '_estranha', false
  ) returning id into v_aula_estranha_id;

  insert into public.fabio_fila_audios(
    professor_id, unidade_id, aula_id, storage_path, status, origem, tentativas
  ) values (
    v_professor_id, v_unidade_id, v_aula_id,
    'teste-094/' || v_tag || '/terminal.ogg', 'erro', 'whatsapp', 3
  ) returning id into v_audio_id;
  insert into public.fabio_fila_audios(
    professor_id, unidade_id, aula_id, storage_path, status, origem, tentativas
  ) values (
    v_professor_id, v_unidade_id, v_aula_id,
    'teste-094/' || v_tag || '/callback-tardio.ogg', 'erro', 'whatsapp', 2
  ) returning id into v_audio_replay_terminal_id;

  insert into public.fabio_registros_aula(
    aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos,
    texto_consolidado, status, origem
  ) values (
    v_aula_id, v_unidade_id, v_professor_id, v_aluno_id, null, 'C', v_campos_antes,
    public.fn_compor_texto_prontuario(v_campos_antes, v_campos_antes), 'gravado_emusys', 'app'
  ) returning id into v_registro_id;
  insert into public.fabio_registros_aula(
    aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos,
    texto_consolidado, status, origem
  ) values (
    v_aula_estranha_id, v_unidade_estranha_id, v_professor_estranho_id, null, null, 'C', '{}',
    null, 'gravado_emusys', 'whatsapp'
  ) returning id into v_registro_estranho_id;
  insert into public.fabio_registros_aula(
    aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos,
    texto_consolidado, status, origem
  ) values (
    v_aula_id, v_unidade_id, v_professor_id, null, null, 'C',
    jsonb_build_object('repertorio', 'Tema comum'),
    'Repertorio: Tema comum', 'gravado_emusys', 'app'
  ) returning id into v_registro_tronco_id;
  insert into public.fabio_registros_aula(
    aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos,
    texto_consolidado, status, origem
  ) values (
    v_aula_id, v_unidade_id, v_professor_id, v_aluno_id, v_registro_tronco_id, 'C',
    jsonb_build_object('progresso', 'Leu com seguranca'),
    'Progresso: Leu com seguranca', 'gravado_emusys', 'app'
  ) returning id into v_registro_fatia_id;

  insert into public.fabio_devolutivas(
    registro_fatia_id, aluno_id, professor_id, texto_normal, texto_apoio_casa, status
  ) values (
    v_registro_id, v_aluno_id, v_professor_id,
    'Texto original para a familia.', 'Praticar leitura.', 'gerada'
  ) returning id into v_devolutiva_id;
  insert into public.fabio_devolutivas(
    registro_fatia_id, aluno_id, professor_id, texto_normal, texto_apoio_casa, status
  ) values (
    v_registro_estranho_id, v_aluno_id, v_professor_estranho_id,
    'Texto estranho.', 'Apoio estranho.', 'gerada'
  ) returning id into v_devolutiva_estranha_id;

  select tentativas into v_tentativas_antes
    from public.fabio_fila_audios where id = v_audio_id;
  v_resultado := public.fabio_marcar_audio_erro_terminal(
    v_audio_id, 'sem_conteudo_pedagogico', E'  sem\nconteudo pedagogico real  '
  );
  select tentativas into v_tentativas_depois
    from public.fabio_fila_audios where id = v_audio_id;
  perform pg_temp.checar_094(
    'erro semantico terminal nao altera tentativas',
    (v_resultado ->> 'status') = 'erro_terminal'
      and (v_resultado ->> 'erro_tipo') = 'semantico_terminal'
      and v_tentativas_depois = v_tentativas_antes,
    coalesce(v_resultado::text, '<NULL>')
  );
  perform pg_temp.checar_094(
    'marcador aceita somente codigos conhecidos e saneia detalhe',
    (select erro_tipo = 'semantico_terminal'
        and erro ilike '%sem_conteudo_pedagogico%'
        and length(erro) <= 360
       from public.fabio_fila_audios where id = v_audio_id),
    coalesce((select jsonb_build_object('erro', erro, 'tipo', erro_tipo)::text
      from public.fabio_fila_audios where id = v_audio_id), '<NULL>')
  );

  perform public.fabio_marcar_audio_erro_terminal(
    v_audio_replay_terminal_id, 'transcricao_incompativel', 'callback nao deve recriar rascunho'
  );
  begin
    perform public.fabio_criar_registro(jsonb_build_object(
      'audio_id', v_audio_replay_terminal_id,
      'aula_id', v_aula_id,
      'professor_id', v_professor_id,
      'origem', 'whatsapp',
      'tronco', jsonb_build_object('campos', jsonb_build_object('objetivo', 'Nao normalizar callback tardio')),
      'fatias', '[]'::jsonb
    ));
    perform pg_temp.checar_094(
      'callback tardio terminal nao recria rascunho nem normaliza audio',
      false,
      'fabio_criar_registro aceitou audio terminal'
    );
  exception when others then
    perform pg_temp.checar_094(
      'callback tardio terminal nao recria rascunho nem normaliza audio',
      position('audio_terminal_nao_normalizavel' in sqlerrm) > 0
        and (select status = 'erro_terminal' and erro_tipo = 'semantico_terminal'
               from public.fabio_fila_audios where id = v_audio_replay_terminal_id)
        and not exists (
          select 1 from public.fabio_registros_aula
           where audio_id = v_audio_replay_terminal_id
        ),
      sqlerrm
    );
  end;

  select pg_get_functiondef('public.fn_fabio_retry_fila()'::regprocedure) into v_def_retry;
  perform pg_temp.checar_094(
    'erro semantico terminal nao pode voltar para fn_fabio_retry_fila',
    v_def_retry ilike '%erro_tipo = ''transitorio''%'
      and v_def_retry ilike '%erro_terminal%',
    left(coalesce(v_def_retry, ''), 1000)
  );

  begin
    perform public.fabio_marcar_audio_erro_terminal(
      v_audio_id, 'codigo_inventado', 'nao deve persistir'
    );
    perform pg_temp.checar_094('codigo terminal inventado e recusado', false, 'aceitou codigo inventado');
  exception when others then
    perform pg_temp.checar_094(
      'codigo terminal inventado e recusado',
      position('codigo_terminal_invalido' in sqlerrm) > 0,
      sqlerrm
    );
  end;
  begin
    execute $$select public.fabio_marcar_audio_erro_terminal('uuid-invalido', 'sem_conteudo_pedagogico', null)$$;
    perform pg_temp.checar_094('id malformado nao chega ao marcador', false, 'uuid invalido aceito');
  exception when others then
    perform pg_temp.checar_094(
      'id malformado nao chega ao marcador',
      position('invalid input syntax' in lower(sqlerrm)) > 0,
      sqlerrm
    );
  end;

  select count(*) into v_presencas_antes
    from public.aluno_presenca where aula_emusys_id = v_aula_id;
  v_resultado := public.fabio_corrigir_registro_confirmado(
    v_professor_id,
    v_registro_id,
    jsonb_build_object('observacoes', 'Conseguiu ler ate o quarto sistema decorado'),
    'corrigir termo transcrito',
    'whatsapp',
    v_tag || ':registro-confirmado-1'
  );
  select count(*) into v_presencas_depois
    from public.aluno_presenca where aula_emusys_id = v_aula_id;
  select count(*) into v_auditoria_registro
    from public.fabio_registro_correcoes where registro_id = v_registro_id;
  perform pg_temp.checar_094(
    'correcao confirmada recompõe prontuario e usa emissao existente',
    (v_resultado ->> 'codigo') = 'registro_corrigido'
      and (select texto_consolidado ilike '%quarto sistema%'
             from public.fabio_registros_aula where id = v_registro_id)
      and (select anotacoes_fabio ilike '%quarto sistema%'
             from public.aulas_emusys where id = v_aula_id),
    coalesce(v_resultado::text, '<NULL>')
  );
  perform pg_temp.checar_094(
    'correcao confirmada nunca altera presenca',
    v_presencas_antes = v_presencas_depois,
    format('antes=%s depois=%s', v_presencas_antes, v_presencas_depois)
  );
  perform pg_temp.checar_094(
    'correcao confirmada audita antes depois autor motivo canal e horario uma vez',
    v_auditoria_registro = 1
      and exists (
        select 1 from public.fabio_registro_correcoes c
         where c.registro_id = v_registro_id
           and c.professor_id = v_professor_id
           and c.autor_usuario_id = v_usuario_id
           and c.canal = 'whatsapp'
           and c.motivo = 'corrigir termo transcrito'
           and c.criado_em is not null
           and c.antes -> 'campos' ->> 'observacoes' = 'Conseguiu ler o quadro sistema decorado'
           and c.depois -> 'campos' ->> 'observacoes' = 'Conseguiu ler ate o quarto sistema decorado'
      ),
    format('auditorias=%s', v_auditoria_registro)
  );

  select ctid::text into v_ctid_registro
    from public.fabio_registros_aula where id = v_registro_id;
  v_resultado_replay := null;
  v_erro_replay := null;
  begin
    v_resultado_replay := public.fabio_corrigir_registro_confirmado(
      v_professor_id,
      v_registro_id,
      jsonb_build_object('observacoes', 'Conseguiu ler ate o quarto sistema decorado'),
      'corrigir termo transcrito',
      'whatsapp',
      v_tag || ':registro-confirmado-1'
    );
  exception when others then
    v_erro_replay := sqlerrm;
  end;
  perform pg_temp.checar_094(
    'replay de correcao WhatsApp devolve resultado anterior sem segundo update ou auditoria',
    v_erro_replay is null
      and v_resultado_replay = v_resultado
      and (select ctid::text from public.fabio_registros_aula where id = v_registro_id) = v_ctid_registro
      and (select count(*) from public.fabio_registro_correcoes where registro_id = v_registro_id) = 1
      and (select count(*) from public.fabio_correcoes_acoes
            where tipo = 'registro_confirmado' and acao_id = v_tag || ':registro-confirmado-1') = 1,
    coalesce(v_erro_replay, v_resultado_replay::text, '<NULL>')
  );
  begin
    perform public.fabio_corrigir_registro_confirmado(
      v_professor_id,
      v_registro_id,
      jsonb_build_object('observacoes', 'nao pode corrigir sem chave'),
      'testar chave nula',
      'whatsapp',
      null::text
    );
    perform pg_temp.checar_094('correcao exige chave de acao sem bypass nulo', false, 'chave nula aceita');
  exception when others then
    perform pg_temp.checar_094(
      'correcao exige chave de acao sem bypass nulo',
      position('acao_id_obrigatorio' in sqlerrm) > 0
        and (select campos ->> 'observacoes' from public.fabio_registros_aula where id = v_registro_id)
              = 'Conseguiu ler ate o quarto sistema decorado'
        and (select count(*) from public.fabio_registro_correcoes where registro_id = v_registro_id) = 1
        and (select count(*) from public.fabio_correcoes_acoes
              where tipo = 'registro_confirmado' and acao_id = v_tag || ':registro-confirmado-1') = 1,
      sqlerrm
    );
  end;

  select campos into v_campos_registro_antes_null_canal
    from public.fabio_registros_aula where id = v_registro_id;
  select count(*) into v_auditoria_registro_antes_null_canal
    from public.fabio_registro_correcoes where registro_id = v_registro_id;
  begin
    perform public.fabio_corrigir_registro_confirmado(
      v_professor_id,
      v_registro_id,
      jsonb_build_object('observacoes', 'nao pode corrigir sem canal'),
      'testar canal nulo',
      null::text,
      v_tag || ':registro-canal-nulo'
    );
  exception when others then
    v_recusou_canal_nulo_registro := position('canal_correcao_invalido' in sqlerrm) > 0;
  end;
  perform pg_temp.checar_094(
    'correcao recusa canal NULL sem alterar registro ou auditoria',
    v_recusou_canal_nulo_registro
      and (select campos from public.fabio_registros_aula where id = v_registro_id)
            = v_campos_registro_antes_null_canal
      and (select count(*) from public.fabio_registro_correcoes where registro_id = v_registro_id)
            = v_auditoria_registro_antes_null_canal,
    format(
      'recusou=%s campos=%s auditorias=%s',
      v_recusou_canal_nulo_registro,
      coalesce((select campos::text from public.fabio_registros_aula where id = v_registro_id), '<NULL>'),
      (select count(*) from public.fabio_registro_correcoes where registro_id = v_registro_id)
    )
  );

  perform public.fabio_corrigir_registro_confirmado(
    v_professor_id,
    v_registro_fatia_id,
    jsonb_build_object('repertorio', '  tema comum  '),
    'remover repertorio repetido da fatia',
    'app',
    v_tag || ':registro-fatia-1'
  );
  perform pg_temp.checar_094(
    'correcao de fatia remove campo igual ao tronco antes de recalcular',
    not ((select campos from public.fabio_registros_aula where id = v_registro_fatia_id) ? 'repertorio')
      and exists (
        select 1
          from public.fabio_registro_correcoes c
         where c.registro_id = v_registro_fatia_id
           and not (c.depois -> 'campos' ? 'repertorio')
      ),
    coalesce((select campos::text from public.fabio_registros_aula where id = v_registro_fatia_id), '<NULL>')
  );

  begin
    perform public.fabio_corrigir_registro_confirmado(
      v_professor_estranho_id, v_registro_id,
      jsonb_build_object('observacoes', 'invasao'), 'tentativa estranha', 'whatsapp', v_tag || ':registro-estranho'
    );
    perform pg_temp.checar_094('outro professor nao corrige registro final', false, 'correcao estranha aceita');
  exception when others then
    perform pg_temp.checar_094(
      'outro professor nao corrige registro final',
      position('registro_nao_pertence_ao_professor' in sqlerrm) > 0,
      sqlerrm
    );
  end;
  begin
    perform public.fabio_corrigir_registro_confirmado(
      v_professor_id, v_registro_id,
      jsonb_build_object('presenca', 'ausente'), 'tentativa fora da lista branca', 'whatsapp', v_tag || ':registro-lista-branca'
    );
    perform pg_temp.checar_094('lista branca impede correcao de presenca', false, 'campo presenca aceito');
  exception when others then
    perform pg_temp.checar_094(
      'lista branca impede correcao de presenca',
      position('campo_correcao_nao_permitido' in sqlerrm) > 0,
      sqlerrm
    );
  end;
  begin
    perform public.fabio_corrigir_registro_confirmado(
      v_professor_id, v_registro_id,
      jsonb_build_object('observacoes', 'canal invalido'), 'testar canal', 'sms', v_tag || ':registro-canal-invalido'
    );
    perform pg_temp.checar_094('correcao recusa canal fora de app ou whatsapp', false, 'canal invalido aceito');
  exception when others then
    perform pg_temp.checar_094(
      'correcao recusa canal fora de app ou whatsapp',
      position('canal_correcao_invalido' in sqlerrm) > 0,
      sqlerrm
    );
  end;

  select count(*) into v_notificacoes_antes
    from public.fabio_notificacoes n
   where to_jsonb(n) ->> 'professor_id' = v_professor_id::text;
  v_resultado := public.fabio_atualizar_devolutiva_rascunho(
    v_professor_id,
    v_devolutiva_id,
    'Texto revisado para a familia.',
    'Praticar leitura em casa.',
    'melhorar devolutiva do aluno',
    'whatsapp',
    v_tag || ':devolutiva-1'
  );
  select count(*) into v_notificacoes_depois
    from public.fabio_notificacoes n
   where to_jsonb(n) ->> 'professor_id' = v_professor_id::text;
  select count(*) into v_auditoria_devolutiva
    from public.fabio_devolutiva_edicoes where devolutiva_id = v_devolutiva_id;
  perform pg_temp.checar_094(
    'editar devolutiva em rascunho nunca cria envio a familia',
    (v_resultado ->> 'codigo') = 'devolutiva_atualizada'
      and v_notificacoes_antes = v_notificacoes_depois
      and (select status = 'gerada'
                  and envio_recibo is null
                  and envio_confirmado_em is null
                  and compartilhada_em is null
             from public.fabio_devolutivas where id = v_devolutiva_id),
    coalesce(v_resultado::text, '<NULL>')
  );
  perform pg_temp.checar_094(
    'edicao de devolutiva audita antes depois autor motivo canal e horario uma vez',
    v_auditoria_devolutiva = 1
      and exists (
        select 1 from public.fabio_devolutiva_edicoes e
         where e.devolutiva_id = v_devolutiva_id
           and e.professor_id = v_professor_id
           and e.autor_usuario_id = v_usuario_id
           and e.canal = 'whatsapp'
           and e.motivo = 'melhorar devolutiva do aluno'
           and e.criado_em is not null
           and e.antes ->> 'texto_normal' = 'Texto original para a familia.'
           and e.depois ->> 'texto_normal' = 'Texto revisado para a familia.'
      ),
    format('auditorias=%s', v_auditoria_devolutiva)
  );

  select ctid::text into v_ctid_devolutiva
    from public.fabio_devolutivas where id = v_devolutiva_id;
  v_resultado_replay := null;
  v_erro_replay := null;
  begin
    v_resultado_replay := public.fabio_atualizar_devolutiva_rascunho(
      v_professor_id,
      v_devolutiva_id,
      'Texto revisado para a familia.',
      'Praticar leitura em casa.',
      'melhorar devolutiva do aluno',
      'whatsapp',
      v_tag || ':devolutiva-1'
    );
  exception when others then
    v_erro_replay := sqlerrm;
  end;
  perform pg_temp.checar_094(
    'replay de devolutiva WhatsApp devolve resultado anterior sem segundo update ou auditoria',
    v_erro_replay is null
      and v_resultado_replay = v_resultado
      and (select ctid::text from public.fabio_devolutivas where id = v_devolutiva_id) = v_ctid_devolutiva
      and (select count(*) from public.fabio_devolutiva_edicoes where devolutiva_id = v_devolutiva_id) = 1
      and (select count(*) from public.fabio_correcoes_acoes
            where tipo = 'devolutiva_rascunho' and acao_id = v_tag || ':devolutiva-1') = 1,
    coalesce(v_erro_replay, v_resultado_replay::text, '<NULL>')
  );
  begin
    perform public.fabio_atualizar_devolutiva_rascunho(
      v_professor_id,
      v_devolutiva_id,
      'Texto que nao pode substituir o rascunho.',
      'Apoio que nao pode substituir o rascunho.',
      'testar chave nula',
      'whatsapp',
      null::text
    );
    perform pg_temp.checar_094('devolutiva exige chave de acao sem bypass nulo', false, 'chave nula aceita');
  exception when others then
    perform pg_temp.checar_094(
      'devolutiva exige chave de acao sem bypass nulo',
      position('acao_id_obrigatorio' in sqlerrm) > 0
        and (select texto_normal from public.fabio_devolutivas where id = v_devolutiva_id)
              = 'Texto revisado para a familia.'
        and (select count(*) from public.fabio_devolutiva_edicoes where devolutiva_id = v_devolutiva_id) = 1
        and (select count(*) from public.fabio_correcoes_acoes
              where tipo = 'devolutiva_rascunho' and acao_id = v_tag || ':devolutiva-1') = 1,
      sqlerrm
    );
  end;

  select texto_normal, texto_apoio_casa
    into v_texto_normal_antes_null_canal, v_texto_apoio_antes_null_canal
    from public.fabio_devolutivas where id = v_devolutiva_id;
  select count(*) into v_auditoria_devolutiva_antes_null_canal
    from public.fabio_devolutiva_edicoes where devolutiva_id = v_devolutiva_id;
  begin
    perform public.fabio_atualizar_devolutiva_rascunho(
      v_professor_id,
      v_devolutiva_id,
      'Texto que nao pode substituir o rascunho.',
      'Apoio que nao pode substituir o rascunho.',
      'testar canal nulo',
      null::text,
      v_tag || ':devolutiva-canal-nulo'
    );
  exception when others then
    v_recusou_canal_nulo_devolutiva := position('canal_correcao_invalido' in sqlerrm) > 0;
  end;
  perform pg_temp.checar_094(
    'devolutiva recusa canal NULL sem alterar alvo ou auditoria',
    v_recusou_canal_nulo_devolutiva
      and (select texto_normal from public.fabio_devolutivas where id = v_devolutiva_id)
            = v_texto_normal_antes_null_canal
      and (select texto_apoio_casa from public.fabio_devolutivas where id = v_devolutiva_id)
            = v_texto_apoio_antes_null_canal
      and (select count(*) from public.fabio_devolutiva_edicoes where devolutiva_id = v_devolutiva_id)
            = v_auditoria_devolutiva_antes_null_canal,
    format(
      'recusou=%s texto=%s apoio=%s auditorias=%s',
      v_recusou_canal_nulo_devolutiva,
      coalesce((select texto_normal from public.fabio_devolutivas where id = v_devolutiva_id), '<NULL>'),
      coalesce((select texto_apoio_casa from public.fabio_devolutivas where id = v_devolutiva_id), '<NULL>'),
      (select count(*) from public.fabio_devolutiva_edicoes where devolutiva_id = v_devolutiva_id)
    )
  );

  begin
    perform public.fabio_atualizar_devolutiva_rascunho(
      v_professor_estranho_id, v_devolutiva_id,
      'Texto invasivo.', 'Apoio invasivo.', 'tentativa estranha', 'whatsapp', v_tag || ':devolutiva-estranha'
    );
    perform pg_temp.checar_094('outro professor nao edita devolutiva', false, 'edicao estranha aceita');
  exception when others then
    perform pg_temp.checar_094(
      'outro professor nao edita devolutiva',
      position('devolutiva_nao_pertence_ao_professor' in sqlerrm) > 0,
      sqlerrm
    );
  end;

  update public.fabio_devolutivas
     set status = 'entrega_incerta'
   where id = v_devolutiva_id;
  begin
    perform public.fabio_atualizar_devolutiva_rascunho(
      v_professor_id, v_devolutiva_id,
      'Nao pode editar.', 'Nao pode editar.', 'status bloqueado', 'whatsapp', v_tag || ':devolutiva-status'
    );
    perform pg_temp.checar_094('status de devolutiva fora de gerada ou oferecida e bloqueado', false, 'status bloqueado aceito');
  exception when others then
    perform pg_temp.checar_094(
      'status de devolutiva fora de gerada ou oferecida e bloqueado',
      position('devolutiva_status_nao_editavel' in sqlerrm) > 0,
      sqlerrm
    );
  end;

  perform pg_temp.checar_094(
    'tabelas de auditoria e ledger tem RLS e nao expoem acesso direto',
    (select relrowsecurity from pg_class where oid = 'public.fabio_registro_correcoes'::regclass)
      and (select relrowsecurity from pg_class where oid = 'public.fabio_devolutiva_edicoes'::regclass)
      and (select relrowsecurity and relforcerowsecurity
             from pg_class where oid = 'public.fabio_correcoes_acoes'::regclass)
      and not has_table_privilege('anon', 'public.fabio_registro_correcoes', 'SELECT')
      and not has_table_privilege('authenticated', 'public.fabio_devolutiva_edicoes', 'SELECT')
      and not has_table_privilege('anon', 'public.fabio_correcoes_acoes', 'SELECT')
      and not has_table_privilege('authenticated', 'public.fabio_correcoes_acoes', 'SELECT'),
    'RLS/ACL das auditorias e ledger'
  );
end
$function$;

select json_build_object(
  'falhas', (select count(*) from _fabio_094_res where not coalesce(ok, false)),
  'detalhe', coalesce((select json_agg(json_build_object(
    'passo', caso,
    'esperado', 'ok',
    'obtido', coalesce(detalhe, '<NULL>')
  )) from _fabio_094_res where not coalesce(ok, false)), '[]'::json)
) as resumo;
