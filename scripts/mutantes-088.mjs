// Mutantes da 088 — o 5º sinal: faltas consecutivas.
//
// Cinco mutantes da tabela do brief. O 5º sinal é PONDERADO (entra na mesma
// redistribuição dos outros 4, tem peso próprio), não um atropelo — os
// mutantes provam isso desfazendo a guarda (V1), a fronteira do crítico
// (V2), a contagem de sinais_totais (V3), o peso configurável (V4) e a
// própria contagem de faltas seguidas na view (V5).
//
// Se um mutante sobreviver, quem está errado é o TESTE que não pegou, nunca
// o mutante — o passo que falta se adiciona lá, não se afrouxa aqui.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/088-a-falta-seguida-e-o-quinto-sinal.sql'
const TESTE = 'supabase/migrations/088-a-falta-seguida-e-o-quinto-sinal.test.sql'
const TEMP = 'supabase/migrations/_mutante-088.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'V1 — a guarda cai (sem aula medida conta como saudavel fantasma)',
    pega: 'passo "sem aula medida, faltas_consecutivas fica sem_dado"',
    de: `      ('faltas_consecutivas',\n       case when coalesce((p_sinais->>'aulas_medidas')::int, 0) > 0\n            then case`,
    para: `      ('faltas_consecutivas',\n       case when true\n            then case`,
  },
  {
    nome: 'V2 — a fronteira do critico some (3 faltas vira 50, nao mais 0)',
    pega: 'passo "3 faltas seguidas pontua 0 (critico)"',
    de: `                        >= coalesce((p_config->>'faltas_consecutivas_critico')::int, 3) then 0`,
    para: `                        >= coalesce((p_config->>'faltas_consecutivas_critico')::int, 3) then 50`,
  },
  {
    nome: 'V3 — sinais_totais nao sobe (fica em 4)',
    pega: 'passo "sinais_totais e 5"',
    de: `    'sinais_totais', 5,`,
    para: `    'sinais_totais', 4,`,
  },
  {
    nome: 'V4 — o peso configuravel vira hardcoded (deixa de ser sinal ponderado de verdade)',
    pega: 'passo "nota com 3 faltas seguidas e menor que com 0" (peso zerado nao move a nota)',
    de: `       coalesce((p_config->>'peso_faltas_consecutivas')::numeric, 0),\n       case when coalesce((p_sinais->>'aulas_medidas')::int, 0) > 0\n            then format('%s falta(s) seguida(s)'`,
    para: `       0,\n       case when coalesce((p_sinais->>'aulas_medidas')::int, 0) > 0\n            then format('%s falta(s) seguida(s)'`,
  },
  {
    nome: 'V5 — a view para de contar falta seguida (conta presenca)',
    pega: 'passo "a view tem faltas_consecutivas e bate com o calculo direto"',
    de: `consecutivas as (\n  select o.aluno_id, count(*) as faltas_consecutivas\n    from ordenada o\n   where not o.veio`,
    para: `consecutivas as (\n  select o.aluno_id, count(*) as faltas_consecutivas\n    from ordenada o\n   where o.veio`,
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
