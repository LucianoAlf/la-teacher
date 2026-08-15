#!/usr/bin/env node
// Mutacoes da fila de espera "o audio guardado entra sozinho quando a vez dele
// chega". PostgreSQL Docker descartavel; cada mutante precisa morrer POR
// ASSERCAO.

import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

const MIGRATION = 'supabase/migrations/20260815110000_o_audio_guardado_entra_sozinho_quando_a_vez_dele_chega.sql'
const TEST = 'supabase/migrations/20260815110000_o_audio_guardado_entra_sozinho_quando_a_vez_dele_chega.test.sql'
const IMAGE = process.env.MUTANTE_PARQUEADOS_POSTGRES_IMAGE ?? 'postgres:17-alpine'
const fonte = readFileSync(MIGRATION, 'utf8')
const teste = readFileSync(TEST, 'utf8')
const testeDocker = extrairTesteDocker(teste)

const bootstrap = `
  create extension if not exists pgcrypto;
  create role anon;
  create role authenticated;
  create role service_role;
`

const mutantes = [
  {
    // Indice unico e ON CONFLICT sao UM contrato: tirar so um faz o ensaio
    // morrer de erro, e mutante que morre de erro nao prova nada sobre o
    // teste. Este tira os DOIS -- ai a duplicata ENTRA de verdade e quem tem
    // que pegar e a assercao de "linhas=2".
    nome: 'a reentrega do UAZAPI vira segunda linha (sem idempotencia)',
    edicoes: [
      {
        ancora: `  on conflict (professor_id, wa_message_id) do nothing
  returning id into v_id;`,
        substituicao: '  returning id into v_id;',
      },
      {
        ancora: `create unique index if not exists uq_fabio_audio_parqueado_mensagem
  on public.fabio_audios_parqueados (professor_id, wa_message_id);`,
        substituicao: '',
      },
    ],
  },
  {
    // LIFO: atende a aula das 13h antes da de 12h. A conversa sobre a primeira
    // aula chega depois do fato.
    nome: 'a fila vira LIFO (atende o mais novo primeiro)',
    ancora: '      order by a.criado_em, a.id',
    substituicao: '      order by a.criado_em desc, a.id desc',
  },
  {
    // Sem o recorte por professor, o audio de um professor entra na conversa
    // de outro.
    nome: 'a fila de um professor vaza pra outro',
    ancora: '      where a.professor_id = p_professor_id\n        and a.consumido_em is null',
    substituicao: '      where a.consumido_em is null',
  },
  {
    // Consumido continua aparecendo como "da vez": o mesmo audio vira acao a
    // cada mensagem, pra sempre.
    nome: 'o audio consumido continua na vez',
    ancora: '        and a.consumido_em is null\n        and a.descartado_em is null\n      order by a.criado_em, a.id',
    substituicao: '        and a.descartado_em is null\n      order by a.criado_em, a.id',
  },
  {
    // Descartado volta pra fila -- o professor mandou ignorar e o Fabio
    // pergunta de novo.
    nome: 'o audio descartado volta pra fila',
    ancora: `      where a.professor_id = p_professor_id
        and a.consumido_em is null
        and a.descartado_em is null`,
    substituicao: `      where a.professor_id = p_professor_id
        and a.consumido_em is null`,
  },
  {
    // Sem a guarda no UPDATE, dois processos no mesmo ciclo consomem o mesmo
    // audio e ele vira DUAS acoes.
    nome: 'consumir deixa de ser atomico (o mesmo audio vira duas acoes)',
    ancora: `   where id = p_id
     and consumido_em is null
     and descartado_em is null;
  get diagnostics v_ok = row_count;
  -- Carimbo atômico`,
    substituicao: `   where id = p_id;
  get diagnostics v_ok = row_count;
  -- Carimbo atômico`,
  },
  {
    // Descartar por cima de consumido/descartado: reescreve historia.
    nome: 'descartar reescreve audio ja resolvido',
    ancora: `   where id = p_id
     and consumido_em is null
     and descartado_em is null;
  get diagnostics v_ok = row_count;
  return jsonb_build_object('ok', coalesce(v_ok, false));
end
$function$;

comment on function public.fabio_audio_parqueado_descartar`,
    substituicao: `   where id = p_id;
  get diagnostics v_ok = row_count;
  return jsonb_build_object('ok', coalesce(v_ok, false));
end
$function$;

comment on function public.fabio_audio_parqueado_descartar`,
  },
  {
    // Parametro vazio vira linha: storage_path em branco = audio que nao
    // existe ocupando a vez da fila pra sempre.
    nome: 'aceita parquear sem storage_path',
    ancora: `  if p_professor_id is null or coalesce(btrim(p_wa_message_id), '') = ''
     or coalesce(btrim(p_storage_path), '') = '' then
    return jsonb_build_object('ok', false, 'erro', 'parametros_obrigatorios');
  end if;
`,
    substituicao: '',
  },
]

function extrairTesteDocker(texto) {
  const inicio = texto.indexOf('PARQUEADOS-DOCKER-DML-TESTS-INICIO')
  const fim = texto.indexOf('PARQUEADOS-DOCKER-DML-TESTS-FIM')
  if (inicio === -1 || fim === -1) throw new Error('bloco DOCKER-DML-TESTS nao encontrado no teste')
  return texto.slice(inicio + 'PARQUEADOS-DOCKER-DML-TESTS-INICIO'.length, fim)
}

function executar(args, input) {
  return spawnSync('docker', args, { cwd: process.cwd(), encoding: 'utf8', input, maxBuffer: 4 * 1024 * 1024 })
}

function contar(texto, trecho) {
  return texto.split(trecho).length - 1
}

function mutar(mutante) {
  const edicoes = mutante.edicoes ?? [{ ancora: mutante.ancora, substituicao: mutante.substituicao }]
  let texto = fonte
  for (const edicao of edicoes) {
    const ocorrencias = contar(texto, edicao.ancora)
    if (ocorrencias !== 1) throw new Error(`${mutante.nome}: ancora apareceu ${ocorrencias} vez(es)`)
    texto = texto.replace(edicao.ancora, edicao.substituicao)
  }
  return texto
}

function esperarPronto(container) {
  for (let tentativa = 0; tentativa < 40; tentativa += 1) {
    const pronto = executar(['exec', container, 'pg_isready', '-h', '127.0.0.1', '-p', '5432', '-U', 'postgres', '-d', 'postgres'])
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

const container = `la-teacher-parqueados-mutantes-${process.pid}-${Date.now()}`
let iniciado = false
let mortos = 0
let invalido = false

try {
  const inicio = executar(['run', '--rm', '--detach', '--name', container, '--env', 'POSTGRES_HOST_AUTH_METHOD=trust', IMAGE])
  if (inicio.status !== 0) throw new Error(inicio.error?.message ?? inicio.stderr ?? 'docker run falhou')
  iniciado = true
  esperarPronto(container)

  const pronto = executar([
    'exec', '-i', container,
    'psql', '-h', '127.0.0.1', '-p', '5432', '-X', '-v', 'ON_ERROR_STOP=1', '-qAt', '-U', 'postgres', '-d', 'postgres',
  ], bootstrap)
  if (pronto.status !== 0) throw new Error(pronto.error?.message ?? pronto.stderr ?? 'bootstrap local falhou')

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
