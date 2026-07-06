-- ============================================================================
-- LA TEACHER · MIGRAÇÃO 001 — FUNDAÇÃO (Fábio no LA Report)
-- Projeto: ouqwbbermlzqqvtqwlul · 04/07/2026
-- Idempotente: pode rodar mais de uma vez sem quebrar.
-- Ordem: fila de áudios → registros → storage → risco → auth/RPCs → RLS → extras
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0 · Helper de updated_at
-- ---------------------------------------------------------------------------
create or replace function public.fn_set_atualizado_em()
returns trigger language plpgsql as $$
begin new.atualizado_em := now(); return new; end $$;

-- ---------------------------------------------------------------------------
-- 1 · FILA DE ÁUDIOS (upload offline-first → transcrição → normalização)
-- ---------------------------------------------------------------------------
create table if not exists public.fabio_fila_audios (
  id               uuid primary key default gen_random_uuid(),
  professor_id     integer references public.professores(id),
  unidade_id       uuid references public.unidades(id),
  aula_id          integer references public.aulas_emusys(id),
  storage_path     text not null,                    -- fabio-audios/{auth_uid}/{uuid}.m4a
  duracao_segundos integer,
  status           text not null default 'pendente'
                   check (status in ('pendente','transcrevendo','transcrito','normalizado','erro')),
  transcricao      text,
  erro             text,
  tentativas       integer not null default 0,
  origem           text not null default 'app' check (origem in ('app','whatsapp')),
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now()
);
create index if not exists ix_fabio_audios_status on public.fabio_fila_audios(status, criado_em);
create index if not exists ix_fabio_audios_prof   on public.fabio_fila_audios(professor_id);
drop trigger if exists trg_fabio_audios_upd on public.fabio_fila_audios;
create trigger trg_fabio_audios_upd before update on public.fabio_fila_audios
  for each row execute function public.fn_set_atualizado_em();

-- ---------------------------------------------------------------------------
-- 2 · REGISTROS DE AULA ESTRUTURADOS (Moldes A/B/C · tronco + fatias)
--    Tese do Quintela + Moldes Canônicos: estrutura uniforme na saída,
--    Fábio nunca inventa (campo faltante = cutucada na Confirmação).
-- ---------------------------------------------------------------------------
create table if not exists public.fabio_registros_aula (
  id                  uuid primary key default gen_random_uuid(),
  aula_id             integer not null references public.aulas_emusys(id),
  unidade_id          uuid not null references public.unidades(id),
  professor_id        integer references public.professores(id),
  aluno_id            integer references public.alunos(id),   -- null = tronco (turma)
  parent_id           uuid references public.fabio_registros_aula(id) on delete cascade,
  molde               text not null check (molde in ('A','B','C')),
  campos              jsonb not null default '{}'::jsonb,
  -- chaves canônicas em `campos` (só o que foi dito):
  --   tronco: atividades, objetivo, repertorio, materiais, dever_casa, obs_gerais,
  --           marco_ref, eixos[] (Teoria|Tecnica|RitmoPercepcao|RepertorioAplicacao)
  --   fatia : progresso, proximo_passo, observacao, presenca, conquista (fase 3)
  texto_consolidado   text,          -- saída no formato da Tese (colável/gravável no Emusys)
  status              text not null default 'rascunho'
                      check (status in ('rascunho','aguardando_confirmacao','confirmado','gravado_emusys','descartado')),
  origem              text not null default 'app' check (origem in ('app','whatsapp')),
  audio_id            uuid references public.fabio_fila_audios(id),
  checkpoint_sugerido jsonb,         -- {jornada, marco, evidencia} · condicional (Q2)
  confirmado_em       timestamptz,
  confirmado_por      integer references public.usuarios(id),
  criado_em           timestamptz not null default now(),
  atualizado_em       timestamptz not null default now(),
  constraint chk_tronco_ou_fatia check (aluno_id is not null or parent_id is null)
);
create index if not exists ix_fabio_reg_aula   on public.fabio_registros_aula(aula_id);
create index if not exists ix_fabio_reg_prof   on public.fabio_registros_aula(professor_id, status);
create index if not exists ix_fabio_reg_aluno  on public.fabio_registros_aula(aluno_id);
create index if not exists ix_fabio_reg_parent on public.fabio_registros_aula(parent_id);
drop trigger if exists trg_fabio_reg_upd on public.fabio_registros_aula;
create trigger trg_fabio_reg_upd before update on public.fabio_registros_aula
  for each row execute function public.fn_set_atualizado_em();

-- ---------------------------------------------------------------------------
-- 3 · STORAGE — bucket privado de áudios + políticas por pasta do usuário
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('fabio-audios','fabio-audios', false)
on conflict (id) do nothing;

drop policy if exists "fabio_audios_insert_own" on storage.objects;
create policy "fabio_audios_insert_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'fabio-audios'
              and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "fabio_audios_select_own" on storage.objects;
