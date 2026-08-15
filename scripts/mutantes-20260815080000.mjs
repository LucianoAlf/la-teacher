#!/usr/bin/env node
// Mutacoes do conserto "o audio que morre em voo volta pra fila". Roda num
// PostgreSQL Docker descartavel: aplica a migration + o bloco DML do teste,
// confere o baseline verde e exige que cada mutante (que reintroduz o bug ou
// afrouxa uma garantia) morra.

import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

const MIGRATION = 'supabase/migrations/20260815080000_o_vinculo_da_experimental_casa_pelo_id_do_lead.sql'
const TEST = 'supabase/migrations/20260815080000_o_vinculo_da_experimental_casa_pelo_id_do_lead.test.sql'
const IMAGE = process.env.MUTANTE_20260815080000_POSTGRES_IMAGE ?? 'postgres:17-alpine'
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
  create table public.aulas_emusys (
    id integer primary key,
    professor_id integer not null,
    unidade_id uuid not null,
    categoria text not null default 'normal',
    cancelada boolean not null default false,
    data_hora_inicio timestamptz not null default now()
  );
  create table public.aula_alunos_emusys (
    aula_emusys_id integer not null,
    aluno_id integer,
    emusys_lead_id integer
  );
  create table public.lead_experimentais (
    id serial primary key,
    unidade_id uuid not null,
    data_experimental date not null,
    emusys_lead_id integer
  );
  create table public.lead_experimental_aulas (
    id bigserial primary key,
    lead_experimental_id integer not null,
    aula_local_id integer,
    estado text not null,
    casado_por text,
    motivo_pendencia text,
    criado_em timestamptz not null default now(),
    vinculado_em timestamptz,
    vinculado_por text,
    substituido_em timestamptz,
    cancelado_em timestamptz,
    constraint lead_experimental_aulas_casado_por_check
      check (casado_por is null or casado_por = any (array['chave_natural','manual']))
  );
  create unique index uq_lead_exp_aula_vigente on public.lead_experimental_aulas (lead_experimental_id) where (substituido_em is null);
  create unique index uq_lead_exp_aula_ocupada on public.lead_experimental_aulas (aula_local_id) where (aula_local_id is not null and substituido_em is null and estado <> 'cancelado');
`

const mutantes = [
  {
    // O CORACAO: sem a data, a remarcacao (mesmo lead, 2 datas) disputa a
    // mesma aula. Medido: 121 leads com mais de uma experimental, um com SEIS.
    nome: 'tira a DATA da chave (remarcacao pendura na tentativa errada)',
    ancora: "       and (ae.data_hora_inicio at time zone 'America/Sao_Paulo')::date\n           = v_lead.data_experimental;",
    substituicao: ';',
  },
  {
    nome: 'deixa de casar pelo id do lead (volta a nao achar nada)',
    ancora: 'and r.emusys_lead_id = v_lead.emusys_lead_id',
    substituicao: 'and r.emusys_lead_id is distinct from v_lead.emusys_lead_id',
  },
  {
    nome: 'escolhe no chute quando ha mais de um par',
    ancora: 'elsif v_qtd_par > 1 then',
    substituicao: 'elsif false then',
  },
  {
    nome: 'atropela vinculo que ja existe vigente',
    ancora: 'and not exists (\n         select 1 from public.lead_experimental_aulas v\n          where v.lead_experimental_id = le.id\n            and v.substituido_em is null\n       )',
    substituicao: 'and true',
  },
  {
    // 'chute' morreria pela CONSTRAINT (exit != 0), e mutante que morre de erro
    // nao conta -- o runner exige morte por ASSERCAO. 'chave_natural' passa no
    // CHECK e mente na procedencia: e o defeito real que queremos pegar.
    nome: 'mente na procedencia (carimba como chave_natural)',
    ancora: "'emusys_lead_id', now(), 'reconciliador_lead'",
    substituicao: "'chave_natural', now(), 'reconciliador_lead'",
  },
]

function extrairTesteDocker(texto) {
  const inicio = texto.indexOf('20260815080000-DOCKER-DML-TESTS-INICIO')
  const fim = texto.indexOf('20260815080000-DOCKER-DML-TESTS-FIM')
  if (inicio === -1 || fim === -1) {
    throw new Error('bloco DOCKER-DML-TESTS nao encontrado no teste')
  }
  return texto.slice(inicio + '20260815080000-DOCKER-DML-TESTS-INICIO'.length, fim)
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

const container = `la-teacher-20260815080000-mutantes-${process.pid}-${Date.now()}`
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
