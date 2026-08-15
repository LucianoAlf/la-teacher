#!/usr/bin/env node
// Mutacoes do conserto "a aula sem aluno para de engolir o trabalho do
// professor". Roda num PostgreSQL Docker descartavel: aplica a migration + o
// bloco DML do teste, confere o baseline verde e exige que cada mutante morra
// POR ASSERCAO (nao por erro de sintaxe ou de constraint -- mutante que morre
// de erro nao prova nada sobre o teste).

import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

const MIGRATION = 'supabase/migrations/20260815100000_a_aula_sem_aluno_para_de_engolir_o_trabalho_do_professor.sql'
const TEST = 'supabase/migrations/20260815100000_a_aula_sem_aluno_para_de_engolir_o_trabalho_do_professor.test.sql'
const IMAGE = process.env.MUTANTE_SEM_ROSTER_POSTGRES_IMAGE ?? 'postgres:17-alpine'
const fonte = readFileSync(MIGRATION, 'utf8')
const teste = readFileSync(TEST, 'utf8')
const testeDocker = extrairTesteDocker(teste)

// O bootstrap espelha producao NO QUE ESTA MIGRATION USA. Os dois CHECKs de
// `fabio_fila_audios` vao junto de proposito: eles amarram status e erro_tipo
// um ao outro, e um schema de teste sem eles deixaria passar um UPDATE que
// producao recusa. Ja aconteceu duas vezes neste projeto (o CHECK de
// `casado_por`, o teto de 3 da shortlist): verde num schema mais frouxo que o
// real nao vale nada.
//
// `fn_aula_operacional_id` e copiada da definicao VIVA em producao, nao
// reescrita "equivalente" -- e ela quem decide metade dos casos aqui.
const bootstrap = `
  create extension if not exists pgcrypto;
  create role anon;
  create role authenticated;
  create role service_role;

  create table public.unidades (id uuid primary key, nome text);

  create table public.aulas_emusys (
    id integer primary key,
    professor_id integer,
    unidade_id uuid,
    tipo varchar,
    categoria varchar,
    turma_nome varchar,
    curso_nome varchar,
    qtd_alunos integer,
    cancelada boolean not null default false,
    data_hora_inicio timestamptz not null,
    data_hora_fim timestamptz
  );

  create table public.aula_alunos_emusys (
    id bigserial primary key,
    aula_emusys_id integer not null,
    unidade_id uuid,
    aluno_id integer
  );

  create table public.fabio_fila_audios (
    id uuid primary key default gen_random_uuid(),
    professor_id integer,
    unidade_id uuid,
    aula_id integer,
    storage_path text,
    duracao_segundos integer,
    status text not null,
    transcricao text,
    erro text,
    tentativas integer not null default 0,
    origem text not null,
    criado_em timestamptz not null default now(),
    atualizado_em timestamptz not null default now(),
    vinculo_id bigint,
    erro_tipo text not null default 'transitorio',
    constraint fabio_fila_audios_status_check
      check (status = any (array['pendente','transcrevendo','transcrito','normalizado','erro','erro_terminal'])),
    constraint fabio_fila_audios_origem_check
      check (origem = any (array['app','whatsapp'])),
    constraint fabio_fila_audios_erro_tipo_check
      check (((status = 'erro_terminal' and erro_tipo = 'semantico_terminal')
           or (status <> 'erro_terminal' and erro_tipo = 'transitorio')))
  );

  create table public.fabio_notificacoes (
    id uuid primary key default gen_random_uuid(),
    professor_id integer,
    tipo text not null,
    categoria text not null,
    titulo text,
    corpo text not null,
    referencia_tipo text,
    referencia_id text,
    canal text not null,
    status text not null,
    criado_em timestamptz not null default now()
  );

  create table public.fabio_registros_aula (
    id uuid primary key default gen_random_uuid(),
    aula_id integer,
    unidade_id uuid,
    professor_id integer,
    parent_id uuid,
    status text,
    criado_em timestamptz not null default now()
  );

  create table public.audit_log (
    id uuid primary key default gen_random_uuid(),
    tabela varchar not null,
    registro_id uuid,
    acao varchar not null,
    dados_antigos jsonb,
    dados_novos jsonb,
    usuario varchar,
    created_at timestamptz default now(),
    auth_user_id uuid,
    origem text,
    registro_id_text text
  );

  create function public.fn_aula_operacional_id(p_aula_id integer)
  returns integer language plpgsql stable security definer
  set search_path to 'pg_catalog', 'public'
  as $fn$
  declare
    v_base public.aulas_emusys%rowtype;
    v_id   integer;
  begin
    select * into v_base from public.aulas_emusys where id = p_aula_id;
    if not found then
      return null;
    end if;

    if v_base.unidade_id is not null
       and v_base.professor_id is not null
       and v_base.data_hora_fim is not null
       and v_base.curso_nome is not null then
      select candidata.id into v_id
        from public.aulas_emusys candidata
        left join lateral (
          select count(*)::integer as n_alunos
            from public.aula_alunos_emusys roster
           where roster.aula_emusys_id = candidata.id
        ) quantidade on true
       where candidata.unidade_id = v_base.unidade_id
         and candidata.professor_id = v_base.professor_id
         and candidata.data_hora_inicio = v_base.data_hora_inicio
         and candidata.data_hora_fim = v_base.data_hora_fim
         and candidata.curso_nome = v_base.curso_nome
         and coalesce(candidata.cancelada, false) = false
       order by coalesce(quantidade.n_alunos, 0) desc,
                case when candidata.tipo = 'turma' then 0 else 1 end,
                candidata.id desc
       limit 1;
      return v_id;
    end if;

    select candidata.id into v_id
      from public.aulas_emusys candidata
      left join lateral (
        select count(*)::integer as n_alunos
          from public.aula_alunos_emusys roster
         where roster.aula_emusys_id = candidata.id
      ) quantidade on true
     where candidata.unidade_id is not distinct from v_base.unidade_id
       and candidata.professor_id is not distinct from v_base.professor_id
       and candidata.data_hora_inicio = v_base.data_hora_inicio
       and candidata.data_hora_fim is not distinct from v_base.data_hora_fim
       and candidata.curso_nome is not distinct from v_base.curso_nome
       and coalesce(candidata.cancelada, false) = false
     order by coalesce(quantidade.n_alunos, 0) desc,
              case when candidata.tipo = 'turma' then 0 else 1 end,
              candidata.id desc
     limit 1;
    return v_id;
  end;
  $fn$;
`

