-- O áudio guardado entra sozinho quando a vez dele chega.
--
-- 15/08/2026, segunda metade do incidente do Isaque. O `5867be0` fez o Fábio
-- PARAR DE DESTRUIR o segundo áudio: chegando com uma ação aberta, os bytes
-- passaram a subir pro Storage antes de a mensagem ser tratada como resposta
-- de texto. O que ele não fez foi retomar. O áudio ficava no bucket e a
-- promessa da resposta — *"assim que a gente fechar o anterior, ele entra"* —
-- não tinha ninguém pra cumprir. Promessa sem executor é a mesma família do
-- "salvei" que o Fábio dizia sem ter salvo.
--
-- O modelo é UMA ação aberta por professor (`fabio_iniciar_acao` recusa a
-- segunda) e isso não muda aqui: é ele que garante que o Fábio não fica
-- perguntando de três aulas ao mesmo tempo. O que faltava era uma fila de
-- espera do lado de fora dessa porta.
--
-- Três saídas foram consideradas:
--   (a) parquear no payload da ação — o áudio some junto quando a ação é
--       cancelada, e o payload vira um lugar onde mora estado de outra coisa;
--   (b) fechar a ação atual e recomeçar do áudio novo — DESCARTADA: vira
--       "perde todos menos o último", que é o defeito com outro nome;
--   (c) fila própria, FIFO por professor — é esta.
--
-- FIFO e não LIFO porque a ordem é a do trabalho do professor: ele gravou a
-- aula das 12h e depois a das 13h. Atender a de 13h primeiro faz a conversa
-- sobre a de 12h chegar depois do fato.
--
-- Idempotência pelo `wa_message_id`: o UAZAPI reentrega, e reentrega é a
-- mesma mensagem, não áudio novo. Índice único + ON CONFLICT são UM contrato.

create table if not exists public.fabio_audios_parqueados (
  id uuid primary key default gen_random_uuid(),
  professor_id integer not null,
  wa_message_id text not null,
  storage_path text not null,
  transcricao text,
  duracao_segundos integer not null default 0,
  criado_em timestamptz not null default now(),
  consumido_em timestamptz,
  consumido_por_acao uuid,
  descartado_em timestamptz,
  descartado_motivo text,
  constraint fabio_audios_parqueados_destino_unico
    check (consumido_em is null or descartado_em is null)
);

comment on table public.fabio_audios_parqueados is
  'Áudio que chegou pelo WhatsApp enquanto o professor tinha uma ação aberta. Fila de espera FIFO por professor, do lado de fora da trava de uma-ação-por-professor. Sai por consumo (virou ação) ou por descarte explícito — nunca some sozinho.';

create unique index if not exists uq_fabio_audio_parqueado_mensagem
  on public.fabio_audios_parqueados (professor_id, wa_message_id);

-- A consulta do worker é sempre "o mais antigo ainda em espera deste
-- professor". Índice parcial pela mesma condição.
create index if not exists idx_fabio_audio_parqueado_espera
  on public.fabio_audios_parqueados (professor_id, criado_em)
  where consumido_em is null and descartado_em is null;

alter table public.fabio_audios_parqueados enable row level security;

comment on constraint fabio_audios_parqueados_destino_unico
  on public.fabio_audios_parqueados is
  'Consumido E descartado ao mesmo tempo seria duas historias sobre o mesmo audio. O contrato e um destino so.';

