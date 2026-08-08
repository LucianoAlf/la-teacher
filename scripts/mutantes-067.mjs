// Mutantes da 067 — a fila para de repetir professor.
//
// V1 é o motivo desta migration existir: ele reintroduz o `group by` que a 065
// tinha. Aquele defeito passou por 10 passos verdes e 5 mutantes sem que nenhum
// piscasse, porque todos perguntavam sobre NÚMEROS e nenhum sobre a CHAVE.
// Somar certo por linha errada continua somando certo.
//
// Quem denunciou foi a tela, mostrando "38 professores afetados" em cima de uma
// fila de 60 linhas. Este arquivo existe pra que a próxima vez seja o teste.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/067-a-fila-para-de-repetir-professor.sql'
const TESTE = 'supabase/migrations/067-a-fila-para-de-repetir-professor.test.sql'
const TEMP = 'supabase/migrations/_mutante-067.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    // O defeito original, de volta. 27 dos 44 professores da casa dão aula em
    // mais de uma unidade — 38 pessoas viram 60 linhas.
    nome: 'V1 — volta a agrupar por (professor, unidade) [o defeito da 065]',
    pega: 'passo "a fila NAO repete professor"',
    de: `     group by professor_id`,
    para: `     group by professor_id, unidade_nome`,
  },
  {
    // A unidade some pro professor multi-unidade: a coordenação liga cobrando o
    // Recreio quando o buraco é em Campo Grande.
    nome: 'V2 — mostra so uma das unidades do professor',
    pega: 'passo "quem e multi-unidade traz as duas na lista"',
    de: `           (select string_agg(distinct u.unidade_nome, ', ' order by u.unidade_nome)
              from pend u where u.professor_id = p.professor_id) as unidades`,
    para: `           min(unidade_nome) as unidades`,
  },
  {
    nome: 'V3 — a fila volta a ser alfabetica',
    pega: 'passo "a fila desce por urgencia"',
    de: `               order by p.em_aberto desc, p.pior_atraso desc, p.professor_nome)`,
    para: `               order by p.professor_nome)`,
  },
  {
    nome: 'V4 — a RPC deixa de checar se quem chamou e coordenacao',
    pega: 'passo "sem identidade a RPC recusa"',
    de: `  if not public.fn_e_coordenacao_la_teacher() then
    raise exception 'apenas_admin';
  end if;`,
    para: `  -- guard removido pelo mutante`,
  },
  {
    nome: 'V5 — o filtro de unidade vira enfeite',
    pega: 'passo "filtrar por unidade devolve menos que o total"',
    de: `       and (p_unidade_id is null or unidade_id = p_unidade_id)`,
    para: `       and (p_unidade_id is null or true)`,
  },
  {
    nome: 'V6 — a janela passa a incluir HOJE (cobra a aula em andamento)',
    pega: 'passo "a aula de HOJE nao entra na cobranca"',
    de: `       and data_aula <  current_date`,
    para: `       and data_aula <= current_date`,
  },
  {
    // `create or replace` PRESERVA privilégios — o mutante tem que dar o grant
    // ATIVAMENTE, senão não mede nada.
    nome: 'V7 — a RPC fica aberta pro anon',
    pega: 'passo "anon NAO executa a RPC do painel"',
    de: `revoke all on function public.app_coordenacao_em_aberto(int, uuid) from anon;`,
    para: `grant execute on function public.app_coordenacao_em_aberto(int, uuid) to anon;`,
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
process.exitCode = mortos === MUTANTES.length ? 0 : 1
