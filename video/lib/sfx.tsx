// Catálogo de efeitos sonoros do estúdio (gerados 1x via scripts/gen-sfx.mjs,
// salvos em public/sfx/ — reusados por todos os vídeos).
// <Sfx file={SFX.tap} at={90} /> toca o som no frame `at` da cena atual.
import { Audio, Sequence, staticFile } from 'remotion';

export const SFX = {
  /** clique de botão/elemento (usado automático pelo Cursor) */
  tap: 'sfx/ui-tap.mp3',
  /** elemento materializando na tela */
  popIn: 'sfx/pop-in.mp3',
  /** painel/sheet deslizando */
  swoosh: 'sfx/swoosh.mp3',
  /** conquista/conclusão (🎉) */
  chime: 'sfx/success-chime.mp3',
  /** bolha de mensagem chegando (usado automático pelo WhatsAppChat) */
  msgPop: 'sfx/msg-pop.mp3',
  /** abertura de vídeo */
  introWhoosh: 'sfx/intro-whoosh.mp3',
} as const;

export const Sfx: React.FC<{ file: string; at: number; volume?: number; rate?: number }> =
  ({ file, at, volume = 0.4, rate = 1 }) => (
  <Sequence from={at} durationInFrames={60}>
    <Audio src={staticFile(file)} volume={volume} playbackRate={rate} />
  </Sequence>
);
