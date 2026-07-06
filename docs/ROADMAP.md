# 🎼 LA TEACHER · Roadmap-Mestre de Execução
### O mapa único para não se perder · 06/07/2026 · banco validado ao vivo

> **Como usar:** siga os blocos na ordem. Cada passo diz o **artefato** que o alimenta, **onde** roda (Claude Code / SQL / você / Claude-chat) e o **aceite** que prova que terminou. Não pule bloco. Marque `[x]` ao concluir.

---

## 📍 ONDE ESTAMOS (estado real do banco — 06/07)
- LA Report `ouqwbbermlzqqvtqwlul`: **222 tabelas**, fundação do Fábio pré-existente (RPC `registrar_aula_fabio`, views `vw_fabio_*`, coluna `anotacoes_fabio`).
- **Nada da migração 001 aplicado ainda** (0 `fabio_*`, 0 `app_*`, sem `risco_evasao`/bucket/vínculo). Terreno limpo.
- 58 professores · 0 com login · 27 usuários admin/unidade com auth.
- Auditoria completa (Fases 1-3) ✅ · Decisões fechadas ✅ · Almas escritas ✅.

## 🗂️ OS 17 ARTEFATOS (biblioteca do projeto)
**Fundação visual/produto:** `design-system-fabio-v1.html` · `la-teacher-prototipo-golden-path.html` · `la-teacher-mapa-produto-v1-1.html` · `la-teacher-frontend-tokens.md` · `la-teacher-repo-estrutura.md`
**Banco:** `la-teacher-sql-001-fundacao.sql` · `la-teacher-sql-002-motor-registro.sql`
**Execução:** `la-teacher-sprint2-prompts.md` · `la-teacher-sprint3-prompts.md`
**Almas/pedagogia:** `fabio-alma-normalizacao-v1.md` · `Relatorio_de_Aula_LA_Music_Tese_Completa.md` (Quintela) · `la-music-health-score-v2-spec.md` · `contrato-de-alerta-v1.md`
**Auditoria/dados:** `auditoria-la-report-relatorio.md` · `auditoria-la-report-fase1/2/3.sql` · `raio-x-por-unidade.sql`

---

# BLOCO 0 · PREPARAÇÃO DO TERRENO (hoje, ~40 min)

- [ ] **0.1 · Criar repo** `LucianoAlf/la-teacher` (privado) no GitHub.
- [ ] **0.2 · Semear a documentação** na estrutura de `la-teacher-repo-estrutura.md`:
  - `docs/` ← design-system, prototipo, mapa-v1-1, frontend-tokens, alma-normalizacao, tese-quintela, health-score-spec, contrato-de-alerta, auditoria-relatorio
  - `supabase/migrations/` ← `001-fundacao-fabio.sql` (=sql-001), `002-motor-registro.sql` (=sql-002)
  - `prompts/` ← sprint2, sprint3
  - *Onde:* você, no computador. *Aceite:* repo com as 3 pastas populadas.
- [ ] **0.3 · Delegações em áudio** (paralelo, não bloqueia):
  - **Hugo:** versionar o modelo em repo hoje · mandar rascunho de schema da `risco_evasao` · bug: RPC `maria_lareport_evasoes_mes_detalhe` lê a `evasoes_v2` legada (Maria responde evasão congelada em fev) · qual job roda `calcular_health_score_alunos_batch` e horário.
  - **Quintela:** validar `fabio-alma-normalizacao-v1.md` + `contrato-de-alerta-v1.md` (tom e regras).
  - **Anne:** testar o protótipo sem instrução (achou o microfone?).
- [ ] **0.4 · Decisão do piloto (A2):** 3-5 professores no **Recreio** (recomendação: melhor cultura de registro). Só decidir; anunciar depois.

---

# BLOCO 1 · SPRINT 2 — APP BASE (a semana)
### Guia: `prompts/sprint2.md` · Regra viva: checklist anti-hex em todo prompt

- [ ] **1.1 · P0 — Scaffold + tokens globais + componentes base**
  *Onde:* Claude Code. *Artefatos:* frontend-tokens, design-system, prototipo.
  *Aceite:* `/dev/ds` mostra os 12 componentes nos 2 temas · grep anti-hex vazio.
- [ ] **1.2 · P1 — Migração 001 no LA Report**
  *Onde:* Claude Code (MCP Supabase) **ou** me peça pra aplicar via `apply_migration` daqui.
  *Artefato:* `001-fundacao-fabio.sql`. *Aceite (eu confiro ao vivo):* `fabio_registros_aula`=0 linhas, `vw_risco_atual` sem erro, 4 RPCs `app_*`, bucket `fabio-audios`, `professores.usuario_id` existe. Depois: `supabase gen types` → `src/types/db.ts`.
