// O áudio dita o tempo: cada cena dura o áudio + respiro, nunca menos que o mínimo do roteiro.
export const FPS = 30;
export const SCENE_PADDING_S = 0.8;

export function sec(s: number): number {
  // ceil de propósito: frame a mais nunca corta áudio; round/floor cortariam.
  return Math.ceil(s * FPS);
}

export function sceneDuration(audioSeconds: number | null, minSeconds: number): number {
  if (audioSeconds == null) return sec(minSeconds);
  return Math.max(sec(minSeconds), sec(audioSeconds + SCENE_PADDING_S));
}

export function sceneStarts(durations: number[]): number[] {
  const starts: number[] = [];
  let acc = 0;
  for (const d of durations) { starts.push(acc); acc += d; }
  return starts;
}
