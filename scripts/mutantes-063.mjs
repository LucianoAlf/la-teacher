// Mutantes da 063 — a tranca nas duas tabelas do ciclo.
//
// Este é o caso em que o mutante trivial (V1/V2: não ligar a RLS) importa
// menos que o V5. Ligar RLS numa tabela lida por RPC `security definer` só
// funciona porque o dono da função é o dono da tabela. V5 quebra essa
// premissa de propósito — troca o definer por invoker — e o ciclo inteiro da
// experimental morre CALADO: a ficha some, o prontuário não grava, e nada
// levanta erro que alguém veja. É exatamente o modo de falha que faria a
// migration parecer boa em produção até um professor tentar registrar.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/063-a-tranca-nas-duas-tabelas-do-ciclo.sql'
const TESTE = 'supabase/migrations/063-a-tranca-nas-duas-tabelas-do-ciclo.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-063.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'V1 — a tabela do vinculo continua sem RLS (o estado do achado)',
    pega: 'passo "RLS ligada na tabela do vinculo"',
    de: 'alter table public.lead_experimental_aulas     enable row level security;',
    para: 'alter table public.lead_experimental_aulas     disable row level security;',
  },
  {
    nome: 'V2 — a tabela do prontuario continua sem RLS',
    pega: 'passo "RLS ligada na tabela do registro"',
    de: 'alter table public.lead_experimental_registros enable row level security;',
    para: 'alter table public.lead_experimental_registros disable row level security;',
  },
  {
    // O deslize que a 063 existe pra tornar inofensivo — só que aqui ele vem
    // junto com a RLS ligada, e uma policy permissiva anula a tranca.
    nome: 'V3 — uma policy "pra nao quebrar nada" abre a tabela inteira',
    pega: 'passos "nenhuma policy abre excecao" e "ler a tabela direto continua bloqueado"',
    de: 'revoke all on table public.lead_experimental_registros from public, anon, authenticated;',
    para: `grant select on table public.lead_experimental_registros to authenticated;
create policy zzmutante_tudo on public.lead_experimental_registros for select to authenticated using (true);`,
  },
  {
    // Grant sem policy: RLS ligada segura, mas o privilégio declarado some do
    // arquivo. O passo mede a intenção, não só o efeito de hoje.
    nome: 'V4 — o grant volta pro authenticated (RLS segura, mas a intencao some)',
    pega: 'passo "anon e authenticated sem privilegio"',
    de: 'revoke all on table public.lead_experimental_aulas     from public, anon, authenticated;',
    para: 'grant select on table public.lead_experimental_aulas to authenticated;',
  },
  {
    // O MODO DE FALHA SILENCIOSO: a RPC deixa de ser definer. Com RLS ligada,
    // ela passa a ler como o professor — que não tem privilégio nenhum.
    nome: 'V5 — a RPC da ficha vira security invoker (o ciclo morre calado)',
    pega: 'passos "o professor continua abrindo a ficha" e "nenhuma RPC quebrou"',
    de: `comment on table public.lead_experimental_aulas is`,
    para: `alter function public.app_experimental_do_professor(bigint) security invoker;
comment on table public.lead_experimental_aulas is`,
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
