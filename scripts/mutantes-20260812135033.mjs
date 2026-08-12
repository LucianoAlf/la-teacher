// Mutantes da regressao presenca JSON null. Cada ensaio passa pelo mesmo
// orquestrador que captura residuos e metadados da funcao antes e depois.

import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import { executarEnsaioPresencaNull } from './verificar-residuos-presenca-null.mjs'

const ORIGINAL = 'supabase/migrations/20260812135033_fix_presence_json_null_confirmation.sql'
const TESTE = 'supabase/migrations/099-presenca-json-null-confirmation.test.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')
const PREDICADO = "       and public.fn_presenca_declarada(coalesce(f.campos, '{}'::jsonb)) = 'nao_informada'"
const MARCADOR_DIVERGENCIA = /—\s+\d+\s+passo\(s\)\s+divergiram:/u
const MARCADOR_ROLLBACK_LINHAS = /✓ linhas vivas idênticas antes e depois/u
const MARCADOR_ROLLBACK_SCHEMA = /✓ schema idêntico antes e depois/u

function contar(texto, trecho) {
  return texto.split(trecho).length - 1
}

async function rodar(migracao) {
  try {
    const resultado = await executarEnsaioPresencaNull({ migracao, teste: TESTE })
    return {
      codigo: resultado.runner.codigo,
      saida: `${resultado.runner.stdout}${resultado.runner.stderr}`,
      prova: resultado.prova,
      erroHarness: null,
    }
  } catch (erro) {
    return {
      codigo: 2,
      saida: '',
      prova: null,
      erroHarness: erro.message,
    }
  }
}

function rollbackConfirmado(saida) {
  return MARCADOR_ROLLBACK_LINHAS.test(saida)
    && MARCADOR_ROLLBACK_SCHEMA.test(saida)
}

function snapshotConfirmado(resultado) {
  return resultado.prova?.ok === true
    && resultado.prova.residuosAntes === 0
    && resultado.prova.residuosDepois === 0
}

async function executarMutante(nome, substituto) {
  if (contar(fonte, PREDICADO) !== 1) {
    console.log(`STALE  ${nome} — ancora aparece ${contar(fonte, PREDICADO)} vez(es)`)
    return false
  }

  const diretorio = mkdtempSync(join(tmpdir(), 'la-teacher-mutante-presenca-null-'))
  const migracao = join(diretorio, 'mutante.sql')
  try {
    writeFileSync(migracao, fonte.replace(PREDICADO, substituto))
    const resultado = await rodar(migracao)
    if (resultado.erroHarness || !snapshotConfirmado(resultado)) {
      console.log(`INVALIDO ${nome} — snapshot/API invalido, com residuo ou metadado nao restaurado`)
      return false
    }
    if (resultado.codigo === 0) {
      console.log(`FALHA  SOBREVIVEU: ${nome}`)
      return false
    }
    if (!MARCADOR_DIVERGENCIA.test(resultado.saida) || !rollbackConfirmado(resultado.saida)) {
      console.log(`INVALIDO ${nome} — falhou sem divergencia estruturada ou rollback comprovado`)
      return false
    }
    console.log(`OK     morto: ${nome}; residuos 0/0 e funcao restaurada`)
    return true
  } finally {
    rmSync(diretorio, { recursive: true, force: true })
  }
}

const baseline = await rodar(ORIGINAL)
if (
  baseline.codigo !== 0
  || baseline.erroHarness
  || !rollbackConfirmado(baseline.saida)
  || !snapshotConfirmado(baseline)
) {
  console.log('BLOQUEADO baseline GREEN, snapshot ou restauracao da funcao falhou')
  process.exitCode = 1
} else {
  console.log('OK     baseline GREEN; residuos 0/0 e funcao restaurada')
  const resultados = []
  resultados.push(await executarMutante(
    'M1 - volta a testar apenas a existencia da chave',
    "       and not (coalesce(f.campos, '{}'::jsonb) ? 'presenca')",
  ))
  resultados.push(await executarMutante(
    'M2 - sobrescreve qualquer presenca, inclusive ausencia explicita',
    '       and true',
  ))
  const mortos = resultados.filter(Boolean).length
  console.log(`\n${mortos}/${resultados.length} mutantes mortos`)
  process.exitCode = mortos === resultados.length ? 0 : 1
}
