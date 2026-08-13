// Mutantes da 080 — um número só no semáforo.
//
// V1 é literalmente o estado de antes: o resumo volta a contar `distinct
// aluno_id` e a tela mostra 1155 no topo com 1161 na lista. Repare que NADA
// quebra — a tela carrega, os filtros funcionam, os nomes estão certos. É por
// isso que este mutante existe: divergência de contagem não derruba nada, só
// destrói a confiança de quem lê.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/080-um-numero-so-no-semaforo.sql'
const TESTE = 'supabase/migrations/080-um-numero-so-no-semaforo.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-080.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'V1 — o resumo volta a contar aluno distinto (1155 no topo, 1161 na lista)',
    pega: 'passos "o numero e o de PARES" e "resumo e lista contam a mesma coisa"',
    de: `          'alunos',         count(*),`,
    para: `          'alunos',         count(distinct aluno_id),`,
  },
  {
    nome: 'V2 — o coracao do resumo desalinha da lista',
    pega: 'passo "resumo e lista contam a mesma coisa"',
    de: `          'sem_resposta',   count(*) filter (where coracao = 'sem_resposta'),`,
    para: `          'sem_resposta',   count(distinct aluno_id) filter (where coracao = 'sem_resposta'),`,
  },
  {
    nome: 'V3 — o chip da unidade promete menos do que o clique entrega',
    pega: 'passo "o chip da unidade bate com a lista que ela abre"',
    de: `                                      'alunos', count(*)) as j
              from fac_uni where unidade_id is not null`,
    para: `                                      'alunos', count(distinct aluno_id)) as j
              from fac_uni where unidade_id is not null`,
  },
  {
    // O oposto do defeito: contar professor em par infla a faixa do topo com
    // gente que não existe.
    nome: 'V4 — professor passa a ser contado em par',
    pega: 'passo "professores continuam contados como pessoa"',
    de: `          'professores',    count(distinct professor_id),`,
    para: `          'professores',    count(*),`,
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
