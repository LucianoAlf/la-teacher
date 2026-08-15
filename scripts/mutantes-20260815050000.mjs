#!/usr/bin/env node
// Mutacoes do conserto "a limpeza nao apaga o que a fila ainda vai usar". Roda
// num PostgreSQL Docker descartavel: aplica a migration + o bloco DML do teste,
// confere o baseline verde e exige que cada mutante (que reintroduz o bug ou
// afrouxa uma garantia) morra.

import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

const MIGRATION = 'supabase/migrations/20260815050000_a_limpeza_nao_apaga_o_que_a_fila_ainda_vai_usar.sql'
const TEST = 'supabase/migrations/20260815050000_a_limpeza_nao_apaga_o_que_a_fila_ainda_vai_usar.test.sql'
const IMAGE = process.env.MUTANTE_20260815050000_POSTGRES_IMAGE ?? 'postgres:17-alpine'
const fonte = readFileSync(MIGRATION, 'utf8')
const teste = readFileSync(TEST, 'utf8')
const testeDocker = extrairTesteDocker(teste)

// As tres tabelas que fabio_provar_limpeza le. As colunas espelham producao no
// que a prova usa; o resto e ruido e fica de fora.
const bootstrap = `
  create extension if not exists pgcrypto;
  create table public.fabio_acoes_pendentes (
    id uuid primary key default gen_random_uuid(),
    professor_id integer not null,
    storage_path text,
    estado text not null
  );
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
  create table public.fabio_registros_aula (
    id uuid primary key default gen_random_uuid(),
    audio_id uuid,
    status text not null
  );
`

const mutantes = [
  {
    nome: 'volta a destruir o audio que a fila ainda vai usar (o caso do Valdo)',
    ancora: "and f.status not in ('normalizado', 'erro_terminal')",
    substituicao: "and f.status in ('jamais_existe')",
  },
  {
    nome: 'ignora o teto de tentativas e nunca mais limpa (vaza Storage)',
    ancora: 'and f.tentativas < 3',
    substituicao: 'and f.tentativas < 999',
  },
  {
    nome: 'ignora a janela de 3 dias e nunca mais limpa (vaza Storage)',
    ancora: "and f.criado_em > now() - interval '3 days'",
    substituicao: "and f.criado_em > now() - interval '3000 days'",
  },
  {
    // Muta a CONDICAO, nao o texto do motivo: renomear o motivo nao muda
    // comportamento nenhum, e um sufixo ainda casaria com o `like` do
    // contrato de catalogo — o mutante morreria de mentira.
    nome: 'perde a guarda da acao ativa',
    ancora: "and a.estado in ('aberta', 'processando', 'adiada')",
    substituicao: "and a.estado in ('jamais_existe')",
  },
  {
    nome: 'perde a guarda do registro confirmado',
    ancora: "and r.status in ('confirmado', 'gravado_emusys')",
    substituicao: "and r.status in ('jamais_existe')",
  },
]

function extrairTesteDocker(texto) {
  const inicio = texto.indexOf('20260815050000-DOCKER-DML-TESTS-INICIO')
  const fim = texto.indexOf('20260815050000-DOCKER-DML-TESTS-FIM')
  if (inicio === -1 || fim === -1) {
    throw new Error('bloco DOCKER-DML-TESTS nao encontrado no teste')
  }
  return texto.slice(inicio + '20260815050000-DOCKER-DML-TESTS-INICIO'.length, fim)
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

const container = `la-teacher-20260815050000-mutantes-${process.pid}-${Date.now()}`
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
