#!/usr/bin/env node
// Mutacoes da RPC "presencas do professor no periodo" (consulta letiva, Fase 1).
//
// O que esta em jogo aqui e ALUNO REAL: se os baldes se somarem, o Fabio acusa
// de falta quem o banco se recusa a afirmar que faltou (o fantasma do "ausente"
// do Emusys). Por isso o fixture tem os cinco baldes com tamanhos DIFERENTES —
// se dois tivessem o mesmo tamanho, o mutante que soma um no outro passaria por
// morto.
//
// O ensaio Docker usa o PREAMBULO do .test.sql + o bloco DOCKER-DML: as
// asercoes remotas dependem do dado de producao (Rodrigo, Valdo) e nao valem
// aqui.

import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

const MIGRATION = 'supabase/migrations/20260817140000_consulta_letiva_presencas_dedup.sql'
const TEST = 'supabase/migrations/20260817140000_consulta_letiva_presencas_dedup.test.sql'
const IMAGE = process.env.MUTANTE_CONSULTA_POSTGRES_IMAGE ?? 'postgres:17-alpine'
const fonte = readFileSync(MIGRATION, 'utf8')
const teste = readFileSync(TEST, 'utf8')

function extrairEntre(texto, inicio, fim, rotulo) {
  const a = texto.indexOf(inicio)
  const b = texto.indexOf(fim)
  if (a === -1 || b === -1) throw new Error(`${rotulo} nao encontrado no teste`)
  return texto.slice(a + inicio.length, b)
}

const preambulo = extrairEntre(teste, 'PREAMBULO-INICIO', 'PREAMBULO-FIM', 'preambulo')
const testeDocker = extrairEntre(
  teste, 'PRESENCAS-DEDUP-DOCKER-DML-TESTS-INICIO', 'PRESENCAS-DEDUP-DOCKER-DML-TESTS-FIM', 'bloco docker')

// A view semantica e complexa; aqui ela vira TABELA com as colunas que a RPC le.
// Os cinco baldes com tamanhos diferentes: 3 presentes, 2 faltas, 2 provaveis,
// 1 indeterminado, 1 nao aplicavel. `proveniencia` existe de proposito: e ela
// que o mutante 3 tenta usar no lugar de situacao_chamada.
const bootstrap = `
do $roles$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if;
end
$roles$;

create table public.alunos (id integer primary key, nome text);
insert into public.alunos values
  (1,'Ana'),(2,'Bruno'),(3,'Carla'),(4,'Diego'),(5,'Elis'),
  (6,'Fabricio'),(7,'Gil'),(8,'Hugo'),(9,'Iara'),(10,'Joana');

create table public.vw_aluno_presenca_semantica_v1 (
  aluno_id integer,
  professor_id integer,
  data_aula date,
  curso_nome text,
  situacao_chamada text,
  resultado_pedagogico text,
  considera_presenca boolean,
  considera_falta boolean,
  proveniencia text,
  aula_emusys_id integer
);
-- Colapsa a aula gemea: id par aponta pro impar anterior (mesma regra do runner
-- de aulas). E o que transforma duas linhas da MESMA aula numa so.
create or replace function public.fn_aula_operacional_id(p_aula_id integer)
returns integer language sql stable as $f$
  select case when p_aula_id % 2 = 0 then p_aula_id - 1 else p_aula_id end
$f$;

insert into public.vw_aluno_presenca_semantica_v1 values
  -- 3 presentes distintos... e uma AULA GEMEA do aluno 1 (aula 102 -> op 101).
  -- Sem essa linha o fixture nao alcanca o defeito que apareceu conversando com
  -- o Fabio (Gabriel e Lavynea repetidos), e o mutante do dedup passaria por morto.
  (1,36,date '2026-08-11','Piano','registrada','presente',true,false,'agenda_secretaria',101),
  (1,36,date '2026-08-11','Piano','registrada','presente',true,false,'emusys',102),
  (2,36,date '2026-08-12','Piano','registrada','presente',true,false,'la_teacher',103),
  (3,36,date '2026-08-13','Piano','registrada','presente',true,false,'emusys',105),
  -- 2 faltas CONFIRMADAS (afirmadas por gente)
  (4,36,date '2026-08-12','Piano','registrada_atestada','falta_confirmada',false,true,'agenda_secretaria',107),
  (4,36,date '2026-08-12','Piano','registrada_atestada','falta_confirmada',false,true,'emusys',108),
  (5,36,date '2026-08-13','Piano','registrada','falta_confirmada',false,true,'la_teacher',109),
  -- 2 faltas PROVAVEIS (fantasma do Emusys)
  (6,36,date '2026-08-13','Piano','registrada_inferida','falta_provavel',false,false,'emusys',111),
  (7,36,date '2026-08-14','Piano','registrada_inferida','falta_provavel',false,false,'emusys',113),
  -- 1 indeterminado / 1 nao aplicavel
  (8,36,date '2026-08-14','Piano','indeterminada','indeterminado',false,false,'emusys',115),
  (9,36,date '2026-08-15','Piano','nao_aplicavel','aula_justificada',false,false,'emusys',117),
  -- outro professor, para provar isolamento
  (10,99,date '2026-08-12','Canto','registrada','presente',true,false,'agenda_secretaria',119);
`

