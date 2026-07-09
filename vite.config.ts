import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Plugin PWA entra na fase do Sprint 3 (ver docs/repo-estrutura.md)
export default defineConfig({
  plugins: [react()],
  // Respeita a porta atribuída pelo harness (PORT) — 5173 pode estar ocupada
  // por outro app (ex.: LA-performance-report). strictPort=false deixa subir.
  server: { port: Number(process.env.PORT) || 5173 },
})
