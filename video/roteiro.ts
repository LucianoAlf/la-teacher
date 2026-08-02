import type { Cena } from './lib/types'

export type { Cena }

export const VIDEO_ID = 'onboarding-professor'

/**
 * Onboarding do professor no LA Teacher — 20 cenas, TODAS as telas.
 *
 * ⚠️ REGRA QUE EU QUEBREI NO 1º CORTE (e que não pode se repetir): a fala tem
 * que COBRIR a ação. Eu tinha escrito frases curtas de apresentação e uma
 * coreografia longa de dedo — resultado: 65s dos 204s (32%) sem voz nenhuma,
 * só trilha, e o vídeo morria no meio de quase toda cena. As falas abaixo são
 * dimensionadas pelo tempo de cada cena (~3,2 palavras/s + 1s de respiro).
 * Ao mexer numa cena, recalcular: palavras ≈ (duracaoMinS − 1,8) × 3,2.
 *
 * TOM: colega de palco, não manual. SEM legenda: a voz conduz, a tela mostra.
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
    duracaoMinS: 15,
    caption: '',
    narracao:
      'Na primeira vez que você entra, eu me apresento. Olha só o que eu faço: você fala do seu jeito, e eu separo o que é de cada aluno. Repara — o Gustavo e a Maria saíram na mesma frase, e cada um ficou com a sua. E fica combinado: eu nunca invento nada.',
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
    narracao:
      'Essa é tua casa. Eu te recebo com o resumo do dia, tuas aulas e o que ficou pendente — tudo na primeira tela, sem precisar procurar.',
  },
  {
    id: 'agenda',
    duracaoMinS: 8,
    caption: '',
    narracao:
      'Tua agenda do dia. Aluno, horário, sala — tudo no lugar quando você chega. E os dias da semana ali em cima, é só deslizar.',
  },
  {
    id: 'gravar',
    duracaoMinS: 13,
    caption: '',
    narracao:
      'Acabou a aula? Toca aqui e fala, do teu jeito. É tipo contar pro colega como foi: o que trabalharam, como cada um foi, o dever de casa. Pode gaguejar, pode voltar atrás — eu entendo. Trinta segundos e tá feito.',
  },
  {
    id: 'ouvir',
    duracaoMinS: 9,
    caption: '',
    narracao:
      'Quer conferir antes de mandar? Escuta aqui, ó. Se não gostou, é só regravar. Tá bom? Então manda pra mim que eu já começo a trabalhar.',
  },
  {
    id: 'processando',
    duracaoMinS: 10,
    caption: '',
    narracao:
      'Aí eu escuto, entendo e separo aluno por aluno. Leva menos de um minuto. E você pode sair da tela, ir tomar um café — quando ficar pronto, eu te aviso.',
  },
  {
    id: 'confirmar',
    duracaoMinS: 18,
    caption: '',
    narracao:
      'Antes de ir pro diário, você confere. Em cima fica o que a turma trabalhou; embaixo, a parte de cada aluno. Se eu não ouvi alguma coisa no áudio, eu deixo o campo vazio com um convite — é só tocar e completar, ó. Nada entra sem o teu OK. Eu nunca invento.',
  },
  {
    id: 'sucesso',
    duracaoMinS: 7,
    caption: '',
    narracao:
      'Pronto! Cada aluno recebeu a aula no diário dele, e a coordenação já consegue ver. Sem digitar nada.',
  },
  {
    id: 'presenca',
    duracaoMinS: 7,
    caption: '',
    narracao:
      'E a presença? Já lancei, junto com o registro. Você gravou o conteúdo — o resto é comigo.',
  },
  {
    id: 'chamada',
    duracaoMinS: 15,
    caption: '',
    narracao:
      'E se num dia você não gravar o áudio? A chamada manual tá aqui. Todo mundo já começa presente — você só toca em quem faltou, confere e envia. Dois toques e acabou. Só presta atenção: depois de enviar, não dá pra editar pelo app.',
  },
  {
    id: 'alunos',
    duracaoMinS: 10,
    caption: '',
    narracao:
      'Aqui é tua carteira inteira, separada por curso e unidade. Dá pra buscar pelo nome, e cada linha já mostra o dia, a hora e em que aula o aluno está.',
  },
  {
    id: 'ficha',
    duracaoMinS: 13,
    caption: '',
    narracao:
      'E a ficha de cada aluno: a jornada dele, a presença de verdade — a que foi confirmada e a que ninguém conferiu — e tudo que já foi trabalhado, inclusive o que ficou de professores anteriores. Você nunca começa do zero.',
  },
  {
    id: 'turma',
    duracaoMinS: 7,
    caption: '',
    narracao:
      'Cada turma guarda a linha do tempo das aulas — o que rolou na semana passada, na retrasada. Você nunca chega perdido.',
  },
  {
    id: 'chat',
    duracaoMinS: 13,
    caption: '',
    narracao:
      'Precisa de alguma coisa? Só me chamar. Pergunta do jeito que você falaria com um colega: como foi a aula do Arthur, o que passar de dever, quem tá faltando muito. Eu tô aqui dentro do app…',
  },
  {
    id: 'whatsapp',
    duracaoMinS: 15,
    caption: '',
    // ⚠️ Sem reticências no INÍCIO da fala: o modelo arrastava pro dobro do
    // tempo (1,66 palavras/s). E comentário NUNCA entre `narracao:` e o texto —
    // o leitor do roteiro (regex) perde a cena inteira e embaralha as falas.
    narracao:
      'E no teu WhatsApp também! Toda manhã, cedinho, eu te mando a agenda do dia: cada aula com o foco, o que já foi trabalhado e o repertório de cada aluno. Você chega sabendo. E pode responder ali mesmo, viu? Pergunta o que quiser que eu respondo na hora, igual aqui dentro do app.',
  },
  {
    id: 'semana',
    duracaoMinS: 8,
    caption: '',
    narracao:
      'Suas horas nascem da chamada, sozinhas. Aqui você acompanha a semana inteira, dia a dia, sem planilha e sem papel.',
  },
  {
    id: 'perfil',
    duracaoMinS: 13,
    caption: '',
    narracao:
      'No teu perfil, conta quem você é: teu instrumento, teu jeito de dar aula. Eu uso isso pra falar contigo do teu jeito. E é aqui que você escolhe onde quer me receber — no app, no WhatsApp, ou nos dois.',
  },
  {
    id: 'fecho',
    duracaoMinS: 5,
    caption: '',
    narracao: 'É isso aí! Manda o áudio que eu cuido da papelada. Tamo junto!',
  },
]
