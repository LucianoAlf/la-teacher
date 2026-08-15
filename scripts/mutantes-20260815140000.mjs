#!/usr/bin/env node
// Mutacoes das RPCs "ocorrencia de participacao (substituicao) em shadow".
// Roda num PostgreSQL Docker descartavel: o bootstrap sobe o SCHEMA INTEIRO da
// Task 1 (tabelas/view/triggers) + uma carteira fake + tabelas fake de
// presenca/registro (para provar shadow por contagem) + fn_aula_operacional_id
// fake; a migration das RPCs e aplicada dentro do ensaio. Confere o baseline
// verde e exige que cada mutante morra POR ASSERCAO (nao por erro).

import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

const MIGRATION = 'supabase/migrations/20260815140000_participacao_ocorrencias_rpcs.sql'
const TEST = 'supabase/migrations/20260815140000_participacao_ocorrencias_rpcs.test.sql'
const IMAGE = process.env.MUTANTE_PARTICIPACAO_POSTGRES_IMAGE ?? 'postgres:17-alpine'
const fonte = readFileSync(MIGRATION, 'utf8')
const teste = readFileSync(TEST, 'utf8')
const testeDocker = extrairTesteDocker(teste)

// DDL do schema da Task 1 (tabelas + indice unico + view + triggers + grants),
// copiado de 20260815130000_participacao_ocorrencias_schema.sql. As RPCs
// consomem estas tabelas/view; sem elas o ensaio nem aplica.
const schema = `
create table if not exists public.fabio_participacao_ocorrencias (
  id uuid primary key default gen_random_uuid(),
  aula_operacional_id integer not null,
  aula_id integer not null,
  professor_id integer not null,
  aluno_matriculado_id integer not null,
  participante_real_id integer,
  participante_real_nome text,
  participante_real_telefone text,
  tipo text not null default 'substituicao',
  confianca text not null,
  metodo_extracao text not null,
  origem text not null,
  origem_message_id text,
  origem_transcricao text,
  supersede_ocorrencia_id uuid references public.fabio_participacao_ocorrencias(id),
  criado_em timestamptz not null default now(),
  constraint chk_participacao_tipo check (tipo = any (array['substituicao'])),
  constraint chk_participacao_confianca check (confianca = any (array['alta','media','baixa'])),
  constraint chk_participacao_metodo check (metodo_extracao = any (array['deterministico','llm'])),
  constraint chk_participacao_origem check (origem = any (array['whatsapp','manual_admin'])),
  constraint chk_participante_identificado
    check (participante_real_id is not null
           or coalesce(btrim(participante_real_nome), '') <> ''),
  constraint chk_matriculado_difere_participante
    check (participante_real_id is null or participante_real_id <> aluno_matriculado_id),
  constraint chk_origem_message_id
    check (origem <> 'whatsapp' or origem_message_id is not null)
);

create unique index if not exists uq_participacao_msg_vigente
  on public.fabio_participacao_ocorrencias (aula_operacional_id, aluno_matriculado_id, origem_message_id)
  where origem_message_id is not null and supersede_ocorrencia_id is null;

create table if not exists public.fabio_participacao_ocorrencia_eventos (
  id uuid primary key default gen_random_uuid(),
  seq bigint generated always as identity,
  ocorrencia_id uuid not null references public.fabio_participacao_ocorrencias(id),
  evento text not null,
  por_tipo text not null,
  por_id text,
  dados jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now(),
  constraint chk_participacao_evento
    check (evento = any (array['registrada','confirmada','validada','descartada','corrigida'])),
  constraint chk_participacao_por_tipo
    check (por_tipo = any (array['sistema','professor','coordenacao']))
);

create index if not exists idx_participacao_evento_ocorrencia
  on public.fabio_participacao_ocorrencia_eventos (ocorrencia_id, criado_em);

create or replace view public.vw_fabio_participacao_ocorrencia_estado as
select distinct on (e.ocorrencia_id)
  e.ocorrencia_id,
  case e.evento when 'registrada' then 'candidata' else e.evento end as estado_atual,
  e.criado_em as estado_em,
  e.por_tipo  as estado_por
from public.fabio_participacao_ocorrencia_eventos e
order by e.ocorrencia_id, e.seq desc;

create or replace function public.fn_participacao_append_only()
returns trigger language plpgsql as $function$
begin
  raise exception 'fabio_participacao e append-only: % bloqueado em %', tg_op, tg_table_name;
end
$function$;

create trigger trg_participacao_ocorrencias_append_only
  before update or delete on public.fabio_participacao_ocorrencias
  for each row execute function public.fn_participacao_append_only();

create trigger trg_participacao_eventos_append_only
  before update or delete on public.fabio_participacao_ocorrencia_eventos
  for each row execute function public.fn_participacao_append_only();

create or replace function public.fn_participacao_supersede_coerente()
returns trigger language plpgsql
set search_path to 'pg_catalog', 'public' as $function$
declare
  v_ant public.fabio_participacao_ocorrencias%rowtype;
begin
  if new.supersede_ocorrencia_id is null then
    return new;
  end if;
  select * into v_ant from public.fabio_participacao_ocorrencias where id = new.supersede_ocorrencia_id;
  if not found then
    raise exception 'supersede aponta pra ocorrencia inexistente';
  end if;
  if v_ant.aula_operacional_id <> new.aula_operacional_id
     or v_ant.aluno_matriculado_id <> new.aluno_matriculado_id then
    raise exception 'supersede so corrige a MESMA aula operacional e o MESMO aluno matriculado';
  end if;
  insert into public.fabio_participacao_ocorrencia_eventos (ocorrencia_id, evento, por_tipo, por_id, dados)
  values (v_ant.id, 'corrigida', 'sistema', null, jsonb_build_object('corrigida_por', new.id));
  return new;
end
$function$;

create trigger trg_participacao_supersede_coerente
  before insert on public.fabio_participacao_ocorrencias
  for each row execute function public.fn_participacao_supersede_coerente();

revoke all on public.fabio_participacao_ocorrencias from public, anon, authenticated, service_role;
revoke all on public.fabio_participacao_ocorrencia_eventos from public, anon, authenticated, service_role;
revoke all on public.vw_fabio_participacao_ocorrencia_estado from public, anon, authenticated, service_role;
grant select, insert on public.fabio_participacao_ocorrencias to service_role;
grant select, insert on public.fabio_participacao_ocorrencia_eventos to service_role;
grant select on public.vw_fabio_participacao_ocorrencia_estado to service_role;
`

