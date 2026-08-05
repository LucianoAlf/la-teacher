-- 031 — o responsavel volta a abrir a propria anamnese
--
-- A 030 (hoje de manha) revogou o EXECUTE de `anon` em `get_anamnese_publica`
-- para fechar o link que ia no WhatsApp do professor. Fechou — e fechou demais.
--
-- O que eu nao sabia quando escrevi a 030, e o Alf esclareceu:
--
--   "Seria para enviar para o proprio responsavel. Ele pode pedir. Voce poderia
--    enviar a minha anamnese que eu preenchi, e o responsavel precisa ter
--    acesso disso."
--
-- O responsavel PREENCHEU aquela anamnese. O dado e dele e do filho dele, e ele
-- pode pedir uma copia a qualquer momento — inclusive por direito, nao so por
-- gentileza. Ele nao tem conta no sistema e nao faz sentido criar uma: o
-- `share_token` E a credencial dele, do mesmo jeito que um link de acesso por
-- e-mail.
--
-- O CONSERTO DE VERDADE JA FOI FEITO, E NAO ERA ESTE. O problema nunca foi o
-- responsavel abrir a ficha. Era o link viajar junto da mensagem do PROFESSOR,
-- que nao e dono do dado e podia repassar. Isso saiu hoje de tres lugares:
--
--   • da mensagem automatica (edge function notificar-anamnese)
--   • do texto copiavel do LA Report (montarTextoAnamnese)
--   • e o `get_anamnese_by_token`, que nao tinha consumidor nenhum, continua
--     revogado — nada aqui devolve o EXECUTE dela
--
-- Entao a superficie hoje e: quem tem token e quem preencheu, ou a coordenacao
-- que abriu a tela. Que e exatamente quem deve ter.
--
-- ⚠️ FICA UM RESIDUO CONHECIDO: as 7 mensagens que ja foram entregues a
-- professores antes de hoje carregam o link, e esses tokens continuam validos.
-- Rotacionar mataria junto os links que responsaveis ja receberam, entao e
-- decisao a parte — registrada na tarefa, nao resolvida aqui em silencio.

grant execute on function public.get_anamnese_publica(text) to anon;

comment on function public.get_anamnese_publica(text) is
'Ficha da anamnese por share_token, aberta a quem tem o token — o responsavel preencheu e e dono do dado. O que NAO pode e o token viajar na mensagem do professor: isso foi removido em 05/08/2026. Ver migrations 030 e 031.';
