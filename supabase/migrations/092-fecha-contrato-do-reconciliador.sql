-- 092 — fecha o contrato entre fila, reconciliador e limpeza do Storage
--
-- A 091 expunha o status do audio, mas omitia o registro criado pelo pipeline.
-- Sem esse vinculo o worker poderia saber que terminou sem ter um alvo seguro
-- para a confirmacao. Esta migration tambem transforma a limpeza em uma prova
-- de banco: o bridge so remove o blob depois de receber pode_remover=true.

drop function if exists public.fabio_status_audio_fila(integer, uuid);

create function public.fabio_status_audio_fila(
  p_professor_id integer,
  p_audio_id uuid
) returns table(
  audio_id uuid,
  registro_id uuid,
  status text,
  tentativas integer,
  tem_erro boolean,
  criado_em timestamptz,
  atualizado_em timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select f.id,
         r.id,
         f.status,
         f.tentativas,
         (f.erro is not null),
         f.criado_em,
         f.atualizado_em
    from public.fabio_fila_audios f
    left join lateral (
      select r0.id
        from public.fabio_registros_aula r0
       where r0.audio_id = f.id
         and r0.parent_id is null
         and r0.professor_id = f.professor_id
       order by r0.criado_em desc, r0.id desc
       limit 1
    ) r on true
   where f.id = p_audio_id
     and f.professor_id = p_professor_id;
$function$;

create or replace function public.fabio_concluir_reconciliacao(
  p_acao_id uuid,
  p_lease_token uuid,
  p_evento text,
  p_dados jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_a public.fabio_acoes_pendentes%rowtype;
  v_registro_id uuid;
  v_resultado jsonb;
begin
  select * into v_a
    from public.fabio_acoes_pendentes
   where id = p_acao_id
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'acao_nao_encontrada');
  end if;

  if v_a.lease_token is distinct from p_lease_token
     or v_a.lease_expira_em < now() then
    return jsonb_build_object('ok', false, 'codigo', 'lease_invalido');
  end if;

  if p_evento not in (
    'rascunho_pronto', 'falha_temporaria', 'falha_terminal',
    'confirmacao_solicitada'
  ) then
    return jsonb_build_object('ok', false, 'codigo', 'evento_reconciliacao_invalido');
  end if;

  if p_evento = 'rascunho_pronto' then
    if v_a.tipo <> 'processando_audio' or v_a.estado <> 'processando' then
      return jsonb_build_object(
        'ok', false,
        'codigo', 'transicao_reconciliacao_invalida',
        'acao', public.fabio_acao_json(v_a.id)
      );
    end if;

    v_registro_id := nullif(p_dados ->> 'registro_id', '')::uuid;
    if v_registro_id is null or not exists (
      select 1
        from public.fabio_registros_aula r
       where r.id = v_registro_id
         and r.parent_id is null
         and r.professor_id = v_a.professor_id
         and r.audio_id = v_a.audio_id
         and r.status in ('rascunho', 'aguardando_confirmacao')
    ) then
      return jsonb_build_object(
        'ok', false,
        'codigo', 'rascunho_invalido',
        'acao', public.fabio_acao_json(v_a.id)
      );
    end if;
  end if;

  update public.fabio_acoes_pendentes
     set tipo = case
                  when p_evento in ('rascunho_pronto', 'confirmacao_solicitada')
                    then 'confirmar_registro'
                  else tipo
                end,
         estado = case
                    when p_evento in ('rascunho_pronto', 'confirmacao_solicitada')
                      then 'aberta'
                    when p_evento = 'falha_terminal' then 'erro'
                    else 'processando'
                  end,
         registro_id = case
                         when p_evento = 'rascunho_pronto' then v_registro_id
                         else registro_id
                       end,
         payload = case
                     when jsonb_typeof(p_dados -> 'tentativas') = 'number' then
                       payload || jsonb_build_object(
                         'reconciliador',
                         case
                           when jsonb_typeof(payload -> 'reconciliador') = 'object'
                             then payload -> 'reconciliador'
                           else '{}'::jsonb
                         end || jsonb_build_object(
                           'tentativas', (p_dados ->> 'tentativas')::integer
                         )
                       )
                     else payload
                   end,
         expira_em = case
                       when p_evento in ('rascunho_pronto', 'confirmacao_solicitada')
                         then now() + interval '24 hours'
                       else null
                     end,
         erro = case when p_evento like 'falha_%' then p_dados ->> 'erro' else null end,
         lease_token = null,
         lease_expira_em = null,
         atualizado_em = now(),
         encerrado_em = case when p_evento = 'falha_terminal' then now() else null end
   where id = v_a.id;

  v_resultado := jsonb_build_object(
    'ok', true,
    'codigo', 'reconciliacao_concluida',
    'acao', public.fabio_acao_json(v_a.id),
    'dados', coalesce(p_dados, '{}'::jsonb)
  );
  insert into public.fabio_acao_eventos(acao_id, wa_message_id, evento, resultado)
  values (
    v_a.id,
    'reconciliacao:' || v_a.id::text || ':' || extract(epoch from clock_timestamp())::bigint,
    p_evento,
    v_resultado
  );
  return v_resultado;
end;
$function$;

create or replace function public.fabio_provar_limpeza(
  p_acao_id uuid,
  p_storage_path text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_a public.fabio_acoes_pendentes%rowtype;
begin
  select * into v_a
    from public.fabio_acoes_pendentes
   where id = p_acao_id;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'acao_nao_encontrada', 'pode_remover', false);
  end if;

  if p_storage_path is null or btrim(p_storage_path) = ''
     or v_a.storage_path is distinct from p_storage_path then
    return jsonb_build_object('ok', false, 'codigo', 'storage_path_divergente', 'pode_remover', false);
  end if;

  if v_a.estado not in ('cancelada', 'expirada', 'erro') then
    return jsonb_build_object('ok', false, 'codigo', 'limpeza_nao_elegivel', 'pode_remover', false);
  end if;

  if exists (
    select 1
      from public.fabio_acoes_pendentes a
     where a.id <> v_a.id
       and a.storage_path = p_storage_path
       and a.estado in ('aberta', 'processando', 'adiada')
  ) then
    return jsonb_build_object(
      'ok', true,
      'codigo', 'limpeza_reprovada',
      'motivo', 'acao_ativa_referencia_storage',
      'pode_remover', false
    );
  end if;

  if exists (
    select 1
      from public.fabio_fila_audios f
      join public.fabio_registros_aula r on r.audio_id = f.id
     where f.storage_path = p_storage_path
       and r.status in ('confirmado', 'gravado_emusys')
  ) then
    return jsonb_build_object(
      'ok', true,
      'codigo', 'limpeza_reprovada',
      'motivo', 'registro_confirmado_referencia_storage',
      'pode_remover', false
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'codigo', 'limpeza_provada',
    'pode_remover', true,
    'storage_path', p_storage_path
  );
end;
$function$;

create or replace function public.fabio_concluir_limpeza(
  p_acao_id uuid,
  p_lease_token uuid,
  p_resultado jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_a public.fabio_acoes_pendentes%rowtype;
  v_prova jsonb;
begin
  select * into v_a
    from public.fabio_acoes_pendentes
   where id = p_acao_id
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'acao_nao_encontrada');
  end if;
  if v_a.lease_token is distinct from p_lease_token
     or v_a.lease_expira_em < now() then
    return jsonb_build_object('ok', false, 'codigo', 'lease_invalido');
  end if;

  v_prova := public.fabio_provar_limpeza(v_a.id, v_a.storage_path);
  if coalesce((v_prova ->> 'pode_remover')::boolean, false) is not true then
    return jsonb_build_object(
      'ok', false,
      'codigo', 'limpeza_insegura',
      'prova', v_prova
    );
  end if;

  update public.fabio_acoes_pendentes
     set payload = payload || jsonb_build_object(
       'limpeza', coalesce(p_resultado, '{}'::jsonb),
       'prova', v_prova
     ),
         lease_token = null,
         lease_expira_em = null,
         atualizado_em = now()
   where id = v_a.id;
  return jsonb_build_object(
    'ok', true,
    'codigo', 'limpeza_concluida',
    'acao', public.fabio_acao_json(v_a.id),
    'prova', v_prova
  );
end;
$function$;

revoke all on function public.fabio_status_audio_fila(integer, uuid)
  from public, anon, authenticated;
revoke all on function public.fabio_concluir_reconciliacao(uuid, uuid, text, jsonb)
  from public, anon, authenticated;
revoke all on function public.fabio_provar_limpeza(uuid, text)
  from public, anon, authenticated;
revoke all on function public.fabio_concluir_limpeza(uuid, uuid, jsonb)
  from public, anon, authenticated;

grant execute on function public.fabio_status_audio_fila(integer, uuid) to service_role;
grant execute on function public.fabio_concluir_reconciliacao(uuid, uuid, text, jsonb) to service_role;
grant execute on function public.fabio_provar_limpeza(uuid, text) to service_role;
grant execute on function public.fabio_concluir_limpeza(uuid, uuid, jsonb) to service_role;
