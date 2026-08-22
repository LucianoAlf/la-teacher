-- Libera 'pendencia_experimental' na allowlist de public.fabio_notificacoes.
--
-- POR QUE ISTO EXISTE (Ruling 11 da revisão da Task 3)
-- fabio_notification_worker.py ganhou o evento experimental_lembrete
-- (EVENTS["experimental_lembrete"] = EventSpec("pendencia_experimental",
-- "governanca", ...)), mas NENHUMA task do plano criava este tipo na
-- allowlist do banco. fabio_notificacoes_tipo_check tinha 14 valores e
-- 'pendencia_experimental' não era um deles.
--
-- O efeito em produção: fabio_claim_notificacao_por_referencia() faz um
-- INSERT puro em public.fabio_notificacoes (sem try/catch dentro da própria
-- função — ver pg_get_functiondef) — o primeiro claim real do lembrete
-- morreria com 23514 (check_violation). O timer roda a cada 5 minutos, pra
-- sempre, sem nunca conseguir gravar uma notificação sequer.
--
-- Esta é a QUARTA vez que este projeto é mordido pelo mesmo padrão:
-- allowlist/CHECK do banco só aparece na execução real contra produção —
-- um dry-run que monta o corpo e para antes do INSERT nunca toca esta
-- porta. O .test.sql que acompanha este arquivo prova em BEGIN/ROLLBACK
-- (raise exception no fim desfaz tudo) que:
--   1. o claim com 'pendencia_experimental' passa;
--   2. um tipo JÁ CONHECIDO (controle) continua passando — prova que a
--      allowlist não foi apenas removida por engano;
--   3. um tipo INVENTADO continua sendo recusado com 23514 — prova que o
--      CHECK ainda restringe alguma coisa, e não virou `true`.

alter table public.fabio_notificacoes
  drop constraint fabio_notificacoes_tipo_check;

alter table public.fabio_notificacoes
  add constraint fabio_notificacoes_tipo_check
  check (tipo = any (array[
    'briefing_matinal',
    'pendencia_registro',
    'experimental_nova',
    'reagendamento',
    'outro',
    'devolutiva_pronta',
    'devolutiva_destinatario',
    'experimental_registrada',
    'experimental_falta',
    'feedback_lembrete',
    'feedback_reforco',
    'feedback_coordenacao',
    'registro_recibo',
    'registro_sem_roster',
    'pendencia_experimental'
  ]));
