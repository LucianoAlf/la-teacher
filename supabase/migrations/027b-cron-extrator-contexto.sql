-- 027b — o extrator ganha quem o chame
--
-- ⚠️ "Função pronta, chamador nenhum" é o defeito que apareceu SEIS vezes neste
-- projeto: a 020, a ceifar_travadas, o fabio-notification-worker.timer que
-- existia disabled, a tela sem porta de entrada na Home e as RPCs de manutenção
-- da 025. Esta migration existe para o extrator não virar a sétima.
--
-- LOTE DE 5, E ISSO NÃO É CHUTE
-- Uma chamada com limite 20 estourou o tempo da edge function e voltou HTML de
-- timeout do gateway. Cada aluno custa uma conversa inteira do Chatwoot
-- (paginada, 35 a 56 mensagens) mais uma chamada ao Gemini. Rodando de hora em
-- hora, 5 por vez cobre as ~19 experimentais da janela com folga.
--
-- {{VITE_SUPABASE_ANON_KEY}} é resolvido pelo scripts/aplicar-sql.mjs. A chave
-- anon é pública (vai no bundle do frontend) e é o mesmo mecanismo dos jobs
-- `alertas-diarios` e `alertas-tarefas-atrasadas` — não inventamos credencial
-- nova para isso.

select cron.unschedule('extrair-contexto-experimental-hora')
 where exists (select 1 from cron.job where jobname = 'extrair-contexto-experimental-hora');

select cron.schedule(
  'extrair-contexto-experimental-hora',
  '7 * * * *',   -- 7 min depois da hora: longe do topo, onde tudo dispara junto
  $$
  select net.http_post(
    url     := 'https://ouqwbbermlzqqvtqwlul.supabase.co/functions/v1/extrair-contexto-experimental',
    headers := jsonb_build_object(
                 'Content-Type',  'application/json',
                 'apikey',        '{{VITE_SUPABASE_ANON_KEY}}',
                 'Authorization', 'Bearer {{VITE_SUPABASE_ANON_KEY}}'),
    body    := jsonb_build_object('dias', 7, 'limite', 5),
    timeout_milliseconds := 150000
  );
  $$
);
