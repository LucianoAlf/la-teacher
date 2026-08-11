-- RED/GREEN contract test for 091. The migration and this file run inside the
-- same disposable transaction.

create temporary table _fabio_091_res(caso text, ok boolean, detalhe text)
on commit drop;

create or replace function pg_temp.checar(p_caso text, p_ok boolean, p_detalhe text)
returns void
language plpgsql
as $function$
begin
  insert into _fabio_091_res values (p_caso, coalesce(p_ok, false), p_detalhe);
end;
$function$;

do $function$
declare
  v_def text;
  v_cfg text[];
begin
  perform pg_temp.checar(
    'assinaturas app permanecem compativeis',
    to_regprocedure('public.app_enfileirar_audio(integer,text,integer,uuid)') is not null
      and to_regprocedure('public.app_atualizar_fatia(uuid,text,jsonb)') is not null
      and to_regprocedure('public.app_responder_presenca(uuid,text)') is not null
      and to_regprocedure('public.app_confirmar_registro(uuid,text)') is not null
      and to_regprocedure('public.app_registrar_presencas_aula(integer,integer[])') is not null
      and to_regprocedure('public.app_status_audio_fila(uuid)') is not null
      and to_regprocedure('public.app_registro_completo(uuid)') is not null,
    'app_*'
  );

  perform pg_temp.checar(
    'assinaturas dos cinco caminhos fabio existem',
    to_regprocedure('public.fabio_enfileirar_audio(integer,integer,text,integer,uuid)') is not null
      and to_regprocedure('public.fabio_atualizar_fatia(integer,uuid,text,jsonb)') is not null
      and to_regprocedure('public.fabio_responder_presenca(integer,uuid,text)') is not null
      and to_regprocedure('public.fabio_confirmar_registro(integer,uuid,text)') is not null
      and to_regprocedure('public.fabio_registrar_presencas_aula(integer,integer,integer[])') is not null
      and to_regprocedure('public.fabio_status_audio_fila(integer,uuid)') is not null
      and to_regprocedure('public.fabio_registro_completo(integer,uuid)') is not null,
    'fabio_*'
  );

  perform pg_temp.checar(
    'cores contractuais existem',
    to_regprocedure('public.fn_enfileirar_audio_core(integer,text,integer,uuid,text)') is not null
      and to_regprocedure('public.fn_atualizar_fatia_core(integer,uuid,text,jsonb)') is not null
      and to_regprocedure('public.fn_responder_presenca_core(integer,uuid,text)') is not null
      and to_regprocedure('public.fn_confirmar_registro_core(integer,uuid,uuid,text)') is not null,
    'fn_*_core'
  );

  select pg_get_functiondef('public.fn_enfileirar_audio_core(integer,text,integer,uuid,text)'::regprocedure)
    into v_def;
  perform pg_temp.checar(
    'core de audio delega para a versao com professor explicito',
    v_def ilike '%fn_enfileirar_audio_core(%'
      and v_def ilike '%p_origem, v_prof%',
    left(coalesce(v_def, ''), 240)
  );

  select pg_get_functiondef('public.fn_atualizar_fatia_core(integer,uuid,text,jsonb)'::regprocedure)
    into v_def;
  perform pg_temp.checar(
    'correcao preserva regeneracao de texto',
    v_def ilike '%fn_compor_texto_prontuario%'
      and v_def ilike '%status not in%'
      and v_def ilike '%parent_id%'
      and (length(v_def) - length(replace(v_def, 'fn_compor_texto_prontuario', '')))
            / length('fn_compor_texto_prontuario') >= 3,
    left(coalesce(v_def, ''), 240)
  );
  perform pg_temp.checar(
    'correcao preserva guarda de professor',
    v_def ilike '%v_prof_dono%'
      and v_def ilike '%is distinct from p_professor_id%',
    left(coalesce(v_def, ''), 240)
  );

  select pg_get_functiondef('public.fn_confirmar_registro_core(integer,uuid,uuid,text)'::regprocedure)
    into v_def;
  perform pg_temp.checar(
    'confirmacao preserva presenca e devolutiva',
    v_def ilike '%fn_presenca_declarada%'
      and v_def ilike '%fabio_emitir_presenca_por_registro_e_devolutiva%'
      and v_def ilike '%registrar_aula_fabio%'
      and v_def ilike '%auth_user_id%'
      and v_def ilike '%confirmado_por = v_user_id%',
    left(coalesce(v_def, ''), 240)
  );

  select pg_get_functiondef('public.fn_enfileirar_audio_core(integer,text,integer,uuid,text,integer)'::regprocedure)
    into v_def;
  perform pg_temp.checar(
    'janela pertence ao enfileiramento',
    v_def ilike '%fn_janela_registro_dias%'
      and pg_get_functiondef('public.fn_confirmar_registro_core(integer,uuid,uuid,text)'::regprocedure)
            not ilike '%fn_janela_registro_dias%',
    left(coalesce(v_def, ''), 240)
  );

  select pg_get_functiondef('public.fn_registrar_presencas_core(integer,integer,integer[],text,boolean)'::regprocedure)
    into v_def;
  perform pg_temp.checar(
    'professor_whatsapp e gemeos permanecem no escritor unico',
    v_def ilike '%professor_whatsapp%'
      and v_def ilike '%fn_sincronizar_gemeos_presenca%',
    left(coalesce(v_def, ''), 240)
  );

  perform pg_temp.checar(
    'professor_whatsapp e uma fonte forte',
    public.fn_presenca_e_forte('professor_whatsapp'),
    'fn_presenca_e_forte'
  );

  select pg_get_functiondef('public.app_registrar_presencas_aula(integer,integer[])'::regprocedure)
    into v_def;
  perform pg_temp.checar(
    'app de chamada usa a mesma guarda de fonte forte',
    v_def ilike '%fn_presenca_e_forte%'
      and v_def ilike '%fn_registrar_presencas_core%'
      and v_def ilike '%professor_la_teacher%',
    left(coalesce(v_def, ''), 240)
  );

  select pg_get_functiondef('public.fabio_enfileirar_audio(integer,integer,text,integer,uuid)'::regprocedure)
    into v_def;
  perform pg_temp.checar(
    'porta de audio fixa origem whatsapp',
    v_def ilike '%whatsapp%'
      and v_def ilike '%fn_enfileirar_audio_core%',
    left(coalesce(v_def, ''), 240)
  );

  select pg_get_functiondef('public.fabio_confirmar_registro(integer,uuid,text)'::regprocedure)
    into v_def;
  perform pg_temp.checar(
    'confirmado_por vem de professores.usuario_id',
    v_def ilike '%professores%'
      and v_def ilike '%usuario_id%'
      and v_def ilike '%fn_confirmar_registro_core%',
    left(coalesce(v_def, ''), 240)
  );

  perform pg_temp.checar(
    'nao existe segundo escritor de presenca',
    to_regprocedure('public.fn_registrar_presencas_aula_core(integer,integer,integer[])') is null
      and to_regprocedure('public.fabio_registrar_presencas_core(integer,integer,integer[])') is null,
    'somente fn_registrar_presencas_core'
  );

  select proconfig into v_cfg
  from pg_proc
  where oid = 'public.fabio_confirmar_registro(integer,uuid,text)'::regprocedure;
  perform pg_temp.checar(
    'porta de confirmacao tem search_path fixo',
    v_cfg @> array['search_path=pg_catalog, public'],
    coalesce(array_to_string(v_cfg, ','), '<NULL>')
  );
