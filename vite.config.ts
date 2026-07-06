import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Plugin PWA entra na fase do Sprint 3 (ver docs/repo-estrutura.md)
export default defineConfig({
  plugins: [react()],
})
