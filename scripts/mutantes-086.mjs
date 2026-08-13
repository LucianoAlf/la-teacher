// Mutantes da 086 — o gêmeo para de divergir na escrita.
//
// V1/V2 são o defeito original voltando: presença gravada só na âncora. V3 é o
// pior desvio possível pro OUTRO lado — a sincronização apaga resposta humana
// forte, o que seria pior que o defeito de origem (ali só faltava atualizar;
// aqui destruiria dado). V4/V5 testam o parâmetro de escopo: sem ele funcionar
// de verdade, cada chamada de um professor varreria a escola inteira.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/086-o-gemeo-para-de-divergir-na-escrita.sql'
const TESTE = 'supabase/migrations/086-o-gemeo-para-de-divergir-na-escrita.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-086.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'V1 — fn_registrar_presencas_core deixa de chamar o sincronizador (o defeito original)',
    pega: 'passos "fixture1: a1/a2 SINCRONIZA" e "gemeos_sincronizados"',
    de: `  -- 086: o gêmeo (turma↔individual) recebe a MESMA resposta. Escopado nesta
  -- aula — não varre a escola inteira a cada chamada.
  v_gemeos := public.fn_sincronizar_gemeos_presenca(v_aula.id);`,
    para: `  v_gemeos := 0;`,
  },
  {
    nome: 'V2 — o gemeo passa a ser buscado do MESMO tipo (turma acha turma, nunca o par)',
    pega: 'passos "fixture1: a1/a2 SINCRONIZA" e "fixture2: backfill"',
    de: `         where i.tipo = (case when f.tipo = 'turma' then 'individual' else 'turma' end)`,
    para: `         where i.tipo = f.tipo`,
  },
  {
    nome: 'V3 — a trava cai: sincronizacao apaga resposta humana forte do gemeo (pior que o defeito original)',
    pega: 'passo "fixture1: a3 tem resposta HUMANA no gemeo (manual) — NAO e sobrescrita"',
    de: `        where aluno_presenca.respondido_por is null
           or aluno_presenca.respondido_por in ('emusys','sistema')
      returning 1`,
    para: `        where true
      returning 1`,
  },
  {
    nome: 'V4 — o parametro de escopo e ignorado (toda chamada varre a escola inteira)',
    pega: 'passo "fixture3: escopo errado NAO toca no par"',
    de: `       and (p_aula_ancora_id is null or ap.aula_emusys_id = p_aula_ancora_id)`,
    para: `       and true`,
  },
  {
    nome: 'V5 — o retorno de fn_registrar_presencas_core esconde quantos gemeos sincronizou',
    pega: 'passo "fixture1: o retorno conta 2 gemeos sincronizados"',
    de: `'gemeos_sincronizados', coalesce(v_gemeos,0), 'aplicado', true);`,
    para: `'gemeos_sincronizados', 0, 'aplicado', true);`,
  },
]

// NÃO existe mutante pra "a linha de BACKFILL sem escopo no fim da migration
// desaparece" — e é de propósito, não descuido. `rodar-teste-sql.mjs` roda
// migration.sql inteiro ANTES de test.sql: o `select
// fn_sincronizar_gemeos_presenca();` no fim da 086 só teria o que sincronizar
// se já existisse divergência em PRODUÇÃO no instante em que a migration
// aplica — as fixtures do teste ainda nem existem quando essa linha roda.
// Um mutante que apagasse essa linha passaria pelas 11 asserções do jeito que
// estão, do mesmo jeito que a migration 068 documentou (ver
// teste-sql-so-vale-com-mutante.md). A prova dessa linha específica é
// medição direta em produção, ANTES/DEPOIS de aplicar — feita à mão, não
// pelo harness: 59 pares fortes divergiam antes de aplicar a 086; 0 depois.

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
