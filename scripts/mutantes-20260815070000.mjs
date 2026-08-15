#!/usr/bin/env node
// Mutacoes do conserto "o audio que morre em voo volta pra fila". Roda num
// PostgreSQL Docker descartavel: aplica a migration + o bloco DML do teste,
// confere o baseline verde e exige que cada mutante (que reintroduz o bug ou
// afrouxa uma garantia) morra.

import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

const MIGRATION = 'supabase/migrations/20260815070000_a_experimental_sem_aluno_nao_entra_pela_porta_do_aluno.sql'
const TEST = 'supabase/migrations/20260815070000_a_experimental_sem_aluno_nao_entra_pela_porta_do_aluno.test.sql'
const IMAGE = process.env.MUTANTE_20260815070000_POSTGRES_IMAGE ?? 'postgres:17-alpine'
const fonte = readFileSync(MIGRATION, 'utf8')
const teste = readFileSync(TEST, 'utf8')
const testeDocker = extrairTesteDocker(teste)

// O bootstrap espelha producao no que a guarda usa: `categoria` na aula
// (o discriminador da experimental) e `aluno_id` NULAVEL em aula_alunos_emusys
// (o lead que ainda nao e aluno — o pivo do conserto).
const bootstrap = `
  create extension if not exists pgcrypto;
  create table public.unidades (id uuid primary key, nome text);
  create table public.professores (id integer primary key, nome text);
  create table public.alunos (id integer primary key, nome text not null);
  create table public.aulas_emusys (
    id integer primary key,
    professor_id integer not null,
    unidade_id uuid not null,
    categoria text not null default 'normal',
    cancelada boolean not null default false,
    data_hora_inicio timestamptz not null default now() - interval '1 hour',
    data_hora_fim timestamptz,
    anotacoes_fabio text
  );
  create table public.aula_alunos_emusys (
    aula_emusys_id integer not null,
    aluno_id integer            -- NULAVEL de proposito: lead nao tem aluno_id
  );
  create table public.aula_registros_fabio_log (
    aula_id integer not null,
    criado_em timestamptz not null default now()
  );
  create table public.fabio_fila_audios (
    id uuid primary key default gen_random_uuid(),
    professor_id integer not null,
    unidade_id uuid not null,
    aula_id integer not null,
    storage_path text not null,
    duracao_segundos integer,
    status text not null,
    erro text,
    tentativas integer not null default 0,
    origem text not null default 'app',
    criado_em timestamptz not null default now(),
    atualizado_em timestamptz not null default now(),
    vinculo_id bigint,
    erro_tipo text not null default 'transitorio'
  );
  create table public.fabio_registros_aula (
    id uuid primary key default gen_random_uuid(),
    professor_id integer,
    aula_id integer,
    parent_id uuid,
    audio_id uuid,
    campos jsonb not null default '{}'::jsonb,
    modo_entrada text not null default 'audio',
    status text not null,
    criado_em timestamptz not null default now()
  );
  create or replace function public.fn_aula_operacional_id(p integer)
  returns integer language sql immutable as $s$ select p $s$;
  create or replace function public.fn_aula_individual_do_aluno(p integer, a integer)
  returns integer language sql immutable as $s$ select p $s$;
  create or replace function public.fn_janela_registro_dias()
  returns integer language sql immutable as $s$ select 7 $s$;
`

const mutantes = [
  {
    nome: 'remove a guarda: experimental com lead volta a entrar e morrer calada',
    ancora: "if v_aula.categoria = 'experimental'",
    substituicao: "if false and v_aula.categoria = 'experimental'",
  },
  {
    // A perna do roster e o que evita falso positivo. Sem ela a guarda vira
    // "toda experimental", e a experimental cujo lead JA virou aluno — que
    // hoje funciona em producao — passaria a ser recusada.
    nome: 'guarda por categoria sozinha (quebra a experimental que funciona)',
    ancora: "and not exists (\n       select 1\n         from public.aula_alunos_emusys r\n        where r.aula_emusys_id = p_aula_id\n          and r.aluno_id is not null\n     )",
    substituicao: '',
  },
  {
    // Espelha o inverso: se a perna do roster deixar de exigir aluno_id NAO
    // nulo, a linha do lead conta como aluno e a guarda nunca dispara.
    nome: 'aceita o lead como se fosse aluno (aluno_id nulo conta)',
    ancora: 'and r.aluno_id is not null',
    substituicao: 'and r.aluno_id is null',
  },
  {
    nome: 'a guarda vira aviso e o audio entra assim mesmo',
    ancora: "raise exception 'aula_experimental_usa_porta_propria';",
    substituicao: "raise notice 'aula_experimental_usa_porta_propria';",
  },
  {
    nome: 'perde a trilha manual separada (regressao do conserto de 14/08)',
    ancora: "and r.modo_entrada = 'audio'",
    substituicao: "and r.modo_entrada in ('audio', 'manual')",
  },
]

function extrairTesteDocker(texto) {
  const inicio = texto.indexOf('20260815070000-DOCKER-DML-TESTS-INICIO')
  const fim = texto.indexOf('20260815070000-DOCKER-DML-TESTS-FIM')
  if (inicio === -1 || fim === -1) {
    throw new Error('bloco DOCKER-DML-TESTS nao encontrado no teste')
  }
  return texto.slice(inicio + '20260815070000-DOCKER-DML-TESTS-INICIO'.length, fim)
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

const container = `la-teacher-20260815070000-mutantes-${process.pid}-${Date.now()}`
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
