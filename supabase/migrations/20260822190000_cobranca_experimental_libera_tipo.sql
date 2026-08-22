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
--
-- `drop constraint if exists` (não `drop constraint` seco): das seis
-- migrations que já mexeram neste CHECK, esta era a única sem o `if
-- exists` — reproduzir num ambiente onde o objeto já não existe (ou não
-- existe ainda) não pode quebrar a migration inteira.
--
-- COMMENT ON CONSTRAINT: a 20260815120000 (terceira mordida, antes desta)
-- já tinha deixado um aviso na própria constraint. Esta migration original
-- fez `drop constraint` + `add constraint` sem reinstalar o COMMENT — o
-- aviso escrito pra evitar a quinta mordida sumiu de produção bem na
-- migration que conserta a quarta. Reinstalado abaixo, com mais uma volta
-- de experiência.

alter table public.fabio_notificacoes
  drop constraint if exists fabio_notificacoes_tipo_check;

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

comment on constraint fabio_notificacoes_tipo_check on public.fabio_notificacoes is
  'Allowlist dos tipos de aviso. Tipo novo no worker exige migration aqui — e o dry-run NÃO cobre isto, porque para antes do claim. Quem inventar um tipo sem passar por aqui descobre em produção, com 23514. Já mordeu esta casa em 15/08 (registro_sem_roster) e em 22/08 (pendencia_experimental) — da segunda vez o próprio conserto deste CHECK apagou este comentário ao fazer drop+add sem `if exists` e sem reinstalar o COMMENT. Quem alterar este CHECK de novo: use `drop constraint if exists`, reinstale este COMMENT, e prove com um .test.sql que faz um CLAIM de verdade (não um --dry-run, que para antes do INSERT e nunca toca esta porta).';
