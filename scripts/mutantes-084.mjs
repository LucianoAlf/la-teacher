// Mutantes da 084 — a janela do professor vira 7 dias.
//
// O mutante que mais importa aqui é o V2/V3: a função `fn_janela_registro_dias`
// continua dizendo 7, e o corpo da chamada (ou da gravação) volta a ter o 3 na
// mão. É o defeito ORIGINAL na forma mais traiçoeira que existe — o contrato
// anuncia uma coisa e o código faz outra, e quem for conferir lendo a função do
// prazo vai jurar que está tudo certo.
//
// V5/V6/V8 são o lado oposto: janela que nunca fecha. Sem eles, "abrir a
// janela" poderia virar "arrancar a porta" e o teste aplaudiria.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/084-a-janela-do-professor-vira-sete-dias.sql'
const TESTE = 'supabase/migrations/084-a-janela-do-professor-vira-sete-dias.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-084.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'V1 — o dono do prazo volta a dizer 3 (o estado de antes, honesto)',
    pega: 'passos "a janela tem um dono unico e ele diz 7", "chamada de 5 dias ENTRA", "audio de 5 dias ENTRA"',
    de: `as $function$ select 7 $function$;`,
    para: `as $function$ select 3 $function$;`,
  },
  {
    nome: 'V2 — a CHAMADA volta a ter o 3 na mao enquanto o contrato anuncia 7',
    pega: 'passo "chamada de 5 dias atras ENTRA"',
    de: `    if coalesce(v_aula.data_hora_fim, v_aula.data_hora_inicio) < now() - (public.fn_janela_registro_dias() || ' days')::interval then raise exception 'janela_de_chamada_encerrada'; end if;`,
    para: `    if coalesce(v_aula.data_hora_fim, v_aula.data_hora_inicio) < now() - interval '3 days' then raise exception 'janela_de_chamada_encerrada'; end if;`,
  },
  {
    nome: 'V3 — a GRAVACAO volta a ter o 3 na mao enquanto o contrato anuncia 7',
    pega: 'passo "audio de 5 dias atras ENTRA na fila"',
    de: `  if coalesce(v_aula.data_hora_fim, v_aula.data_hora_inicio) < now() - (public.fn_janela_registro_dias() || ' days')::interval then raise exception 'janela_de_gravacao_encerrada'; end if;`,
    para: `  if coalesce(v_aula.data_hora_fim, v_aula.data_hora_inicio) < now() - interval '3 days' then raise exception 'janela_de_gravacao_encerrada'; end if;`,
  },
  {
    nome: 'V4 — a escalacao volta a cobrar em 3 dias (entrega a coordenacao quem ainda tem 4 dias)',
    pega: 'passos "a escalacao sem argumento usa a MESMA regua" e "aula de 5 dias NAO sobe"',
    de: `  v_dias integer := coalesce(p_dias, public.fn_janela_registro_dias());`,
    para: `  v_dias integer := coalesce(p_dias, 3);`,
  },
  {
    nome: 'V5 — a janela da CHAMADA nunca fecha (abrir a porta virou arrancar a porta)',
    pega: 'passo "chamada de 10 dias atras continua RECUSADA"',
    de: `then raise exception 'janela_de_chamada_encerrada'; end if;`,
    para: `then raise notice 'janela_de_chamada_encerrada'; end if;`,
  },
  {
    nome: 'V6 — a guarda de aula FUTURA cai junto (registra aula que nao aconteceu)',
    pega: 'passo "aula futura continua recusada"',
    de: `    if v_aula.data_hora_inicio > now() + interval '15 minutes' then raise exception 'chamada_ainda_nao_disponivel'; end if;`,
    para: `    if false then raise exception 'chamada_ainda_nao_disponivel'; end if;`,
  },
  {
    nome: 'V7 — o argumento explicito da escalacao vira parametro morto',
    pega: 'passo "argumento explicito continua vencendo o default"',
    de: `  v_dias integer := coalesce(p_dias, public.fn_janela_registro_dias());
begin`,
    para: `  v_dias integer := public.fn_janela_registro_dias();
begin`,
  },
  {
    nome: 'V8 — a janela da GRAVACAO nunca fecha',
    pega: 'passo "audio de 10 dias atras continua RECUSADO"',
    de: `then raise exception 'janela_de_gravacao_encerrada'; end if;`,
    para: `then raise notice 'janela_de_gravacao_encerrada'; end if;`,
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
