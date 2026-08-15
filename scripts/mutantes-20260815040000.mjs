#!/usr/bin/env node
// Mutacoes do conserto "o audio que morre em voo volta pra fila". Roda num
// PostgreSQL Docker descartavel: aplica a migration + o bloco DML do teste,
// confere o baseline verde e exige que cada mutante (que reintroduz o bug ou
// afrouxa uma garantia) morra.

import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

const MIGRATION = 'supabase/migrations/20260815040000_o_audio_que_morre_em_voo_volta_pra_fila.sql'
const TEST = 'supabase/migrations/20260815040000_o_audio_que_morre_em_voo_volta_pra_fila.test.sql'
const IMAGE = process.env.MUTANTE_20260815040000_POSTGRES_IMAGE ?? 'postgres:17-alpine'
const fonte = readFileSync(MIGRATION, 'utf8')
const teste = readFileSync(TEST, 'utf8')
const testeDocker = extrairTesteDocker(teste)

// So a fila importa aqui: e a unica tabela que fn_fabio_retry_fila le. As
// colunas espelham producao, inclusive vinculo_id (a fronteira da experimental)
// e erro_tipo (o que separa transitorio de terminal).
const bootstrap = `
  create extension if not exists pgcrypto;
  create table public.fabio_fila_audios (
    id uuid primary key default gen_random_uuid(),
    professor_id integer not null,
    unidade_id uuid not null,
    aula_id integer not null,
    storage_path text not null,
    duracao_segundos integer not null default 0,
    status text not null,
    transcricao text,
    erro text,
    tentativas integer not null default 0,
    origem text not null default 'app',
    criado_em timestamptz not null default now(),
    atualizado_em timestamptz not null default now(),
    vinculo_id uuid,
    erro_tipo text not null default 'transitorio'
  );
  -- Stub: a versao real depende do vault. O teste Docker o sobrescreve por um
  -- que apenas REGISTRA quem foi disparado — e a selecao que esta sob teste.
  create or replace function public.fn_fabio_chama_edge(p_audio_id uuid)
  returns void language plpgsql as $stub$ begin return; end $stub$;
`

const mutantes = [
  {
    nome: 'volta a ignorar quem morreu em voo (o bug do Valdo)',
    ancora: "f.status in ('transcrevendo', 'transcrito')",
    substituicao: "f.status in ('nunca_existe_a', 'nunca_existe_b')",
  },
  {
    nome: 'reenfileira em voo sem janela de folga (atropela quem esta vivo)',
    ancora: "and f.atualizado_em < now() - interval '15 minutes'",
    substituicao: "and f.atualizado_em < now() + interval '15 minutes'",
  },
  {
    nome: 'perde a fronteira da experimental (rouba audio pro Hermes)',
    ancora: 'and f.vinculo_id is null',
    substituicao: 'and (f.vinculo_id is null or f.vinculo_id is not null)',
  },
  {
    // Os dois guards sao redundantes POR DESENHO: em producao
    // erro_tipo='semantico_terminal' sempre vem com status='erro_terminal'
    // (9/9 medido em 15/08). Mutar so um deixa o outro barrando a linha e o
    // mutante sobrevive sem que exista defeito — por isso o par cai junto.
    nome: 'deixa erro_terminal voltar pro retry (os dois guards juntos)',
    ancora: "and f.erro_tipo = 'transitorio'\n       and f.status <> 'erro_terminal'",
    substituicao: 'and true\n       and true',
  },
  {
    nome: 'derruba o teto de tentativas',
    ancora: 'and f.tentativas < 3',
    substituicao: 'and f.tentativas < 999',
  },
]

function extrairTesteDocker(texto) {
  const inicio = texto.indexOf('20260815040000-DOCKER-DML-TESTS-INICIO')
  const fim = texto.indexOf('20260815040000-DOCKER-DML-TESTS-FIM')
  if (inicio === -1 || fim === -1) {
    throw new Error('bloco DOCKER-DML-TESTS nao encontrado no teste')
  }
  return texto.slice(inicio + '20260815040000-DOCKER-DML-TESTS-INICIO'.length, fim)
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

const container = `la-teacher-20260815040000-mutantes-${process.pid}-${Date.now()}`
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
