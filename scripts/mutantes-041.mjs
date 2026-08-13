// Mutantes do escalonamento pra coordenacao (039 + 040 + 041).
//
// Regra da casa: verde nao-falsificado e decoracao. Cada defesa da funcao tem
// aqui um mutante que a desliga; se o teste continuar verde, a defesa nao
// estava sendo medida.
//
// Ancora que nao bate e FALHA, nao aviso. Mutante cita SQL literal e apodrece
// em silencio quando a migration muda — um `AVISO` no meio do log vira "10/10"
// mentiroso na linha de baixo.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/041-escalonamento-usa-registro.sql'
const TESTE = 'supabase/migrations/041-escalonamento-usa-registro.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-041.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    // O erro real de 05/08: o Fabio disse ao Matheus, na frente da
    // coordenacao, que ele tinha 18 aulas atrasadas. Todas as 18 eram passivo.
    nome: 'M1 — o passivo volta a ser cobrado (sem o filtro cobravel)',
    pega: 'passo "passivo (antes do corte) NAO e cobrado"',
    de: '     where v.cobravel                              -- <<< nunca o passivo',
    para: '     where true                                    -- MUTANTE M1',
  },
  {
    // A regressao inteira da 040: cobrar presenca, que e CONSEQUENCIA do
    // lancamento. Reescrita coerente (colunas da outra view), pra nao morrer
    // de erro de SQL — mutante que morre por sintaxe nao prova nada.
    nome: 'M2 — a fonte volta a ser vw_presenca_pendencia',
    pega: 'passo "aula com conteudo lancado NAO e cobrada"',
    de:
      '    select v.professor_id, v.professor_nome, u.nome as unidade_nome,\n' +
      '           v.aula_ancora_id as aula_id, v.data_aula, v.data_hora_inicio,\n' +
      "           to_char(v.data_hora_inicio at time zone 'America/Sao_Paulo','HH24:MI') as hora,\n" +
      '           v.curso_nome, v.turma_nome, v.aluno_nome, v.dias_em_atraso\n' +
      '      from vw_registro_pendencia v\n' +
      '      left join unidades u on u.id = v.unidade_id\n' +
      '     where v.cobravel                              -- <<< nunca o passivo\n',
    para:
      '    select v.professor_id, v.professor_nome, v.unidade_nome,\n' +
      '           v.aula_id, v.data_aula, v.data_hora_inicio, v.hora,\n' +
      '           v.curso_nome, v.turma_nome, v.aluno_nome, v.dias_em_atraso\n' +
      '      from vw_presenca_pendencia v\n' +
      '     where true                                    -- MUTANTE M2\n',
  },
  {
    // Um dia a menos no limite e o Fabio escala quem ainda esta dentro dos
    // dois avisos (fim do dia + manha seguinte) e nao teve chance de arrumar.
    nome: 'M3 — o limite vira >= e escala quem esta no ultimo dia',
    pega: 'passo "aula com exatos 3 dias NAO e cobrada"',
    de: '       and v.dias_em_atraso > p_dias',
    para: '       and v.dias_em_atraso >= p_dias',
  },
  {
    // Estamos em piloto: so o Matheus sobe pro grupo. Sem esta guarda, o
    // primeiro disparo leva a escola inteira pra coordenacao de uma vez.
    nome: 'M4 — o escopo do piloto vaza (todo professor sobe pro grupo)',
    pega: 'passo "nenhum professor fora do escopo entra"',
    de: '       and (p_professor_id is null or v.professor_id = p_professor_id)',
    para: '       and (true or v.professor_id = p_professor_id)',
  },
  {
    // Quem recebe o encaminhamento precisa identificar o aluno; primeiro nome
    // repete demais numa escola, e o distinct ainda funde dois alunos num so.
    nome: 'M5 — volta pro primeiro nome do aluno',
    pega: 'passo "nome COMPLETO dos dois alunos da mesma aula"',
    de: '           jsonb_agg(distinct aluno_nome) as alunos',
    para: "           jsonb_agg(distinct split_part(btrim(aluno_nome),' ',1)) as alunos",
  },
  {
    // 26 dos 42 professores dao aula em mais de uma unidade. Um max() no
    // nivel do professor carimba a unidade errada em metade das aulas.
    nome: 'M6 — unidade volta a ser max() por professor, nao por aula',
    de: '    select *, row_number() over (',
    para:
      '    select *, max(unidade_nome) over (partition by professor_id) as unidade_prof,\n' +
      '           row_number() over (',
    pega: 'passo "unidade da aula de CG"',
    extra: {
      de: "                     'unidade',   unidade_nome,",
      para: "                     'unidade',   unidade_prof,",
    },
  },
  {
    nome: 'M7 — p_max_aulas para de cortar a lista',
    pega: 'passo "p_max_aulas=1 manda so uma aula"',
    de: '       where rn <= p_max_aulas',
    para: '       where rn <= 999999',
  },
  {
    // A funcao e security definer e le a escola inteira. Exposta ao
    // authenticated, qualquer professor logado consulta a pendencia dos
    // colegas de todas as unidades.
    nome: 'M8 — a funcao fica exposta ao authenticated',
    pega: 'passo "authenticated nao executa a funcao"',
    de: 'grant execute on function public.fn_pendencias_escalonadas(integer,integer,integer) to service_role;',
    para:
      'grant execute on function public.fn_pendencias_escalonadas(integer,integer,integer) to service_role;\n' +
      'grant execute on function public.fn_pendencias_escalonadas(integer,integer,integer) to authenticated;',
  },
]

let previstos = 0
let stale = 0

for (const m of MUTANTES) {
  const trocas = [{ de: m.de, para: m.para }, ...(m.extra ? [m.extra] : [])]
  let mutado = fonte
  let ancoraOk = true
  for (const t of trocas) {
    if (!mutado.includes(t.de)) {
      console.log(`STALE  ${m.nome} — ancora nao existe mais na migration`)
      console.log(`       procurava: ${JSON.stringify(t.de.slice(0, 90))}`)
      ancoraOk = false
      break
    }
    mutado = mutado.replace(t.de, t.para)
  }
  if (!ancoraOk) { stale++; continue }

  writeFileSync(TEMP, mutado)
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
