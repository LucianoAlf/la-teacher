-- A identidade do professor vira uma CAPACIDADE curta, não um argumento.
--
-- POR QUE ISTO EXISTE (medido em 17/08/2026):
--   - o MCP que a casa já tinha recebe `professor_id: int` como argumento — ou
--     seja, quem escolhe de quem falar é o MODELO;
--   - o papel `fabio_agent` do postgres-mcp tem `rolbypassrls = true` e SELECT
--     em 412 tabelas (financeiro e anamnese inclusos);
--   - o canal `api_server` é o MESMO do professor e do admin, então canal não
--     pode ser fronteira;
--   - a descoberta de MCP do Hermes é global e sem contexto de sessão
--     (`hermes_cli/mcp_startup.py`), então o servidor não tem como saber
--     sozinho com quem o Fábio está falando.
--
-- Sobra a única coisa que o CHAMADOR sabe e o modelo não: quem mandou a
-- mensagem. O bridge lê isso da linha em `fabio_chat_mensagens` — não do texto,
-- que é justamente o que um modelo consegue inventar.
--
-- O que o token é: opaco, curto de vida, com número de usos limitado, e
-- guardado aqui **só como hash**. Vazamento desta tabela não vira capacidade.
--
-- O que o token NÃO é: autenticação de pessoa. É uma capacidade sobre a vida
-- letiva de UM professor, válida por minutos. Financeiro e dados de outro
-- professor não estão do outro lado dela — não existe função que os devolva.

create table if not exists public.fabio_agente_sessoes (
  id uuid primary key default gen_random_uuid(),
  -- Só o hash. O token cru existe uma vez, na resposta da cunhagem.
  token_hash text not null unique,
  professor_id integer not null,
  -- De qual mensagem esta capacidade nasceu: dá rastro sem guardar segredo.
  origem_mensagem_id uuid,
  criado_em timestamptz not null default now(),
  expira_em timestamptz not null,
  usos integer not null default 0,
  max_usos integer not null default 8,
  revogado_em timestamptz,
  constraint fabio_agente_sessoes_max_usos_ck check (max_usos between 1 and 32),
  constraint fabio_agente_sessoes_janela_ck check (expira_em > criado_em)
);

comment on table public.fabio_agente_sessoes is
  'Capacidade curta que carrega a identidade do professor ate a ferramenta. Guarda HASH, nunca o token. Ver spec 2026-08-18-fabio-ferramenta-identidade-caller.';

create index if not exists fabio_agente_sessoes_professor_idx
  on public.fabio_agente_sessoes (professor_id, criado_em desc);

alter table public.fabio_agente_sessoes enable row level security;
-- Sem policy: ninguem alcanca a tabela por PostgREST. Quem le e escreve sao as
-- funcoes `security definer` abaixo.

