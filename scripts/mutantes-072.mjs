// Mutantes da 072 — a pendência aprende o Emusys.
//
// V1 é o motivo da migration: voltar a tratar tudo como "em aberto". O caso
// que falseia é o Isaque (25 de 29 aulas com anotação no Emusys): com o
// mutante vivo, a fila volta a mandar cobrar quem fez o trabalho.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/072-a-pendencia-aprende-o-emusys.sql'
const TESTE = 'supabase/migrations/072-a-pendencia-aprende-o-emusys.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-072.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    // Tudo volta a ser "sem nada": a transição deixa de existir.
    nome: 'V1 — a anotacao do Emusys deixa de contar [o defeito original]',
    pega: 'passos "no_emusys conta quem tem ANOTACAO" + "sem_nada conta..."',
    de: `           -- Anotação digitada no Emusys = trabalho feito lá. Presença do sync
           -- NÃO entra aqui de propósito — ver o cabeçalho.
           (nullif(btrim(ae.anotacoes), '') is not null) as no_emusys`,
    para: `           false as no_emusys`,
  },
  {
    // O outro extremo: o campo sempre-preenchido do sync (744/744) no lugar da
    // anotação — TUDO viraria "no Emusys" e ninguém seria cobrado nunca.
    nome: 'V2 — professor_presenca (default do sync) no lugar da anotacao',
    pega: 'passo "sem_nada conta quem NAO tem nada"',
    de: `           (nullif(btrim(ae.anotacoes), '') is not null) as no_emusys
      from public.vw_presenca_pendencia v
      join public.aulas_emusys ae on ae.id = v.aula_id
     where v.data_aula >= current_date - p_dias`,
    para: `           (nullif(btrim(ae.professor_presenca), '') is not null) as no_emusys
      from public.vw_presenca_pendencia v
      join public.aulas_emusys ae on ae.id = v.aula_id
     where v.data_aula >= current_date - p_dias`,
  },
  {
    nome: 'V3 — a fila volta a ordenar pelo TOTAL (o Isaque sobe de novo)',
    pega: 'passo "a fila desce por sem_nada" (com a ancora de divergencia)',
    de: `               order by p.sem_nada desc, p.pior_atraso desc nulls last,
                        p.professor_nome)`,
    para: `               order by p.aulas desc, p.pior_atraso desc nulls last,
                        p.professor_nome)`,
  },
  {
    nome: 'V4 — o atraso volta a contar aula que esta no Emusys',
    pega: 'passo "o atraso da linha e o da aula mais antiga SEM NADA"',
    de: `           max(dias_em_atraso) filter (where not no_emusys)::int      as pior_atraso,`,
    para: `           max(dias_em_atraso)::int                                   as pior_atraso,`,
  },
  {
    nome: 'V5 — "so de ontem" volta a misturar a pendencia de migracao',
    pega: 'passo "so de ontem conta so o cobravel"',
    de: `      'ontem',      (select count(distinct aula_id) from pend
                      where data_aula = current_date - 1 and not no_emusys),`,
    para: `      'ontem',      (select count(distinct aula_id) from pend
                      where data_aula = current_date - 1),`,
  },
  {
    nome: 'V6 — o DETALHE para de marcar as aulas do Emusys',
    pega: 'passos "o detalhe marca..." + "a marca bate com a linha"',
    de: `           (nullif(btrim(ae.anotacoes), '') is not null) as no_emusys
      from public.vw_presenca_pendencia v
      join public.aulas_emusys ae on ae.id = v.aula_id
     where v.professor_id = p_professor_id`,
    para: `           false as no_emusys
      from public.vw_presenca_pendencia v
      join public.aulas_emusys ae on ae.id = v.aula_id
     where v.professor_id = p_professor_id`,
  },
  {
    nome: 'V7 — a fila deixa de checar quem chamou',
    pega: 'passo "sem identidade a fila recusa"',
    de: `  if not public.fn_e_coordenacao_la_teacher() then
    raise exception 'apenas_admin';
  end if;

  with janela as (`,
    para: `  with janela as (`,
  },
  {
    nome: 'V8 — o detalhe deixa de checar quem chamou',
    pega: 'passo "sem identidade o detalhe recusa"',
    de: `  if not public.fn_e_coordenacao_la_teacher() then
    raise exception 'apenas_admin';
  end if;

  with pend as (`,
    para: `  with pend as (`,
  },
  {
    nome: 'V9 — a fila fica aberta pro anon',
    pega: 'passo "anon NAO executa a fila"',
    de: `revoke all on function public.app_coordenacao_em_aberto(int, uuid, text) from anon;`,
    para: `grant execute on function public.app_coordenacao_em_aberto(int, uuid, text) to anon;`,
  },
  {
    nome: 'V10 — o detalhe fica aberto pro anon',
    pega: 'passo "anon NAO executa o detalhe"',
    de: `revoke all on function public.app_coordenacao_professor_detalhe(int, int, uuid, text) from anon;`,
    para: `grant execute on function public.app_coordenacao_professor_detalhe(int, int, uuid, text) to anon;`,
  },
]

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
  let passou = true
  try {
    execFileSync('node', ['scripts/rodar-teste-sql.mjs', TEMP, TESTE], { stdio: 'pipe' })
  } catch {
    passou = false
  }
  if (!passou) {
    mortos++
    console.log(`OK     morto: ${m.nome}  (${m.pega})`)
  } else {
    console.log(`FALHA  SOBREVIVEU: ${m.nome}  (${m.pega})`)
  }
}

try { unlinkSync(TEMP) } catch {}
console.log(`\n${mortos}/${MUTANTES.length} mutantes mortos` + (stale ? `  —  ${stale} ANCORA(S) PODRE(S)` : ''))
process.exitCode = mortos === MUTANTES.length && stale === 0 ? 0 : 1
