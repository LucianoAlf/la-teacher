import type { Cena } from './lib/types'

export type { Cena }

export const VIDEO_ID = 'onboarding-professor'

/**
 * Onboarding do professor no LA Teacher.
 *
 * TOM (feedback do Alf, 02/08): o professor de música é descolado — a narração
 * fala como colega de palco, não como manual. Frases curtas, 2ª pessoa, gíria
 * na medida, energia. Nada de "clique no botão para prosseguir".
 * SEM legenda na tela (mesma decisão do estúdio do TOM em 19/06): a voz conduz,
 * a tela mostra. Legenda só rouba atenção do que importa.
 *
 * Dados reais: a agenda é a do Matheus em 03/08 e o conteúdo da Valentina veio
 * do registro de verdade — nada de mock.
 */
export const ROTEIRO: Cena[] = [
  {
    id: 'intro',
    duracaoMinS: 4,
    caption: '',
    narracao: 'E aí, professor! Aqui é o Fábio. Bora afinar essa parada do registro de aula?',
  },
  {
    id: 'agenda',
    duracaoMinS: 6,
    caption: '',
    narracao: 'Essa é a tua agenda do dia. Aluno, horário, sala — tudo no lugar, já pronto quando você chega.',
  },
  {
    id: 'gravar',
    duracaoMinS: 7,
    caption: '',
    narracao: 'Acabou a aula? Toca aqui e fala, do teu jeito. É tipo contar pro colega como foi. Trinta segundos e tá feito.',
  },
  {
    id: 'resultado',
    duracaoMinS: 8,
    caption: '',
    narracao: 'Pronto! Eu organizo o resto: o que rolou na aula, o repertório, o dever de casa. Tudo no prontuário do aluno.',
  },
  {
    id: 'presenca',
    duracaoMinS: 6,
    caption: '',
    narracao: 'E a presença? Já lancei. Você gravou o conteúdo, o resto é comigo.',
  },
  {
    id: 'outro',
    duracaoMinS: 5,
    caption: '',
    narracao: 'É isso aí! Manda o áudio que eu cuido da papelada. Tamo junto!',
  },
]
