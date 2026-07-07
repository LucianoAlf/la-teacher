-- =============================================================================
-- 003 · Sync da GRADE FUTURA (Emusys → aulas_emusys)
-- =============================================================================
-- Agenda a edge `sync-grade-futura-emusys` para popular a grade dos próximos
-- 35 dias, por unidade, de madrugada — para o app do professor (la-teacher)
-- enxergar o mês inteiro à frente lendo `aulas_emusys` direto (sem chamar a
-- Emusys no clique).
--
-- Fronteira com a sync-presenca (ver comentário-cabeçalho da edge):
--   • grade-futura: dona de `data_aula >= hoje` (só a linha da aula, sem presença);
--     só cancela fantasmas em `data_aula > hoje`.
--   • sync-presenca: dona de `hoje pra trás` (aula + presença real).
--   Convergem na mesma linha via upsert (emusys_id, unidade_id).
--
-- Escalonado 03:00/03:05/03:10 BRT (06:00/06:05/06:10 UTC), depois dos
-- syncs de matrícula (02h BRT). Um job por unidade p/ dividir carga e evitar
-- timeout, no mesmo padrão de `sync-presenca-*`.
--
-- ⚠️ Pré-requisito: a edge `sync-grade-futura-emusys` precisa estar deployada
--    (verify_jwt:false) ANTES de os jobs dispararem.
-- =============================================================================

-- Idempotência: remove agendamentos anteriores destes jobs, se existirem.
do $$
declare j text;
begin
  foreach j in array array[
    'sync-grade-futura-cg',
    'sync-grade-futura-barra',
    'sync-grade-futura-recreio'
  ] loop
    if exists (select 1 from cron.job where jobname = j) then
      perform cron.unschedule(j);
    end if;
  end loop;
end $$;

-- Campo Grande (unidade_index 0) — 06:00 UTC
select cron.schedule(
  'sync-grade-futura-cg',
  '0 6 * * *',
  $$
  select net.http_post(
    url := 'https://ouqwbbermlzqqvtqwlul.supabase.co/functions/v1/sync-grade-futura-emusys',
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im91cXdiYmVybWx6cXF2dHF3bHVsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc1Nzg5NTgsImV4cCI6MjA4MzE1NDk1OH0.KGEzs2T-NPBc1DaWjgIVbJkEsjAdluT4q5kHrFvIJus"}'::jsonb,
    body := '{"janela_dias": 35, "unidade_index": 0}'::jsonb
  );
  $$
);

-- Barra (unidade_index 1) — 06:05 UTC
select cron.schedule(
  'sync-grade-futura-barra',
  '5 6 * * *',
  $$
  select net.http_post(
    url := 'https://ouqwbbermlzqqvtqwlul.supabase.co/functions/v1/sync-grade-futura-emusys',
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im91cXdiYmVybWx6cXF2dHF3bHVsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc1Nzg5NTgsImV4cCI6MjA4MzE1NDk1OH0.KGEzs2T-NPBc1DaWjgIVbJkEsjAdluT4q5kHrFvIJus"}'::jsonb,
    body := '{"janela_dias": 35, "unidade_index": 1}'::jsonb
  );
  $$
);

-- Recreio (unidade_index 2) — 06:10 UTC
select cron.schedule(
  'sync-grade-futura-recreio',
  '10 6 * * *',
  $$
  select net.http_post(
    url := 'https://ouqwbbermlzqqvtqwlul.supabase.co/functions/v1/sync-grade-futura-emusys',
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im91cXdiYmVybWx6cXF2dHF3bHVsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc1Nzg5NTgsImV4cCI6MjA4MzE1NDk1OH0.KGEzs2T-NPBc1DaWjgIVbJkEsjAdluT4q5kHrFvIJus"}'::jsonb,
    body := '{"janela_dias": 35, "unidade_index": 2}'::jsonb
  );
  $$
);
