-- Contrato do upsert de recibo contra o indice unico PARCIAL.
--
-- ESTE TESTE JA EXISTIA E NUNCA RODOU. Nasceu como
-- `097-registro-recibo-partial-conflict.test.sql` -- nome que nao casa com o da
-- migration -- e o runner agregado pareia por nome, entao ele ficou invisivel.
-- Alem disso vinha com `begin;`/`rollback;` proprios, e o runner e o dono da
-- transacao. Duas camadas de silencio sobre a MESMA guarda que ja tinha
-- deixado a producao passar por um incidente real:
--
--   12/08 00:40 UTC -- `notify_worker_registro_recibo_entregue_mas_nao_fechado`,
--   status `delivered_unclosed`: o recibo foi ENTREGUE ao professor 10 e a
--   funcao que fecha quebrou com 42P10. A notificacao so nao virou duplicata
--   porque um caminho de recuperacao a fechou com o marcador sintetico
--   `recovered-delivered-unclosed`.
--
-- A causa: `fabio_chat_mensagens` tem indice unico PARCIAL
-- (`fcm_wa_msg_uq ... where wa_message_id is not null`), e `ON CONFLICT
-- (wa_message_id)` sem o mesmo predicado nao consegue inferir o indice. Indice
-- unico e ON CONFLICT sao UM contrato so -- lição que esta casa ja pagou antes.
--
-- Renomeado e convertido ao formato da casa em 13/08/2026, preservando
-- exatamente o que ele afirmava.

create temporary table _recibo_conflict_res(caso text, ok boolean, detalhe text)
on commit drop;

create or replace function pg_temp.checar_recibo_conflict(p_caso text, p_ok boolean, p_detalhe text)
returns void
language plpgsql
as $$
begin
  insert into _recibo_conflict_res values (p_caso, coalesce(p_ok, false), p_detalhe);
end
$$;

do $$
declare
  v_professor_id integer;
  v_key text := 'zztest-recibo-partial-conflict-' || gen_random_uuid()::text;
  v_first uuid;
  v_second uuid;
begin
  select id into v_professor_id from public.professores order by id limit 1;

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

  perform pg_temp.checar_recibo_conflict(
    'upsert reaproveita a mesma linha em vez de criar a segunda',
    v_first is not distinct from v_second,
    format('primeira=%s segunda=%s', v_first, v_second)
  );

  perform pg_temp.checar_recibo_conflict(
    'upsert atualiza o conteudo da linha existente',
    (select content from public.fabio_chat_mensagens where id = v_first) = 'segundo',
    coalesce((select content from public.fabio_chat_mensagens where id = v_first), '<NULL>')
  );

  perform pg_temp.checar_recibo_conflict(
    'wa_message_id nao duplica',
    (select count(*) from public.fabio_chat_mensagens where wa_message_id = v_key) = 1,
    (select count(*)::text from public.fabio_chat_mensagens where wa_message_id = v_key)
  );

  -- A guarda que faltava no incidente: o indice E parcial, e quem esquecer o
  -- predicado no ON CONFLICT nao consegue inferi-lo.
  perform pg_temp.checar_recibo_conflict(
    'o indice unico de wa_message_id e PARCIAL (o predicado e obrigatorio)',
    exists (
      select 1 from pg_index i
       where i.indrelid = 'public.fabio_chat_mensagens'::regclass
         and i.indisunique
         and i.indpred is not null
         and pg_get_indexdef(i.indexrelid) ilike '%wa_message_id%'
    ),
    'fcm_wa_msg_uq deve existir como unico parcial'
  );

  -- ESTE PASSO NASCEU DE UM MUTANTE SOBREVIVENTE (13/08/2026).
  -- Os passos acima reproduzem o upsert INLINE, entao provam o comportamento
  -- do indice -- mas nao tocam em `fabio_concluir_registro_recibo`. Apagar o
  -- predicado DENTRO da funcao passava despercebido: o mutante que reintroduz
  -- exatamente o defeito de 12/08 sobrevivia. E a propria funcao que precisa
  -- carregar o predicado, e e isso que se cobra aqui.
  perform pg_temp.checar_recibo_conflict(
    'a funcao que fecha o recibo carrega o predicado do indice parcial',
    (select pg_get_functiondef(p.oid)
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname = 'fabio_concluir_registro_recibo')
      ilike '%on conflict (wa_message_id) where wa_message_id is not null%',
    coalesce((select substring(pg_get_functiondef(p.oid) from 'on conflict[^\n]*')
                from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where n.nspname = 'public'
                 and p.proname = 'fabio_concluir_registro_recibo'), '<NULL>')
  );
end
$$;

select json_build_object(
  'teste', '20260812004430-fix-registro-recibo-partial-conflict',
  'falhas', (select count(*) from _recibo_conflict_res where not ok),
  'detalhe', coalesce((select json_agg(json_build_object(
    'passo', caso, 'esperado', 'ok', 'obtido', coalesce(detalhe, '<NULL>'))
  ) from _recibo_conflict_res where not ok), '[]'::json)
) as resumo;
