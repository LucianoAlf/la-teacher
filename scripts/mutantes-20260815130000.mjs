#!/usr/bin/env node
// Mutacoes do schema "ocorrencia de participacao (substituicao) em shadow".
// Roda num PostgreSQL Docker descartavel: aplica a migration + o bloco DML do
// teste, confere o baseline verde e exige que cada mutante morra POR ASSERCAO
// (nao por erro de sintaxe ou de constraint -- mutante que morre de erro nao
// prova nada sobre o teste).

import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

const MIGRATION = 'supabase/migrations/20260815130000_participacao_ocorrencias_schema.sql'
const TEST = 'supabase/migrations/20260815130000_participacao_ocorrencias_schema.test.sql'
const IMAGE = process.env.MUTANTE_PARTICIPACAO_POSTGRES_IMAGE ?? 'postgres:17-alpine'
const fonte = readFileSync(MIGRATION, 'utf8')
const teste = readFileSync(TEST, 'utf8')
const testeDocker = extrairTesteDocker(teste)

// O bootstrap espelha producao NO QUE ESTA MIGRATION USA: pgcrypto (para o
// gen_random_uuid dos defaults), os tres roles que o revoke/grant nomeiam, e
// uma fn_aula_operacional_id fake que devolve o proprio id (o schema nao a
// chama, mas o bootstrap padrao da frente a inclui e ela nao atrapalha).
const bootstrap = `
  create extension if not exists pgcrypto;
  create role anon;
  create role authenticated;
  create role service_role;

  create function public.fn_aula_operacional_id(p_aula_id integer)
  returns integer language sql immutable as $fn$ select p_aula_id $fn$;
`

const mutantes = [
  {
    // Sem o trigger, o UPDATE/DELETE direto no fato deixa de estourar -- o
    // grant ausente sozinho nao pega quem tem privilegio elevado (dono).
    nome: 'remove o trigger append-only da ocorrencia (UPDATE/DELETE deixa de estourar)',
    ancora: `create trigger trg_participacao_ocorrencias_append_only
  before update or delete on public.fabio_participacao_ocorrencias
  for each row execute function public.fn_participacao_append_only();`,
    substituicao: '',
  },
  {
    // A view expondo o evento cru desfaz o mapa registrada->candidata: as RPCs
    // que devolvem 'candidata' passariam a ver 'registrada'.
    nome: 'a view expoe o evento cru (some o mapa registrada->candidata)',
    ancora: "case e.evento when 'registrada' then 'candidata' else e.evento end as estado_atual",
    substituicao: 'e.evento as estado_atual',
  },
  {
    // Sem a checagem de aula+aluno, o supersede corrige uma ocorrencia
    // aleatoria de outra aula.
    nome: 'remove a coerencia do supersede (corrige ocorrencia de outra aula)',
    ancora: `  if v_ant.aula_operacional_id <> new.aula_operacional_id
     or v_ant.aluno_matriculado_id <> new.aluno_matriculado_id then
    raise exception 'supersede so corrige a MESMA aula operacional e o MESMO aluno matriculado';
  end if;`,
    substituicao: '',
  },
  {
    // Sem o carimbo, a ocorrencia antiga fica viva depois de sobrescrita.
    nome: 'remove o carimbo corrigida na antiga (supersede nao encerra a anterior)',
    ancora: `  insert into public.fabio_participacao_ocorrencia_eventos (ocorrencia_id, evento, por_tipo, por_id, dados)
  values (v_ant.id, 'corrigida', 'sistema', null, jsonb_build_object('corrigida_por', new.id));`,
    substituicao: '',
  },
  {
    // Sem o CHECK, a reentrega do UAZAPI (whatsapp sem message_id) entra e
    // duplica a candidata.
    nome: 'remove o chk_origem_message_id (whatsapp sem message_id entra)',
    ancora: `,
  constraint chk_origem_message_id
    check (origem <> 'whatsapp' or origem_message_id is not null)`,
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

const container = `la-teacher-participacao-mutantes-${process.pid}-${Date.now()}`
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