-- ── Cunhagem: só o bridge, com a chave de serviço ────────────────────────────
create or replace function public.fabio_agente_cunhar_sessao(
  p_professor_id integer,
  p_mensagem_id uuid default null,
  p_ttl_minutos integer default 10,
  p_max_usos integer default 8
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'extensions'
as $function$
declare
  v_token text;
  v_hash text;
  v_id uuid;
  v_expira timestamptz;
  v_ttl integer := least(greatest(coalesce(p_ttl_minutos, 10), 1), 60);
  v_usos integer := least(greatest(coalesce(p_max_usos, 8), 1), 32);
begin
  if p_professor_id is null then
    raise exception 'professor_obrigatorio';
  end if;
  if not exists (select 1 from public.professores p where p.id = p_professor_id) then
    raise exception 'professor_inexistente';
  end if;

  -- base64url: sem '+', '/' nem '=' — o token atravessa prompt e JSON sem
  -- escapar e sem virar duas strings diferentes no meio do caminho.
  v_token := translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/=', '-_');
  v_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');
  v_expira := now() + make_interval(mins => v_ttl);

  insert into public.fabio_agente_sessoes
         (token_hash, professor_id, origem_mensagem_id, expira_em, max_usos)
  values (v_hash, p_professor_id, p_mensagem_id, v_expira, v_usos)
  returning id into v_id;

  -- O token cru sai daqui UMA vez e nunca mais. `assinatura` e o que pode ser
  -- logado (exigencia do Alf: log leva hash curto, jamais o token).
  return jsonb_build_object(
    'ok', true,
    'sessao_id', v_id,
    'token', v_token,
    'assinatura', left(v_hash, 8),
    'expira_em', v_expira,
    'max_usos', v_usos
  );
end
$function$;

comment on function public.fabio_agente_cunhar_sessao(integer, uuid, integer, integer) is
  'Cunha a capacidade do professor. Devolve o token CRU uma unica vez; a tabela guarda so o hash. Logar apenas a assinatura.';

-- ── Resolução: consumida por dentro, nunca pelo agente ───────────────────────
create or replace function public.fabio_agente_resolver(p_token text)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'extensions'
as $function$
declare
  v_hash text;
  v_sessao public.fabio_agente_sessoes%rowtype;
begin
  if nullif(btrim(coalesce(p_token, '')), '') is null then
    return jsonb_build_object('ok', false, 'codigo', 'token_ausente');
  end if;

  v_hash := encode(extensions.digest(btrim(p_token), 'sha256'), 'hex');

  -- `for update`: duas ferramentas na mesma resposta nao podem consumir o
  -- mesmo uso duas vezes e passar do teto sem ninguem ver.
  select * into v_sessao
    from public.fabio_agente_sessoes
   where token_hash = v_hash
   for update;

  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'token_desconhecido');
  end if;
  if v_sessao.revogado_em is not null then
    return jsonb_build_object('ok', false, 'codigo', 'token_revogado');
  end if;
  if v_sessao.expira_em <= now() then
    return jsonb_build_object('ok', false, 'codigo', 'token_expirado');
  end if;
  if v_sessao.usos >= v_sessao.max_usos then
    return jsonb_build_object('ok', false, 'codigo', 'token_esgotado');
  end if;

  update public.fabio_agente_sessoes
     set usos = usos + 1
   where id = v_sessao.id;

  return jsonb_build_object(
    'ok', true,
    'professor_id', v_sessao.professor_id,
    'assinatura', left(v_hash, 8),
    'usos', v_sessao.usos + 1,
    'max_usos', v_sessao.max_usos
  );
end
$function$;

comment on function public.fabio_agente_resolver(text) is
  'Resolve a capacidade em professor_id, consumindo um uso. Nao e exposta ao agente: quem chama sao as RPCs escopadas (security definer).';

create or replace function public.fabio_agente_revogar_sessao(p_sessao_id uuid)
returns jsonb
language sql
volatile
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  update public.fabio_agente_sessoes
     set revogado_em = coalesce(revogado_em, now())
   where id = p_sessao_id
  returning jsonb_build_object('ok', true, 'sessao_id', id, 'revogado_em', revogado_em);
$function$;

-- ── Portas: nada disso e alcancavel pelo app nem pelo agente ─────────────────
revoke all on function public.fabio_agente_cunhar_sessao(integer, uuid, integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.fabio_agente_cunhar_sessao(integer, uuid, integer, integer)
  to service_role;

-- `resolver` NAO recebe grant nenhum de proposito: quem a usa sao as RPCs
-- escopadas, que sao `security definer` e rodam como dono. Assim nem o papel do
-- agente consegue chamar a resolucao direto pra descobrir de quem e um token.
revoke all on function public.fabio_agente_resolver(text)
  from public, anon, authenticated, service_role;

revoke all on function public.fabio_agente_revogar_sessao(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.fabio_agente_revogar_sessao(uuid) to service_role;

revoke all on table public.fabio_agente_sessoes from public, anon, authenticated;
