// Mutantes da 052 — a skill do registro por áudio.
//
// Mutar prosa é diferente de mutar código: o mutante não quebra execução, ele
// tira uma promessa do texto. T1 é o que importa — sem a instrução de devolver
// nulo, o modelo preenche os quatro campos sempre, e o campo inventado sai bem
// escrito. Nada dá erro. O professor confirma sem ler com atenção, e a família
// recebe uma frase sobre uma aula que ninguém contou assim.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/052-skill-do-registro-por-audio.sql'
const TESTE = 'supabase/migrations/052-skill-do-registro-por-audio.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-052.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'T1 — some a regra de devolver nulo no que não foi dito',
    pega: 'passo "a skill manda devolver NULO no que nao foi dito"',
    de: `Se o professor não falou sobre um campo, devolva null nesse campo. Não
deduza, não infira do resto do áudio, não escreva o que "provavelmente"
aconteceu.`,
    para: 'Preencha os quatro campos.',
  },
  {
    nome: 'T2 — a fronteira do dinheiro deixa de nomear onde ele pode',
    pega: 'passo "a skill proibe dinheiro fora da leitura de conversao"',
    de: `Preço, mensalidade, matrícula, desconto, condição de pagamento e qualquer
leitura sobre "vai fechar ou não" só podem aparecer em leitura_de_conversao.`,
    para: 'Fale de dinheiro só quando o professor falar.',
  },
  {
    nome: 'T3 — a skill deixa de proibir invenção de nome e repertório',
    pega: 'passo "a skill diz que nao e pra inventar"',
    de: `Não invente nome, idade,
instrumento nem repertório que não estejam no áudio.`,
    para: 'Complete o que faltar.',
  },
  {
    // Nome de campo trocado = JSON que não casa no parse do worker. Não é
    // detalhe de redação: é o contrato com o código.
    nome: 'T4 — um dos quatro campos muda de nome na skill',
    pega: 'passo "a skill nomeia os quatro campos na lista"',
    de: '- proximos_passos — por onde começar se o aluno continuar.',
    para: '- proximos_passos_do_aluno — por onde começar se o aluno continuar.',
  },
  {
    // Duas ativas = o worker escolhe por sorte de ordenação, e a skill velha
    // pode voltar a valer sem ninguém mudar nada.
    nome: 'T5 — a versão nova não desliga a anterior',
    pega: 'passo "existe exatamente uma skill ativa com esse nome"',
    de: `update public.fabio_skills set ativa = false
 where nome = 'registro_experimental_audio' and ativa;`,
    para: `insert into public.fabio_skills (nome, versao, conteudo, ativa, criado_por)
values ('registro_experimental_audio', 99, 'sobra velha', true, 'mutante');`,
  },
  {
    nome: 'T6 — a skill da devolutiva é desligada junto',
    pega: 'passo "a skill da devolutiva continua ativa"',
    de: " where nome = 'registro_experimental_audio' and ativa;",
    para: ' where ativa;',
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
