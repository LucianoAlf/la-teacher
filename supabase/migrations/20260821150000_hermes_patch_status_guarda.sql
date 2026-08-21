-- Trava do patch do Hermes: o guard root (vps/hermes-patches/hermes-patch-guard.sh)
-- varre os agentes e reporta aqui; o edge monitor-saude-fabio lê e alerta no
-- WhatsApp se algum estiver sem patch OU se o próprio guard parou de rodar (status
-- velho). Ver vps/hermes-patches/README.md.
create table if not exists public.hermes_patch_status (
  agente      text primary key,
  patch_nome  text not null,
  patched     boolean not null,
  detalhe     text,
  checado_em  timestamptz not null default now()
);

comment on table public.hermes_patch_status is
  'Estado do patch local do Hermes por agente (Fabio/Mila/Lia/...). Escrito por um cron root (hermes-patch-guard.sh) e lido por monitor-saude-fabio. Se patched=false ou checado_em velho, alerta no WhatsApp.';

-- RPC de upsert usada pelo guard root (via REST com a service role).
create or replace function public.hermes_patch_status_reportar(
  p_agente text, p_patch text, p_patched boolean, p_detalhe text default null
) returns void
language sql security definer set search_path to 'public'
as $$
  insert into public.hermes_patch_status(agente, patch_nome, patched, detalhe, checado_em)
  values (btrim(p_agente), btrim(p_patch), p_patched, left(p_detalhe, 300), now())
  on conflict (agente) do update
    set patch_nome = excluded.patch_nome,
        patched    = excluded.patched,
        detalhe    = excluded.detalhe,
        checado_em = now();
$$;