const mutantes = [
  {
    // O DEFEITO QUE ACUSA ALUNO REAL: provavel entra em faltas (2 -> 4).
    nome: 'soma falta_provavel dentro de faltas (acusa aluno que o banco nao afirma)',
    ancora: `                  from base where considera_falta`,
    substituicao: `                  from base where considera_falta or situacao_chamada = 'registrada_inferida'`,
  },
  {
    // "Nao presente" vira falta: engole provavel, indeterminado e nao aplicavel.
    nome: 'faltas = tudo que nao esta presente (engole os outros tres baldes)',
    ancora: `                  from base where considera_falta
                 order by aluno_id, aula_op, aula_emusys_id) q
      ),
      'falta_provavel', (`,
    substituicao: `                  from base where not considera_presenca
                 order by aluno_id, aula_op, aula_emusys_id) q
      ),
      'falta_provavel', (`,
  },
  {
    // A guarda contra classificar por PROCEDENCIA e a asercao de catalogo: o
    // corpo da funcao nao pode mencionar 'proveniencia'. Este mutante faz
    // exatamente o primeiro passo de quem cometeria o erro — trazer a coluna
    // pra query — e morre ali, compilando normalmente. (Tentar tambem trocar o
    // balde faria o mutante morrer de ERRO, e morte por sintaxe nao prova nada.)
    nome: 'traz proveniencia pra dentro da query (porta pra classificar por procedencia)',
    ancora: `             v.considera_falta,`,
    substituicao: `             v.considera_falta,
             v.proveniencia,`,
  },
  {
    nome: 'remove o filtro por professor (vaza presenca de outro)',
    ancora: `       where v.professor_id = p_professor_id\n`,
    substituicao: `       where (v.professor_id = p_professor_id or true)\n`,
  },
  {
    nome: 'ignora o periodo pedido',
    ancora: `         and v.data_aula between p_inicio and p_fim`,
    substituicao: `         and true`,
  },
  {
    // Expoe id de aluno no lugar do nome (contrato do retorno).
    nome: 'devolve id do aluno em vez do nome',
    ancora: `             jsonb_build_object('aluno', al.nome, 'data', b.data_aula, 'curso', b.curso_nome) as linha,`,
    substituicao: `             jsonb_build_object('aluno', b.aluno_id::text, 'data', b.data_aula, 'curso', b.curso_nome) as linha,`,
  },
  {
    // O DEFEITO QUE O FABIO ME MOSTROU: sem o dedup, a aula gemea conta o mesmo
    // aluno duas vezes (presentes 3 -> 4) e o professor ouve o nome repetido.
    nome: 'remove o dedup por (aluno, aula operacional) (aula gemea conta em dobro)',
    ancora: `      'presentes', count(distinct (aluno_id, aula_op)) filter (where considera_presenca),`,
    substituicao: `      'presentes', count(*) filter (where considera_presenca),`,
  },
  {
    // Mesmo defeito, no balde de faltas: sem o distinct o aluno 4 (aula gemea
    // 107/108) aparece DUAS vezes na lista — foi assim que apareceu na conversa
    // com o Fabio (Gabriel e Lavynea repetidos).
    nome: 'remove o dedup do balde de faltas (aluno repetido na lista)',
    ancora: `          from (select distinct on (aluno_id, aula_op) aluno_id, aula_op, data_aula, linha
                  from base where considera_falta`,
    substituicao: `          from (select aluno_id, aula_op, data_aula, linha
                  from base where considera_falta`,
  },
  {
    // A FRONTEIRA DO FINANCEIRO.
    nome: 'injeta coluna financeira no retorno (fronteira do financeiro)',
    ancora: `      'ok', true,`,
    substituicao: `      'ok', true,\n      'mensalidade_aluno', 350,`,
  },
]

function executar(args, input) {
  return spawnSync('docker', args, {
    cwd: process.cwd(),
    encoding: 'utf8',
    input,
    maxBuffer: 4 * 1024 * 1024,
  })
}

