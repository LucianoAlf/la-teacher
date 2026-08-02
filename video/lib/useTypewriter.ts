// Digitação letra-a-letra dirigida pelo frame (determinística pro render).
import { useCurrentFrame } from 'remotion';
import { FPS } from './timing';

export function useTypewriter(text: string, startFrame: number, cps = 14) {
  const frame = useCurrentFrame();
  const chars = Math.max(0, Math.floor(((frame - startFrame) / FPS) * cps));
  const shown = text.slice(0, Math.min(chars, text.length));
  return { shown, done: chars >= text.length, caretOn: Math.floor(frame / 8) % 2 === 0 };
}
