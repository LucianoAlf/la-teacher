// Mutantes da identidade da pessoa.
//
// Cada um reintroduz um erro que a auditoria de 13/08/2026 MEDIU na producao.
// Nao sao hipoteses de laboratorio:
//
//   M1 -> volta a contar linha (o 23 em vez do 20)
//   M2 -> volta a contar cadastro (o 21 em vez do 20)
//   M3 -> usa o id do Emusys sem a unidade, fundindo Pietro com Julia
//   M4 -> tira a saida conservadora e junta os 16 sem identidade numa pessoa
//   M5 -> abre a porta de worker para o cliente

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/20260813190000_a_pessoa_ganha_nome.sql'
const TESTE = 'supabase/migrations/20260813190000_a_pessoa_ganha_nome.test.sql'
const TEMP = 'supabase/migrations/_mutante-a-pessoa-ganha-nome.sql'

const lf = (s) => s.replace(/\r\n/g, '\n')
const fonte = lf(readFileSync(ORIGINAL, 'utf8'))

const MUTANTES = [
  {
    nome: 'M1 — a carteira volta a contar LINHA (o 23)',
    pega: 'passo "carteira do professor 25 conta 20 pessoas"',
    de: "    'pessoas',       count(distinct p.pessoa_chave),",
    para: "    'pessoas',       count(*),",
  },
  {
    nome: 'M2 — a carteira volta a contar CADASTRO (o 21)',
    pega: 'passo "carteira do professor 25 conta 20 pessoas"',
    de: "    'pessoas',       count(distinct p.pessoa_chave),",
    para: "    'pessoas',       count(distinct c.aluno_id),",
  },
  {
    nome: 'M3 — a chave perde a unidade e funde Pietro com Julia',
    pega: 'passo "o mesmo emusys_student_id em unidades diferentes NAO vira a mesma pessoa"',
    de: "      then 'emusys:' || a.unidade_id::text || ':' || btrim(a.emusys_student_id)",
    para: "      then 'emusys:' || btrim(a.emusys_student_id)",
  },
  {
    nome: 'M4 — a saida conservadora some e os sem-identidade viram um so',
    pega: 'passo "aluno sem identidade no Emusys continua sendo pessoa propria"',
    de: "    else 'cadastro:' || a.id::text",
    para: "    else 'cadastro:' || a.unidade_id::text",
  },
  {
    nome: 'M5 — a porta de worker se abre para o cliente autenticado',
    pega: 'passo "contagem da carteira nao e alcancavel pelo cliente"',
    de: `revoke all on function public.app_professor_carteira_contagem(integer)
  from public, anon, authenticated;`,
    para: `revoke all on function public.app_professor_carteira_contagem(integer)
  from public, anon;`,
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
