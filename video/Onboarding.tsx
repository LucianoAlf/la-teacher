import React from 'react'
import {
  AbsoluteFill,
  Audio,
  Easing,
  interpolate,
  Sequence,
  Series,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion'
import { ROTEIRO } from './roteiro'
import { SceneAudio, type SceneMeta } from './lib/narration'
import { sceneDuration } from './lib/timing'
import { Sfx, SFX } from './lib/sfx'
import { Dedo, type CursorKeyframe } from './lib/Dedo'
import { TypingTicks } from './lib/TypingTicks'
import { Telefone } from './ui/Telefone'
import { MenuProfessor } from './ui/AppShell'
import { Abertura, Fecho } from './cenas/Marca'
import { IntroTela } from './telas/IntroTela'
import { CODIGO, Login, TELEFONE } from './telas/Login'
import { Home } from './telas/Home'
import { AgendaTela } from './telas/AgendaTela'
import { Gravar } from './telas/Gravar'
import { Ouvir } from './telas/Ouvir'
import { ProcessandoTela } from './telas/ProcessandoTela'
import { ConfirmarTela, OBS_TEXTO } from './telas/ConfirmarTela'
import { Sucesso } from './telas/Sucesso'
import { PresencaAuto } from './telas/PresencaAuto'
import { ChamadaTela } from './telas/ChamadaTela'
import {
  ExperimentalConfirmar,
  ExperimentalFalta,
  ExperimentalFicha,
  ExperimentalRegistrar,
} from './telas/ExperimentalTelas'
import { AlunosTela } from './telas/AlunosTela'
import { FichaTela } from './telas/FichaTela'
import { TurmaTela } from './telas/TurmaTela'
import { ChatTela, PERGUNTA } from './telas/ChatTela'
import { WhatsAppFabio } from './telas/WhatsAppFabio'
import { SemanaTela } from './telas/SemanaTela'
import { PerfilTela, BIO } from './telas/PerfilTela'
import { C, FONT } from './tokens'

/**
 * O VÍDEO: 20 cenas, todas as telas, dedo com tic em cada toque, sem pular
 * etapa (roteiro aprovado pelo Alf em 02/08). Motor do estúdio do TOM:
 * o áudio dita a duração, música de fundo com fade, SEM legenda.
 * Coordenadas do dedo no espaço do conteúdo do telefone (410×816).
 */

const MUSIC_VOLUME = 0.09

/**
 * ⚠️ A trilha TEM que ser a `-loop`, montada por scripts/montar-trilha.mjs.
 *
 * O tom-theme.mp3 cru tem 60s com fade-in e fade-out PRÓPRIOS (~2s cada) mais
 * silêncio nas pontas: emendado ponta com ponta, cada volta abre um buraco de
 * 4,4s de silêncio ABSOLUTO. No render de 3min42 saíram três buracos, o maior
 * com 2,3s de nada — nem voz nem trilha. Passou despercebido porque meu teste
 * de música só provava que existia som em ALGUM lugar do arquivo.
 * A `-loop` já sai com a cauda cruzada em cima da cabeça: 50,7s sem um ponto
 * abaixo de −30dB, então as cópias podem só encostar uma na outra.
 *
 * O envelope recebe o frame ABSOLUTO de propósito. Dentro de `<Audio loop>` o
 * frame do callback reinicia a cada volta, e um fade escrito contra a duração
 * do vídeo viraria um fade a cada emenda.
 *
 * Gate: node scripts/conferir-mixagem.mjs — não pode sobrar silêncio nenhum.
 */
const TRILHA_FRAMES = 1589 // 52,98s do tom-theme-loop (o script cospe esse número)
const PASSO = TRILHA_FRAMES - 3 // 3 frames de sobreposição: nunca uma fresta

export const BackgroundMusic: React.FC<{ file: string }> = ({ file }) => {
  const { durationInFrames } = useVideoConfig()
  const copias = Math.ceil(durationInFrames / PASSO)
  const envelope = (absoluto: number) =>
    interpolate(
      absoluto,
      [0, 24, durationInFrames - 45, durationInFrames - 4],
      [0, MUSIC_VOLUME, MUSIC_VOLUME, 0],
      { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' },
    )
  return (
    <>
      {Array.from({ length: copias }, (_, i) => (
        <Sequence key={i} from={i * PASSO} durationInFrames={TRILHA_FRAMES}>
          <Audio src={staticFile(file)} volume={(f) => envelope(f + i * PASSO)} />
        </Sequence>
      ))}
    </>
  )
}

/** Entrada de cena: além do fade, um leve recuo que assenta — dá respiro ao corte. */
export const FadeIn: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const frame = useCurrentFrame()
  const t = interpolate(frame, [0, 14], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.out(Easing.cubic),
  })
  return (
    <AbsoluteFill
      style={{
        opacity: interpolate(frame, [0, 8], [0, 1], { extrapolateRight: 'clamp' }),
        transform: `scale(${1.035 - t * 0.035})`,
      }}
    >
      {children}
    </AbsoluteFill>
  )
}

