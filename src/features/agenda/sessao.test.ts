import { describe, expect, it } from 'vitest'
import type { AlunoSessao, SessaoAula } from '../../lib/api'
import { agruparSessoes } from './sessao'

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
