import { describe, expect, it } from 'vitest'
import {
  assinaturaIntencaoDevolutiva,
  LIMITE_TENTATIVAS_AUTOMATICAS,
  RETRY_AUTOMATICO_ATRASOS_MS,
  descreverFalhaFila,
  nomeCabecalho,
  proximaTentativaAutomatica,
  repertorioIndividualVisivel,
  retryAutomaticoPermitido,
  rotuloRegistro,
  textoEquivalente,
} from './camposCanonicos'

describe('campos canônicos da interface', () => {
  it('compara texto pedagógico sem diferença só de caixa ou espaços', () => {
    expect(textoEquivalente(' Prelude em Do ', 'prelude EM do')).toBe(true)
  })

  it('não repete o repertório individual que já é o da turma', () => {
    expect(repertorioIndividualVisivel('Titanic', 'Titanic')).toBe(false)
  })

  it('usa apenas o primeiro nome no cabeçalho', () => {
    expect(nomeCabecalho({ nome: 'Isaque Mendes', email: '5521...' })).toBe('Isaque')
  })

  it('anuncia o rascunho antes da confirmação como estado próprio', () => {
    expect(rotuloRegistro({ temRegistro: false, temRascunho: true })).toBe('Rascunho pronto')
  })

  it('mantém o rascunho visível mesmo quando já existe um registro anterior', () => {
    expect(rotuloRegistro({ temRegistro: true, temRascunho: true })).toBe('Rascunho pronto')
  })

  it('mantém a contagem e a mensagem da última falha da fila', () => {
    expect(descreverFalhaFila({ ultimaFalha: 'timeout', tentativas: 2 })).toContain('2 tentativas')
  })

  it('para o retry automático no limite e pede uma decisão humana', () => {
    expect(retryAutomaticoPermitido({ transitoria: true, tentativas: LIMITE_TENTATIVAS_AUTOMATICAS - 1 })).toBe(true)
    expect(retryAutomaticoPermitido({ transitoria: true, tentativas: LIMITE_TENTATIVAS_AUTOMATICAS })).toBe(false)
    expect(descreverFalhaFila({ ultimaFalha: 'timeout', tentativas: LIMITE_TENTATIVAS_AUTOMATICAS })).toContain(
      'aguarda sua decisão',
    )
  })

  it('agenda o próximo retry transitório com backoff observável', () => {
    const agora = Date.parse('2026-08-11T12:00:00.000Z')
    expect(
      proximaTentativaAutomatica(
        {
          retryAutomatico: true,
          tentativas: 1,
          ultimaTentativaEm: new Date(agora).toISOString(),
        },
        agora,
      ),
    ).toBe(agora + RETRY_AUTOMATICO_ATRASOS_MS[0])
  })

  it('não agenda retry depois do teto, mesmo se o estado legado disser que pode', () => {
    expect(
      proximaTentativaAutomatica({
        retryAutomatico: true,
        tentativas: LIMITE_TENTATIVAS_AUTOMATICAS,
        ultimaTentativaEm: '2026-08-11T12:00:00.000Z',
      }),
    ).toBeNull()
  })

  it('reconhece a mesma intenção de edição por impressão não reversível', async () => {
    const comum = {
      devolutivaId: 'devolutiva-1',
      textoNormal: 'Muito bem no estudo desta semana.',
      textoApoioCasa: 'Praticar devagar todos os dias.',
      motivo: 'Ajustei o tom para a família',
    }
    expect(await assinaturaIntencaoDevolutiva(comum)).toBe(await assinaturaIntencaoDevolutiva({ ...comum }))
    expect(await assinaturaIntencaoDevolutiva({ ...comum, motivo: 'Outro motivo' })).not.toBe(
      await assinaturaIntencaoDevolutiva(comum),
    )
  })
})
