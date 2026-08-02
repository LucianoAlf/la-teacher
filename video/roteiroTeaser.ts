import type { Cena } from './lib/types'

export const TEASER_ID = 'teaser-efeitos'

/**
 * Teaser de ~35s pro Alf validar UX/efeitos ANTES da produção dos 5 minutos:
 * abertura com o Fábio de verdade → login com o dedo digitando (tic-tic) →
 * gravação (onda + stop) → comemoração (confete + chime) → fecho.
 * As falas são as MESMAS do roteiro de 20 cenas (cenas 1, 3, 6, 10 e 20) —
 * aprovou aqui, tá aprovado lá.
 */
export const TEASER: Cena[] = [
  {
    id: 'abertura',
    duracaoMinS: 4,
    caption: '',
    narracao: 'E aí, professor! Aqui é o Fábio. Bora afinar essa parada do registro de aula?',
  },
  {
    id: 'login',
    duracaoMinS: 7,
    caption: '',
    narracao:
      'Primeiro acesso é rapidinho: teu e-mail da LA e a senha que a coordenação te passou. Só isso.',
  },
  {
    id: 'gravar',
    duracaoMinS: 8,
    caption: '',
    narracao:
      'Acabou a aula? Toca aqui e fala, do teu jeito. É tipo contar pro colega como foi. Trinta segundos e tá feito.',
  },
  {
    id: 'sucesso',
    duracaoMinS: 5,
    caption: '',
    narracao: 'Pronto! Cada aluno recebeu a aula no diário dele.',
  },
  {
    id: 'fecho',
    duracaoMinS: 4,
    caption: '',
    narracao: 'É isso aí! Manda o áudio que eu cuido da papelada. Tamo junto!',
  },
]
