// Mutantes da 081 — os sinais do Radar do aluno.
//
// Cada mutante desfaz uma das quatro decisões que custaram medição contra o
// banco de produção: grão de aula (não linha), denominador honesto, janela
// virada em 01/08 e coorte de professor com login — mais a coerência entre
// absenteismo_pct e a ausência de base. Se um sobreviver, quem está errado é
// o TESTE que não pegou, não o mutante — o passo que falta se adiciona lá.
//
// V6-V8 vieram da rodada de correção (revisão, 10/08): V6 é o C1 crítico (a
// porta pra `authenticated` reabrindo), V7 é o I2 (o mutante "is not null"
// que o passo estrutural sozinho não pegava — a coluna nunca é NULL de
// verdade, então ele é gêmeo do V2), V8 é o I1 (current_date cru voltando no
// lugar de fn_competencia_feedback).
//
// REPONTADO PARA A 088 (revisão da Task 10, 10/08): a 088 reaplica esta MESMA
// view (create or replace) com o 5º sinal ACRESCENTADO no fim da lista de
// colunas — a view viva tem 21 colunas, e `081-os-sinais-do-radar.sql`
// sozinho só define 20. `create or replace view` recusa DROPAR coluna, então
// mutar o arquivo 081 e tentar reaplicar contra a view viva falha com
// "cannot drop columns from view" pra QUALQUER mutação, inclusive nenhuma —
// os "mortos" que isso produzia não provavam nada (erro de schema, não a
// asserção do teste). As 4 decisões que este arquivo documenta continuam
// intactas, palavra por palavra, dentro do corpo da 088 — por isso ORIGINAL
// aponta pra lá agora, e as 8 âncoras abaixo batem sem ajuste (conferido:
// cada uma ocorre exatamente 1 vez no texto da 088). TESTE continua sendo o
// da 081: nenhuma das assertions checa contagem/ordem de coluna, então
// seguem válidas contra o formato novo.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/088-a-falta-seguida-e-o-quinto-sinal.sql'
const TESTE = 'supabase/migrations/081-os-sinais-do-radar.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-081.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'V1 — o grão volta a ser linha (aula_emusys_id entra no group by)',
    pega: 'passo "aulas_medidas conta AULA, nao linha"',
    de: `   group by 1, 2, 3\n)`,
    para: `   group by 1, 2, 3, v.aula_emusys_id\n)`,
  },
  {
    // O passo comportamental ("nenhum aluno tem mais aula medida do que aula
    // confirmada") não pega este mutante HOJE: medido em 10/08, todo slot de
    // aula da coorte desde 01/08 já tem uma linha confirmada, então tirar o
    // filtro não muda nenhuma contagem nos dados atuais. Quem mata é o passo
    // estrutural, que lê o texto da view (mesma técnica do `fn_hoje_brt`).
    nome: 'V2 — o denominador para de ser honesto (justificada/provavel entram)',
    pega: 'passo "a view cita considera_frequencia_denominador no filtro da aula"',
    de: `   where v.considera_frequencia_denominador\n     and v.data_aula >= date '2026-08-01'`,
    para: `   where true\n     and v.data_aula >= date '2026-08-01'`,
  },
  {
    nome: 'V3 — a janela vaza pra era contaminada (busca desde junho)',
    pega: 'passo "a janela nao busca antes de 01/08"',
    de: `     and v.data_aula >= date '2026-08-01'`,
    para: `     and v.data_aula >= date '2026-06-01'`,
  },
  {
    nome: 'V4 — a coorte cai, a escola inteira entra (join vira left join)',
    pega: 'passo "so entra aluno de professor que ja entrou no app"',
    de: `  join coorte c   on c.professor_id = s.professor_atual_id`,
    para: `  left join coorte c   on c.professor_id = s.professor_atual_id`,
  },
  {
    nome: 'V5 — sem base vira 0% em vez de nulo',
    pega: 'passo "sem aula medida, o absenteismo e NULO (nao zero)"',
    de: `       case when coalesce(j.aulas_medidas, 0) > 0\n            then round(100.0 * j.faltas_janela / j.aulas_medidas, 1)\n       end`,
    para: `       coalesce(round(100.0 * j.faltas_janela / nullif(j.aulas_medidas,0), 1), 0)`,
  },
  {
    // C1 da revisão: a porta pra `authenticated` reabre (ex.: alguém adiciona
    // de volta sem tirar o revoke/grant certo). Sem este passo, RLS de
    // aluno_feedback_professor fica sem efeito nenhum pra quem lê pela view.
    nome: 'V6 — o grant pra authenticated volta (C1, a porta reabre)',
    pega: 'passo "a view NAO e legivel por authenticated"',
    de: `grant select on table public.vw_radar_aluno_sinais to service_role;`,
    para: `grant select on table public.vw_radar_aluno_sinais to service_role;\ngrant select on public.vw_radar_aluno_sinais to authenticated;`,
  },
  {
    // I2 da revisão: `is not null` é sempre verdadeiro (a coluna nunca é NULL
    // de verdade) — MESMO defeito do V2, mas mantém o identificador no texto,
    // então o passo estrutural sozinho não pega. Só o fixture ZZTESTE pega.
    nome: 'V7 — denominador neutralizado sem apagar o identificador (is not null)',
    pega: 'passo "aluno so com aula fora do denominador: aulas_medidas fica 0"',
    de: `   where v.considera_frequencia_denominador\n     and v.data_aula >= date '2026-08-01'`,
    para: `   where v.considera_frequencia_denominador is not null\n     and v.data_aula >= date '2026-08-01'`,
  },
  {
    // I1 da revisão: current_date cru é UTC — erra a competência das 21h à
    // meia-noite BRT do último dia do mês (mesma armadilha da 018/073).
    nome: 'V8 — a competencia do semaforo volta a usar current_date cru',
    pega: 'passo "a view usa fn_competencia_feedback, nao current_date cru"',
    de: `   where f.competencia = public.fn_competencia_feedback()`,
    para: `   where f.competencia = date_trunc('month', current_date)::date`,
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
