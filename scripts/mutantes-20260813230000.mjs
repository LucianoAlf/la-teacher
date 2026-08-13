// Mutantes do arquivamento de bloqueio permanente.
//
// M1 e M2 são os caros: um carimba o que devia voltar (o áudio some do radar
// enquanto uma ação aberta ainda o usa) e o outro carimba o que era removível
// (o laço ao contrário — nunca mais limpa). M3 é o defeito original: voltar a
// não carimbar nada, que é o `continue` do worker escrito em SQL.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/20260813230000_bloqueio_permanente_sai_da_fila.sql'
const TESTE = 'supabase/migrations/20260813230000_bloqueio_permanente_sai_da_fila.test.sql'
const TEMP = 'supabase/migrations/_mutante-bloqueio-permanente.sql'

const lf = (s) => s.replace(/\r\n/g, '\n')
const fonte = lf(readFileSync(ORIGINAL, 'utf8'))

const MUTANTES = [
  {
    nome: 'M1 — carimba qualquer motivo, inclusive o temporario',
    pega: 'passo "bloqueio temporario NAO e carimbado"',
    de: "if v_motivo is distinct from 'registro_confirmado_referencia_storage' then",
    para: 'if false then',
  },
  {
    nome: 'M2 — a guarda de "limpeza permitida" cai',
    pega: 'passo "audio REMOVIVEL nao pode ser arquivado por esta porta"',
    de: "if coalesce((v_prova ->> 'pode_remover')::boolean, false) is true then",
    para: 'if false then',
  },
  {
    // O carimbo e o claim são UM contrato: a chave `limpeza`. Renomear de um
    // lado só não quebra nada visível — a ação volta a girar em silêncio, que
    // é exatamente o defeito original com outra roupa.
    nome: 'M3 — o carimbo usa outra chave e o claim volta a enxergar a acao',
    pega: 'passos do carimbo e do claim que nao ve mais a permanente',
    de: `       'limpeza', jsonb_build_object(
         'removido', false,`,
    para: `       'limpeza_bloqueada', jsonb_build_object(
         'removido', false,`,
  },
  {
    nome: 'M4 — o lease deixa de ser conferido',
    pega: 'passo "lease invalido e recusado"',
    de: `  if v_a.lease_token is distinct from p_lease_token
     or v_a.lease_expira_em < now() then`,
    para: '  if false then',
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
