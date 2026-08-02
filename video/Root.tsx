import React from 'react'
import { Composition, staticFile } from 'remotion'
import { Onboarding } from './Onboarding'
import { ROTEIRO, VIDEO_ID } from './roteiro'
import { measureScenes, type SceneMeta } from './lib/narration'
import { sec } from './lib/timing'

// Trilha padrão (herdada do estúdio do TOM). A/B por props:
//   npx remotion render onboarding-professor --props='{"musicFile":"music/opcao-a.mp3"}'
const MUSIC_DEFAULT = 'music/tom-theme.mp3'

export const Root: React.FC = () => (
  <>
    <Composition
      id={VIDEO_ID}
      component={Onboarding}
      fps={30}
      width={1080}
      height={1920} // 9:16 — o app é PWA de celular, o vídeo tem que ter a cara dele
      defaultProps={{ scenes: [] as SceneMeta[], musicFile: null as string | null }}
      // O áudio dita a duração: mede os MP3 e dimensiona cada cena (+0.8s de respiro).
      calculateMetadata={async ({ props }) => {
        const scenes = await measureScenes(VIDEO_ID, ROTEIRO)
        const durationInFrames = scenes.reduce((a, s) => a + s.durationInFrames, 0)
        // A trilha entra SEMPRE por padrão. (Antes eu checava com fetch(staticFile);
        // no render por CLI esse fetch falha e o vídeo saía mudo — foi o "falta música".)
        // Pra rodar sem trilha: --props='{"musicFile":null}'
        const musicFile = props.musicFile === undefined ? MUSIC_DEFAULT : props.musicFile
        return {
          durationInFrames: Math.max(durationInFrames, sec(10)),
          props: { ...props, scenes, musicFile },
        }
      }}
    />
  </>
)
