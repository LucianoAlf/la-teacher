import { describe, expect, it } from 'vitest'
import {
  avaliarSnapshots,
  construirConsultaSnapshot,
  executarEnsaioPresencaNull,
  formatarResumoResiduos,
  validarRespostaSnapshot,
} from '../../../scripts/verificar-residuos-presenca-null.mjs'

const metaFuncao = {
  tabela: '__funcao_fn_materializar_presenca_padrao',
  linhas: 1,
  digest: '0123456789abcdef0123456789abcdef',
  owner: 'postgres',
  acl: 'postgres=X/postgres',
  comment: 'Comentario exato da funcao',
}

describe('verificador de residuos da presenca JSON null', () => {
  it('parte somente do codigo exato da unidade e segue ids relacionados', () => {
    const sql = construirConsultaSnapshot('zztest_presenca_null')

    expect(sql).not.toMatch(/\bto_jsonb\b|\bilike\b|\blike\b/i)
    expect(sql).not.toMatch(/\.nome\b|\.email\b/i)
    expect(sql).toContain('un.codigo = m.valor')
    expect(sql).toContain('public.usuarios')
    expect(sql).toContain('public.professores')
    expect(sql).toContain('public.alunos')
    expect(sql).toContain('public.aulas_emusys')
    expect(sql).toContain('public.aula_alunos_emusys')
    expect(sql).toContain('public.fabio_registros_aula')
    expect(sql).toContain('public.aluno_presenca')
    expect(sql).toContain('public.aula_registros_fabio_log')
    expect(sql).toContain('public.fabio_devolutivas')
    expect(sql).toContain('public.fabio_notificacoes')
    expect(sql).toContain("md5(pg_get_functiondef(p.oid))")
    expect(sql).toContain('pg_get_userbyid(p.proowner)')
    expect(sql).toContain('p.proacl')
    expect(sql).toContain("obj_description(p.oid, 'pg_proc')")
  })

  it('aceita somente linhas de snapshot estritamente tipadas', () => {
    expect(validarRespostaSnapshot([metaFuncao])).toEqual([metaFuncao])
  })

  it.each([
    ['linhas ausente', { tabela: 'unidades', digest: 'abc' }],
    ['linhas NaN', { tabela: 'unidades', linhas: Number.NaN, digest: 'abc' }],
    ['linhas infinita', { tabela: 'unidades', linhas: Number.POSITIVE_INFINITY, digest: 'abc' }],
    ['linhas texto', { tabela: 'unidades', linhas: 'garbage', digest: 'abc' }],
    ['linhas negativa', { tabela: 'unidades', linhas: -1, digest: 'abc' }],
    ['digest ausente', { tabela: 'unidades', linhas: 1 }],
    ['digest vazio', { tabela: 'unidades', linhas: 1, digest: '   ' }],
    ['tabela vazia', { tabela: ' ', linhas: 1, digest: 'abc' }],
    ['linha nao objeto', ['unidades', 1, 'abc']],
  ])('rejeita %s', (_caso, linha) => {
    expect(() => validarRespostaSnapshot([linha])).toThrow('linha_snapshot_invalida')
  })

  it.each([null, {}, 'garbage', 1])('rejeita top-level invalido: %j', (resposta) => {
    expect(() => validarRespostaSnapshot(resposta)).toThrow('resposta_snapshot_invalida')
  })

  it('compara residuos e metadados exatos da funcao', () => {
    const limpo = avaliarSnapshots([metaFuncao], [metaFuncao])
    expect(limpo).toMatchObject({ ok: true, residuosAntes: 0, residuosDepois: 0 })

    const alterado = avaliarSnapshots(
      [metaFuncao],
      [{ ...metaFuncao, acl: 'authenticated=X/postgres' }],
    )
    expect(alterado.ok).toBe(false)
    expect(alterado.erros).toContain('metadados_funcao_nao_restaurados')
  })

  it('reprova quando o comentario da funcao muda', () => {
    const alterado = avaliarSnapshots(
      [metaFuncao],
      [{ ...metaFuncao, comment: 'Comentario alterado' }],
    )

    expect(alterado.ok).toBe(false)
    expect(alterado.erros).toContain('metadados_funcao_nao_restaurados')
  })

  it.each([null, 7, {}, undefined])('rejeita comentario malformado: %j', (comment) => {
    const linha = { ...metaFuncao, comment }
    expect(() => validarRespostaSnapshot([linha])).toThrow('linha_snapshot_invalida_0_comment')
  })

  it('captura snapshot depois mesmo quando o runner falha e devolve seu resultado', async () => {
    const eventos: string[] = []
    const snapshots = [[metaFuncao], [metaFuncao]]
    let chamada = 0
    const resultado = await executarEnsaioPresencaNull({
      token: 'token-de-teste',
      fetchImpl: async () => {
        eventos.push(`snapshot-${chamada + 1}`)
        return {
          ok: true,
          status: 200,
          json: async () => snapshots[chamada++],
        }
      },
      executarRunner: () => {
        eventos.push('runner')
        return { codigo: 7, stdout: 'saida estruturada', stderr: 'erro controlado' }
      },
    })

    expect(eventos).toEqual(['snapshot-1', 'runner', 'snapshot-2'])
    expect(resultado.runner).toEqual({
      codigo: 7,
      stdout: 'saida estruturada',
      stderr: 'erro controlado',
    })
    expect(resultado.prova.ok).toBe(true)
  })

  it('formata somente tabela, contagem e digest mesmo se receber corpo extra', () => {
    const saida = formatarResumoResiduos([
      { tabela: 'professores', linhas: 1, digest: 'abc123', linha: 'SEGREDO_REAL' },
    ])

    expect(saida).toContain('professores: 1 linha(s), digest abc123')
    expect(saida).not.toContain('SEGREDO_REAL')
  })
})
