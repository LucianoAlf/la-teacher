// Mutantes da limpeza que para de se repetir.
//
// Cada alteracao abaixo tem que MORRER no teste SQL. Se uma sobreviver, ou o
// laco volta (o worker limpando as mesmas linhas pra sempre) ou o conserto
// fechou o laco quebrando a limpeza -- que e o erro pior dos dois.
//
// NORMALIZACAO DE FIM DE LINHA, E POR QUE ELA ESTA AQUI:
// a auditoria de 13/08 descobriu que 4 dos 5 mutantes da fila experimental
// estavam STALE nesta maquina. Causa: `core.autocrlf=true` sem `.gitattributes`
// deixa os .sql em CRLF no checkout, enquanto as ancoras sao escritas com \n
// dentro de literais JS. Ancora de uma linha casa; ancora multilinha nunca
// casa -- e o placar final passa a vista como se fosse resultado.
// Enquanto o Sprint 2 nao conserta isso na origem (.gitattributes), este
// runner se defende sozinho normalizando o que le.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/20260813160000_limpeza_nao_se_repete.sql'
const TESTE = 'supabase/migrations/20260813160000_limpeza_nao_se_repete.test.sql'
const TEMP = 'supabase/migrations/_mutante-limpeza-nao-se-repete.sql'

const lf = (s) => s.replace(/\r\n/g, '\n')
const fonte = lf(readFileSync(ORIGINAL, 'utf8'))

const MUTANTES = [
  {
    nome: 'M1 — o claim volta a ignorar o carimbo (o laco renasce)',
    pega: 'passo "acao ja limpa NAO e reivindicada de novo"',
    de: "      and not (coalesce(a.payload, '{}'::jsonb) ? 'limpeza')\n",
    para: '',
  },
  // NAO existe mutante para o `coalesce` do payload: a coluna e NOT NULL com
  // default '{}'::jsonb, entao o banco recusa o fixture de payload nulo. Esta
  // anotado na migration que aquela clausula e defesa futura, nao coberta hoje.
  // Escrever o mutante assim mesmo daria 5/5 por ERRO de fixture, nao por
  // assercao -- que foi exatamente como o "5/5" da fila experimental nasceu.
  {
    nome: 'M2 — o claim devolve fila vazia em silencio',
    pega: 'passo "acao terminal ainda nao limpa e reivindicada"',
    de: 'limit greatest(p_limite, 0)',
    para: 'limit 0',
  },
  {
    nome: 'M3 — clausula invertida: so limpa quem JA foi limpo',
    pega: 'passo "acao terminal ainda nao limpa e reivindicada"',
    de: "and not (coalesce(a.payload, '{}'::jsonb) ? 'limpeza')",
    para: "and (coalesce(a.payload, '{}'::jsonb) ? 'limpeza')",
  },
  {
    nome: 'M4 — a porta de worker se abre para authenticated',
    pega: 'passo "claim de limpeza nao executavel por authenticated"',
    de: '  to service_role;',
    para: '  to service_role, authenticated;',
  },
  {
    nome: 'M5 — o filtro de estado cai e a limpeza alcanca acao viva',
    pega: 'passo "acao viva nunca e reivindicada pela limpeza"',
    de: "    where a.estado in ('cancelada','expirada','erro') and a.storage_path is not null",
    para: '    where a.storage_path is not null',
  },
]

// Sem baseline verde, todo mutante morre de erro e o placar mente.
exigirBaselineVerde(ORIGINAL, TESTE)

let mortos = 0
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

// STALE conta como falha: ancora podre nao prova nada, e foi exatamente assim
// que "5/5" virou 1/5 sem ninguem perceber.
process.exitCode = mortos === MUTANTES.length ? 0 : 1
