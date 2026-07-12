import { defineConfig, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'
import { VitePWA } from 'vite-plugin-pwa'

// Resolve %OG_BASE_URL% no index.html pela URL absoluta de produção.
// Na Vercel vem de VERCEL_PROJECT_PRODUCTION_URL (domínio estável do projeto);
// fallback local pro domínio conhecido. Assim o og:image nunca fica relativo.
function ogBaseUrl(): Plugin {
  const host = process.env.VERCEL_PROJECT_PRODUCTION_URL || 'la-teacher.vercel.app'
  const base = `https://${host}`
  return {
    name: 'la-og-base-url',
    transformIndexHtml: (html) => html.replaceAll('%OG_BASE_URL%', base),
  }
}

export default defineConfig({
  plugins: [
    react(),
    ogBaseUrl(),
    // PWA instalável: service worker (precache do shell + auto-update) que destrava
    // o convite de instalação no Android. O manifest é o nosso (public/manifest.webmanifest),
    // por isso manifest:false — o plugin cuida só do service worker + registro.
    VitePWA({
      registerType: 'autoUpdate',
      injectRegister: 'auto',
      manifest: false,
      includeAssets: ['icons/*.png', 'icons/*.svg', 'og-image.png'],
      workbox: {
        globPatterns: ['**/*.{js,css,html,svg,png,webmanifest,woff2}'],
        navigateFallback: '/index.html',
        navigateFallbackDenylist: [/^\/icons\//, /\.webmanifest$/],
        cleanupOutdatedCaches: true,
        clientsClaim: true,
        skipWaiting: true,
      },
      devOptions: { enabled: false },
    }),
  ],
  // Respeita a porta atribuída pelo harness (PORT) — 5173 pode estar ocupada
  // por outro app (ex.: LA-performance-report). strictPort=false deixa subir.
  server: { port: Number(process.env.PORT) || 5173 },
})
