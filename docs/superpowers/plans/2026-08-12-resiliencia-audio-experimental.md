# Resiliência do áudio de experimental — plano em gates

## Contexto e causa confirmada

O professor Matheus Reis enviou um áudio da experimental de Antônio Soares em
11/08 e recebeu a tela genérica de falha. A investigação mostrou que o fluxo
`uploadAudioExperimental.ts` faz Storage e RPC diretamente: ele não persiste o
`Blob` no IndexedDB antes da rede. Logo, uma indisponibilidade transitória do
Supabase pode deixar a gravação somente na memória da tela e ela se perde ao
fechar o app.

Há uma segunda lacuna que impede a recuperação: o fluxo de áudio normal usa
`upsert: true`, enquanto o bucket `fabio-audios` tem políticas `INSERT` e
`SELECT`, mas não `UPDATE`. Um retry depois de upload bem-sucedido e falha da
RPC não consegue reutilizar o mesmo objeto.

O problema de agenda exibido na mesma janela é efeito da indisponibilidade de
transporte/autenticação, mas não deve apagar a fila nem induzir o professor a
regravar.

## Limites

- Reutilizar o motor de fila de áudio já usado por aula normal; não criar uma
  segunda fila experimental.
- A fila é por `auth.uid()`, persiste antes de qualquer I/O e só remove o Blob
  após aceite autoritativo da RPC.
- O caminho de Storage é estável por intenção, protegido por RLS, e a RPC é
  idempotente por professor + caminho + vínculo experimental.
- Nenhuma confirmação desta mudança manda conteúdo à família. Um E2E de
  experimental termina em rascunho e será descartado depois da evidência.
- A alteração não muda o comportamento de recibos: app continua no app,
  WhatsApp continua no WhatsApp.

## Gate 1 — Fila única e UX honesta

Arquivos: `src/features/registro/filaOffline.ts`,
`src/features/registro/uploadAudio.ts`,
`src/features/experimental/uploadAudioExperimental.ts`,
`src/features/experimental/GravadorExperimental.tsx`,
`src/pages/app/Home.tsx` e testes unitários adjacentes.

1. Modelar na fila local dois destinos discriminados: `aula` e `experimental`.
   Itens legados sem destino continuam sendo normalizados como `aula`; itens
   inválidos ficam preservados/quarentenados, nunca são enviados para outra
   pessoa.
2. Extrair o transporte comum: criar intenção e `storagePath` estáveis, salvar
   o Blob, fazer upload idempotente e chamar a RPC específica do destino.
3. Para experimental, usar `authUid/experimental-vinculoId/chave.ext`; chamar
   `app_enfileirar_audio_experimental`; aceitar somente resposta válida com
   UUID antes de descartar localmente.
4. Falha transitória (incluindo gateway 5xx/522, timeout e offline) preserva o
   Blob e agenda o backoff existente. O professor vê “áudio guardado neste
   aparelho”, pode sair da tela e encontra a ação na Home. Falha semântica é
   marcada terminalmente, sem retry automático.
5. A Home reconhece o destino experimental e, depois de um retry aceito,
   orienta a reabrir a ficha correta em vez de navegar à tela de aula comum.
6. Testes unitários: destino preservado, caminho estável, falha transitória
   continua reenviável, falha terminal não é reenviável, contrato de resposta
   inválida não descarta a intenção.

## Gate 2 — Banco: retry de Storage e idempotência de experimental

Arquivos novos: uma migration e seu teste SQL sob `supabase/migrations/`.

1. Criar a política RLS de `UPDATE` (com `USING` e `WITH CHECK` pelo primeiro
   diretório igual a `auth.uid()`) para `fabio-audios`. Não alterar objetos de
   Storage diretamente.
2. Reescrever somente a versão corrente de
   `app_enfileirar_audio_experimental`: adquirir lock por professor/caminho,
   devolver a fila existente quando o replay é do mesmo vínculo, rejeitar
   reutilização cruzada e serializar uma nova intenção por vínculo quando há
   fila viva ou rascunho.
3. Testar em transação reversível: retorno idempotente do mesmo caminho,
   isolamento contra vínculo alheio, uma única fila para replay e policy de
   update restrita ao dono. Rodar o teste SQL e mutante específico.

## Gate 3 — Revisão e validação local

1. Revisar o diff do Gate 1 antes de integrar; corrigir somente achados
   comprovados.
2. Revisar o diff do Gate 2, rodar `npm run test:unit`, o teste SQL da nova
   migration, mutante e `npm run build`.
3. Fazer smoke do app com rede simulada: gravar, interromper a requisição,
   fechar/abrir a rota e confirmar que a Home mostra o áudio preservado.

## Gate 4 — Rollout e E2E real, depois da aprovação do professor de teste

1. Aplicar a migration pelo fluxo normal do Supabase e publicar somente o
   frontend revisado; validar versão/saúde antes de criar dados reais.
2. Antes de iniciar o E2E, informar Luciano do professor e do vínculo que serão
   usados. O teste usa uma experimental realizada dentro da janela, cria apenas
   um rascunho no app, não confirma e não envia WhatsApp nem conteúdo à família.
3. Enviar um áudio real por uma sessão autenticada do professor, observar
   `storage.objects` -> `fabio_fila_audios` -> worker ->
   `lead_experimental_registros` e verificar a transcrição/campos na tela.
4. Confirmar o rascunho apenas se o professor de teste tiver sido avisado e o
   comportamento externo estiver explicitamente previsto; no teste padrão,
   descartar o rascunho e manter a evidência da fila/logs.

## Evidências de aceite

- Uma indisponibilidade entre upload e RPC não exige regravação e não cria
  duas filas.
- O mesmo Blob refeito após falha aponta ao mesmo objeto e ao mesmo `audio_id`.
- O professor vê claramente que pode sair e que o áudio está preservado.
- A fila experimental não é processada pelo Hermes nem dispara mensagem
  externa antes da confirmação humana.
- A agenda pode falhar por transporte sem apagar a gravação local.
