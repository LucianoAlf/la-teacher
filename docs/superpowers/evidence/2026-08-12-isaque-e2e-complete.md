# E2E de produção do Isaque — registro completo pelo WhatsApp

**Janela do ensaio:** 11/08/2026 21:32–21:51 BRT (12/08/2026 00:32–00:51 UTC)

**Professor:** Isaque (`professor_id=10`)

**Escopo do piloto:** áudio real já existente, injetado de forma controlada na
inbox persistente; turma e horário explícitos; confirmação sintética pelo mesmo
fluxo do bridge. Nenhuma mensagem foi enviada à família.

## Caminho executado

1. A mensagem `e2e-isaque-close-c8162ac8fe76465fa36b` entrou uma única vez.
2. O bridge classificou registro, reduziu a shortlist à aula `202499`
   (`Piano T`, `P_Qui_19`, 19h) e enfileirou o áudio
   `6fb36ec3-f468-4727-9315-84f8ff2368fc` com origem `whatsapp`.
3. O Hermes transcreveu o objeto resolvido internamente por `audio_id`; nenhum
   signed URL ou `registro_id` foi transportado pelo modelo.
4. O normalizador criou o tronco
   `88f536f5-fb0a-4b02-aa8a-d8b7dfdbc0bf` e a fatia canônica do Pedro
   `7093bf0c-ae1c-4694-870f-4d840c33c59e` (aula individual `202500`).
5. O preview canônico foi persistido e enviado uma única vez com a chave
   `fabio-preview:8fd8af03-979f-4128-8340-513fdf719702` (731 caracteres).
6. A confirmação `e2e-isaque-confirm-8499e1f7bde0429697eb` entrou uma única
   vez. O replay exato foi rejeitado como duplicado.
7. A ação `8fd8af03-979f-4128-8340-513fdf719702` terminou `resolvida`, sem erro.

## Escritas canônicas verificadas

- 2 registros, ambos `gravado_emusys`, confirmados no mesmo instante e com
  origem final `whatsapp`.
- 1 presença: Pedro (`aluno_id=1629`), aula `202500`, `presente`, escritor
  `fabio_audio`.
- 1 devolutiva (`a00a1056-826e-4533-a478-a36e95d4f20e`), status `gerada`.
- A devolutiva continua rascunho: `envio_recibo`, `compartilhada_em` e
  `envio_confirmado_em` permanecem nulos.
- 1 notificação de carimbo e 1 mensagem de memória. Novas execuções do worker
  retornaram fila vazia e não reenviaram.
- O objeto de staging permanece no bucket porque o registro confirmado o
  referencia. A guarda de limpeza recusa apagar essa fonte auditável.

## Defeitos encontrados e corrigidos durante o ensaio

### Autoridade do áudio e do canal

O contrato anterior forçava `origem=app` no tool mesmo quando a fila era
WhatsApp. O tool agora resolve `aula_id`, `professor_id` e `origem` da própria
linha de `fabio_fila_audios`; o modelo só organiza os campos pedagógicos.
A migration `20260812103000_align_registro_origin_with_audio_queue` corrigiu os
dois registros do ensaio e deixou zero divergências entre fila e registro.

### Preview idempotente

O preview passou a ter outbox durável por ação. Replay de item concluído
retorna `ja_enviado=true`; item pré-existente sem fechamento é tratado como
entrega incerta e nunca é reenviado automaticamente.

### Confirmação pós-commit

O primeiro processamento confirmou banco e presença, mas falhou ao sanear
metadados operacionais do read-back. O sanitizador agora projeta somente campos
pedagógicos e a confirmação recupera estados já confirmados sem escrever de
novo.

### Fechamento do carimbo

O carimbo chegou ao WhatsApp, mas o fechamento encontrou o índice parcial
`fcm_wa_msg_uq`. A migration
`20260812004430_fix_registro_recibo_partial_conflict` alinhou o `ON CONFLICT`
ao predicado `wa_message_id is not null`. O item já entregue foi fechado sem
um segundo transporte.

### Redundância no texto do carimbo

O primeiro carimbo real revelou que `texto_consolidado` repetia o conteúdo
comum no bloco do aluno. O formatador agora usa o tronco uma única vez e, por
aluno, apenas progresso, observação, próximo passo e repertório individuais.
No mesmo payload vivo, a renderização corrigida teve `common_count=1`, presença,
progresso e rascunho de devolutiva. Ela foi verificada sem reenviar uma segunda
mensagem confusa ao professor.

## Rollout e backups

- `/home/fabio/fabio-chat-bridge/backups/20260812T002927Z`
- `/home/fabio/fabio-chat-bridge/backups/20260812T003711Z`
- `/home/fabio/fabio-chat-bridge/backups/20260812T004202Z`
- `/home/fabio/fabio-chat-bridge/backups/20260812T004900Z`
- `/home/fabio/fabio-chat-bridge/backups/20260812T103000Z`

Serviços finais: `fabio-chat-bridge`, `fabio-hermes-gateway`,
`fabio-whatsapp-reconciler.timer` e `fabio-registro-recibo.timer` ativos. Portas
8644, 8645 e 8652 em escuta.

## Verificação

- Normalização/tool: 26 testes.
- Contrato do webhook: 1 teste.
- Ações WhatsApp: 16 testes.
- Bridge: 15 testes.
- Reconciliador: 7 testes.
- Worker do recibo: 8 testes.
- Auditoria de carimbo: 25 casos.
- Mutantes: 10/10 mortos.
- As duas migrations novas passaram em transação com rollback no PostgreSQL
  vivo antes da aplicação; migration history e estado final foram conferidos.

## Veredicto

O E2E de produção está fechado para o piloto do Isaque: áudio, shortlist,
transcrição, normalização, preview, confirmação, presença, devolutiva em
rascunho, carimbo, memória e idempotência foram exercitados. O primeiro carimbo
foi a prova que expôs a redundância; a correção final foi validada sobre os
mesmos dados sem produzir um reenvio. O piloto continua restrito e não autoriza
envio automático para responsáveis.
