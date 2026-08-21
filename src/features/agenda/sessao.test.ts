import { describe, expect, it } from 'vitest'
import type { AlunoSessao, SessaoAula } from '../../lib/api'
import { agruparSessoes, AVISO_EXPERIMENTAL_SEM_VINCULO, destinoSessao } from './sessao'

const aluno = (id: number, nome: string): AlunoSessao => ({
  aluno_id: id,
  nome,
  presenca: 'a_confirmar',
  tem_presenca_registrada: false,
  tem_registro: false,
  justificada: false,
})

const sessao = (
  aulaId: number,
  tipo: SessaoAula['tipo'],
  alunos: AlunoSessao[],
): SessaoAula => ({
  aula_id_ancora: aulaId,
  hora: '14:00',
  hora_fim: '15:00',
  data_hora_inicio: '2026-08-12T17:00:00.000Z',
  data_hora_fim: '2026-08-12T18:00:00.000Z',
  curso: 'Guitarra T',
  turma_nome: tipo === 'turma' ? 'G_Qua_14' : null,
  tipo,
  n_alunos: alunos.length,
  n_registradas: 0,
  roster_incompleto: false,
  alunos,
})

describe('agruparSessoes', () => {
  it('suprime turma vazia legada quando outra turma do slot tem roster', () => {
    const hugo = aluno(10, 'Hugo')
    const resultado = agruparSessoes([
      sessao(100, 'turma', []),
      sessao(200, 'turma', [hugo]),
      sessao(201, 'individual', [hugo]),
    ])

    expect(resultado).toHaveLength(1)
    expect(resultado[0].alunos.map((item) => item.nome)).toEqual(['Hugo'])
    expect(resultado[0].aula_id_chamada).toBe(200)
  })

  it('suprime turma vazia quando a única concorrente com roster é reagendada individual', () => {
    const arthur = aluno(20, 'Arthur')
    const resultado = agruparSessoes([
      sessao(300, 'turma', []),
      sessao(301, 'individual', [arthur]),
    ])

    expect(resultado).toHaveLength(1)
    expect(resultado[0].aula_id_ancora).toBe(301)
    expect(resultado[0].alunos.map((item) => item.nome)).toEqual(['Arthur'])
  })

  it('mantém turma vazia quando não existe concorrente com roster', () => {
    const resultado = agruparSessoes([sessao(400, 'turma', [])])

    expect(resultado).toHaveLength(1)
    expect(resultado[0].aula_id_ancora).toBe(400)
  })
})

describe('destinoSessao — a régua da experimental, uma só para todas as telas', () => {
  const base = sessao(500, 'individual', [aluno(1, 'Thiago Fernandes Rios')])
  const ACOES = ['chamada', 'gravar', 'manual'] as const

  it('aula normal vai pra porta certa de cada ação', () => {
    expect(destinoSessao(base, 'gravar')).toEqual({ tipo: 'navegar', rota: '/app/gravar/500' })
    expect(destinoSessao(base, 'chamada')).toEqual({ tipo: 'navegar', rota: '/app/chamada/500' })
    expect(destinoSessao(base, 'manual')).toEqual({ tipo: 'navegar', rota: '/app/registro-manual/500' })
  })

  it('experimental COM vínculo vai pra porta própria — nunca a do aluno', () => {
    const exp = { ...base, experimental: true, vinculo_id: 77 }
    for (const acao of ACOES) {
      expect(destinoSessao(exp, acao)).toEqual({ tipo: 'navegar', rota: '/app/experimental/77' })
    }
  })

  it('experimental SEM vínculo avisa e não abre porta nenhuma', () => {
    const exp = { ...base, experimental: true, vinculo_id: null }
    for (const acao of ACOES) {
      expect(destinoSessao(exp, acao)).toEqual({ tipo: 'aviso', texto: AVISO_EXPERIMENTAL_SEM_VINCULO })
    }
  })

  it('REGRESSÃO 20/08 (Thiago, na Home): experimental NUNCA cai em /app/gravar', () => {
    // A Home mandava a experimental direto pra /app/gravar (porta do aluno),
    // onde o banco recusa com aula_experimental_usa_porta_propria. A régua tem
    // que impedir isso em QUALQUER tela que a use — com ou sem vínculo.
    for (const vinculo_id of [9, null]) {
      const exp = { ...base, experimental: true, vinculo_id }
      const d = destinoSessao(exp, 'gravar')
      const rota = d.tipo === 'navegar' ? d.rota : ''
      expect(rota.startsWith('/app/gravar/')).toBe(false)
    }
  })
})
