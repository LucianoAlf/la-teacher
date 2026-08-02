import React from 'react'
import { Composition } from 'remotion'
import './lib/fonts' // Inter + Prompt — as mesmas do app; sem isso o render cai em fonte genérica
import { Onboarding } from './Onboarding'
import { Teaser } from './Teaser'
import { ROTEIRO, VIDEO_ID } from './roteiro'
import { TEASER, TEASER_ID } from './roteiroTeaser'
import { measureScenes, type SceneMeta } from './lib/narration'
import { sec } from './lib/timing'
import type { Cena } from './lib/types'

// Trilha padrão (herdada do estúdio do TOM). A/B por props:
//   npx remotion render onboarding-professor --props='{"musicFile":"music/opcao-a.mp3"}'
const MUSIC_DEFAULT = 'music/tom-theme.mp3'

// O áudio dita a duração: mede os MP3 e dimensiona cada cena (+0.8s de respiro).
// A trilha entra SEMPRE por padrão — via defaultProps, NUNCA via check de
// undefined: o defaultProps entrega `null`, então `=== undefined` nunca
// dispara e o vídeo sai sem música (2ª vez que esse bug morde — teaser 02/08,
// flagrado pelo Alf). Pra rodar sem trilha: --props='{"musicFile":null}'
const metadataDoRoteiro =
  (videoId: string, roteiro: Cena[]) =>
  async ({ props }: { props: { scenes: SceneMeta[]; musicFile: string | null } }) => {
    const scenes = await measureScenes(videoId, roteiro)
    const durationInFrames = scenes.reduce((a, s) => a + s.durationInFrames, 0)
    const musicFile = props.musicFile === undefined ? MUSIC_DEFAULT : props.musicFile
    return {
      durationInFrames: Math.max(durationInFrames, sec(10)),
      props: { ...props, scenes, musicFile },
    }
  }

export const Root: React.FC = () => (
  <>
    <Composition
      id={VIDEO_ID}
      component={Onboarding}
      fps={30}
      width={1080}
      height={1920} // 9:16 — o app é PWA de celular, o vídeo tem que ter a cara dele
      defaultProps={{ scenes: [] as SceneMeta[], musicFile: MUSIC_DEFAULT as string | null }}
      calculateMetadata={metadataDoRoteiro(VIDEO_ID, ROTEIRO)}
    />
    <Composition
      id={TEASER_ID}
      component={Teaser}
      fps={30}
      width={1080}
      height={1920}
      defaultProps={{ scenes: [] as SceneMeta[], musicFile: MUSIC_DEFAULT as string | null }}
      calculateMetadata={metadataDoRoteiro(TEASER_ID, TEASER)}
    />
  </>
)
