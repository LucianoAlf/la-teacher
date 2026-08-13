// Mutantes do upsert de recibo contra o indice unico PARCIAL.
//
// O M1 aqui reintroduz LITERALMENTE o defeito que derrubou a producao em
// 12/08 00:40 UTC (`delivered_unclosed`, recibo entregue ao professor 10 e a
// funcao de fechar quebrando com 42P10). Se ele sobreviver, o teste nao
// protege o que diz proteger.
//
// Este teste passou semanas sem rodar: nome que nao pareava com a migration e
// formato que o runner recusa. Por isso o mutante vem junto -- verde que nunca
// foi falsificado e decoracao, e este em particular ja custou um incidente.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/20260812004430_fix_registro_recibo_partial_conflict.sql'
const TESTE = 'supabase/migrations/20260812004430_fix_registro_recibo_partial_conflict.test.sql'
const TEMP = 'supabase/migrations/_mutante-recibo-partial-conflict.sql'

const lf = (s) => s.replace(/\r\n/g, '\n')
const fonte = lf(readFileSync(ORIGINAL, 'utf8'))

const MUTANTES = [
  {
    nome: 'M1 — o predicado do indice parcial some do ON CONFLICT (o incidente de 12/08)',
    pega: 'a insercao nem chega a planejar: 42P10',
    de: 'on conflict (wa_message_id) where wa_message_id is not null do update',
    para: 'on conflict (wa_message_id) do update',
  },
  {
    nome: 'M2 — o upsert vira insert cego e duplica a mensagem',
    pega: 'passo "wa_message_id nao duplica"',
    de: `  on conflict (wa_message_id) where wa_message_id is not null do update
     set kind = excluded.kind,
         content = excluded.content`,
    para: `  on conflict (wa_message_id) where wa_message_id is not null do nothing`,
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
