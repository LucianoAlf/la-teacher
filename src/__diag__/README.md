# Harness de diagnóstico das telas do professor

```bash
npm run diag
```

Sobe um Vite na porta **5211** servindo `diag-tremida.html`, que monta a tela
**real** (`RegistroManual.tsx`) trocando só duas coisas por dublês:

| trocado | por | por quê |
|---|---|---|
| `lib/api` | `stub-api.ts` | não precisar de sessão de produção pra abrir a tela |
| `lib/auth` | `stub-auth.tsx` | idem — nenhuma credencial real envolvida |

Tudo o mais é o código que vai pro professor: componente, design system,
moldura, IndexedDB.

## Por que isso existe

Em 18/08/2026 o Matheus relatou "tremida ao digitar" no caderno da aula. Sem
harness não havia como reproduzir — a tela exige login, aula do dia e roster.
Com ele deu pra **medir**: 37 teclas produziam **74 trocas** no selo do
cabeçalho ("Não salvo" 71,7px ⇄ "Só neste aparelho" 109px, duas por tecla).
Depois do conserto, **2** — e as duas no começo da rajada. A mesma régua nos
dois lados; foi ela que também mostrou que consertar só a porta síncrona **não
bastava** (o `.then` do gravador local ainda apagava o banner de conflito).

## Pegadinhas que já custaram tempo

- **`cacheDir` próprio** (`node_modules/.vite-diag`). Sem isso o dev server
  normal (5183) e este compartilham o pré-bundle, os hashes divergem e a página
  carrega **duas cópias do React** → `Invalid hook call`.
- **Aba em segundo plano congela `setTimeout`.** Pra marcar o passo entre teclas
  use `MessageChannel` (o truque do scheduler do React), que não é estrangulado.
- **Não bombeie os prazos longos entre uma tecla e outra.** Disparar o debounce
  de 800ms a cada tecla faz uma ida ao servidor por caractere — isso é artefato
  do instrumento, e já me fez ler regressão onde não havia.

## Interruptores

`window.__diagConflito = true` faz o servidor recusar por versão (exercita o
banner de conflito). `window.__diagLatencia` ajusta a latência do salvar.
