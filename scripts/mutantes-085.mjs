// Mutantes da 085 — a nota do Radar do aluno.
//
// V1-V5 vêm da primeira rodada (brief original). V6 e V7 vêm da rodada de
// correção: a revisão achou C1 (greatest(0,NULL)=0 faz faltas_mes ausente
// virar o PIOR score, não SEM DADO), I1 (nota e soma das contribuições eram
// duas contas independentes que cruzavam o ,5 em direções diferentes) e I2
// (decomposição vazava contribuição de uma nota calada). I1 mudou onde v_nota
// é calculado — V1 precisou de âncora nova por causa disso (o bloco do `if`
// ganhou mais linhas dentro, mesmo sem a condição em si mudar).
//
// Se um mutante sobreviver, quem está errado é o TESTE que não pegou, nunca
// o mutante — o passo que falta se adiciona lá, não se afrouxa aqui.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/085-a-nota-do-radar.sql'
const TESTE = 'supabase/migrations/085-a-nota-do-radar.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-085.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'V1 — o piso de cobertura cai (nota nunca se cala)',
    pega: 'passo "e a nota vem NULA (nao um numero bonito)"',
    de: `  if v_apurados < v_minimo then`,
    para: `  if false then`,
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
    pega: 'passo "descendo a faixa_critico, uma nota antes atencao vira critico"',
    de: `    when v_nota < coalesce((p_config->>'faixa_critico')::numeric, 40)   then 'critico'`,
    para: `    when v_nota < 40 then 'critico'`,
  },
  {
    nome: 'V5 — a decomposicao para de dizer quanto cada sinal CONTRIBUIU',
    pega: 'passo "cada linha diz quanto CONTRIBUIU (nao so o peso)"',
    de: `               'contribuiu',   round((d->>'score')::numeric * (d->>'peso')::numeric\n                                     / v_peso_vivo, 1),`,
    para: `               'contribuiu',   null,`,
  },
  {
    // C1, achado da revisão: greatest() do Postgres ignora NULL, então a
    // guarda velha (só aulas_mes>0) deixava faltas_mes ausente entrar como
    // score ZERO. Reintroduz exatamente essa guarda velha no lado do score.
    nome: 'V6 — C1: a guarda de faltas_mes volta a ignorar se o dado existe (so aulas_mes>0)',
    pega: 'passo "aulas_mes sem faltas_mes nao conta como sinal apurado" e os dois seguintes',
    de: `       case when (p_sinais->>'faltas_mes') is not null\n                 and coalesce((p_sinais->>'aulas_mes')::int, 0) > 0\n            then greatest(0, 100 - 100.0 * (p_sinais->>'faltas_mes')::numeric\n                                        / (p_sinais->>'aulas_mes')::numeric) end,`,
    para: `       case when coalesce((p_sinais->>'aulas_mes')::int, 0) > 0\n            then greatest(0, 100 - 100.0 * (p_sinais->>'faltas_mes')::numeric\n                                        / (p_sinais->>'aulas_mes')::numeric) end,`,
  },
  {
    // I2, achado da revisão: a nota se cala mas a decomposição não podia
    // continuar vazando contribuiu/peso_efetivo/de calculados. Remove só a
    // limpeza da decomposição, mantendo v_nota:=null intacto — prova que o
    // passo "nota vem nula" sozinho NÃO bastava pra pegar esse vazamento.
    nome: 'V7 — I2: a decomposicao para de ser limpa quando a nota se cala (mas a nota continua nula)',
    pega: 'passo "com poucos sinais, NENHUMA linha da decomposicao mostra contribuicao"',
    de: `    v_nota := null;\n    v_dec := (\n      select jsonb_agg(\n               d || jsonb_build_object('contribuiu', null, 'peso_efetivo', null, 'de', null)\n               order by ord)\n        from jsonb_array_elements(v_dec) with ordinality as e(d, ord));\n  end if;`,
    para: `    v_nota := null;\n  end if;`,
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
