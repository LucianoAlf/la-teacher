// Mutantes 093 — presença padrão só pode nascer na confirmação.
// Cada variante roda em diretório temporário e o runner abre/fecha ROLLBACK
// contra o alvo compartilhado. O processo só aprova quando ambos os mutantes
// morrem pelos asserts reais do contrato.

import { execFileSync } from 'node:child_process'
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/093-presenca-padrao-e-fatias-canonicas.sql'
const TESTE = 'supabase/migrations/093-presenca-padrao-e-fatias-canonicas.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const RUNNER = 'scripts/rodar-teste-sql.mjs'
const fonte = readFileSync(ORIGINAL, 'utf8')
const CHAMADA = '  perform public.fn_materializar_presenca_padrao(p_registro_id, p_professor_id);'
const MARCADOR_DIVERGENCIA = /—\s+\d+\s+passo\(s\)\s+divergiram:/u
const MARCADOR_ROLLBACK_LINHAS = /✓ linhas vivas idênticas antes e depois/u
const MARCADOR_ROLLBACK_SCHEMA = /✓ schema idêntico antes e depois/u
const ANCORA_RASCUNHO = [
  '  end loop;',
  '',
  '  if v_audio_id is not null then',
  "    update public.fabio_fila_audios set status = 'normalizado', atualizado_em = now()",
].join('\n')

function contar(texto, trecho) {
  return texto.split(trecho).length - 1
}

function rodar(migration) {
  try {
    const stdout = execFileSync('node', [RUNNER, migration, TESTE], { stdio: 'pipe' })
    return { codigo: 0, saida: stdout.toString('utf8') }
  } catch (erro) {
    return {
      codigo: erro.status ?? 1,
      saida: Buffer.concat([
        Buffer.isBuffer(erro.stdout) ? erro.stdout : Buffer.from(''),
        Buffer.isBuffer(erro.stderr) ? erro.stderr : Buffer.from(''),
      ]).toString('utf8'),
    }
  }
}

function rollbackConfirmado(saida) {
  return MARCADOR_ROLLBACK_LINHAS.test(saida) && MARCADOR_ROLLBACK_SCHEMA.test(saida)
}

function executarMutante(nome, transformar) {
  let mutante
  try {
    mutante = transformar(fonte)
  } catch (erro) {
    console.log(`STALE  ${nome} — ${erro.message}`)
    return { morto: false, stale: true }
  }

  const diretorio = mkdtempSync(join(tmpdir(), 'la-teacher-mutante-093-'))
  const migration = join(diretorio, '093-mutante.sql')
  try {
    writeFileSync(migration, mutante)
    const resultado = rodar(migration)
    if (resultado.codigo === 0) {
      console.log(`FALHA  SOBREVIVEU: ${nome}`)
      return { morto: false, stale: false, invalido: false }
    }
    if (!MARCADOR_DIVERGENCIA.test(resultado.saida) || !rollbackConfirmado(resultado.saida)) {
      console.log(`INVALIDO ${nome} — falhou sem divergencia estruturada ou rollback confirmado pelo runner`)
      return { morto: false, stale: false, invalido: true }
    }
    console.log(`OK     morto: ${nome}`)
    return { morto: true, stale: false, invalido: false }
  } finally {
    rmSync(diretorio, { recursive: true, force: true })
  }
}

const baseline = rodar(ORIGINAL)
if (baseline.codigo !== 0 || !rollbackConfirmado(baseline.saida)) {
  const tipo = baseline.codigo !== 0 && MARCADOR_DIVERGENCIA.test(baseline.saida)
    ? 'divergencia estruturada'
    : 'erro de infraestrutura/sintaxe/autorizacao/rollback'
  console.log(`BLOQUEADO baseline GREEN falhou (${tipo})`)
  process.exitCode = 1
} else {
const resultados = [
  executarMutante('M1 - confirmacao deixa de materializar presenca', (texto) => {
    if (contar(texto, CHAMADA) !== 1) {
      throw new Error(`ancora da confirmacao aparece ${contar(texto, CHAMADA)} vez(es)`)
    }
    return texto.replace(CHAMADA, '  -- M1: materializacao removida')
  }),
  executarMutante('M2 - materializacao e movida para o rascunho', (texto) => {
    if (contar(texto, CHAMADA) !== 1) {
      throw new Error(`ancora da confirmacao aparece ${contar(texto, CHAMADA)} vez(es)`)
    }
    if (contar(texto, ANCORA_RASCUNHO) !== 1) {
      throw new Error(`ancora do normalizador aparece ${contar(texto, ANCORA_RASCUNHO)} vez(es)`)
    }
    const semConfirmacao = texto.replace(CHAMADA, '  -- M2: materializacao removida da confirmacao')
    return semConfirmacao.replace(
      ANCORA_RASCUNHO,
      [
        '  end loop;',
        '',
        '  -- M2: presenca materializada cedo demais, ainda no rascunho.',
        '  perform public.fn_materializar_presenca_padrao(v_tronco_id, v_professor);',
        '',
        '  if v_audio_id is not null then',
        "    update public.fabio_fila_audios set status = 'normalizado', atualizado_em = now()",
      ].join('\n')
    )
  }),
]

const mortos = resultados.filter((resultado) => resultado.morto).length
const stale = resultados.filter((resultado) => resultado.stale).length
const invalidos = resultados.filter((resultado) => resultado.invalido).length
console.log(`\n${mortos}/${resultados.length} mutantes mortos${stale ? ` — ${stale} ancora(s) stale` : ''}${invalidos ? ` — ${invalidos} invalido(s)` : ''}`)
process.exitCode = mortos === resultados.length && stale === 0 && invalidos === 0 ? 0 : 1
}