/** O aparelho no palco: halo teal + respiração lenta. 1.8× — o celular domina o 9:16. */
export const Palco: React.FC<{
  children: React.ReactNode
  escalaBase?: number
  /** A mão vai AQUI (não como filha da tela): renderizada por cima do aparelho,
   *  fora do recorte, senão ela é decepada pela moldura quando toca perto da
   *  borda — na barra de baixo só aparecia a pontinha do dedo.
   *  Coordenadas continuam as do conteúdo (410×816); o deslocamento da moldura
   *  (10px de borda + 44px de status bar) é aplicado aqui. */
  dedo?: CursorKeyframe[]
}> = ({ children, escalaBase = 2.08, dedo }) => {
  const frame = useCurrentFrame()
  const escala = escalaBase + Math.sin(frame / 90) * 0.006
  return (
    <AbsoluteFill style={{ background: '#05080A' }}>
      <AbsoluteFill
        style={{
          background:
            'radial-gradient(ellipse 62% 46% at 50% 44%, rgba(42,157,143,.20), transparent 70%)',
        }}
      />
      <AbsoluteFill style={{ alignItems: 'center', justifyContent: 'center' }}>
        <div style={{ transform: `scale(${escala})`, position: 'relative' }}>
          <Telefone>{children}</Telefone>
          {dedo ? (
            <div style={{ position: 'absolute', left: 10, top: 54, width: 410, height: 816 }}>
              <Dedo keyframes={dedo} />
            </div>
          ) : null}
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  )
}

const clamp = (v: number, min: number, max: number) => Math.min(max, Math.max(min, v))
/** caracteres "digitados" até este frame (casa com o cps do TypingTicks) */
const digitado = (frame: number, desde: number, cps: number, max: number) =>
  frame < desde ? 0 : clamp(Math.floor(((frame - desde) * cps) / 30), 0, max)

// O login não tem mais e-mail nem senha: é WhatsApp + código de 8 dígitos
// (migrations 056/057). As constantes vêm da própria tela pra não divergirem
// dela — era exatamente assim que o vídeo ia ensinar um caminho que não existe.

/** Frames de espera antes da voz entrar em cada cena. A vinheta de abertura
 *  precisa de mais: o logo tem que assentar e o whoosh sair da frente antes
 *  do Fábio falar (era o "embolou o áudio no início"). */
const ATRASO_VOZ: Record<string, number> = { abertura: 20 }
const ATRASO_PADRAO = 5

/* ------------------------------- cenas ---------------------------------- */

const CenaIntro: React.FC = () => {
  const frame = useCurrentFrame()
  const passo = frame < 122 ? 1 : frame < 332 ? 2 : 3
  const faseDemo = frame < 212 ? 1 : frame < 268 ? 2 : 3
  const kfs: CursorKeyframe[] = [
    { frame: 80, x: 330, y: 760 },
    { frame: 108, x: 205, y: 758, click: true }, // Continuar (passo 1)
    { frame: 120, x: 320, y: 690 },
    { frame: 318, x: 205, y: 758, click: true }, // Continuar (passo 2)
    { frame: 332, x: 320, y: 690 },
    { frame: 428, x: 205, y: 758, click: true }, // Entrar (passo 3)
    { frame: 442, x: 320, y: 720 },
  ]
  return (
    <Palco dedo={kfs}>
      <IntroTela passo={passo} faseDemo={faseDemo} demoDesde={faseDemo === 3 ? 268 : 138} />
      <Sfx file={SFX.popIn} at={273} volume={0.3} />
      <Sfx file={SFX.popIn} at={281} volume={0.26} />
    </Palco>
  )
}

