import { useState, type FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { Button } from '../../components/ui'
import { useAuth } from '../../lib/auth'
import { supabase } from '../../lib/supabase'
import { CapaLogin, FaixaCapa, RotuloCapa, campoCapa, campoCapaStyle } from './CapaLogin'

/**
 * /app/nova-senha — onde o link do e-mail cai.
 *
 * O link do Supabase traz a sessão de recuperação no hash da URL; o client
 * (`detectSessionInUrl: true`) troca isso por sessão sozinho. Por isso esta rota
 * fica FORA do guard: se ela passasse pelo RequireProfessor, ou pelo redirect do
 * /app/login, o professor seria jogado pra outra tela antes de conseguir digitar
 * a senha nova — e o link, que é de uso único, já teria queimado.
 */
export default function NovaSenhaPage() {
  const { session, loading, encerrarRecuperacao } = useAuth()
  const navigate = useNavigate()
  const [senha, setSenha] = useState('')
  const [conf, setConf] = useState('')
  const [erro, setErro] = useState<string | null>(null)
  const [salvando, setSalvando] = useState(false)

  async function salvar(e: FormEvent) {
    e.preventDefault()
    setErro(null)
    if (senha.length < 6) return setErro('A senha precisa ter no mínimo 6 caracteres.')
    if (senha !== conf) return setErro('As senhas não batem. Confere aí.')
    setSalvando(true)
    const { error } = await supabase.auth.updateUser({ password: senha })
    setSalvando(false)
    if (error) return setErro('Não consegui alterar a senha. Pede um link novo e tenta de novo.')
    // Baixa a bandeira ANTES de sair, senão o GuardRecuperacao devolve pra cá.
    encerrarRecuperacao()
    navigate('/app', { replace: true })
  }

  if (loading) {
    return (
      <CapaLogin>
        <p className="text-center text-[13px]" style={{ color: 'var(--login-text-muted)' }}>
          <i className="fa-solid fa-spinner fa-spin" aria-hidden="true" /> Conferindo o link…
        </p>
      </CapaLogin>
    )
  }

  // Sem sessão aqui = link expirado, já usado, ou aberto em outro navegador.
  // Os três casos têm a mesma saída prática: pedir outro.
  if (!session) {
    // O botão precisa baixar a bandeira antes de voltar: enquanto ela estiver
    // de pé, o GuardRecuperacao devolve o professor pra cá e ele fica num laço
    // entre as duas telas, sem nunca conseguir pedir outro link.
    return (
      <CapaLogin>
        <FaixaCapa tom="erro">Esse link não vale mais. Eles expiram e só funcionam uma vez.</FaixaCapa>
        <Button
          block
          className="mt-3"
          onClick={() => {
            encerrarRecuperacao()
            navigate('/app/login', { replace: true })
          }}
        >
          <i className="fa-solid fa-arrow-left" aria-hidden="true" /> Pedir um link novo
        </Button>
      </CapaLogin>
    )
  }

  return (
    <CapaLogin>
      <form className="flex flex-col gap-3" onSubmit={salvar}>
        <p className="text-[13px] leading-[1.5]" style={{ color: 'var(--login-text-muted)' }}>
          Escolhe uma senha nova. Depois disso já entra direto.
        </p>

        <label className="flex flex-col gap-[6px]">
          <RotuloCapa>Nova senha</RotuloCapa>
          <input
            type="password"
            autoComplete="new-password"
            required
            value={senha}
            onChange={(e) => setSenha(e.target.value)}
            placeholder="Mínimo 6 caracteres"
            className={campoCapa}
            style={campoCapaStyle}
          />
        </label>

        <label className="flex flex-col gap-[6px]">
          <RotuloCapa>Confirmar</RotuloCapa>
          <input
            type="password"
            autoComplete="new-password"
            required
            value={conf}
            onChange={(e) => setConf(e.target.value)}
            placeholder="Repete a senha nova"
            className={campoCapa}
            style={campoCapaStyle}
          />
        </label>

        {erro && <FaixaCapa tom="erro">{erro}</FaixaCapa>}

        <Button type="submit" block disabled={salvando} className="mt-2">
          {salvando ? (
            <>
              <i className="fa-solid fa-spinner fa-spin" aria-hidden="true" /> Salvando…
            </>
          ) : (
            <>
              <i className="fa-solid fa-check" aria-hidden="true" /> Salvar e entrar
            </>
          )}
        </Button>
      </form>
    </CapaLogin>
  )
}
