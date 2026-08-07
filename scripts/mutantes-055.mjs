// Mutantes da 055 — o Fábio fica sabendo como a experimental foi.
//
// Y1 devolve o estado que eu acabei de achar conversando: o Fábio negando o
// capítulo que ajudou a escrever. Y2 é o excesso oposto — a leitura de
// conversão indo pro WhatsApp. Os dois precisam morrer, e num teste só: uma
// migration que corrige omissão erra pra dentro OU pra fora, e um teste que
// olha só um lado aprova o outro.
//
// Y6 é o que eu quase não escrevi: o LEFT JOIN novo pode DUPLICAR a
// experimental se o filtro de vínculo substituído cair. Duplicar não parece
// defeito de fronteira nem de conteúdo — parece um Fábio confuso, e a causa
// fica escondida numa cláusula de junção.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/055-o-fabio-fica-sabendo-como-foi.sql'
const TESTE = 'supabase/migrations/055-o-fabio-fica-sabendo-como-foi.test.sql'
const TEMP = 'supabase/migrations/_mutante-055.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'Y1 — o Fábio volta a não ver o registro (o defeito de hoje)',
    pega: 'passo "o Fabio sabe que houve registro"',
    de: `           'registro', case when r.id is null then null else jsonb_build_object(`,
    para: `           'registro', case when true then null else jsonb_build_object(`,
  },
  {
    nome: 'Y2 — a leitura de conversão vaza pro WhatsApp',
    pega: 'passo "e o Fabio NAO leva a leitura de conversao"',
    de: `             'proximos_passos',     r.proximos_passos`,
    para: `             'proximos_passos',     r.proximos_passos,
             'leitura_de_conversao', r.leitura_de_conversao`,
  },
  {
    // Cortar demais: o professor pergunta como foi e recebe metade. Já
    // aconteceu com a anamnese — eu cortei por privacidade e o Alf reverteu.
    nome: 'Y3 — o corte leva junto o que o professor escreveu',
    pega: 'passo "e leva o que aconteceu na aula"',
    de: `             'anotacao_pedagogica', r.anotacao_pedagogica,`,
    para: '',
  },
  {
    nome: 'Y4 — a presença não viaja (o Fábio não sabe se aconteceu)',
    pega: 'passo "e a presenca"',
    de: `           'presenca',             v.presenca_status,`,
    para: '',
  },
  {
    // O corte da 049 desfeito na reescrita: é o risco de toda migration que
    // republica uma função inteira.
    nome: 'Y5 — a reescrita desfaz o corte da 049',
    pega: 'passo "e o sinal de conversao continua barrado nos dois"',
    de: `           'contexto',             (e.contexto #- '{para_a_devolutiva,atencao_conversao}'),`,
    para: `           'contexto',             e.contexto,`,
  },
  {
    nome: 'Y6 — o vínculo substituído duplica a experimental',
    pega: 'passo "vinculo substituido nao duplica a experimental"',
    de: `          and v.substituido_em is null`,
    para: '',
  },
  {
    // A guarda de posse da 029: sem ela o Fábio mostra a experimental de
    // qualquer professor.
    nome: 'Y7 — a guarda de posse some na reescrita',
    pega: 'passo "professor nulo continua sendo recusado"',
    de: `    raise exception 'professor_id_obrigatorio: o Fabio so pode mostrar as experimentais DESTE professor.'
      using errcode = '42501';`,
    para: `    return '[]'::jsonb;`,
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