/**
 * Login: DUAS telas na mesma cena, como no app — pedir o código e digitar o
 * código. O corte entre elas (frame 150) é o momento em que a mensagem chega
 * no WhatsApp; por isso o `popIn` sai ali, e não no clique do botão.
 */
const CenaLogin: React.FC = () => {
  const frame = useCurrentFrame()
  // Frames ancorados no MP3 (silencedetect + ATRASO_PADRAO de 5):
  //   t2 "coloca teu WhatsApp"            37–70   → toca o campo
  //   t3 "Eu te mando um código…"         79–163  → toca Receber código
  //   "na hora, na nossa conversa"        ~129    → o código CHEGA (troca a tela)
  //   t4 "Digita ele aqui e pronto"       172–215 → digita e entra
  const kfs: CursorKeyframe[] = [
    { frame: 8, x: 330, y: 800 },
    { frame: 45, x: 205, y: 600, click: true }, // campo WhatsApp
    { frame: 57, x: 305, y: 760 },
    { frame: 92, x: 205, y: 672, click: true }, // Receber código (digitação já acabou)
    { frame: 104, x: 320, y: 780 },
    { frame: 178, x: 205, y: 612, click: true }, // campo Código (tela 2)
    { frame: 190, x: 315, y: 770 },
    { frame: 218, x: 205, y: 690, click: true }, // Entrar
    { frame: 230, x: 320, y: 780 },
  ]
  const modoCodigo = frame >= 134
  return (
    <Palco dedo={kfs}>
      <Login
        focoTelefone={frame >= 45 && frame < 92}
        telefoneDigitado={digitado(frame, 49, 10, TELEFONE.length)}
        modoCodigo={modoCodigo}
        focoCodigo={frame >= 178 && frame < 218}
        codigoDigitado={digitado(frame, 182, 8, CODIGO.length)}
        entrando={(frame >= 94 && frame < 134) || frame >= 220}
      />
      <TypingTicks text={TELEFONE} startFrame={49} cps={10} />
      <TypingTicks text={CODIGO} startFrame={182} cps={8} />
      {/* o código chegando no WhatsApp, em cima de "na hora, na nossa conversa" */}
      <Sfx file={SFX.popIn} at={134} volume={0.3} />
    </Palco>
  )
}

const CenaHome: React.FC = () => {
  const frame = useCurrentFrame()
  const scrollY = interpolate(frame, [60, 200], [0, 90], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })
  const kfs: CursorKeyframe[] = [
    { frame: 30, x: 335, y: 640 },
    { frame: 130, x: 335, y: 520 },
    { frame: 200, x: 320, y: 480 },
    { frame: 232, x: 205, y: 120 },
  ]
  return (
    <Palco dedo={kfs}>
      <Home scrollY={scrollY} />
      <Sfx file={SFX.popIn} at={10} volume={0.3} />
    </Palco>
  )
}

const CenaAgenda: React.FC = () => {
  const frame = useCurrentFrame()
  const kfs: CursorKeyframe[] = [
    { frame: 10, x: 330, y: 700 },
    { frame: 28, x: 287, y: 780, click: true }, // aba Agenda na TabBar
    { frame: 42, x: 320, y: 620 },
    { frame: 160, x: 205, y: 276, click: true }, // card das 11:00 (Valentina)
    { frame: 174, x: 320, y: 420 },
  ]
  return (
    <Palco dedo={kfs}>
      <AgendaTela aulaDestacada={frame >= 164 ? 0 : -1} />
      <Sfx file={SFX.popIn} at={10} volume={0.28} />
      <Sfx file={SFX.swoosh} at={168} volume={0.3} />
    </Palco>
  )
}

