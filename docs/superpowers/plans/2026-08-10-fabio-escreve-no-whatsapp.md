# Fábio escreve no WhatsApp Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permitir que o professor registre conteúdo de aula por áudio e faça chamada avulsa pelo WhatsApp usando o mesmo motor e as mesmas guardas do app, com escolha explícita da aula, read-back, confirmação humana, idempotência e recibo autoritativo.

**Architecture:** O bridge identifica o professor pelo telefone, classifica apenas intenções fechadas e mantém a conversa em uma máquina de estados durável. O banco é a autoridade para candidatas, transições e escrita: cinco portas `fabio_*` reutilizam os mesmos núcleos das portas `app_*`; o LLM só classifica/redige e nunca recebe ferramenta de escrita. Um reconciliador independente acompanha o motor assíncrono, expira rascunhos e executa limpeza idempotente. A entrada na VPS é protegida por modo `off|shadow|pilot|on`, e cada mudança produtiva é um gate separado.

**Tech Stack:** Python 3 + bridge UAZAPI/Hermes na VPS, PostgreSQL 17/Supabase, Storage privado `fabio-audios`, RPCs PostgREST com `service_role`, systemd user services, testes SQL descartáveis via `scripts/rodar-teste-sql.mjs`, mutantes Node.js e testes Python sem rede.

---

## Fontes autoritativas e limites

