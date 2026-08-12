-- 096-ACAO-START-CHOOSER-INICIO
-- O bridge abre a shortlist diretamente quando a classificacao deterministica
-- ja fechou a intencao. A RPC antiga aceitava apenas os estados de pergunta
-- de intencao e recusava `escolher_aula_*`, quebrando antes da shortlist.
create or replace function public.fabio_iniciar_acao(
  p_professor_id integer,
  p_wa_message_id text,
  p_tipo text,
  p_storage_path text default null,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_id uuid;
  v_acao jsonb;
begin
  if p_tipo not in (
    'confirmar_intencao_audio',
    'confirmar_intencao_chamada',
    'escolher_aula_audio',
    'escolher_aula_chamada'
  ) then
    return jsonb_build_object('ok', false, 'codigo', 'tipo_invalido');
  end if;
  if p_wa_message_id is null or btrim(p_wa_message_id) = '' then
    return jsonb_build_object('ok', false, 'codigo', 'wa_message_id_obrigatorio');
  end if;
  if not exists (select 1 from public.professores p where p.id = p_professor_id) then
    return jsonb_build_object('ok', false, 'codigo', 'professor_nao_encontrado');
  end if;

  select id into v_id
    from public.fabio_acoes_pendentes
   where wa_message_id = p_wa_message_id;
  if v_id is not null then
    return jsonb_build_object(
      'ok', true,
      'codigo', 'acao_existente',
      'acao', public.fabio_acao_json(v_id)
    );
  end if;

  if exists (
    select 1
      from public.fabio_acoes_pendentes
     where professor_id = p_professor_id
       and estado in ('aberta', 'processando', 'adiada')
  ) then
    return jsonb_build_object(
      'ok', false,
      'codigo', 'acao_ativa_existente',
      'acao', public.fabio_acao_ativa(p_professor_id) -> 'acao'
    );
  end if;

  insert into public.fabio_acoes_pendentes(
    professor_id,
    wa_message_id,
    tipo,
    estado,
    storage_path,
    candidatas,
    payload,
    expira_em
  ) values (
    p_professor_id,
    p_wa_message_id,
    p_tipo,
    'aberta',
    p_storage_path,
    '{}'::integer[],
    coalesce(p_payload, '{}'::jsonb),
    now() + interval '24 hours'
  ) returning id into v_id;

  v_acao := public.fabio_acao_json(v_id);
  return jsonb_build_object(
    'ok', true,
    'codigo', 'acao_criada',
    'acao', v_acao,
    'dados', '{}'::jsonb
  );
exception when unique_violation then
  select id into v_id
    from public.fabio_acoes_pendentes
   where wa_message_id = p_wa_message_id;
  if v_id is not null then
    return jsonb_build_object(
      'ok', true,
      'codigo', 'acao_existente',
      'acao', public.fabio_acao_json(v_id)
    );
  end if;
  return jsonb_build_object('ok', false, 'codigo', 'acao_concorrente');
end;
$function$;

revoke all on function public.fabio_iniciar_acao(integer, text, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.fabio_iniciar_acao(integer, text, text, text, jsonb)
  to service_role;
-- 096-ACAO-START-CHOOSER-FIM