const GRAVAR_MIC = 32
const GRAVAR_STOP = 300
const CenaGravar: React.FC = () => {
  const kfs: CursorKeyframe[] = [
    { frame: 8, x: 330, y: 740 },
    { frame: GRAVAR_MIC, x: 205, y: 470, click: true },
    { frame: 46, x: 320, y: 700 },
    { frame: GRAVAR_STOP - 16, x: 240, y: 640 },
    { frame: GRAVAR_STOP, x: 205, y: 510, click: true },
    { frame: GRAVAR_STOP + 12, x: 315, y: 700 },
  ]
  return (
    <Palco dedo={kfs}>
      <Gravar micFrame={GRAVAR_MIC} stopFrame={GRAVAR_STOP} aceleracao={4.6} />
      <Sfx file={SFX.popIn} at={GRAVAR_STOP + 8} volume={0.3} />
    </Palco>
  )
}

const CenaOuvir: React.FC = () => {
  const kfs: CursorKeyframe[] = [
    { frame: 8, x: 330, y: 700 },
    { frame: 20, x: 205, y: 430, click: true }, // player
    { frame: 32, x: 320, y: 620 },
    { frame: 198, x: 240, y: 600 },
    { frame: 212, x: 205, y: 516, click: true }, // Enviar pro Fábio
    { frame: 224, x: 320, y: 700 },
  ]
  return (
    <Palco dedo={kfs}>
      <Ouvir playFrame={20} enviarFrame={212} />
      <Sfx file={SFX.swoosh} at={218} volume={0.3} />
    </Palco>
  )
}

const CenaProcessando: React.FC = () => (
  <Palco>
    <ProcessandoTela p2Frame={60} p3Frame={150} fimFrame={240} />
    <Sfx file={SFX.popIn} at={62} volume={0.26} />
    <Sfx file={SFX.popIn} at={152} volume={0.26} />
    <Sfx file={SFX.popIn} at={242} volume={0.3} />
  </Palco>
)

const CenaConfirmar: React.FC = () => {
  const frame = useCurrentFrame()
  const scrollY = interpolate(frame, [30, 70, 260, 330], [0, 80, 80, 400], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })
  const kfs: CursorKeyframe[] = [
    { frame: 8, x: 330, y: 700 },
    { frame: 40, x: 335, y: 600 },
    { frame: 86, x: 205, y: 310, click: true }, // campo Observações (cutucada)
    { frame: 98, x: 305, y: 680 },
    { frame: 206, x: 350, y: 180, click: true }, // toca fora — salva
    { frame: 220, x: 340, y: 400 },
    { frame: 300, x: 335, y: 620 },
    { frame: 466, x: 302, y: 775, click: true }, // Confirmar e gravar
    { frame: 480, x: 330, y: 730 },
  ]
  return (
    <Palco dedo={kfs}>
      <ConfirmarTela
        scrollY={scrollY}
        obsFoco={frame >= 86 && frame < 206}
        obsDigitada={digitado(frame, 96, 12, OBS_TEXTO.length)}
        toastVisivel={frame >= 220 && frame < 276}
        gravando={frame >= 470}
      />
      <TypingTicks text={OBS_TEXTO} startFrame={96} cps={12} />
      <Sfx file={SFX.popIn} at={214} volume={0.3} />
    </Palco>
  )
}

const CenaSucesso: React.FC = () => (
  <Palco>
    <Sucesso />
    <Sfx file={SFX.chime} at={8} volume={0.5} />
    <Sfx file={SFX.popIn} at={28} volume={0.25} />
  </Palco>
)

const CenaPresenca: React.FC = () => (
  <Palco>
    <PresencaAuto seloFrame={30} />
    <Sfx file={SFX.popIn} at={10} volume={0.28} />
    <Sfx file={SFX.chime} at={32} volume={0.32} />
  </Palco>
)

const CenaChamada: React.FC = () => {
  const kfs: CursorKeyframe[] = [
    { frame: 10, x: 330, y: 700 },
    { frame: 76, x: 205, y: 318, click: true }, // Maria Isabel → Faltou
    { frame: 90, x: 320, y: 650 },
    { frame: 180, x: 330, y: 780, click: true }, // Enviar chamada
    { frame: 194, x: 320, y: 650 },
    { frame: 290, x: 250, y: 535, click: true }, // Enviar agora
    { frame: 302, x: 330, y: 680 },
  ]
  return (
    <Palco dedo={kfs}>
      <ChamadaTela faltouFrame={76} enviarFrame={180} agoraFrame={290} enviadaFrame={352} />
      <Sfx file={SFX.popIn} at={186} volume={0.28} />
      <Sfx file={SFX.chime} at={356} volume={0.3} />
    </Palco>
  )
}

