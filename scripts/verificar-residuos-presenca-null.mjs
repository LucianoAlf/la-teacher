import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { pathToFileURL } from 'node:url'

const PROJETO = 'ouqwbbermlzqqvtqwlul'
const MARCADOR = 'zztest_presenca_null'
const TABELA_META_FUNCAO = '__funcao_fn_materializar_presenca_padrao'
const RUNNER = 'scripts/rodar-teste-sql.mjs'
const MIGRACAO = 'supabase/migrations/20260812135033_fix_presence_json_null_confirmation.sql'
const TESTE = 'supabase/migrations/099-presenca-json-null-confirmation.test.sql'

function literalSql(valor) {
  return `'${valor.replaceAll("'", "''")}'`
}

export function construirConsultaSnapshot(marcador = MARCADOR) {
  if (!/^[a-z][a-z0-9_]{2,63}$/i.test(marcador)) {
    throw new Error('marcador_de_residuo_invalido')
  }

  return `
    with marcador(valor) as (values (${literalSql(marcador)}::text)),
    unidades_marcadas as (
      select un.id
        from public.unidades un cross join marcador m
       where un.codigo = m.valor
    ), usuarios_marcados as (
      select u.id
        from public.usuarios u
       where u.unidade_id in (select un.id from unidades_marcadas un)
    ), professores_marcados as (
      select p.id
        from public.professores p
       where p.usuario_id in (select u.id from usuarios_marcados u)
    ), alunos_marcados as (
      select a.id
        from public.alunos a
       where a.unidade_id in (select un.id from unidades_marcadas un)
          or a.professor_atual_id in (select p.id from professores_marcados p)
    ), aulas_marcadas as (
      select ae.id
        from public.aulas_emusys ae
       where ae.unidade_id in (select un.id from unidades_marcadas un)
          or ae.professor_id in (select p.id from professores_marcados p)
    ), roster_marcado as (
      select aa.id
        from public.aula_alunos_emusys aa
       where aa.unidade_id in (select un.id from unidades_marcadas un)
          or aa.aula_emusys_id in (select ae.id from aulas_marcadas ae)
          or aa.aluno_id in (select a.id from alunos_marcados a)
    ), registros_marcados as (
      select r.id
        from public.fabio_registros_aula r
       where r.unidade_id in (select un.id from unidades_marcadas un)
          or r.professor_id in (select p.id from professores_marcados p)
          or r.aluno_id in (select a.id from alunos_marcados a)
          or r.aula_id in (select ae.id from aulas_marcadas ae)
    ), residuos(tabela, id) as (
      select 'unidades', un.id::text
        from public.unidades un where un.id in (select id from unidades_marcadas)
      union all
      select 'usuarios', u.id::text
        from public.usuarios u where u.id in (select id from usuarios_marcados)
      union all
      select 'professores', p.id::text
        from public.professores p where p.id in (select id from professores_marcados)
      union all
      select 'alunos', a.id::text
        from public.alunos a where a.id in (select id from alunos_marcados)
      union all
      select 'aulas_emusys', ae.id::text
        from public.aulas_emusys ae where ae.id in (select id from aulas_marcadas)
      union all
      select 'aula_alunos_emusys', aa.id::text
        from public.aula_alunos_emusys aa where aa.id in (select id from roster_marcado)
      union all
      select 'fabio_registros_aula', r.id::text
        from public.fabio_registros_aula r where r.id in (select id from registros_marcados)
      union all
      select 'aluno_presenca', ap.id::text
        from public.aluno_presenca ap
       where ap.unidade_id in (select un.id from unidades_marcadas un)
          or ap.professor_id in (select p.id from professores_marcados p)
          or ap.aluno_id in (select a.id from alunos_marcados a)
          or ap.aula_emusys_id in (select ae.id from aulas_marcadas ae)
      union all
      select 'aula_registros_fabio_log', l.id::text
        from public.aula_registros_fabio_log l
       where l.aula_id in (select ae.id from aulas_marcadas ae)
          or l.professor_id in (select p.id from professores_marcados p)
      union all
      select 'fabio_devolutivas', d.id::text
        from public.fabio_devolutivas d
       where d.professor_id in (select p.id from professores_marcados p)
          or d.aluno_id in (select a.id from alunos_marcados a)
          or d.registro_fatia_id in (select r.id from registros_marcados r)
      union all
      select 'fabio_notificacoes', n.id::text
        from public.fabio_notificacoes n
       where n.professor_id in (select p.id from professores_marcados p)
          or (
            n.referencia_tipo = 'registro_aula'
            and n.referencia_id in (select r.id::text from registros_marcados r)
          )
    ), funcao_meta as (
      select md5(pg_get_functiondef(p.oid)) as digest,
             pg_get_userbyid(p.proowner) as owner,
             coalesce((
               select string_agg(permissao::text, ',' order by permissao::text)
                 from unnest(coalesce(p.proacl, '{}'::aclitem[])) as permissoes(permissao)
             ), '<NULL>') as acl,
             coalesce(obj_description(p.oid, 'pg_proc'), '<NULL>') as comment
        from pg_proc p
       where p.oid = 'public.fn_materializar_presenca_padrao(uuid,integer)'::regprocedure
    ), resumo_residuos as (
      select tabela,
             count(*)::integer as linhas,
             coalesce(md5(string_agg(id, '|' order by id)), 'vazio') as digest,
             null::text as owner,
             null::text as acl,
             null::text as comment
        from residuos
       group by tabela
    )
    select tabela, linhas, digest, owner, acl, comment from resumo_residuos
    union all
    select ${literalSql(TABELA_META_FUNCAO)}, 1, digest, owner, acl, comment from funcao_meta
    order by tabela`
}

