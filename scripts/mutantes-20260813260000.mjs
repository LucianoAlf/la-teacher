// Mutantes da aula operacional.
//
// Aqui há duas famílias de erro, e as duas precisam morrer: "ficou lento de
// novo" (o índice volta a ser inalcançável) e "ficou rápido e ERRADO" (o
// caminho rápido responde diferente do antigo). A segunda é a perigosa --
// otimização que muda resposta some sem alarme.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/20260813260000_a_aula_operacional_volta_a_usar_o_indice.sql'
const TESTE = 'supabase/migrations/20260813260000_a_aula_operacional_volta_a_usar_o_indice.test.sql'
const TEMP = 'supabase/migrations/_mutante-aula-operacional.sql'

const lf = (s) => s.replace(/\r\n/g, '\n')
const fonte = lf(readFileSync(ORIGINAL, 'utf8'))

const MUTANTES = [
  {
    nome: 'M1 — o caminho rapido nunca e escolhido (volta a lentidao)',
    pega: 'passo do orcamento de buffers',
    de: `  if v_base.unidade_id     is not null
     and v_base.professor_id  is not null
     and v_base.data_hora_fim is not null
     and v_base.curso_nome    is not null then`,
    para: '  if false then',
  },
  {
    nome: 'M2 — o caminho rapido esquece de comparar o curso (rapido e ERRADO)',
    pega: 'passo de equivalencia no lote quente',
    de: '       and candidata.curso_nome      = v_base.curso_nome\n',
    para: '',
  },
  {
    nome: 'M3 — o desempate do rapido inverte (escolhe outra aula)',
    pega: 'passo de equivalencia no lote quente',
    de: `     order by coalesce(quantidade.n_alunos, 0) desc,
              case when candidata.tipo = 'turma' then 0 else 1 end,
              candidata.id desc
     limit 1;
    return v_id;`,
    para: `     order by coalesce(quantidade.n_alunos, 0) asc,
              case when candidata.tipo = 'turma' then 0 else 1 end,
              candidata.id desc
     limit 1;
    return v_id;`,
  },
  {
    // Cada guarda vigia uma coluna diferente, e as colunas tem populacoes
    // MUITO diferentes (9.089 aulas sem professor x 17 sem curso). Por isso
    // sao dois mutantes, e nao um: o de curso so morre se a amostra do teste
    // for estratificada -- e na primeira rodada ela nao era.
    nome: 'M4 — a guarda do professor cai (9.089 aulas caem no caminho errado)',
    pega: 'passo de equivalencia nas linhas orfas',
    de: '     and v_base.professor_id  is not null',
    para: '     and true',
  },
  {
    nome: 'M5 — a guarda do curso cai (so 17 aulas: exige amostra estratificada)',
    pega: 'passo de equivalencia nas linhas orfas',
    de: '     and v_base.curso_nome    is not null then',
    para: '     and true then',
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
