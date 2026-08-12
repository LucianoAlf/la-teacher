#!/usr/bin/env node
// Mutacoes do contrato de recibo. Roda exclusivamente num PostgreSQL Docker
// descartavel: nao usa o runner remoto, nem dados, triggers ou sequencias live.

import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

const MIGRATION = 'supabase/migrations/20260812163000_recibo_so_whatsapp_e_fila_ativa.sql'
const TEST = 'supabase/migrations/20260812163000_recibo_so_whatsapp_e_fila_ativa.test.sql'
const IMAGE = process.env.MUTANTE_20260812163000_POSTGRES_IMAGE ?? 'postgres:17-alpine'
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
    anotacoes_fabio text
  );
  create table public.aula_alunos_emusys (
    aula_emusys_id integer not null,
    aluno_id integer not null
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
    criado_em timestamptz not null default now()
  );
  create table public.fabio_notificacoes (
    id uuid primary key default gen_random_uuid(),
    professor_id integer,
    tipo text,
    categoria text,
    canal text,
    titulo text,
    corpo text,
    destinatario_tipo text,
    status text,
    tentativas integer,
    lease_token uuid,
    lease_expira_em timestamptz,
    referencia_tipo text,
    referencia_id text,
    proxima_tentativa_em timestamptz,
    criado_em timestamptz,
    last_error text
  );
  create unique index uq_fabio_notificacoes_registro_recibo_unico
    on public.fabio_notificacoes (
      professor_id, tipo, referencia_tipo, referencia_id, canal
    )
    where tipo = 'registro_recibo'
      and referencia_tipo = 'registro_aula'
      and canal = 'whatsapp';
  create table public.fabio_devolutivas (
    id uuid primary key default gen_random_uuid(),
    registro_fatia_id uuid not null,
    status text not null
  );
  create table public.alunos (
    id integer primary key,
    nome text not null
  );
  create table public.aula_registros_fabio_log (
    aula_id integer not null,
    criado_em timestamptz not null default now()
  );
  create function public.fn_presenca_declarada(jsonb)
  returns text language sql immutable as $$ select $1 ->> 'presenca' $$;
  create function public.fn_compor_texto_prontuario(jsonb, jsonb)
  returns text language sql immutable as $$ select ''::text $$;
  create function public.fn_remover_campos_comuns_da_fatia(jsonb, jsonb)
  returns jsonb language sql immutable as $$ select coalesce($2, '{}'::jsonb) $$;
  create function public.fn_aula_individual_do_aluno(integer, integer)
  returns integer language sql immutable as $$ select $1 $$;
  create function public.fn_janela_registro_dias()
  returns integer language sql immutable as $$ select 7 $$;
  create function public.fn_professor_do_usuario()
  returns integer language sql stable as $$ select 702 $$;
  create function public.fn_enfileirar_audio_core(
    integer, text, integer, uuid, text, integer
  ) returns jsonb language sql as $$ select '{}'::jsonb $$;
  revoke all on function public.fn_enfileirar_audio_core(integer, text, integer, uuid, text, integer)
    from public, anon, authenticated, service_role;
