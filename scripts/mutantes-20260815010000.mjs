#!/usr/bin/env node
// Mutacoes do conserto "o professor corrige a propria chamada". Roda num
// PostgreSQL Docker descartavel: aplica a migration + o bloco DML do teste,
// confere o baseline verde e exige que cada mutante (que reintroduz o bug de
// precedencia) morra.

import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

const MIGRATION = 'supabase/migrations/20260815010000_o_professor_corrige_a_propria_chamada.sql'
const TEST = 'supabase/migrations/20260815010000_o_professor_corrige_a_propria_chamada.test.sql'
const IMAGE = process.env.MUTANTE_20260815010000_POSTGRES_IMAGE ?? 'postgres:17-alpine'
const fonte = readFileSync(MIGRATION, 'utf8')
const teste = readFileSync(TEST, 'utf8')
const testeDocker = extrairTesteDocker(teste)

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
    data_aula date not null default current_date,
    curso_nome varchar,
    turma_nome varchar,
    sala_nome varchar,
    tipo varchar not null default 'turma'
  );
  create table public.aula_alunos_emusys (
    aula_emusys_id integer not null,
    aluno_id integer not null
  );
  create table public.aluno_presenca (
    id uuid primary key default gen_random_uuid(),
    aluno_id integer not null,
    aula_emusys_id integer not null,
    professor_id integer,
    unidade_id uuid,
    data_aula date,
    horario_aula time,
    status varchar,
    respondido_por varchar,
    respondido_em timestamptz,
    created_at timestamptz not null default now(),
    curso_nome varchar,
    turma_nome varchar,
    sala_nome varchar,
    status_presenca text,
    emusys_presenca_bruta text,
    espelhado_de_presenca_id uuid,
    unique (aluno_id, aula_emusys_id)
  );
  create function public.fn_professor_do_usuario()
  returns integer language sql stable as $$ select 836 $$;
  create function public.fn_janela_registro_dias()
  returns integer language sql immutable as $$ select 7 $$;
  create function public.fn_sincronizar_gemeos_presenca(integer)
  returns integer language sql stable as $$ select 0 $$;
  create function public.fn_presenca_e_forte(text)
  returns boolean language sql immutable as $$
    select coalesce($1 in (
      'professor_la_teacher','fabio_audio','manual','professor_whatsapp','agenda_secretaria'
    ), false)
  $$;
`

const mutantes = [
  {
    nome: 'M1 core volta ao booleano forte/fraca (reintroduz o bug do Valdo)',
    ancora: [
      '    on conflict (aluno_id, aula_emusys_id) do update',
      '      set status = excluded.status, status_presenca = excluded.status_presenca,',
      '          respondido_por = excluded.respondido_por, respondido_em = excluded.respondido_em',
      '      where public.fn_presenca_precedencia(excluded.respondido_por)',
      '            >= public.fn_presenca_precedencia(aluno_presenca.respondido_por)',
    ].join('\n'),
    substituicao: [
      '    on conflict (aluno_id, aula_emusys_id) do update',
      '      set status = excluded.status, status_presenca = excluded.status_presenca,',
      '          respondido_por = excluded.respondido_por, respondido_em = excluded.respondido_em',
      '      where not public.fn_presenca_e_forte(aluno_presenca.respondido_por)',
    ].join('\n'),
  },
  {
    nome: 'M2 app do professor: chamada_ja_enviada volta a travar so com secretaria',
    ancora: [
      '            and public.fn_presenca_precedencia(ap.respondido_por)',
      "                >= public.fn_presenca_precedencia('professor_la_teacher'))) then",
      "    return jsonb_build_object('aula_id', v_aula.id,",
      "      'total_roster', v_roster_total, 'inseridos', 0,",
      "      'ignorados_first_write_wins', v_roster_total,",
      "      'ja_havia_registros', true, 'chamada_ja_enviada', true);",
      '  end if;',
      '  v_res := public.fn_registrar_presencas_core(',
      "    v_aula.id, v_prof, p_alunos_ausentes, 'professor_la_teacher', true);",
    ].join('\n'),
    substituicao: [
      "            and public.fn_presenca_e_forte(ap.respondido_por))) then",
      "    return jsonb_build_object('aula_id', v_aula.id,",
      "      'total_roster', v_roster_total, 'inseridos', 0,",
      "      'ignorados_first_write_wins', v_roster_total,",
      "      'ja_havia_registros', true, 'chamada_ja_enviada', true);",
      '  end if;',
      '  v_res := public.fn_registrar_presencas_core(',
      "    v_aula.id, v_prof, p_alunos_ausentes, 'professor_la_teacher', true);",
    ].join('\n'),
  },
  {
    nome: 'M3 porta whatsapp/audio: chamada_ja_enviada volta a travar so com secretaria',
    ancora: [
      '            and public.fn_presenca_precedencia(ap.respondido_por)',
      "                >= public.fn_presenca_precedencia('professor_la_teacher'))) then",
      "    return jsonb_build_object('aula_id', v_aula.id,",
      "      'total_roster', v_roster_total, 'inseridos', 0,",
      "      'ignorados_first_write_wins', v_roster_total,",
      "      'ja_havia_registros', true, 'chamada_ja_enviada', true);",
      '  end if;',
      '  v_res := public.fn_registrar_presencas_core(',
      "    v_aula.id, p_professor_id, p_alunos_ausentes, 'professor_whatsapp', true);",
    ].join('\n'),
    substituicao: [
      "            and public.fn_presenca_e_forte(ap.respondido_por))) then",
      "    return jsonb_build_object('aula_id', v_aula.id,",
      "      'total_roster', v_roster_total, 'inseridos', 0,",
      "      'ignorados_first_write_wins', v_roster_total,",
      "      'ja_havia_registros', true, 'chamada_ja_enviada', true);",
      '  end if;',
      '  v_res := public.fn_registrar_presencas_core(',
      "    v_aula.id, p_professor_id, p_alunos_ausentes, 'professor_whatsapp', true);",
    ].join('\n'),
  },
  {
    nome: 'M4 manual perde o teto (empatado com o professor)',
    ancora: "    when 'manual'               then 3",
    substituicao: "    when 'manual'               then 2",
  },
  {
    nome: 'M5 secretaria empatada com o professor (volta a poder travar a correcao)',
    ancora: "    when 'agenda_secretaria'    then 1",
    substituicao: "    when 'agenda_secretaria'    then 2",
  },
]

function extrairTesteDocker(sql) {
  const inicio = '/* 20260815010000-DOCKER-DML-TESTS-INICIO'
  const fim = '20260815010000-DOCKER-DML-TESTS-FIM */'
  const indiceInicio = sql.indexOf(inicio)
  const indiceFim = sql.indexOf(fim)
  if (indiceInicio < 0 || indiceFim < 0 || indiceFim <= indiceInicio) {
    throw new Error('bloco Docker de DML do teste 20260815010000 ausente ou malformado')
  }
  if (sql.indexOf(inicio, indiceInicio + inicio.length) >= 0 || sql.indexOf(fim, indiceFim + fim.length) >= 0) {
    throw new Error('bloco Docker de DML do teste 20260815010000 deve ser unico')
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

const container = `la-teacher-20260815010000-mutantes-${process.pid}-${Date.now()}`
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
