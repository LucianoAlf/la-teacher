# LA Teacher 🎼

**A casa do Fábio** — app agent-first para os professores da LA Music registrarem aulas por voz, com o agente pedagógico Fábio transformando fala em relatório estruturado.

> North Star: **% de aulas com relatório em ≤24h** — baseline auditada **45,9%** → meta **>90%**.

---

## O que é

Um PWA (React + TypeScript + Vite + Tailwind + Supabase) com duas superfícies no mesmo repositório:

- **`/app`** — o professor (mobile-first, instalável): grava um áudio ao fim da aula, o Fábio estrutura nos Moldes A/B/C, o professor confere e confirma. O texto é gravado na aula de cada aluno.
- **`/painel`** — a coordenação (desktop-first): funil de risco, Fila de Casos com SLA, KPIs.

O agente **Fábio** tem alma própria (prompt de normalização) e vive no runtime Hermes; este repositório é o **corpo** (o app). A alma fica em [`fabio-backup`](https://github.com/LucianoAlf/fabio-backup).

## Princípios inegociáveis

1. **Tokens semânticos globais** — cores/sombras/raios/fontes só em `src/styles/tokens.css`. Nenhuma página declara hex. O checklist anti-hex é critério de aceite de todo PR.
2. **Dados só via RPCs `app_*`** — o cliente nunca faz `select` direto em tabela.
3. **Uma porta de escrita pedagógica** — tudo passa por `registrar_aula_fabio`.
4. **Fábio nunca inventa** — campo não dito = cutucada na Confirmação, jamais preenchimento por dedução.
5. **Zero financeiro no app do professor** — valor/parcela nunca chegam ao bundle.
6. **Login por pessoa, carteira por vínculo** — professor multiunidade loga uma vez e alterna unidades.

## Stack & banco

- **Banco:** Supabase LA Report (`ouqwbbermlzqqvtqwlul`) — 222 tabelas, RLS onipresente. O app **integra** ao existente (não cria banco próprio).
- **Fundação do Fábio já existente:** RPC `registrar_aula_fabio`, views `vw_fabio_aulas_contexto` / `vw_fabio_carteira_professor`, coluna `aulas_emusys.anotacoes_fabio`.
- **Migrações deste projeto:** `supabase/migrations/` (001 fundação, 002 motor de registro).

## Como navegar este repositório

| Pasta | O que tem |
|---|---|
| `docs/` | Design system, protótipo, mapa de produto, tese pedagógica, almas dos agentes, auditoria |
| `docs/ROADMAP.md` | **Comece aqui** — ordem de execução de tudo |
| `supabase/migrations/` | SQL de fundação e motor |
| `prompts/` | Pacotes de execução por sprint (para o Claude Code) |

## Status

🚧 Sprint 2 (app base) — em execução. Ver `docs/ROADMAP.md`.

---

*LA Music · Sistema Agent-First · 2026 · "Os humanos cuidam de gente; os agentes cuidam do operacional difícil de operar."*
