// Mutantes da 071 — o painel filtra por unidade e por curso.
//
// V1 é o motivo desta migration existir: filtrar pelo NOME cru do curso em vez
// da chave agrupada. Com "Bateria" (46 aulas), "Bateria T" (82) e "Bateria IND"
// (1) sendo modalidades do mesmo curso, esse filtro responderia 46 de 129 — com
// confiança, sem erro nenhum na tela.
//
// V10 é o outro estrago silencioso: deixar a assinatura de 2 argumentos viva ao
// lado da nova. Não degrada o painel, PARA ele — o PostgREST recusa a chamada
// ambígua com "could not choose the best candidate function".

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/071-o-painel-filtra-por-unidade-e-curso.sql'
const TESTE = 'supabase/migrations/071-o-painel-filtra-por-unidade-e-curso.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-071.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'V1 — a fila filtra pelo NOME cru do curso, nao pela chave',
    pega: 'passos "AGRUPA as modalidades" + "MAIOR que a maior variante"',
    de: `       and (p_curso is null or curso_chave = p_curso)`,
    para: `       and (p_curso is null or curso_nome = p_curso)`,
  },
  {
    nome: 'V2 — a chave para de tirar a modalidade (" T" / " IND")',
    pega: 'passo "a chave junta as tres modalidades"',
    de: `  select nullif(lower(regexp_replace(btrim(p_nome), '\\s+(t|ind)$', '', 'i')), '')`,
    para: `  select nullif(lower(btrim(p_nome)), '')`,
  },
  {
    nome: 'V3 — a chave volta a distinguir caixa',
    pega: 'passo "a chave ignora a caixa"',
    de: `  select nullif(lower(regexp_replace(btrim(p_nome), '\\s+(t|ind)$', '', 'i')), '')`,
    para: `  select nullif(regexp_replace(btrim(p_nome), '\\s+(t|ind)$', '', 'i'), '')`,
  },
  {
    // Agrupa demais: "Teclado" e "Teoria Musical" cairiam juntos se a chave
    // virasse só a primeira letra/prefixo.
    nome: 'V4 — a chave agrupa DEMAIS (corta a ultima palavra sempre)',
    pega: 'passo "a chave NAO junta cursos diferentes"',
    de: `  select nullif(lower(regexp_replace(btrim(p_nome), '\\s+(t|ind)$', '', 'i')), '')`,
    para: `  select nullif(lower(regexp_replace(btrim(p_nome), '\\s+\\S+$', '', 'i')), '')`,
  },
  {
    nome: 'V5 — a faceta de unidade respeita o proprio filtro (as opcoes somem)',
    pega: 'passo "filtrar unidade NAO apaga as outras unidades da lista"',
    de: `    select unidade_id, min(unidade_nome) as unidade_nome,
           count(distinct aula_id)::int as aulas
      from janela
     where (p_curso is null or curso_chave = p_curso)
       and unidade_id is not null`,
    para: `    select unidade_id, min(unidade_nome) as unidade_nome,
           count(distinct aula_id)::int as aulas
      from janela
     where (p_curso is null or curso_chave = p_curso)
       and (p_unidade_id is null or unidade_id = p_unidade_id)
       and unidade_id is not null`,
  },
  {
    nome: 'V6 — a faceta de curso respeita o proprio filtro (as opcoes somem)',
    pega: 'passo "filtrar curso NAO apaga os outros cursos da lista"',
    de: `      from janela
     where (p_unidade_id is null or unidade_id = p_unidade_id)
       and curso_chave is not null
     group by curso_chave`,
    para: `      from janela
     where (p_unidade_id is null or unidade_id = p_unidade_id)
       and (p_curso is null or curso_chave = p_curso)
       and curso_chave is not null
     group by curso_chave`,
  },
  {
    // Oferece curso que não existe naquela unidade: a coordenação clica e vê
    // zero, sem explicação.
    nome: 'V7 — a faceta de curso ignora o filtro de unidade',
    pega: 'passo "a lista de cursos da unidade so tem curso que existe la"',
    de: `      from janela
     where (p_unidade_id is null or unidade_id = p_unidade_id)
       and curso_chave is not null`,
    para: `      from janela
     where curso_chave is not null`,
  },
  {
    nome: 'V8 — o filtro de unidade vira enfeite',
    pega: 'passo "filtrar por unidade bate com a janela"',
    de: `     where (p_unidade_id is null or unidade_id = p_unidade_id)
       and (p_curso is null or curso_chave = p_curso)
  ),
  por_professor as (`,
    para: `     where (p_unidade_id is null or true)
       and (p_curso is null or curso_chave = p_curso)
  ),
  por_professor as (`,
  },
  {
    nome: 'V9 — o rotulo da opcao mantem a modalidade ("Bateria T")',
    pega: 'passo "o rotulo do curso NAO mostra a modalidade"',
    de: `           min(regexp_replace(btrim(curso_nome), '\\s+(t|ind)$', '', 'i')) as curso_nome,`,
    para: `           min(curso_nome) as curso_nome,`,
  },
  {
    // ⚠️ Estes dois já foram "apaga o `drop`". Pararam de falsear no momento em
    // que a 071 foi aplicada em produção: sem a assinatura de 2 argumentos no
    // banco, não há o que o `drop` deixe de apagar. O RISCO, porém, continua —
    // ele só mudou de direção. Hoje o jeito de estragar é CRIAR uma segunda
    // sobrecarga (um `create or replace` distraído com outra aridade), e com
    // duas candidatas o PostgREST recusa toda chamada com "could not choose the
    // best candidate function": o painel não degrada, para.
    nome: 'V10 — nasce uma SEGUNDA fila de 2 argumentos (PostgREST fica ambiguo)',
    pega: 'passos "so existe UMA fila publicada" + "a fila publicada e a de 3 parametros"',
    de: `drop function if exists public.app_coordenacao_em_aberto(int, uuid);`,
    para: `drop function if exists public.app_coordenacao_em_aberto(int, uuid);
create or replace function public.app_coordenacao_em_aberto(
  p_dias int default 7, p_unidade_id uuid default null
) returns jsonb language sql stable as $mut$ select '{}'::jsonb $mut$;`,
  },
  {
    nome: 'V11 — nasce um SEGUNDO detalhe de 2 argumentos',
    pega: 'passos "so existe UM detalhe publicado" + "o detalhe publicado e o de 4 parametros"',
    de: `drop function if exists public.app_coordenacao_professor_detalhe(int, int);`,
    para: `drop function if exists public.app_coordenacao_professor_detalhe(int, int);
create or replace function public.app_coordenacao_professor_detalhe(
  p_professor_id int, p_dias int default 7
) returns jsonb language sql stable as $mut$ select '{}'::jsonb $mut$;`,
  },
  {
    // O selo da linha diz "12 aulas" e o expandir lista 35.
    nome: 'V12 — o DETALHE ignora o filtro de curso',
    pega: 'passo "o detalhe FILTRADO bate com a linha filtrada"',
    de: `       and (p_curso is null or public.fn_curso_chave(curso_nome) = p_curso)`,
    para: `       and (p_curso is null or true)`,
  },
  {
    nome: 'V13 — a fila deixa de checar se quem chamou e coordenacao',
    pega: 'passo "sem identidade a fila recusa"',
    de: `  if not public.fn_e_coordenacao_la_teacher() then
    raise exception 'apenas_admin';
  end if;

  with janela as (`,
    para: `  with janela as (`,
  },
  {
    nome: 'V14 — o DETALHE deixa de checar se quem chamou e coordenacao',
    pega: 'passo "sem identidade o detalhe recusa"',
    de: `  if not public.fn_e_coordenacao_la_teacher() then
    raise exception 'apenas_admin';
  end if;

  with pend as (`,
    para: `  with pend as (`,
  },
  {
    nome: 'V15 — a fila volta a agrupar por (professor, unidade)',
    pega: 'passo "a fila NAO repete professor"',
    de: `      from pend p
     group by professor_id
  ),`,
    para: `      from pend p
     group by professor_id, unidade_nome
  ),`,
  },
  {
    nome: 'V16 — a fila volta a contar par aluno-aula',
    pega: 'passo "sem filtro, o total e o da janela inteira"',
    de: `      'sem_lancamento',     (select count(distinct aula_id) from pend),`,
    para: `      'sem_lancamento',     (select count(*) from pend),`,
  },
  {
    nome: 'V17 — a fila volta a ser alfabetica',
    pega: 'passo "a fila desce por urgencia"',
    de: `               order by p.aulas desc, p.pior_atraso desc, p.professor_nome)`,
    para: `               order by p.professor_nome)`,
  },
  {
    nome: 'V18 — a janela passa a incluir HOJE',
    pega: 'passo "a aula de HOJE nao entra na cobranca"',
    de: `     where data_aula >= current_date - p_dias
       and data_aula <  current_date
  ),
  pend as (`,
    para: `     where data_aula >= current_date - p_dias
       and data_aula <= current_date
  ),
  pend as (`,
  },
  {
    nome: 'V19 — a linha perde a foto do professor',
    pega: 'passo "a linha traz a foto de quem tem"',
    de: `                 'foto_url',       pr.foto_url,`,
    para: `                 'foto_url',       null,`,
  },
  {
    // `create ... function` novo NÃO herda grant, mas o revoke explícito é o
    // que garante — o mutante precisa dar o grant ATIVAMENTE.
    nome: 'V20 — a fila fica aberta pro anon',
    pega: 'passo "anon NAO executa a fila"',
    de: `revoke all on function public.app_coordenacao_em_aberto(int, uuid, text) from anon;`,
    para: `grant execute on function public.app_coordenacao_em_aberto(int, uuid, text) to anon;`,
  },
  {
    nome: 'V21 — o detalhe fica aberto pro anon',
    pega: 'passo "anon NAO executa o detalhe"',
    de: `revoke all on function public.app_coordenacao_professor_detalhe(int, int, uuid, text) from anon;`,
    para: `grant execute on function public.app_coordenacao_professor_detalhe(int, int, uuid, text) to anon;`,
  },
  {
    nome: 'V22 — o detalhe deixa de ser executavel pelo app',
    pega: 'passo "authenticated executa o detalhe"',
    de: `grant execute on function public.app_coordenacao_professor_detalhe(int, int, uuid, text) to authenticated;`,
    para: `revoke execute on function public.app_coordenacao_professor_detalhe(int, int, uuid, text) from authenticated;`,
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
