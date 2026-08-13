// Mutantes das guardas resgatadas da 093 e da 099.
//
// Cada mutante abre uma porta que tem que ficar fechada. Se algum sobreviver,
// a guarda resgatada e decorativa -- e ai teria sido melhor nem resgatar,
// porque guarda que nao morde da falsa seguranca.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/20260813170000_guardas_resgatadas_da_presenca.sql'
const TESTE = 'supabase/migrations/20260813170000_guardas_resgatadas_da_presenca.test.sql'
const TEMP = 'supabase/migrations/_mutante-guardas-resgatadas.sql'

const lf = (s) => s.replace(/\r\n/g, '\n')
const fonte = lf(readFileSync(ORIGINAL, 'utf8'))

const MUTANTES = [
  {
    nome: 'M1 — authenticated ganha a funcao interna de presenca',
    pega: 'passo "fn_materializar_presenca_padrao e interna: ninguem executa"',
    de: `revoke all on function public.fn_materializar_presenca_padrao(uuid, integer)
  from public, anon, authenticated, service_role;`,
    para: `revoke all on function public.fn_materializar_presenca_padrao(uuid, integer)
  from public, anon, service_role;
grant execute on function public.fn_materializar_presenca_padrao(uuid, integer) to authenticated;`,
  },
  {
    nome: 'M2 — service_role ganha a funcao interna de fatia',
    pega: 'passo "fn_remover_campos_comuns_da_fatia e interna: ninguem executa"',
    de: `revoke all on function public.fn_remover_campos_comuns_da_fatia(jsonb, jsonb)
  from public, anon, authenticated, service_role;`,
    para: `revoke all on function public.fn_remover_campos_comuns_da_fatia(jsonb, jsonb)
  from public, anon, authenticated;
grant execute on function public.fn_remover_campos_comuns_da_fatia(jsonb, jsonb) to service_role;`,
  },
  {
    nome: 'M3 — anon alcanca a confirmacao de registro',
    pega: 'passo "app_confirmar_registro e do professor logado, nao do anonimo"',
    de: 'revoke all on function public.app_confirmar_registro(uuid, text) from public, anon;',
    para: `revoke all on function public.app_confirmar_registro(uuid, text) from public;
grant execute on function public.app_confirmar_registro(uuid, text) to anon;`,
  },
  {
    // Nao adianta so APAGAR o grant: como a producao ja concede a
    // `authenticated`, o grant deste arquivo e reafirmacao idempotente e
    // remove-lo nao muda estado nenhum -- o mutante sobrevivia sem revelar
    // nada. Para testar o risco de verdade (apertar demais e trancar o
    // professor fora da confirmacao), o mutante precisa REVOGAR.
    nome: 'M4 — a guarda aperta demais e tranca o professor logado',
    pega: 'passo "app_confirmar_registro e do professor logado, nao do anonimo"',
    de: `revoke all on function public.app_confirmar_registro(uuid, text) from public, anon;
grant execute on function public.app_confirmar_registro(uuid, text) to authenticated;`,
    para: 'revoke all on function public.app_confirmar_registro(uuid, text) from public, anon, authenticated;',
  },
]

// Sem baseline verde, todo mutante morre de erro e o placar mente.
exigirBaselineVerde(ORIGINAL, TESTE)

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
  let morreu = false
  try {
    execFileSync('node', ['scripts/rodar-teste-sql.mjs', TEMP, TESTE], { stdio: 'pipe' })
  } catch {
    morreu = true
  }
  if (morreu) {
    mortos++
    console.log(`OK     morto: ${m.nome}  (${m.pega})`)
  } else {
    console.log(`FALHA  SOBREVIVEU: ${m.nome}  (${m.pega})`)
  }
}

try { unlinkSync(TEMP) } catch {}

console.log(`\n${mortos}/${MUTANTES.length} mutantes mortos${stale > 0 ? ` (${stale} ancora(s) stale)` : ''}`)
process.exitCode = mortos === MUTANTES.length ? 0 : 1
