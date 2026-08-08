// Mutantes da 064 — a pendência de presença para de levar 27 segundos.
//
// Otimização é onde mutante é mais necessário e menos usado: um teste que só
// olha "o índice existe" fica verde com o índice errado, e o verde vira prova
// de que ninguém mediu. Aqui os mutantes criam índices PLAUSÍVEIS — nas
// colunas quase certas, na ordem quase certa — porque é isso que sai errado
// de verdade.
//
// V5 é uma pergunta honesta, não um defeito: o `analyze` no fim da migration
// serve pra alguma coisa? Se ele sobreviver, a linha é cerimônia e sai.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/064-a-pendencia-de-presenca-para-de-levar-27s.sql'
const TESTE = 'supabase/migrations/064-a-pendencia-de-presenca-para-de-levar-27s.test.sql'
const TEMP = 'supabase/migrations/_mutante-064.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const CRIACAO = `create index if not exists idx_aulas_emusys_turma_no_horario
    on public.aulas_emusys (unidade_id, professor_id, data_hora_inicio)
 where tipo = 'turma' and not coalesce(cancelada, false);`

const MUTANTES = [
  {
    nome: 'V1 — o indice nao e criado (os 27 segundos de volta)',
    pega: 'passos do plano e do teto de buffers',
    de: CRIACAO,
    para: 'select 1;',
  },
  {
    // Ordem trocada: parece o mesmo índice numa leitura rápida do diff.
    nome: 'V2 — as colunas na ordem errada (horario primeiro)',
    pega: 'passo "o indice existe com as tres colunas na ordem certa"',
    de: CRIACAO,
    para: `create index if not exists idx_aulas_emusys_turma_no_horario
    on public.aulas_emusys (data_hora_inicio, professor_id, unidade_id)
 where tipo = 'turma' and not coalesce(cancelada, false);`,
  },
  {
    // Esquece o professor — e a pergunta é justamente sobre o professor.
    nome: 'V3 — o indice esquece o professor_id',
    pega: 'passo "o indice existe com as tres colunas na ordem certa"',
    de: CRIACAO,
    para: `create index if not exists idx_aulas_emusys_turma_no_horario
    on public.aulas_emusys (unidade_id, data_hora_inicio)
 where tipo = 'turma' and not coalesce(cancelada, false);`,
  },
  {
    // Predicado invertido: o índice existe, tem as colunas certas, e o
    // planejador não pode usá-lo porque ele cobre exatamente as linhas erradas.
    nome: 'V4 — o predicado parcial invertido (indexa o que a view nao pergunta)',
    pega: 'passo "o planejador escolheu o indice novo"',
    de: CRIACAO,
    para: `create index if not exists idx_aulas_emusys_turma_no_horario
    on public.aulas_emusys (unidade_id, professor_id, data_hora_inicio)
 where tipo <> 'turma' and not coalesce(cancelada, false);`,
  },
  {
    // O índice existe mas cobre a tabela inteira: 53.112 linhas em vez de
    // 21.882. Funciona — e é o mutante que prova que o "parcial" do arquivo
    // não é enfeite, porque o passo do predicado o mata.
    nome: 'V5 — o indice deixa de ser parcial (indexa a tabela inteira)',
    pega: 'passo "e e parcial (so aula de turma nao cancelada)"',
    de: CRIACAO,
    para: `create index if not exists idx_aulas_emusys_turma_no_horario
    on public.aulas_emusys (unidade_id, professor_id, data_hora_inicio);`,
  },
]

// V5 original era "tirar o `analyze public.aulas_emusys;` do fim". Ele
// SOBREVIVEU: o planejador escolhe o índice novo sem estatística refrescada.
// Em vez de manter um mutante que não mata nada, tirei a linha da migration —
// o achado foi que ela não fazia nada.

let previstos = 0
let stale = 0

for (const m of MUTANTES) {
  const n = fonte.split(m.de).length - 1
  if (n !== 1) {
    console.log(`STALE  ${m.nome} — ancora aparece ${n} vez(es), esperava 1`)
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
