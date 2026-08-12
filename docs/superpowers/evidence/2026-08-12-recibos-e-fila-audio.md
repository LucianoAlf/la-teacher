# Rollout — recibos e fila de áudio (12/08/2026)

## Estado final

Rollout concluído na branch `codex/corrige-recibos-e-fila-audio` e integrado pela PR #4 em 12/08/2026 (merge commit `1d5e3c2`). A sequência de commits do trabalho foi `66d509b`, `074dbed`, `ea51cfd`, `193859a` e `197b1bb`.

A migration `20260812163000` foi aplicada e registrada. O ensaio de rollback preservou o schema e as 35 linhas verificadas. A ACL de `app_status_audio_fila` está confirmada: `anon=false`, `authenticated=true` e `service_role=true`.

## Comportamento entregue

- Registro feito no aplicativo permanece no aplicativo: não cria recibo verboso no WhatsApp.
- Registro iniciado no WhatsApp continua sendo salvo no aplicativo e pode usar o retorno próprio do canal WhatsApp.
- A fila reutiliza o áudio já em processamento ou o rascunho já preparado para a mesma aula, em vez de criar outro registro.
- Erro recuperável continua em acompanhamento; erro terminal é informado separadamente.
- A interface não descarta o Blob offline diante de resposta RPC inválida e evita expor IDs técnicos nas pendências.

## Verificações

- 28/28 mutantes SQL eliminados.
- 43 testes unitários e `npm run build` passaram.
- Não havia jobs de recibo ativos, de qualquer origem.
- Na VPS, `fabio-chat-bridge` e `fabio-hermes-gateway` permanecem ativos; `fabio-registro-recibo.timer` está enabled/active e o último worker terminou com sucesso, sem claims.
- A Production Vercel foi publicada. `https://la-teacher.vercel.app/app/login` respondeu HTTP 200; o DOM de login carregou sem erros de console e o bundle contém os novos textos.

## Limite da validação

Não foi gerado áudio real de professor, presença, falta, mensagem WhatsApp de saída nem mensagem a responsável. Portanto, esta evidência não declara E2E com professor.
