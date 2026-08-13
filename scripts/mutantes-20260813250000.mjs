// Mutantes do conserto do aviso ao comercial.
//
// O defeito original não aparece em nenhuma tela: quem morre é o worker, num
// timer de 3 minutos, e o comercial só não fica sabendo da experimental. Por
// isso os mutantes aqui são todos da forma "consertou pela metade" -- que é
// exatamente como o defeito nasceu (corrigido numa função, não nas outras).

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/20260813250000_o_aviso_ao_comercial_volta_a_caber_no_indice.sql'
const TESTE = 'supabase/migrations/20260813250000_o_aviso_ao_comercial_volta_a_caber_no_indice.test.sql'
const TEMP = 'supabase/migrations/_mutante-aviso-comercial.sql'

const lf = (s) => s.replace(/\r\n/g, '\n')
const fonte = lf(readFileSync(ORIGINAL, 'utf8'))

const MUTANTES = [
  {
    nome: 'M1 — a troca nao acrescenta a condicao que faltava',
    pega: 'passos das duas funcoes + "nao sobrou nenhum predicado incompleto"',
    de: `  v_para  constant text := 'where referencia_tipo is not null and referencia_id is not null and tipo <> ''registro_recibo''';`,
    para: `  v_para  constant text := 'where referencia_tipo is not null and referencia_id is not null';`,
  },
  {
    nome: 'M2 — o conserto so alcanca a primeira funcao (o defeito original)',
    pega: 'passo "fabio_claim_aviso_falta_experimental carrega..."',
    de: `  foreach v_nome in array array['fabio_claim_aviso_comercial',
                                'fabio_claim_aviso_falta_experimental'] loop`,
    para: `  foreach v_nome in array array['fabio_claim_aviso_comercial'] loop`,
  },
  {
    nome: 'M3 — a guarda de idempotencia passa a pular TODA funcao',
    pega: 'todos os passos de conteudo',
    de: `    if position('tipo <> ''registro_recibo''' in v_def) > 0 then`,
    para: '    if true then',
  },
  {
    nome: 'M4 — recria a funcao sem trocar nada (execute do texto original)',
    pega: 'passos das duas funcoes + "nao sobrou nenhum predicado incompleto"',
    de: '    execute replace(v_def, v_de, v_para);',
    para: '    execute v_def;',
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