-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.fabio_parquear_audio(
  p_professor_id integer,
  p_wa_message_id text,
  p_storage_path text,
  p_transcricao text default null,
  p_duracao_segundos integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_id uuid;
begin
  if p_professor_id is null or coalesce(btrim(p_wa_message_id), '') = ''
     or coalesce(btrim(p_storage_path), '') = '' then
    return jsonb_build_object('ok', false, 'erro', 'parametros_obrigatorios');
  end if;

  insert into public.fabio_audios_parqueados
    (professor_id, wa_message_id, storage_path, transcricao, duracao_segundos)
  values
    (p_professor_id, btrim(p_wa_message_id), btrim(p_storage_path),
     nullif(btrim(coalesce(p_transcricao, '')), ''), greatest(coalesce(p_duracao_segundos, 0), 0))
  on conflict (professor_id, wa_message_id) do nothing
  returning id into v_id;

  if v_id is null then
    -- Reentrega do UAZAPI. O áudio já está na fila (ou já foi atendido) —
    -- devolver ok=true com ja_existia deixa o chamador seguir sem tratar
    -- reentrega como falha.
    return jsonb_build_object('ok', true, 'ja_existia', true);
  end if;
  return jsonb_build_object('ok', true, 'ja_existia', false, 'id', v_id);
end
$function$;

comment on function public.fabio_parquear_audio(integer, text, text, text, integer) is
  'Põe na fila de espera o áudio que chegou com ação aberta. Idempotente por (professor, wa_message_id): reentrega do UAZAPI não vira segunda linha.';

create or replace function public.fabio_audio_parqueado_proximo(
  p_professor_id integer
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  select coalesce(
    (select jsonb_build_object(
              'id', a.id,
              'wa_message_id', a.wa_message_id,
              'storage_path', a.storage_path,
              'transcricao', coalesce(a.transcricao, ''),
              'duracao_segundos', a.duracao_segundos,
              'criado_em', a.criado_em)
       from public.fabio_audios_parqueados a
      where a.professor_id = p_professor_id
        and a.consumido_em is null
        and a.descartado_em is null
      order by a.criado_em, a.id
      limit 1),
    '{}'::jsonb);
$function$;

comment on function public.fabio_audio_parqueado_proximo(integer) is
  'O mais antigo áudio em espera do professor (FIFO — a ordem é a do trabalho dele). Devolve {} quando não há.';

create or replace function public.fabio_audio_parqueado_consumir(
  p_id uuid,
  p_acao_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_ok boolean;
begin
  update public.fabio_audios_parqueados
     set consumido_em = now(),
         consumido_por_acao = p_acao_id
   where id = p_id
     and consumido_em is null
     and descartado_em is null;
  get diagnostics v_ok = row_count;
  -- Carimbo atômico: dois processos no mesmo ciclo, só um consome. Sem isto o
  -- mesmo áudio viraria duas ações — que é o defeito oposto ao que a fila veio
  -- resolver.
  return jsonb_build_object('ok', coalesce(v_ok, false));
end
$function$;

comment on function public.fabio_audio_parqueado_consumir(uuid, uuid) is
  'Carimba o áudio como atendido. Devolve ok=false se alguém chegou antes — a trava contra virar duas ações mora aqui, não no chamador.';

create or replace function public.fabio_audio_parqueado_descartar(
  p_id uuid,
  p_motivo text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_ok boolean;
begin
  update public.fabio_audios_parqueados
     set descartado_em = now(),
         descartado_motivo = left(coalesce(p_motivo, 'sem_motivo'), 200)
   where id = p_id
     and consumido_em is null
     and descartado_em is null;
  get diagnostics v_ok = row_count;
  return jsonb_build_object('ok', coalesce(v_ok, false));
end
$function$;

comment on function public.fabio_audio_parqueado_descartar(uuid, text) is
  'Tira da fila sem virar ação, com motivo escrito. Um áudio que não serviu sai por aqui — some sozinho, nunca.';

-- ─────────────────────────────────────────────────────────────────────────────
-- Portas fechadas: quem fala com esta fila é o bridge, com service_role.

revoke all on public.fabio_audios_parqueados from public, anon, authenticated;
revoke all on function
  public.fabio_parquear_audio(integer, text, text, text, integer),
  public.fabio_audio_parqueado_proximo(integer),
  public.fabio_audio_parqueado_consumir(uuid, uuid),
  public.fabio_audio_parqueado_descartar(uuid, text)
  from public, anon, authenticated;

grant select, insert, update on public.fabio_audios_parqueados to service_role;
grant execute on function
  public.fabio_parquear_audio(integer, text, text, text, integer),
  public.fabio_audio_parqueado_proximo(integer),
  public.fabio_audio_parqueado_consumir(uuid, uuid),
  public.fabio_audio_parqueado_descartar(uuid, text)
  to service_role;
