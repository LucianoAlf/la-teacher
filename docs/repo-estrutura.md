# LA Teacher · Estrutura do Repositório
### Decisões A3 (mesmo repo) + separação corpo × alma · 04/07/2026

**Repo novo: `la-teacher`** (GitHub `LucianoAlf/la-teacher`, privado).
O `fabio-backup` continua sendo **só a alma do agente** (SOUL/AGENTS/PERMISSOES/skills — deploy na VPS/Hermes). App e agente têm ciclos de deploy diferentes; misturar incha o contexto do Fábio.

## Um app, duas superfícies

App único Vite + React + TS + Tailwind + Supabase (padrão LA Organizer), com **rotas por perfil** — não monorepo com workspaces (menos atrito para o Claude Code, componentização compartilhada de graça):

- `/app/*` → professor (mobile-first, PWA instalável)
- `/painel/*` → coordenação (desktop-first, mesma base de componentes)

## Árvore

```
la-teacher/
├─ index.html
├─ vite.config.ts              # + plugin PWA (fase do S3)
├─ tailwind.config.ts          # mapeia var(--token) — ver frontend-tokens.md
├─ .env.example                # VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY
├─ src/
│  ├─ main.tsx                 # importa styles/tokens.css UMA vez
│  ├─ routes.tsx               # guard por sessão + perfil (professor | coordenação)
│  ├─ styles/
│  │  └─ tokens.css            # ÚNICA fonte de valores brutos (Fábio DS v1.0)
│  ├─ components/ui/           # componentes base (só tokens) — lista no frontend-tokens.md
│  ├─ features/
│  │  ├─ agenda/               # Sprint 2
│  │  ├─ registro/             # Sprint 3 (gravação → confirmação → sucesso)
│  │  ├─ alunos/               # Sprint 2 (lista) / S4 (perfil completo)
│  │  └─ chat/                 # Sprint 4
│  ├─ pages/
│  │  ├─ app/                  # Home, Agenda, Alunos, Login, VinculoPendente
│  │  └─ painel/               # entra na fase do Painel
│  ├─ lib/
│  │  ├─ supabase.ts           # client
│  │  ├─ api.ts                # SOMENTE RPCs app_* (nunca select direto em tabela)
│  │  └─ theme.ts              # useTheme
│  └─ types/
│     └─ db.ts                 # gerado: supabase gen types typescript
├─ supabase/
│  └─ migrations/
│     └─ 001-fundacao-fabio.sql   # espelho do SQL aplicado no LA Report
├─ docs/
│  ├─ design-system-fabio-v1.html
│  ├─ la-teacher-mapa-produto-v1-1.html
│  ├─ la-teacher-prototipo-golden-path.html   # spec visual viva do fluxo
│  ├─ frontend-tokens.md
│  └─ tese-relatorio-quintela.md
└─ prompts/
   └─ sprint2.md               # este pacote
```

## Regras de fronteira

1. **Dados**: o front fala com o LA Report **exclusivamente via RPCs `app_*`** (segurança resolvida no banco por `auth.uid()`; o professor nunca passa o próprio id). Sem `select` direto em tabela no cliente.
2. **Escrita pedagógica**: uma porta só — `app_confirmar_registro` → `registrar_aula_fabio`. Nem o app, nem o Painel, nem edge alguma grava `anotacoes_fabio` por outro caminho.
3. **Financeiro**: nenhum campo de valor/parcela chega ao bundle do professor (a RPC de carteira já não retorna).
4. **Alma × corpo**: prompts do agente, skills e memória do Fábio vivem no `fabio-backup`/Hermes; o app só enfileira trabalho (áudio na fila) e lê resultado.
