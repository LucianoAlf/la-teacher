// Mutantes das guardas resgatadas da 090, 091 e 095.
//
// Cada um abre uma porta que precisa ficar fechada, ou fecha uma que precisa
// ficar aberta. Guarda que nao morde e pior que guarda ausente: da a sensacao
// de estar coberto.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/20260813180000_guardas_resgatadas_do_whatsapp.sql'
const TESTE = 'supabase/migrations/20260813180000_guardas_resgatadas_do_whatsapp.test.sql'
const TEMP = 'supabase/migrations/_mutante-guardas-whatsapp.sql'

const lf = (s) => s.replace(/\r\n/g, '\n')
const fonte = lf(readFileSync(ORIGINAL, 'utf8'))

const MUTANTES = [
  {
    nome: 'M1 — authenticated alcanca a porta que inicia acao no WhatsApp',
    pega: 'porta de worker: fabio_iniciar_acao',
    de: `revoke all on function public.fabio_iniciar_acao(integer, text, text, text, jsonb)
  from public, anon, authenticated;`,
    para: `revoke all on function public.fabio_iniciar_acao(integer, text, text, text, jsonb)
  from public, anon;
grant execute on function public.fabio_iniciar_acao(integer, text, text, text, jsonb) to authenticated;`,
  },
  {
    nome: 'M2 — anon alcanca a confirmacao de registro pelo WhatsApp',
    pega: 'porta de worker: fabio_confirmar_registro',
    de: `revoke all on function public.fabio_confirmar_registro(integer, uuid, text)
  from public, anon, authenticated;`,
    para: `revoke all on function public.fabio_confirmar_registro(integer, uuid, text)
  from public, authenticated;
grant execute on function public.fabio_confirmar_registro(integer, uuid, text) to anon;`,
  },
  {
    nome: 'M3 — a interna de confirmacao vira alcancavel pelo worker',
    pega: 'passo "fn_confirmar_registro_core e interna"',
    de: `revoke all on function public.fn_confirmar_registro_core(integer, uuid, uuid, text)
  from public, anon, authenticated, service_role;`,
    para: `revoke all on function public.fn_confirmar_registro_core(integer, uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.fn_confirmar_registro_core(integer, uuid, uuid, text) to service_role;`,
  },
  {
    nome: 'M4 — o cliente autenticado passa a ler a fila de acoes',
    pega: 'tabela do fluxo de acao: fabio_acoes_pendentes',
    de: 'revoke all on table public.fabio_acoes_pendentes from public, anon, authenticated;',
    para: `revoke all on table public.fabio_acoes_pendentes from public, anon;
grant select on table public.fabio_acoes_pendentes to authenticated;`,
  },
  {
    nome: 'M5 — o worker PERDE a porta do recibo (guarda apertada demais)',
    pega: 'porta de worker: fabio_concluir_registro_recibo',
    de: `revoke all on function public.fabio_concluir_registro_recibo(uuid, uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.fabio_concluir_registro_recibo(uuid, uuid, text, text)
  to service_role;`,
    para: `revoke all on function public.fabio_concluir_registro_recibo(uuid, uuid, text, text)
  from public, anon, authenticated, service_role;`,
  },
]

exigirBaselineVerde(ORIGINAL, TESTE)

let mortos = 0
let stale = 0

for (const m of MUTANTES) {
  const n = fonte.split(m.de).length - 1
  if (n !== 1) {
    console.log(`STALE  ${m.nome} — ancora aparece ${n} vez(es), esperava 1`)
    stale++
    continue
  }
  writeFileSync(TEMP, fonte.replace(m.de, m.para))
  let morreu = false
  try {
    execFileSync('node', ['scripts/rodar-teste-sql.mjs', TEMP, TESTE], { stdio: 'pipe' })
  } catch {
    morreu = true
  }
  if (morreu) {
    mortos++
    console.log(`OK     morto: ${m.nome}  (${m.pega})`)
  } else {
    console.log(`FALHA  SOBREVIVEU: ${m.nome}  (${m.pega})`)
  }
}

try { unlinkSync(TEMP) } catch {}

console.log(`\n${mortos}/${MUTANTES.length} mutantes mortos${stale > 0 ? ` (${stale} ancora(s) stale)` : ''}`)
process.exitCode = mortos === MUTANTES.length ? 0 : 1
