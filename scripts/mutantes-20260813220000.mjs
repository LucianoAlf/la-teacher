// Mutantes da régua única de precedência.
//
// M1 e M2 são os que importam: eles reintroduzem a perda de decisão humana --
// o defeito mais caro que este banco pode ter, porque some sem alarme e só
// aparece quando alguém reclama que a chamada "sumiu".

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/20260813220000_uma_regua_so_de_precedencia.sql'
const TESTE = 'supabase/migrations/20260813220000_uma_regua_so_de_precedencia.test.sql'
const TEMP = 'supabase/migrations/_mutante-uma-regua.sql'

const lf = (s) => s.replace(/\r\n/g, '\n')
const fonte = lf(readFileSync(ORIGINAL, 'utf8'))

const MUTANTES = [
  {
    nome: 'M1 — a guarda cai e qualquer fonte pisa na decisao humana',
    pega: 'passo "decisao da secretaria NAO e pisada pelo audio do Fabio"',
    de: 'where not public.fn_presenca_e_forte(aluno_presenca.respondido_por)',
    para: 'where true',
  },
  {
    nome: 'M2 — a guarda inverte e so pisa em quem e forte',
    pega: 'passo "decisao da secretaria NAO e pisada" / "emusys E promovido"',
    de: 'where not public.fn_presenca_e_forte(aluno_presenca.respondido_por)',
    para: 'where public.fn_presenca_e_forte(aluno_presenca.respondido_por)',
  },
  {
    nome: 'M3 — volta a repetir a lista negativa em vez de perguntar a regua',
    pega: 'passos de contrato: "o core consulta fn_presenca_e_forte"',
    de: 'where not public.fn_presenca_e_forte(aluno_presenca.respondido_por)',
    para: "where aluno_presenca.respondido_por is null\n         or aluno_presenca.respondido_por in ('emusys', 'sistema')",
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
