// Áudio dita o tempo: mede os MP3 do manifest e dimensiona cada cena.
// Sem manifest (narração ainda não gerada) → cai no duracaoMinS do roteiro.
// GOTCHA: o Studio cacheia manifest/MP3 (HTTP + cache interno do media-utils);
// depois de regenerar narração com o Studio aberto, RECARREGUE a página.
// Render via CLI é processo novo — sempre lê o estado atual.
import { Audio, staticFile, interpolate, useCurrentFrame } from 'remotion';
import { getAudioDurationInSeconds } from '@remotion/media-utils';
import { sceneDuration } from './timing';
import type { Cena } from './types';

export type SceneMeta = { id: string; durationInFrames: number; audioFile: string | null };

export async function measureScenes(videoId: string, roteiro: Cena[]): Promise<SceneMeta[]> {
  let manifest: Record<string, string> | null = null;
  try {
    const res = await fetch(staticFile(`audio/${videoId}/manifest.json`));
    if (res.ok) manifest = await res.json();
  } catch {
    manifest = null;
  }
  return Promise.all(roteiro.map(async (c) => {
    const file = manifest?.[c.id] ? `audio/${videoId}/${manifest[c.id]}` : null;
    let audioS: number | null = null;
    if (file) {
      try {
        audioS = await getAudioDurationInSeconds(staticFile(file));
      } catch {
        audioS = null; // mp3 sumiu/corrompeu → não trava o Studio
      }
    }
    return { id: c.id, durationInFrames: sceneDuration(audioS, c.duracaoMinS), audioFile: audioS == null ? null : file };
  }));
}

export const SceneAudio: React.FC<{ meta: SceneMeta }> = ({ meta }) =>
  meta.audioFile ? <Audio src={staticFile(meta.audioFile)} /> : null;

export const Caption: React.FC<{ text: string }> = ({ text }) => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [0, 10], [0, 1], { extrapolateRight: 'clamp' });
  return (
    <div className="absolute inset-x-0 bottom-[72px] flex justify-center z-50" style={{ opacity }}>
      <div className="max-w-[80%] px-7 py-3 rounded-full bg-black/70 text-fg text-[30px] font-sans font-medium text-center">
        {text}
      </div>
    </div>
  );
};