function contar(texto, trecho) {
  return texto.split(trecho).length - 1
}

function mutar(mutante) {
  // Um mutante pode precisar de mais de uma troca para continuar COMPILANDO.
  // Morte por erro de sintaxe nao prova nada: o mutante tem que rodar e ser
  // pego pela asercao.
  const trocas = mutante.trocas ?? [{ ancora: mutante.ancora, substituicao: mutante.substituicao }]
  let mutado = fonte
  for (const troca of trocas) {
    const ocorrencias = contar(mutado, troca.ancora)
    if (ocorrencias !== 1) {
      throw new Error(`${mutante.nome}: ancora apareceu ${ocorrencias} vez(es)`)
    }
    mutado = mutado.replace(troca.ancora, troca.substituicao)
  }
  return mutado
}

function esperarPronto(container) {
  for (let tentativa = 0; tentativa < 40; tentativa += 1) {
    const pronto = executar([
      'exec', container, 'pg_isready', '-h', '127.0.0.1', '-p', '5432', '-U', 'postgres', '-d', 'postgres',
    ])
    if (pronto.status === 0) return
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 250)
  }
  throw new Error('PostgreSQL descartavel nao ficou pronto por TCP')
}

function executarEnsaio(container, migration) {
  const sql = `begin;\n${migration}\n${preambulo}\n${testeDocker}\nrollback;`
  const resultado = executar([
    'exec', '-i', container,
    'psql', '-h', '127.0.0.1', '-p', '5432', '-X', '-v', 'ON_ERROR_STOP=1', '-qAt', '-U', 'postgres', '-d', 'postgres',
  ], sql)
  const saida = `${resultado.stdout ?? ''}${resultado.stderr ?? ''}`.trim()
  const linhaResumo = saida.split(/\r?\n/u).reverse().find((linha) => linha.includes('"falhas"'))
  let resumo = null
  try {
    resumo = linhaResumo ? JSON.parse(linhaResumo) : null
  } catch {
    resumo = null
  }
  return { codigo: resultado.status, erro: resultado.error?.message ?? null, resumo, saida }
}

function mostrarFalha(nome, resultado) {
  console.log(`FALHA  ${nome}`)
  if (resultado.erro) console.log(`       executor: ${resultado.erro}`)
  if (resultado.saida) console.log(resultado.saida)
}

const container = `la-teacher-consulta-presencas-dedup-mutantes-${process.pid}-${Date.now()}`
let iniciado = false
let mortos = 0
let invalido = false

try {
  const inicio = executar([
    'run', '--rm', '--detach', '--name', container,
    '--env', 'POSTGRES_HOST_AUTH_METHOD=trust', IMAGE,
  ])
  if (inicio.status !== 0) {
    throw new Error(inicio.error?.message ?? inicio.stderr ?? 'docker run falhou')
  }
  iniciado = true
  esperarPronto(container)

  const pronto = executar([
    'exec', '-i', container,
    'psql', '-h', '127.0.0.1', '-p', '5432', '-X', '-v', 'ON_ERROR_STOP=1', '-qAt', '-U', 'postgres', '-d', 'postgres',
  ], bootstrap)
  if (pronto.status !== 0) {
    throw new Error(pronto.error?.message ?? pronto.stderr ?? 'bootstrap local falhou')
  }

  const baseline = executarEnsaio(container, fonte)
  if (baseline.codigo !== 0 || baseline.resumo?.falhas !== 0) {
    mostrarFalha('baseline deveria estar verde', baseline)
    invalido = true
  } else {
    console.log('OK     baseline verde')
  }

  if (!invalido) {
    for (const mutante of mutantes) {
      let resultado
      try {
        resultado = executarEnsaio(container, mutar(mutante))
      } catch (erro) {
        console.log(`FALHA  ${mutante.nome}: ${erro.message}`)
        invalido = true
        continue
      }
      if (resultado.codigo === 0 && resultado.resumo?.falhas > 0) {
        mortos += 1
        console.log(`OK     morto: ${mutante.nome}`)
      } else {
        mostrarFalha(`sobreviveu ou ensaio invalido: ${mutante.nome}`, resultado)
        invalido = true
      }
    }
  }
} catch (erro) {
  console.log(`FALHA  ambiente local: ${erro.message}`)
  invalido = true
} finally {
  if (iniciado) executar(['rm', '--force', container])
}

console.log(`\n${mortos}/${mutantes.length} mutantes mortos`)
process.exit(invalido || mortos !== mutantes.length ? 1 : 0)
