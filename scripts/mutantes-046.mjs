// Mutantes da 046 — a dica de conducao pela lista branca.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/046-dica-de-conducao-pela-lista-branca.sql'
const TESTE = 'supabase/migrations/046-dica-de-conducao-pela-lista-branca.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-046.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    // O buraco do tamanho de um objeto: lista branca que so lista NOMES nao
    // protege contra o modelo devolver estrutura no lugar de string.
    nome: 'T1 — a dica passa como objeto (chaves inventadas atravessam)',
    pega: 'passo "objeto do LLM vira TEXTO, nao objeto"',
    de: "      'como_conduzir', p_contexto ->> 'como_conduzir',",
    para: "      'como_conduzir', p_contexto -> 'como_conduzir',",
  },
  {
    // Volta o atalho da 045: a dica lida do cru, por fora da lista branca.
    nome: 'T2 — a RPC volta a ler a dica do contexto_ia cru',
    pega: 'passo "a dica chega na tela do professor"',
    de: "    'como_conduzir', (public.fn_experimental_contexto_seguro(le.contexto_ia) ->> 'como_conduzir'),",
    para: "    'como_conduzir', (le.contexto_ia -> 'como_conduzir_indisponivel'),",
  },
  {
    nome: 'T3 — a dica volta a viver em dois lugares no payload',
    pega: 'passo "e mora num lugar so no payload"',
    de: "                   #- '{como_conduzir}'),",
    para: '                   ),',
  },
  {
    // A 046 mexeu na lista branca. Provar que nao comeu o que ja passava.
    nome: 'T4 — a lista branca perde os ganchos de conexao',
    pega: 'passo "os ganchos continuam passando"',
    de: "      'ganchos_de_conexao', p_contexto -> 'ganchos_de_conexao',",
    para: '',
  },
  {
    nome: 'T5 — o porque do sinal volta a atravessar a lista branca',
    pega: 'passo "o porque do sinal continua barrado"',
    de: "        'o_que_a_familia_espera', p_contexto -> 'para_a_devolutiva' ->> 'o_que_a_familia_espera',",
    para:
      "        'o_que_a_familia_espera', p_contexto -> 'para_a_devolutiva' ->> 'o_que_a_familia_espera',\n" +
      "        'porque', p_contexto -> 'para_a_devolutiva' ->> 'porque',",
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
