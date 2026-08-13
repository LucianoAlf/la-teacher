// Mutantes da 037 — as duas views.
//
// O plano tinha 2. Viraram 5: os tres novos existem porque o teste do plano
// so olhava catalogo, e catalogo sozinho fica verde com view quebrada (M4) ou
// com registro descartado vazando (M3).

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/037-views-registro-experimental.sql'
const TESTE = 'supabase/migrations/037-views-registro-experimental.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-037.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    // O vazamento que a spec proibe: o "por que ele converte" chegando num
    // texto que pode ser repassado a familia.
    nome: 'M1 — a leitura de conversao entra na view family-safe',
    pega: 'passo "view family_safe NAO TEM leitura_de_conversao"',
    de: `       r.status,
       r.criado_em
       -- leitura_de_conversao NAO entra aqui. Nunca.`,
    para: `       r.status,
       r.criado_em,
       r.leitura_de_conversao`,
  },
  {
    nome: 'M2 — anon ganha leitura da view comercial',
    pega: 'passo "anon nao le a view comercial"',
    de: 'revoke all on public.vw_experimental_registro_comercial from public, anon, authenticated;',
    para: 'grant select on public.vw_experimental_registro_comercial to anon;',
  },
  {
    // "family-safe" e sobre CONTEUDO, nao autorizacao: a linha carrega nome de
    // lead, unidade e horario, e sem filtro por professor o select direto
    // entrega a base de leads inteira.
    nome: 'M3 — authenticated le a family_safe (base de leads exposta)',
    pega: 'passo "authenticated nao le a view family_safe"',
    de: 'revoke all on public.vw_experimental_registro_family_safe from public, anon, authenticated;',
    para: 'grant select on public.vw_experimental_registro_family_safe to authenticated;',
  },
  {
    // Registro descartado e o rascunho substituido. Vazando pra view, o
    // comercial recebe a versao velha da conversa.
    nome: 'M4 — o descartado volta a aparecer na family_safe',
    pega: 'passo "descartado fica fora da family_safe"',
    de: `  left join public.aulas_emusys ae on ae.id = v.aula_local_id
 where r.status <> 'descartado';

-- As DUAS views`,
    para: `  left join public.aulas_emusys ae on ae.id = v.aula_local_id;

-- As DUAS views`,
  },
  {
    // O mutante que justifica ter saido do teste-so-de-catalogo: view que nao
    // devolve nada passa em TODA asercao de coluna.
    nome: 'M5 — a comercial deixa de devolver linha (join quebrado)',
    pega: 'passo "comercial devolve o registro vigente"',
    de: `  join public.lead_experimentais le on le.id = v.lead_experimental_id
  left join public.aulas_emusys ae on ae.id = v.aula_local_id
 where r.status <> 'descartado';

create or replace view public.vw_experimental_registro_family_safe`,
    para: `  join public.lead_experimentais le on le.id = v.lead_experimental_id
  left join public.aulas_emusys ae on ae.id = v.aula_local_id
 where r.status <> 'descartado' and le.aluno_id is not null;

create or replace view public.vw_experimental_registro_family_safe`,
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
