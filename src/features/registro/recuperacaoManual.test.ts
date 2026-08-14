import { describe, expect, it } from 'vitest'
import { montarFatiaCache, recuperarCamposFatia } from './recuperacaoManual'

describe('recuperação do registro manual na tela de confirmação', () => {
  it('traz de volta o texto local que não sincronizou, sem apagar a presença do servidor', () => {
    // O save do texto falhou (conexão caiu): o servidor só tem a presença e um
    // valor antigo; o cache local tem o que o professor acabou de digitar.
    const servidor = { presenca: 'presente', objetivo: 'antigo' }
    const local = { objetivo: 'Faltou luz', atividades: 'escala de dó' }
    expect(recuperarCamposFatia(servidor, local)).toEqual({
      presenca: 'presente',
      objetivo: 'Faltou luz',
      atividades: 'escala de dó',
    })
  })

  it('monta a fatia do cache só com os campos pedagógicos (compatível com o Caderno)', () => {
    const fatia = {
      id: 'f1',
      aluno_id: 5,
      aluno_nome: 'Ana Paula',
      aluno_foto_url: null,
      versao: 2,
      campos: { objetivo: 'x', presenca: 'presente', progresso: 'y' },
    }
    expect(montarFatiaCache(fatia)).toEqual({
      id: 'f1',
      alunoId: 5,
      alunoNome: 'Ana Paula',
      alunoFotoUrl: null,
      versao: 2,
      campos: { objetivo: 'x', progresso: 'y' },
    })
  })

  it('preenche defaults quando a fatia vem sem aluno vinculado', () => {
    const fatia = { id: 'f2', campos: {} }
    expect(montarFatiaCache(fatia)).toEqual({
      id: 'f2',
      alunoId: 0,
      alunoNome: 'Aluno',
      alunoFotoUrl: null,
      versao: 1,
      campos: {},
    })
  })
})