/** Vem da Home: o dedo toca a aba ALUNOS lá embaixo e a carteira abre. */
/* ------------------- o ciclo da aula experimental ------------------------ */

/**
 * A experimental na agenda. O dedo não toca nada aqui: a cena inteira é sobre
 * RECONHECER a linha antes de tocar. Por isso a única coisa que acontece é a
 * linha acender — o professor precisa aprender a diferença de relance, que é
 * como ele vai encontrar na segunda de manhã.
 */
const CenaExpAgenda: React.FC = () => {
  const frame = useCurrentFrame()
  const kfs: CursorKeyframe[] = [
    { frame: 20, x: 340, y: 720 },
    { frame: 60, x: 250, y: 617 },
  ]
  return (
    <Palco dedo={kfs}>
      {/* índice 2 = a Helena, 16:00 (entre a Amanda e a musicalização).
          Acende no meio de "Repara nessa aqui de quatro horas" (t1, 0–2,1s). */}
      <AgendaTela aulaDestacada={frame >= 45 ? 2 : -1} />
      <Sfx file={SFX.popIn} at={45} volume={0.26} />
    </Palco>
  )
}

/** A ficha: o contexto do lead antes de a criança entrar na sala. */
const CenaExpFicha: React.FC = () => {
  const frame = useCurrentFrame()
  const kfs: CursorKeyframe[] = [
    { frame: 8, x: 250, y: 617, click: true }, // abre pela linha da agenda
    { frame: 24, x: 330, y: 760 },
    { frame: 300, x: 330, y: 640 },
  ]
  return (
    <Palco dedo={kfs}>
      {/* o card acende junto com "A Helena tem sete anos" (t2, 3,7s) */}
      <ExperimentalFicha destacarContexto={frame >= 116} />
      <Sfx file={SFX.swoosh} at={10} volume={0.3} />
      <Sfx file={SFX.popIn} at={116} volume={0.26} />
    </Palco>
  )
}

/**
 * Registrar: três estados numa cena — botão, gravando, campos prontos. O corte
 * pro resultado (frame 250) é o Fábio devolvendo o áudio já separado; o `chime`
 * marca esse momento, que é o que a cena existe pra mostrar.
 */
const CenaExpRegistrar: React.FC = () => {
  const frame = useCurrentFrame()
  const kfs: CursorKeyframe[] = [
    { frame: 10, x: 330, y: 760 },
    { frame: 85, x: 215, y: 560, click: true }, // toca o microfone em "toca e fala"
    { frame: 101, x: 330, y: 800 },
    { frame: 200, x: 320, y: 700 },
  ]
  // Os campos aparecem quando a voz NOMEIA os dois destinos ("o que fica pra
  // escola de um lado, e do outro o que a mãe vai receber", ~5,5s): o
  // espectador vê a separação no instante em que a ouve.
  const etapa: 0 | 1 | 2 = frame >= 172 ? 2 : frame >= 89 ? 1 : 0
  return (
    <Palco dedo={kfs}>
      <ExperimentalRegistrar etapa={etapa} segundos={(frame - 89) / 30} />
      <Sfx file={SFX.popIn} at={89} volume={0.3} />
      <Sfx file={SFX.chime} at={172} volume={0.28} />
    </Palco>
  )
}

/** Confirmar: nada vai pra família sem o OK, e o "pronto" diz a quem chegou. */
const CenaExpConfirmar: React.FC = () => {
  const frame = useCurrentFrame()
  const kfs: CursorKeyframe[] = [
    { frame: 14, x: 330, y: 700 },
    { frame: 150, x: 215, y: 690, click: true }, // "Confirmou?" (t3, 4,8s)
    { frame: 166, x: 330, y: 780 },
  ]
  return (
    <Palco dedo={kfs}>
      {/* as três linhas do "feito" caem em cima de "eu lanço a presença,
          mando a devolutiva e aviso o comercial" (t4–t6, 6,1s–11,2s) */}
      <ExperimentalConfirmar confirmado={frame >= 166} pressionado={frame >= 150 && frame < 166} />
      <Sfx file={SFX.chime} at={170} volume={0.32} />
    </Palco>
  )
}

