# Pendências detalhadas no chat do Fábio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permitir que o Fábio liste e explique as pendências canônicas de conteúdo e presença do professor identificado no WhatsApp.

**Architecture:** O bridge detecta intenção explícita de pendências e pré-busca, com service role e professor_id já resolvido, as duas RPCs read-only existentes. O bloco compacto entra no prompt; o Hermes continua sem MCP/SQL e nenhuma escrita acontece nessa consulta.

**Tech Stack:** Python 3, `unittest`, Supabase PostgREST RPC, Hermes bridge, systemd user services.

---

### Task 1: Pré-busca canônica e fail-closed

**Files:**
- Modify: `vps/fabio/fabio_chat_bridge.py`
- Test: `vps/fabio/teste_whatsapp_bridge.py`

- [ ] **Step 1: Write the failing tests**

Adicionar testes que provem: intenção explícita aciona as duas RPCs com o
`professor_id` da linha; conversa comum não consulta; falha de uma fonte fica
registrada sem apagar a outra.

- [ ] **Step 2: Run tests to verify they fail**

Run: `python vps/fabio/teste_whatsapp_bridge.py -v`

Expected: FAIL porque o prefetch de pendências ainda não existe.

- [ ] **Step 3: Write minimal implementation**

Criar detector fechado de intenção, wrapper das duas RPCs e compactador do
resultado. Integrar o bloco somente em `build_prompt` para identidade professor.

- [ ] **Step 4: Run focused tests**

Run: `python vps/fabio/teste_whatsapp_bridge.py -v`

Expected: PASS.

- [ ] **Step 5: Commit**

Run: `git add vps/fabio/fabio_chat_bridge.py vps/fabio/teste_whatsapp_bridge.py docs/superpowers/specs/2026-08-12-pendencias-no-chat-do-fabio-design.md docs/superpowers/plans/2026-08-12-pendencias-no-chat-do-fabio.md && git commit -m "feat: levar pendencias canonicas ao chat do Fabio"`

### Task 2: Regressão, publicação e prova produtiva

**Files:**
- Verify: `vps/fabio/teste_whatsapp_bridge.py`
- Verify: `vps/fabio/teste_whatsapp_actions.py`
- Deploy: `/home/fabio/fabio-chat-bridge/fabio_chat_bridge.py`

- [ ] **Step 1: Run the WhatsApp regression suite**

Run: `python -m unittest discover -s vps/fabio -p "teste_whatsapp*.py" -v`

Expected: PASS, zero failures.

- [ ] **Step 2: Verify the protected channel contract**

Confirmar na configuração viva que `api_server` continua com `skills_leitura`,
`memory`, `todo`, `vision`, `no_mcp`, sem SQL, terminal ou arquivos.

- [ ] **Step 3: Back up and deploy the bridge**

Criar backup timestampado do arquivo vivo, copiar o artefato versionado e
reiniciar `fabio-chat-bridge.service`.

- [ ] **Step 4: Run a read-only Matheus probe**

Construir o prompt de uma mensagem simulada do professor 25 e provar que ele
contém os dois pools reais, sem inserir mensagem nem enviar WhatsApp.

- [ ] **Step 5: Push and report**

Run: `git push -u origin codex/fabio-pendencias-whatsapp`

Expected: branch publicada e VPS saudável.
