// Harness de diagnóstico da "tremida ao digitar" (relato do Matheus, 17/08 20:55).
// Monta a tela REAL do caderno manual com a rede dublada e instrumenta:
//   - quantos renders o componente faz por tecla
//   - a sequência de textos do selo de salvamento
//   - o deslocamento horizontal do título do cabeçalho (layout shift medido)
import React from 'react'
import ReactDOM from 'react-dom/client'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import '../styles/tokens.css'
import '../styles/tailwind.css'
import RegistroManualPage from '../features/registroManual/RegistroManual'

declare global {
  interface Window {
    __diag: {
      renders: number
      selo: string[]
      titulo: Array<{ x: number; largura: number }>
      shifts: number
    }
  }
}

window.__diag = { renders: 0, selo: [], titulo: [], shifts: 0 }

// Sonda: conta cada render da árvore e registra o selo + a posição do título.
function Sonda({ children }: { children: React.ReactNode }) {
  window.__diag.renders += 1
  React.useEffect(() => {
    const selo = document.querySelector('header span.font-bold:last-child')
    const titulo = document.querySelector('header b')
    const texto = (selo?.textContent ?? '').trim()
    const anterior = window.__diag.selo[window.__diag.selo.length - 1]
    if (texto && texto !== anterior) window.__diag.selo.push(texto)
    if (titulo) {
      const r = titulo.getBoundingClientRect()
      const ultimo = window.__diag.titulo[window.__diag.titulo.length - 1]
      const atual = { x: Math.round(r.x * 100) / 100, largura: Math.round(r.width * 100) / 100 }
      if (!ultimo || ultimo.x !== atual.x || ultimo.largura !== atual.largura) {
        window.__diag.titulo.push(atual)
        if (ultimo) window.__diag.shifts += 1
      }
    }
  })
  return <>{children}</>
}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <MemoryRouter initialEntries={['/app/registro-manual/999000']}>
    <Routes>
      <Route path="/app/registro-manual/:aulaId" element={<Sonda><RegistroManualPage /></Sonda>} />
      <Route path="*" element={<div>fora da rota</div>} />
    </Routes>
  </MemoryRouter>,
)
