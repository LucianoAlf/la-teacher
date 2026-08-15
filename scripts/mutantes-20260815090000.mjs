#!/usr/bin/env node
// Mutacoes do conserto "a chave natural nao desfaz o que o id do lead casou".
// Roda num PostgreSQL Docker descartavel: aplica a migration + o bloco DML do
// teste, confere o baseline verde e exige que cada mutante morra POR ASSERCAO
// (nao por erro de sintaxe ou de constraint -- mutante que morre de erro nao
// prova nada sobre o teste).

import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

const MIGRATION = 'supabase/migrations/20260815090000_a_chave_natural_nao_desfaz_o_que_o_id_do_lead_casou.sql'
const TEST = 'supabase/migrations/20260815090000_a_chave_natural_nao_desfaz_o_que_o_id_do_lead_casou.test.sql'
const IMAGE = process.env.MUTANTE_20260815090000_POSTGRES_IMAGE ?? 'postgres:17-alpine'
const fonte = readFileSync(MIGRATION, 'utf8')
const teste = readFileSync(TEST, 'utf8')
const testeDocker = extrairTesteDocker(teste)

// O bootstrap espelha producao NO QUE AS DUAS PORTAS USAM. Os CHECKs e os dois
// indices unicos vao junto de proposito: na 080000 o teste passou verde num
// schema sem o CHECK de `casado_por` e a funcao estourava em producao -- schema
// de teste divergindo do real e verde que nao vale.
const bootstrap = `
  create extension if not exists pgcrypto;
  -- Os papeis do Supabase: a migration revoga/concede neles, e sem eles o
  -- ensaio morre no primeiro \`revoke\` -- por ambiente, nao por assercao.
  create role anon;
  create role authenticated;
  create role service_role;
  create table public.unidades (id uuid primary key, nome text);
  create table public.professores (id integer primary key, nome text);
  create table public.leads (
    id integer primary key,
    professor_experimental_id integer
  );
  create table public.aulas_emusys (
    id integer primary key,
    professor_id integer not null,
    unidade_id uuid not null,
    categoria text not null default 'normal',
    cancelada boolean not null default false,
    data_hora_inicio timestamptz not null default now()
  );
  create table public.aula_alunos_emusys (
    id bigserial primary key,
    aula_emusys_id integer not null,
    unidade_id uuid not null,
    aluno_id integer,
    emusys_lead_id integer
  );
  create table public.lead_experimentais (
    id serial primary key,
    lead_id integer,
    status text,
    unidade_id uuid not null,
    data_experimental date,
    horario_experimental time,
    professor_experimental_id integer,
    aluno_id integer,
    emusys_lead_id integer
  );
  create table public.lead_experimental_aulas (
    id bigserial primary key,
    lead_experimental_id integer not null,
    aula_local_id integer,
    estado text not null,
    motivo_pendencia text,
    casado_por text,
    criado_em timestamptz not null default now(),
    vinculado_em timestamptz,
    vinculado_por text,
    substituido_em timestamptz,
    cancelado_em timestamptz,
    aluno_id integer,
    aluno_vinculado_em timestamptz,
    aluno_vinculado_por text,
    aluno_origem text,
    presenca_status text,
    presenca_respondido_por text,
    presenca_respondido_em timestamptz,
    presenca_bruta_emusys text,
    constraint lead_experimental_aulas_casado_por_check
      check (casado_por is null or casado_por = any (array['chave_natural','manual','emusys_lead_id'])),
    constraint lead_experimental_aulas_estado_check
      check (estado = any (array['pendente','vinculado','manual','realizado','faltou','cancelado'])),
    constraint lead_experimental_aulas_motivo_pendencia_check
      check (motivo_pendencia is null or motivo_pendencia = any (array['sem_par','ambiguo']))
  );
  -- A porta antiga chama este helper (migration 012) ao sincronizar presenca.
  -- Sem ele, TODO lead cai no \`exception when others\` do laco e vira "+1 erro"
  -- em silencio -- foi assim que o primeiro ensaio deu 5 erros e 0 vinculos.
  create function public.fn_presenca_e_forte(p_respondido_por text)
  returns boolean language sql immutable parallel safe as $fn$
    select coalesce(p_respondido_por in (
      'professor_la_teacher','fabio_audio','manual','professor_whatsapp','agenda_secretaria'
    ), false)
  $fn$;
  create unique index uq_lead_exp_aula_vigente on public.lead_experimental_aulas (lead_experimental_id) where (substituido_em is null);
  create unique index uq_lead_exp_aula_ocupada on public.lead_experimental_aulas (aula_local_id) where (aula_local_id is not null and substituido_em is null and estado <> 'cancelado');
`