const mutantes = [
  {
    // A fronteira que o worker da experimental sempre teve. Sem ela, este aviso
    // passa a falar de aula experimental -- que tem porta propria desde a
    // 20260815070000.
    nome: 'o aviso rouba audio da experimental (sem vinculo_id is null)',
    ancora: "where f.vinculo_id is null            -- experimental tem worker e porta próprios",
    substituicao: 'where true',
  },
  {
    // Ancorar no aula_id cru desfaz o resolvedor de 12/08: a turma velha vazia
    // volta a parecer problema quando o gemeo com roster resolve o caso.
    nome: 'a view volta a ancorar no aula_id cru (ignora o resolvedor)',
    ancora: '  on a.id = public.fn_aula_operacional_id(f.aula_id)',
    substituicao: '  on a.id = f.aula_id',
  },
  {
    // Sem a folga, o Fabio cobra a secretaria enquanto a secretaria esta
    // lancando a turma.
    nome: 'o aviso perde a janela de folga (cobra em 2 minutos)',
    ancora: '     and v.atualizado_em < now() - make_interval(mins => greatest(p_grace_minutos, 0))',
    substituicao: '     and true',
  },
  {
    // Sem isto o professor leva a mesma noticia a cada ciclo do timer.
    nome: 'o aviso reenvia pra quem ja foi avisado',
    ancora: `     and not exists (
       select 1 from public.fabio_notificacoes n
        where n.referencia_tipo = 'fila_audio_sem_roster'
          and n.referencia_id   = v.fila_id::text
          and n.status          = 'enviada'
     )`,
    substituicao: '     and true',
  },
  {
    // O professor ja resolveu na mao. Avisar agora e ruido puro.
    nome: 'o aviso cutuca quem ja registrou na mao',
    ancora: '   where not v.ja_tem_registro',
    substituicao: '   where true',
  },
  {
    // O CORACAO da retomada: sem o marcador da promessa, ela religa QUALQUER
    // terminal cuja aula tenha roster -- inclusive quem morreu por outro motivo
    // semantico e vai morrer de novo, em loop.
    nome: 'a retomada religa as cegas (sem exigir o aviso enviado)',
    ancora: `       and exists (
         select 1 from public.fabio_notificacoes nt
          where nt.referencia_tipo = 'fila_audio_sem_roster'
            and nt.referencia_id   = f.id::text
            and nt.status          = 'enviada'
       )`,
    substituicao: '       and true',
  },
  {
    // Marcar 'pendente' sem disparar nao retoma nada: fn_fabio_retry_fila so
    // alcanca linha com criado_em nos ultimos 3 dias.
    nome: 'a retomada so troca a cor da linha (nao dispara a edge)',
    ancora: '    perform public.fn_fabio_chama_edge(r.id);\n',
    substituicao: '',
  },
  {
    // Religar sem rastro: o audit_log e o unico lugar onde fica escrito que a
    // linha mudou de aula e de estado por decisao de maquina.
    nome: 'a retomada mexe na fila sem deixar rastro no audit_log',
    ancora: `    insert into public.audit_log(tabela, registro_id_text, acao, dados_antigos, dados_novos, origem)
    values (
      'fabio_fila_audios', r.id::text, 'retomada_por_roster',
      jsonb_build_object('aula_id', r.aula_antiga, 'status', 'erro/erro_terminal'),
      jsonb_build_object('aula_id', r.aula_nova, 'status', 'pendente'),
      'fn_fila_audio_retomar_por_roster'
    );
`,
    substituicao: '',
  },
]

function extrairTesteDocker(texto) {
  const inicio = texto.indexOf('SEM-ROSTER-DOCKER-DML-TESTS-INICIO')
  const fim = texto.indexOf('SEM-ROSTER-DOCKER-DML-TESTS-FIM')
  if (inicio === -1 || fim === -1) {
    throw new Error('bloco DOCKER-DML-TESTS nao encontrado no teste')
  }
  return texto.slice(inicio + 'SEM-ROSTER-DOCKER-DML-TESTS-INICIO'.length, fim)
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

const container = `la-teacher-sem-roster-mutantes-${process.pid}-${Date.now()}`
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
