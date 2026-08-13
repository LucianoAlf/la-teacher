-- Regressao do incidente Daiana/Elisete (11/08/2026).
-- O orquestrador externo fotografa residuos e metadados da funcao, enquanto o
-- runner abre/fecha a transacao. Todas as fixtures partem da unidade sintetica
-- com codigo fixo zztest_presenca_null.

create temporary table _fabio_20260812135033_res(
  caso text,
  ok boolean,
  detalhe text
) on commit drop;

create or replace function pg_temp.checar_20260812135033(
  p_caso text,
  p_ok boolean,
  p_detalhe text
) returns void
language plpgsql
as $function$
begin
  insert into _fabio_20260812135033_res
  values (p_caso, coalesce(p_ok, false), p_detalhe);
end
$function$;

do $function$
declare
  v_marker constant text := 'zztest_presenca_null';
  v_tag text := v_marker || '_' || txid_current()::text;
  v_unidade_id uuid := gen_random_uuid();
  v_auth_user_id uuid := gen_random_uuid();
  v_auth_estranho_id uuid := gen_random_uuid();
  v_usuario_id integer;
  v_usuario_estranho_id integer;
  v_professor_id integer;
  v_professor_estranho_id integer;
  v_aluno_null integer;
  v_aluno_ausente integer;
  v_emusys_base integer := 810000000 + (txid_current() % 100000000)::integer;
  v_roster_base bigint := -9000000000000000000::bigint + txid_current() * 10;
  v_inicio timestamptz := date_trunc('hour', now()) - interval '1 day' + interval '17 minutes';
  v_ancora integer;
  v_alvo_null integer;
  v_alvo_ausente integer;
  v_raiz uuid;
  v_fatia_null uuid;
  v_fatia_ausente uuid;
  v_retorno jsonb;
