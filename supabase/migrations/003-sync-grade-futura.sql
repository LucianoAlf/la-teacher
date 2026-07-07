-- =============================================================================
-- 003 · Sync da GRADE FUTURA (Emusys → aulas_emusys)
-- =============================================================================
-- Agenda a edge `sync-grade-futura-emusys` para popular a grade dos próximos
-- 35 dias, por unidade, para o app do professor (la-teacher) enxergar o mês
-- inteiro à frente lendo `aulas_emusys` direto (sem chamar a Emusys no clique).
--
-- Fronteira com a sync-presenca (ver comentário-cabeçalho da edge):
--   • grade-futura: dona de `data_aula >= hoje` (só a linha da aula, sem presença);
--     só cancela fantasmas em `data_aula > hoje`.
--   • sync-presenca: dona de `hoje pra trás` (aula + presença real).
--   Convergem na mesma linha via upsert (emusys_id, unidade_id).
--
-- HORÁRIO: roda 10 min depois da sync-presenca de cada unidade (não junto —
-- evita somar as duas rajadas de chamadas paginadas à Emusys no mesmo minuto).
-- Segue o MESMO padrão de dias da presença: seg-sex + job separado de sábado
-- (domingo não roda, escola fechada).
--
--   Unidade   | Presença (BRT) | Grade futura (BRT)
--   Barra     | 19h50 (seg-sex)| 20h00
--   CG        | 20h50 (seg-sex)| 21h00
--   Recreio   | 20h52 (seg-sex)| 21h02
--   CG        | 14h50 (sábado) | 15h00
--   Recreio   | 14h52 (sábado) | 15h02
--   Barra     | 15h50 (sábado) | 16h00
--
-- ⚠️ Cuidado de fuso: o banco guarda os crons em UTC (BRT = UTC-3). Horários
-- de CG/Recreio (seg-sex) passam das 21h BRT, o que cruza a meia-noite em
-- UTC — por isso o dia da semana do cron é `2-6` (não `1-5`): a noite de
-- segunda BRT já é terça de madrugada em UTC. Barra (20h BRT) e os jobs de
-- sábado não cruzam a virada, por isso mantêm o dia "normal". Conversão
-- validada por SQL antes de aplicar (ver docs/hugo do dia), não à mão.
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
    'sync-grade-futura-recreio',
    'sync-grade-futura-cg-sabado',
    'sync-grade-futura-recreio-sabado',
    'sync-grade-futura-barra-sabado'
  ] loop
    if exists (select 1 from cron.job where jobname = j) then
      perform cron.unschedule(j);
    end if;
  end loop;
end $$;

-- Barra (seg-sex): presença 19h50 BRT -> grade futura 20h00 BRT = 23:00 UTC (sem virada de dia)
select cron.schedule(
  'sync-grade-futura-barra', '0 23 * * 1-5',
  $$select net.http_post(
    url := 'https://ouqwbbermlzqqvtqwlul.supabase.co/functions/v1/sync-grade-futura-emusys',
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im91cXdiYmVybWx6cXF2dHF3bHVsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc1Nzg5NTgsImV4cCI6MjA4MzE1NDk1OH0.KGEzs2T-NPBc1DaWjgIVbJkEsjAdluT4q5kHrFvIJus"}'::jsonb,
    body := '{"janela_dias": 35, "unidade_index": 1}'::jsonb
  );$$
);

-- CG (seg-sex): presença 20h50 BRT -> grade futura 21h00 BRT = 00:00 UTC do dia seguinte (dow desloca +1)
select cron.schedule(
  'sync-grade-futura-cg', '0 0 * * 2-6',
  $$select net.http_post(
    url := 'https://ouqwbbermlzqqvtqwlul.supabase.co/functions/v1/sync-grade-futura-emusys',
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im91cXdiYmVybWx6cXF2dHF3bHVsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc1Nzg5NTgsImV4cCI6MjA4MzE1NDk1OH0.KGEzs2T-NPBc1DaWjgIVbJkEsjAdluT4q5kHrFvIJus"}'::jsonb,
    body := '{"janela_dias": 35, "unidade_index": 0}'::jsonb
  );$$
);

-- Recreio (seg-sex): presença 20h52 BRT -> grade futura 21h02 BRT = 00:02 UTC do dia seguinte (dow desloca +1)
select cron.schedule(
  'sync-grade-futura-recreio', '2 0 * * 2-6',
  $$select net.http_post(
    url := 'https://ouqwbbermlzqqvtqwlul.supabase.co/functions/v1/sync-grade-futura-emusys',
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im91cXdiYmVybWx6cXF2dHF3bHVsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc1Nzg5NTgsImV4cCI6MjA4MzE1NDk1OH0.KGEzs2T-NPBc1DaWjgIVbJkEsjAdluT4q5kHrFvIJus"}'::jsonb,
    body := '{"janela_dias": 35, "unidade_index": 2}'::jsonb
  );$$
);

-- CG (sábado): presença 14h50 BRT -> grade futura 15h00 BRT = 18:00 UTC (sem virada)
select cron.schedule(
  'sync-grade-futura-cg-sabado', '0 18 * * 6',
  $$select net.http_post(
    url := 'https://ouqwbbermlzqqvtqwlul.supabase.co/functions/v1/sync-grade-futura-emusys',
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im91cXdiYmVybWx6cXF2dHF3bHVsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc1Nzg5NTgsImV4cCI6MjA4MzE1NDk1OH0.KGEzs2T-NPBc1DaWjgIVbJkEsjAdluT4q5kHrFvIJus"}'::jsonb,
    body := '{"janela_dias": 35, "unidade_index": 0}'::jsonb
  );$$
);

-- Recreio (sábado): presença 14h52 BRT -> grade futura 15h02 BRT = 18:02 UTC (sem virada)
select cron.schedule(
  'sync-grade-futura-recreio-sabado', '2 18 * * 6',
  $$select net.http_post(
    url := 'https://ouqwbbermlzqqvtqwlul.supabase.co/functions/v1/sync-grade-futura-emusys',
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im91cXdiYmVybWx6cXF2dHF3bHVsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc1Nzg5NTgsImV4cCI6MjA4MzE1NDk1OH0.KGEzs2T-NPBc1DaWjgIVbJkEsjAdluT4q5kHrFvIJus"}'::jsonb,
    body := '{"janela_dias": 35, "unidade_index": 2}'::jsonb
  );$$
);

-- Barra (sábado): presença 15h50 BRT -> grade futura 16h00 BRT = 19:00 UTC (sem virada)
select cron.schedule(
  'sync-grade-futura-barra-sabado', '0 19 * * 6',
  $$select net.http_post(
    url := 'https://ouqwbbermlzqqvtqwlul.supabase.co/functions/v1/sync-grade-futura-emusys',
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im91cXdiYmVybWx6cXF2dHF3bHVsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc1Nzg5NTgsImV4cCI6MjA4MzE1NDk1OH0.KGEzs2T-NPBc1DaWjgIVbJkEsjAdluT4q5kHrFvIJus"}'::jsonb,
    body := '{"janela_dias": 35, "unidade_index": 1}'::jsonb
  );$$
);
