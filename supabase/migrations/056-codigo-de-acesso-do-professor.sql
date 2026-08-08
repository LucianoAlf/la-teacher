-- 056 — o código de acesso do professor
--
-- O professor entra no app com o WhatsApp dele e um código de 6 dígitos. Sem
-- senha: ele já conversa com o Fábio naquele número todo dia, e senha é a
-- primeira coisa que 44 pessoas vão esquecer numa segunda-feira de manhã.
--
-- Molde: `send-magic-link` do LA Organizer, que já roda com gente de verdade.
--
-- ── POR QUE A REGRA MORA AQUI E NÃO NA EDGE FUNCTION ───────────────────────
-- A tentação era deixar o limite de tentativas no TypeScript, onde a chamada
-- acontece. Mas regra que mora só na edge function não tem como ser testada
-- com mutante — e este é o guarda que impede alguém que conhece o número de um
-- professor de encher o WhatsApp dele de código. Guarda sem carrasco é
-- decoração, e essa lição já custou caro aqui.
--
-- Então a edge function só pergunta: "posso mandar?" e registra o que fez. Quem
-- decide é o banco.
--
-- Teste: 056-codigo-de-acesso-do-professor.test.sql
-- Mutantes: scripts/mutantes-056.mjs

create table if not exists public.professor_acesso_codigos (
  id            uuid primary key default gen_random_uuid(),
  professor_id  integer references public.professores(id),
  telefone      text not null,
  email         text,
  status        text not null default 'enviado'
                check (status in ('enviado', 'falhou', 'bloqueado')),
  ip_hint       text,
  user_agent    text,
  criado_em     timestamptz not null default now(),
  expira_em     timestamptz
);

comment on table public.professor_acesso_codigos is
  'Rastro de cada pedido de código de acesso. Serve de auditoria e de base pro '
  'limite: sem ele, quem souber o número de um professor enche o WhatsApp dele.';

create index if not exists ix_professor_acesso_codigos_tel
  on public.professor_acesso_codigos (telefone, criado_em desc);

alter table public.professor_acesso_codigos enable row level security;
-- Sem policy: ninguém lê pelo PostgREST. Só a edge function, com service_role,
-- que ignora RLS. Tabela de segurança não é tabela de consulta.
revoke all on table public.professor_acesso_codigos from public, anon, authenticated;

-- ── As variantes do número brasileiro ──────────────────────────────────────
-- O mesmo número aparece de quatro jeitos: com ou sem o 55 do país, com ou sem
-- o 9 do celular. O cadastro tem de um jeito, o professor digita de outro, e a
-- busca por igualdade falha em silêncio — que é o pior tipo de falha, porque a
-- tela diz "não consegui enviar" e todo mundo vai procurar defeito no WhatsApp.
create or replace function public.fn_variantes_telefone_br(p_numero text)
returns text[]
language plpgsql
immutable
as $function$
declare
  d       text := regexp_replace(coalesce(p_numero, ''), '\D', '', 'g');
  local   text;
  saida   text[] := '{}';
begin
  if length(d) < 8 then
    return case when d = '' then '{}'::text[] else array[d] end;
  end if;

  saida := array[d];
  local := d;

  if left(d, 2) = '55' and length(d) >= 12 then
    local := substr(d, 3);
    saida := saida || local;
  elsif left(d, 2) <> '55' then
    saida := saida || ('55' || d);
  end if;

  -- Celular BR: DDD + 9 + 8 dígitos (11 no total) ou DDD + 8 (padrão antigo).
  if length(local) = 11 and substr(local, 3, 1) = '9' then
    saida := saida || (left(local, 2) || substr(local, 4));
    saida := saida || ('55' || left(local, 2) || substr(local, 4));
  elsif length(local) = 10 then
    saida := saida || (left(local, 2) || '9' || substr(local, 3));
    saida := saida || ('55' || left(local, 2) || '9' || substr(local, 3));
  end if;

  return array(select distinct unnest(saida));
