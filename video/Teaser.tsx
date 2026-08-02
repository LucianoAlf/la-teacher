import React from 'react'
import { AbsoluteFill, Series, useCurrentFrame } from 'remotion'
import { TEASER } from './roteiroTeaser'
import { SceneAudio, type SceneMeta } from './lib/narration'
import { sceneDuration } from './lib/timing'
import { Sfx, SFX } from './lib/sfx'
import type { CursorKeyframe } from './lib/Dedo'
import { TypingTicks } from './lib/TypingTicks'
import { BackgroundMusic, FadeIn, Palco } from './Onboarding'
import { Abertura, Fecho } from './cenas/Marca'
import { Login } from './telas/Login'
import { Gravar } from './telas/Gravar'
import { Sucesso } from './telas/Sucesso'
import { C, FONT } from './tokens'

/**
 * TEASER de ~35s — prova de conceito do formato pro Alf validar antes das
 * 20 cenas: telas réplica do app, dedo com ripple + tic no toque, digitação
 * com key-ticks, confete com chime, voz do Fábio e a trilha do estúdio.
 * Coordenadas do dedo no espaço do telefone (430×880, conteúdo 410×816).
 */

const EMAIL = 'matheus.felipe@lamusic.com.br'
const clamp = (v: number, min: number, max: number) => Math.min(max, Math.max(min, v))

/** Login: toca no e-mail → digita → senha → digita → Entrar. Sem pular etapa. */
const CenaLogin: React.FC = () => {
  const frame = useCurrentFrame()
  const kfs: CursorKeyframe[] = [
    { frame: 8, x: 330, y: 790 },
    { frame: 22, x: 205, y: 552, click: true }, // campo e-mail
    { frame: 34, x: 305, y: 735 }, // sai da frente enquanto digita
    { frame: 118, x: 205, y: 628, click: true }, // campo senha
    { frame: 130, x: 305, y: 735 },
    { frame: 162, x: 205, y: 693, click: true }, // Entrar
    { frame: 174, x: 310, y: 765 },
  ]
  return (
    <Palco dedo={kfs}>
      <Login
        focoEmail={frame >= 22 && frame < 118}
        emailDigitado={frame < 26 ? 0 : clamp(Math.floor(((frame - 26) * 10) / 30), 0, EMAIL.length)}
        focoSenha={frame >= 118 && frame < 162}
        senhaDigitada={frame < 126 ? 0 : clamp(Math.floor(((frame - 126) * 8) / 30), 0, 8)}
        entrando={frame >= 166}
      />
      <TypingTicks text={EMAIL} startFrame={26} cps={10} />
      <TypingTicks text="••••••••" startFrame={126} cps={8} />
    </Palco>
  )
}

/** Gravar: toca no mic 88 → onda + timer → toca no stop 74 → chip Gravado. */
const MIC_FRAME = 32
const STOP_FRAME = 194
const CenaGravar: React.FC = () => {
  const kfs: CursorKeyframe[] = [
    { frame: 10, x: 330, y: 740 },
    { frame: MIC_FRAME, x: 205, y: 470, click: true }, // mic teal 88px
    { frame: 46, x: 320, y: 700 },
    { frame: STOP_FRAME - 14, x: 240, y: 640 },
    { frame: STOP_FRAME, x: 205, y: 510, click: true }, // stop vermelho 74px
    { frame: STOP_FRAME + 12, x: 315, y: 700 },
  ]
  return (
    <Palco dedo={kfs}>
      <Gravar micFrame={MIC_FRAME} stopFrame={STOP_FRAME} />
      <Sfx file={SFX.popIn} at={STOP_FRAME + 6} volume={0.3} />
    </Palco>
  )
}

const CENAS: Record<string, React.FC> = {
  abertura: () => (
    <>
      <Abertura />
      <Sfx file={SFX.introWhoosh} at={2} volume={0.5} />
    </>
  ),
  login: CenaLogin,
  gravar: CenaGravar,
  sucesso: () => (
    <Palco>
      <Sucesso />
      <Sfx file={SFX.chime} at={8} volume={0.5} />
      <Sfx file={SFX.popIn} at={26} volume={0.25} />
    </Palco>
  ),
  fecho: () => (
    <>
      <Fecho />
      <Sfx file={SFX.swoosh} at={2} volume={0.35} />
    </>
  ),
}

export const Teaser: React.FC<{ scenes: SceneMeta[]; musicFile?: string | null }> = ({
  scenes,
  musicFile = null,
}) => (
  <AbsoluteFill style={{ background: '#05080A', fontFamily: FONT, color: C.text }}>
    {musicFile && <BackgroundMusic file={musicFile} />}
    <Series>
      {TEASER.map((cena, i) => {
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