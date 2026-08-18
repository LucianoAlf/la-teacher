// Config SÓ do harness de diagnóstico. Troca a camada de rede e a sessão por
// dublês; todo o resto (tela, design system, moldura) é o código real.
// A raiz "/" serve diag-tremida.html — assim o preview abre direto no harness.
import path from 'node:path'
import { defineConfig, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'

function indexDoDiag(): Plugin {
  return {
    name: 'diag-index',
    configureServer(server) {
      server.middlewares.use((req, _res, next) => {
        if (req.url === '/' || req.url === '/index.html') req.url = '/diag-tremida.html'
        next()
      })
    },
  }
}

export default defineConfig({
  plugins: [react(), indexDoDiag()],
  resolve: {
    alias: [
      { find: /^(\.\.\/)+lib\/api$/, replacement: path.resolve(__dirname, 'src/__diag__/stub-api.ts') },
      { find: /^(\.\.\/)+lib\/auth$/, replacement: path.resolve(__dirname, 'src/__diag__/stub-auth.tsx') },
    ],
  },
  // cacheDir próprio: o dev server normal (5183) e este compartilhariam
  // node_modules/.vite e o pré-bundle sai com hashes divergentes → duas cópias
  // do React na mesma página ("Invalid hook call").
  cacheDir: 'node_modules/.vite-diag',
  server: { port: 5211, strictPort: true, open: false },
})
