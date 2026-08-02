import type { Cena } from './lib/types'

export type { Cena }

export const VIDEO_ID = 'onboarding-professor'

/**
 * Onboarding do professor no LA Teacher — 20 cenas, TODAS as telas
 * (decisão do Alf 02/08: é lançamento, nada fica de fora). Falas aprovadas
 * pelo Alf em 02/08 — texto verbatim de docs/video/ROTEIRO-onboarding-professor.md.
 *
 * TOM: o professor de música é descolado — a narração fala como colega de
 * palco, não como manual. SEM legenda na tela (decisão de 19/06): a voz
 * conduz, a tela mostra.
 *
 * `duracaoMinS` é o piso pra coreografia do dedo caber; o áudio estica se
 * a fala for maior.
 */
export const ROTEIRO: Cena[] = [
  {
    id: 'abertura',
    duracaoMinS: 4,
    caption: '',
    narracao: 'E aí, professor! Aqui é o Fábio. Bora afinar essa parada do registro de aula?',
  },
  {
    id: 'intro',
    duracaoMinS: 18,
    caption: '',
    narracao:
      'Na primeira vez, eu me apresento. Olha só o que eu faço: você fala do jeito que sai — e eu transformo em registro organizado, aluno por aluno. E fica combinado: eu nunca invento nada.',
  },
  {
    id: 'login',
    duracaoMinS: 7,
    caption: '',
    narracao:
      'Primeiro acesso é rapidinho: teu e-mail da LA e a senha que a coordenação te passou. Só isso.',
  },
  {
    id: 'home',
    duracaoMinS: 8,
    caption: '',
    narracao: 'Essa é tua casa. Eu te recebo com o resumo do dia, tuas aulas e o que ficou pendente.',
  },
  {
    id: 'agenda',
    duracaoMinS: 8,
    caption: '',
    narracao: 'Tua agenda do dia. Aluno, horário, sala — tudo no lugar quando você chega.',
  },
  {
    id: 'gravar',
    duracaoMinS: 13,
    caption: '',
    narracao:
      'Acabou a aula? Toca aqui e fala, do teu jeito. É tipo contar pro colega como foi. Trinta segundos e tá feito.',
  },
  {
    id: 'ouvir',
    duracaoMinS: 9,
    caption: '',
    narracao: 'Quer conferir antes? Escuta aqui. Tá bom? Manda pra mim.',
  },
  {
    id: 'processando',
    duracaoMinS: 10,
    caption: '',
    narracao:
      'Aí eu escuto, entendo e separo aluno por aluno. Leva menos de um minuto — e você pode sair da tela, não perde nada.',
  },
  {
    id: 'confirmar',
    duracaoMinS: 18,
    caption: '',
    narracao:
      'Antes de ir pro diário, você confere. Se faltou alguma coisa, é só tocar e completar. Nada entra sem o teu OK — eu nunca invento.',
  },
  {
    id: 'sucesso',
    duracaoMinS: 7,
    caption: '',
    narracao: 'Pronto! Cada aluno recebeu a aula no diário dele.',
  },
  {
    id: 'presenca',
    duracaoMinS: 7,
    caption: '',
    narracao: 'E a presença? Já lancei. Você gravou o conteúdo, o resto é comigo.',
  },
  {
    id: 'chamada',
    duracaoMinS: 15,
    caption: '',
    narracao:
      'E se num dia você não gravar o áudio? A chamada manual tá aqui: todo mundo começa presente, você só toca em quem faltou e envia. Dois toques.',
  },
  {
    id: 'alunos',
    duracaoMinS: 9,
    caption: '',
    narracao: 'Aqui é tua carteira inteira, separada por curso e unidade.',
  },
  {
    id: 'ficha',
    duracaoMinS: 13,
    caption: '',
    narracao:
      'E a ficha de cada aluno: a jornada, a presença de verdade e tudo que já foi trabalhado — inclusive o que ficou de professores anteriores.',
  },
  {
    id: 'turma',
    duracaoMinS: 7,
    caption: '',
    narracao: 'Cada turma guarda a linha do tempo das aulas — você nunca chega perdido.',
  },
  {
    id: 'chat',
    duracaoMinS: 13,
    caption: '',
    narracao: 'Precisa de alguma coisa? Só me chamar. Eu tô aqui dentro do app…',
  },
  {
    id: 'whatsapp',
    duracaoMinS: 10,
    caption: '',
    narracao:
      '…e no teu WhatsApp também. Toda manhã eu te mando a agenda do dia, com o que rolou na última aula de cada aluno.',
  },
  {
    id: 'semana',
    duracaoMinS: 8,
    caption: '',
    narracao:
      'Suas horas nascem da chamada, sozinhas. Aqui você acompanha a semana inteira — sem planilha, sem papel.',
  },
  {
    id: 'perfil',
    duracaoMinS: 13,
    caption: '',
    narracao:
      'No teu perfil, conta quem você é — o Fábio usa isso pra falar contigo do teu jeito. E é aqui que você ajusta como e quando ele te chama.',
  },
  {
    id: 'fecho',
    duracaoMinS: 5,
    caption: '',
    narracao: 'É isso aí! Manda o áudio que eu cuido da papelada. Tamo junto!',
  },
]
