// Mutantes da 081 — os sinais do Radar do aluno.
//
// Cada mutante desfaz uma das quatro decisões que custaram medição contra o
// banco de produção: grão de aula (não linha), denominador honesto, janela
// virada em 01/08 e coorte de professor com login — mais a coerência entre
// absenteismo_pct e a ausência de base. Se um sobreviver, quem está errado é
// o TESTE que não pegou, não o mutante — o passo que falta se adiciona lá.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/081-os-sinais-do-radar.sql'
const TESTE = 'supabase/migrations/081-os-sinais-do-radar.test.sql'
const TEMP = 'supabase/migrations/_mutante-081.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'V1 — o grão volta a ser linha (aula_emusys_id entra no group by)',
    pega: 'passo "aulas_medidas conta AULA, nao linha"',
    de: `   group by 1, 2, 3\n)`,
    para: `   group by 1, 2, 3, v.aula_emusys_id\n)`,
  },
  {
    // O passo comportamental ("nenhum aluno tem mais aula medida do que aula
    // confirmada") não pega este mutante HOJE: medido em 10/08, todo slot de
    // aula da coorte desde 01/08 já tem uma linha confirmada, então tirar o
    // filtro não muda nenhuma contagem nos dados atuais. Quem mata é o passo
    // estrutural, que lê o texto da view (mesma técnica do `fn_hoje_brt`).
    nome: 'V2 — o denominador para de ser honesto (justificada/provavel entram)',
    pega: 'passo "a view cita considera_frequencia_denominador no filtro da aula"',
    de: `   where v.considera_frequencia_denominador\n     and v.data_aula >= date '2026-08-01'`,
    para: `   where true\n     and v.data_aula >= date '2026-08-01'`,
  },
  {
    nome: 'V3 — a janela vaza pra era contaminada (busca desde junho)',
    pega: 'passo "a janela nao busca antes de 01/08"',
    de: `     and v.data_aula >= date '2026-08-01'`,
    para: `     and v.data_aula >= date '2026-06-01'`,
  },
  {
    nome: 'V4 — a coorte cai, a escola inteira entra (join vira left join)',
    pega: 'passo "so entra aluno de professor que ja entrou no app"',
    de: `  join coorte c   on c.professor_id = s.professor_atual_id`,
    para: `  left join coorte c   on c.professor_id = s.professor_atual_id`,
  },
  {
    nome: 'V5 — sem base vira 0% em vez de nulo',
    pega: 'passo "sem aula medida, o absenteismo e NULO (nao zero)"',
    de: `       case when coalesce(j.aulas_medidas, 0) > 0\n            then round(100.0 * j.faltas_janela / j.aulas_medidas, 1)\n       end`,
    para: `       coalesce(round(100.0 * j.faltas_janela / nullif(j.aulas_medidas,0), 1), 0)`,
  },
]

let previstos = 0
let stale = 0

for (const m of MUTANTES) {
  const n = fonte.split(m.de).length - 1
  if (n !== 1) {
    console.log(`STALE  ${m.nome} — ancora aparece ${n} vez(es), esperava 1`)
    console.log(`       procurava: ${JSON.stringify(m.de.slice(0, 90))}`)
    stale++
    continue
  }
  writeFileSync(TEMP, fonte.replace(m.de, m.para))
  let passou = true
  try {
    execFileSync('node', ['scripts/rodar-teste-sql.mjs', TEMP, TESTE], { stdio: 'pipe' })
  } catch {
    passou = false
  }
  if (!passou) {
    previstos++
    console.log(`OK     morto: ${m.nome}  (${m.pega})`)
  } else {
    console.log(`FALHA  SOBREVIVEU: ${m.nome}  (${m.pega})`)
  }
}

try { unlinkSync(TEMP) } catch {}
console.log(`\n${previstos}/${MUTANTES.length} mutantes mortos` + (stale ? `  —  ${stale} ANCORA(S) PODRE(S)` : ''))
process.exitCode = previstos === MUTANTES.length ? 0 : 1
