// Mutantes da 087 — a RPC da tela do Radar.
//
// V1-V6 vêm do brief: guard, faceta auto-filtrante, resumo/lista discordam,
// semáforo agregado por professor (fronteira), validação de status, e mediana
// ausente. Cada um testa uma regra que a casa já pagou pra aprender.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/087-a-tela-do-radar.sql'
const TESTE = 'supabase/migrations/087-a-tela-do-radar.test.sql'
const TEMP = 'supabase/migrations/_mutante-087.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'V1 — guard cai (professor abre o radar)',
    pega: 'passo "professor nao abre o radar"',
    de: `  if not public.fn_e_coordenacao_la_teacher() then
    raise exception 'apenas_admin';
  end if;`,
    para: `  if false then
    raise exception 'apenas_admin';
  end if;`,
  },
  {
    nome: 'V2 — faceta se filtra (faceta_uni fica cega a unidade_id)',
    pega: 'passo "com unidade escolhida, a lista de unidades NAO encolhe"',
    de: `  fac_uni  as (select * from com_status
                where (p_professor_id is null or professor_id = p_professor_id)
                  and (v_status is null or status_calc = v_status)),`,
    para: `  fac_uni  as (select * from com_status
                where (p_unidade_id is null or unidade_id = p_unidade_id) and (p_professor_id is null or professor_id = p_professor_id)
                  and (v_status is null or status_calc = v_status)),`,
  },
  {
    nome: 'V3 — resumo e lista contam coisas diferentes',
    pega: 'passo "resumo e lista contam a mesma coisa"',
    de: `    'total_lista', (select count(*) from linha),`,
    para: `    'total_lista', (select count(*) from com_status),`,
  },
  {
    nome: 'V4 — semáforo agregado por professor (fronteira §2.1 quebrada)',
    pega: 'passo "as medias por professor nao carregam semaforo"',
    de: `                              jsonb_build_object('professor_id', professor_id, 'professor', professor_nome,
                                                'absenteismo_media', round(avg(absenteismo_pct),1)) as j
                         from com_status where professor_id is not null`,
    para: `                              jsonb_build_object('professor_id', professor_id, 'professor', professor_nome,
                                                'absenteismo_media', round(avg(absenteismo_pct),1), 'vermelhos', count(*) filter (where feedback='vermelho')) as j
                         from com_status where professor_id is not null`,
  },
  {
    nome: 'V5 — validação de status cai (status inventado passa)',
    pega: 'passo "status invalido e recusado"',
    de: `  if v_status is not null and v_status not in ('critico','atencao','saudavel','sem_nota') then
    raise exception 'status_invalido';
  end if;`,
    para: `  if false then
    raise exception 'status_invalido';
  end if;`,
  },
  {
    nome: 'V6 — mediana some do resumo',
    pega: 'passo "e a media E a mediana vem as duas"',
    de: `'absenteismo_mediana', round(percentile_cont(0.5)
                                 within group (order by absenteismo_pct)::numeric, 1),`,
    para: `'absenteismo_mediana', (case when false then round(percentile_cont(0.5) within group (order by absenteismo_pct)::numeric, 1) else null end),`,
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

console.log(`\n${previstos}/${MUTANTES.length} mutantes mortos${stale > 0 ? ` (${stale} ancora(s) stale)` : ''}`)

if (previstos < MUTANTES.length - stale) {
  process.exit(1)
}
