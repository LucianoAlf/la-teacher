#!/usr/bin/env node
// Mutacoes do conserto "a ficha manual nao engole o audio". Roda num PostgreSQL
// Docker descartavel: aplica a migration + o bloco DML do teste, confere o
// baseline verde e exige que cada mutante (que reintroduz o bug) morra.

import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

const MIGRATION = 'supabase/migrations/20260814230000_o_rascunho_manual_nao_engole_o_audio.sql'
const TEST = 'supabase/migrations/20260814230000_o_rascunho_manual_nao_engole_o_audio.test.sql'
const IMAGE = process.env.MUTANTE_20260814230000_POSTGRES_IMAGE ?? 'postgres:17-alpine'
const fonte = readFileSync(MIGRATION, 'utf8')
const teste = readFileSync(TEST, 'utf8')
const testeDocker = extrairTesteDocker(teste)

// A tabela fabio_registros_aula aqui TEM modo_entrada (default 'audio', not null),
// espelhando producao — e o pivo do conserto. As funcoes sao stubs minimos.
const bootstrap = `
  create extension if not exists pgcrypto;
  create role anon;
  create role authenticated;
  create role service_role;
  create table public.aulas_emusys (
    id integer primary key,
    professor_id integer not null,
    unidade_id uuid not null,
    cancelada boolean not null default false,
    data_hora_inicio timestamptz not null default now() - interval '1 hour',
    data_hora_fim timestamptz,
    anotacoes_fabio text
  );
  create table public.aula_alunos_emusys (
    aula_emusys_id integer not null,
    aluno_id integer not null
  );
  create table public.alunos (
    id integer primary key,
    nome text not null
  );
  create table public.aula_registros_fabio_log (
    aula_id integer not null,
    criado_em timestamptz not null default now()
  );
  create table public.fabio_fila_audios (
    id uuid primary key default gen_random_uuid(),
    professor_id integer not null,
    aula_id integer not null,
    unidade_id uuid not null,
    storage_path text not null,
    duracao_segundos integer,
    origem text not null default 'app',
    status text not null,
    tentativas integer not null default 0,
    erro text,
    erro_tipo text,
    criado_em timestamptz not null default now(),
    atualizado_em timestamptz not null default now()
  );
  create table public.fabio_registros_aula (
    id uuid primary key default gen_random_uuid(),
    aula_id integer,
    unidade_id uuid,
    parent_id uuid,
    professor_id integer,
    aluno_id integer,
    molde text,
    campos jsonb not null default '{}'::jsonb,
    texto_consolidado text,
    confirmado_em timestamptz,
    status text,
    origem text,
    audio_id uuid,
    modo_entrada text not null default 'audio',
    criado_em timestamptz not null default now()
  );
  create function public.fn_aula_operacional_id(integer)
  returns integer language sql immutable as $$ select $1 $$;
  create function public.fn_aula_individual_do_aluno(integer, integer)
  returns integer language sql immutable as $$ select $1 $$;
  create function public.fn_janela_registro_dias()
  returns integer language sql immutable as $$ select 7 $$;
  create function public.fn_enfileirar_audio_core(
    integer, text, integer, uuid, text, integer
  ) returns jsonb language sql as $$ select '{}'::jsonb $$;
  revoke all on function public.fn_enfileirar_audio_core(integer, text, integer, uuid, text, integer)
    from public, anon, authenticated, service_role;
`

const mutantes = [
  {
    nome: 'M1 filtro de modo removido: a ficha manual volta a engolir o audio',
    ancora: "       and r.modo_entrada = 'audio'\n",
    substituicao: '       and true -- M1: filtro de modo_entrada removido\n',
  },
  {
    nome: 'M2 filtro invertido: audio para de retomar e manual passa a bloquear',
    ancora: "and r.modo_entrada = 'audio'",
    substituicao: "and r.modo_entrada <> 'audio'",
  },
  {
    nome: 'M3 rascunho de audio deixa de sinalizar que ja existe',
    ancora: "'rascunho_existente', true",
    substituicao: "'rascunho_existente', false",
  },
]

function extrairTesteDocker(sql) {
  const inicio = '/* 20260814230000-DOCKER-DML-TESTS-INICIO'
  const fim = '20260814230000-DOCKER-DML-TESTS-FIM */'
  const indiceInicio = sql.indexOf(inicio)
  const indiceFim = sql.indexOf(fim)
  if (indiceInicio < 0 || indiceFim < 0 || indiceFim <= indiceInicio) {
    throw new Error('bloco Docker de DML do teste 20260814230000 ausente ou malformado')
  }
  if (sql.indexOf(inicio, indiceInicio + inicio.length) >= 0 || sql.indexOf(fim, indiceFim + fim.length) >= 0) {
    throw new Error('bloco Docker de DML do teste 20260814230000 deve ser unico')
  }
  return sql.slice(indiceInicio + inicio.length, indiceFim).trim()
}

function executar(args, input) {
  return spawnSync('docker', args, {
    cwd: process.cwd(),
    encoding: 'utf8',
    input,
    maxBuffer: 2 * 1024 * 1024,
  })
}

function contar(texto, trecho) {
  return texto.split(trecho).length - 1
}

function mutar(mutante) {
  const ocorrencias = contar(fonte, mutante.ancora)
  if (ocorrencias !== 1) {
    throw new Error(`${mutante.nome}: ancora apareceu ${ocorrencias} vez(es)`)
  }
  return fonte.replace(mutante.ancora, mutante.substituicao)
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
  const sql = `begin;\n${migration}\n${teste}\n${testeDocker}\nrollback;`
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

const container = `la-teacher-20260814230000-mutantes-${process.pid}-${Date.now()}`
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
process.exitCode = !invalido && mortos === mutantes.length ? 0 : 1
