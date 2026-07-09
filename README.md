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
5. **Zero financeiro e zero contato no app do professor** — valor/parcela/telefone/whatsapp nunca chegam ao bundle (a comunicação com pai/aluno será mediada por dentro do app, em fase futura).
6. **Login por pessoa, carteira por vínculo** — professor multiunidade loga uma vez e alterna unidades.

## Stack & banco

- **Banco:** Supabase LA Report (`ouqwbbermlzqqvtqwlul`) — 222 tabelas, RLS onipresente. O app **integra** ao existente (não cria banco próprio).
- **Fundação do Fábio já existente:** RPC `registrar_aula_fabio`, view `vw_fabio_aulas_contexto`, coluna `aulas_emusys.anotacoes_fabio`.
- **Carteira = jornada canônica:** desde a migração 008, `app_minha_carteira` lê `vw_jornada_professor_atual` (fonte única, régua "Aula X/40"); `vw_fabio_carteira_professor` ficou para a agente Maria, fora do app.
- **Migrações deste projeto:** `supabase/migrations/` (001–008, espelho comentado do que está aplicado).

## Como navegar este repositório

| Pasta | O que tem |
|---|---|
| `docs/` | Design system, protótipo, mapa de produto, tese pedagógica, almas dos agentes, auditoria |
| `docs/ROADMAP.md` | **Comece aqui** — ordem de execução de tudo |
| `supabase/migrations/` | SQL de fundação e motor |
| `prompts/` | Pacotes de execução por sprint (para o Claude Code) |

## Rodando localmente (do zero)

Pré-requisitos: **Node 20+** e npm.

```bash
git clone https://github.com/LucianoAlf/la-teacher.git
cd la-teacher
npm install

cp .env.example .env      # depois edite o .env
```

No `.env`, preencha (a `anon key` é pública por design — a segurança é a RLS + as RPCs `app_*`):

```
VITE_SUPABASE_URL=https://ouqwbbermlzqqvtqwlul.supabase.co
VITE_SUPABASE_ANON_KEY=<anon/publishable key do projeto LA Report>
```

```bash
npm run dev        # sobe o Vite em http://localhost:5173
```

Rotas: `/app` (Home), `/app/agenda`, `/app/alunos`, `/app/login`, e `/dev/ds` (vitrine do design system, sem login).

### Scripts

| Comando | O que faz |
|---|---|
| `npm run dev` | servidor de desenvolvimento (HMR) |
| `npm run build` | type-check (`tsc`) + build de produção (`vite build`) |
| `npm run preview` | serve o build de produção localmente |

### Login do professor de teste

O app usa o Supabase Auth do LA Report. Para um professor entrar e ver a própria
agenda/carteira, é preciso **vincular** o usuário a um `professores.id` — passo a passo
em [`docs/seed-professor-teste.md`](docs/seed-professor-teste.md). Sem vínculo, o login
funciona mas cai na tela **VínculoPendente** (comportamento esperado).

### Regra de ouro do código (anti-hex)

Nenhuma cor/sombra/raio/fonte crua fora de `src/styles/tokens.css`. Verificação:

```bash
grep -rnE '#[0-9a-fA-F]{3,8}' src/ --include='*.tsx' --include='*.ts' --include='*.css' | grep -v tokens.css
# saída vazia = ok
```

## Status

🚧 Sprint 2 (app base) — Home, Agenda e Alunos com dados vivos; auth + vínculo; design
system em `/dev/ds`. Ver `docs/ROADMAP.md`. Próximo: Sprint 3 (motor de registro por voz).

---

*LA Music · Sistema Agent-First · 2026 · "Os humanos cuidam de gente; os agentes cuidam do operacional difícil de operar."*
