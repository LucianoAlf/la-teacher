import type { Config } from 'tailwindcss'

// Mapeamento token → utilitário conforme docs/frontend-tokens.md.
// NUNCA usar a paleta default do Tailwind nem cores arbitrárias com hex.
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  darkMode: ['selector', '[data-theme="dark"]'],
  theme: {
    extend: {
      colors: {
        'bg-app': 'var(--bg-app)', 'bg-surface': 'var(--bg-surface)',
        'bg-inset': 'var(--bg-inset)', 'bg-hover': 'var(--bg-hover)',
        'text-primary': 'var(--text-primary)', 'text-secondary': 'var(--text-secondary)',
        'text-muted': 'var(--text-muted)',
        'border-subtle': 'var(--border-subtle)', 'border-strong': 'var(--border-strong)',
        brand: 'var(--brand)', 'brand-text': 'var(--brand-text)',
        'brand-soft': 'var(--brand-soft)', 'on-brand': 'var(--on-brand)',
        success: 'var(--success)', 'success-text': 'var(--success-text)', 'success-soft': 'var(--success-soft)',
        danger: 'var(--danger)', 'danger-text': 'var(--danger-text)', 'danger-soft': 'var(--danger-soft)',
        warning: 'var(--warning)', 'warning-text': 'var(--warning-text)', 'warning-soft': 'var(--warning-soft)',
        info: 'var(--info)', 'info-text': 'var(--info-text)', 'info-soft': 'var(--info-soft)',
      },
      borderRadius: { sm: 'var(--r-sm)', md: 'var(--r-md)', lg: 'var(--r-lg)', xl: 'var(--r-xl)', full: 'var(--r-full)' },
      boxShadow: { card: 'var(--shadow-card)', fab: 'var(--shadow-fab)' },
      fontFamily: { sans: 'var(--font)', mono: 'var(--mono)' },
      keyframes: {
        // pulso do dot "agora" (protótipo golden-path) — só opacidade, sem cor
        'pulse-soft': { '0%,100%': { opacity: '1' }, '50%': { opacity: '.45' } },
        // onda da gravação (protótipo .wave) — só altura
        wave: { '0%,100%': { height: '10px' }, '50%': { height: '56px' } },
        // robô do "processando" (protótipo .bot-big) — só translação
        bob: { '0%,100%': { transform: 'translateY(0)' }, '50%': { transform: 'translateY(-7px)' } },
      },
      animation: {
        'pulse-soft': 'pulse-soft 1.6s infinite',
        wave: 'wave 1s ease-in-out infinite',
        bob: 'bob 2.2s ease-in-out infinite',
      },
    },
  },
  plugins: [],
} satisfies Config
