// Mutantes da régua do veredito.
//
// Duas famílias: "muda a resposta" (M1-M4) e "passa a custar" (M5). A segunda
// existe porque a promessa que eu fiz ao Alf foi de CUSTO ZERO — e promessa
// sem carrasco é decoração. M5 troca a função por plpgsql: continua dando a
// mesma resposta, e tem que morrer mesmo assim.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/20260813270000_a_regua_do_veredito_vira_funcao.sql'
const TESTE = 'supabase/migrations/20260813270000_a_regua_do_veredito_vira_funcao.test.sql'
const TEMP = 'supabase/migrations/_mutante-regua-veredito.sql'

const lf = (s) => s.replace(/\r\n/g, '\n')
const fonte = lf(readFileSync(ORIGINAL, 'utf8'))

const MUTANTES = [
  {
    nome: 'M1 — Emusys presente deixa de contar (volta aos 44,4%)',
    pega: 'passo "EMUSYS PRESENTE conta" + equivalencia com o predicado vivo',
    de: `      or (
        p_respondido_por = 'emusys'
        and public.fn_presenca_status_efetivo(p_status_presenca, p_status) = 'presente'
      )`,
    para: '',
  },
  {
    nome: 'M2 — Emusys AUSENTE passa a valer como falta',
    pega: 'passos "EMUSYS AUSENTE nao vale" e "falta explicita" + equivalencia',
    de: `        and public.fn_presenca_status_efetivo(p_status_presenca, p_status) = 'presente'`,
    para: '',
  },
  {
    nome: 'M3 — o fallback da coluna antiga some (10 linhas de agosto caem)',
    pega: 'passo do fallback + equivalencia com o predicado vivo',
    de: `  select coalesce(
    p_status_presenca,
    case p_status
      when 'presente' then 'presente'
      when 'ausente'  then 'falta'
      else null
    end
  )`,
    para: '  select p_status_presenca',
  },
  {
    nome: 'M4 — exige veredito TAMBEM da fonte humana que diz falta',
    pega: 'passo "equipe marcando FALTA conta" + equivalencia',
    de: `      in ('presente', 'falta', 'falta_justificada')`,
    para: `      in ('presente')`,
  },
  {
    // Mesma resposta, custo diferente: plpgsql NAO e inlinado. Sem o passo do
    // plano, este mutante passaria verde -- e a promessa de custo zero seria
    // exatamente o tipo de garantia nao medida que esta casa ja pagou caro.
    nome: 'M5 — vira plpgsql: responde igual, mas para de ser inlinada',
    pega: 'passo "a funcao e INLINADA pelo planejador"',
    de: `returns boolean
language sql
immutable
parallel safe
as $function$
  select coalesce(`,
    para: `returns boolean
language plpgsql
immutable
parallel safe
as $function$
begin
  return coalesce(`,
  },
]

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
  writeFileSync(TEMP, fonte.replace(m.de, () => m.para))
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
