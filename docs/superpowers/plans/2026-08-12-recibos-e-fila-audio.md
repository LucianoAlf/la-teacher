# Recibos por Canal e Fila de Audio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Registros feitos no aplicativo nao enviam recibo ao WhatsApp, e o professor acompanha um audio ate o preview sem reenviar depois de uma falha transitoria.

**Architecture:** O banco continua como fonte do canal: `fabio_fila_audios.origem` e a origem autoritativa do registro. O outbox de recibo somente aceita registros de origem `whatsapp`, tanto ao enfileirar quanto ao reivindicar linhas antigas. O app interpreta `tem_erro` como erro atual somente enquanto o audio ainda nao normalizou e passa a exibir o rascunho com identificacao da aula; a API impede uma segunda gravacao enquanto ja houver audio vivo ou rascunho para a mesma aula.

**Tech Stack:** PostgreSQL/Supabase migrations e RPCs, React/TypeScript, Vitest, Vite, Python notification worker na VPS.

---

### Task 1: Fechar o outbox de recibo pelo canal de origem

**Concluída — commit `66d509b` (`fix: restringir recibos ao canal WhatsApp`).**

**Files:**
- Create: `supabase/migrations/20260812163000_recibo_so_whatsapp_e_fila_ativa.sql`
- Create: `supabase/migrations/20260812163000_recibo_so_whatsapp_e_fila_ativa.test.sql`
- Create: `scripts/mutantes-20260812163000.mjs`

- [x] **Step 1: Write the failing SQL test**

Criar fixtures de registro raiz confirmado com `origem='app'` e `origem='whatsapp'`. Provar que `fn_enfileirar_registro_recibo` retorna `skipped=true, motivo='origem_app'` sem notificacao para app, cria uma notificacao para WhatsApp, e que `fabio_claim_registro_recibo` nao reivindica notificacao historica ligada a raiz app.

- [x] **Step 2: Run test to verify it fails**

Run: `node scripts/rodar-teste-sql.mjs supabase/migrations/095-recibo-de-registro-no-whatsapp.sql supabase/migrations/20260812163000_recibo_so_whatsapp_e_fila_ativa.test.sql`

Expected: falha nos casos que exigem a guarda de origem.

- [x] **Step 3: Write minimal implementation**

Redefinir `fn_enfileirar_registro_recibo` para retornar `jsonb_build_object('ok', true, 'skipped', true, 'motivo', 'origem_app')` quando a raiz nao tiver origem WhatsApp, sem inserir em `fabio_notificacoes`. Redefinir `fabio_claim_registro_recibo` com `raiz.origem = 'whatsapp'`, preservando guardas de devolutiva e lease.

- [x] **Step 4: Verify tests and mutants pass**

Run: `node scripts/rodar-teste-sql.mjs supabase/migrations/095-recibo-de-registro-no-whatsapp.sql supabase/migrations/20260812163000_recibo_so_whatsapp_e_fila_ativa.sql supabase/migrations/20260812163000_recibo_so_whatsapp_e_fila_ativa.test.sql`

Run: `node scripts/mutantes-20260812163000.mjs`

Expected: `falhas: 0` e todos os mutantes mortos.

- [x] **Step 5: Commit**

```powershell
git add supabase/migrations/20260812163000_recibo_so_whatsapp_e_fila_ativa.sql supabase/migrations/20260812163000_recibo_so_whatsapp_e_fila_ativa.test.sql scripts/mutantes-20260812163000.mjs
git commit -m "fix: restringir recibo ao WhatsApp"
```

### Task 2: Expor apenas falha atual e bloquear gravacao concorrente

**Concluída — commit `074dbed` (`fix: evitar reenvio enquanto áudio processa`).**

**Files:**
- Modify: `supabase/migrations/20260812163000_recibo_so_whatsapp_e_fila_ativa.sql`
- Modify: `supabase/migrations/20260812163000_recibo_so_whatsapp_e_fila_ativa.test.sql`
- Modify: `scripts/mutantes-20260812163000.mjs`

- [x] **Step 1: Add failing SQL cases**

Criar fila `normalizado` com `erro` historico e provar `app_status_audio_fila(...).tem_erro=false`. Criar fila viva e provar que nova chamada para mesma aula devolve o mesmo `audio_id` e `ja_em_processamento=true`, sem segunda linha. Criar rascunho sem fila viva e provar retorno `registro_id_existente` com `rascunho_existente=true`.

- [x] **Step 2: Run test to verify it fails**

Run: `node scripts/rodar-teste-sql.mjs supabase/migrations/095-recibo-de-registro-no-whatsapp.sql supabase/migrations/20260812163000_recibo_so_whatsapp_e_fila_ativa.test.sql`

Expected: falhas nos tres contratos novos.

- [x] **Step 3: Write minimal implementation**

