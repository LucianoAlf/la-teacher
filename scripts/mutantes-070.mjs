// Mutantes da 070 — o painel conta AULA, não par aluno-aula.
//
// V1 é o motivo desta migration existir: ele devolve o `count(*)` da 067. Esse
// defeito atravessou a 065 e a 067 inteiras — 10 + 12 passos, 5 + 7 mutantes —
// porque todo passo comparava o número da RPC com o mesmo `count(*)` da view.
// Um teste que confere a conta contra ela mesma nunca discorda dela.
//
// Quem discordou foi o Alf, olhando a tela: "em aberto 50, alunos 49, o quê?".
// O par de passos "conta AULAS" + "NAO e mais o total de linhas" existe pra que
// da próxima vez seja o teste.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/070-o-painel-conta-aula-nao-par-aluno-aula.sql'
const TESTE = 'supabase/migrations/070-o-painel-conta-aula-nao-par-aluno-aula.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-070.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    // O defeito de origem, de volta.
    nome: 'V1 — o resumo volta a contar par aluno-aula [o defeito da 067]',
    pega: 'passos "o resumo conta AULAS" + "NAO e mais o total de linhas"',
    de: `      'sem_lancamento',     (select count(distinct aula_id) from pend),`,
    para: `      'sem_lancamento',     (select count(*) from pend),`,
  },
  {
    // A linha e o topo passam a contar coisas diferentes: a coluna deixa de
    // somar o número grande, e é assim que a coordenação para de confiar.
    nome: 'V2 — a LINHA volta a contar par, o topo continua contando aula',
    pega: 'passo "somar as AULAS das linhas devolve o total do resumo"',
    de: `           count(distinct aula_id)::int   as aulas,`,
    para: `           count(*)::int                  as aulas,`,
  },
  {
    nome: 'V3 — "so de ontem" volta a contar par',
    pega: 'passo "so de ontem tambem conta aula"',
    de: `      'ontem',              (select count(distinct aula_id) from pend
                              where data_aula = current_date - 1),`,
    para: `      'ontem',              (select count(*) from pend
                              where data_aula = current_date - 1),`,
  },
  {
    nome: 'V4 — a linha perde a foto do professor',
    pega: 'passo "a linha traz a foto de quem tem"',
    de: `                 'foto_url',       pr.foto_url,`,
    para: `                 'foto_url',       null,`,
  },
  {
    nome: 'V5 — a linha perde os cursos',
    pega: 'passo "a linha traz os cursos do professor"',
    de: `                 'cursos',         p.cursos,`,
    para: `                 'cursos',         null,`,
  },
  {
    // O join com professores é o que traz a foto. Se ele virar `left join` e a
    // tabela tiver buraco, a linha some da fila em silêncio — por isso o passo
    // "a fila tem 1 linha por professor" e a soma cobrem este caso.
    nome: 'V6 — a fila volta a ser alfabetica',
    pega: 'passo "a fila desce por urgencia"',
    de: `               order by p.aulas desc, p.pior_atraso desc, p.professor_nome)`,
    para: `               order by p.professor_nome)`,
  },
  {
    nome: 'V7 — a fila volta a agrupar por (professor, unidade) [o defeito da 065]',
    pega: 'passo "a fila NAO repete professor"',
    de: `     group by professor_id`,
    para: `     group by professor_id, unidade_nome`,
  },
  {
    nome: 'V8 — a janela da fila passa a incluir HOJE',
    pega: 'passo "a aula de HOJE nao entra na cobranca"',
    de: `       and data_aula <  current_date
       and (p_unidade_id is null or unidade_id = p_unidade_id)`,
    para: `       and data_aula <= current_date
       and (p_unidade_id is null or unidade_id = p_unidade_id)`,
  },
  {
    nome: 'V9 — a fila deixa de checar se quem chamou e coordenacao',
    pega: 'passo "sem identidade a fila recusa"',
    de: `  if not public.fn_e_coordenacao_la_teacher() then
    raise exception 'apenas_admin';
  end if;

  with pend as (
    select professor_id, professor_nome, unidade_nome, curso_nome,`,
    para: `  with pend as (
    select professor_id, professor_nome, unidade_nome, curso_nome,`,
  },
  {
    nome: 'V10 — o DETALHE deixa de checar se quem chamou e coordenacao',
    pega: 'passo "sem identidade o detalhe recusa"',
    de: `  if not public.fn_e_coordenacao_la_teacher() then
    raise exception 'apenas_admin';
  end if;

  with pend as (
    select aula_id, data_aula, hora, curso_nome, turma_nome, unidade_nome,`,
    para: `  with pend as (
    select aula_id, data_aula, hora, curso_nome, turma_nome, unidade_nome,`,
  },
  {
    // Sem o filtro de professor, o detalhe traz a escola inteira — e a
    // coordenação cobra um professor pelas aulas de outro.
    nome: 'V11 — o detalhe ignora de qual professor e',
    pega: 'passo "o detalhe bate com a linha da fila"',
    de: `     where professor_id = p_professor_id`,
    para: `     where (professor_id = p_professor_id or true)`,
  },
  {
    nome: 'V12 — o detalhe conta par aluno-aula em vez de aula',
    pega: 'passos "o detalhe bate com a linha" + "somar os itens"',
    de: `      from por_aula
     group by data_aula`,
    para: `      from pend
     group by data_aula`,
  },
  {
    // Ordem invertida = a fila diz "urgência" e o detalhe começa pelo mais
    // recente. O painel de equipe já foi ao ar uma vez com esse tipo de mentira.
    nome: 'V13 — o detalhe comeca pelo dia mais NOVO',
    pega: 'passo "os dias sobem do mais ANTIGO para o mais novo"',
    de: `             order by data_aula)          -- mais antigo primeiro = mais urgente`,
    para: `             order by data_aula desc)`,
  },
  {
    nome: 'V14 — o detalhe inclui a aula de HOJE',
    pega: 'passo "a aula de HOJE nao entra no detalhe"',
    de: `       and data_aula <  current_date
  ),
  por_aula as (`,
    para: `       and data_aula <= current_date
  ),
  por_aula as (`,
  },
  {
    // Turma de 5 vira "Beatriz" — a coordenação liga achando que é aula
    // individual.
    nome: 'V15 — a aula de turma lista so um aluno',
    pega: 'passo "aula de turma lista mais de um nome"',
    de: `           string_agg(distinct aluno_primeiro_nome, ', '
                      order by aluno_primeiro_nome) as alunos_nomes`,
    para: `           min(aluno_primeiro_nome) as alunos_nomes`,
  },
  {
    // `create or replace` PRESERVA privilégios — o mutante tem que dar o grant
    // ATIVAMENTE, senão não mede nada.
    nome: 'V16 — a fila fica aberta pro anon',
    pega: 'passo "anon NAO executa a fila"',
    de: `revoke all on function public.app_coordenacao_em_aberto(int, uuid) from anon;`,
    para: `grant execute on function public.app_coordenacao_em_aberto(int, uuid) to anon;`,
  },
  {
    nome: 'V17 — o detalhe fica aberto pro anon',
    pega: 'passo "anon NAO executa o detalhe"',
    de: `revoke all on function public.app_coordenacao_professor_detalhe(int, int) from anon;`,
    para: `grant execute on function public.app_coordenacao_professor_detalhe(int, int) to anon;`,
  },
  {
    nome: 'V18 — o detalhe deixa de ser executavel pelo app',
    pega: 'passo "authenticated executa o detalhe"',
    de: `grant execute on function public.app_coordenacao_professor_detalhe(int, int) to authenticated;`,
    para: `revoke execute on function public.app_coordenacao_professor_detalhe(int, int) from authenticated;`,
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
