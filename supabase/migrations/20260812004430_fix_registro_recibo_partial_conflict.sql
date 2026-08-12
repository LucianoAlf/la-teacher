-- Close registro receipt outbox rows against the existing partial unique index.
-- fcm_wa_msg_uq is UNIQUE (wa_message_id) WHERE wa_message_id IS NOT NULL;
-- PostgreSQL requires the same predicate in the ON CONFLICT inference clause.

create or replace function public.fabio_concluir_registro_recibo(
  p_notificacao_id uuid,
  p_lease_token uuid,
  p_envio_recibo text,
  p_corpo text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_notificacao public.fabio_notificacoes%rowtype;
  v_chat_id uuid;
  v_envio_recibo text := nullif(btrim(p_envio_recibo), '');
  v_corpo text := nullif(btrim(p_corpo), '');
begin
  if p_notificacao_id is null or p_lease_token is null then
    return jsonb_build_object('ok', false, 'codigo', 'lease_obrigatorio');
  end if;
  if v_envio_recibo is null or v_corpo is null then
    return jsonb_build_object('ok', false, 'codigo', 'recibo_e_corpo_obrigatorios');
  end if;

  select * into v_notificacao
    from public.fabio_notificacoes n
   where n.id = p_notificacao_id
     and n.tipo = 'registro_recibo'
     and n.referencia_tipo = 'registro_aula'
     and n.canal = 'whatsapp'
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'recibo_nao_encontrado');
  end if;
  if v_notificacao.status = 'enviada' then
    return jsonb_build_object(
      'ok', v_notificacao.envio_recibo = v_envio_recibo and v_notificacao.corpo = v_corpo,
      'ja_enviado', true,
      'codigo', case when v_notificacao.envio_recibo = v_envio_recibo
                         and v_notificacao.corpo = v_corpo
                     then 'replay_idempotente' else 'recibo_ja_concluido' end
    );
  end if;
  if v_notificacao.status is distinct from 'processando'
     or v_notificacao.lease_token is distinct from p_lease_token
     or v_notificacao.lease_expira_em is null
     or v_notificacao.lease_expira_em <= now() then
    return jsonb_build_object('ok', false, 'codigo', 'lease_invalido');
  end if;

  insert into public.fabio_chat_mensagens(
    identidade_tipo, role, kind, content, channel, professor_id, wa_message_id
  ) values (
    'professor', 'fabio', 'text', v_corpo, 'whatsapp',
    v_notificacao.professor_id, v_envio_recibo
  )
  on conflict (wa_message_id) where wa_message_id is not null do update
     set kind = excluded.kind,
         content = excluded.content
   where public.fabio_chat_mensagens.professor_id = excluded.professor_id
     and public.fabio_chat_mensagens.role = 'fabio'
     and public.fabio_chat_mensagens.channel = 'whatsapp'
  returning id into v_chat_id;
  if v_chat_id is null then
    raise exception 'recibo_contexto_conflitante';
  end if;

  update public.fabio_notificacoes
     set status = 'enviada',
         enviada_em = now(),
         envio_recibo = v_envio_recibo,
         corpo = v_corpo,
         lease_token = null,
         lease_expira_em = null,
         last_error = null
   where id = v_notificacao.id;

  return jsonb_build_object(
    'ok', true,
    'notificacao_id', v_notificacao.id,
    'chat_mensagem_id', v_chat_id,
    'envio_recibo', v_envio_recibo
  );
end
$function$;

revoke all on function public.fabio_concluir_registro_recibo(uuid, uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.fabio_concluir_registro_recibo(uuid, uuid, text, text)
  to service_role;

comment on function public.fabio_concluir_registro_recibo(uuid, uuid, text, text) is
  'Fecha recibo uma vez e espelha a mensagem usando o indice parcial fcm_wa_msg_uq.';
