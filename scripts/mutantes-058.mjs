// Mutantes da 058 — a fila do painel é por urgência.
//
// V1 é o defeito que eu tinha e que nenhum teste pegou: a lista alfabética. Ela
// não parece errada — os nomes estão todos lá, os campos certos, a guarda
// funcionando. Só que quem abre a tela hoje decide por ela quem entra primeiro,
// e alfabético faz liberar por acaso.
//
// Por isso as fixtures têm nome ao contrário da urgência: quem tem MAIS
// experimental tem nome mais no fim do alfabeto. Sem essa inversão o passo
// passaria com as duas ordenações.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/058-a-fila-do-painel-e-por-urgencia.sql'
const TESTE = 'supabase/migrations/058-a-fila-do-painel-e-por-urgencia.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-058.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'V1 — a fila volta a ser alfabética (o defeito da 057)',
    pega: 'passo "quem tem mais experimental vem primeiro"',
    de: 'order by ja_tem, exp_7d desc, nome',
    para: 'order by ja_tem, nome',
  },
  {
    // Inverter a urgência: quem não tem nada marcado sobe. Pior que alfabético,
    // porque parece intencional.
    nome: 'V2 — a urgência ordena ao contrário',
    pega: 'passo "quem tem mais experimental vem primeiro"',
    de: 'order by ja_tem, exp_7d desc, nome',
    para: 'order by ja_tem, exp_7d asc, nome',
  },
  {
    // Quem já entra misturado na fila de quem falta liberar: o admin lê a lista
    // como "faltam todos".
    nome: 'V3 — quem já tem acesso deixa de ir pro fim',
    pega: 'passo "quem ja tem acesso vai pro fim"',
    de: 'order by ja_tem, exp_7d desc, nome',
    para: 'order by exp_7d desc, nome',
  },
  {
    // A contagem no card vindo errada: o admin prioriza por um número falso.
    nome: 'V4 — a contagem da semana ignora a janela de 7 dias',
    pega: 'passo "e a contagem de cada um confere"',
    de: `            'experimentais_7d', (
              select count(*) from public.lead_experimentais le
               where le.professor_experimental_id = p.id
                 and le.status = 'experimental_agendada'
                 and le.data_experimental between (now() at time zone 'America/Sao_Paulo')::date
                                              and (now() at time zone 'America/Sao_Paulo')::date + 7)`,
    para: `            'experimentais_7d', 0`,
  },
  {
    nome: 'V5 — a reescrita derruba a guarda de admin',
    pega: 'passo "professor comum continua sem ver o painel"',
    de: `  if v_perfil is distinct from 'admin' then
    raise exception 'apenas_admin' using errcode = '42501';
  end if;`,
    para: '',
  },
  {
    nome: 'V6 — a reescrita perde a marca de quem tem WhatsApp',
    pega: 'passo "e o painel continua marcando quem tem whatsapp"',
    de: `            'tem_whatsapp',  (nullif(btrim(coalesce(p.telefone_whatsapp, '')), '') is not null),`,
    para: `            'tem_whatsapp',  false,`,
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
