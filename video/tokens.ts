/**
 * Os MESMOS tokens do app (src/styles/tokens.css) — copiados como constantes
 * porque o Remotion roda fora do pipeline do Tailwind. Se um token mudar lá,
 * muda aqui. Tema dark (a cara do LA Teacher).
 */
export const C = {
  bgApp: '#0A0F0E', // ink-950
  bgSurface: '#111916', // ink-900
  bgHover: '#1A2421', // ink-800
  bgRaised: '#243430', // ink-700
  brand: '#2A9D8F', // teal-500 — a assinatura do Fábio
  brandLight: '#48BFB3', // teal-400
  brandSoft: 'rgba(42,157,143,.15)',
  brandBorder: 'rgba(42,157,143,.30)',
  text: '#F5F5F5', // white-off
  textDim: '#9CA3AF', // slate-400
  textMuted: 'rgba(245,245,245,.45)',
  border: '#1E2A26',
  borderStrong: '#2C3B36',
  success: '#22C55E',
  danger: '#EF4444',
  warning: '#EAB308',
  pink: '#E91451', // a marca da família LA
} as const

export const FONT =
  '"Prompt", system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", sans-serif'
