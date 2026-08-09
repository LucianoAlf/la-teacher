// Mutantes da 075 — o Fábio cobra o semáforo.
//
// V1 pega o achado que dá nome à migration junto com a 066: "reforço" e
// "coordenação" só valem pra quem não fechou — cobrar quem já respondeu é o
// jeito mais rápido de ensinar o professor a ignorar o Fábio.
//
// V2 pega o outro jeito de errar a competência: no dia 1, olhar o mês que
// COMEÇOU em vez do que ACABOU contaria feedback que ninguém pediu ainda.
//
// V3 e V4 pegam a âncora no fim do mês, que é o motivo desta migration
// existir com este desenho: a primeira versão do plano usava "segunda da
// janela" / "quinta da janela" e, em agosto/2026, isso invertia lembrete e
// reforço (reforço no dia 27, lembrete no 31 — cobrado antes de avisado). V4
// reproduz exatamente essa régua velha.
//
// V5 pega o contrato entre o índice único e o ON CONFLICT DO NOTHING: sem o
// UNIQUE, o índice ainda "funciona" pra leitura, mas o conflito nunca dispara
// e a idempotência vira decoração.
//
// V6 é a mesma armadilha de permissão das tasks anteriores (073/074): um
// `grant` a mais reabre a porta que o `revoke` fechou.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/075-o-fabio-cobra-o-semaforo.sql'
const TESTE = 'supabase/migrations/075-o-fabio-cobra-o-semaforo.test.sql'
const TEMP = 'supabase/migrations/_mutante-075.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'V1 — o reforco volta a cobrar quem JA fechou',
    pega: 'passo do reforco (quem esta completo nao pode receber)',
    de: `     where v_fase = 'lembrete' or ok < total`,
    para: `     where true`,
  },
  {
    nome: 'V2 — o dia 1 olha a competencia ERRADA (o mes que comecou)',
    pega: 'passo "dia 1 olha a competencia que ACABOU"',
    de: `    v_comp := (date_trunc('month', v_dia) - interval '1 month')::date;`,
    para: `    v_comp := date_trunc('month', v_dia)::date;`,
  },
  {
    nome: 'V3 — dispara em qualquer dia da janela, nao so no primeiro',
    pega: 'passo "dia do meio da janela NAO dispara"',
    de: `  elsif v_dia = v_ultimo - 6 then   -- primeiro dia da janela`,
    para: `  elsif public.fn_janela_feedback_aberta(v_dia) then   -- primeiro dia da janela`,
  },
  {
    // O defeito real que motivou a âncora no fim do mês: com a régua de dia da
    // semana, em agosto/2026 o reforço cai no dia 27 e o lembrete no 31 — o
    // professor é cobrado antes de ser avisado.
    nome: 'V4 — volta a regua de dia da semana e INVERTE a ordem',
    pega: 'passo "em todo mes de 2026 o lembrete vem antes do reforco"',
    de: `  elsif v_dia = v_ultimo - 6 then   -- primeiro dia da janela
    v_fase := 'lembrete';
  elsif v_dia = v_ultimo - 3 then   -- três dias depois, sempre depois
    v_fase := 'reforco';`,
    para: `  elsif public.fn_janela_feedback_aberta(v_dia) and extract(isodow from v_dia) = 1 then
    v_fase := 'lembrete';
  elsif public.fn_janela_feedback_aberta(v_dia) and extract(isodow from v_dia) = 4 then
    v_fase := 'reforco';`,
  },
  {
    nome: 'V5 — some o indice unico e o ON CONFLICT vira decoracao',
    pega: 'passo "rodar de novo no mesmo dia NAO duplica"',
    de: `create unique index if not exists fabio_notificacoes_feedback_dia_unico
  on public.fabio_notificacoes (professor_id, tipo, dia_referencia)
  where tipo like 'feedback_%';`,
    para: `create index if not exists fabio_notificacoes_feedback_dia_unico
  on public.fabio_notificacoes (professor_id, tipo, dia_referencia)
  where tipo like 'feedback_%';`,
  },
  {
    nome: 'V6 — a cobranca fica aberta pro authenticated',
    pega: 'passo "authenticated NAO executa a cobranca"',
    de: `revoke all on function public.fn_enfileirar_cobranca_feedback(date) from public, anon, authenticated;`,
    para: `grant execute on function public.fn_enfileirar_cobranca_feedback(date) to authenticated;`,
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