const mutantes = [
  {
    // O CORACAO. Sem a guarda, a chave natural confere o vinculo do id do lead
    // pela regua dela, nao acha (o professor trocou -- que e o caso todo) e
    // desfaz no mesmo tick o que a porta nova acabou de casar.
    nome: 'a chave natural volta a desfazer o vinculo do id do lead (bloco 3)',
    ancora: "        if not v_soberano and v_vinculo.id is not null and v_vinculo.estado = 'vinculado' then",
    substituicao: "        if v_vinculo.id is not null and v_vinculo.estado = 'vinculado' then",
  },
  {
    // Sobrevive ao bloco 3 mas cai no bloco 4: o re-casamento tenta inserir
    // pendente por cima do vigente, bate no indice e o `exception when others`
    // do laco engole como "+1 erro". O vinculo sobrevive -- so a assercao de
    // `erros = 0` pega isto.
    nome: 'o bloco 4 re-casa por cima do vinculo soberano (erro silencioso)',
    ancora: "        if not v_soberano and (v_vinculo.id is null or v_vinculo.estado <> 'vinculado'",
    substituicao: "        if false or (v_vinculo.id is null or v_vinculo.estado <> 'vinculado'",
  },
  {
    // Soberania virando IMUNIDADE: o vinculo nunca mais e conferido, nem pela
    // chave que o criou. A remarcacao de verdade fica pendurada pra sempre.
    nome: 'soberania vira imunidade (nao confere nem pelo id do lead)',
    ancora: "             and (ae.data_hora_inicio at time zone 'America/Sao_Paulo')::date\n                 = v_lead.data_experimental;\n          if found then",
    substituicao: ';\n          if found then',
  },
  {
    // A aula que chega depois: sem promover, a porta nova tenta INSERT, bate no
    // indice de vigencia e o lead fica preso no 'pendente' pra sempre.
    nome: 'a porta nova deixa de promover o pendente',
    ancora: '        if v_pendente_id is not null then',
    substituicao: '        if false then',
  },
  {
    // A ordem E o contrato: quem chega antes num lead sem vinculo carimba a
    // procedencia. Invertida, a chave natural ganha os casos que as duas
    // alcancam -- e a porta nova vira decoracao.
    nome: 'o tick inverte a ordem (chave natural primeiro)',
    ancora: '    v_por_lead := public.fn_reconciliar_experimental_por_lead(1, p_dias, p_limite);',
    substituicao:
      '    v_natural := public.fn_reconciliar_experimental_aulas(p_dias, p_limite);\n'
      + '    v_por_lead := public.fn_reconciliar_experimental_por_lead(1, p_dias, p_limite);',
  },
  {
    // Guarda ESTRUTURAL, nao comportamental: nao ha como fazer a porta nova
    // falhar dentro do ensaio sem inventar uma falha. O que se afirma aqui e
    // que o handler existe -- e o mutante prova que a assercao o cobra.
    nome: 'a falha da porta nova passa a derrubar a antiga (sem handler)',
    ancora: "  exception when others then\n    -- A porta nova é a ADIÇÃO. Se ela quebrar, a porta que já roda há meses\n    -- não pode cair junto — o erro aparece no resumo e alguém conserta.\n    v_por_lead := jsonb_build_object('ok', false, 'erro', sqlerrm);\n  end;",
    substituicao: '  end;',
  },
]

function extrairTesteDocker(texto) {
  const inicio = texto.indexOf('20260815090000-DOCKER-DML-TESTS-INICIO')
  const fim = texto.indexOf('20260815090000-DOCKER-DML-TESTS-FIM')
  if (inicio === -1 || fim === -1) {
    throw new Error('bloco DOCKER-DML-TESTS nao encontrado no teste')
  }
  return texto.slice(inicio + '20260815090000-DOCKER-DML-TESTS-INICIO'.length, fim)
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

const container = `la-teacher-20260815090000-mutantes-${process.pid}-${Date.now()}`
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
