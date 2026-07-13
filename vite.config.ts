import { execSync } from 'node:child_process'
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

// Selo de versão: qual build o usuário está rodando. Na Vercel vem o SHA do commit
// (VERCEL_GIT_COMMIT_SHA); local cai pro git; sem git, 'dev'. Injetado como
// __APP_VERSION__ / __BUILD_TIME__ (ver src/env.d.ts) e mostrado no Perfil.
function appVersion(): string {
  const sha = process.env.VERCEL_GIT_COMMIT_SHA
  if (sha) return sha.slice(0, 7)
  try {
    return execSync('git rev-parse --short HEAD').toString().trim()
  } catch {
    return 'dev'
  }
}
const BUILD_TIME = new Date().toISOString()

export default defineConfig({
  plugins: [
    react(),
    ogBaseUrl(),
    // PWA instalável: service worker (precache do shell) que destrava o convite de
    // instalação no Android. registerType:'prompt' — a versão nova NÃO se aplica
    // sozinha (evita janela de código velho servido enquanto atualiza): o app avisa
    // e o professor toca "Atualizar" (updateServiceWorker no AtualizacaoDisponivel).
    // injectRegister:false — o registro é feito pelo hook useRegisterSW. O manifest
    // é o nosso (public/manifest.webmanifest), por isso manifest:false.
    VitePWA({
      registerType: 'prompt',
      injectRegister: false,
      manifest: false,
      includeAssets: ['icons/*.png', 'icons/*.svg', 'og-image.png'],
      workbox: {
        // App shell model: bundles com hash (js/css/fontes) ficam em precache
        // cache-first (imutáveis, carregam na hora). O HTML NÃO entra no precache
        // (repare: sem 'html' aqui) — ele é a "portaria" que aponta os bundles,
        // e é a única coisa mutável a cada deploy. Servir o HTML do cache é o
        // clássico "corrijo e não muda".
        globPatterns: ['**/*.{js,css,svg,png,webmanifest,woff2}'],
        runtimeCaching: [
          {
            // Documento (navegação) em NETWORK-FIRST: abre sempre no HTML mais
            // novo → puxa os bundles novos. request.mode === 'navigate' é o que
            // importa (é a requisição da "portaria"); testar com fetch de JS
            // solto não prova nada. Cai no cache só quando a rede falha ou
            // estoura o timeout — sala de aula offline continua abrindo.
            // networkTimeoutSeconds: 3 igual ao LA Organizer (mesma config nos
            // dois apps facilita a manutenção).
            urlPattern: ({ request }) => request.mode === 'navigate',
            handler: 'NetworkFirst',
            options: {
              cacheName: 'documento-html',
              networkTimeoutSeconds: 3,
              expiration: { maxEntries: 1 },
            },
          },
        ],
        cleanupOutdatedCaches: true,
      },
      devOptions: { enabled: false },
    }),
  ],
  define: {
    __APP_VERSION__: JSON.stringify(appVersion()),
    __BUILD_TIME__: JSON.stringify(BUILD_TIME),
  },
  // Respeita a porta atribuída pelo harness (PORT) — 5173 pode estar ocupada
  // por outro app (ex.: LA-performance-report). strictPort=false deixa subir.
  server: { port: Number(process.env.PORT) || 5173 },
})