// Bootstrap: pgcrypto, roles, o schema acima, a regua da aula operacional fake
// (devolve o proprio id), tabelas fake de presenca/registro (contamos antes/
// depois para provar shadow) e a carteira fake com o Billy, o Marcelo e DOIS
// Felipe (cardinalidade 2). Os nomes tem sobrenome de proposito: casar por
// string inteira (o mutante 4) nao acha o primeiro nome.
const bootstrap = `
  create extension if not exists pgcrypto;
  create role anon;
  create role authenticated;
  create role service_role;

  create function public.fn_aula_operacional_id(p_aula_id integer)
  returns integer language sql immutable as $fn$ select p_aula_id $fn$;

  create table public.aluno_presenca (id serial primary key);
  create table public.fabio_registros_aula (id serial primary key);

  create table public._carteira_fake (
    professor_id integer,
    aluno_id integer,
    aluno_nome text,
    unidade_id uuid
  );
  insert into public._carteira_fake (professor_id, aluno_id, aluno_nome, unidade_id) values
    (10, 101, 'Billy Paulo Vangu',  '11111111-1111-1111-1111-111111111111'),
    (10, 103, 'Felipe Souza',       '11111111-1111-1111-1111-111111111111'),
    (10, 104, 'Felipe Andrade',     '11111111-1111-1111-1111-111111111111'),
    (99, 102, 'Marcelo Dias',       '11111111-1111-1111-1111-111111111111');

  create view public.vw_fabio_carteira_professor as
    select professor_id, aluno_id, aluno_nome, unidade_id from public._carteira_fake;
` + schema

