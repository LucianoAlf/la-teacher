// Zoom/pan de "câmera": escala e desloca o conteúdo entre dois enquadramentos.
// Não usada no grupos-de-tarefas; mantida pra vídeos futuros (zoom em detalhe).
import { interpolate, useCurrentFrame, Easing } from 'remotion';

type Frame = { scale: number; x: number; y: number };

export const Camera: React.FC<{
  from: Frame; to: Frame; startFrame: number; endFrame: number; children: React.ReactNode;
}> = ({ from, to, startFrame, endFrame, children }) => {
  const frame = useCurrentFrame();
  const opts = { extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: Easing.inOut(Easing.quad) } as const;
  const scale = interpolate(frame, [startFrame, endFrame], [from.scale, to.scale], opts);
  const x = interpolate(frame, [startFrame, endFrame], [from.x, to.x], opts);
  const y = interpolate(frame, [startFrame, endFrame], [from.y, to.y], opts);
  return (
    <div style={{ width: '100%', height: '100%', transform: `scale(${scale}) translate(${x}px, ${y}px)` }}>
      {children}
    </div>
  );
};