create policy "fabio_audios_select_own" on storage.objects
  for select to authenticated
  using (bucket_id = 'fabio-audios'
         and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------------
-- 4 · RISCO DE EVASÃO (modelo do Hugo) — append-only, 1 snapshot/aluno/dia
-- ---------------------------------------------------------------------------
create table if not exists public.risco_evasao (
  id            bigint generated always as identity primary key,
  aluno_id      integer not null references public.alunos(id),
  unidade_id    uuid references public.unidades(id),
  probabilidade numeric(5,4) not null check (probabilidade >= 0 and probabilidade <= 1),
  faixa         text not null check (faixa in ('baixo','atencao','critico')),
  fatores       jsonb,                       -- top features do modelo p/ o caso
  modelo_versao text not null default 'rf-v1',
  calculado_em  date not null default current_date,
  criado_em     timestamptz not null default now(),
  unique (aluno_id, calculado_em, modelo_versao)
);
create index if not exists ix_risco_data  on public.risco_evasao (calculado_em desc);
create index if not exists ix_risco_faixa on public.risco_evasao (faixa, calculado_em desc);

create or replace view public.vw_risco_atual as
  select distinct on (aluno_id) *
  from public.risco_evasao
  order by aluno_id, calculado_em desc, id desc;

-- Role dedicada do job de ML (primeira escrita externa no LA Report — H3 do Hugo).
-- Credencial/login é criada à parte (painel/vault); NUNCA usar service_role no cron.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'ml_jobs') then
    create role ml_jobs nologin;
  end if;
end $$;
grant usage on schema public to ml_jobs;
grant select on public.alunos, public.aluno_presenca, public.vw_risco_atual to ml_jobs;
grant insert on public.risco_evasao to ml_jobs;

-- ---------------------------------------------------------------------------
-- 5 · IDENTIDADE — vínculo professor ↔ usuário/auth (hoje: 0 professores logam)
-- ---------------------------------------------------------------------------
alter table public.professores add column if not exists usuario_id integer references public.usuarios(id);
create unique index if not exists ux_professores_usuario
  on public.professores(usuario_id) where usuario_id is not null;

create or replace function public.fn_professor_do_usuario()
returns integer language sql stable security definer set search_path = public as $$
  select p.id
  from public.professores p
  join public.usuarios u on u.id = p.usuario_id
  where u.auth_user_id = auth.uid()
  limit 1;
$$;

-- ---------------------------------------------------------------------------
-- 6 · RPCs DO APP (padrão de segurança: o professor NUNCA passa o próprio id;
--     tudo resolve via auth.uid() → fn_professor_do_usuario)
-- ---------------------------------------------------------------------------
create or replace function public.app_minha_agenda(p_data date default current_date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_prof integer := public.fn_professor_do_usuario();
begin
  if v_prof is null then
    return jsonb_build_object('erro','sem_professor_vinculado');
  end if;
  return (
    select jsonb_build_object(
      'data', p_data,
      'total', count(*),
      'aulas', coalesce(jsonb_agg(to_jsonb(v) order by v.data_hora_inicio), '[]'::jsonb))
    from public.vw_fabio_aulas_contexto v
    where v.professor_id = v_prof and v.data_aula = p_data
  );
end $$;

create or replace function public.app_minha_carteira()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_prof integer := public.fn_professor_do_usuario();
begin
  if v_prof is null then
    return jsonb_build_object('erro','sem_professor_vinculado');
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'aluno_id', c.aluno_id, 'aluno_nome', c.aluno_nome, 'aluno_status', c.aluno_status,
      'curso', c.curso_nome, 'tipo_matricula', c.tipo_matricula_nome,
      'dia_aula', c.dia_aula, 'horario_aula', c.horario_aula,
      'responsavel', c.responsavel_nome, 'qualidade', c.qualidade_contexto
      -- sem valor_parcela / telefone / e-mail: financeiro e contato não são do app do professor
    ) order by c.aluno_nome), '[]'::jsonb)
    from public.vw_fabio_carteira_professor c
    where c.professor_id = v_prof
  );
end $$;

create or replace function public.app_meus_registros(p_status text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_prof integer := public.fn_professor_do_usuario();
begin
  if v_prof is null then return '[]'::jsonb; end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(r) order by r.criado_em desc), '[]'::jsonb)
    from public.fabio_registros_aula r
    where r.professor_id = v_prof
      and r.parent_id is null                       -- raiz (tronco ou 1:1)
      and (p_status is null or r.status = p_status)
  );
end $$;

