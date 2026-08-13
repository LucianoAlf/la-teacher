// Mutantes da 044 — a fronteira do bloco interno na mensagem ao comercial.
//
// R1 e o que importa: a leitura de conversao subindo pro meio do bloco
// pedagogico. Nao quebra nada, nao levanta erro, e a mensagem continua
// "certa" — ate o dia em que um consultor encaminha pra mae.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/044-mensagem-comercial-hierarquia.sql'
const TESTE = 'supabase/migrations/044-mensagem-comercial-hierarquia.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-044.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    // O interno sobe pro meio: some a regua, some o cadeado, e o "por que ele
    // converte" fica colado no texto que o consultor repassa.
    nome: 'R1 — a leitura de conversao sobe pro meio do bloco pedagogico',
    pega: 'passo "a leitura de conversao vem DEPOIS do marcador"',
    de: `    '*Como foi*\\n%s\\n\\n'
    '*Próximos passos*\\n%s\\n'
    '━━━━━━━━━━━━━━\\n'
    '🔒 *Leitura de conversão* — uso interno, não encaminhar\\n%s',
    v_reg.nome_aluno,`,
    para: `    '*Como foi*\\n%s\\n\\n'
    'Leitura: %s\\n\\n'
    '*Próximos passos*\\n%s',
    v_reg.nome_aluno,`,
    reordenar: true,
  },
  {
    // O bloco continua por ultimo, mas sem dizer que e interno. O consultor
    // nao tem como saber que aquilo nao se repassa.
    nome: 'R2 — o bloco interno perde o aviso de nao encaminhar',
    pega: 'passo "o bloco interno e marcado como interno"',
    de: "    '🔒 *Leitura de conversão* — uso interno, não encaminhar\\n%s',",
    para: "    'Leitura de conversão\\n%s',",
  },
  {
    // Sem regua, tudo vira um bloco de texto so — a maçaroca que o Alf pediu
    // pra resolver na governanca.
    nome: 'R3 — somem as reguas e tudo vira um bloco so',
    pega: 'passo "ha regua separando os blocos"',
    de: "    '━━━━━━━━━━━━━━\\n'\n    '*Como foi*",
    para: "    '*Como foi*",
  },
  {
    // O defeito visivel no primeiro tiro real, de volta.
    nome: 'R4 — Próximos volta a perder o acento',
    pega: 'passo "Proximos virou Próximos"',
    de: "    '*Próximos passos*\\n%s\\n'",
    para: "    '*Proximos passos*\\n%s\\n'",
  },
  {
    // to_char(...,'Day') depende de lc_time do servidor: devolveria "Thursday"
    // sem avisar ninguem, e ninguem confere nome de dia em code review.
    nome: 'R5 — o dia da semana volta a depender do locale do servidor',
    pega: 'passo "dia da semana em portugues, sem depender de locale"',
    de: `    case extract(dow from v_reg.data_hora_inicio at time zone 'America/Sao_Paulo')
      when 0 then 'domingo' when 1 then 'segunda' when 2 then 'terça'
      when 3 then 'quarta'  when 4 then 'quinta' when 5 then 'sexta'
      else 'sábado' end,`,
    para: `    trim(to_char(v_reg.data_hora_inicio at time zone 'America/Sao_Paulo', 'Day')),`,
  },
  {
    // Falta virando presenca na mensagem: o comercial liga pra familia
    // parabenizando por uma aula que nao aconteceu.
    nome: 'R6 — falta aparece como presente na mensagem',
    pega: 'passo "e quem faltou NAO aparece como presente"',
    de: `    case coalesce(v_reg.presenca_status, 'nao informada')
      when 'presente' then 'presente ✅'
      when 'falta'    then 'faltou ❌'
      else 'presença não informada' end,`,
    para: "    'presente ✅',",
  },
  {
    // A reforma comendo o dado que o comercial mais precisa.
    nome: 'R7 — a leitura de conversao some da mensagem',
    pega: 'passo "a leitura de conversao NAO sumiu na reforma"',
    de: "    coalesce(v_reg.leitura_de_conversao, '_(não preenchido)_'));",
    para: "    '');",
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
  let mutado = fonte.replace(m.de, m.para)
  if (m.reordenar) {
    // R1 troca a ordem dos %s: a leitura passa a ser o 2o argumento de texto.
    mutado = mutado.replace(
      `    coalesce(v_reg.devolutiva_familia, '_(não preenchido)_'),
    coalesce(v_reg.proximos_passos, '_(não preenchido)_'),
    coalesce(v_reg.leitura_de_conversao, '_(não preenchido)_'));`,
      `    coalesce(v_reg.devolutiva_familia, '_(não preenchido)_'),
    coalesce(v_reg.leitura_de_conversao, '_(não preenchido)_'),
    coalesce(v_reg.proximos_passos, '_(não preenchido)_'));`,
    )
  }
  writeFileSync(TEMP, mutado)
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
