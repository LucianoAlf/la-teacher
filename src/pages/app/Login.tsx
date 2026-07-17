import { useState, type FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { Button } from '../../components/ui'
import { useAuth } from '../../lib/auth'

/**
 * /app/login — capa da marca (LA Teacher · família LA).
 * Tela dark FIXA (independe do tema): atmosfera rosa da casa —
 * pontinhos halftone + marca d'água LA grande + glow no avatar do Fábio —
 * com o TEAL do Fábio só no botão. Todos os valores vêm de tokens.
 */
export default function LoginPage() {
  const { signIn } = useAuth()
  const navigate = useNavigate()
  const [email, setEmail] = useState('')
  const [senha, setSenha] = useState('')
  const [erro, setErro] = useState<string | null>(null)
  const [enviando, setEnviando] = useState(false)

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    setErro(null)
    setEnviando(true)
    const { error } = await signIn(email.trim(), senha)
    setEnviando(false)
    if (error) {
      setErro('E-mail ou senha incorretos. Confere e tenta de novo.')
      return
    }
    navigate('/app', { replace: true })
  }

  const campo = 'rounded-md px-[14px] py-[12px] text-sm outline-none placeholder:text-text-muted'
  const campoStyle = {
    background: 'var(--login-input-bg)',
    border: '1px solid var(--login-input-border)',
    color: 'var(--login-text)',
  }

  return (
    <div className="flex h-svh justify-center overflow-hidden" style={{ background: 'var(--login-bg)' }}>
      <div
        className="relative flex h-svh w-full max-w-[430px] flex-col overflow-x-hidden overflow-y-auto"
        style={{ background: 'var(--login-bg)', color: 'var(--login-text)' }}
      >
        {/* ---- ATMOSFERA — cobre o topo, atrás de tudo (pontinhos + marca d'água grande) ---- */}
        <div aria-hidden="true" className="pointer-events-none absolute inset-x-0 top-0 z-0 h-[60%]">
          <div
            className="absolute inset-0"
            style={{ backgroundImage: 'radial-gradient(var(--login-dots) 1px, transparent 1.2px)', backgroundSize: '14px 14px' }}
          />
          <svg
            viewBox="0 0 943.27 1072.1"
            preserveAspectRatio="xMidYMid meet"
            className="absolute left-1/2 top-0 w-[470px] -translate-x-1/2 -rotate-6"
            style={{ color: 'var(--login-watermark)' }}
          >
            <path
              fill="currentColor"
              d="M239.82 637.01c0,29.4 39.64,3.39 71.41,-12.52 10.64,-5.33 20.21,-9.03 30.22,-13.96 5.09,-2.51 8.93,-4.67 14.66,-7.42l326.15 -150.9c21.28,-9.87 34.61,-6.35 34.61,-55.94l-156.81 0 -8.81 46.41c-3.46,14.12 -10.92,10.83 -34.65,22.77l-104.2 48.19c-9,3.64 -18.1,8.33 -26.81,12.94 0.52,-23.21 41.14,-215.41 45.65,-226.01 9.92,-23.35 32.37,-28.16 64.77,-28 61.08,0.32 122.24,0.02 183.33,0.02 41.43,0 148.24,-5.46 174.81,4.09 9.43,3.39 18.65,12.15 23.01,21.16 11.27,23.32 -5.76,86.69 -11.74,116.65l-95.52 454.42c-27.78,6.47 -134.41,39.3 -154.6,39.75l16.01 -76.75c5.01,-24.95 9.94,-51.89 15.09,-77.67 5.1,-25.5 10.26,-51.29 15.46,-77.3l15.28 -79.69c-8.22,0.68 -27.73,9.9 -35.31,13.28l-118.01 56.46c-29.64,12.21 -22.44,10.66 -29.05,46.04l-42.9 208.88c-11.1,46.77 -2.82,29.46 -50.8,48.59l-74.81 26.78c-10.56,3.51 -28.2,8.35 -37.83,12.97 0,-11.29 22.85,-124.33 25.58,-137.85 4.8,-23.82 8.4,-44.39 13.25,-68.47l14.17 -69.75c-11.56,2.69 -46.01,18.91 -61.21,24.92 -50.85,20.1 -154.91,78.15 -197.61,46.17 -36.6,-27.4 -15.26,-96.82 -4.88,-138.24 23.54,-93.97 43.31,-194.41 66.69,-286.68 6.16,-24.31 10.58,-46.95 16.8,-71.54l41.02 -179.83c4.25,-18.39 2.61,-17.53 20.71,-23.46l133.93 -42.75c0,24.07 -53.09,261.93 -57.99,286.55 -5.54,27.82 -59.07,267.83 -59.07,287.68zm-123.68 240.73c39.45,0 106.61,-23.58 141.35,-41.96 -0.32,14.25 -33.13,163.72 -33.13,174.48 0,31.95 25.81,61.84 64.05,61.84 17.44,0 75.27,-21.54 96.25,-29.64 70.46,-27.24 107.24,-22.68 123.32,-86.49 15.59,-61.84 32.48,-159.23 46.25,-225.41 2.02,-9.68 0.93,-9.29 8.59,-13.5 6.65,-3.66 23.81,-12.27 30.38,-13.79l-20.43 103.25c-4.37,21.87 -19.32,88.57 -19.32,106.57 0,22.21 14.92,41.72 32.34,51.58 6.4,3.62 13.19,5.49 21.92,6.97 19.83,3.34 159.83,-35.96 182.41,-44.94 33.66,-13.39 36.69,-31.65 45.09,-69.76 27.21,-123.58 52.37,-259.38 80.01,-377.17 7.21,-30.72 13.69,-61.32 19.38,-93.25 6.36,-35.7 13.6,-62.82 4.1,-99.42 -26.73,-102.99 -165.74,-76.34 -263.79,-76.34 -46.82,0 -190.37,-2.98 -225.53,4.16 -22.85,4.64 -40.45,14.79 -55.57,30.57l-12.64 16.07c0.67,-8.09 3.2,-14.75 4.98,-23.73 6.4,-32.14 34.77,-158.93 34.77,-179.46 0,-21.64 -17.32,-44.45 -37.16,-53.39 -24.83,-11.19 -50.3,-1.05 -73.55,6.73 -23.58,7.89 -46.25,14.61 -70.12,22.64 -20.79,7 -50.55,14.67 -66.59,26.17 -34.56,24.76 -35.67,79.39 -49.4,133.92l-69.83 299c-12.21,49.89 -23.16,101.27 -34.85,150.67 -16.65,70.37 -43.89,158.73 26.3,211.3 15.96,11.95 43.1,22.35 70.41,22.35z"
            />
          </svg>
        </div>

        {/* ---- IDENTIDADE (centrada no topo) ---- */}
        <div className="relative z-10 flex flex-1 flex-col items-center justify-center px-7 pt-8 text-center">
          <img
            src="/brand/fabio-avatar.svg"
            alt="Fábio"
            className="mx-auto h-auto w-[120px]"
            style={{ filter: 'drop-shadow(0 0 24px var(--login-glow))' }}
          />
          <h1 className="mt-4 font-brand text-[32px] font-black leading-none tracking-[-.5px]">
            <span className="text-la-pink">LA</span> <span style={{ color: 'var(--login-text)' }}>Teacher</span>
          </h1>
          <p className="mt-2 text-[13px] leading-[1.45]" style={{ color: 'var(--login-text-muted)' }}>
            Suas aulas registradas em segundos, sem digitar.
          </p>
        </div>

        {/* ---- FORMULÁRIO (colado no rodapé, igual o Organizer) ---- */}
        <div className="relative z-10 px-7 pb-10">
          <form className="flex flex-col gap-3" onSubmit={onSubmit}>
            <label className="flex flex-col gap-[6px]">
              <span className="text-[11px] font-semibold uppercase tracking-[.5px]" style={{ color: 'var(--login-text-muted)' }}>
                E-mail
              </span>
              <input
                type="email"
                autoComplete="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="voce@lamusic.com.br"
                className={campo}
                style={campoStyle}
              />
            </label>

            <label className="flex flex-col gap-[6px]">
              <span className="text-[11px] font-semibold uppercase tracking-[.5px]" style={{ color: 'var(--login-text-muted)' }}>
                Senha
              </span>
              <input
                type="password"
                autoComplete="current-password"
                required
                value={senha}
                onChange={(e) => setSenha(e.target.value)}
                placeholder="••••••••"
                className={campo}
                style={campoStyle}
              />
            </label>

            {erro && (
              <div
                className="flex items-center gap-2 rounded-md px-3 py-[10px] text-[13px] font-semibold"
                style={{ background: 'var(--login-danger-soft)', color: 'var(--login-danger)' }}
              >
                <i className="fa-solid fa-circle-exclamation" aria-hidden="true" />
                {erro}
              </div>
            )}

            <Button type="submit" block disabled={enviando} className="mt-2">
              {enviando ? (
                <>
                  <i className="fa-solid fa-spinner fa-spin" aria-hidden="true" /> Entrando…
                </>
              ) : (
                <>
                  <i className="fa-solid fa-arrow-right-to-bracket" aria-hidden="true" /> Entrar
                </>
              )}
            </Button>
          </form>

          <p className="mt-5 text-center text-[12px] leading-relaxed" style={{ color: 'var(--login-text-muted)' }}>
            Sem acesso ainda? Fala com a coordenação da sua unidade pra ativar seu login.
          </p>
        </div>
      </div>
    </div>
  )
}
