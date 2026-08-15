-- O CHECK do tipo não conhecia o aviso novo.
--
-- 15/08/2026, 19:53 UTC. O aviso "a aula está sem aluno no sistema"
-- (20260815100000) rodou pela primeira vez em produção e morreu com 23514:
-- `fabio_notificacoes_tipo_check` é uma ALLOWLIST, e `registro_sem_roster`
-- não estava nela.
--
-- O dry-run tinha passado — e passou honestamente: `--dry-run` monta o corpo e
-- para ANTES do claim, que é exatamente onde o CHECK mora. Terceira vez neste
-- projeto que uma guarda de banco que o código não conhecia só apareceu na
-- execução real (o CHECK de `casado_por`, o teto de 3 da shortlist, agora
-- este). O padrão é sempre o mesmo: **allowlist no banco, chamador novo no
-- código, e um ensaio que não chega a tocar a porta.**
--
-- A allowlist não é o problema — ela é boa: impede que um `tipo` digitado
-- errado vire uma família nova de notificação em silêncio. O que faltava era
-- passar por ela ao criar o aviso.

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
    -- 20260815100000: o professor gravou sobre uma aula que está com ZERO
    -- aluno no Emusys. O normalizador recusa certo; o que faltava era ele
    -- ficar sabendo.
    'registro_sem_roster'
  ]));

comment on constraint fabio_notificacoes_tipo_check on public.fabio_notificacoes is
  'Allowlist dos tipos de aviso. Tipo novo no worker exige migration aqui — e o dry-run NÃO cobre isto, porque para antes do claim. Quem inventar um tipo sem passar por aqui descobre em produção, com 23514.';
