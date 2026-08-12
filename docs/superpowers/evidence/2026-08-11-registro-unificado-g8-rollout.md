# Evidência G8 — registro unificado com recibo desligado

Data: 11/08/2026 (BRT)

## Banco

- Projeto confirmado: `ouqwbbermlzqqvtqwlul`, status `ACTIVE_HEALTHY`, região
  `sa-east-1`, PostgreSQL 17.6.
- Preflight encontrou as funções-base 090/091 e nenhum objeto específico de
  095. As migrations 093, 094 e 095 foram aplicadas em sequência pelo
  `scripts/aplicar-sql.mjs`, sem SQL manual reconstruído.
- 093 verificada com `fn_registrar_presencas_core` contendo a identidade
  `professor_whatsapp`; 094 verificada com a RPC de correção auditada e ACL
  somente `service_role`; 095 verificada com as quatro portas do worker, índice
  único e tipo `registro_recibo`.
- Pós-rollout: `registro_recibo=0`, pendentes `0`, enviados `0`.

## VPS

- Host `la-hq`, usuário `fabio`, Python 3.12.3.
- Backup: `/home/fabio/fabio-chat-bridge/backups/20260811-registro-recibo-g8-20260811230107/`.
- Arquivos versionados publicados e compilados com `python3 -m py_compile`.
- O bridge foi reiniciado e ficou `active`; o reconciliador permaneceu ativo.
- `fabio-registro-recibo.timer` foi instalado, habilitado e ficou `active`.
- O ambiente remoto confirmou `FABIO_REGISTRO_RECIBO_MODE=off`.
- Execução manual e duas execuções do timer retornaram `status=disabled`,
  `claimed=0`, `sent=0`; não houve chamada de transporte.

## Limites da evidência

Não houve mensagem WhatsApp, professor, dado pedagógico ou E2E funcional. O
runner SQL descartável e os mutantes não foram considerados prova porque o
runner SQL aponta para o Supabase remoto e não há PostgreSQL local seguro.
O próximo gate é um piloto E2E restrito, com comparação contra o app e sem
habilitar o recibo geral.
