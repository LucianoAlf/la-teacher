import { useState, type FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../../lib/auth'
import { useTheme } from '../../lib/theme'
import { supabase } from '../../lib/supabase'
import { Toast, useToast } from '../../components/ui'

function primeiroNome(email?: string, nome?: string): string {
  if (nome) return nome.split(' ')[0]
  if (!email) return 'professor'
  const local = email.split('@')[0].split(/[._-]/)[0]
  return local.charAt(0).toUpperCase() + local.slice(1)
}

/** "Sábado, 11 de julho" com a primeira letra maiúscula. */
function dataLonga(): string {
  const d = new Date().toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' })
  return d.charAt(0).toUpperCase() + d.slice(1)
}

/**
 * Header das telas internas — padrão da família LA (espelha o LA Organizer):
 * avatar do Fábio · saudação + data · toggle de tema (sol/lua) · foto + menu.
 */
export function AppHeader() {
  const { session, signOut } = useAuth()
  const { theme, toggle } = useTheme()
  const navigate = useNavigate()
  const { message, visible, show } = useToast()

  const [menu, setMenu] = useState(false)
  const [modalSenha, setModalSenha] = useState(false)

  const nomeCompleto = (session?.user.user_metadata?.name as string | undefined) ?? undefined
  const nome = primeiroNome(session?.user.email, nomeCompleto)
  const inicial = nome.charAt(0).toUpperCase()

  return (
    <header className="relative z-30 flex items-center gap-[10px] px-4 pb-1 pt-[14px]">
      {/* Avatar do Fábio (assistente) */}
      <img src="/brand/fabio-avatar.svg" alt="Fábio" className="h-11 w-11 flex-none" />

      {/* Saudação + data */}
      <div className="min-w-0 flex-1">
        <b className="block truncate text-[17px] font-extrabold leading-tight tracking-[-.3px]">
          E aí, {nome}! 👋
        </b>
        <span className="block truncate text-[12.5px] text-text-secondary">{dataLonga()}</span>
      </div>

      {/* Toggle de tema — sol no escuro (clarear), lua no claro (escurecer) */}
      <button
        type="button"
        aria-label={theme === 'dark' ? 'Mudar para tema claro' : 'Mudar para tema escuro'}
        className="flex h-[38px] w-[38px] flex-none items-center justify-center rounded-full border border-border-subtle bg-bg-surface text-text-secondary"
        onClick={toggle}
      >
        <i className={theme === 'dark' ? 'fa-solid fa-sun' : 'fa-solid fa-moon'} aria-hidden="true" />
      </button>

      {/* Foto do professor + menu */}
      <div className="relative flex-none">
        <button
          type="button"
          aria-label="Menu do perfil"
          aria-expanded={menu}
          className="flex h-10 w-10 items-center justify-center rounded-full bg-[var(--avatar-grad)] text-[15px] font-extrabold text-[color:var(--avatar-fg)]"
          onClick={() => setMenu((v) => !v)}
        >
          {inicial}
        </button>

        {menu && (
          <>
            {/* backdrop pra fechar ao tocar fora */}
            <button
              type="button"
              aria-label="Fechar menu"
              className="fixed inset-0 z-40 cursor-default bg-transparent"
              onClick={() => setMenu(false)}
            />
            <div className="absolute right-0 top-[calc(100%+8px)] z-50 w-[224px] overflow-hidden rounded-xl border border-border-subtle bg-bg-surface shadow-fab">
              {/* cabeçalho do menu */}
              <div className="flex items-center gap-[10px] border-b border-border-subtle px-[14px] py-3">
                <div className="flex h-10 w-10 flex-none items-center justify-center rounded-full bg-[var(--avatar-grad)] text-sm font-extrabold text-[color:var(--avatar-fg)]">
                  {inicial}
                </div>
                <div className="min-w-0">
                  <b className="block truncate text-sm">{nomeCompleto ?? nome}</b>
                  <span className="block text-[12px] text-text-secondary">Professor</span>
                </div>
              </div>

              <MenuItem icon="fa-camera" label="Trocar foto" onClick={() => { setMenu(false); show('Trocar foto chega em breve 📸') }} />
              <MenuItem icon="fa-lock" label="Mudar senha" onClick={() => { setMenu(false); setModalSenha(true) }} />
              <MenuItem icon="fa-user" label="Perfil" onClick={() => { setMenu(false); navigate('/app/perfil') }} />
              <MenuItem icon="fa-gear" label="Configurações" onClick={() => { setMenu(false); show('Configurações chega em breve ⚙️') }} />
              <MenuItem
                icon="fa-arrow-right-from-bracket"
                label="Sair"
                danger
                onClick={() => { setMenu(false); void signOut() }}
              />
            </div>
          </>
        )}
      </div>

      {modalSenha && <ModalSenha show={show} onFechar={(msg) => { setModalSenha(false); if (msg) show(msg) }} />}
      <Toast message={message} visible={visible} />
    </header>
  )
}

function MenuItem({
  icon,
  label,
  onClick,
  danger,
}: {
  icon: string
  label: string
  onClick: () => void
  danger?: boolean
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`flex w-full items-center gap-3 border-b border-border-subtle px-[14px] py-[11px] text-left text-sm last:border-b-0 ${danger ? 'text-danger-text' : 'text-text-primary'}`}
    >
      <i className={`fa-solid ${icon} w-[18px] text-center text-[13px] ${danger ? '' : 'text-text-secondary'}`} aria-hidden="true" />
      {label}
    </button>
  )
}

