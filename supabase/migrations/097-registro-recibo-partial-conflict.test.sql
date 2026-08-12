begin;

do $test$
declare
  v_professor_id integer;
  v_key text := 'zztest-recibo-partial-conflict-' || gen_random_uuid()::text;
  v_first uuid;
  v_second uuid;
begin
  select id into v_professor_id from public.professores order by id limit 1;
  if v_professor_id is null then
    raise exception 'fixture_professor_ausente';
  end if;

  insert into public.fabio_chat_mensagens(
    identidade_tipo, role, kind, content, channel, professor_id, wa_message_id
  ) values (
    'professor', 'fabio', 'text', 'primeiro', 'whatsapp', v_professor_id, v_key
  ) returning id into v_first;

  insert into public.fabio_chat_mensagens(
    identidade_tipo, role, kind, content, channel, professor_id, wa_message_id
  ) values (
    'professor', 'fabio', 'text', 'segundo', 'whatsapp', v_professor_id, v_key
  )
  on conflict (wa_message_id) where wa_message_id is not null do update
     set content = excluded.content
  returning id into v_second;

  if v_first is distinct from v_second then
    raise exception 'upsert_criou_segunda_linha';
  end if;
  if (select content from public.fabio_chat_mensagens where id = v_first) <> 'segundo' then
    raise exception 'upsert_nao_atualizou';
  end if;
  if (select count(*) from public.fabio_chat_mensagens where wa_message_id = v_key) <> 1 then
    raise exception 'wa_message_id_duplicado';
  end if;
end
$test$;

rollback;
