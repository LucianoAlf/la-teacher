import { useState, type FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { Button } from '../../components/ui'
import { classificarFalhaAuth, useAuth, type FalhaLogin } from '../../lib/auth'
import { supabase } from '../../lib/supabase'
import { CapaLogin, FaixaCapa, RotuloCapa, campoCapa, campoCapaStyle } from './CapaLogin'

/**
 * Cada falha tem a sua frase, e cada frase leva a uma ação diferente: conferir
 * a senha, conferir a internet, esperar. Uma frase só pra tudo manda o
 * professor procurar no lugar errado — foi o que aconteceu no piloto.
 */
const RECADO: Record<FalhaLogin, string> = {
  credenciais: 'E-mail ou senha incorretos. Confere e tenta de novo.',
  conexao: 'Não consegui falar com o servidor. Confere a internet e tenta de novo.',
  muitas_tentativas: 'Muitas tentativas seguidas. Espera um minutinho e tenta de novo.',
  inesperado: 'Deu um problema do nosso lado. Tenta de novo em um minutinho.',
}

/**
 * /app/login — entrar, e pedir link de nova senha.
 *
 * Os dois modos dividem a mesma capa porque são a mesma tela na cabeça do
 * professor: "eu quero entrar". Ele só troca o caminho quando a senha falha.
 */
export default function LoginPage() {
  const { signIn } = useAuth()
  const navigate = useNavigate()
  const [modo, setModo] = useState<'entrar' | 'recuperar'>('entrar')
  const [email, setEmail] = useState('')
  const [senha, setSenha] = useState('')
  const [erro, setErro] = useState<string | null>(null)
  const [aviso, setAviso] = useState<string | null>(null)
  const [enviando, setEnviando] = useState(false)

  function trocarPara(destino: 'entrar' | 'recuperar') {
    setModo(destino)
    setErro(null)
    setAviso(null)
  }

  async function entrar(e: FormEvent) {
    e.preventDefault()
    setErro(null)
    setEnviando(true)
    const { falha } = await signIn(email.trim(), senha)
    setEnviando(false)
    if (falha) {
      setErro(RECADO[falha])
      return
    }
    navigate('/app', { replace: true })
  }

  async function pedirLink(e: FormEvent) {
    e.preventDefault()
    setErro(null)
    setAviso(null)
    setEnviando(true)
    const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), {
      redirectTo: `${window.location.origin}/app/nova-senha`,
    })
    setEnviando(false)
    if (error) {
      // Mesmo cuidado do login: sem rede não é "não consegui enviar", é "não
      // cheguei a tentar". Mas aqui não existe senha errada — 'credenciais'
      // num pedido de link só pode ser e-mail malformado.
      const falha = classificarFalhaAuth(error)
      setErro(
        falha === 'credenciais'
          ? 'Confere se o e-mail está escrito certo.'
          : RECADO[falha],
      )
      return
    }
    // Resposta idêntica exista ou não a conta: quem digita um e-mail alheio não
    // pode descobrir por aqui quem tem acesso ao LA Teacher.
    setAviso('Se esse e-mail tiver acesso ao LA Teacher, o link chega em instantes. Dá uma olhada na caixa de entrada — e no spam.')
  }

  const linkDiscreto = 'text-[12px] font-semibold underline underline-offset-2'

  return (
    <CapaLogin>
      {modo === 'entrar' ? (
        <>
          <form className="flex flex-col gap-3" onSubmit={entrar}>
            <label className="flex flex-col gap-[6px]">
              <RotuloCapa>E-mail</RotuloCapa>
              <input
                type="email"
                autoComplete="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="voce@lamusic.com.br"
                className={campoCapa}
                style={campoCapaStyle}
              />
            </label>

            <label className="flex flex-col gap-[6px]">
              <RotuloCapa>Senha</RotuloCapa>
              <input
                type="password"
                autoComplete="current-password"
                required
                value={senha}
                onChange={(e) => setSenha(e.target.value)}
                placeholder="••••••••"
                className={campoCapa}
                style={campoCapaStyle}
              />
            </label>

            {erro && <FaixaCapa tom="erro">{erro}</FaixaCapa>}

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

          <div className="mt-4 text-center">
            <button
              type="button"
              onClick={() => trocarPara('recuperar')}
              className={linkDiscreto}
              style={{ color: 'var(--login-text-muted)' }}
            >
              Esqueci minha senha
            </button>
          </div>

          <p className="mt-4 text-center text-[12px] leading-relaxed" style={{ color: 'var(--login-text-muted)' }}>
            Sem acesso ainda? Fala com a coordenação da sua unidade pra ativar seu login.
          </p>
        </>
      ) : (
        <>
          <form className="flex flex-col gap-3" onSubmit={pedirLink}>
            <p className="text-[13px] leading-[1.5]" style={{ color: 'var(--login-text-muted)' }}>
              Coloca teu e-mail que eu te mando um link pra criar uma senha nova.
            </p>

            <label className="flex flex-col gap-[6px]">
              <RotuloCapa>E-mail</RotuloCapa>
              <input
                type="email"
                autoComplete="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="voce@lamusic.com.br"
                className={campoCapa}
                style={campoCapaStyle}
              />
            </label>

            {erro && <FaixaCapa tom="erro">{erro}</FaixaCapa>}
            {aviso && <FaixaCapa tom="aviso">{aviso}</FaixaCapa>}

            <Button type="submit" block disabled={enviando} className="mt-2">
              {enviando ? (
                <>
                  <i className="fa-solid fa-spinner fa-spin" aria-hidden="true" /> Enviando…
                </>
              ) : (
                <>
                  <i className="fa-solid fa-paper-plane" aria-hidden="true" /> Enviar link
                </>
              )}
            </Button>
          </form>

          <div className="mt-4 text-center">
            <button
              type="button"
              onClick={() => trocarPara('entrar')}
              className={linkDiscreto}
              style={{ color: 'var(--login-text-muted)' }}
            >
              Voltar pro login
            </button>
          </div>
        </>
      )}
    </CapaLogin>
  )
}
