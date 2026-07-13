import { useEffect, useRef, useState } from 'react'

/**
 * A demonstração — a tela que vende o app inteiro em ~6s, sem clique, sem API.
 * A fala crua do professor sai palavra por palavra; os termos-chave acendem em
 * teal; então a fala esmaece e se reorganiza sozinha em dois cards estruturados.
 * Input solto → output organizado, lado a lado. Loop infinito (autoplay).
 * Respeita prefers-reduced-motion: mostra direto o estado final.
 */

// A fala e os cards que ela vira. "a maria é o contrário" = boa no agudo, ruim no ritmo.
const FALA = 'o gustavo foi bem no ritmo mas desafina no agudo, a maria é o contrário…'
const REALCE = new Set(['gustavo', 'ritmo', 'agudo', 'maria']) // puxam pros cards
const CARDS = [
  { nome: 'Gustavo', progresso: 'Foi bem no ritmo', proximo: 'Afinar no agudo' },
  { nome: 'Maria', progresso: 'Afina bem no agudo', proximo: 'Trabalhar o ritmo' },
]

// 0 ouvindo · 1 fala saindo · 2 termos acendem · 3 virou estrutura
type Fase = 0 | 1 | 2 | 3

export function DemoMorph() {
  const [fase, setFase] = useState<Fase>(0)
  const timers = useRef<number[]>([])

  useEffect(() => {
    const reduzir = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ?? false
    if (reduzir) {
      setFase(3)
      return
    }
    const ciclo = () => {
      setFase(0)
      timers.current.push(window.setTimeout(() => setFase(1), 500)) // fala começa a sair
      timers.current.push(window.setTimeout(() => setFase(2), 2600)) // termos acendem
      timers.current.push(window.setTimeout(() => setFase(3), 3500)) // vira estrutura
      timers.current.push(window.setTimeout(ciclo, 8200)) // segura nos cards e repete
    }
    ciclo()
    return () => {
      timers.current.forEach(clearTimeout)
      timers.current = []
    }
  }, [])

  const palavras = FALA.split(' ')

  return (
    <div className="flex w-full flex-col items-center">
      {/* Status do Fábio: ouvindo → estruturou */}
      <div
        className="mb-5 inline-flex items-center gap-2 rounded-full px-3 py-[6px] text-[11px] font-bold"
        style={{ background: 'var(--login-input-bg)', color: 'var(--login-accent)' }}
      >
        <span className="relative flex h-[7px] w-[7px]">
          <span
            className="absolute inline-flex h-full w-full rounded-full animate-pulse-soft"
            style={{ background: 'var(--login-accent)' }}
          />
        </span>
        {fase >= 3 ? 'Fábio estruturou' : 'Fábio ouvindo…'}
      </div>

      {/* A FALA CRUA — sai palavra por palavra; encolhe/esmaece quando vira card */}
      <p
        className="max-w-[300px] text-center text-[15.5px] leading-relaxed transition-all duration-700"
        style={{
          color: 'var(--login-text)',
          opacity: fase >= 3 ? 0.4 : 1,
          transform: fase >= 3 ? 'scale(.92)' : 'scale(1)',
        }}
      >
        <span aria-hidden="true" style={{ color: 'var(--login-text-muted)' }}>“</span>
        {palavras.map((p, i) => {
          const limpa = p.replace(/[.,…]/g, '').toLowerCase()
          const acende = fase >= 2 && REALCE.has(limpa)
          return (
            <span
              key={i}
              style={{
                color: acende ? 'var(--login-accent)' : undefined,
                fontWeight: acende ? 700 : 400,
                opacity: fase >= 1 ? 1 : 0,
                transitionProperty: 'opacity, color, font-weight',
                transitionDuration: '450ms',
                transitionTimingFunction: 'ease',
                transitionDelay: fase === 1 ? `${i * 85}ms` : '0ms',
              }}
            >
              {p}{' '}
            </span>
          )
        })}
        <span aria-hidden="true" style={{ color: 'var(--login-text-muted)' }}>”</span>
      </p>

      {/* OS CARDS ESTRUTURADOS — sobem quando a fala se reorganiza */}
      <div className="mt-6 grid w-full max-w-[330px] gap-[10px]">
        {CARDS.map((c, i) => (
          <div
            key={c.nome}
            className="flex items-center gap-3 rounded-lg p-3 text-left transition-all duration-500"
            style={{
              background: 'var(--login-input-bg)',
              border: '1px solid var(--login-input-border)',
              opacity: fase >= 3 ? 1 : 0,
              transform: fase >= 3 ? 'translateY(0)' : 'translateY(14px)',
              transitionDelay: fase >= 3 ? `${i * 180}ms` : '0ms',
            }}
          >
            <span
              className="flex h-9 w-9 flex-none items-center justify-center rounded-full text-[13px] font-extrabold"
              style={{ background: 'var(--brand-soft)', color: 'var(--login-accent)' }}
            >
              {c.nome.charAt(0)}
            </span>
            <div className="min-w-0 flex-1">
              <b className="block text-[14px]" style={{ color: 'var(--login-text)' }}>
                {c.nome}
              </b>
              <span className="block text-[12px]" style={{ color: 'var(--login-text-muted)' }}>
                <span style={{ color: 'var(--login-accent)' }}>Progresso</span> · {c.progresso}
              </span>
              <span className="block text-[12px]" style={{ color: 'var(--login-text-muted)' }}>
                <span style={{ color: 'var(--login-accent)' }}>Próximo passo</span> · {c.proximo}
              </span>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