create or replace function public.app_confirmar_registro(p_registro_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_prof integer := public.fn_professor_do_usuario();
  v_reg  public.fabio_registros_aula%rowtype;
  v_out  jsonb;
begin
  if v_prof is null then raise exception 'Usuário sem professor vinculado'; end if;

  select * into v_reg from public.fabio_registros_aula
   where id = p_registro_id and parent_id is null;
  if not found then raise exception 'Registro % não encontrado', p_registro_id; end if;
  if v_reg.professor_id is distinct from v_prof then
    raise exception 'Registro não pertence a este professor';
  end if;
  if v_reg.status not in ('rascunho','aguardando_confirmacao') then
    raise exception 'Registro em status % não pode ser confirmado', v_reg.status;
  end if;
  if v_reg.texto_consolidado is null or btrim(v_reg.texto_consolidado) = '' then
    raise exception 'Registro sem texto consolidado';
  end if;

  -- Porta única de escrita pedagógica (auditada e idempotente):
  v_out := public.registrar_aula_fabio(
             p_aula_id      => v_reg.aula_id,
             p_texto        => v_reg.texto_consolidado,
             p_origem       => v_reg.origem,
             p_professor_id => v_reg.professor_id,
             p_modo         => 'novo');

  update public.fabio_registros_aula
     set status = 'gravado_emusys', confirmado_em = now(),
         confirmado_por = (select u.id from public.usuarios u where u.auth_user_id = auth.uid())
   where id = p_registro_id or parent_id = p_registro_id;

  return jsonb_build_object('registro_id', p_registro_id, 'gravacao', v_out);
end $$;

revoke all on function public.app_minha_agenda(date)            from public, anon;
revoke all on function public.app_minha_carteira()              from public, anon;
revoke all on function public.app_meus_registros(text)          from public, anon;
revoke all on function public.app_confirmar_registro(uuid)      from public, anon;
grant execute on function public.app_minha_agenda(date)         to authenticated;
grant execute on function public.app_minha_carteira()           to authenticated;
grant execute on function public.app_meus_registros(text)       to authenticated;
grant execute on function public.app_confirmar_registro(uuid)   to authenticated;

-- ---------------------------------------------------------------------------
-- 7 · RLS — professor só enxerga o que é dele; coordenação enxerga risco
-- ---------------------------------------------------------------------------
alter table public.fabio_registros_aula enable row level security;
drop policy if exists fabio_reg_prof_select on public.fabio_registros_aula;
create policy fabio_reg_prof_select on public.fabio_registros_aula
  for select to authenticated using (professor_id = public.fn_professor_do_usuario());
drop policy if exists fabio_reg_prof_update on public.fabio_registros_aula;
create policy fabio_reg_prof_update on public.fabio_registros_aula
  for update to authenticated
  using  (professor_id = public.fn_professor_do_usuario()
          and status in ('rascunho','aguardando_confirmacao'))
  with check (professor_id = public.fn_professor_do_usuario());

alter table public.fabio_fila_audios enable row level security;
drop policy if exists fabio_audio_prof_select on public.fabio_fila_audios;
create policy fabio_audio_prof_select on public.fabio_fila_audios
  for select to authenticated using (professor_id = public.fn_professor_do_usuario());
drop policy if exists fabio_audio_prof_insert on public.fabio_fila_audios;
create policy fabio_audio_prof_insert on public.fabio_fila_audios
  for insert to authenticated
  with check (professor_id = public.fn_professor_do_usuario());

alter table public.risco_evasao enable row level security;
drop policy if exists risco_coordenacao_select on public.risco_evasao;
create policy risco_coordenacao_select on public.risco_evasao
  for select to authenticated
  using (exists (select 1 from public.usuarios u
                 where u.auth_user_id = auth.uid()
                   and u.perfil in ('admin','unidade')));
-- Professor NÃO lê risco cru (guardrail): o briefing dele recebe fatores
-- traduzidos pelo Fábio, nunca probabilidade.

-- ---------------------------------------------------------------------------
-- 8 · EXTENSÕES LEVES — Fila de Casos (H5+H6 do Hugo) e registro do agente
-- ---------------------------------------------------------------------------
alter table public.farmer_tarefas add column if not exists sla_em date;
alter table public.farmer_tarefas add column if not exists desfecho text;
alter table public.farmer_tarefas add column if not exists origem_alerta text;
alter table public.farmer_tarefas drop constraint if exists chk_farmer_desfecho;
alter table public.farmer_tarefas add constraint chk_farmer_desfecho
  check (desfecho is null or desfecho in ('retido','evadiu','renovou','sem_resposta','em_andamento'));

do $$ begin
  if not exists (select 1 from public.agentes where lower(nome) = 'fábio' or lower(nome) = 'fabio') then
    insert into public.agentes (nome, descricao, is_active, status, modo_teste)
    values ('Fábio', 'Agente pedagógico — LA Teacher (registro de aulas, briefing, jornada)',
            false, 'configuracao', true);
  end if;
exception when others then
  raise notice 'agentes: insert do Fábio pulado (%). Registrar manualmente.', sqlerrm;
end $$;

-- ---------------------------------------------------------------------------
-- 9 · REALTIME — o app assina o status do processamento
-- ---------------------------------------------------------------------------
do $$ begin
  alter publication supabase_realtime add table public.fabio_registros_aula;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.fabio_fila_audios;
exception when duplicate_object then null; end $$;

-- ============================================================================
-- FIM · Sanidade sugerida:
--   select count(*) from fabio_registros_aula;            -- 0
--   select * from vw_risco_atual limit 1;                  -- vazio, sem erro
--   select public.fn_professor_do_usuario();               -- null (sem vínculo ainda)
-- ============================================================================
