import { useState, type FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { Button } from '../../components/ui'
import { classificarFalhaAuth, useAuth, type FalhaLogin } from '../../lib/auth'
import { supabase } from '../../lib/supabase'
import {
  entrarComCodigo,
  pedirCodigo,
  type MotivoRecusa,
} from '../../features/login/acessoPorWhatsApp'
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
 * A recusa é sempre a mesma frase, venha de número desconhecido, de professor
 * sem acesso liberado ou de professor inativo. Distinguir seria entregar a
 * lista de quem trabalha na escola pra quem testar número por número — e o
 * backend já responde igual pros três (migration 056).
 */
const RECADO_ZAP: Record<MotivoRecusa, string> = {
  nao_encontrado:
    'Não achei esse número liberado. Confere se digitou certo — e, se estiver certo, fala com a coordenação pra liberar teu acesso.',
  telefone_invalido: 'Faltou algum número. Escreve com o DDD, tipo 21 99999-9999.',
  muitas_tentativas: 'Já mandei alguns códigos aí. Espera uns 15 minutinhos e tenta de novo.',
  nao_consegui_enviar: 'Não consegui te mandar no WhatsApp. Tenta de novo em um minutinho.',
  indisponivel: 'Deu um problema do nosso lado. Tenta de novo em um minutinho.',
  rede: 'Não consegui falar com o servidor. Confere a internet e tenta de novo.',
}

type Modo = 'whatsapp' | 'codigo' | 'email' | 'recuperar'

/**
 * /app/login.
 *
 * O CAMINHO PRINCIPAL É O WHATSAPP, e isso é decisão, não estética: 43 dos 44
 * professores nunca tiveram senha aqui. Pedir e-mail e senha de entrada seria
 * abrir a porta com a chave que quase ninguém tem.
 *
 * E-mail e senha continuam existindo, embaixo, pra quem já entrava assim.
 */
export default function LoginPage() {
  const { signIn } = useAuth()
  const navigate = useNavigate()
  const [modo, setModo] = useState<Modo>('whatsapp')
  const [telefone, setTelefone] = useState('')
  const [codigo, setCodigo] = useState('')
  const [emailOtp, setEmailOtp] = useState('')
  const [mascarado, setMascarado] = useState('')
  const [primeiroNome, setPrimeiroNome] = useState('')
  const [email, setEmail] = useState('')
  const [senha, setSenha] = useState('')
  const [erro, setErro] = useState<string | null>(null)
  const [aviso, setAviso] = useState<string | null>(null)
  const [enviando, setEnviando] = useState(false)

  function trocarPara(destino: Modo) {
    setModo(destino)
    setErro(null)
    setAviso(null)
  }

  async function mandarCodigo(e: FormEvent) {
    e.preventDefault()
    setErro(null)
    setEnviando(true)
    const r = await pedirCodigo(telefone)
    setEnviando(false)
    if (!r.ok) {
      setErro(RECADO_ZAP[r.motivo])
      return
    }
    setEmailOtp(r.email)
    setMascarado(r.telefone_mascarado)
    setPrimeiroNome(r.primeiro_nome)
    setCodigo('')
    trocarPara('codigo')
  }

  async function conferirCodigo(e: FormEvent) {
    e.preventDefault()
    setErro(null)
    setEnviando(true)
    const { falha } = await entrarComCodigo(emailOtp, codigo)
    setEnviando(false)
    if (falha) {
      setErro(
        falha === 'expirado'
          ? 'Esse código já venceu. Pede um novo que eu te mando na hora.'
          : falha === 'codigo_errado'
            ? 'Esse código não bateu. Confere os 8 números da mensagem.'
            : 'Não consegui falar com o servidor. Confere a internet e tenta de novo.',
      )
      return
    }
    navigate('/app', { replace: true })
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
      {modo === 'whatsapp' ? (
        <>
          <form className="flex flex-col gap-3" onSubmit={mandarCodigo}>
            <p className="text-[13px] leading-[1.5]" style={{ color: 'var(--login-text-muted)' }}>
              Coloca teu WhatsApp que eu te mando um código de acesso. Sem senha pra decorar.
            </p>

            <label className="flex flex-col gap-[6px]">
              <RotuloCapa>WhatsApp</RotuloCapa>
              <input
                type="tel"
                inputMode="numeric"
                autoComplete="tel"
                required
                value={telefone}
                onChange={(e) => setTelefone(e.target.value)}
                placeholder="21 99999-9999"
                className={campoCapa}
                style={campoCapaStyle}
              />
            </label>

            {erro && <FaixaCapa tom="erro">{erro}</FaixaCapa>}

            <Button type="submit" block disabled={enviando} className="mt-2">
              {enviando ? (
                <>
                  <i className="fa-solid fa-spinner fa-spin" aria-hidden="true" /> Mandando…
                </>
              ) : (
                <>
                  <i className="fa-brands fa-whatsapp" aria-hidden="true" /> Receber código
                </>
              )}
            </Button>
          </form>

          <div className="mt-4 text-center">
            <button
              type="button"
              onClick={() => trocarPara('email')}
              className={linkDiscreto}
              style={{ color: 'var(--login-text-muted)' }}
            >
              Entrar com e-mail e senha
            </button>
          </div>

          <p className="mt-4 text-center text-[12px] leading-relaxed" style={{ color: 'var(--login-text-muted)' }}>
            Sem acesso ainda? Fala com a coordenação da sua unidade pra ativar seu login.
          </p>
        </>
      ) : modo === 'codigo' ? (
        <>
          <form className="flex flex-col gap-3" onSubmit={conferirCodigo}>
            <p className="text-[13px] leading-[1.5]" style={{ color: 'var(--login-text-muted)' }}>
              {primeiroNome ? `Boa, ${primeiroNome}! ` : ''}Mandei um código no WhatsApp{' '}
              <b style={{ color: 'var(--login-text)' }}>{mascarado}</b>. Ele vale por 1 hora.
            </p>

            <label className="flex flex-col gap-[6px]">
              <RotuloCapa>Código</RotuloCapa>
              <input
                type="text"
                inputMode="numeric"
                autoComplete="one-time-code"
                required
                value={codigo}
                onChange={(e) => setCodigo(e.target.value)}
                // 8 dígitos: é o tamanho que o Supabase Auth gera (medido, não
                // suposto). O placeholder é a forma que a pessoa espera ver —
                // com 6 zeros ela conta os dela, dá 8, e conclui que copiou errado.
                placeholder="00000000"
                maxLength={8}
                className={campoCapa}
                style={{ ...campoCapaStyle, letterSpacing: '.35em', textAlign: 'center', fontSize: 22 }}
              />
            </label>

            {erro && <FaixaCapa tom="erro">{erro}</FaixaCapa>}

            <Button type="submit" block disabled={enviando} className="mt-2">
              {enviando ? (
                <>
                  <i className="fa-solid fa-spinner fa-spin" aria-hidden="true" /> Conferindo…
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
              onClick={() => trocarPara('whatsapp')}
              className={linkDiscreto}
              style={{ color: 'var(--login-text-muted)' }}
            >
              Não chegou? Pedir de novo
            </button>
          </div>
        </>
      ) : modo === 'email' ? (
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

          <div className="mt-4 flex flex-col items-center gap-2">
            <button
              type="button"
              onClick={() => trocarPara('recuperar')}
              className={linkDiscreto}
              style={{ color: 'var(--login-text-muted)' }}
            >
              Esqueci minha senha
            </button>
            <button
              type="button"
              onClick={() => trocarPara('whatsapp')}
              className={linkDiscreto}
              style={{ color: 'var(--login-text-muted)' }}
            >
              Entrar pelo WhatsApp
            </button>
          </div>
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
              onClick={() => trocarPara('email')}
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
