// Mutantes da 085 — a nota do Radar do aluno.
//
// Os cinco vêm do brief e cobrem as três amarras que a migration promete nos
// comentários: a nota SEMPRE ABRE (V5), sinal sem dado SAI DA CONTA e o peso
// SE REDISTRIBUI (V2 e V3), e o PISO DE COBERTURA cala a nota sem base (V1).
// V4 cobre a régua vindo da config, não do código — mesma família de defeito
// que a 082 existe pra evitar (régua hardcoded não muda com a gestão).
//
// Se um mutante sobreviver, quem está errado é o TESTE que não pegou, nunca
// o mutante — o passo que falta se adiciona lá, não se afrouxa aqui.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/085-a-nota-do-radar.sql'
const TESTE = 'supabase/migrations/085-a-nota-do-radar.test.sql'
const TEMP = 'supabase/migrations/_mutante-085.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'V1 — o piso de cobertura cai (nota nunca se cala)',
    pega: 'passo "e a nota vem NULA (nao um numero bonito)"',
    de: `  if v_apurados < v_minimo then\n    v_nota := null;\n  end if;`,
    para: `  if false then\n    v_nota := null;\n  end if;`,
  },
  {
    nome: 'V2 — a redistribuicao desliga (peso_vivo vira sempre a soma dos 4)',
    pega: 'passo "sinal ausente NAO puxa a nota pra baixo" (nota vira 55, nao 100)',
    de: `      v_apurados  := v_apurados + 1;\n      v_peso_vivo := v_peso_vivo + r.peso;`,
    para: `      v_apurados  := v_apurados + 1;\n      v_peso_vivo := coalesce((p_config->>'peso_absenteismo')::numeric,0) + coalesce((p_config->>'peso_feedback')::numeric,0) + coalesce((p_config->>'peso_pratica')::numeric,0) + coalesce((p_config->>'peso_faltas_mes')::numeric,0);`,
  },
  {
    nome: 'V3 — sinal ausente passa a entrar na conta como se tivesse dado',
    pega: 'passo "apurados = 2 de 4" e "o peso efetivo do absenteismo subiu de 40"',
    de: `    if r.score is null then`,
    para: `    if false then`,
  },
  {
    nome: 'V4 — a faixa de critico para de vir da config (fica hardcoded em 40)',
    pega: 'passo novo "descendo a faixa_critico, uma nota antes atencao vira critico"',
    de: `    when v_nota < coalesce((p_config->>'faixa_critico')::numeric, 40)   then 'critico'`,
    para: `    when v_nota < 40 then 'critico'`,
  },
  {
    nome: 'V5 — a decomposicao para de dizer quanto cada sinal CONTRIBUIU',
    pega: 'passo "cada linha diz quanto CONTRIBUIU (nao so o peso)"',
    de: `               'contribuiu',   round((d->>'score')::numeric * (d->>'peso')::numeric\n                                     / v_peso_vivo, 1),`,
    para: `               'contribuiu',   null,`,
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