function objetoPlano(valor) {
  if (valor === null || typeof valor !== 'object' || Array.isArray(valor)) return false
  const prototipo = Object.getPrototypeOf(valor)
  return prototipo === Object.prototype || prototipo === null
}

export function validarRespostaSnapshot(dados) {
  if (!Array.isArray(dados)) throw new Error('resposta_snapshot_invalida')

  return dados.map((linha, indice) => {
    if (!objetoPlano(linha)) throw new Error(`linha_snapshot_invalida_${indice}_objeto`)
    if (typeof linha.tabela !== 'string' || linha.tabela.trim() === '') {
      throw new Error(`linha_snapshot_invalida_${indice}_tabela`)
    }
    if (
      typeof linha.linhas !== 'number'
      || !Number.isFinite(linha.linhas)
      || !Number.isInteger(linha.linhas)
      || linha.linhas < 0
    ) {
      throw new Error(`linha_snapshot_invalida_${indice}_linhas`)
    }
    if (typeof linha.digest !== 'string' || linha.digest.trim() === '') {
      throw new Error(`linha_snapshot_invalida_${indice}_digest`)
    }
    if (
      linha.tabela === TABELA_META_FUNCAO
      && (typeof linha.comment !== 'string' || linha.comment.trim() === '')
    ) {
      throw new Error(`linha_snapshot_invalida_${indice}_comment`)
    }
    if (
      linha.tabela !== TABELA_META_FUNCAO
      && 'comment' in linha
      && linha.comment !== null
    ) {
      throw new Error(`linha_snapshot_invalida_${indice}_comment`)
    }

    const normalizada = {
      tabela: linha.tabela,
      linhas: linha.linhas,
      digest: linha.digest,
    }
    if ('owner' in linha) normalizada.owner = linha.owner
    if ('acl' in linha) normalizada.acl = linha.acl
    if ('comment' in linha) normalizada.comment = linha.comment
    return normalizada
  })
}

function decomporSnapshot(linhas) {
  const metadados = linhas.filter((linha) => linha.tabela === TABELA_META_FUNCAO)
  if (metadados.length !== 1) throw new Error('metadados_funcao_invalidos_quantidade')

  const funcao = metadados[0]
  if (
    funcao.linhas !== 1
    || typeof funcao.owner !== 'string'
    || funcao.owner.trim() === ''
    || typeof funcao.acl !== 'string'
    || funcao.acl.trim() === ''
    || typeof funcao.comment !== 'string'
    || funcao.comment.trim() === ''
  ) {
    throw new Error('metadados_funcao_invalidos_formato')
  }

  return {
    funcao: {
      digest: funcao.digest,
      owner: funcao.owner,
      acl: funcao.acl,
      comment: funcao.comment,
    },
    residuos: linhas.filter((linha) => linha.tabela !== TABELA_META_FUNCAO),
  }
}

export function avaliarSnapshots(antesBruto, depoisBruto) {
  const antes = decomporSnapshot(validarRespostaSnapshot(antesBruto))
  const depois = decomporSnapshot(validarRespostaSnapshot(depoisBruto))
  const residuosAntes = antes.residuos.reduce((total, linha) => total + linha.linhas, 0)
  const residuosDepois = depois.residuos.reduce((total, linha) => total + linha.linhas, 0)
  const erros = []

  if (residuosAntes !== 0) erros.push('residuos_antes_encontrados')
  if (residuosDepois !== 0) erros.push('residuos_depois_encontrados')
  if (
    antes.funcao.digest !== depois.funcao.digest
    || antes.funcao.owner !== depois.funcao.owner
    || antes.funcao.acl !== depois.funcao.acl
    || antes.funcao.comment !== depois.funcao.comment
  ) {
    erros.push('metadados_funcao_nao_restaurados')
  }

  return {
    ok: erros.length === 0,
    erros,
    residuosAntes,
    residuosDepois,
    linhasAntes: antes.residuos,
    linhasDepois: depois.residuos,
    funcaoAntes: antes.funcao,
    funcaoDepois: depois.funcao,
  }
}

