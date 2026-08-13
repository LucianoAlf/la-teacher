// Mutantes da 060 — o reconciliador passa a rodar.
//
// V1 é o defeito original em pessoa: nenhum job. Ele "sobreviveu" no banco de
// verdade por semanas, porque nada olhava. V2 é o irmão traiçoeiro — o job
// existe, aparece na lista de crons, e não roda.
//
// V5 é o que separa este teste de um teste de fachada: se o job apontar pra
// uma função que não faz nada, os passos de existir/ativo/ritmo continuam
// verdes. Só o passo que RODA o comando e mede o buraco acusa.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/060-o-reconciliador-passa-a-rodar.sql'
const TESTE = 'supabase/migrations/060-o-reconciliador-passa-a-rodar.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-060.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    // O job NÃO EXISTIR é o defeito original, mas depois que a migration foi
    // aplicada de verdade a linha mora em `cron.job` — produção, não este
    // arquivo. Um mutante que apenas deixa de criar o job encontra o que já
    // está lá e sobrevive sem significar nada. Por isso ele DESAGENDA: é a
    // mesma semântica ("não roda") de um jeito que o teste consegue ver.
    nome: 'V1 — o job e desagendado (a semantica do "nao roda")',
    pega: 'passo "o job existe"',
    de: `select cron.schedule(
  'reconciliar-experimental-aulas',
  '12,27,42,57 * * * *',
  $cron$select public.fn_reconciliar_experimental_aulas(7, 200)$cron$
);`,
    para: `select cron.unschedule('reconciliar-experimental-aulas');`,
  },
  {
    // O pior de todos: aparece na lista de crons, tem nome bonito, e nunca
    // dispara. "Está lá" vira prova falsa.
    nome: 'V2 — o job nasce desativado (aparece na lista, nao roda)',
    pega: 'passo "o job esta ativo"',
    de: `select cron.schedule(
  'reconciliar-experimental-aulas',
  '12,27,42,57 * * * *',
  $cron$select public.fn_reconciliar_experimental_aulas(7, 200)$cron$
);`,
    para: `select cron.schedule(
  'reconciliar-experimental-aulas',
  '12,27,42,57 * * * *',
  $cron$select public.fn_reconciliar_experimental_aulas(7, 200)$cron$
);
update cron.job set active = false where jobname = 'reconciliar-experimental-aulas';`,
  },
  {
    // Roda ANTES dos sync-metadados: reconcilia contra espelho velho e o
    // vínculo só nasce no ciclo seguinte — de graça, uma hora de atraso.
    nome: 'V3 — o ritmo volta pro comeco do quarto de hora (antes do espelho)',
    pega: 'passo "roda depois dos tres sync-metadados"',
    de: `'12,27,42,57 * * * *'`,
    para: `'0,15,30,45 * * * *'`,
  },
  {
    // Janela de 1 dia: a experimental de sexta só casa na quinta à noite, e o
    // professor abre o app na segunda sem ficha nenhuma da semana.
    nome: 'V4 — a janela encolhe pra 1 dia',
    pega: 'passo "a janela e de 7 dias"',
    de: `fn_reconciliar_experimental_aulas(7, 200)`,
    para: `fn_reconciliar_experimental_aulas(1, 200)`,
  },
  {
    // Aponta pra outra coisa: existe, ativo, no horário certo — e inútil.
    nome: 'V5 — o job aponta pra uma funcao que nao reconcilia nada',
    pega: 'passos "chama a funcao certa" e "rodar o job reduz o buraco"',
    de: `$cron$select public.fn_reconciliar_experimental_aulas(7, 200)$cron$`,
    para: `$cron$select 1$cron$`,
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
