import { useState, type FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { Button } from '../../components/ui'
import { useAuth } from '../../lib/auth'
import { AppFrame } from './AppFrame'

/** /app/login — e-mail + senha no Fábio DS. */
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

  return (
    <AppFrame>
      <div className="flex flex-1 flex-col justify-center gap-6 px-6 pb-10">
        <div className="flex flex-col items-center gap-3 text-center">
          <div className="flex h-16 w-16 items-center justify-center rounded-full bg-brand text-2xl text-on-brand shadow-fab">
            <i className="fa-solid fa-robot" aria-hidden="true" />
          </div>
          <div>
            <h1 className="text-2xl font-extrabold tracking-[-.3px]">LA Teacher</h1>
            <p className="text-[13px] text-text-secondary">A casa do Fábio · entre pra registrar suas aulas</p>
          </div>
        </div>

        <form className="flex flex-col gap-3" onSubmit={onSubmit}>
          <label className="flex flex-col gap-[6px]">
            <span className="text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">E-mail</span>
            <input
              type="email"
              autoComplete="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="voce@lamusic.com.br"
              className="rounded-md border border-border-strong bg-bg-inset px-[14px] py-[12px] text-sm text-text-primary placeholder:text-text-muted focus-visible:border-brand"
            />
          </label>

          <label className="flex flex-col gap-[6px]">
            <span className="text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">Senha</span>
            <input
              type="password"
              autoComplete="current-password"
              required
              value={senha}
              onChange={(e) => setSenha(e.target.value)}
              placeholder="••••••••"
              className="rounded-md border border-border-strong bg-bg-inset px-[14px] py-[12px] text-sm text-text-primary placeholder:text-text-muted focus-visible:border-brand"
            />
          </label>

          {erro && (
            <div className="flex items-center gap-2 rounded-md border border-border-subtle bg-danger-soft px-3 py-[10px] text-[13px] font-semibold text-danger-text">
              <i className="fa-solid fa-circle-exclamation" aria-hidden="true" />
              {erro}
            </div>
          )}

          <Button type="submit" block disabled={enviando} className="mt-1">
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

        <p className="text-center text-[12px] leading-relaxed text-text-muted">
          Sem acesso ainda? Fala com a coordenação da sua unidade pra ativar seu login.
        </p>
      </div>
    </AppFrame>
  )
}
