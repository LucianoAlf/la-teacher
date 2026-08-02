// Cursor sintético: bolinha translúcida que viaja por keyframes com easing suave
// e solta um "ripple" nos cliques. Coordenadas no espaço do pai (position:relative).
// Cada clique também TOCA o tap de UI sozinho (clickSound={false} desliga).
import { interpolate, useCurrentFrame, Easing } from 'remotion';
import { Sfx, SFX } from './sfx';

export type CursorKeyframe = { frame: number; x: number; y: number; click?: boolean };

export const Cursor: React.FC<{ keyframes: CursorKeyframe[]; size?: number; clickSound?: boolean }> =
  ({ keyframes, size = 34, clickSound = true }) => {
  const frame = useCurrentFrame();
  if (keyframes.length < 2) return null;
  // interpolate exige inputRange estritamente crescente; keyframes com frame
  // repetido (idioma "chega e clica no mesmo frame") são deduplicados pro x/y.
  const sorted = [...keyframes].sort((a, b) => a.frame - b.frame);
  const posKfs = sorted.filter((k, i) => i === 0 || k.frame > sorted[i - 1].frame);
  const frames = posKfs.map(k => k.frame);
  const opts = { extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: Easing.inOut(Easing.cubic) } as const;
  const x = posKfs.length < 2 ? posKfs[0].x : interpolate(frame, frames, posKfs.map(k => k.x), opts);
  const y = posKfs.length < 2 ? posKfs[0].y : interpolate(frame, frames, posKfs.map(k => k.y), opts);
  // "Pressiona" levemente no clique (janela 12f; o ripple usa 16f de propósito — anel sobrevive ao press)
  const clicks = sorted.filter(k => k.click);
  const nearClick = clicks.find(k => frame >= k.frame && frame <= k.frame + 12);
  const press = nearClick
    ? interpolate(frame - nearClick.frame, [0, 4, 12], [1, 0.82, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })
    : 1;
  return (
    <>
      {clickSound && clicks.map(k => <Sfx key={`snd-${k.frame}`} file={SFX.tap} at={k.frame} volume={0.45} />)}
      {clicks.map(k => {
        if (frame < k.frame || frame > k.frame + 16) return null;
        const t = (frame - k.frame) / 16;
        return (
          <div key={k.frame} style={{
            position: 'absolute', left: k.x, top: k.y, width: size * (1 + t * 1.6), height: size * (1 + t * 1.6),
            transform: 'translate(-50%, -50%)', borderRadius: '50%',
            border: '3px solid rgba(163,190,80,0.9)', opacity: 1 - t,
          }} />
        );
      })}
      <div style={{
        position: 'absolute', left: x, top: y, width: size, height: size,
        transform: `translate(-50%, -50%) scale(${press})`, borderRadius: '50%',
        background: 'rgba(255,255,255,0.35)', border: '2.5px solid rgba(255,255,255,0.85)',
        boxShadow: '0 4px 14px rgba(0,0,0,0.45)', zIndex: 50,
      }} />
    </>
  );
};