- [ ] **1.3 · P2 — Auth + vínculo do professor**
  *Aceite:* professor de teste loga; sem vínculo cai em "VínculoPendente"; logout ok.
  *Sub-passo humano:* seed do professor-piloto (doc `seed-professor-teste.md` sai no P2).
- [ ] **1.4 · P3 — Home com dados vivos**
  *Aceite:* Home lista aulas reais de hoje (BRT), contador "X de Y", pendências de ontem.
- [ ] **1.5 · P4 — Agenda + Alunos (leitura)**
  *Aceite:* navegação 3 telas com dados vivos; busca de alunos; README sobe o projeto do zero.

**✅ DoD Sprint 2:** professor-piloto usa Home/Agenda/Alunos com dados reais · sem financeiro/risco no bundle · anti-hex verde no repo.

---

# BLOCO 2 · SPRINT 3 — MOTOR DE REGISTRO (o coração)
### Guia: `prompts/sprint3.md` · Depende do Bloco 1 concluído

- [ ] **2.0 · Pré-req do Fábio:** decidir chave de IA (Anthropic direto na edge — recomendado) e criar secrets no Vault (`fabio_edge_url`, `fabio_edge_token`).
- [ ] **2.1 · Migração 002** (motor) — *Aceite (eu confiro):* RPCs `app_enfileirar_audio`/`app_confirmar_registro v2`, cron `fabio-retry-fila`, trigger de disparo.
- [ ] **2.2 · P5 — Captura de áudio offline-first** (iOS=mp4!) → bucket + fila.
- [ ] **2.3 · P6 — Edge `fabio-processa-audio`** (Groq STT + Alma) — usa `fabio-alma-normalizacao-v1.md` como system prompt lido do repo.
- [ ] **2.4 · P7 — Tela de Confirmação** (tronco+fatias, cutucadas, checkpoint).
- [ ] **2.5 · P8 — Confirmar (gravação POR ALUNO) + Sucesso** — *Teste de fogo:* turma 3 presentes+1 ausente grava 3 aulas, log com 3 linhas, ausente não grava.
- [ ] **2.6 · P9 — Corrigir por voz + acabamento.**
- [ ] **2.7 · Áudio real de cobaia** (você ou aliado nº1): 1-2 min de aula real = caso de teste de ouro.

**✅ DoD Sprint 3:** golden path real ponta a ponta · North Star sai do papel (contador ≤24h na Home).

---

# BLOCO 3 · INTELIGÊNCIA & COORDENAÇÃO (pós-golden-path)
### Ordem flexível — começa quando o registro estiver rodando no piloto

- [ ] **3.1 · Risco preditivo em produção** — fundir spec (`health-score-v2`) + rascunho do Hugo → job diário populando `risco_evasao` (role `ml_jobs`). *Antes:* Hugo versiona o modelo (0.3).
- [ ] **3.2 · Migração 003 — Contrato de Alerta** (`alerta_config`/`alerta_dono`/`alerta_log`) via `contrato-de-alerta-v1.md`.
- [ ] **3.3 · Painel da Coordenação** (`/painel`) — funil 1.199→147→74 + Fila de Casos (farmer estendido) sobre as 30+ views prontas.
- [ ] **3.4 · Ativação das agentes** (Lia/Sol) plugadas no Contrato + governança padrão.
- [ ] **3.5 · Backfill de motivos 2025** (fonte: `movimentacoes_admin`) + higiene de dado (CG sem categoria, "Saúde" duplicado).

---

# 🔒 REGRAS PERMANENTES (valem em todo bloco)
1. **Tokens globais, zero hex local** — anti-hex é aceite de todo PR.
2. **Dados só via RPCs `app_*`** — nunca select direto de tabela no cliente.
3. **Uma porta de escrita pedagógica:** `registrar_aula_fabio`.
4. **Zero financeiro/risco cru** no app do professor.
5. **Design questionado = explico + você decide** (nunca altero sem aval).
6. **Nada novo até o repo existir** (a régua anti-dispersão).
7. **Corpo × alma:** app no `la-teacher`; alma do Fábio no `fabio-backup`.

# 🎯 O PRÓXIMO CLIQUE
**Bloco 0.1 → 0.2.** Cria o repo e joga a documentação nas pastas. Quando terminar, me diz "repo pronto" que a gente dispara o **P0** — e, se quiser, eu já aplico a **migração 001 ao vivo** daqui no LA Report (agora tenho acesso de escrita) e te entrego o banco pronto pro P2, economizando um passo inteiro.