end
$function$;

-- ── Quem pode pedir código ─────────────────────────────────────────────────
create or replace function public.fn_pedir_codigo_de_acesso(
  p_telefone   text,
  p_ip_hint    text default null,
  p_user_agent text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_digitos   text;
  v_variantes text[];
  v_prof      record;
  v_recentes  integer;
begin
  v_digitos := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
  if length(v_digitos) < 10 then
    return jsonb_build_object('ok', false, 'motivo', 'telefone_invalido');
  end if;

  -- VARIANTES do número. Não é zelo: o cadastro tem número com e sem 55, e o
  -- professor digita como quiser. No LA Organizer isso foi conserto de campo
  -- (Sprint 29) — a busca falhava em silêncio e a tela dizia "não consegui
  -- enviar", mandando todo mundo procurar defeito no WhatsApp.
  v_variantes := public.fn_variantes_telefone_br(v_digitos);

  select p.id, p.nome, p.nome_preferido, p.telefone_whatsapp, u.email, u.id as usuario_id
    into v_prof
    from public.professores p
    left join public.usuarios u on u.id = p.usuario_id
   where p.ativo
     and regexp_replace(coalesce(p.telefone_whatsapp, ''), '\D', '', 'g') = any (v_variantes)
   order by p.usuario_id nulls last
   limit 1;

  if not found then
    -- Resposta deliberadamente igual à de "não liberado": quem está sondando
    -- números não descobre quais existem na escola.
    return jsonb_build_object('ok', false, 'motivo', 'nao_encontrado');
  end if;

  if v_prof.usuario_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'nao_encontrado');
  end if;

  -- Limite: 3 pedidos em 15 minutos por telefone. Quem errou o código duas
  -- vezes ainda consegue a terceira; quem está atacando para na quarta.
  select count(*) into v_recentes
    from public.professor_acesso_codigos c
   where c.telefone = v_prof.telefone_whatsapp
     and c.status = 'enviado'
     and c.criado_em > now() - interval '15 minutes';

  if v_recentes >= 3 then
    insert into public.professor_acesso_codigos
      (professor_id, telefone, email, status, ip_hint, user_agent)
    values (v_prof.id, v_prof.telefone_whatsapp, v_prof.email, 'bloqueado', p_ip_hint, p_user_agent);
    return jsonb_build_object('ok', false, 'motivo', 'muitas_tentativas', 'espere_min', 15);
  end if;

  return jsonb_build_object(
    'ok',            true,
    'professor_id',  v_prof.id,
    'primeiro_nome', coalesce(nullif(btrim(v_prof.nome_preferido), ''),
                              split_part(btrim(v_prof.nome), ' ', 1)),
    'telefone',      v_prof.telefone_whatsapp,   -- o do CADASTRO, não o digitado
    'email',         v_prof.email);
end
$function$;

revoke all on function public.fn_pedir_codigo_de_acesso(text, text, text) from public, anon, authenticated;
grant execute on function public.fn_pedir_codigo_de_acesso(text, text, text) to service_role;

-- ── O rastro do que foi enviado ────────────────────────────────────────────
create or replace function public.fn_registrar_codigo_enviado(
  p_professor_id integer,
  p_telefone     text,
  p_email        text,
  p_enviou       boolean,
  p_ip_hint      text default null,
  p_user_agent   text default null
) returns uuid
language sql
security definer
set search_path to 'public'
as $function$
  insert into public.professor_acesso_codigos
    (professor_id, telefone, email, status, ip_hint, user_agent, expira_em)
  values (p_professor_id, p_telefone, p_email,
          case when p_enviou then 'enviado' else 'falhou' end,
          p_ip_hint, p_user_agent, now() + interval '1 hour')
  returning id;
$function$;

revoke all on function public.fn_registrar_codigo_enviado(integer, text, text, boolean, text, text) from public, anon, authenticated;
grant execute on function public.fn_registrar_codigo_enviado(integer, text, text, boolean, text, text) to service_role;