/** Modal "Mudar senha" — troca a senha do auth (Supabase). */
function ModalSenha({ onFechar, show }: { onFechar: (msg?: string) => void; show: (m: string) => void }) {
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
    if (error) return setErro('Não consegui alterar a senha. Tenta de novo.')
    onFechar('Senha alterada ✓')
  }

  const campo = 'w-full rounded-md border border-border-strong bg-bg-inset px-[14px] py-[11px] text-sm text-text-primary placeholder:text-text-muted focus-visible:border-brand'

  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center px-6" style={{ background: 'var(--scrim)' }}>
      <div className="w-full max-w-[380px] rounded-xl border border-border-subtle bg-bg-surface p-5">
        <b className="mb-3 block text-lg font-extrabold">Mudar senha</b>
        <form className="flex flex-col gap-3" onSubmit={salvar}>
          <input
            type="password"
            autoComplete="new-password"
            value={senha}
            onChange={(e) => setSenha(e.target.value)}
            placeholder="Nova senha (mín. 6 caracteres)"
            className={campo}
          />
          <input
            type="password"
            autoComplete="new-password"
            value={conf}
            onChange={(e) => setConf(e.target.value)}
            placeholder="Confirmar nova senha"
            className={campo}
          />
          {erro && <span className="text-[13px] font-semibold text-danger-text">{erro}</span>}
          <div className="mt-1 flex gap-3">
            <button
              type="button"
              onClick={() => onFechar()}
              className="flex-1 rounded-md border border-border-strong bg-transparent py-[11px] text-sm font-semibold text-text-secondary"
            >
              Cancelar
            </button>
            <button
              type="submit"
              disabled={salvando}
              className="flex-1 rounded-md bg-brand py-[11px] text-sm font-bold text-on-brand disabled:opacity-60"
            >
              {salvando ? 'Salvando…' : 'Salvar senha'}
            </button>
          </div>
        </form>
        <button
          type="button"
          onClick={() => show('Link por WhatsApp chega em breve 💬')}
          className="mt-3 block w-full text-center text-[12.5px] text-text-secondary"
        >
          Esqueceu a senha? <span className="font-semibold text-brand-text">Receber link no WhatsApp</span>
        </button>
      </div>
    </div>
  )
}