- SPEC aprovada: `docs/superpowers/specs/2026-08-10-fabio-escreve-no-whatsapp-design.md`.
- Handoff e disciplina operacional: `RETOMADA.md` e `CLAUDE.md`.
- Referências oficiais de segurança: [Database Functions](https://supabase.com/docs/guides/database/functions), [Storage Access Control](https://supabase.com/docs/guides/storage/security/access-control) e [mudança para grants explícitos na Data API](https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically).
- Banco compartilhado: projeto Supabase `ouqwbbermlzqqvtqwlul`.
- Espelho versionado do bridge: `vps/fabio/`; runtime: `fabio@89.116.73.186:~/fabio-chat-bridge/`.
- O runner SQL usa `BEGIN/ROLLBACK`; aplicação definitiva usa `scripts/aplicar-sql.mjs` e só aparece depois de aprovação explícita.
- O modo novo começa `off`. Publicar schema ou código não ativa o fluxo.
- Não há ferramenta de escrita no Hermes, nem SQL direto do bridge contra tabelas pedagógicas.
- Não entram nesta fase: correção pós-confirmação, pedido de extensão de prazo e texto completo da devolutiva no WhatsApp.
- Nada de `git add -A`, `git add .`, stash, reset ou clean. Sempre conferir o disco antes de reservar migration.

## Gates de entrega

| Gate | Resultado verificável | Escrita produtiva? | Aprovação para avançar |
|---|---|---:|---|
| G0 — isolamento e contrato | worktree próprio, baseline verde, definições vivas capturadas | não | executor |
| G1 — banco em rollback | migrations 090/091, testes e mutantes verdes em transação descartada | não | revisão de código |
| G2 — banco publicado, entrada desligada | migrations aplicadas e contratos/ACLs relidos no banco | schema apenas | **Alf antes de aplicar** |
| G3 — bridge local | classificadores, ações e reconciliador verdes, sem rede real | não | revisão de código |
| G4 — shadow na VPS | classifica/mede, mas toda mensagem segue pelo comportamento antigo | logs apenas | **Alf antes do deploy** |
| G5 — piloto real | um professor autorizado fecha os dois fluxos ponta a ponta | sim, só piloto | **Alf escolhe professor e casos** |
| G6 — rollout | entrada geral ativada, observação e rollback provados | sim | **Alf autoriza** |

Em qualquer gate, falha fecha a entrada: não se “contorna” teste, não se amplia piloto e não se usa dado sintético em produção para forçar uma prova.

---

## G0 — isolar a execução e congelar o contrato vivo

### Task 1: Registrar a aprovação e preparar um worktree limpo

**Files:**

- Modify: `RETOMADA.md`
- Existing dirty doc: `docs/superpowers/specs/2026-08-10-fabio-escreve-no-whatsapp-design.md`
- Existing plan: `docs/superpowers/plans/2026-08-10-fabio-escreve-no-whatsapp.md`

- [ ] **Step 1: Confirmar que só os documentos aprovados estão sujos**

Run:

```powershell
git status --short
git rev-parse --short HEAD
git diff -- docs/superpowers/specs/2026-08-10-fabio-escreve-no-whatsapp-design.md docs/superpowers/plans/2026-08-10-fabio-escreve-no-whatsapp.md RETOMADA.md
```

Expected before the docs commit: HEAD `398505b`; no source, migration or VPS file modified.

- [ ] **Step 2: Atualizar `RETOMADA.md` com o checkpoint factual**

Record exactly: SPEC approved on 10/08/2026; plan created; implementation not started; next action G0; production gates G2, G4, G5 and G6 require Alf.

- [ ] **Step 3: Commit only the approved planning documents**

```powershell
git add -- docs/superpowers/specs/2026-08-10-fabio-escreve-no-whatsapp-design.md docs/superpowers/plans/2026-08-10-fabio-escreve-no-whatsapp.md RETOMADA.md
git diff --cached --check
git diff --cached --name-only
git commit -m "docs: aprovar plano do Fabio no WhatsApp"
```

Expected staged names: exactly the three documents above.

- [ ] **Step 4: Invoke `superpowers:using-git-worktrees`**

There is currently no `.worktrees/` or `worktrees/` convention in this repo. The skill must ask the user for the location before creating anything. Once selected, create branch `codex/fabio-whatsapp` from the docs commit and verify the chosen project-local directory is ignored, if applicable.

- [ ] **Step 5: Install dependencies and run the baseline inside the worktree**

```powershell
npm ci
npm run teste:084
npm run teste:086
python vps/fabio/teste_auditoria_carimbo.py
git status --short
```

Expected: all commands exit 0; worktree clean. If an existing baseline fails, stop and report it separately from this feature.

### Task 2: Capturar o contrato vivo antes de extrair núcleos

**Files:**

- Create: `docs/superpowers/evidence/2026-08-10-fabio-whatsapp-live-contract.md`

The live `app_atualizar_fatia` is newer than `005-confirmacao.sql`, and `app_status_audio_fila` plus `fabio_identidade_whatsapp` are not fully represented by a current local migration. Copying only local SQL would regress production.

- [ ] **Step 1: Read the project URL and current definitions through a read-only query**

Use the Management API/MCP only for `SELECT`. Capture:

```sql
select current_database(), current_user;

select p.oid::regprocedure::text as signature,
       pg_get_functiondef(p.oid) as definition,
       p.proacl
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'app_enfileirar_audio',
    'app_atualizar_fatia',
    'app_responder_presenca',
    'app_confirmar_registro',
    'app_registrar_presencas_aula',
    'app_registro_completo',
    'app_status_audio_fila',
    'fabio_identidade_whatsapp',
    'fn_janela_registro_dias',
    'fn_compor_texto_prontuario',
    'fn_presenca_declarada',
    'fn_pendencia_presenca',
    'fabio_emitir_presenca_por_registro_e_devolutiva',
    'registrar_aula_fabio',
    'fn_registrar_presencas_core',
    'fn_presenca_e_forte',
    'fn_sincronizar_gemeos_presenca'
  )
order by p.proname, p.oid::regprocedure::text;
```

- [ ] **Step 2: Capture table/storage contracts without secrets or row data**

Record columns, constraints, indexes, RLS flags and ACLs for `fabio_fila_audios`, `fabio_registros_aula` (troncos e fatias), `fabio_chat_mensagens`, `aulas`, `aluno_presenca`, `aula_registros_fabio_log` and `fabio_devolutivas`. Record policies and bucket metadata for `fabio-audios`; do not print tokens, phone numbers, message bodies or signed URLs.

- [ ] **Step 3: Write the evidence file**

The file must contain:

- timestamp and project id;
- exact function signatures and hashes of normalized definitions;
- the complete live definitions needed to preserve behavior;
- current ACL/RLS summary;
- explicit deltas from local migrations;
- statement “read-only; no production rows changed”.

- [ ] **Step 4: Gate the extraction against the snapshot**

Add a checklist asserting:

```text
app_atualizar_fatia: owner/status guard + whitelist + text regeneration preserved
app_confirmar_registro: write log + presence hook + devolutiva hook preserved
app_registrar_presencas_aula: anchor/roster/twin behavior preserved
app_* signatures: byte-for-byte same regprocedure identities
```

- [ ] **Step 5: Commit the evidence**

```powershell
git add -- docs/superpowers/evidence/2026-08-10-fabio-whatsapp-live-contract.md
git diff --cached --check
git commit -m "docs: congelar contrato vivo do registro de aula"
```

---

## G1 — banco inteiro provado em rollback

### Task 3: Reservar migrations 090/091 pelo CLI oficial

**Files:**

- Create: `supabase/migrations/090-fabio-whatsapp-acoes.sql`
- Create: `supabase/migrations/090-fabio-whatsapp-acoes.test.sql`
- Create: `supabase/migrations/091-as-cinco-portas-do-whatsapp.sql`
- Create: `supabase/migrations/091-as-cinco-portas-do-whatsapp.test.sql`
- Create: `scripts/mutantes-090.mjs`
- Create: `scripts/mutantes-091.mjs`
- Modify: `package.json`

- [ ] **Step 1: Recheck numbering on disk**

```powershell
Get-ChildItem supabase/migrations -File | Sort-Object Name | Select-Object -Last 12 -ExpandProperty Name
git fetch origin
git status --short
```

If 090 or 091 now exists, stop and renumber both migrations, tests, mutant scripts and package scripts consistently before writing SQL.

- [ ] **Step 2: Generate both migration files through the installed Supabase CLI**

```powershell
supabase --version
supabase migration new fabio_whatsapp_acoes
supabase migration new as_cinco_portas_do_whatsapp
```

Rename the two generated timestamp files with `git mv` to the reserved house names `090-fabio-whatsapp-acoes.sql` and `091-as-cinco-portas-do-whatsapp.sql`. Content edits after that use `apply_patch`.

- [ ] **Step 3: Add exact package scripts**

```json
"teste:090": "node scripts/rodar-teste-sql.mjs supabase/migrations/090-fabio-whatsapp-acoes.sql supabase/migrations/090-fabio-whatsapp-acoes.test.sql",
"mutantes:090": "node scripts/mutantes-090.mjs",
"teste:091": "node scripts/rodar-teste-sql.mjs supabase/migrations/091-as-cinco-portas-do-whatsapp.sql supabase/migrations/091-as-cinco-portas-do-whatsapp.test.sql",
"mutantes:091": "node scripts/mutantes-091.mjs"
```

Keep valid JSON and preserve all existing scripts.

### Task 4: Escrever primeiro os testes RED da máquina de ações

**Files:**

- Modify: `supabase/migrations/090-fabio-whatsapp-acoes.test.sql`
- Modify: `scripts/mutantes-090.mjs`

- [ ] **Step 1: Define the public database contract in the test**

The migration must create these restricted RPCs with fixed signatures:

```sql
public.fabio_aulas_candidatas(
  p_professor_id integer,
  p_fluxo text,
  p_referencia timestamptz default now()
) returns jsonb

public.fabio_iniciar_acao(
  p_professor_id integer,
  p_wa_message_id text,
  p_tipo text,
  p_storage_path text default null,
  p_payload jsonb default '{}'::jsonb
) returns jsonb

public.fabio_acao_ativa(p_professor_id integer) returns jsonb

public.fabio_aplicar_evento_acao(
  p_acao_id uuid,
  p_professor_id integer,
  p_wa_message_id text,
  p_evento text,
  p_dados jsonb default '{}'::jsonb
) returns jsonb

public.fabio_claim_acoes_processando(
  p_limite integer default 10,
  p_lease_segundos integer default 120
) returns jsonb

public.fabio_concluir_reconciliacao(
  p_acao_id uuid,
  p_lease_token uuid,
  p_evento text,
  p_dados jsonb default '{}'::jsonb
) returns jsonb

public.fabio_claim_acoes_limpeza(
  p_limite integer default 20,
  p_lease_segundos integer default 120
) returns jsonb

public.fabio_concluir_limpeza(
  p_acao_id uuid,
  p_lease_token uuid,
  p_resultado jsonb
) returns jsonb
```

All return envelopes use the stable shape:

```json
{"ok":true,"codigo":"acao_criada","acao":{},"dados":{}}
```

Business refusals return `ok=false` with a closed `codigo`; unexpected SQL errors still raise and are translated by the bridge.

- [ ] **Step 2: Write fixtures and twelve required SQL assertions**

The test runs under the house runner and must cover:

1. registration pool means `anotacoes_fabio` missing, window explicit, grouped by anchor, with no `chamada_feita` filter;
2. attendance pool means at least one roster member without `fn_presenca_e_forte`, regardless of relato;
3. candidate JSON exposes only stable DB IDs and contextual fields, never phone or free-form authority;
4. one active action per professor and unique initial `wa_message_id`;
5. same initial message returns the same action/result;
6. old event replay still returns its ledger result after newer events;
7. invalid state transition, professor mismatch, candidate outside `candidatas`, expired action and stale lease all fail closed;
8. `depois` preserves original `expira_em`; unrelated conversation does not mutate the action;
9. processing has no human expiry and is recoverable after lease expiry;
10. cancel/expire produces cleanup work, retains action/event audit and never declares a confirmed blob removable;
11. `anon` and `authenticated` cannot read tables or execute any new RPC; direct execution of helpers is revoked;
12. RLS, grants, constraints, indexes and fixed `search_path` are explicit.

Before the migration body exists, run:

```powershell
npm run teste:090
```

Expected: failure because the new relations/functions do not exist. Save the exact RED reason in the commit message notes; a syntax error in the test is not a valid RED.

- [ ] **Step 3: Write the 090 mutant runner against exact anchors**

Mutants must cover at least:

- registration filtered by `chamada_feita=false`;
- attendance incorrectly based on `vw_registro_pendencia`;
- proximity presented as authority rather than ranking;
- unique active-action index removed;
- event dedupe removed;
- candidate-membership guard removed;
- stale lease accepted;
- expiry leaves no cleanup claim;
- RLS or revoke removed.

The runner must mark `STALE` when an anchor no longer exists and treat `STALE` or surviving mutant as exit 1.

### Task 5: Implementar a migration 090

**Files:**

- Modify: `supabase/migrations/090-fabio-whatsapp-acoes.sql`

- [ ] **Step 1: Create `fabio_acoes_pendentes` with exact states**

Use UUID defaults from `gen_random_uuid()`, foreign keys to `professores`, `aulas`, `fabio_fila_audios` and `fabio_registros_aula`, and the SPEC columns. Enforce:

```sql
tipo in (
  'confirmar_intencao_audio', 'confirmar_intencao_chamada',
  'escolher_aula_audio', 'escolher_aula_chamada',
  'processando_audio', 'confirmar_registro', 'confirmar_chamada'
)

estado in ('aberta','processando','resolvida','adiada','cancelada','expirada','erro')
canal = 'whatsapp'
```

Create a partial unique index on `professor_id` for `estado in ('aberta','processando','adiada')`, a unique index on initial `wa_message_id`, an expiry index and a lease index.

- [ ] **Step 2: Create `fabio_acao_eventos` as the idempotency ledger**

Columns: `id`, `acao_id`, optional `chat_mensagem_id`, unique `wa_message_id`, `evento`, `resultado jsonb`, `criado_em`. Foreign keys do not cascade-delete the audit.

- [ ] **Step 3: Implement the two candidate pools**

`fabio_aulas_candidatas` validates `p_fluxo in ('registro','chamada')`, professor ownership, cancellation, future tolerance and `fn_janela_registro_dias()`. It returns ordered JSON with `aula_id`, `aula_ancora_id`, date/time, course/turma labels and roster `{aluno_id,nome}`. It does not accept transcription and does not choose a class.

For `registro`, source “sem relato” from the same `anotacoes_fabio` semantics as migration 083 and never filter attendance. For `chamada`, start from roster and `fn_presenca_e_forte`, never from `vw_registro_pendencia`.

- [ ] **Step 4: Implement atomic transition RPCs**

Every mutation locks the action `FOR UPDATE`, checks professor/state/expiry, inserts the event and transitions in one transaction. Exact accepted events:

```text
intencao_confirmada, intencao_negada,
shortlist_definida, pergunta_refinada, aula_escolhida,
audio_enfileirado, rascunho_pronto,
correcao_aplicada, confirmacao_solicitada,
confirmado, cancelado, adiado, retomado,
falha_temporaria, falha_terminal, expirado,
limpeza_solicitada, limpeza_concluida
```

The RPC derives allowed next type/state from current type/state/event; `p_dados` can only supply values validated against DB rows and current `candidatas`. It never trusts `p_dados` as ownership authority.

- [ ] **Step 5: Implement fenced claims**

Claims use `FOR UPDATE SKIP LOCKED`, generate `lease_token`, set `lease_expira_em`, and return only rows owned by that token. Completion requires matching unexpired token. Retry returns an action to claimable state with a bounded attempt counter in `payload`; terminal failure records `erro` without exposing raw SQL to the professor.

- [ ] **Step 6: Lock security explicitly**

For both tables: enable RLS, revoke all from `PUBLIC`, `anon`, `authenticated`, and do not create permissive policies. For all `fabio_*` and internal helpers: `SECURITY DEFINER SET search_path = pg_catalog, public`, revoke execute from `PUBLIC`, `anon`, `authenticated`; grant only the guarded `fabio_*` RPCs to `service_role`. Internal helpers are not granted to `service_role` directly.

- [ ] **Step 7: Run GREEN and mutants**

```powershell
npm run teste:090
npm run mutantes:090
```

Expected: test reports all assertions green and rollback fingerprint unchanged; every non-stale mutant is killed, and there are zero `STALE` anchors.

- [ ] **Step 8: Commit 090 only**

```powershell
git add -- supabase/migrations/090-fabio-whatsapp-acoes.sql supabase/migrations/090-fabio-whatsapp-acoes.test.sql scripts/mutantes-090.mjs package.json
git diff --cached --check
git commit -m "feat: criar maquina duravel de acoes do WhatsApp"
```

### Task 6: Escrever primeiro os testes RED das cinco portas

**Files:**

- Modify: `supabase/migrations/091-as-cinco-portas-do-whatsapp.test.sql`
- Modify: `scripts/mutantes-091.mjs`

- [ ] **Step 1: Fix the core and WhatsApp signatures in the test**

```sql
public.fn_enfileirar_audio_core(integer,text,integer,uuid,text)
public.fabio_enfileirar_audio(integer,integer,text,integer,uuid)

public.fn_atualizar_fatia_core(integer,uuid,text,jsonb)
public.fabio_atualizar_fatia(integer,uuid,text,jsonb)

public.fn_responder_presenca_core(integer,uuid,text)
public.fabio_responder_presenca(integer,uuid,text)

public.fn_confirmar_registro_core(integer,uuid,uuid,text)
public.fabio_confirmar_registro(integer,uuid,text)

public.fabio_registrar_presencas_aula(integer,integer,integer[])

public.fabio_status_audio_fila(integer,uuid)
public.fabio_registro_completo(integer,uuid)
```

The fifth write path continues ending in existing `fn_registrar_presencas_core`; no parallel writer is created.

- [ ] **Step 2: Write parity, ownership and timing tests**

Cover all twelve SQL/security items from the SPEC, including:

- current `app_*` regprocedure signatures unchanged;
- app and WhatsApp wrappers producing equal pedagogical effects from equal fixtures;
- differences only in actor/channel/origin audit;
- live `app_atualizar_fatia` whitelist and text regeneration preserved;
- `app_confirmar_registro` hooks for presence and devolutiva preserved;
- registration window checked at enqueue but not re-rejected at confirm;
- standalone attendance window rechecked at commit;
- WhatsApp ownership mismatch rejected on all seven public RPCs;
- corrections outside roster/whitelist rejected;
- `professor_whatsapp` accepted and synchronized to twins as a strong source;
- `confirmado_por` uses linked `professores.usuario_id`, nullable when no app user, while the action ledger remains authoritative;
- only service role executes `fabio_*`; no role executes internal core directly.

Run before implementation:

```powershell
npm run teste:091
```

Expected: valid RED from missing cores/wrappers.

- [ ] **Step 3: Write mutation operators for the five-door boundary**

At minimum kill mutations that remove owner guards, widen ACL, diverge an app/WhatsApp core call, bypass whitelist, remove text regeneration, create a second presence writer, remove `professor_whatsapp`, skip twin synchronization, apply window at the wrong confirmation, or send a devolutiva result as a receipt.

### Task 7: Implementar a migration 091 without regressing the app

**Files:**

- Modify: `supabase/migrations/091-as-cinco-portas-do-whatsapp.sql`

- [ ] **Step 1: Rebuild from the captured live definitions, not from migration 005 alone**

Copy each current function body from the G0 evidence into the migration, extract only the identity-dependent body into its core, and keep each `app_*` signature and result shape unchanged.

- [ ] **Step 2: Extract enqueue core**

`fn_enfileirar_audio_core` receives explicit professor, storage path, duration, optional record id and origin. It owns all current guards and inserts. The app wrapper passes `auth.uid()`-resolved professor and origin `app`; `fabio_enfileirar_audio` takes explicit professor and forces origin `whatsapp`.

- [ ] **Step 3: Extract correction cores**

`fn_atualizar_fatia_core` preserves the current whitelist, owner/status guards and regeneration through `fn_compor_texto_prontuario`. `fn_responder_presenca_core` preserves roster and allowed-answer validation. Both WhatsApp wrappers revalidate record ownership from `p_professor_id`.

- [ ] **Step 4: Extract confirmation core with explicit authorship**

`fn_confirmar_registro_core(p_professor_id,p_confirmado_por,p_registro_id,p_modo)` owns the current log writes, content writes, absence skipping, presence hook and devolutiva hook. The app wrapper passes `auth.uid()`; the WhatsApp wrapper resolves `professores.usuario_id` inside SQL. Neither trusts a user id supplied by Python.

- [ ] **Step 5: Reuse the one presence writer**

Extend `fn_registrar_presencas_core` input validation to `professor_whatsapp`, keep `fn_sincronizar_gemeos_presenca`, and make both app and WhatsApp preparation terminate in this core. Replace hardcoded strong-source shortcuts in the wrapper with `fn_presenca_e_forte` so `professor_whatsapp` is not accidentally downgraded.

- [ ] **Step 6: Add guarded read-back RPCs**

`fabio_status_audio_fila` and `fabio_registro_completo` accept explicit professor and return only a queue/record owned by that professor. Preserve the rich live app result without exposing other professors’ rows. These reads let the worker send authoritative read-back and receipts without direct table updates.

- [ ] **Step 7: Apply the same security boundary**

All new cores/wrappers use fixed search paths. Revoke default function execute immediately after creation. Preserve the current `authenticated` and `service_role` execution grants on `app_*`; grant `fabio_*` only to `service_role`. Do not grant new table access.

- [ ] **Step 8: Run focused and regression tests**

```powershell
npm run teste:091
npm run mutantes:091
npm run teste:084
npm run teste:086
npm run teste:019
npm run teste:020
```

Expected: all focused tests green, all mutants killed, existing app contracts green. If an older migration is documented as non-reapplicable/superseded, record that separately and run its surviving current contract test; never call it green merely because the bulk runner skipped it.

- [ ] **Step 9: Commit 091 only**

```powershell
git add -- supabase/migrations/091-as-cinco-portas-do-whatsapp.sql supabase/migrations/091-as-cinco-portas-do-whatsapp.test.sql scripts/mutantes-091.mjs package.json
git diff --cached --check
git commit -m "feat: compartilhar cinco portas entre app e WhatsApp"
```

### G1 checkpoint

- [ ] Request `superpowers:requesting-code-review` for migrations, tests and mutants.
- [ ] Re-run all focused commands after review fixes.
- [ ] Show Alf: changed files, RED/GREEN evidence, mutant totals, rollback fingerprint and zero production writes.
- [ ] Stop. Do not run `scripts/aplicar-sql.mjs` without explicit G2 approval.

---

## G2 — publicar o banco com a entrada ainda desligada

### Task 8: Preflight and apply the exact tested SQL

**Files:**

- No new code files
- Update after success: `RETOMADA.md`

- [ ] **Step 1: Recheck target and drift immediately before application**

Verify project id `ouqwbbermlzqqvtqwlul`, rerun the live-definition hashes from G0, check whether `fabio_acoes_pendentes`, `fabio_acao_eventos` or any planned RPC appeared, and inspect current migration filenames on disk. Any unexpected drift stops the gate and requires rebase/retest.

- [ ] **Step 2: Obtain explicit Alf approval for G2**

The approval text must clearly authorize permanent schema/function changes in the shared Supabase project. Approval for the plan alone is not G2 approval.

- [ ] **Step 3: Apply in order using the repository’s definitive runner**

```powershell
node scripts/aplicar-sql.mjs supabase/migrations/090-fabio-whatsapp-acoes.sql
node scripts/aplicar-sql.mjs supabase/migrations/091-as-cinco-portas-do-whatsapp.sql
```

Do not pass `.test.sql`; do not reconstruct SQL in a shell string.

- [ ] **Step 4: Verify the deployed definitions and security live**

Read `pg_get_functiondef`, `proacl`, RLS flags, policies, constraints and indexes. Assert:

```text
app_* signatures unchanged
fabio_* executable only by service_role
cores not directly executable by API roles
new tables RLS enabled and no anon/authenticated table grants
one-active-action and wa-message unique indexes present
fn_registrar_presencas_core accepts professor_whatsapp
```

Also run Supabase security/performance advisors and classify any finding as new, pre-existing or false positive; new security findings block the gate.

- [ ] **Step 5: Run one read-only smoke through service-role RPCs**

Call candidate/read RPCs for an existing professor without creating an action. Prove returned candidate rows all belong to that professor. Do not initiate a real action or create test rows in production.

- [ ] **Step 6: Record the production checkpoint**

Update `RETOMADA.md` with applied files, timestamp, live hashes, focused tests and the explicit statement: “schema published; WhatsApp ingress still off; no real flow enabled.”

- [ ] **Step 7: Commit only the handoff update**

```powershell
git add -- RETOMADA.md
git diff --cached --check
git commit -m "docs: registrar publicacao do banco do WhatsApp"
```

---

## G3 — bridge and reconciler proven locally

### Task 9: Implementar classificadores fechados e shortlist pura

**Files:**

- Create: `vps/fabio/fabio_whatsapp_intents.py`
- Create: `vps/fabio/teste_whatsapp_intents.py`
- Create: `vps/fabio/fixtures/whatsapp_intents.json`

- [ ] **Step 1: Write failing tests first**

Define and test these pure interfaces:

```text
AudioIntent = Literal["registro", "conversa", "ambiguo"]
TextIntent = Literal["chamada", "conversa", "ambiguo"]

classificar_intencao_audio(transcricao: str, llm_json: str | None) -> AudioIntent
classificar_intencao_texto(texto: str, llm_json: str | None) -> TextIntent
reduzir_shortlist(texto: str, candidatas: list[dict]) -> dict
interpretar_resposta_pendente(texto: str, acao: dict) -> dict
validar_patch_correcao(saida: dict, rascunho: dict, roster: list[dict]) -> dict
```

The implementation output is closed and validated. Invalid JSON, unknown label, timeout represented as `None`, content+presence, contradictory evidence or unsupported correction returns an explicit question/`ambiguo`; never defaults to writing.

- [ ] **Step 2: Build fixtures from redacted real phrases**

Include conversation audio, pedagogical record, ambiguous audio, clear attendance, ordinary conversation, mixed content+attendance, one compatible class, two/three choices, more than three requiring discriminant, roster-name contradiction, cancellation, deferral, unrelated question and corrections in text/audio. Remove names/phones not required for the behavioral case.

- [ ] **Step 3: Run RED**

```powershell
python vps/fabio/teste_whatsapp_intents.py
```

Expected: import/function failure before implementation.

- [ ] **Step 4: Implement strict parsing and deterministic evidence**

LLM output may only choose one closed label or one ID already supplied in `candidatas`. Deterministic code owns schema validation, candidate membership, date/time/course/roster contradiction and maximum three displayed options. Proximity can rank but cannot disambiguate two otherwise compatible classes.

- [ ] **Step 5: Run GREEN**

```powershell
python vps/fabio/teste_whatsapp_intents.py
```

- [ ] **Step 6: Commit**

```powershell
git add -- vps/fabio/fabio_whatsapp_intents.py vps/fabio/teste_whatsapp_intents.py vps/fabio/fixtures/whatsapp_intents.json
git diff --cached --check
git commit -m "feat: classificar intencoes fechadas do WhatsApp"
```

### Task 10: Implementar o orquestrador determinístico

**Files:**

- Create: `vps/fabio/fabio_whatsapp_actions.py`
- Create: `vps/fabio/teste_whatsapp_actions.py`

- [ ] **Step 1: Write fake-adapter tests first**

Use dependency injection; no network, Storage or production DB. Define:

```text
FabioWhatsappBackend.rpc(name: str, payload: dict) -> dict
FabioWhatsappBackend.download_audio(media_url: str, max_bytes: int) -> tuple[bytes, str, str]
FabioWhatsappBackend.upload_audio(storage_path: str, content: bytes, mime: str) -> None
FabioWhatsappBackend.remove_audio(storage_path: str) -> None

tratar_mensagem_professor(contexto: dict, backend: FabioWhatsappBackend) -> dict
```

Result shape:

```python
{
    "handled": bool,
    "reply": str | None,
    "forward_to_hermes": bool,
    "action_id": str | None,
    "code": str,
}
```

- [ ] **Step 2: Test every state-machine edge before implementation**

Cover the fourteen bridge proofs from the SPEC, especially: ambiguity before pool lookup, replay without duplicate upload/RPC, parallel conversation, existing action blocking a second request, `depois` without deadline renewal, correction through guarded RPC then read-back, and receipt only after positive commit.

- [ ] **Step 3: Implement the orchestrator**

The orchestrator:

1. loads current action;
2. interprets action-specific response before opening a new request;
3. forwards unrelated conversation to Hermes without changing action;
4. stages only `registro|ambiguo` audio at `whatsapp/{professor_id}/{wa_message_id}.{ext}`;
5. requests candidates only after closed intent;
6. stores only DB candidate IDs;
7. calls only the `fabio_*` RPCs;
8. translates closed DB codes, never raw SQL errors;
9. returns an authoritative receipt only from the RPC/read-back payload.

- [ ] **Step 4: Run tests and commit**

```powershell
python vps/fabio/teste_whatsapp_actions.py
git add -- vps/fabio/fabio_whatsapp_actions.py vps/fabio/teste_whatsapp_actions.py
git diff --cached --check
git commit -m "feat: orquestrar acoes guardadas do professor"
```

### Task 11: Implementar reconciliador, retry e limpeza

**Files:**

- Create: `vps/fabio/fabio_whatsapp_reconciler.py`
- Create: `vps/fabio/teste_whatsapp_reconciler.py`
- Create: `vps/fabio/fabio-whatsapp-reconciler.systemd.txt`

- [ ] **Step 1: Write lease/restart tests first**

Test: claim bounded batch, poll `fabio_status_audio_fila`, transition only at `aguardando_confirmacao`, retry temporary failures, stale-token refusal, terminal error, 24-hour expiry, confirmed-blob preservation, discarded-record cleanup and restart after lease expiry.

- [ ] **Step 2: Implement one-shot cycles**

```text
reconcile_once(backend: FabioWhatsappBackend, limit: int = 10) -> dict
cleanup_once(backend: FabioWhatsappBackend, limit: int = 20) -> dict
main() -> int
```

No sleep inside bridge/webhook. A systemd timer/service invokes bounded cycles. A cleanup claim first receives the database proof that no confirmed record or active action references the path; only then can Python remove the blob and call `fabio_concluir_limpeza`.

- [ ] **Step 3: Define the user systemd unit**

The mirror file must set working directory `~/fabio-chat-bridge`, load the existing protected environment file, run the reconciler as the `fabio` user, use restart/backoff, and never embed tokens in the unit. Reuse the repository’s existing user-service convention.

- [ ] **Step 4: Run and commit**

```powershell
python vps/fabio/teste_whatsapp_reconciler.py
git add -- vps/fabio/fabio_whatsapp_reconciler.py vps/fabio/teste_whatsapp_reconciler.py vps/fabio/fabio-whatsapp-reconciler.systemd.txt
git diff --cached --check
git commit -m "feat: reconciliar e limpar rascunhos do WhatsApp"
```

### Task 12: Interceptar o fluxo no bridge sob feature flag

**Files:**

- Modify: `vps/fabio/fabio_chat_bridge.py`
- Modify: `vps/fabio/README.md`
- Create: `vps/fabio/teste_whatsapp_bridge.py`
- Create: `vps/fabio/mutantes_whatsapp_registro.py`

- [ ] **Step 1: Write integration tests against the imported bridge**

Patch network/environment as existing bridge tests do. Prove:

- interception is after batching and before `generate_answer`;
- only professor+WhatsApp enters the new path;
- `off` preserves current behavior;
- `shadow` classifies/logs but performs no upload/action/write and still calls current Hermes behavior;
- `pilot` handles only ids in `FABIO_WHATSAPP_REGISTRO_PILOT_IDS`;
- `on` handles all identified professors;
- media webhook persists an idempotent inbox row before ACK, returns before transcription and never polls in `process_one`;
- no service-role value is logged;
- dynamic capability text is honest for non-pilot/pilot;
- receipt excludes `fabio_devolutivas` text.

- [ ] **Step 2: Add explicit ingress configuration**

```text
FABIO_WHATSAPP_REGISTRO_MODE=off|shadow|pilot|on
FABIO_WHATSAPP_REGISTRO_PILOT_IDS=comma-separated integer ids
FABIO_WHATSAPP_REGISTRO_MAX_AUDIO_BYTES=26214400
```

Default is `off`; unknown value fails to `off`. The reconciler remains capable of draining already-open actions when ingress is turned off.

- [ ] **Step 3: Wire the action handler**

Replace the daemon-only media ingestion with a durable inbox step: resolve identity and insert an idempotent `fabio_chat_mensagens` row (`kind='audio'`, `wa_message_id`) before returning the webhook ACK. Do not transcribe in the request. Extend claim/batch projections to carry `media_url`, `media_mime` and `wa_message_id`. After `claim_next_message`, hydrate every claimed audio row that lacks `media_extracted_text` by calling UAZAPI with its `wa_message_id`, then patch and return that same chat row with URL/MIME/transcription. A temporary failure leaves `fabio_done_at` null so the existing stale-claim path retries it; a replay still hits the unique `wa_message_id`. Preserve the hydrated media rows in the merged context so staging downloads the URL tied to the initiating `wa_message_id`. Do not coalesce two independent audio messages into one hidden write: leave the second unclaimed for the next cycle, when the active-action rules decide whether it is a correction or a new blocked request. After hydration and batching, invoke the new action handler before `generate_answer`. If `handled=false` or mode is shadow/off, continue through the existing path exactly once.

- [ ] **Step 4: Rewrite `CAPACIDADE_PROFESSOR` by effective mode**

For an enabled professor, say the guarded flow can register only after choice/read-back/confirmation and all other writes remain unavailable. For a disabled professor, keep the current no-write guidance. The LLM toolset remains unchanged in every mode.

- [ ] **Step 5: Add Python mutation tests**

Mutate at least: ambiguous→register, pool lookup before text intent, mixed text→attendance, shortlist membership bypass, pending generic message→confirm, duplicate webhook→second upload, receipt before RPC, devolutiva appended, interception after `generate_answer`, and mode default→on. All must be killed.

- [ ] **Step 6: Run complete local bridge suite**

```powershell
python vps/fabio/teste_whatsapp_intents.py
python vps/fabio/teste_whatsapp_actions.py
python vps/fabio/teste_whatsapp_reconciler.py
python vps/fabio/teste_whatsapp_bridge.py
python vps/fabio/mutantes_whatsapp_registro.py
python vps/fabio/teste_auditoria_carimbo.py
```

- [ ] **Step 7: Document operation and rollback**

`vps/fabio/README.md` must document env flags, systemd user commands, log commands, shadow/pilot/on semantics, drain behavior and safe rollback.

- [ ] **Step 8: Commit**

```powershell
git add -- vps/fabio/fabio_chat_bridge.py vps/fabio/README.md vps/fabio/teste_whatsapp_bridge.py vps/fabio/mutantes_whatsapp_registro.py
git diff --cached --check
git commit -m "feat: ligar fluxo guardado ao bridge do Fabio"
```

### G3 checkpoint

- [ ] Invoke `superpowers:requesting-code-review` for the complete branch.
- [ ] Invoke `superpowers:verification-before-completion` and rerun fresh focused SQL/Python tests.
- [ ] Verify `git diff origin/main...HEAD --stat` contains only planned files.
- [ ] Stop before copying anything to the VPS.

---

## G4 — deploy in shadow on the VPS

### Task 13: Preflight, backup and deploy without enabling writes

**Files deployed:**

- `vps/fabio/fabio_chat_bridge.py`
- `vps/fabio/fabio_whatsapp_intents.py`
- `vps/fabio/fabio_whatsapp_actions.py`
- `vps/fabio/fabio_whatsapp_reconciler.py`
- systemd user unit from the mirror

- [ ] **Step 1: Obtain explicit Alf approval for the VPS shadow deploy**

- [ ] **Step 2: Read-only preflight on the VPS**

```powershell
ssh -i ~/.ssh/id_ed25519_lahq_fabio_claude_code fabio@89.116.73.186 "cd ~/fabio-chat-bridge && pwd && git status --short 2>/dev/null || true; systemctl --user status fabio-chat-bridge --no-pager; python3 --version"
```

Compare checksums of every live file to the repository mirror. Unexpected live drift stops deployment for reconciliation; do not overwrite it blindly.

- [ ] **Step 3: Create recoverable backups with a timestamped explicit target**

Back up only the files being replaced inside `~/fabio-chat-bridge/backups/20260810-fabio-whatsapp/`. Verify the resolved target is under `~/fabio-chat-bridge/backups/` before copying.

- [ ] **Step 4: Copy source and install the user unit**

Use `scp` for exact files. Keep mode `FABIO_WHATSAPP_REGISTRO_MODE=shadow`; do not put service role/token in commands, logs or versioned files. Run `python3 -m py_compile` before restart.

- [ ] **Step 5: Start/restart user services and verify**

```text
systemctl --user daemon-reload
systemctl --user restart fabio-chat-bridge
systemctl --user enable --now fabio-whatsapp-reconciler.timer
systemctl --user status fabio-chat-bridge --no-pager
systemctl --user status fabio-whatsapp-reconciler.timer --no-pager
journalctl --user -u fabio-chat-bridge -n 100 --no-pager
```

Use the actual existing bridge unit name measured in preflight if it differs; do not guess and create a duplicate service.

- [ ] **Step 6: Observe shadow behavior**

For an agreed observation window, verify: messages still receive current behavior, shadow produces classification metrics, no row appears in `fabio_acoes_pendentes`, no `whatsapp/` blob is created, no `fabio_fila_audios.origem='whatsapp'` row appears, latency/error rate does not regress, and logs contain no message bodies/tokens.

- [ ] **Step 7: Roll back immediately if shadow changes behavior**

Set mode `off`, restore only timestamped changed files if needed, restart bridge, keep DB schema in place because it is additive/restricted, and verify current conversational flow returns.

- [ ] **Step 8: Record G4 evidence in `RETOMADA.md` and commit it**

Do not call this “feature live”; record “shadow only, no write path enabled.”

---

## G5 — controlled real pilot

### Task 14: Activate one real professor and prove both flows

- [ ] **Step 1: Alf selects the pilot professor and real eligible sessions**

No synthetic professor, fake attendance or fabricated class is inserted. Confirm consent, linked phone identity, expected app user link, eligible content class and eligible attendance class.

- [ ] **Step 2: Take a read-only before snapshot**

Record relevant action count, candidate result, queue/record rows, final class content, attendance/twin rows and notification queue state for only the selected real cases.

- [ ] **Step 3: Set `pilot` mode for that professor only**

Set `FABIO_WHATSAPP_REGISTRO_MODE=pilot` and exactly the approved professor id in `FABIO_WHATSAPP_REGISTRO_PILOT_IDS`; restart bridge and verify effective configuration without printing secrets.

- [ ] **Step 4: Prove audio registration end to end**

The professor sends a real audio. Verify in sequence:

1. intent is closed or the system asks;
2. shortlist uses only eligible DB IDs and asks when required;
3. original is staged once;
4. queue origin is `whatsapp`;
5. reconciler reaches authoritative read-back;
6. a correction, if naturally needed, goes through `fabio_atualizar_fatia`/`fabio_responder_presenca`;
7. no final content exists before explicit confirmation;
8. confirmation writes the expected targets and authorship/audit;
9. receipt matches DB and contains no devolutiva text;
10. notification worker remains the only owner of the devolutiva offer.

- [ ] **Step 5: Prove standalone attendance end to end**

Use a real eligible message. Verify intent before pool, roster preview, explicit confirmation, `professor_whatsapp` as strong source, twin synchronization and no content-record side effect.

- [ ] **Step 6: Prove one safe negative path**

With the same pilot, exercise cancellation or ambiguity naturally. Verify no final write, retained audit, cleanup idempotency and honest wording. Do not manufacture an expired production action merely to test the 24-hour job; that is already covered by rollback tests.

- [ ] **Step 7: Compare after snapshot**

Every changed productive row must map to the approved real messages. Separate “code deployed”, “worker healthy” and “real E2E passed” in the report.

- [ ] **Step 8: Stop and ask for G6 approval**

Keep pilot mode. A successful pilot does not authorize general rollout.

---

## G6 — general rollout, monitoring and handoff

### Task 15: Turn on ingress generally with a proven rollback

- [ ] **Step 1: Obtain explicit Alf approval**

- [ ] **Step 2: Re-run fresh production preflight**

Check bridge/worker health, open/erro/expired action counts, oldest lease, queue latency, Storage orphan candidates, DB advisors and notification-worker health.

- [ ] **Step 3: Set mode `on` and restart only the bridge**

The reconciler continues running. Verify effective mode from sanitized startup log.

- [ ] **Step 4: Observe first real flows**

Monitor counts and codes, not message content. Investigate any owner refusal, repeated event, lease starvation, orphan candidate, raw SQL error or premature receipt immediately.

- [ ] **Step 5: Prove rollback while preserving open actions**

Rollback ingress is `mode=off` plus bridge restart. Do not stop the reconciler until active actions are zero; it must drain flows already accepted. If a schema rollback is ever required, design a separate forward migration after assessing existing actions—never drop audit tables/functions ad hoc.

- [ ] **Step 6: Update docs and operational handoff**

Record commits, applied migrations, VPS checksums, systemd status, pilot evidence, rollout timestamp, monitoring queries and rollback outcome in `RETOMADA.md` and `vps/fabio/README.md`.

- [ ] **Step 7: Final verification and integration choice**

Invoke `superpowers:verification-before-completion`, then `superpowers:finishing-a-development-branch`. Re-run focused SQL and Python suites, check live function definitions/ACLs, check VPS services, and present merge/PR options. Do not merge or push without the user’s requested integration choice.

---

## Final acceptance matrix

| Requirement | Proof owner |
|---|---|
| ambiguous audio/text asks before any write | Python fixtures + mutants + pilot |
| two pools never cross-contaminate | SQL 090 tests + mutants |
| shortlist has only DB IDs and max 3 options | Python + SQL ownership tests |
| five app/WhatsApp doors share one core | SQL 091 parity + mutation |
| `professor_whatsapp` is strong and twins sync | SQL 091 + real attendance pilot |
| no direct API access to action tables/cores | live ACL/RLS readback + advisors |
| replay does not duplicate anything | SQL ledger + Python fake backend + pilot observation |
| pending action does not hijack conversation | Python state tests |
| webhook does not poll | bridge integration test + latency observation |
| expiry/cancel safely cleans only drafts | SQL lease/cleanup tests + Python worker tests |
| correction uses guarded RPC and re-reads DB | Python action tests + audio pilot |
| receipt follows commit and excludes devolutiva | SQL/Python tests + pilot |
| current app behavior remains compatible | live snapshot + 091 parity/regression |
| rollback stops new ingress but drains accepted work | shadow/pilot/on operational proof |

## Commit sequence

1. `docs: aprovar plano do Fabio no WhatsApp`
2. `docs: congelar contrato vivo do registro de aula`
3. `feat: criar maquina duravel de acoes do WhatsApp`
4. `feat: compartilhar cinco portas entre app e WhatsApp`
5. `feat: classificar intencoes fechadas do WhatsApp`
6. `feat: orquestrar acoes guardadas do professor`
7. `feat: reconciliar e limpar rascunhos do WhatsApp`
8. `feat: ligar fluxo guardado ao bridge do Fabio`
9. factual handoff commits after each approved production gate

No commit combines unreviewed SQL, bridge deployment and production evidence. The plan is complete only after G6; stopping at any earlier gate is a valid, explicitly documented checkpoint, not a claim that the feature is fully live.
