// Mutantes da 082 — as réguas do Radar do aluno.
//
// V1-V4 vêm do brief: guard da leitura, histórico que some na escrita, chave
// desconhecida sendo aceita, e a fábrica deixando de ser referência (a coluna
// que NUNCA muda — é o que sustenta a régua "nasce frouxa, aperta com o
// tempo": sem fábrica intacta, ninguém prova quanto a linha já andou).
//
// V5 é acréscimo à revisão: reintroduz exatamente o defeito que a Task 1
// (081) cometeu numa VIEW — grant de leitura pra `authenticated` — agora
// numa TABELA. Sem ele, o passo novo do teste ("as tabelas de config nao sao
// legiveis por authenticated") fica bonito mas nunca foi provado capaz de
// pegar a régua voltando a vazar.
//
// Se um mutante sobreviver, quem está errado é o TESTE que não pegou, nunca
// o mutante — o passo que falta se adiciona lá, não se afrouxa aqui.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/082-as-reguas-do-radar.sql'
const TESTE = 'supabase/migrations/082-as-reguas-do-radar.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-082.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'V1 — guard da leitura cai (app_radar_config nao exige coordenacao)',
    pega: 'passo "quem nao e coordenacao nao le a config"',
    de: `  if not public.fn_e_coordenacao_la_teacher() then\n    raise exception 'apenas_admin';\n  end if;\n\n  return jsonb_build_object(\n    'itens'`,
    para: `  if false then\n    raise exception 'apenas_admin';\n  end if;\n\n  return jsonb_build_object(\n    'itens'`,
  },
  {
    nome: 'V2 — o historico some na escrita',
    pega: 'passo "a mudanca gravou historico"',
    de: `  insert into public.radar_config_historico (chave, valor_anterior, valor_novo, mudado_por)\n  values (p_chave, v_anterior, p_valor, v_quem);`,
    para: `  if false then\n  insert into public.radar_config_historico (chave, valor_anterior, valor_novo, mudado_por)\n  values (p_chave, v_anterior, p_valor, v_quem);\n  end if;`,
  },
  {
    nome: 'V3 — chave desconhecida e aceita (vira lixo silencioso)',
    pega: 'passo "chave desconhecida e recusada"',
    de: `    raise exception 'chave_desconhecida';`,
    para: `    insert into public.radar_config(chave,valor,fabrica,rotulo,grupo,ordem) values (p_chave,p_valor,p_valor,p_chave,'outros',99); return jsonb_build_object('ok',true);`,
  },
  {
    nome: 'V4 — a fabrica deixa de ser referencia (muda junto com o valor)',
    pega: 'passo "a fabrica NAO mudou (e a referencia do que foi mexido)"',
    de: `  update public.radar_config set valor = p_valor where chave = p_chave;`,
    para: `  update public.radar_config set valor = p_valor, fabrica = p_valor where chave = p_chave;`,
  },
  {
    // Reintroduz o defeito da Task 1 (081), agora em tabela: RLS sem policy
    // barra a LINHA, mas o GRANT explícito pra `authenticated` reabre a
    // LEITURA pelo catálogo de privilégios — has_table_privilege() acusa,
    // mesmo que nenhuma linha volte pela RLS.
    nome: 'V5 — o grant pra authenticated volta na tabela (o vazamento da 081, em tabela)',
    pega: 'passo "as tabelas de config nao sao legiveis por authenticated"',
    de: `revoke all on table public.radar_config           from public, anon, authenticated;\nrevoke all on table public.radar_config_historico from public, anon, authenticated;`,
    para: `revoke all on table public.radar_config           from public, anon, authenticated;\nrevoke all on table public.radar_config_historico from public, anon, authenticated;\ngrant select on public.radar_config to authenticated;`,
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
