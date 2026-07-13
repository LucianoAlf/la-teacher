# Deploy do LA Teacher na Vercel

O app é um SPA Vite (React + React Router). O `vercel.json` na raiz já configura
build (`npm run build` → `dist`) e o rewrite de SPA (toda rota serve `index.html`,
senão `/app/chamada/:id` daria 404 em acesso direto).

## Ambiente A — PRODUÇÃO (somente leitura, para o passeio de teste)

O professor navega logado (conta real) e confere **Carteira, Agenda, Meu Ponto,
Disponibilidade**. A **Chamada aparece mas NÃO grava** — a flag `VITE_SOMENTE_LEITURA`
desliga a porta de escrita (verificado: `registrarPresencas` devolve `somente_leitura`
sem tocar a rede; o envio de áudio também fica travado com aviso).

**Passo a passo (dashboard Vercel — você faz, ~3 min):**
1. vercel.com → **Add New… → Project** → importe `LucianoAlf/la-teacher`.
2. Framework: **Vite** (autodetecta). Build/output já vêm do `vercel.json`.
3. **Environment Variables** (as três):
   | Nome | Valor |
   |------|-------|
   | `VITE_SUPABASE_URL` | `https://ouqwbbermlzqqvtqwlul.supabase.co` |
   | `VITE_SUPABASE_ANON_KEY` | *(anon key da LA Performance Report — te passo no chat)* |
   | `VITE_SOMENTE_LEITURA` | `true` |
4. **Deploy**. A Vercel devolve a URL pública (PWA).

> A anon key é pública por design (o que protege é o RLS do banco). Mesmo assim,
> não fica versionada aqui — pego pra você no chat / painel Supabase (Settings → API).

**Para o teste de fogo real de segunda (13/07 11h):** troque `VITE_SOMENTE_LEITURA`
para `false` (ou remova a var) nas Environment Variables e **Redeploy**. Aí a chamada
grava de verdade.

## Ambiente B — STAGING (testar a chamada gravando, sem risco)

Preview separada da Vercel apontando para a **branch da LA Performance Report**
(banco isolado). Mesmas duas vars de Supabase, mas com **URL + anon key da branch**,
e `VITE_SOMENTE_LEITURA=false` (aqui pode gravar — é descartável). Detalhe do setup
da branch e do seed no fluxo com o Claude Web (ver DOSSIE / conversa).

## Service worker & cache (por que o deploy aparece na hora)

O app é PWA instalável (`vite-plugin-pwa`). A estratégia de cache é o **app shell
model** do Workbox — e ela decide se "corrijo e não muda" acontece ou não:

- **Bundles com hash (js/css/fontes) → precache cache-first.** Nome com hash =
  imutável; servir do cache é perfeito e carrega na hora.
- **HTML (documento) → NETWORK-FIRST.** O `index.html` é a "portaria" que aponta
  quais bundles carregar, e é a única coisa mutável a cada deploy. Por isso ele
  **não entra no precache** (repare no `globPatterns` sem `html`) e é servido por
  uma rota `NetworkFirst` (`request.mode === 'navigate'`), com
  `networkTimeoutSeconds: 3`. Resultado: reabrir/recarregar já puxa o HTML novo →
  os bundles novos, **sem depender de o professor tocar em nada**. Sem rede, cai
  no cache e abre offline (sala de aula).

> **Pegadinha aprendida no LA Organizer (não redescubra do zero):** o que decide
> a frescura do app é a requisição de **navegação** — `request.mode === 'navigate'`,
> ou seja, quando o browser busca o `index.html`. Testar cache com um `fetch()` de
> um `.js` solto **não prova nada** sobre o comportamento offline/atualização: aquele
> JS tem hash e vem do precache de qualquer jeito. Para validar de verdade: recarregue
> a página (navegação) online e confirme que o HTML veio da rede; depois offline,
> confirme que caiu no cache. `networkTimeoutSeconds: 3` é igual nos dois apps de
> propósito — mesma config facilita quem mexe nos dois.

Além do network-first, o `registerType: 'prompt'` mostra o banner "Nova versão
disponível" (rede de segurança pra trocar o precache offline). E o **selo de versão**
no rodapé do Perfil (`__APP_VERSION__` = SHA do commit, injetado no build via
`vite.config.ts`) deixa bater o olho e saber em que build o professor está.