const mutantes = [
  {
    // precisa_confirmar fixo em false: o externo (participante_real_id null)
    // deixa de pedir confirmacao.
    nome: 'precisa_confirmar fixo em false (externo deixa de pedir confirmacao)',
    ancora: `  v_precisa := (p_participante_real_id is null) or (p_confianca is distinct from 'alta');`,
    substituicao: '  v_precisa := false;',
  },
  {
    // validar deixa de exigir 'confirmada': validar uma candidata passa.
    nome: 'validar aceita candidata (some a checagem de confirmada)',
    ancora: `  if v_estado <> 'confirmada' then
    return jsonb_build_object('ok', false, 'estado', v_estado, 'motivo', 'so valida confirmada');
  end if;`,
    substituicao: '',
  },
  {
    // descartar deixa de bloquear validada: descartar uma validada passa.
    nome: 'descartar aceita validada (some o bloqueio de estados finais)',
    ancora: `  if v_estado not in ('candidata', 'confirmada') then
    return jsonb_build_object('ok', false, 'estado', v_estado, 'motivo', 'so descarta candidata ou confirmada');
  end if;`,
    substituicao: '',
  },
  {
    // resolver casa por nome INTEIRO (nao por token): 'Billy' nao acha
    // 'Billy Paulo Vangu' -> cardinalidade 0.
    nome: 'resolver casa por nome inteiro (Billy deixa de resolver cardinalidade 1)',
    ancora: `  select public.fn_participacao_nome_tokens(p_nome_a) && public.fn_participacao_nome_tokens(p_nome_b)`,
    substituicao: `  select lower(btrim(coalesce(p_nome_a, ''))) = lower(btrim(coalesce(p_nome_b, '')))`,
  },
  {
    // remove o guard de idempotencia: a segunda mensagem tenta inserir de novo
    // e bate no indice unico -> a segunda chamada nao devolve a existente.
    nome: 'remove o guard de idempotencia (mesma mensagem deixa de devolver a existente)',
    ancora: `  -- IDEMPOTENCIA-INICIO: mesma mensagem+aula+matriculado vigente devolve a existente.
  select o.id into v_id
  from public.fabio_participacao_ocorrencias o
  where o.aula_operacional_id = v_aula_op
    and o.aluno_matriculado_id = p_aluno_matriculado_id
    and o.origem_message_id = p_origem_message_id
    and o.supersede_ocorrencia_id is null
  limit 1;

  if v_id is not null then
    select estado_atual into v_estado
      from public.vw_fabio_participacao_ocorrencia_estado where ocorrencia_id = v_id;
    return jsonb_build_object(
      'ok', true,
      'ocorrencia_id', v_id,
      'estado', coalesce(v_estado, 'candidata'),
      'precisa_confirmar', ((p_participante_real_id is null) or (p_confianca is distinct from 'alta')),
      'motivo_ambiguidade', null,
      'ja_existia', true
    );
  end if;
  -- IDEMPOTENCIA-FIM`,
    substituicao: '',
  },
]

function extrairTesteDocker(texto) {
  const inicio = texto.indexOf('PARTICIPACAO-DOCKER-DML-TESTS-INICIO')
  const fim = texto.indexOf('PARTICIPACAO-DOCKER-DML-TESTS-FIM')
  if (inicio === -1 || fim === -1) {
    throw new Error('bloco DOCKER-DML-TESTS nao encontrado no teste')
  }
  return texto.slice(inicio + 'PARTICIPACAO-DOCKER-DML-TESTS-INICIO'.length, fim)
}

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

const container = `la-teacher-participacao-rpcs-mutantes-${process.pid}-${Date.now()}`
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