export function formatarResumoResiduos(resumos) {
  return resumos
    .map(({ tabela, linhas, digest }) => `${tabela}: ${linhas} linha(s), digest ${digest}`)
    .join('\n')
}

function lerEnv(chave) {
  if (process.env[chave]) return process.env[chave]
  const texto = readFileSync(resolve(process.cwd(), '.env'), 'utf8')
  for (const linha of texto.split(/\r?\n/)) {
    const corte = linha.indexOf('=')
    if (corte < 0 || linha.trimStart().startsWith('#')) continue
    if (linha.slice(0, corte).trim() === chave) {
      return linha.slice(corte + 1).trim().replace(/^["']|["']$/g, '')
    }
  }
  return null
}

async function capturarSnapshot({ token, fetchImpl }) {
  if (!token) throw new Error('SUPABASE_ACCESS_TOKEN_nao_encontrado')

  const resposta = await fetchImpl(
    `https://api.supabase.com/v1/projects/${PROJETO}/database/query`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query: construirConsultaSnapshot() }),
    },
  )
  if (!resposta.ok) throw new Error(`consulta_snapshot_falhou_http_${resposta.status}`)

  const linhas = validarRespostaSnapshot(await resposta.json())
  decomporSnapshot(linhas)
  return linhas
}

function executarRunnerPadrao(migracao, teste) {
  const resultado = spawnSync(process.execPath, [RUNNER, migracao, teste], {
    cwd: process.cwd(),
    encoding: 'utf8',
    maxBuffer: 10 * 1024 * 1024,
  })
  const stderrErro = resultado.error ? `${resultado.error.message}\n` : ''
  return {
    codigo: Number.isInteger(resultado.status) ? resultado.status : 1,
    stdout: typeof resultado.stdout === 'string' ? resultado.stdout : '',
    stderr: `${typeof resultado.stderr === 'string' ? resultado.stderr : ''}${stderrErro}`,
  }
}

function normalizarResultadoRunner(resultado) {
  if (!objetoPlano(resultado)) throw new Error('resultado_runner_invalido')
  if (!Number.isInteger(resultado.codigo) || resultado.codigo < 0) {
    throw new Error('codigo_runner_invalido')
  }
  if (typeof resultado.stdout !== 'string' || typeof resultado.stderr !== 'string') {
    throw new Error('saida_runner_invalida')
  }
  return resultado
}

export async function executarEnsaioPresencaNull({
  migracao = MIGRACAO,
  teste = TESTE,
  token = lerEnv('SUPABASE_ACCESS_TOKEN'),
  fetchImpl = fetch,
  executarRunner = executarRunnerPadrao,
} = {}) {
  const antes = await capturarSnapshot({ token, fetchImpl })
  let runner
  try {
    runner = normalizarResultadoRunner(await executarRunner(migracao, teste))
  } catch (erro) {
    runner = {
      codigo: 1,
      stdout: '',
      stderr: `runner_nao_executado_corretamente: ${erro.message}\n`,
    }
  }
  const depois = await capturarSnapshot({ token, fetchImpl })
  return { runner, prova: avaliarSnapshots(antes, depois) }
}

function imprimirResultado(resultado) {
  if (resultado.runner.stdout) process.stdout.write(resultado.runner.stdout)
  if (resultado.runner.stderr) process.stderr.write(resultado.runner.stderr)

  if (!resultado.prova.ok) {
    console.error(`✗ snapshot presenca-null invalido: ${resultado.prova.erros.join(', ')}`)
    if (resultado.prova.linhasAntes.length > 0) {
      console.error(`antes:\n${formatarResumoResiduos(resultado.prova.linhasAntes)}`)
    }
    if (resultado.prova.linhasDepois.length > 0) {
      console.error(`depois:\n${formatarResumoResiduos(resultado.prova.linhasDepois)}`)
    }
    return false
  }

  console.log(`✓ residuos ${MARCADOR}: 0 antes e 0 depois`)
  console.log(
    `✓ fn_materializar_presenca_padrao restaurada — digest ${resultado.prova.funcaoDepois.digest.slice(0, 12)}…, owner ${resultado.prova.funcaoDepois.owner}, ACL ${resultado.prova.funcaoDepois.acl}`,
  )
  return true
}

async function main() {
  try {
    const resultado = await executarEnsaioPresencaNull()
    const seguro = imprimirResultado(resultado)
    process.exitCode = seguro ? resultado.runner.codigo : 2
  } catch (erro) {
    console.error(`✗ orquestrador presenca-null falhou: ${erro.message}`)
    process.exitCode = 2
  }
}

const executadoDiretamente = process.argv[1]
  && pathToFileURL(resolve(process.argv[1])).href === import.meta.url
if (executadoDiretamente) await main()