begin
  perform pg_temp.checar_20260812135033(
    'fronteiras de owner e ACL permanecem fechadas',
    (select pg_get_userbyid(p.proowner)
       from pg_proc p
      where p.oid = 'public.fn_materializar_presenca_padrao(uuid,integer)'::regprocedure)
      =
    (select pg_get_userbyid(p.proowner)
       from pg_proc p
      where p.oid = 'public.fn_confirmar_registro_core(integer,uuid,uuid,text)'::regprocedure)
      and has_function_privilege(
        'authenticated', 'public.app_confirmar_registro(uuid,text)', 'EXECUTE')
      and not has_function_privilege(
        'anon', 'public.app_confirmar_registro(uuid,text)', 'EXECUTE')
      and not has_function_privilege(
        'anon', 'public.fn_materializar_presenca_padrao(uuid,integer)', 'EXECUTE')
      and not has_function_privilege(
        'authenticated', 'public.fn_materializar_presenca_padrao(uuid,integer)', 'EXECUTE')
      and not has_function_privilege(
        'service_role', 'public.fn_materializar_presenca_padrao(uuid,integer)', 'EXECUTE')
      and not has_function_privilege(
        'anon', 'public.fn_confirmar_registro_core(integer,uuid,uuid,text)', 'EXECUTE')
      and not has_function_privilege(
        'authenticated', 'public.fn_confirmar_registro_core(integer,uuid,uuid,text)', 'EXECUTE')
      and not has_function_privilege(
        'service_role', 'public.fn_confirmar_registro_core(integer,uuid,uuid,text)', 'EXECUTE'),
    'owner compartilhado pelo core; somente app_* fica na API autenticada'
  );

  insert into public.unidades(id, nome, codigo)
  values (v_unidade_id, v_tag || '_unidade', v_marker);

  insert into public.usuarios(nome, email, unidade_id, perfil, auth_user_id, ativo)
  values (
    v_tag || '_usuario', v_tag || '_usuario@example.invalid',
    v_unidade_id, 'professor', v_auth_user_id, true
  ) returning id into v_usuario_id;
  insert into public.usuarios(nome, email, unidade_id, perfil, auth_user_id, ativo)
  values (
    v_tag || '_usuario_estranho', v_tag || '_estranho@example.invalid',
    v_unidade_id, 'professor', v_auth_estranho_id, true
  ) returning id into v_usuario_estranho_id;

  insert into public.professores(nome, ativo, usuario_id)
  values (v_tag || '_professor', true, v_usuario_id)
  returning id into v_professor_id;
  insert into public.professores(nome, ativo, usuario_id)
  values (v_tag || '_professor_estranho', true, v_usuario_estranho_id)
  returning id into v_professor_estranho_id;

  insert into public.alunos(nome, unidade_id, professor_atual_id)
  values (v_tag || '_aluna_null', v_unidade_id, v_professor_id)
  returning id into v_aluno_null;
  insert into public.alunos(nome, unidade_id, professor_atual_id)
  values (v_tag || '_aluna_ausente', v_unidade_id, v_professor_id)
  returning id into v_aluno_ausente;

  -- A ancora e os dois alvos individuais compartilham professor, unidade e
  -- slot. O roster liga cada aluna a ancora e ao seu alvo canonico, exercitando
  -- fn_aula_individual_do_aluno em vez de aceitar um id inventado pela fixture.
  insert into public.aulas_emusys(
    emusys_id, unidade_id, professor_id, data_aula, data_hora_inicio,
    data_hora_fim, tipo, curso_nome, turma_nome, cancelada
  ) values (
    v_emusys_base + 1, v_unidade_id, v_professor_id, v_inicio::date, v_inicio,
    v_inicio + interval '50 minutes', 'turma', v_tag || '_curso',
    v_tag || '_turma', false
  ) returning id into v_ancora;
  insert into public.aulas_emusys(
    emusys_id, unidade_id, professor_id, data_aula, data_hora_inicio,
    data_hora_fim, tipo, curso_nome, turma_nome, cancelada
  ) values (
    v_emusys_base + 2, v_unidade_id, v_professor_id, v_inicio::date, v_inicio,
    v_inicio + interval '50 minutes', 'individual', v_tag || '_curso',
    v_tag || '_turma', false
  ) returning id into v_alvo_null;
  insert into public.aulas_emusys(
    emusys_id, unidade_id, professor_id, data_aula, data_hora_inicio,
    data_hora_fim, tipo, curso_nome, turma_nome, cancelada
  ) values (
    v_emusys_base + 3, v_unidade_id, v_professor_id, v_inicio::date, v_inicio,
    v_inicio + interval '50 minutes', 'individual', v_tag || '_curso',
    v_tag || '_turma', false
  ) returning id into v_alvo_ausente;

  insert into public.aula_alunos_emusys(
    id, aula_emusys_id, unidade_id, aluno_chave, aluno_id,
    aluno_nome, aluno_nome_normalizado
  ) values
    (v_roster_base + 1, v_ancora, v_unidade_id,
     v_tag || '_ancora_null', v_aluno_null,
     v_tag || '_aluna_null', v_tag || '_aluna_null'),
    (v_roster_base + 2, v_ancora, v_unidade_id,
     v_tag || '_ancora_ausente', v_aluno_ausente,
     v_tag || '_aluna_ausente', v_tag || '_aluna_ausente'),
    (v_roster_base + 3, v_alvo_null, v_unidade_id,
     v_tag || '_individual_null', v_aluno_null,
     v_tag || '_aluna_null', v_tag || '_aluna_null'),
    (v_roster_base + 4, v_alvo_ausente, v_unidade_id,
     v_tag || '_individual_ausente', v_aluno_ausente,
     v_tag || '_aluna_ausente', v_tag || '_aluna_ausente');

  insert into public.fabio_registros_aula(
    aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos,
    texto_consolidado, status, origem
  ) values (
    v_ancora, v_unidade_id, v_professor_id, null, null, 'C',
    jsonb_build_object(
      'objetivo', v_tag || '_objetivo',
      'atividades', v_tag || '_atividade'
    ),
    null, 'aguardando_confirmacao', 'app'
  ) returning id into v_raiz;
  insert into public.fabio_registros_aula(
    aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos,
    texto_consolidado, status, origem
  ) values (
    v_ancora, v_unidade_id, v_professor_id, v_aluno_null, v_raiz, 'C',
    jsonb_build_object(
      'presenca', null,
      'repertorio', v_tag || '_conteudo_presente'
    ),
    null, 'aguardando_confirmacao', 'app'
  ) returning id into v_fatia_null;
  insert into public.fabio_registros_aula(
    aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos,
    texto_consolidado, status, origem
  ) values (
    v_ancora, v_unidade_id, v_professor_id, v_aluno_ausente, v_raiz, 'C',
    jsonb_build_object(
      'presenca', 'ausente',
      'repertorio', v_tag || '_conteudo_ausente_isca'
    ),
    null, 'aguardando_confirmacao', 'app'
  ) returning id into v_fatia_ausente;

  perform pg_temp.checar_20260812135033(
    'antes de confirmar a chave JSON null existe e e nao informada',
    (select campos ? 'presenca'
       from public.fabio_registros_aula where id = v_fatia_null)
      and public.fn_presenca_declarada(
        (select campos from public.fabio_registros_aula where id = v_fatia_null)
      ) = 'nao_informada',
    coalesce((select campos::text from public.fabio_registros_aula
               where id = v_fatia_null), '<NULL>')
  );
  perform pg_temp.checar_20260812135033(
    'materializacao e conteudo canonico nao acontecem no rascunho',
    (select status = 'aguardando_confirmacao'
       from public.fabio_registros_aula where id = v_raiz)
      and (select status = 'aguardando_confirmacao'
             and campos -> 'presenca' = 'null'::jsonb
             from public.fabio_registros_aula where id = v_fatia_null)
      and (select anotacoes_fabio is null from public.aulas_emusys where id = v_alvo_null)
      and (select anotacoes_fabio is null from public.aulas_emusys where id = v_alvo_ausente),
    jsonb_build_object(
      'raiz', (select status from public.fabio_registros_aula where id = v_raiz),
      'fatia', (select to_jsonb(f) from public.fabio_registros_aula f where id = v_fatia_null),
      'alvo_null', (select anotacoes_fabio from public.aulas_emusys where id = v_alvo_null),
      'alvo_ausente', (select anotacoes_fabio from public.aulas_emusys where id = v_alvo_ausente)
    )::text
  );
  perform pg_temp.checar_20260812135033(
    'rascunho nao emite presenca devolutiva recibo nem log canonico',
    not exists (
      select 1 from public.aluno_presenca p
       where p.aluno_id in (v_aluno_null, v_aluno_ausente)
         and p.aula_emusys_id in (v_ancora, v_alvo_null, v_alvo_ausente)
    )
      and not exists (
        select 1 from public.fabio_devolutivas d
         where d.registro_fatia_id in (v_fatia_null, v_fatia_ausente)
      )
      and not exists (
        select 1 from public.fabio_notificacoes n
         where n.professor_id = v_professor_id
           and n.tipo = 'registro_recibo'
           and n.referencia_tipo = 'registro_aula'
           and n.referencia_id = v_raiz::text
      )
      and not exists (
        select 1 from public.aula_registros_fabio_log l
         where l.aula_id in (v_alvo_null, v_alvo_ausente)
      ),
    'presenca/devolutiva/recibo/log devem nascer somente na confirmacao'
  );

  -- A mesma porta publica, com outro usuario sintetico, deve barrar ownership
  -- antes da materializacao e antes de qualquer efeito canonico.
  perform set_config('request.jwt.claim.sub', v_auth_estranho_id::text, true);
  begin
    perform public.app_confirmar_registro(v_raiz, 'novo');
    perform pg_temp.checar_20260812135033(
      'app recusa professor que nao e dono do registro', false, 'nao levantou excecao');
  exception when others then
    perform pg_temp.checar_20260812135033(
      'app recusa professor que nao e dono do registro',
      position('nao pertence' in lower(sqlerrm)) > 0,
      sqlerrm
    );
  end;
  perform pg_temp.checar_20260812135033(
    'recusa por ownership nao materializa nem produz efeitos',
    (select campos -> 'presenca' = 'null'::jsonb
       from public.fabio_registros_aula where id = v_fatia_null)
      and (select status = 'aguardando_confirmacao'
             from public.fabio_registros_aula where id = v_raiz)
      and (select anotacoes_fabio is null from public.aulas_emusys where id = v_alvo_null)
      and not exists (
        select 1 from public.aluno_presenca p
         where p.aluno_id in (v_aluno_null, v_aluno_ausente)
      )
      and not exists (
        select 1 from public.fabio_devolutivas d
         where d.registro_fatia_id in (v_fatia_null, v_fatia_ausente)
      )
      and not exists (
        select 1 from public.fabio_notificacoes n
         where n.professor_id = v_professor_id
           and n.referencia_id = v_raiz::text
      ),
    'porta publica deve falhar antes de qualquer escrita do core'
  );

  perform set_config('request.jwt.claim.sub', v_auth_user_id::text, true);
  v_retorno := public.app_confirmar_registro(v_raiz, 'novo');

  perform pg_temp.checar_20260812135033(
    'JSON null vira presente e sua fatia e gravada no alvo canonico',
    (select campos ->> 'presenca' = 'presente'
             and status = 'gravado_emusys'
             and aula_id = v_alvo_null
             and (campos ->> 'aula_alvo_resolvida')::integer = v_alvo_null
             and confirmado_por = v_usuario_id
       from public.fabio_registros_aula where id = v_fatia_null)
      and (select anotacoes_fabio ilike '%' || v_tag || '_conteudo_presente%'
             from public.aulas_emusys where id = v_alvo_null),
    jsonb_build_object(
      'fatia', (select to_jsonb(f) from public.fabio_registros_aula f where id = v_fatia_null),
      'alvo', (select anotacoes_fabio from public.aulas_emusys where id = v_alvo_null)
    )::text
  );
  perform pg_temp.checar_20260812135033(
    'ausencia explicita permanece ausente confirmada e sem conteudo',
    (select campos ->> 'presenca' = 'ausente'
             and status = 'confirmado'
             and aula_id = v_ancora
             and confirmado_por = v_usuario_id
       from public.fabio_registros_aula where id = v_fatia_ausente)
      and (select anotacoes_fabio is null
             from public.aulas_emusys where id = v_alvo_ausente),
    jsonb_build_object(
      'fatia', (select to_jsonb(f) from public.fabio_registros_aula f where id = v_fatia_ausente),
      'alvo', (select anotacoes_fabio from public.aulas_emusys where id = v_alvo_ausente)
    )::text
  );
  perform pg_temp.checar_20260812135033(
    'log canonico registra somente o alvo presente com o texto correto',
    (select count(*) = 1
              and bool_and(
                l.professor_id = v_professor_id
                and l.origem = 'audio'
                and l.modo = 'novo'
                and l.texto_novo ilike '%' || v_tag || '_conteudo_presente%'
              )
       from public.aula_registros_fabio_log l
      where l.aula_id = v_alvo_null)
      and not exists (
        select 1 from public.aula_registros_fabio_log l
         where l.aula_id = v_alvo_ausente
      ),
    coalesce((
      select jsonb_agg(to_jsonb(l) order by l.id)::text
        from public.aula_registros_fabio_log l
       where l.aula_id in (v_alvo_null, v_alvo_ausente)
    ), '<NULL>')
  );
  perform pg_temp.checar_20260812135033(
    'confirmacao fecha a raiz sem pendencias e conta gravada e ausencia',
    (select status = 'gravado_emusys'
             and confirmado_por = v_usuario_id
       from public.fabio_registros_aula where id = v_raiz)
      and jsonb_array_length(coalesce(v_retorno -> 'pendencias', '[]'::jsonb)) = 0
      and coalesce((v_retorno ->> 'gravadas')::integer, -1) = 1
      and coalesce((v_retorno ->> 'ausentes_puladas')::integer, -1) = 1,
    coalesce(v_retorno::text, '<NULL>')
  );
  perform pg_temp.checar_20260812135033(
    'presencas canonicas distinguem presente de falta',
    exists (
      select 1 from public.aluno_presenca p
       where p.aula_emusys_id = v_alvo_null
         and p.aluno_id = v_aluno_null
         and p.status_presenca = 'presente'
    )
      and exists (
        select 1 from public.aluno_presenca p
         where p.aula_emusys_id = v_alvo_ausente
           and p.aluno_id = v_aluno_ausente
           and p.status_presenca = 'falta'
      ),
    coalesce((
      select jsonb_agg(to_jsonb(p) order by p.aula_emusys_id, p.aluno_id)::text
        from public.aluno_presenca p
       where p.aluno_id in (v_aluno_null, v_aluno_ausente)
         and p.aula_emusys_id in (v_ancora, v_alvo_null, v_alvo_ausente)
    ), '<NULL>')
  );
  perform pg_temp.checar_20260812135033(
    'somente presente ganha devolutiva e a raiz ganha um recibo',
    (select count(*) = 1
       from public.fabio_devolutivas d
      where d.registro_fatia_id = v_fatia_null
        and d.aluno_id = v_aluno_null
        and d.professor_id = v_professor_id)
      and not exists (
        select 1 from public.fabio_devolutivas d
         where d.registro_fatia_id = v_fatia_ausente
            or (d.aluno_id = v_aluno_ausente and d.professor_id = v_professor_id)
      )
      and (select count(*) = 1
             from public.fabio_notificacoes n
            where n.professor_id = v_professor_id
              and n.tipo = 'registro_recibo'
              and n.referencia_tipo = 'registro_aula'
              and n.referencia_id = v_raiz::text
              and n.canal = 'whatsapp')
      and coalesce((v_retorno -> 'recibo_enfileirado' ->> 'ok')::boolean, false),
    jsonb_build_object(
      'retorno', v_retorno,
      'devolutivas', (select coalesce(jsonb_agg(to_jsonb(d)), '[]'::jsonb)
                        from public.fabio_devolutivas d
                       where d.professor_id = v_professor_id),
      'recibos', (select coalesce(jsonb_agg(to_jsonb(n)), '[]'::jsonb)
                    from public.fabio_notificacoes n
                   where n.professor_id = v_professor_id
                     and n.referencia_id = v_raiz::text)
    )::text
  );
end
$function$;

select json_build_object(
  'falhas', (select count(*) from _fabio_20260812135033_res where not coalesce(ok, false)),
  'detalhe', coalesce((select json_agg(json_build_object(
    'passo', caso,
    'esperado', 'ok',
    'obtido', coalesce(detalhe, '<NULL>')
  )) from _fabio_20260812135033_res where not coalesce(ok, false)), '[]'::json)
) as resumo;
