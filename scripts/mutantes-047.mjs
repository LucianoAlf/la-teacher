// Mutantes da 047 — a experimental na agenda.
//
// Esta migration mexe no payload da tela mais usada do app. Metade dos
// mutantes ataca o campo novo; a outra metade prova que o CONTROLE (a aula
// comum) continua sendo medido — senao "nao quebrou nada" seria fe, nao teste.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/047-experimental-na-agenda.sql'
const TESTE = 'supabase/migrations/047-experimental-na-agenda.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-047.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    // Toda aula viraria roxa na agenda, e o professor pararia de olhar o selo.
    nome: 'U1 — o criterio afrouxa e a aula comum vira experimental',
    pega: 'passo "a aula comum nao vira experimental"',
    de: "        'experimental', (ae.categoria = 'experimental'),",
    para: "        'experimental', (ae.categoria is not null),",
  },
  {
    nome: 'U2 — a experimental para de se declarar',
    pega: 'passo "a experimental se declara experimental"',
    de: "        'experimental', (ae.categoria = 'experimental'),",
    para: "        'experimental', false,",
  },
  {
    // O vinculo tem historia: remarcacao deixa o antigo cancelado. Apontar pro
    // cancelado abre a ficha da aula que nao houve.
    nome: 'U3 — o vinculo cancelado volta a ser apontado',
    pega: 'passo "vinculo cancelado nao e apontado"',
    de: '           where v.aula_local_id = ae.id and v.cancelado_em is null\n           order by v.id desc limit 1),',
    para: '           where v.aula_local_id = ae.id\n           order by v.id desc limit 1),',
  },
  {
    // Vinculo de outra aula: a ficha abriria com o aluno errado, e o registro
    // iria pro prontuario de outra pessoa.
    nome: 'U4 — o vinculo deixa de ser o da aula (aponta qualquer um)',
    pega: 'passo "o vinculo apontado e o certo"',
    de: '           where v.aula_local_id = ae.id and v.cancelado_em is null\n           order by v.id desc limit 1),',
    para: '           where v.cancelado_em is null\n           order by v.id asc limit 1),',
  },
  {
    nome: 'U5 — o nome de quem vem some do card',
    pega: 'passo "e traz o nome de quem vem"',
    de: "        'experimental_nome', (",
    para: "        'experimental_nome_indisponivel', (",
  },
  {
    // O controle: prova que o teste mediria uma quebra na aula comum.
    nome: 'U6 — o roster da aula comum quebra (o controle e medido mesmo)',
    pega: 'passo "a aula comum mantem o roster"',
    de: "        'n_alunos', coalesce(roster.n_alunos, 0),",
    para: "        'n_alunos', 0,",
  },
]

let previstos = 0
let stale = 0

for (const m of MUTANTES) {
  if (!fonte.includes(m.de)) {
    console.log(`STALE  ${m.nome} — ancora nao existe mais na migration`)
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