/** Não veio: um toque. A cena é curta porque a tela é curta — é o ponto. */
const CenaExpFalta: React.FC = () => {
  const frame = useCurrentFrame()
  const kfs: CursorKeyframe[] = [
    { frame: 12, x: 330, y: 720 },
    { frame: 90, x: 215, y: 800, click: true }, // "Um toque e o comercial já sabe" (t2, 2,8s)
    { frame: 106, x: 330, y: 860 },
  ]
  return (
    <Palco dedo={kfs}>
      <ExperimentalFalta feito={frame >= 108} pressionado={frame >= 90 && frame < 108} />
      <Sfx file={SFX.popIn} at={112} volume={0.3} />
    </Palco>
  )
}

const CenaAlunos: React.FC = () => {
  const frame = useCurrentFrame()
  const TROCA = 36 // a aba só responde depois do toque assentar
  const kfs: CursorKeyframe[] = [
    { frame: 6, x: 330, y: 690 },
    { frame: 22, x: 123, y: 778, click: true }, // aba Alunos (TabBar)
    { frame: 44, x: 320, y: 620 },
    { frame: 190, x: 205, y: 203, click: true }, // Valentina
    { frame: 204, x: 320, y: 420 },
  ]
  return (
    <Palco dedo={kfs}>
      {frame < TROCA ? (
        <Home />
      ) : (
        <AlunosTela destacado={frame >= 194 ? 'Valentina' : undefined} />
      )}
      <Sfx file={SFX.swoosh} at={TROCA} volume={0.28} />
    </Palco>
  )
}

const CenaFicha: React.FC = () => {
  const frame = useCurrentFrame()
  const scrollY = interpolate(frame, [60, 330], [0, 400], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })
  const kfs: CursorKeyframe[] = [
    { frame: 30, x: 340, y: 650 },
    { frame: 330, x: 340, y: 480 },
  ]
  return (
    <Palco dedo={kfs}>
      <FichaTela scrollY={scrollY} />
      <Sfx file={SFX.popIn} at={24} volume={0.28} />
    </Palco>
  )
}

const CenaTurma: React.FC = () => (
  <Palco>
    <TurmaTela />
    <Sfx file={SFX.popIn} at={12} volume={0.26} />
    <Sfx file={SFX.popIn} at={20} volume={0.22} />
  </Palco>
)

/** Vem da Home: o dedo aperta a BOLOTA TEAL do Fábio (o FAB central) e o chat abre. */
const CenaChat: React.FC = () => {
  const frame = useCurrentFrame()
  const TROCA = 38
  const kfs: CursorKeyframe[] = [
    { frame: 6, x: 320, y: 700 },
    { frame: 24, x: 205, y: 752, click: true }, // FAB central do Fábio
    { frame: 48, x: 300, y: 700 },
    { frame: 68, x: 190, y: 780, click: true }, // campo de mensagem
    { frame: 84, x: 300, y: 720 },
    { frame: 150, x: 368, y: 780, click: true }, // enviar
    { frame: 168, x: 330, y: 700 },
  ]
  return (
    <Palco dedo={kfs}>
      {frame < TROCA ? (
        <Home />
      ) : (
        <ChatTela digitaFrame={78} enviaFrame={150} digitandoFrame={172} respostaFrame={286} />
      )}
      <TypingTicks text={PERGUNTA} startFrame={78} cps={12} />
      <Sfx file={SFX.swoosh} at={TROCA} volume={0.28} />
      <Sfx file={SFX.msgPop} at={158} volume={0.4} rate={1.12} />
      <Sfx file={SFX.msgPop} at={286} volume={0.45} />
    </Palco>
  )
}

/** O briefing REAL que o Fábio manda às 8h — no formato detalhado do Alf:
 *  cada aula com última aula registrada, foco, trabalho feito e repertório.
 *  É o que o professor mais usa, então aparece por inteiro. */
