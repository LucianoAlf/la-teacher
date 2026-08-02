// "Tic tic tic" da digitação: 1 tick por caractere, casado com o useTypewriter
// (mesmos text/startFrame/cps). Alterna 2 samples e varia o pitch de leve por
// índice (determinístico) pra não soar metralhadora. Espaços não clicam.
import { Audio, Sequence, staticFile } from 'remotion';
import { FPS } from './timing';

const TICKS = ['sfx/key-tick-a.mp3', 'sfx/key-tick-b.mp3'];
const TICK_VOLUME = 0.3;

export const TypingTicks: React.FC<{ text: string; startFrame: number; cps?: number }> = ({ text, startFrame, cps = 14 }) => (
  <>
    {[...text].map((ch, i) => {
      if (ch === ' ') return null;
      const at = startFrame + Math.round((i * FPS) / cps);
      const rate = 0.9 + ((i * 7919) % 5) * 0.05; // 0.90..1.10
      return (
        <Sequence key={i} from={at} durationInFrames={15}>
          <Audio src={staticFile(TICKS[i % TICKS.length])} volume={TICK_VOLUME} playbackRate={rate} />
        </Sequence>
      );
    })}
  </>
);
