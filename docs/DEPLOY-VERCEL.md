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
