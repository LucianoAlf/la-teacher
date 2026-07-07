# 🎼 LA TEACHER · Dossiê Central
### A fonte de verdade única do projeto — não depende da memória de nenhum chat
### Última atualização: 07/07/2026 (v2 — P5 captura de áudio concluída)

> **Como usar este documento:** este é o estado consolidado do LA Teacher. Sempre que uma conversa (aqui, LA HQ, Claude Code) precisar de contexto, é daqui que se puxa. Quando algo mudar de forma estrutural, atualize este arquivo. Ele mora em `docs/DOSSIE-CENTRAL.md` no repo `la-teacher`.

---

## 0 · O QUE É O PROJETO

**LA Teacher** — app agent-first (PWA) para os ~46 professores da LA Music registrarem aulas por voz. O agente pedagógico **Fábio** transforma a fala do professor em relatório estruturado, gravado na aula de cada aluno.

- **North Star:** % de aulas com relatório em ≤24h. Baseline auditada **45,9%** → meta **>90%**.
- **Meta de lançamento:** **21/07/2026**, com o Matheus + professores selecionados.
- **Filosofia:** "Os humanos cuidam de gente; os agentes cuidam do operacional difícil de operar."
- **Regra de trabalho:** quando o Alf questiona um design, explica-se o racional e ele decide — nunca alterar sem aprovação.

---

## 1 · AS TRÊS FRENTES (o modelo de execução em paralelo)

O projeto avança em três frentes que não se travam:

| Frente | Dono | O que faz | Estado |
|---|---|---|---|
| **A · App** | Alf + Claude Code | Constrói o PWA (captura, telas, confirmação) | 🟢 Captura de áudio CONCLUÍDA (P5) · próximo: tela de Confirmação (P7) |
| **B · Dados** | Hugo (sessão própria) | Sync Emusys↔LA Report, webhooks, crons | 🟢 Grade nas 3 unidades OK |
| **C · Cérebro** | chat do LA HQ (guia Alf via PowerShell na VPS) | Config do Hermes/Fábio (webhook, assinatura) | ⚪ Config do webhook pendente |
| **Banco** | Claude (este chat) | Migrações, RPCs, arquitetura de dados | 🟢 Fundação + Motor aplicados |

---

## 2 · ARQUITETURA DO FÁBIO (decisão fechada pelos 3 chats)

**O Fábio NÃO roda numa Edge Function com IA própria.** Ele roda no **Hermes (VPS LAHQ)**, reaproveitando a assinatura do GPT-5.5 (via Codex) e a alma já existentes. "Uma alma, dois canais" — o WhatsApp e o app batem no mesmo cérebro.

### Fluxo completo (assíncrono via banco)
```
1. App: professor grava áudio → sobe pro Supabase Storage (bucket fabio-audios)
        → chama app_enfileirar_audio(aula_id, path, duração, registro_id)
2. Edge Function "CARTEIRO" (sem IA): POST assinado (HMAC-SHA256)
        → http://<vps-lahq>:8644/webhooks/registro-aula
3. Hermes/Fábio: baixa o áudio → transcreve (STT nativo do Hermes) →
        normaliza (Alma v1.1, separa turma comum vs. nominal) →
        grava tronco+fatias em fabio_registros_aula com status 'aguardando_confirmacao'
4. App: Realtime detecta o registro → mostra tela de Confirmação →
        professor confere → confirma → app_confirmar_registro grava por aluno
```

### Por que assíncrono (não síncrono)
Se a Edge Function esperasse a resposta do Fábio, daria timeout (transcrever+normalizar leva segundos). No modelo assíncrono, o Fábio grava no banco quando termina, e o app ouve via Realtime. Sem timeout, robusto. **O banco já está pronto pra isso** (tabela + Realtime + status).

### O CARTEIRO (Edge Function) — payload cravado
```json
{
  "aula_id": <aula_local_id>,        // PK de aulas_emusys — resolve professor interno E emusys por join
  "unidade_id": "<uuid>",
  "professor_id": <professores.id INTERNO>,  // ex. 25 — NUNCA o emusys_professor_id (182)
  "audio_url": "<signed url do storage>",
  "registro_id": null                 // null=novo; uuid=correção por voz de rascunho
}
```
**Regra dos IDs (alinhada entre os 3 chats):** o `professor_id` do payload é SEMPRE o `professores.id` interno, porque é o que a `registrar_aula_fabio` usa pra gravar. O `emusys_professor_id` fica fora do payload; se o Fábio precisar, tira da aula. WhatsApp e app mandam o mesmo ID interno → zero retrabalho.

