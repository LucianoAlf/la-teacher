import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Button, FabioAvatar } from '../../components/ui'
import { DemoMorph } from '../../features/onboarding/DemoMorph'
import { marcarIntroVisto } from '../../features/onboarding/introState'

/**
 * /app/intro — primeiro contato, ANTES do login. 3 telas na capa dark da marca
 * (a mesma atmosfera do login, pra continuidade). Sem API, sem clique obrigatório:
 * a do meio (a demonstração) se explica sozinha. "Pular" pra quem já viu.
 *
 * 1. O Fábio se apresenta.  2. A demonstração (vende o produto).  3. A confiança.
 */
const TOTAL = 3

export default function IntroPage() {
  const navigate = useNavigate()
  const [passo, setPasso] = useState(0)

  function sair() {
    marcarIntroVisto()
    navigate('/app/login', { replace: true })
  }
  const avancar = () => (passo < TOTAL - 1 ? setPasso((p) => p + 1) : sair())

  return (
    <div className="flex h-dvh justify-center overflow-hidden" style={{ background: 'var(--login-bg)' }}>
      <div
        className="relative flex h-dvh w-full max-w-[430px] flex-col overflow-hidden"
        style={{ background: 'var(--login-bg)', color: 'var(--login-text)' }}
      >
        {/* Atmosfera: pontinhos halftone rosa (assinatura da família LA) */}
        <div
          aria-hidden="true"
          className="pointer-events-none absolute inset-0 z-0"
          style={{
            backgroundImage: 'radial-gradient(var(--login-dots) 1px, transparent 1.2px)',
            backgroundSize: '14px 14px',
          }}
        />

        {/* Topo: passos + Pular */}
        <div className="relative z-10 flex items-center justify-between px-6 pt-[calc(14px_+_env(safe-area-inset-top))]">
          <div className="flex gap-[6px]">
            {Array.from({ length: TOTAL }).map((_, i) => (
              <span
                key={i}
                className="h-[6px] rounded-full transition-all duration-300"
                style={{
                  width: i === passo ? '22px' : '6px',
                  background: i === passo ? 'var(--login-accent)' : 'var(--login-input-border)',
                }}
              />
            ))}
          </div>
          {passo < TOTAL - 1 && (
            <button
              type="button"
              onClick={sair}
              className="text-[13px] font-semibold"
              style={{ color: 'var(--login-text-muted)' }}
            >
              Pular
            </button>
          )}
        </div>

        {/* Conteúdo do passo atual (remonta a cada passo → a demo reinicia sozinha) */}
        <div key={passo} className="relative z-10 flex flex-1 animate-fade-in flex-col items-center justify-center px-7 text-center">
          {passo === 0 && <PassoApresentacao />}
          {passo === 1 && <PassoDemonstracao />}
          {passo === 2 && <PassoConfianca />}
        </div>

        {/* CTA */}
        <div className="relative z-10 px-7 pb-[calc(28px_+_env(safe-area-inset-bottom))] pt-2">
          {passo < TOTAL - 1 ? (
            // Botão custom com cores FIXAS: a capa é dark independente do tema,
            // então não dá pra usar o Button ghost (texto segue o tema do aparelho
            // e some no claro). Contorno + texto claro dos tokens --login-*.
            <button
              type="button"
              onClick={avancar}
              className="inline-flex w-full items-center justify-center gap-2 rounded-md py-[13px] text-[14.5px] font-bold transition-transform duration-75 active:scale-[.97]"
              style={{
                border: '1px solid var(--login-input-border)',
                color: 'var(--login-text)',
                background: 'transparent',
              }}
            >
              Continuar <i className="fa-solid fa-arrow-right" aria-hidden="true" />
            </button>
          ) : (
            <Button block onClick={sair}>
              <i className="fa-solid fa-arrow-right-to-bracket" aria-hidden="true" /> Entrar
            </Button>
          )}
        </div>
      </div>
    </div>
  )
}

// --- Tela 1 · O Fábio se apresenta (avatar grande, com respiro) --------------
function PassoApresentacao() {
  return (
    <>
      <FabioAvatar
        className="h-auto w-[150px] animate-bob"
        alt="Fábio"
      />
      <h1 className="mt-8 text-[26px] font-extrabold leading-tight tracking-[-.3px]">
        Oi. Eu sou o Fábio.
      </h1>
      <p className="mt-3 text-[15px] leading-relaxed" style={{ color: 'var(--login-text-muted)' }}>
        Você fala. Eu escrevo.
      </p>
    </>
  )
}

// --- Tela 2 · A demonstração (a mais importante) -----------------------------
function PassoDemonstracao() {
  return (
    <>
      <p className="mb-7 text-[15px] leading-relaxed" style={{ color: 'var(--login-text-muted)' }}>
        Sem digitar. Você só fala como a aula foi —
      </p>
      <DemoMorph />
    </>
  )
}

// --- Tela 3 · A confiança (responde a objeção antes de ela existir) ----------
function PassoConfianca() {
  return (
    <>
      <div
        className="flex h-[76px] w-[76px] items-center justify-center rounded-full text-[30px]"
        style={{ background: 'var(--brand-soft)', color: 'var(--login-accent)' }}
      >
        <i className="fa-solid fa-shield-heart" aria-hidden="true" />
      </div>
      <h1 className="mt-8 text-[26px] font-extrabold leading-tight tracking-[-.3px]">
        Eu nunca invento.
      </h1>
      <p className="mt-3 max-w-[300px] text-[15px] leading-relaxed" style={{ color: 'var(--login-text-muted)' }}>
        Campo vazio é convite. Nada vai pro diário do seu aluno sem você confirmar.
      </p>
    </>
  )
}