end
$function$;

do $function$
declare
  v_def text;
begin
  select pg_get_functiondef('public.fabio_registro_completo(integer,uuid)'::regprocedure)
    into v_def;
  perform pg_temp.checar(
    'read-back de registro exige professor explicito',
    v_def ilike '%p_professor_id%'
      and v_def ilike '%professor_id = p_professor_id%',
    left(coalesce(v_def, ''), 240)
  );

  select pg_get_functiondef('public.fabio_status_audio_fila(integer,uuid)'::regprocedure)
    into v_def;
  perform pg_temp.checar(
    'read-back de audio filtra por professor',
    v_def ilike '%professor_id = p_professor_id%',
    left(coalesce(v_def, ''), 240)
  );

  perform pg_temp.checar(
    'fabio confirmacao nao executavel por anon',
    not has_function_privilege('anon', 'public.fabio_confirmar_registro(integer,uuid,text)', 'EXECUTE'),
    'ACL anon'
  );
  perform pg_temp.checar(
    'fabio confirmacao nao executavel por authenticated',
    not has_function_privilege('authenticated', 'public.fabio_confirmar_registro(integer,uuid,text)', 'EXECUTE'),
    'ACL authenticated'
  );
  perform pg_temp.checar(
    'fabio confirmacao executavel somente pelo service_role',
    has_function_privilege('service_role', 'public.fabio_confirmar_registro(integer,uuid,text)', 'EXECUTE'),
    'ACL service_role'
  );
  perform pg_temp.checar(
    'core de confirmacao nao executavel diretamente',
    not has_function_privilege('service_role', 'public.fn_confirmar_registro_core(integer,uuid,uuid,text)', 'EXECUTE')
      and not has_function_privilege('authenticated', 'public.fn_confirmar_registro_core(integer,uuid,uuid,text)', 'EXECUTE'),
    'ACL core'
  );
end
$function$;

do $function$
declare
  v_prof integer;
  v_out jsonb;
  v_audio_rows integer;
begin
  select id into v_prof from public.professores order by id limit 1;
  if v_prof is null then
    perform pg_temp.checar('read-back sem professor nao vaza dados', false, 'nenhum professor fixture');
    return;
  end if;

  select count(*) into v_audio_rows
    from public.fabio_status_audio_fila(v_prof, gen_random_uuid());
  perform pg_temp.checar(
    'read-back de audio inexistente retorna vazio',
    v_audio_rows = 0,
    v_audio_rows::text
  );

  v_out := public.fabio_registro_completo(v_prof, gen_random_uuid());
  perform pg_temp.checar(
    'read-back de registro inexistente retorna erro fechado',
    v_out->>'erro' = 'nao_encontrado',
    v_out::text
  );
end
$function$;

select json_build_object(
  'teste', '091-as-cinco-portas-do-whatsapp',
  'falhas', (select count(*) from _fabio_091_res where not ok),
  'detalhe', coalesce((select json_agg(json_build_object(
    'passo', caso, 'esperado', 'ok', 'obtido', coalesce(detalhe, '<NULL>'))
  ) from _fabio_091_res where not ok), '[]'::json)
) as resumo;