### Segurança do carteiro (crítico — o Fábio tem escrita no banco)
Um webhook exposto que aciona um agente com escrita no banco é alvo de alto valor. Regras inegociáveis:
1. **HMAC-SHA256 obrigatório** — o Hermes recusa POST sem assinatura válida.
2. **Toolset mínimo na rota** — a sessão de webhook do Fábio acessa só a skill de registro + a RPC de gravar. Nada de terminal/acesso amplo.
3. **Porta única de escrita** — a gravação passa sempre por `registrar_aula_fabio` (idempotente, validação por aluno). Mesmo acionado de forma inesperada, o Fábio não escreve fora do trilho.
4. Config da VPS (habilitar webhook, expor porta 8644 com firewall, sandbox) é feita pelo **Alf, guiado pelo chat do LA HQ** via PowerShell.

---

## 3 · OS DOIS NÍVEIS DE CORREÇÃO (decisão fechada)

Existem dois tipos de correção, com caminhos distintos — não confundir:

**Nível 2 · Corrigir o RASCUNHO (antes de confirmar)** — o comum, é o do dia 21.
- Professor grava, Fábio monta rascunho (`aguardando_confirmacao`), professor manda 2º áudio ("esqueci de mencionar a Maria").
- Caminho: `app_enfileirar_audio` com **`registro_id` preenchido** → o Fábio atualiza o rascunho em `fabio_registros_aula`.
- Ao confirmar, grava normal (modo `novo`). **Não vira segunda via.**

**Nível 1 · Corrigir aula JÁ GRAVADA (depois de confirmar)** — raro, fica pra depois do dia 21.
- Caminho: `app_confirmar_registro(registro_id, 'complementar')` anexa à anotação; `'substituir'` troca.
- **Porta aberta, mas não precisa construir agora.**

Os três contratos casam: `app_enfileirar_audio` (o `registro_id` decide novo vs. correção de rascunho) · `app_confirmar_registro` (aceita `p_modo`, default `novo`) · `registrar_aula_fabio` (modos `novo`/`substituir`/`complementar`).

---

## 4 · A REGRA DE OURO DO FÁBIO (a separação de turma)

Numa aula de turma, o professor grava **um áudio só**, com dois tipos de conteúdo misturados:
- **Sem nome de aluno** ("trabalhei respiração") → COMUM → tronco → vai pra TODOS os presentes.
- **Com nome** ("com a Maria o exercício X") → NOMINAL → fatia daquele aluno.
- Cada aluno recebe: **comum + o individual dele**. Na dúvida, trata como comum (errar pra "todos" é seguro; atribuir errado é grave).

Isso é o **modelo tronco+fatias**, já suportado pelo banco (não precisa refatorar). A inteligência de separar vive na **Alma de Normalização do Fábio v1.1** (`docs/fabio-alma-normalizacao-v1.md`).

**Turma = um áudio só.** A separação por aluno é o Fábio que faz. O app NUNCA pede um áudio por aluno.

---

## 5 · ESTADO DO BANCO (LA Report · ouqwbbermlzqqvtqwlul) — confirmado ao vivo 07/07

### Migrações aplicadas
- **001 (Fundação)** ✅ — tabelas `fabio_registros_aula`, `fabio_fila_audios`, `risco_evasao` + `vw_risco_atual` (security_invoker); RPCs `app_minha_agenda`, `app_minha_carteira`, `app_meus_registros`, `app_confirmar_registro`; `fn_professor_do_usuario()`; bucket `fabio-audios`; vínculo `professores.usuario_id`; perfil 'professor'; campos em `farmer_tarefas`; Fábio em `agentes`; RLS.
- **002 (Motor)** ✅ — `app_enfileirar_audio` (com correção por voz), `fn_fabio_chama_edge` (dispara via Vault), `fn_fabio_retry_fila` + cron `fabio-retry-fila` (5 min), `app_confirmar_registro` v2 **com gravação POR ALUNO** e parâmetro `p_modo`, trigger de disparo, índice de confirmação.
- **004 (Hugo)** ✅ — `app_minha_agenda_mes` (mês inteiro numa chamada, filtra canceladas).

