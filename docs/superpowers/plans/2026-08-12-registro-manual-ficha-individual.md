# Plano de implementação — registro manual por ficha individual

**Objetivo:** permitir que o professor escolha, na própria agenda, entre gravar áudio e preencher durante a aula uma ficha individual por aluno, sem criar outro prontuário nem outra fonte de presença.

**Arquitetura:** o fluxo manual reutiliza `fabio_registros_aula`, `app_registro_completo` e `app_confirmar_registro`. Uma RPC autenticada abre raiz/fatias a partir do roster canônico; outra salva o agregado completo com concorrência otimista; uma terceira muda o rascunho para `aguardando_confirmacao`. Só a confirmação existente materializa presença e grava o prontuário.

## 1. Contrato PostgreSQL

**Arquivos:**

- Criar `supabase/migrations/20260812220500_registro_manual_ficha_individual.sql`
- Criar `supabase/migrations/20260812220500_registro_manual_ficha_individual.test.sql`
- Alterar `package.json`

Implementar e provar:

1. `modo_entrada` (`audio|manual`) e `versao >= 1`, com defaults retrocompatíveis.
2. Índice parcial único para uma raiz manual aberta por professor/aula.
3. `app_abrir_rascunho_manual(integer)` com professor derivado do JWT, mesma janela/cancelamento/roster do áudio, raiz/fatias atômicas e nenhuma escrita em `aluno_presenca`.
4. `app_salvar_rascunho_manual(uuid, integer, jsonb, jsonb)` com whitelist, fatias exatamente do servidor, escrita atômica e `conflito_de_versao`.
5. `app_preparar_rascunho_manual(uuid, integer)` que apenas promove o agregado para a revisão existente.
6. Privilégios mínimos: somente `authenticated` executa as três portas públicas; helpers permanecem privados.

## 2. Contrato TypeScript e estado local

**Arquivos:**

- Alterar `src/lib/api.ts`
- Criar `src/features/registroManual/modelo.ts`
- Criar `src/features/registroManual/modelo.test.ts`
- Criar `src/features/registroManual/rascunhoLocal.ts`
- Criar `src/features/registroManual/rascunhoLocal.test.ts`

Implementar e provar:

1. Tipos do agregado manual e wrappers das três RPCs.
2. Operações puras de copiar campo e duplicar ficha, limitadas às seis chaves permitidas e aos IDs de fatia presentes no agregado.
3. Detecção explícita de sobrescrita antes da confirmação da cópia.
4. Cache IndexedDB/local de transporte separado da fila de áudio, rotulado como local até resposta do servidor.

## 3. Interface da agenda e formulário

**Arquivos:**

- Alterar `src/features/agenda/SessaoRow.tsx`
- Alterar `src/features/agenda/CardSessoesDoDia.tsx`
- Alterar `src/pages/app/Home.tsx`
- Alterar `src/pages/app/Agenda.tsx`
- Alterar `src/routes.tsx`
- Criar `src/features/registroManual/RegistroManual.tsx`

Implementar:

1. Dois controles diretos e equivalentes na linha: microfone e caderno.
2. Página móvel com um cartão por aluno e campos na ordem aprovada: repertório, atividades, objetivo, observações, dever e progresso.
3. Autosave após pausa, estados `Salvando`, `Salvo` e `Não salvo neste dispositivo`.
4. Ações `Copiar campo` e `Duplicar ficha`, seleção de destinos e confirmação quando houver sobrescrita.
5. Aviso de áudio aberto sem merge implícito e atalho para o preview do áudio.
6. Botão `Revisar e confirmar` levando ao preview canônico.

## 4. Preview canônico

**Arquivos:**

- Alterar `src/features/registro/Confirmar.tsx`
- Alterar `src/lib/api.ts`

Quando `modo_entrada=manual`, ocultar o tronco vazio e exibir nos cartões individuais todos os seis campos. O ato final continua chamando `app_confirmar_registro`; nenhuma nova gravação ou presença nasce no frontend.

## 5. Verificação e publicação

1. Rodar teste SQL descartável com rollback e impressão digital de produção.
2. Rodar `npm run test:unit` e `npm run build`.
3. Validar no navegador em 390×844 e desktop: botões, rolagem, cópia, duplicação, autosave e preview.
4. Aplicar a migration no projeto principal do Supabase, sem branch.
5. Atualizar `RETOMADA.md` com RPCs, migration, provas e próximo passo.
6. Commitar, publicar PR/merge e promover o artefato Vercel já validado.
7. Repetir a simulação controlada na agenda real do professor Matheus em 17/08, sem fabricar presença nem deixar rascunho residual.
