// Mutantes 094 - a baseline precisa estar verde, cada mutacao precisa divergir
// pelo resumo estruturado e cada ensaio precisa provar ROLLBACK completo.

import { execFileSync } from 'node:child_process'
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'

const DEPENDENCIA = 'supabase/migrations/093-presenca-padrao-e-fatias-canonicas.sql'
const ORIGINAL = 'supabase/migrations/094-falhas-e-correcoes-auditadas.sql'
const TESTE = 'supabase/migrations/094-falhas-e-correcoes-auditadas.test.sql'
const RUNNER = 'scripts/rodar-teste-sql.mjs'
const fonte = readFileSync(ORIGINAL, 'utf8')
const MUTANTES_SELECIONADOS = new Set(
  (process.env.MUTANTE_094_APENAS ?? '').split(',').map((id) => id.trim()).filter(Boolean),
)
const MARCADOR_DIVERGENCIA = /—\s+\d+\s+passo\(s\) divergiram:/u
const MARCADOR_ROLLBACK_LINHAS = /linhas vivas idênticas antes e depois/u
const MARCADOR_ROLLBACK_SCHEMA = /schema idêntico antes e depois/u
const ANCORA_RETRY = "       and f.erro_tipo = 'transitorio'\n"
const ANCORA_AUDIO_TERMINAL = [
  '    -- 094-GUARDA-AUDIO-TERMINAL-INICIO',
  "    if v_audio_status = 'erro_terminal'",
  "       or v_audio_erro_tipo = 'semantico_terminal' then",
  "      raise exception 'audio_terminal_nao_normalizavel';",
  '    end if;',
  '    -- 094-GUARDA-AUDIO-TERMINAL-FIM',
].join('\n')
const ANCORA_AUDITORIA = [
  '  -- 094-AUDIT-REGISTRO-INICIO',
  '  insert into public.fabio_registro_correcoes(',
  '    registro_id, professor_id, autor_usuario_id, canal, antes, depois, motivo',
  '  ) values (',
  '    v_registro.id, p_professor_id, v_autor_usuario_id, p_canal,',
  '    v_antes, v_depois, left(btrim(p_motivo), 500)',
  '  );',
  '  -- 094-AUDIT-REGISTRO-FIM',
].join('\n')
const ANCORA_GUARDA = [
  '  -- 094-GUARDA-STATUS-DEVOLUTIVA-INICIO',
  "  if v_devolutiva.status not in ('gerada', 'oferecida')",
  '     or v_devolutiva.compartilhada_em is not null',
  '     or v_devolutiva.envio_confirmado_em is not null then',
  "    raise exception 'devolutiva_status_nao_editavel';",
  '  end if;',
  '  -- 094-GUARDA-STATUS-DEVOLUTIVA-FIM',
].join('\n')
const ANCORA_LEDGER_UNICO = '  constraint fabio_correcoes_acoes_tipo_acao_id_key unique (tipo, acao_id)\n'
const ANCORA_REPLAY_REGISTRO = [
  '  -- 094-REPLAY-REGISTRO-CONFLITO-INICIO',
  '  exception when unique_violation then',
  '    select * into v_acao',
  '      from public.fabio_correcoes_acoes',
  "     where tipo = 'registro_confirmado'",
  '       and acao_id = v_chave_acao;',
  '    if not found then',
  "      raise exception 'acao_correcao_concorrente';",
  '    end if;',
  '    if v_acao.professor_id is distinct from p_professor_id',
  '       or v_acao.alvo_id is distinct from p_registro_id',
  '       or v_acao.canal is distinct from p_canal',
  '       or v_acao.requisicao is distinct from v_requisicao then',
  "      raise exception 'acao_id_reutilizada_para_outra_correcao';",
  '    end if;',
  '    if v_acao.resultado is null then',
  "      raise exception 'acao_correcao_sem_resultado';",
  '    end if;',
  '    return v_acao.resultado;',
  '  -- 094-REPLAY-REGISTRO-CONFLITO-FIM',
].join('\n')
const ANCORA_REPLAY_DEVOLUTIVA = [
  '  -- 094-REPLAY-DEVOLUTIVA-CONFLITO-INICIO',
  '  exception when unique_violation then',
  '    select * into v_acao',
  '      from public.fabio_correcoes_acoes',
  "     where tipo = 'devolutiva_rascunho'",
  '       and acao_id = v_chave_acao;',
  '    if not found then',
  "      raise exception 'acao_correcao_concorrente';",
  '    end if;',
  '    if v_acao.professor_id is distinct from p_professor_id',
  '       or v_acao.alvo_id is distinct from p_devolutiva_id',
  '       or v_acao.canal is distinct from p_canal',
  '       or v_acao.requisicao is distinct from v_requisicao then',
  "      raise exception 'acao_id_reutilizada_para_outra_correcao';",
  '    end if;',
  '    if v_acao.resultado is null then',
  "      raise exception 'acao_correcao_sem_resultado';",
  '    end if;',
  '    return v_acao.resultado;',
  '  -- 094-REPLAY-DEVOLUTIVA-CONFLITO-FIM',
].join('\n')