const BRIEFING = `Bom dia, Matheus! 🎵

Hoje você tem 4 aulas com 5 alunos.

*Agenda de hoje:*

*11:00 — Canto*
Aluna: Valentina
Última aula registrada: 27/07
Foco: decorar a letra, com preparação vocal.
Trabalho feito: vocalizes e respiração.
Repertório: “Temos que Pegar” (Pokémon).

*15:00 — Canto*
Aluna: Amanda
Última aula registrada: 28/07
Foco: afinação no registro médio.
Trabalho feito: escalas e apoio.
Repertório: “Anunciação”.

*17:00 — Musicalização*
Alunos: Gustavo e Maria Isabel
Última aula registrada: 28/07
Foco: pulsação e tempo forte.
Trabalho feito: marchinha com palmas.

*18:00 — Musicalização*
Aluno: Arthur
Última aula registrada: 28/07
Foco: firmar o tempo forte.
Repertório: Balão Mágico.

Bora! 🚀`

const PERGUNTA_WA = 'Fábio, o Arthur ficou com dever de casa?'
const RESPOSTA_WA =
  'Ficou sim! Treinar as palmas no refrão do Balão Mágico. Quer que eu lembre a mãe dele hoje à tarde?'

/** WhatsApp — a cena mais importante pro professor: o briefing detalhado das
 *  8h E a conversa. Aqui ele pergunta e o Fábio responde, igual dentro do app. */
// O WhatsApp é onde o professor mais vai usar o Fábio (pedido do Alf), então a
// cena não pode ser só "chega mensagem": ele TOCA a barra, digita e envia — e o
// Fábio responde ali mesmo, igual dentro do app. É o que a narração promete.
// Os frames saem da própria narração, medida por silencedetect no MP3: a fala
// "E pode responder ali mesmo" começa em 9,91s → frame 302 (5 de atraso da voz).
// O dedo tem que ir digitar AÍ, não antes — senão ele pergunta enquanto o Fábio
// ainda está descrevendo o briefing.
const WA_TOQUE = 300
const WA_DIGITA = 308
const WA_ENVIA = 342
const CenaWhatsApp: React.FC = () => {
  const frame = useCurrentFrame()
  const rolagem = interpolate(frame, [70, 190, 348, 396], [0, 46, 120, 210], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })
  const rascunho = PERGUNTA_WA.slice(0, digitado(frame, WA_DIGITA, 45, PERGUNTA_WA.length))
  const kfs: CursorKeyframe[] = [
    { frame: 260, x: 340, y: 880 },
    { frame: WA_TOQUE, x: 170, y: 788, click: true }, // barra de digitar
    { frame: WA_ENVIA, x: 370, y: 788, click: true }, // botão de enviar
    { frame: 400, x: 350, y: 880 },
  ]
  return (
    <Palco dedo={kfs}>
      <WhatsAppFabio
        rolagem={rolagem}
        rascunho={frame >= WA_ENVIA ? '' : rascunho}
        mensagens={[
          { texto: <span style={{ whiteSpace: 'pre-line' }}>{BRIEFING}</span>, atFrame: 24, hora: '8:00' },
          { texto: PERGUNTA_WA, atFrame: WA_ENVIA + 2, enviada: true, hora: '8:04' },
          { texto: RESPOSTA_WA, atFrame: 382, hora: '8:04' },
        ]}
      />
      <TypingTicks text={PERGUNTA_WA} startFrame={WA_DIGITA} cps={45} />
    </Palco>
  )
}

/** Vem da Home: o dedo toca o card "Minha semana" e a tela abre. */
const CenaSemana: React.FC = () => {
  const frame = useCurrentFrame()
  const TROCA = 38
  const kfs: CursorKeyframe[] = [
    { frame: 6, x: 330, y: 640 },
    { frame: 24, x: 205, y: 659, click: true }, // card Minha semana (Home rolada)
    { frame: 46, x: 330, y: 560 },
    { frame: 160, x: 335, y: 430 },
  ]
  return (
    <Palco dedo={kfs}>
      {/* a Home entra já rolada pro card "Minha semana" aparecer acima da barra */}
      {frame < TROCA ? <Home scrollY={120} /> : <SemanaTela />}
      <Sfx file={SFX.swoosh} at={TROCA} volume={0.28} />
    </Palco>
  )
}

