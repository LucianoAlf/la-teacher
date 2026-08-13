// Mutantes da 089 — a foto do aluno no Radar.
//
// A foto é um campo pequeno e por isso perigoso: quando ela falha, a tela não
// quebra — ela fica com cara de "esses alunos não têm foto". Os cinco mutantes
// desfazem exatamente os cinco jeitos de a foto sumir em silêncio: não trazer
// (V1), não entregar (V2), entregar `''` no lugar de nulo (V3), levar a 088
// embora na reaplicação (V4) e vazar a fronteira das médias (V5).
//
// Se um mutante sobreviver, quem está errado é o TESTE que não pegou, nunca o
// mutante — o passo que falta se adiciona lá, não se afrouxa aqui.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/089-a-foto-do-aluno-no-radar.sql'
const TESTE = 'supabase/migrations/089-a-foto-do-aluno-no-radar.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-089.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    // O defeito real que isto representa é ler `alunos.photo_url` — a coluna
    // gêmea que existe e está ZERADA. Mutar pra `photo_url` daria erro de
    // coluna inexistente (a view-fonte não tem essa), e mutante que morre de
    // erro de sintaxe não prova nada sobre o teste. `null::text` produz o
    // MESMO observável da coluna errada: coorte inteira sem foto.
    nome: 'V1 — a view para de trazer a foto (mesmo observavel de ler a coluna zerada)',
    pega: 'passos de cobertura ("a coorte tem foto de verdade" e "a lista traz foto em pelo menos uma linha")',
    de: `       s.foto_url                          as aluno_foto_url`,
    para: `       null::text                          as aluno_foto_url`,
  },
  {
    nome: 'V2 — a RPC deixa de mandar a chave foto na linha',
    pega: 'passo "toda linha da RPC tem a chave foto"',
    de: `        'aluno_id', aluno_id, 'aluno', aluno_nome, 'foto', aluno_foto_url,`,
    para: `        'aluno_id', aluno_id, 'aluno', aluno_nome,`,
  },
  {
    nome: 'V3 — aluno sem foto vira string vazia (Avatar tenta <img src=""> em vez das iniciais)',
    pega: 'passo "aluno sem foto vem nulo, nunca string vazia"',
    de: `       s.foto_url                          as aluno_foto_url\n  from public.vw_aluno_sucesso_lista s`,
    para: `       coalesce(s.foto_url, '')            as aluno_foto_url\n  from public.vw_aluno_sucesso_lista s`,
  },
  {
    nome: 'V4 — a reaplicacao da RPC come faltas_consecutivas (campo da 088)',
    pega: 'passo "faltas_consecutivas (088) sobreviveu a reaplicacao"',
    de: `        'faltas_janela', faltas_janela, 'faltas_consecutivas', faltas_consecutivas,`,
    para: `        'faltas_janela', faltas_janela,`,
  },
  {
    nome: 'V5 — a foto vaza pra medias.professores (fronteira da §2.1)',
    pega: 'passo "a foto nao aparece em medias nem em filtros"',
    de: `                       select professor_id, professor_nome,\n                              jsonb_build_object('professor_id', professor_id, 'professor', professor_nome,\n                                                'absenteismo_media', round(avg(absenteismo_pct),1)) as j`,
    para: `                       select professor_id, professor_nome,\n                              jsonb_build_object('professor_id', professor_id, 'professor', professor_nome,\n                                                'foto', max(aluno_foto_url),\n                                                'absenteismo_media', round(avg(absenteismo_pct),1)) as j`,
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
