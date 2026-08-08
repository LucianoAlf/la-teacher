-- 068 — o default que o próprio CHECK recusa
--
-- `fabio_notificacoes.status` tinha `DEFAULT 'pendente'` e um CHECK que aceita
-- só ('processando','enviada','falhou','pulada_preferencia',
-- 'pulada_sem_destinatario'). Quer dizer: qualquer INSERT que OMITISSE o status
-- morria — e morria dizendo
--
--     new row for relation "fabio_notificacoes" violates check constraint
--     "fabio_notificacoes_status_check"
--
-- que manda o leitor investigar a constraint. A causa era o default, e o erro
-- nunca dizia isso. Achado em 08/08/2026 durante a 066; estava dormindo porque
-- todo caminho de escrita informa o status explicitamente.
--
-- POR QUE TIRAR O DEFAULT E NÃO TROCAR PRA 'processando'
-- Trocar seria escolher um estado de entrada para uma fila que não tem: a linha
-- NASCE no claim, com lease, tentativa e destinatário já resolvidos (é a
-- decisão registrada na 066). Um default 'processando' faria o INSERT
-- incompleto PASSAR, fabricando em silêncio uma linha que se diz em voo — sem
-- lease pra expirar e sem ninguém pra concluir. O defeito sairia do INSERT e
-- reapareceria como uma mensagem que nunca chega, horas depois, longe de quem
-- causou. Sem default, a mesma omissão falha na hora com
--
--     null value in column "status" of relation "fabio_notificacoes"
--     violates not-null constraint
--
-- que nomeia a coluna. O NOT NULL FICA: é ele que transforma a falta do default
-- em erro. Sem ele, o INSERT omisso passaria a gravar null caladinho — pior que
-- o erro confuso que esta migration corrige.
--
-- AUDITADO ANTES DE MEXER (nenhum caminho dependia do default)
--   • 5 funções no banco inserem na tabela, em 7 INSERTs no total —
--     fabio_claim_notificacao, fabio_claim_notificacao_por_referencia,
--     fabio_claim_aviso_comercial, fabio_claim_aviso_falta_experimental e
--     fn_reservar_recado_coordenacao. Os 7 nomeiam `status` na lista de
--     colunas (conferido na lista de colunas de cada INSERT, não no corpo
--     inteiro da função: um `on conflict do update set status=…` teria dado
--     falso positivo).
--   • Zero triggers e zero rules na tabela; nenhuma view escreve nela.
--   • 56 cron jobs no banco, nenhum cita a tabela.
--   • Na VPS: `~/.hermes` não menciona a tabela, e o
--     `~/fabio-chat-bridge/fabio_notification_worker.py` só fala com ela por
--     RPC (claim / marcar_enviada / marcar_falhou) — nunca por INSERT.
--   • A edge function `coordenacao-recado` também é só RPC.
--   • RLS ligada: quem escreve é service_role.
--   • Nos dados: 19 linhas, todas 'enviada'. Nenhuma 'pendente' jamais existiu
--     — nem poderia.
--
-- Isto torna obsoleta a justificativa escrita no comentário da 066 ("o DEFAULT
-- da coluna é 'pendente' … omitir quebraria"). O conselho dela continua certo —
-- status vai explícito —, só a razão mudou: agora quebra por NOT NULL.

alter table public.fabio_notificacoes
  alter column status drop default;

comment on column public.fabio_notificacoes.status is
  'Estado do envio. NAO tem default de proposito: a linha nasce no claim, ja '
  'com o estado que lhe cabe. Sem default, o INSERT que esquecer a coluna falha '
  'em 23502 nomeando "status"; com um default qualquer, ele passaria e '
  'fabricaria uma linha em voo que ninguem reservou.';
