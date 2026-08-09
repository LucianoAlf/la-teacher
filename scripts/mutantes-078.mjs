// Mutantes da 078 — o Fábio lê o semáforo.
//
// V1 é o estado de ANTES: a chave some e ele volta a negar o que não vê.
// V2 é o mais importante: derruba o escopo por professor. Se ele sobreviver,
// significa que o teste aceitaria o Fábio contando pro professor o que o
// COLEGA escreveu — a fronteira de 09/08 caindo em silêncio.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/078-o-fabio-le-o-semaforo.sql'
const TESTE = 'supabase/migrations/078-o-fabio-le-o-semaforo.test.sql'
const TEMP = 'supabase/migrations/_mutante-078.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'V1 — o semaforo some do prontuario (estado de antes da 078)',
    pega: 'passo "o semaforo do proprio professor chega (resolvido por pessoa)"',
    de: `      || jsonb_build_object('semaforo',     coalesce(v_semaforo, '[]'::jsonb));`,
    para: `      || jsonb_build_object('semaforo',     '[]'::jsonb);`,
  },
  {
    nome: 'V2 — o escopo por professor cai (o Fabio conta o recado do colega)',
    pega: 'passo "o semaforo do colega NAO chega"',
    de: `             where f.aluno_id = any (v_ids)
               and f.professor_id = p_professor_id`,
    para: `             where f.aluno_id = any (v_ids)`,
  },
  {
    nome: 'V3 — volta a procurar pela matricula, nao pela pessoa',
    pega: 'passo "o semaforo do proprio professor chega (resolvido por pessoa)"',
    de: `             where f.aluno_id = any (v_ids)
               and f.professor_id = p_professor_id`,
    para: `             where f.aluno_id = p_aluno_id
               and f.professor_id = p_professor_id`,
  },
  {
    nome: 'V4 — so o coracao viaja, as tres perguntas ficam pra tras',
    pega: 'passo "as tres perguntas vem junto do coracao"',
    de: `             'pratica_em_casa', s.pratica_em_casa,`,
    para: `             'pratica_em_casa', null,`,
  },
  {
    nome: 'V5 — a chave nem existe quando nao ha resposta (o Fabio nao sabe que existe semaforo)',
    pega: 'passo "sem resposta, semaforo vem vazio (e existe a chave)"',
    de: `      || jsonb_build_object('semaforo',     coalesce(v_semaforo, '[]'::jsonb));`,
    para: `      || case when v_semaforo is null then '{}'::jsonb
              else jsonb_build_object('semaforo', v_semaforo) end;`,
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
