# LA Teacher · Tokens Semânticos & Componentização
### Regra de ouro do projeto — diretriz do Alf (04/07/2026)

> **Tokens definidos UMA vez, globalmente. Toda página nasce consumindo tokens e componentes base. Nenhuma página declara cor, sombra, raio ou fonte crua. Nunca.**

Fonte da verdade visual: **`design-system-fabio-v1.html`** (Fábio DS v1.0). Este guia diz onde os tokens vivem no código e como o Claude Code deve usá-los.

---

## 1 · Onde os tokens vivem

```
src/styles/tokens.css   ← ÚNICO lugar com valores brutos (hex, px, shadow)
src/main.tsx            ← importa tokens.css UMA vez (antes de tudo)
tailwind.config.ts      ← mapeia utilitários para var(--token)
```

`tokens.css` contém, copiado do Fábio DS: o bloco `:root` (paleta bruta: teal, ink, mist, funcionais, party, geometria, fontes) e os blocos `[data-theme="dark"]` e `[data-theme="light"]` (tokens **semânticos**: `--bg-app`, `--bg-surface`, `--text-primary`, `--brand`, `--success-soft`, `--shadow-fab`, `--focus-ring`…).

**Componentes e páginas só conhecem os semânticos.** A paleta bruta (`--teal-500`) é implementação interna do tokens.css — se um componente precisa de `--teal-500` direto, o token semântico certo está faltando: cria-se o token, não se usa o bruto.

## 2 · Tailwind mapeado (nunca cor arbitrária)

```ts
// tailwind.config.ts (trecho essencial)
export default {
  darkMode: ['selector', '[data-theme="dark"]'],
  theme: {
    extend: {
      colors: {
        'bg-app':'var(--bg-app)', 'bg-surface':'var(--bg-surface)',
        'bg-inset':'var(--bg-inset)', 'bg-hover':'var(--bg-hover)',
        'text-primary':'var(--text-primary)', 'text-secondary':'var(--text-secondary)',
        'text-muted':'var(--text-muted)',
        'border-subtle':'var(--border-subtle)', 'border-strong':'var(--border-strong)',
        brand:'var(--brand)', 'brand-text':'var(--brand-text)',
        'brand-soft':'var(--brand-soft)', 'on-brand':'var(--on-brand)',
        success:'var(--success)', 'success-text':'var(--success-text)', 'success-soft':'var(--success-soft)',
        danger:'var(--danger)', 'danger-text':'var(--danger-text)', 'danger-soft':'var(--danger-soft)',
        warning:'var(--warning)', 'warning-text':'var(--warning-text)', 'warning-soft':'var(--warning-soft)',
        info:'var(--info)', 'info-text':'var(--info-text)', 'info-soft':'var(--info-soft)',
      },
      borderRadius: { sm:'var(--r-sm)', md:'var(--r-md)', lg:'var(--r-lg)', xl:'var(--r-xl)', full:'var(--r-full)' },
      boxShadow: { card:'var(--shadow-card)', fab:'var(--shadow-fab)' },
      fontFamily: { sans:'var(--font)', mono:'var(--mono)' },
    },
  },
}
```

Uso correto: `bg-surface text-text-primary border-border-subtle rounded-lg shadow-card`.
Uso **proibido**: `bg-[#2A9D8F]`, `text-[#9CA3AF]`, `style={{color:'#...'}}`, classes `bg-teal-500` do Tailwind default.

## 3 · Tema

- `data-theme` no `<html>` (dark = padrão do app do professor).
- Hook `useTheme()` em `src/lib/theme.ts`: lê/salva preferência (`localStorage`), aplica no `documentElement`.
- Nenhum componente checa o tema: os tokens já resolvem. Se um componente tem `if (dark)`, está errado.

## 4 · Componentes base obrigatórios (`src/components/ui/`)

Nascem no P0 do Sprint 2, copiando o comportamento visual do Fábio DS e do protótipo:

| Componente | Papel |
|---|---|
| `Button` | primary / ghost / sm / block |
| `Card` | superfície com título opcional (ícone + "right slot") |
| `Badge` | ok / warn / danger / brand / info |
| `AulaRow` | linha de aula (hora, info, badge, dot de status) |
| `FabioCard` | card do briefing (gradiente brand-soft) |
| `FieldCard` | campo do molde (label + valor editável + variante dever) |
| `Fatia` | accordion por aluno (avatar, badge de presença, corpo) |
| `Fab` | botão central de microfone (círculo, aprovado como está) |
| `TabBar` | navegação inferior |
| `Toast` | feedback transitório |
| `ScreenHeader` | cabeçalho de tela com voltar |
| `EmptyState` | vazio com direção (nunca só "sem dados") |

Página = composição de componentes + chamadas de API. **Página não estiliza.**

## 5 · Checklist de aceite (todo PR / todo prompt)

1. `grep -rnE '#[0-9a-fA-F]{3,8}' src/ --include='*.tsx' --include='*.ts' --include='*.css' | grep -v tokens.css` → **vazio**.
2. Nenhum `style=` inline com cor/sombra/fonte.
3. Nenhuma classe Tailwind de cor default (`bg-teal-*`, `text-gray-*`…) nem arbitrária (`bg-[#...]`).
4. Alternar o tema na tela nova: tudo legível nos dois modos sem ajuste local.
5. Componente novo genérico? Vai para `ui/`. Específico de feature? `features/<área>/components/`.

*Se o item 1 falhar, o prompt não está concluído — corrigir antes de seguir.*