function contar(texto, trecho) {
  return texto.split(trecho).length - 1
}

function rodar(migration) {
  try {
    const stdout = execFileSync('node', [RUNNER, DEPENDENCIA, migration, TESTE], { stdio: 'pipe' })
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
  if (MUTANTES_SELECIONADOS.size > 0 && !MUTANTES_SELECIONADOS.has(nome.slice(0, 2))) {
    return null
  }
  let mutante
  try {
    mutante = transformar(fonte)
  } catch (erro) {
    console.log(`STALE  ${nome} - ${erro.message}`)
    return { morto: false, stale: true, invalido: false }
  }

  const diretorio = mkdtempSync(join(tmpdir(), 'la-teacher-mutante-094-'))
  const migration = join(diretorio, '094-mutante.sql')
  try {
    writeFileSync(migration, mutante)
    const resultado = rodar(migration)
    if (resultado.codigo === 0) {
      console.log(`FALHA  SOBREVIVEU: ${nome}`)
      return { morto: false, stale: false, invalido: false }
    }
    if (!MARCADOR_DIVERGENCIA.test(resultado.saida) || !rollbackConfirmado(resultado.saida)) {
      console.log(`INVALIDO ${nome} - falhou sem divergencia estruturada ou rollback confirmado`)
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
    executarMutante('M0 - callback terminal perde a guarda antes de normalizar', (texto) => {
      if (contar(texto, ANCORA_AUDIO_TERMINAL) !== 1) throw new Error('ancora da guarda terminal nao e unica')
      return texto.replace(ANCORA_AUDIO_TERMINAL, '    -- M0: callback terminal sem guarda\n')
    }),
    executarMutante('M1 - retry perde o filtro erro_tipo transitorio', (texto) => {
      if (contar(texto, ANCORA_RETRY) !== 1) throw new Error('ancora do filtro de retry nao e unica')
      return texto.replace(ANCORA_RETRY, '       -- M1: retry sem tipo transitorio\n')
    }),
    executarMutante('M2 - correcao perde a auditoria', (texto) => {
      if (contar(texto, ANCORA_AUDITORIA) !== 1) throw new Error('ancora da auditoria nao e unica')
      return texto.replace(ANCORA_AUDITORIA, '  -- M2: auditoria removida\n')
    }),
    executarMutante('M3 - devolutiva perde a guarda de status', (texto) => {
      if (contar(texto, ANCORA_GUARDA) !== 1) throw new Error('ancora da guarda de status nao e unica')
      return texto.replace(ANCORA_GUARDA, '  -- M3: status sem guarda\n')
    }),
    executarMutante('M4 - ledger de correcao perde a unicidade da acao', (texto) => {
      if (contar(texto, ANCORA_LEDGER_UNICO) !== 1) throw new Error('ancora da unicidade do ledger nao e unica')
      return texto.replace(
        ANCORA_LEDGER_UNICO,
        '  constraint fabio_correcoes_acoes_tipo_acao_id_key check (true)\n',
      )
    }),
    executarMutante('M5 - correcao perde o ramo de replay do ledger', (texto) => {
      if (contar(texto, ANCORA_REPLAY_REGISTRO) !== 1) throw new Error('ancora do replay de registro nao e unica')
      return texto.replace(
        ANCORA_REPLAY_REGISTRO,
        [
          '  -- M5: replay de registro removido',
          '  exception when unique_violation then',
          "    raise exception 'M5_replay_registro_removido';",
        ].join('\n'),
      )
    }),
    executarMutante('M6 - devolutiva perde o ramo de replay do ledger', (texto) => {
      if (contar(texto, ANCORA_REPLAY_DEVOLUTIVA) !== 1) throw new Error('ancora do replay de devolutiva nao e unica')
      return texto.replace(
        ANCORA_REPLAY_DEVOLUTIVA,
        [
          '  -- M6: replay de devolutiva removido',
          '  exception when unique_violation then',
          "    raise exception 'M6_replay_devolutiva_removido';",
        ].join('\n'),
      )
    }),
  ].filter(Boolean)

  if (MUTANTES_SELECIONADOS.size > 0 && resultados.length !== MUTANTES_SELECIONADOS.size) {
    console.log('BLOQUEADO filtro de mutantes contem identificador desconhecido')
    process.exitCode = 1
  } else {

    const mortos = resultados.filter((resultado) => resultado.morto).length
    const stale = resultados.filter((resultado) => resultado.stale).length
    const invalidos = resultados.filter((resultado) => resultado.invalido).length
    console.log(`\n${mortos}/${resultados.length} mutantes mortos${stale ? ` - ${stale} ancora(s) stale` : ''}${invalidos ? ` - ${invalidos} invalido(s)` : ''}`)
    process.exitCode = mortos === resultados.length && stale === 0 && invalidos === 0 ? 0 : 1
  }
}
