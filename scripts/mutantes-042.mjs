// Mutantes do contexto do professor — a chave do passivo (LA Report).
//
// A migration mora no outro repo (D:/la-performance-report), porque
// fabio_contexto_professor e de la. O runner e o padrao de mutante moram aqui.
// Repo diferente, mesmo banco, mesma disciplina.
//
// O que estes tres guardam:
//   N1  o passivo nao pode virar espelho da cobranca
//   N2  a chave nao pode sumir quando nao ha o que mostrar (chave sumida foi
//       exatamente o defeito: sem numero, o modelo afirma a negativa)
//   N3  a cobranca NAO engordou junto com o conserto — e o mutante mais
//       importante, porque o risco de "consertar" era desfazer a 041

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const BASE = 'D:/la-performance-report/supabase/migrations'
const ORIGINAL = `${BASE}/20260806103000_fabio_contexto_conta_o_passivo.sql`
const TESTE = `${BASE}/20260806103000_fabio_contexto_conta_o_passivo.test.sql`
const TEMP = `${BASE}/_mutante-042.sql`
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'N1 — o passivo vira espelho da cobranca (filtro invertido)',
    pega: 'passo "fim da janela do passivo e a vespera do corte"',
    de: '       where professor_id = p_professor_id and not cobravel',
    para: '       where professor_id = p_professor_id and cobravel',
  },
  {
    // Renomear a chave e o jeito coerente de faze-la sumir: nao quebra SQL,
    // e reproduz exatamente o estado de antes do conserto.
    nome: 'N2 — a chave do passivo some do contexto',
    pega: 'passo "a chave do passivo existe"',
    de: "    'registro_fora_da_cobranca', (",
    para: "    'registro_fora_da_cobranca_indisponivel', (",
  },
  {
    // Se a cobranca passar a incluir o passivo, o Fabio volta a cobrar o
    // Matheus por aulas de junho na frente da coordenacao. Foi o erro de
    // 05/08, e "consertar a resposta" e uma otima desculpa pra reintroduzi-lo.
    nome: 'N3 — o passivo entra na COBRANCA de carona',
    pega: 'passo "cobranca conta so os alunos cobraveis"',
    de: '        (public.fn_pendencias_do_professor(p_professor_id, false))->>\'total_alunos\',',
    para: '        (public.fn_pendencias_do_professor(p_professor_id, true))->>\'total_alunos\',',
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
