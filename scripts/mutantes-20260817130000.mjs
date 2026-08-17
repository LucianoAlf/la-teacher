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

const MIGRATION = 'supabase/migrations/20260817130000_consulta_letiva_presencas.sql'
const TEST = 'supabase/migrations/20260817130000_consulta_letiva_presencas.test.sql'
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
  teste, 'PRESENCAS-DOCKER-DML-TESTS-INICIO', 'PRESENCAS-DOCKER-DML-TESTS-FIM', 'bloco docker')

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
  proveniencia text
);
insert into public.vw_aluno_presenca_semantica_v1 values
  -- 3 presentes (2 deles em 11-12/08, para o recorte por periodo poder medir)
  (1,36,date '2026-08-11','Piano','registrada','presente',true,false,'agenda_secretaria'),
  (2,36,date '2026-08-12','Piano','registrada','presente',true,false,'la_teacher'),
  (3,36,date '2026-08-13','Piano','registrada','presente',true,false,'emusys'),
  -- 2 faltas CONFIRMADAS (afirmadas por gente)
  (4,36,date '2026-08-12','Piano','registrada_atestada','falta_confirmada',false,true,'agenda_secretaria'),
  (5,36,date '2026-08-13','Piano','registrada','falta_confirmada',false,true,'la_teacher'),
  -- 2 faltas PROVAVEIS (fantasma do Emusys — o banco se recusa a afirmar)
  (6,36,date '2026-08-13','Piano','registrada_inferida','falta_provavel',false,false,'emusys'),
  (7,36,date '2026-08-14','Piano','registrada_inferida','falta_provavel',false,false,'emusys'),
  -- 1 indeterminado
  (8,36,date '2026-08-14','Piano','indeterminada','indeterminado',false,false,'emusys'),
  -- 1 nao aplicavel
  (9,36,date '2026-08-15','Piano','nao_aplicavel','aula_justificada',false,false,'emusys'),
  -- outro professor, para provar isolamento
  (10,99,date '2026-08-12','Canto','registrada','presente',true,false,'agenda_secretaria');
`

const mutantes = [
  {
    // O DEFEITO QUE ACUSA ALUNO REAL: provavel entra em faltas (2 -> 4).
    nome: 'soma falta_provavel dentro de faltas (acusa aluno que o banco nao afirma)',
    ancora: `          from base where considera_falta`,
    substituicao: `          from base where considera_falta or situacao_chamada = 'registrada_inferida'`,
  },
  {
    // "Nao presente" vira falta: engole provavel, indeterminado e nao aplicavel.
    nome: 'faltas = tudo que nao esta presente (engole os outros tres baldes)',
    ancora: `        select coalesce(jsonb_agg(linha order by data_aula, linha->>'aluno'), '[]'::jsonb)
          from base where considera_falta
      ),
      'falta_provavel', (`,
    substituicao: `        select coalesce(jsonb_agg(linha order by data_aula, linha->>'aluno'), '[]'::jsonb)
          from base where not considera_presenca
      ),
      'falta_provavel', (`,
  },
  {
    // Classifica o provavel por PROCEDENCIA. Parece equivalente e nao e: com o
    // fixture, 'emusys' pega tambem o presente 3, o indeterminado 8 e o nao
    // aplicavel 9 -> 2 vira 5. Duas trocas de proposito: quem fizesse isso de
    // verdade traria a coluna no CTE junto — com uma troca so o mutante morreria
    // de ERRO ("column does not exist"), e morte por sintaxe nao prova nada.
    nome: 'classifica falta_provavel por proveniencia em vez de situacao_chamada',
    trocas: [
      {
        ancora: `             v.considera_falta,`,
        substituicao: `             v.considera_falta,\n             v.proveniencia,`,
      },
      {
        ancora: `          from base where situacao_chamada = 'registrada_inferida'`,
        substituicao: `          from base where proveniencia = 'emusys'`,
      },
    ],
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
    ancora: `             jsonb_build_object('aluno', al.nome, 'data', v.data_aula, 'curso', v.curso_nome) as linha,`,
    substituicao: `             jsonb_build_object('aluno', v.aluno_id::text, 'data', v.data_aula, 'curso', v.curso_nome) as linha,`,
  },
  {
    // A FRONTEIRA DO FINANCEIRO.
    nome: 'injeta coluna financeira no retorno (fronteira do financeiro)',
    ancora: `      'presentes', count(*) filter (where considera_presenca),`,
    substituicao: `      'presentes', count(*) filter (where considera_presenca),\n      'mensalidade_aluno', 350,`,
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

const container = `la-teacher-consulta-presencas-mutantes-${process.pid}-${Date.now()}`
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
