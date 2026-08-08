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
    // ⚠️ REESCRITA EM 08/08/2026. Dizia "teu e-mail da LA e a senha que a
    // coordenação te passou" — e não existe mais senha nenhuma no caminho do
    // professor. É WhatsApp + código de 8 dígitos (056/057). Vídeo que ensina
    // o passo errado é pior que vídeo nenhum: a pessoa tenta, não entra, e
    // conclui que o app não funciona no aparelho dela.
    //
    // E o comentário fica DEPOIS do `id:`, não antes: o leitor do roteiro é
    // uma regex que casa `{ id:` com `\s*` no meio — comentário ali dentro faz
    // a cena inteira sumir da geração de voz, em silêncio.
    duracaoMinS: 12,
    caption: '',
    narracao:
      'Primeiro acesso: coloca teu WhatsApp. Eu te mando um código de oito números na hora, na nossa conversa. Digita ele aqui e pronto — sem senha pra decorar, sem e-mail pra lembrar.',
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
  // ---- o ciclo da aula experimental (acrescentado em 08/08/2026) ----
  // Entra aqui, DEPOIS da chamada: fecha o bloco "como registrar uma aula" e
  // abre o de "e tem uma aula que não é como as outras". Antes dos alunos, que
  // é a carteira de quem JÁ ficou na escola — a experimental é justamente
  // sobre quem ainda está decidindo.
  {
    id: 'exp-agenda',
    duracaoMinS: 9,
    caption: '',
    narracao:
      'Repara nessa aqui de quatro horas. Ela vem com uma estrelinha e o nome de uma pessoa, não de uma turma: é aula experimental. Alguém que nunca pisou aqui.',
  },
  {
    id: 'exp-ficha',
    duracaoMinS: 14,
    caption: '',
    narracao:
      'Toca e eu te conto quem vem antes de ela entrar na sala. A Helena tem sete anos, a irmã já faz teclado aqui, e a mãe avisou que ela é tímida no começo. Você entra sabendo — não descobre quando a criança chega.',
  },
  {
    id: 'exp-registrar',
    duracaoMinS: 15,
    caption: '',
    narracao:
      'Acabou? Mesmo gesto de sempre: toca e fala. Só que agora eu separo de um jeito diferente — o que fica pra escola de um lado, e do outro o que a mãe vai receber. Você fala tudo junto, eu que divido.',
  },
  {
    id: 'exp-confirmar',
    duracaoMinS: 14,
    caption: '',
    narracao:
      'Antes de sair, você lê o que a Camila vai receber. Nada vai pra família sem você ver. Confirmou? Aí eu lanço a presença, mando a devolutiva e aviso o comercial — as três de uma vez.',
  },
  {
    id: 'exp-falta',
    duracaoMinS: 9,
    caption: '',
    narracao:
      'E se ela não aparecer, não precisa escrever nada. Um toque e o comercial já sabe, ainda hoje, pra correr atrás de remarcar antes que a família esfrie.',
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
