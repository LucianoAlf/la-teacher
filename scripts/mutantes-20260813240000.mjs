// Mutantes da carteira fatiada.
//
// O defeito caro aqui é silencioso: um número plausível com gente faltando.
// M1 e M2 são os dois jeitos de errar que o Alf recusou explicitamente --
// somar tudo num número só, e sumir com quem só faz atividade extra.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/20260813240000_a_banda_vem_separada.sql'
const TESTE = 'supabase/migrations/20260813240000_a_banda_vem_separada.test.sql'
const TEMP = 'supabase/migrations/_mutante-banda-separada.sql'

const lf = (s) => s.replace(/\r\n/g, '\n')
const fonte = lf(readFileSync(ORIGINAL, 'utf8'))

const MUTANTES = [
  {
    nome: 'M1 — regulares volta a ser TODO mundo (a soma que o Alf recusou)',
    pega: 'passo "Ramon: 47 = 13 + 34" e a identidade da fatia',
    de: `    'regulares',          (select count(*) from classificada where tem_regular),`,
    para: `    'regulares',          (select count(*) from classificada),`,
  },
  {
    nome: 'M2 — quem so faz atividade extra some da conta',
    pega: 'passos da fatia do Ramon e da identidade em TODO professor',
    de: `    'so_atividade_extra', (select count(*) from classificada where tem_extra and not tem_regular),`,
    para: `    'so_atividade_extra', 0,`,
  },
  {
    // Sem o nome, "3 atividades extras" nao diz ao professor QUAL e qual --
    // que era exatamente o pedido do Alf.
    nome: 'M3 — a lista de atividades perde o nome do curso',
    pega: 'passo "as atividades extras vem NOMEADAS"',
    de: `jsonb_build_object('curso', curso, 'alunos', alunos)`,
    para: `jsonb_build_object('alunos', alunos)`,
  },
  {
    nome: 'M4 — curso desconhecido deixa de contar como regular',
    pega: 'identidade da fatia / conferencia contra is_projeto_banda',
    de: '           bool_or(not coalesce(cu.is_projeto_banda, false)) as tem_regular,',
    para: '           bool_or(not cu.is_projeto_banda) as tem_regular,',
  },
  {
    nome: 'M5 — o contexto do Fabio volta a levar so o total',
    pega: 'passo "o contexto do Fabio carrega a carteira fatiada"',
    de: `    'carteira', public.fn_carteira_fatiada(p_professor_id),`,
    para: '',
  },
  {
    nome: 'M6 — a RPC do agente volta a contar por conta propria',
    pega: 'passo "a RPC do agente deriva da regua unica"',
    de: `  select public.fn_carteira_fatiada(p_professor_id)
      || jsonb_build_object(`,
    para: `  select jsonb_build_object(
           'regulares', (select count(*) from public.vw_professor_carteira_pessoa_canonica_sombra c
                          where c.professor_id = p_professor_id),`,
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