/** Caminho real do Perfil: avatar do professor → menu → Perfil. Sem pular etapa. */
const CenaPerfil: React.FC = () => {
  const frame = useCurrentFrame()
  const MENU = 34 // o menu abre
  const TROCA = 68 // o Perfil abre
  const scrollY = interpolate(frame, [TROCA + 4, TROCA + 40], [0, 150], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })
  const kfs: CursorKeyframe[] = [
    { frame: 4, x: 300, y: 300 },
    { frame: 20, x: 374, y: 34, click: true }, // avatar do professor
    { frame: 40, x: 300, y: 200 },
    { frame: 54, x: 300, y: 203, click: true }, // item "Perfil" do menu
    { frame: 72, x: 320, y: 620 },
    { frame: 120, x: 205, y: 395, click: true }, // Bio
    { frame: 134, x: 300, y: 690 },
    { frame: 286, x: 205, y: 524, click: true }, // Salvar perfil
    { frame: 300, x: 330, y: 660 },
  ]
  return (
    <Palco dedo={kfs}>
      {frame < TROCA ? (
        <>
          <Home />
          {frame >= MENU ? <MenuProfessor destaque={frame >= 54 ? 'Perfil' : undefined} /> : null}
        </>
      ) : (
        <PerfilTela
          scrollY={scrollY}
          bioFoco={frame >= 120 && frame < 286}
          bioDigitada={digitado(frame, 134, 20, BIO.length)}
          toastVisivel={frame >= 300 && frame < 366}
        />
      )}
      <TypingTicks text={BIO} startFrame={134} cps={20} />
      <Sfx file={SFX.popIn} at={MENU} volume={0.28} />
      <Sfx file={SFX.swoosh} at={TROCA} volume={0.28} />
      <Sfx file={SFX.popIn} at={298} volume={0.3} />
    </Palco>
  )
}

const CENAS: Record<string, React.FC> = {
  abertura: () => (
    <>
      <Abertura />
      <Sfx file={SFX.introWhoosh} at={0} volume={0.32} />
    </>
  ),
  intro: CenaIntro,
  login: CenaLogin,
  home: CenaHome,
  agenda: CenaAgenda,
  gravar: CenaGravar,
  ouvir: CenaOuvir,
  processando: CenaProcessando,
  confirmar: CenaConfirmar,
  sucesso: CenaSucesso,
  presenca: CenaPresenca,
  chamada: CenaChamada,
  'exp-agenda': CenaExpAgenda,
  'exp-ficha': CenaExpFicha,
  'exp-registrar': CenaExpRegistrar,
  'exp-confirmar': CenaExpConfirmar,
  'exp-falta': CenaExpFalta,
  alunos: CenaAlunos,
  ficha: CenaFicha,
  turma: CenaTurma,
  chat: CenaChat,
  whatsapp: CenaWhatsApp,
  semana: CenaSemana,
  perfil: CenaPerfil,
  fecho: () => (
    <>
      <Fecho />
      <Sfx file={SFX.swoosh} at={2} volume={0.35} />
    </>
  ),
}

export const Onboarding: React.FC<{ scenes: SceneMeta[]; musicFile?: string | null }> = ({
  scenes,
  musicFile = null,
}) => (
  <AbsoluteFill style={{ background: '#05080A', fontFamily: FONT, color: C.text }}>
    {musicFile && <BackgroundMusic file={musicFile} />}
    <Series>
      {ROTEIRO.map((cena, i) => {
        const meta =
          scenes[i] ?? {
            id: cena.id,
            durationInFrames: sceneDuration(null, cena.duracaoMinS),
            audioFile: null,
          }
        const Cena = CENAS[cena.id]
        return (
          <Series.Sequence key={cena.id} durationInFrames={meta.durationInFrames}>
            {i === 0 ? (
              <AbsoluteFill>
                <Cena />
              </AbsoluteFill>
            ) : (
              <FadeIn>
                <Cena />
              </FadeIn>
            )}
            <SceneAudio meta={meta} atraso={ATRASO_VOZ[cena.id] ?? ATRASO_PADRAO} />
          </Series.Sequence>
        )
      })}
    </Series>
  </AbsoluteFill>
)