### As 6 RPCs `app_*` (a única via de dados do app)
`app_minha_agenda` · `app_minha_agenda_mes` · `app_minha_carteira` · `app_meus_registros` · `app_enfileirar_audio` · `app_confirmar_registro`

### Realtime ligado em: `fabio_registros_aula`, `fabio_fila_audios`

### ✅ Captura provada ao vivo (P5, 07/07)
2 áudios do Matheus na `fabio_fila_audios` (aulas 193326/193327), `professor_id 25` resolvido pelo banco (app nunca passa ID), path no bucket começando com auth.uid(), status 'pendente' (aguardando o carteiro/Hermes — o cron de retry parou em 5 tentativas, inofensivo). Offline-first testado (IndexedDB → banner → religou → upload automático).

### ⚠️ Pendente no banco (não bloqueia captura)
- **Secrets no Vault** (`fabio_edge_url`, `fabio_edge_token`) — só existem depois que a Edge carteiro tiver URL. Sem eles, o pipeline não dispara. Entra no fim.

---

## 6 · ESTADO DO SYNC (Frente B · Hugo) — 🟢 GRADE COMPLETA

Confirmado ao vivo 07/07: **as 3 unidades têm grade futura**.
| Unidade | Aulas futuras |
|---|---|
| Recreio | 2.298 |
| Campo Grande | 2.715 |
| Barra | 1.553 |
| Aula mais futura no espelho | 11/08/2026 |

