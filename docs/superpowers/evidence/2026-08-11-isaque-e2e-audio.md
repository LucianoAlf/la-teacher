# E2E simulado do áudio do Isaque — 2026-08-11

## Escopo

- Professor: `10` (Isaque).
- Áudio-fonte: `378cd2e3-9048-4797-8f7a-83bc38162b59`, 50s, aula original `202736`.
- A origem original permaneceu `app`, `normalizado`, com o mesmo `storage_path` e timestamps.
- O teste usou uma cópia nova no bucket privado e mensagens com `wa_message_id` sintético; não reutilizou o UUID do áudio original.
- O webhook da UAZAPI não foi chamado: a injeção controlada começou no inbox persistido para exercitar o poller e as portas do bridge.

## Caminho executado

1. Download do objeto original com service role.
2. Upload de staging privado `whatsapp/{professor_id}/{wa_message_id}.webm`.
3. Poller do bridge, classificação fechada como `registro` e abertura da ação.
4. Mais de três candidatas gerou pergunta discriminante, sem gravação.
5. Resposta sintética com horário recalculou o pool e reduziu para duas aulas do banco; nenhuma foi escolhida arbitrariamente.
6. Cancelamento sintético fechou a ação como `cancelada`.
7. Reconciliador executou `claimed=1`, `limpas=1`; o staging do bridge e a cópia de origem foram removidos.

## Resultado verificado

- Ação: `cancelada`; sem ação ativa para o professor.
- `fabio_fila_audios`: zero linhas do namespace E2E.
- `fabio_registros_aula`: zero registros criados no intervalo do teste.
- `registro_recibo`: zero notificações criadas.
- Ledger: `pergunta_refinada`, `shortlist_definida`, `cancelado`; eventos internos usaram chaves derivadas distintas.
- Serviço `fabio-chat-bridge`: ativo após rollout; reconciliador encerrou com sucesso.

## Correções descobertas pelo E2E

- Migration 096: `fabio_iniciar_acao` aceita os dois tipos `escolher_aula_*` que o bridge já usa.
- Bridge: eventos múltiplos da mesma mensagem usam chaves derivadas idempotentes.
- Bridge: resposta de dia/horário/turma recalcula a shortlist antes de escolher.
- Storage: limpeza usa `DELETE /storage/v1/object/{bucket}` com `prefixes`, contrato real da API.

## Limite da prova

Este ensaio provou ingestão controlada, classificação, shortlist, refinamento, cancelamento e limpeza sem escrita pedagógica. Não provou a entrada física do webhook UAZAPI nem uma confirmação final de registro, porque o áudio-fonte não identificava uma das duas aulas restantes com segurança.
