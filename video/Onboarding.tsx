import React from 'react'
import {
  AbsoluteFill,
  Audio,
  interpolate,
  Series,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion'
import { ROTEIRO } from './roteiro'
import { SceneAudio, type SceneMeta } from './lib/narration'
import { sceneDuration } from './lib/timing'
import { Sfx, SFX } from './lib/sfx'
import { Telefone } from './ui/Telefone'
import { Agenda } from './cenas/Agenda'
import { Gravando } from './cenas/Gravando'
import { Resultado } from './cenas/Resultado'
import { Abertura, Fecho } from './cenas/Marca'
import { C, FONT } from './tokens'

/**
 * Motor herdado do estúdio do TOM (D:\la-organizer\video-studio):
 * o ÁUDIO dita a duração de cada cena, música de fundo em 0.1 com fade,
 * SFX pontuando os momentos — e SEM legenda (a voz conduz, a tela mostra).
 */

const MUSIC_VOLUME = 0.09

export const BackgroundMusic: React.FC<{ file: string }> = ({ file }) => {
  const { durationInFrames } = useVideoConfig()
  return (
    <Audio
      src={staticFile(file)}
      loop
      volume={(f) =>
        interpolate(
          f,
          [0, 24, durationInFrames - 60, durationInFrames - 8],
          [0, MUSIC_VOLUME, MUSIC_VOLUME, 0],
          { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' },
        )
      }
    />
  )
}

export const FadeIn: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const frame = useCurrentFrame()
  return (
    <AbsoluteFill
      style={{ opacity: interpolate(frame, [0, 8], [0, 1], { extrapolateRight: 'clamp' }) }}
    >
      {children}
    </AbsoluteFill>
  )
}

/** O aparelho no palco: halo teal + respiração lenta (sem zoom agressivo).
 *  Escala 1.8: em 1080×1920 o telefone ocupa ~72% da largura — vídeo 9:16
 *  é sobre o celular, ele tem que dominar a tela. */
export const Palco: React.FC<{ children: React.ReactNode; escalaBase?: number }> = ({
  children,
  escalaBase = 1.8,
}) => {
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
        <div style={{ transform: `scale(${escala})` }}>
          <Telefone>{children}</Telefone>
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  )
}

/** Cada cena traz seus próprios efeitos sonoros, no frame em que a ação acontece. */
const CENAS: Record<string, React.FC> = {
  intro: () => (
    <>
      <Abertura />
      <Sfx file={SFX.introWhoosh} at={2} volume={0.5} />
    </>
  ),
  agenda: () => (
    <Palco>
      <Agenda alvo={0} />
      <Sfx file={SFX.popIn} at={10} volume={0.3} />
    </Palco>
  ),
  gravar: () => (
    <Palco>
      <Gravando segundos={6} />
      <Sfx file={SFX.tap} at={4} volume={0.5} />
      <Sfx file={SFX.swoosh} at={8} volume={0.3} />
    </Palco>
  ),
  resultado: () => (
    <Palco>
      <Resultado />
      <Sfx file={SFX.swoosh} at={4} volume={0.32} />
      <Sfx file={SFX.popIn} at={16} volume={0.26} />
      <Sfx file={SFX.popIn} at={28} volume={0.26} />
    </Palco>
  ),
  presenca: () => (
    <Palco>
      <Resultado destaquePresenca />
      <Sfx file={SFX.chime} at={8} volume={0.45} />
    </Palco>
  ),
  outro: () => (
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
            <SceneAudio meta={meta} />
          </Series.Sequence>
        )
      })}
    </Series>
  </AbsoluteFill>
)
