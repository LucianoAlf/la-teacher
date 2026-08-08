-- 060 — o reconciliador da experimental passa a rodar
--
-- ELE NUNCA TEVE QUEM O CHAMASSE.
--
-- `fn_reconciliar_experimental_aulas` é a chave do ciclo inteiro da
-- experimental: sem o vínculo lead↔aula, o professor não abre a ficha, não
-- registra, não declara falta, e o Fábio não sabe como a aula foi. A função
-- existe desde a 033, foi corrigida na 034, tem teste e tem mutante.
--
-- E não rodava. Medido em 08/08/2026: 57 jobs no `cron.job`, nenhum a chama;
-- nenhuma edge function a invoca; o vínculo mais recente do banco era de
-- 06/08 00:31, com ZERO nas últimas 24h. Ela só tinha rodado quando alguém
-- chamou na mão, durante o desenvolvimento.
--
-- O efeito visível: 12 das 23 experimentais dos próximos 7 dias sem vínculo —
-- inclusive uma a 2 dias da aula. E 11 dessas 12 tinham par perfeito esperando
-- no espelho (mesma unidade, mesmo professor, mesmo horário exato, categoria
-- 'experimental', não cancelada). Não era o casamento que falhava. Era a falta
-- de quem mandasse casar.
--
-- POR QUE :12, :27, :42, :57
-- Os três `sync-metadados-aulas-15m-u{0,1,2}` populam o espelho em
-- 0/15/30/45, 5/20/35/50 e 10/25/40/55. Rodar dois minutos depois do último
-- pega as três unidades no mesmo ciclo, em vez de reconciliar contra um
-- espelho que acabou de mudar.
--
-- Chamada SQL direta, sem edge function: a função já é `security definer` e o
-- job roda como `postgres`, dono dela. É o mesmo padrão de
-- `sincronizar-grade-horaria` e `recalcular-health-score-alunos-diario`.
--
-- Teste: 060-o-reconciliador-passa-a-rodar.test.sql
-- Mutantes: scripts/mutantes-060.mjs

select cron.schedule(
  'reconciliar-experimental-aulas',
  '12,27,42,57 * * * *',
  $cron$select public.fn_reconciliar_experimental_aulas(7, 200)$cron$
);
