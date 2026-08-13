// Mutantes da 073 — o semáforo ganha as perguntas.
//
// V2 é o motivo do arquivo existir: a régua da janela em UTC. Ela sobrevive a
// qualquer teste que use `current_date` dos dois lados — foi assim que o 018
// ficou vermelho por três horas por dia sem ninguém entender.
//
// V6/V7/V8/V9/V10 vieram da revisão de qualidade da Task 1: `evolucao` e
// `animo` tinham constraint sem prova, e só `fn_janela_feedback_aberta` tinha
// teste de permissão — as outras duas réguas de data ficaram tão abertas pro
// `anon` quanto ela ficaria sem o `revoke` dela.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/073-o-semaforo-ganha-as-perguntas.sql'
const TESTE = 'supabase/migrations/073-o-semaforo-ganha-as-perguntas.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-073.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'V1 — a janela abre 10 dias antes do fim do mes',
    pega: 'passos "janela FECHADA no dia 24" e "fevereiro: FECHADA em 21/02"',
    de: `  select with_dia.d >= (date_trunc('month', with_dia.d) + interval '1 month - 7 days')::date`,
    para: `  select with_dia.d >= (date_trunc('month', with_dia.d) + interval '1 month - 10 days')::date`,
  },
  {
    nome: 'V2 — hoje volta a ser UTC [a armadilha do 018]',
    pega: 'passo "fn_hoje_brt e a data BRT, nao a UTC"',
    de: `  select (now() at time zone 'America/Sao_Paulo')::date`,
    para: `  select current_date`,
  },
  {
    nome: 'V3 — a competencia arredonda pra semana em vez de mes',
    pega: 'passo "competencia de 31/08 as 22h BRT ainda e agosto"',
    de: `  select date_trunc('month', coalesce(p_dia, public.fn_hoje_brt()))::date`,
    para: `  select date_trunc('week', coalesce(p_dia, public.fn_hoje_brt()))::date`,
  },
  {
    nome: 'V4 — o check de pratica_em_casa aceita qualquer coisa',
    pega: 'passo "check recusa pratica_em_casa invalida"',
    de: `       check (pratica_em_casa is null or pratica_em_casa in ('sim','as_vezes','nao'));`,
    para: `       check (true);`,
  },
  {
    nome: 'V5 — o check da cor aceita qualquer coisa',
    pega: 'passo "check recusa cor invalida"',
    de: `       check (feedback in ('verde','amarelo','vermelho'));`,
    para: `       check (true);`,
  },
  {
    nome: 'V6 — o check de evolucao aceita qualquer coisa',
    pega: 'passo "check recusa evolucao invalida"',
    de: `       check (evolucao is null or evolucao in ('evoluindo','parado','regredindo'));`,
    para: `       check (true);`,
  },
  {
    nome: 'V7 — o check de animo aceita qualquer coisa',
    pega: 'passo "check recusa animo invalido"',
    de: `       check (animo is null or animo in ('animado','neutro','desanimado'));`,
    para: `       check (true);`,
  },
  {
    nome: 'V8 — fn_hoje_brt fica aberta pro anon [revoke perde o alvo PUBLIC+anon]',
    pega: 'passo "anon NAO executa fn_hoje_brt"',
    de: `revoke all on function public.fn_hoje_brt() from public, anon;`,
    para: `grant execute on function public.fn_hoje_brt() to anon;`,
  },
  {
    nome: 'V9 — fn_competencia_feedback fica aberta pro anon [revoke perde o alvo PUBLIC+anon]',
    pega: 'passo "anon NAO executa fn_competencia_feedback"',
    de: `revoke all on function public.fn_competencia_feedback(date) from public, anon;`,
    para: `grant execute on function public.fn_competencia_feedback(date) to anon;`,
  },
  {
    nome: 'V10 — fn_janela_feedback_aberta fica aberta pro anon [o achado do revisor]',
    pega: 'passo "anon NAO executa fn_janela_feedback_aberta"',
    de: `revoke all on function public.fn_janela_feedback_aberta(date) from public, anon;`,
    para: `grant execute on function public.fn_janela_feedback_aberta(date) to anon;`,
  },
]

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
  let passou = true
  try {
    execFileSync('node', ['scripts/rodar-teste-sql.mjs', TEMP, TESTE], { stdio: 'pipe' })
  } catch {
    passou = false
  }
  if (!passou) {
    mortos++
    console.log(`OK     morto: ${m.nome}  (${m.pega})`)
  } else {
    console.log(`FALHA  SOBREVIVEU: ${m.nome}  (${m.pega})`)
  }
}

try { unlinkSync(TEMP) } catch {}
console.log(`\n${mortos}/${MUTANTES.length} mutantes mortos` + (stale ? `  —  ${stale} ANCORA(S) PODRE(S)` : ''))
process.exitCode = mortos === MUTANTES.length && stale === 0 ? 0 : 1