Redefinir `app_status_audio_fila` para considerar erro atual somente em `pendente|transcrevendo|transcrito|erro`. Redefinir `fn_enfileirar_audio_core`, antes do insert e somente no modo novo, para devolver a fila viva da mesma aula; na ausencia dela, devolver rascunho existente da mesma aula. Manter deduplicacao por `storage_path` e o caminho de complemento inalterados.

- [x] **Step 4: Verify tests and mutants pass**

Run: `node scripts/rodar-teste-sql.mjs supabase/migrations/095-recibo-de-registro-no-whatsapp.sql supabase/migrations/20260812163000_recibo_so_whatsapp_e_fila_ativa.sql supabase/migrations/20260812163000_recibo_so_whatsapp_e_fila_ativa.test.sql`

Run: `node scripts/mutantes-20260812163000.mjs`

Expected: `falhas: 0` e todos os mutantes mortos.

- [x] **Step 5: Commit**

```powershell
git add supabase/migrations/20260812163000_recibo_so_whatsapp_e_fila_ativa.sql supabase/migrations/20260812163000_recibo_so_whatsapp_e_fila_ativa.test.sql scripts/mutantes-20260812163000.mjs
git commit -m "fix: impedir duplicidade enquanto audio processa"
```

### Task 3: Levar o professor ao preview e identificar o rascunho

**Concluída — commits `ea51cfd` (`test: corrigir import do verificador de presenca`) e `193859a` (`fix: retomar fila de audio sem reenviar`).**

**Files:**
- Modify: `src/lib/api.ts`
- Modify: `src/features/registro/Processando.tsx`
- Modify: `src/pages/app/Home.tsx`
- Modify: `src/features/registro/GravarAula.tsx`
- Create: `src/features/registro/Processando.test.tsx`

- [x] **Step 1: Write failing Vitest cases**

Cobrir: `normalizado` com erro historico continua polling e navega a `/app/confirmar/:id`; resposta `ja_em_processamento=true` abre o audio existente; `rascunho_existente=true` abre o preview; Home mostra turma e horario, com fallback humano.

- [x] **Step 2: Run test to verify it fails**

Run: `npm run test:unit -- src/features/registro/Processando.test.tsx`

Expected: falha pelos comportamentos ausentes.

- [x] **Step 3: Write minimal implementation**

Ampliar `EnfileirarResultado` com retornos do core. Em `GravarAula`, interpretar fila viva e rascunho sem novo blob. Em `Processando`, exibir vermelho apenas para erro atual e manter polling retomavel. Em `Home`, mostrar turma/horario dos campos e `Registro pronto para conferir` como fallback.

- [x] **Step 4: Verify unit tests and build**

Run: `npm run test:unit`

Run: `npm run build`

Expected: exit code 0 nos dois.

- [x] **Step 5: Commit**

```powershell
git add src/lib/api.ts src/features/registro/Processando.tsx src/pages/app/Home.tsx src/features/registro/GravarAula.tsx src/features/registro/Processando.test.tsx
git commit -m "fix: acompanhar audio ate o preview"
```

### Task 4: Publicar sem interromper workers e validar em producao

**Estado parcial:** banco aplicado e verificado no Supabase. A migration `20260812163000` foi registrada; o ensaio com rollback confirmou 35 linhas e schema idêntico; as ACLs foram confirmadas corretas e há zero recibos ativos. Deploy Vercel, integração e validações pós-deploy continuam pendentes.

**Files:**
- Modify: `RETOMADA.md`
- Create: `docs/superpowers/evidence/2026-08-12-recibos-e-fila-audio.md`

- [x] **Step 1: Apply migration after preflight**

Confirmar que a versao esta livre em `supabase_migrations.schema_migrations`, aplicar apenas a nova migration pela rotina do repositorio e registrar o historico. Nao pausar `fabio-registro-recibo.timer` nem bridge.

- [x] **Step 2: Verify database contract**

Ler as definicoes das quatro funcoes alteradas e confirmar que nao existem recibos app pendentes aptos a envio. Nenhuma mensagem WhatsApp deve ser enviada para teste.

- [ ] **Step 3: Deploy app and verify artifact**

Executar o deploy configurado, registrar URL/commit e carregar o preview. Verificar no browser Home e Processando com o bundle novo, sem professor real nem dado sintetico em producao.

- [ ] **Step 4: Document and commit**

Atualizar a retomada e escrever evidencia com comandos, migration, commits e verificacoes; commitar somente estes arquivos.

### Task 5: Integrar e verificar o resultado integrado

- [ ] **Step 1: Review complete diff**

Conferir contra este plano: sem limpeza automatica de Valdo, sem envio a familia, sem worker parado e sem recibo app elegivel.

- [ ] **Step 2: Push, merge and post-merge verification**

Fazer push, PR e merge conforme autorizacao desta conversa. Atualizar `main` e rodar testes/build no resultado integrado.

- [ ] **Step 3: Final deployment checks**

Confirmar migration registrada, timer e bridge ativos, e worker sem claim de origem app.