### Como os dados entram (arquitetura definida)
- **Grade futura + presença** → **cron** (edge `sync-grade-futura-emusys`, hoje→+35d, diário). Rede de arrasto.
- **Movimentações** (matrícula nova/renovação/trancamento/finalização/**alterada**, experimental, evasão) → **webhook** do Emusys. Fonte fresca, tempo real. Bisturi.
- Regra: **webhook = fonte primária e instantânea; cron = rede de segurança que reconcilia 1x/dia.** ("cinto + suspensório")

### Novidades liberadas pelo Emusys (CEO Mateus, 07/07)
- Múltiplos webhooks por evento (mesmo evento pra várias URLs).
- Webhook `matricula_alterada` (troca de curso/dia/professor — payload com `alteracao.descricao` HTML + matrícula completa).
- Endpoint `/faturas` (financeiro — **não interessa ao app do Fábio**; é da Sol/Maria).
- Bug de professor-vazio-em-turma **corrigido** (94%+ das turmas futuras vêm com professor).

---

## 7 · ROADMAP (3 fases) — ver dashboard vivo

Dashboard HTML clicável: `la-teacher-roadmap-dashboard.html` (marca tarefas, salva no navegador).

- **Fase 1 · Fundação & App Base** — ~85% (auditoria, fundação, login, Sprint 2, sync das 3 unidades ✅; faltam: propagar Alma v1.1, pendências de segurança).
- **Fase 2 · Motor de Registro por Voz** — em andamento (banco ✅; **captura de áudio CONCLUÍDA e provada ponta a ponta ✅** — P5, commit 1dfc84e; falta: Edge carteiro + config VPS + tela de Confirmação P7).
- **Fase 3 · Inteligência & Coordenação** — futura (risco, alertas, Home completa, webhooks de movimentação, painel da coordenação, agentes Lia/Sol).

---

## 8 · PENDÊNCIAS DE ATENÇÃO

### 🔒 Segurança (URGENTE)
- Rotacionar os **3 tokens do Emusys** (CG/Barra/Recreio) — colados em chat.
- Revogar o **token `ghp_` do GitHub** — colado em chat.

### Técnicas
- **Propagar Alma v1.1** para o `fabio-backup` (Hermes) — "uma alma, dois canais" exige sincronia.
- **Bug conhecido:** RPC `maria_lareport_evasoes_mes_detalhe` lê `evasoes_v2` legada → refatorar para `movimentacoes_admin`.
- **Hugo:** versionar o modelo de churn (hoje só notebook local, sem git — bus factor).
- **Config da VPS (Alf + chat do LA HQ, via PowerShell):** habilitar webhook do Hermes, expor porta 8644 com HMAC+sandbox, criar rota `registro-aula`. Prompt pronto entregue.

---

## 9 · COORDENADAS TÉCNICAS

- **Banco LA Report:** `ouqwbbermlzqqvtqwlul`
- **Unidades:** Campo Grande `2ec861f6-023f-4d7b-9927-3960ad8c2a92` · Recreio `95553e96-971b-4590-a6eb-0201d013c14d` · Barra `368d47f5-2d88-4475-bc14-ba084a9a348e`
- **Professor-piloto:** Matheus Felipe Lourenço · professor_id **25** · usuario_id **32** · `matheus.felipe@lamusic.com.br` · Recreio (emusys 182) + Campo Grande (emusys 897) · dá aula ter/qui
- **API Emusys:** base `https://api.emusys.com.br/v1` · header `token: <unidade>` · rate limit 60/min · IDs namespaced por unidade · v1.2.2
- **Hermes:** VPS LAHQ · webhook adapter porta 8644 · roda GPT-5.5 via Codex · STT nativo
- **Repos:** `LucianoAlf/la-teacher` (app) · `LucianoAlf/fabio-backup` (alma) · `LucianoAlf/LAperformanceReport` (LA Report)
- **Chaves de resolução:** `aulas_emusys.id` (aula_local_id, a PK) resolve professor interno + emusys por join · chave única `emusys_id + unidade_id` garante idempotência · aula de turma = 1 linha por aluno

---

## 10 · GLOSSÁRIO DE AGENTES (escala musical: Mi-Fá-Sol-Lá)

- **Fábio** (Fá) — pedagógico: registro de aulas, briefing, jornada. Vive no Hermes.
- **Lia** — Sucesso do Aluno/Jornada: assiduidade, onboarding, renovações, NPS, risco.
- **Sol** — ADM/Gestão: relatórios, cobrança, anamnese, alertas. Cobrança consulta risco da Lia antes de escalar.
- **Mila** (Mi) — SDR.

---

---

## 11 · LOG DE PROGRESSO (marcos com data — atualizar a cada avanço)

> Regra: sempre que uma frente entregar algo estrutural, adicione uma linha aqui. Assim qualquer chat vê o histórico sem depender de memória.

**07/07/2026**
- ✅ Migração 002 (motor) aplicada e verificada — enfileirar áudio, confirmar por aluno (com p_modo), cron de retry.
- ✅ **P7 — Tela de Confirmação concluída (commit 3346948). PRIMEIRA AULA DA HISTÓRIA GRAVADA POR VOZ:** turma de canto C_Ter_15, 3 alunos (Davi/Marina/Sofia), cada um recebeu comum+individual na sua própria aula (202886/202885/202878). A regra tronco+fatias funcionando em produção. Cutucada nos campos null funcionando.
- ✅ Bug de integração corrigido (migração 006): app_confirmar_registro passava origem='app' pra registrar_aula_fabio (que só aceita audio|texto) → traduzido pra 'audio'. A 1ª confirmação real teria falhado sem o fix.
- ✅ Migração 005: app_registro_completo, app_registros_pendentes, app_atualizar_fatia (edição inline com merge).
- ✅ Amarrados os dois níveis de correção por voz (rascunho via registro_id; aula gravada via complementar/substituir).
- ✅ Cravada a regra dos IDs no payload do carteiro (aula_id resolve tudo; professor_id sempre o interno).
- ✅ Hugo: grade futura sincronizada nas 3 unidades (Recreio 2.298, CG 2.715, Barra 1.553) + cron da grade ligado.
- ✅ Emusys (Mateus) liberou: webhook matricula_alterada, múltiplas URLs por evento, endpoint /faturas (não usado pelo app).
- ✅ **P5 — Captura de áudio concluída e provada ponta a ponta** (commit 1dfc84e): gravar → Storage → enfileirar → pipeline. Offline-first testado. 2 áudios do Matheus na fila.
- ✅ Definida arquitetura do Fábio-carteiro (Edge sem IA → webhook Hermes 8644 → grava no banco → app lê via Realtime).
- ⏳ Prompt entregue ao chat do LA HQ pra config do webhook do Hermes na VPS.

**06/07/2026**
- ✅ Auditoria do LA Report (3 fases). Fundação do Fábio descoberta já existente.
- ✅ Migração 001 (fundação) aplicada. Login do Matheus criado.
- ✅ Sprint 2 completo (P0→P4): app base no ar (Home, Agenda, Alunos).
- ✅ Alma do Fábio v1.1 (regra de separação de turma). Contrato de Alerta v1.0. Health Score v2.

---

*Dossiê Central · LA Music · Sistema Agent-First · mantido no repo como fonte de verdade única.*
*"Quem constrói ponte não é arrogante — arrogante é quem cobra pedágio."* 🌉🎼