`

const mutantes = [
  {
    nome: 'M1 origem NULL deixa de ser bloqueada',
    ancora: "  if v_registro.origem is distinct from 'whatsapp' then",
    substituicao: "  if v_registro.origem <> 'whatsapp' then",
  },
  {
    nome: 'M2 enqueue perde SECURITY DEFINER',
    ancora: [
      'create or replace function public.fn_enfileirar_registro_recibo(',
      '  p_registro_id uuid,',
      '  p_professor_id integer',
      ') returns jsonb',
      'language plpgsql',
      'security definer',
      'set search_path = pg_catalog, public',
    ].join('\n'),
    substituicao: [
      'create or replace function public.fn_enfileirar_registro_recibo(',
      '  p_registro_id uuid,',
      '  p_professor_id integer',
      ') returns jsonb',
      'language plpgsql',
      'security invoker',
      'set search_path = pg_catalog, public',
    ].join('\n'),
  },
  {
    nome: 'M3 enqueue perde search_path seguro',
    ancora: [
      'create or replace function public.fn_enfileirar_registro_recibo(',
      '  p_registro_id uuid,',
      '  p_professor_id integer',
      ') returns jsonb',
      'language plpgsql',
      'security definer',
      'set search_path = pg_catalog, public',
    ].join('\n'),
    substituicao: [
      'create or replace function public.fn_enfileirar_registro_recibo(',
      '  p_registro_id uuid,',
      '  p_professor_id integer',
      ') returns jsonb',
      'language plpgsql',
      'security definer',
      'set search_path = public',
    ].join('\n'),
  },
  {
    nome: 'M4 claim aceita raiz que nao veio do WhatsApp',
    ancora: "       and raiz.origem = 'whatsapp'",
    substituicao: '       and true -- M4: origem da raiz ignorada',
  },
  {
    nome: 'M5 enqueue perde DO NOTHING idempotente',
    ancora: '  do nothing\n  returning id into v_notificacao_id;',
    substituicao: '  do update set corpo = excluded.corpo\n  returning id into v_notificacao_id;',
  },
  {
    nome: 'M6 ACL do enqueue volta a expor a API',
    ancora: [
      'revoke all on function public.fn_enfileirar_registro_recibo(uuid, integer)',
      '  from public, anon, authenticated, service_role;',
    ].join('\n'),
    substituicao: [
      'grant execute on function public.fn_enfileirar_registro_recibo(uuid, integer)',
      '  to anon, authenticated, service_role;',
    ].join('\n'),
  },
  {
    nome: 'M7 ACL do claim volta a expor anon',
    ancora: [
      'grant execute on function public.fabio_claim_registro_recibo(integer, integer)',
      '  to service_role;',
    ].join('\n'),
    substituicao: [
      'grant execute on function public.fabio_claim_registro_recibo(integer, integer)',
      '  to service_role, anon;',
    ].join('\n'),
  },
  {
    nome: 'M8 claim deixa passar devolutiva ausente ou pendente',
    ancora: "            and (d.id is null or d.status not in ('gerada', 'oferecida'))",
    substituicao: '            and false -- M8: cerca de devolutiva removida',
  },
  {
    nome: 'M9 claim perde SKIP LOCKED',
    ancora: '     for update of n skip locked',
    substituicao: '     for update of n',
  },
  {
    nome: 'M10 normalizacao de audio volta a confiar no payload',
    ancora: 'select f.origem, f.status, f.erro_tipo',
    substituicao: "select coalesce(p_payload ->> 'origem', 'app'), f.status, f.erro_tipo",
  },
  {
    nome: 'M11 normalizacao sem audio deixa de usar app seguro',
    ancora: "  v_origem text := 'app';",
    substituicao: '  v_origem text := null;',
  },
  {
    nome: 'M12 status volta a tratar texto de erro historico como erro atual',
    ancora: "case when f.status = 'erro' then true else false end",
    substituicao: 'case when f.erro is not null then true else false end',
  },
  {
    nome: 'M13 status passa a tratar erro terminal como retryavel',
    ancora: "case when f.status = 'erro' then true else false end",
    substituicao: "case when f.status in ('erro', 'erro_terminal') then true else false end",
  },
  {
    nome: 'M14 fila pendente deixa de bloquear nova gravacao',
    ancora: "and f.status in ('pendente', 'transcrevendo', 'transcrito', 'erro')",
    substituicao: "and f.status in ('transcrevendo', 'transcrito', 'erro')",
  },
  {
    nome: 'M15 fila transcrevendo deixa de bloquear nova gravacao',
    ancora: "and f.status in ('pendente', 'transcrevendo', 'transcrito', 'erro')",
    substituicao: "and f.status in ('pendente', 'transcrito', 'erro')",
  },
  {
    nome: 'M16 fila transcrito deixa de bloquear nova gravacao',
    ancora: "and f.status in ('pendente', 'transcrevendo', 'transcrito', 'erro')",
    substituicao: "and f.status in ('pendente', 'transcrevendo', 'erro')",
  },
  {
    nome: 'M17 fila com erro retryavel deixa de bloquear nova gravacao',
    ancora: "and f.status in ('pendente', 'transcrevendo', 'transcrito', 'erro')",
    substituicao: "and f.status in ('pendente', 'transcrevendo', 'transcrito')",
  },
  {
    nome: 'M18 nova gravacao perde a serializacao por aula',
    ancora: "'fabio-fila-audio-aula:' || p_professor_id::text || ':' || p_aula_id::text",
    substituicao: "'fabio-fila-audio-path:' || p_professor_id::text || ':' || v_storage_path",
  },
  {
    nome: 'M19 novas gravacoes deixam de consultar a fila viva e o rascunho',
    ancora: '  if p_registro_id is null then\n    select * into v_fila_viva',
    substituicao: '  if false then\n    select * into v_fila_viva',
  },
  {
    nome: 'M20 registro confirmado volta a bloquear nova gravacao',
    ancora: "and r.status in ('rascunho', 'aguardando_confirmacao')",
    substituicao: "and r.status in ('rascunho', 'aguardando_confirmacao', 'gravado_emusys', 'confirmado')",
  },
  {
    nome: 'M21 retorno de rascunho deixa de sinalizar que ja existe',
    ancora: "'rascunho_existente', true",
    substituicao: "'rascunho_existente', false",
  },
  {
    nome: 'M22 dedupe por storage path e removido',
    ancora: '     and storage_path = v_storage_path',
    substituicao: '     and false -- M22: storage_path ignorado',
  },
  {
    nome: 'M23 complemento deixa de anexar o novo audio ao rascunho',
    ancora: [
      '  if p_registro_id is not null then',
      '    update public.fabio_registros_aula',
      "       set campos = campos || jsonb_build_object('audio_complemento_id', v_id)",
      '     where id = p_registro_id;',
      '  end if;',
    ].join('\n'),
    substituicao: '  perform 1; -- M23: complemento nao fica vinculado ao registro',
  },
  {
    nome: 'M24 janela de gravacao encerrada deixa de ser recusada',
    ancora: "    raise exception 'janela_de_gravacao_encerrada';",
    substituicao: '      null; -- M24: janela expirada aceita',
  },
  {
    nome: 'M25 ACL do status deixa PUBLIC executar',
    ancora: [
      'revoke all on function public.app_status_audio_fila(uuid)',
      '  from public, anon, authenticated, service_role;',
    ].join('\n'),
    substituicao: [
      'revoke all on function public.app_status_audio_fila(uuid)',
      '  from anon, authenticated, service_role;',
    ].join('\n'),
  },
  {
    nome: 'M26 ACL do status remove acesso autenticado',
    ancora: [
      'grant execute on function public.app_status_audio_fila(uuid)',
      '  to authenticated, service_role;',
    ].join('\n'),
    substituicao: [
      'grant execute on function public.app_status_audio_fila(uuid)',
      '  to service_role;',
    ].join('\n'),
  },
  {
    nome: 'M27 ACL do status remove acesso service_role',
    ancora: [
      'grant execute on function public.app_status_audio_fila(uuid)',
      '  to authenticated, service_role;',
    ].join('\n'),
    substituicao: [
      'grant execute on function public.app_status_audio_fila(uuid)',
      '  to authenticated;',
    ].join('\n'),
  },
  {
    nome: 'M28 status de audio perde search_path seguro',
    ancora: [
      'create or replace function public.app_status_audio_fila(p_audio_id uuid)',
      'returns table(',
      '  audio_id uuid,',
      '  status text,',
      '  tentativas integer,',
      '  tem_erro boolean,',
      '  criado_em timestamptz,',
      '  atualizado_em timestamptz',
      ')',
      'language sql',
      'security definer',
      'set search_path = pg_catalog, public',
    ].join('\n'),
    substituicao: [
      'create or replace function public.app_status_audio_fila(p_audio_id uuid)',
      'returns table(',
      '  audio_id uuid,',
      '  status text,',
      '  tentativas integer,',
      '  tem_erro boolean,',
      '  criado_em timestamptz,',
      '  atualizado_em timestamptz',
      ')',
      'language sql',
      'security definer',
      'set search_path = public',
    ].join('\n'),
  },
]

function extrairTesteDocker(sql) {
  const inicio = '/* 20260812163000-DOCKER-DML-TESTS-INICIO'
  const fim = '20260812163000-DOCKER-DML-TESTS-FIM */'
  const indiceInicio = sql.indexOf(inicio)
  const indiceFim = sql.indexOf(fim)
  if (indiceInicio < 0 || indiceFim < 0 || indiceFim <= indiceInicio) {
    throw new Error('bloco Docker de DML do teste 20260812163000 ausente ou malformado')
  }
  if (sql.indexOf(inicio, indiceInicio + inicio.length) >= 0 || sql.indexOf(fim, indiceFim + fim.length) >= 0) {
    throw new Error('bloco Docker de DML do teste 20260812163000 deve ser unico')
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

function mascarar(caracteres, inicio, fim) {
  for (let indice = inicio; indice < fim; indice += 1) {
    if (caracteres[indice] !== '\n' && caracteres[indice] !== '\r') caracteres[indice] = ' '
  }
}

// Preserva o tamanho e as quebras de linha do SQL, mas remove comentarios,
// strings e identificadores entre aspas da analise de comandos. Literais dollar
// tambem sao devolvidos separadamente: corpos de DO/funcoes temporarias sao
// analisados recursivamente, enquanto texto usado por position()/pg_get_* nao.
function analisarLexicamente(sql) {
  const caracteres = [...sql]
  const dollar = []

  for (let indice = 0; indice < sql.length;) {
    if (sql.startsWith('--', indice)) {
      const fim = sql.indexOf('\n', indice)
      const proximo = fim < 0 ? sql.length : fim
      mascarar(caracteres, indice, proximo)
      indice = proximo
      continue
    }

    if (sql.startsWith('/*', indice)) {
      let profundidade = 1
      let cursor = indice + 2
      while (cursor < sql.length && profundidade > 0) {
        if (sql.startsWith('/*', cursor)) {
          profundidade += 1
          cursor += 2
        } else if (sql.startsWith('*/', cursor)) {
          profundidade -= 1
          cursor += 2
        } else {
          cursor += 1
        }
      }
      if (profundidade !== 0) throw new Error('comentario SQL nao terminado')
      mascarar(caracteres, indice, cursor)
      indice = cursor
      continue
    }

    if (sql[indice] === "'") {
      let cursor = indice + 1
      let terminada = false
      while (cursor < sql.length) {
        if (sql[cursor] === '\\') {
          cursor += 2
        } else if (sql[cursor] === "'") {
          if (sql[cursor + 1] === "'") {
            cursor += 2
          } else {
            cursor += 1
            terminada = true
            break
          }
        } else {
          cursor += 1
        }
      }
      if (!terminada) throw new Error('string SQL nao terminada')
      mascarar(caracteres, indice, cursor)
      indice = cursor
      continue
    }

    if (sql[indice] === '"') {
      let cursor = indice + 1
      let terminada = false
      while (cursor < sql.length) {
        if (sql[cursor] === '"') {
          if (sql[cursor + 1] === '"') {
            cursor += 2
          } else {
            cursor += 1
            terminada = true
            break
          }
        } else {
          cursor += 1
        }
      }
      if (!terminada) throw new Error('identificador SQL nao terminado')
      mascarar(caracteres, indice, cursor)
      indice = cursor
      continue
    }

    const podeAbrirDollar = indice === 0 || !/[A-Za-z0-9_$]/u.test(sql[indice - 1])
    const abertura = podeAbrirDollar ? sql.slice(indice).match(/^\$([A-Za-z_][A-Za-z0-9_]*|)\$/u) : null
    if (abertura) {
      const delimitador = abertura[0]
      const inicioCorpo = indice + delimitador.length
      const fimCorpo = sql.indexOf(delimitador, inicioCorpo)
      if (fimCorpo < 0) throw new Error(`literal dollar ${delimitador} nao terminado`)
      const fim = fimCorpo + delimitador.length
      dollar.push({ inicio: indice, corpo: sql.slice(inicioCorpo, fimCorpo) })
      mascarar(caracteres, indice, fim)
      indice = fim
      continue
    }

    indice += 1
  }

  return { codigo: caracteres.join(''), dollar }
}

function alvoTemporario(alvo) {
  return alvo.toLowerCase() === 'pg_temp._fabio_20260812163000_res'
}

function validarComandos(sql, contexto = 'topo') {
  const { codigo, dollar } = analisarLexicamente(sql)
  const escritas = [
    ...codigo.matchAll(/\b(insert\s+into|update|delete\s+from|merge\s+into|truncate(?:\s+table)?|copy)\s+([A-Za-z_][A-Za-z0-9_.]*)/giu),
  ]
  for (const [, comando, alvo] of escritas) {
    if (!alvoTemporario(alvo)) {
      throw new Error(`${contexto}: ${comando.toUpperCase()} aponta para ${alvo}, nao para a tabela temporaria permitida`)
    }
  }

  if (/\bexecute\b/iu.test(codigo)) {
    throw new Error(`${contexto}: EXECUTE dinamico e proibido no ensaio isolado`)
  }
  if (/\b(?:public\.)?(?:fn_enfileirar_registro_recibo|fabio_claim_registro_recibo)\s*\(/iu.test(codigo)) {
    throw new Error(`${contexto}: o teste chama uma porta que escreve em public`)
  }
  if (/\bcreate\s+(?!temporary\s+table\b|or\s+replace\s+function\s+pg_temp\.)/iu.test(codigo)) {
    throw new Error(`${contexto}: o teste cria objeto que nao e temporario`)
  }
  if (
    /\b(?:alter|grant|revoke|comment\s+on)\b/iu.test(codigo)
    || /\bdrop\s+(?:table|function|schema|database|index|type|view|materialized|policy|trigger|extension|sequence)\b/iu.test(codigo)
  ) {
    throw new Error(`${contexto}: o teste altera objeto ou permissao persistente`)
  }

  for (const literal of dollar) {
    const antes = codigo.slice(0, literal.inicio).replace(/[\s;]+$/gu, '')
    const inicioComando = antes.lastIndexOf(';') + 1
    const cabecalho = antes.slice(inicioComando)
    const corpoDeFuncaoTemp = /\bcreate\s+(?:or\s+replace\s+)?function\s+pg_temp\.[A-Za-z_][A-Za-z0-9_]*[\s\S]*\bas$/iu.test(cabecalho)
    const corpoDo = /\bdo$/iu.test(cabecalho)
    if (corpoDeFuncaoTemp || corpoDo) validarComandos(literal.corpo, corpoDeFuncaoTemp ? 'corpo de funcao temporaria' : 'corpo DO')
  }
}

function validarTesteSemDmlPersistente(sql) {
  validarComandos(sql)
}

function esperarPreflightAceitar(sql, caso) {
  try {
    validarTesteSemDmlPersistente(sql)
  } catch (erro) {
    throw new Error(`${caso}: preflight rejeitou SQL seguro: ${erro.message}`)
  }
}

function esperarPreflightRejeitar(sql, caso) {
  try {
    validarTesteSemDmlPersistente(sql)
  } catch {
    return
  }
  throw new Error(`${caso}: preflight aceitou SQL inseguro`)
}

function testarPreflightLexico() {
  esperarPreflightAceitar(
    'create temporary table pg_temp._fabio_20260812163000_res (ok boolean) on commit drop;',
    'ON COMMIT DROP de tabela temporaria',
  )
  esperarPreflightAceitar(`
    do $corpo$
    begin
      perform position('insert into public.fabio_notificacoes' in 'texto de inspecao');
    end
    $corpo$;
  `, 'literais de inspecao nao sao DML')
  esperarPreflightAceitar(`
    create or replace function pg_temp.checar() returns void language plpgsql as $corpo$
    begin
      insert into pg_temp._fabio_20260812163000_res values ('ok');
    end
    $corpo$;
  `, 'DML na tabela temporaria permitida')
  esperarPreflightRejeitar(`
    do $corpo$
    begin
      insert into public.fabio_notificacoes values (null);
    end
    $corpo$;
  `, 'DML persistente em corpo DO')
  esperarPreflightRejeitar(
    'select public.fn_enfileirar_registro_recibo(null, null);',
    'chamada da porta de enqueue',
  )
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

testarPreflightLexico()
console.log('OK     preflight lexico ignora strings e rejeita DML persistente')
validarTesteSemDmlPersistente(teste)
console.log('OK     teste sem DML persistente nem chamadas de escrita em public')

const container = `la-teacher-task1-mutantes-${process.pid}-${Date.now()}`
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
