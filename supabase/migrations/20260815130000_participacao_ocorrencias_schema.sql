-- Camada de ocorrência de participação (substituição) — SHADOW.
-- Onde o Fábio registra quem PARTICIPOU no lugar de quem, separado do roster
-- ESPERADO. Nada aqui toca presença/falta/financeiro/Emusys nesta fase.

create table if not exists public.fabio_participacao_ocorrencias (
  id uuid primary key default gen_random_uuid(),
  aula_operacional_id integer not null,
  aula_id integer not null,
  professor_id integer not null,
  aluno_matriculado_id integer not null,
  participante_real_id integer,
  participante_real_nome text,
  participante_real_telefone text,
  tipo text not null default 'substituicao',
  confianca text not null,
  metodo_extracao text not null,
  origem text not null,
  origem_message_id text,
  origem_transcricao text,
  supersede_ocorrencia_id uuid references public.fabio_participacao_ocorrencias(id),
  criado_em timestamptz not null default now(),
  constraint chk_participacao_tipo check (tipo = any (array['substituicao'])),
  constraint chk_participacao_confianca check (confianca = any (array['alta','media','baixa'])),
  constraint chk_participacao_metodo check (metodo_extracao = any (array['deterministico','llm'])),
  constraint chk_participacao_origem check (origem = any (array['whatsapp','manual_admin'])),
  constraint chk_participante_identificado
    check (participante_real_id is not null
           or coalesce(btrim(participante_real_nome), '') <> ''),
  constraint chk_matriculado_difere_participante
    check (participante_real_id is null or participante_real_id <> aluno_matriculado_id),
  constraint chk_origem_message_id
    check (origem <> 'whatsapp' or origem_message_id is not null)
);

comment on table public.fabio_participacao_ocorrencias is
  'Quem participou no lugar de quem (substituicao), separado do roster esperado. Append-only: fatos nunca mudam; correcao e linha nova com supersede_ocorrencia_id. SHADOW: nao toca presenca/falta/financeiro/Emusys.';

-- Idempotencia estrutural: a mesma mensagem do WhatsApp nao gera duas
-- candidatas vigentes pra mesma aula+matriculado.
create unique index if not exists uq_participacao_msg_vigente
  on public.fabio_participacao_ocorrencias (aula_operacional_id, aluno_matriculado_id, origem_message_id)
  where origem_message_id is not null and supersede_ocorrencia_id is null;

create table if not exists public.fabio_participacao_ocorrencia_eventos (
  id uuid primary key default gen_random_uuid(),
  ocorrencia_id uuid not null references public.fabio_participacao_ocorrencias(id),
  evento text not null,
  por_tipo text not null,
  por_id text,
  dados jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now(),
  constraint chk_participacao_evento
    check (evento = any (array['registrada','confirmada','validada','descartada','corrigida'])),
  constraint chk_participacao_por_tipo
    check (por_tipo = any (array['sistema','professor','coordenacao']))
);

create index if not exists idx_participacao_evento_ocorrencia
  on public.fabio_participacao_ocorrencia_eventos (ocorrencia_id, criado_em);

comment on table public.fabio_participacao_ocorrencia_eventos is
  'Ciclo de vida da ocorrencia (append-only). Estado atual = ultimo evento. registrada->candidata na view.';

-- Estado atual = ultimo evento. registrada aparece como candidata.
create or replace view public.vw_fabio_participacao_ocorrencia_estado as
select distinct on (e.ocorrencia_id)
  e.ocorrencia_id,
  case e.evento when 'registrada' then 'candidata' else e.evento end as estado_atual,
  e.criado_em as estado_em,
  e.por_tipo  as estado_por
from public.fabio_participacao_ocorrencia_eventos e
order by e.ocorrencia_id, e.criado_em desc, e.id desc;

comment on view public.vw_fabio_participacao_ocorrencia_estado is
  'Fonte unica do estado atual de cada ocorrencia. registrada->candidata; o resto 1:1.';

-- Append-only camada 2: nem dono nem migration reescrevem/apagam fato.
create or replace function public.fn_participacao_append_only()
returns trigger language plpgsql as $function$
begin
  raise exception 'fabio_participacao e append-only: % bloqueado em %', tg_op, tg_table_name;
end
$function$;

create trigger trg_participacao_ocorrencias_append_only
  before update or delete on public.fabio_participacao_ocorrencias
  for each row execute function public.fn_participacao_append_only();

create trigger trg_participacao_eventos_append_only
  before update or delete on public.fabio_participacao_ocorrencia_eventos
  for each row execute function public.fn_participacao_append_only();

-- Coerencia do supersede: so corrige ocorrencia da MESMA aula + MESMO aluno
-- matriculado, e carimba 'corrigida' na antiga.
create or replace function public.fn_participacao_supersede_coerente()
returns trigger language plpgsql
set search_path to 'pg_catalog', 'public' as $function$
declare
  v_ant public.fabio_participacao_ocorrencias%rowtype;
begin
  if new.supersede_ocorrencia_id is null then
    return new;
  end if;
  select * into v_ant from public.fabio_participacao_ocorrencias where id = new.supersede_ocorrencia_id;
  if not found then
    raise exception 'supersede aponta pra ocorrencia inexistente';
  end if;
  if v_ant.aula_operacional_id <> new.aula_operacional_id
     or v_ant.aluno_matriculado_id <> new.aluno_matriculado_id then
    raise exception 'supersede so corrige a MESMA aula operacional e o MESMO aluno matriculado';
  end if;
  insert into public.fabio_participacao_ocorrencia_eventos (ocorrencia_id, evento, por_tipo, por_id, dados)
  values (v_ant.id, 'corrigida', 'sistema', null, jsonb_build_object('corrigida_por', new.id));
  return new;
end
$function$;

create trigger trg_participacao_supersede_coerente
  before insert on public.fabio_participacao_ocorrencias
  for each row execute function public.fn_participacao_supersede_coerente();

-- Portas fechadas: maquinario de worker. Inclui service_role no revoke porque
-- no Supabase os default privileges concedem ALL (UPDATE/DELETE inclusive) a
-- service_role em toda tabela nova; sem tirar isso, o append-only por grant
-- (camada 1) seria so decoracao e a garantia ficaria so no trigger (camada 2).
-- Os grants abaixo devolvem exatamente SELECT/INSERT.
revoke all on public.fabio_participacao_ocorrencias from public, anon, authenticated, service_role;
revoke all on public.fabio_participacao_ocorrencia_eventos from public, anon, authenticated, service_role;
revoke all on public.vw_fabio_participacao_ocorrencia_estado from public, anon, authenticated, service_role;
grant select, insert on public.fabio_participacao_ocorrencias to service_role;
grant select, insert on public.fabio_participacao_ocorrencia_eventos to service_role;
grant select on public.vw_fabio_participacao_ocorrencia_estado to service_role;
