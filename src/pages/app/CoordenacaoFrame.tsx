import { useEffect, useState, type ReactNode } from 'react'
import { NavLink } from 'react-router-dom'
import { FabioAvatar } from '../../components/ui'
import { InstallPrompt } from '../../features/pwa/InstallPrompt'
import { meuPerfilCoordenacao, type MeuPerfilCoordenacao } from '../../lib/api'

/**
 * Moldura das telas da COORDENAÇÃO — e ela existe porque o `AppFrame` não serve.
 *
 * O AppFrame é `max-w-[430px]`: a moldura do celular do professor. No desktop
 * ele vira uma coluna estreita no meio de 1300px — foi o que aconteceu com o
 * `/app/equipe`, onde seis professores ocupavam a tela inteira rolando.
 *
 * Layout por breakpoint, não por JS:
 *  - celular: sem sidebar, largura cheia, navegação no rodapé
 *  - md+ : sidebar fixa (colapsável), topbar, conteúdo em largura cheia
 *
 * Padrão do shell copiado do LA Organizer (`web/src/components/DesktopShell.tsx`):
 * a moldura ocupa a janela e NÃO cresce com o conteúdo — só o `<main>` rola. O
 * que NÃO foi copiado, de propósito: a coluna de leitura de 720px. As telas dele
 * são de ler e responder; esta é de varrer uma lista e agir.
 */

const COLAPSADA_KEY = 'la-coord-sidebar-colapsada'

const ITENS = [
  { para: '/app/coordenacao', rotulo: 'Painel', icone: 'fa-solid fa-table-columns' },
  { para: '/app/equipe', rotulo: 'Equipe', icone: 'fa-solid fa-users' },
] as const

export function CoordenacaoFrame({
  titulo,
  subtitulo,
  acaoTopo,
  children,
}: {
  titulo: string
  subtitulo?: string
  /** Canto direito da topbar: filtro de unidade, data, o que a tela precisar. */
  acaoTopo?: ReactNode
  children: ReactNode
}) {
  // Colapso persiste: quem trabalha o dia todo no painel não quer reajustar a
  // largura a cada navegação. Mesmo comportamento do Organizer.
  const [colapsada, setColapsada] = useState(
    () => localStorage.getItem(COLAPSADA_KEY) === 'true',
  )
  useEffect(() => {
    localStorage.setItem(COLAPSADA_KEY, String(colapsada))
  }, [colapsada])

  const [perfil, setPerfil] = useState<MeuPerfilCoordenacao | null>(null)
  useEffect(() => {
    let vivo = true
    meuPerfilCoordenacao()
      .then((p) => vivo && setPerfil(p))
      .catch(() => {}) // rodapé sem foto não impede trabalhar
    return () => {
      vivo = false
    }
  }, [])

  return (
    <div className="flex h-svh overflow-hidden bg-bg-app">
      {/* ── Sidebar: só md+ ─────────────────────────────────────────────── */}
      <aside
        className={`hidden shrink-0 flex-col border-r border-border-subtle bg-bg-surface transition-[width] duration-150 md:flex ${
          colapsada ? 'w-[64px]' : 'w-[210px]'
        }`}
      >
        {/* O Fábio é a cara do app — ele abre a sidebar, não um texto. */}
        <div
          className={`flex items-center gap-2.5 border-b border-border-subtle p-3 ${
            colapsada ? 'justify-center' : ''
          }`}
        >
          <FabioAvatar className="h-8 w-8 shrink-0" alt="Fábio" />
          {!colapsada && (
            <div className="min-w-0">
              <div className="truncate font-brand text-[16px] font-black leading-none tracking-tight text-text-primary">
                <span className="text-la-pink">LA</span> teacher
              </div>
              <div className="mt-1 text-[9.5px] uppercase tracking-wider text-text-muted">
                Coordenação
              </div>
            </div>
          )}
        </div>

        <nav className="flex-1 p-2">
          {ITENS.map((item) => (
            <NavLink
              key={item.para}
              to={item.para}
              title={colapsada ? item.rotulo : undefined}
              className={({ isActive }) =>
                `mb-1 flex items-center gap-2.5 rounded-sm px-3 py-2.5 text-[13px] ${
                  colapsada ? 'justify-center' : ''
                } ${
                  isActive
                    ? 'bg-brand-soft font-bold text-brand-text'
                    : 'text-text-secondary hover:bg-bg-hover'
                }`
              }
            >
              <i className={`${item.icone} w-[16px] shrink-0 text-center`} aria-hidden />
              {!colapsada && item.rotulo}
            </NavLink>
          ))}
        </nav>

        {/* Perfil de VERDADE: foto, nome e cargo, vindos da 069. Antes daqui
            havia um link "Meu perfil" que apontava pra rota do professor — e a
            coordenação não tem vínculo de professor, então o guard expulsava a
            dona do painel pra tela de quem não tem acesso. */}
        <NavLink
          to="/app/coordenacao/perfil"
          title={colapsada ? (perfil?.nome ?? 'Meu perfil') : undefined}
          className={({ isActive }) =>
            `flex items-center gap-2.5 border-t border-border-subtle p-3 ${
              colapsada ? 'justify-center' : ''
            } ${isActive ? 'bg-brand-soft' : 'hover:bg-bg-hover'}`
          }
        >
          <AvatarDoUsuario perfil={perfil} />
          {!colapsada && (
            <div className="min-w-0 flex-1">
              <div className="truncate text-[12px] text-text-primary">
                {perfil?.apelido || perfil?.nome || 'Meu perfil'}
              </div>
              <div className="truncate text-[10px] text-text-muted">
                {perfil?.cargo || 'Coordenação'}
              </div>
            </div>
          )}
        </NavLink>

        <button
          onClick={() => setColapsada((v) => !v)}
          aria-label={colapsada ? 'Expandir menu' : 'Recolher menu'}
          className="flex items-center justify-center border-t border-border-subtle py-2 text-text-muted hover:bg-bg-hover hover:text-text-secondary"
        >
          <i
            className={`fa-solid ${colapsada ? 'fa-chevron-right' : 'fa-chevron-left'} text-[11px]`}
            aria-hidden
          />
        </button>
      </aside>

      {/* ── Coluna principal ─────────────────────────────────────────────── */}
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex h-[46px] shrink-0 items-center justify-between gap-3 border-b border-border-subtle bg-bg-surface px-4">
          <div className="min-w-0">
            <span className="text-[14.5px] font-bold text-text-primary">{titulo}</span>
            {subtitulo ? (
              <span className="ml-2 text-[11.5px] text-text-secondary">{subtitulo}</span>
            ) : null}
          </div>
          {acaoTopo ? <div className="flex shrink-0 items-center gap-2">{acaoTopo}</div> : null}
        </header>

        {/* Só o miolo rola — a moldura não cresce com o conteúdo. */}
        <main className="min-h-0 flex-1 overflow-y-auto">{children}</main>

        {/* Navegação do celular. No desktop some: quem navega é a sidebar. */}
        <nav className="flex shrink-0 border-t border-border-subtle bg-bg-surface md:hidden">
          {ITENS.map((item) => (
            <NavLink
              key={item.para}
              to={item.para}
              className={({ isActive }) =>
                `flex flex-1 flex-col items-center gap-1 py-2 text-[11px] ${
                  isActive ? 'font-bold text-brand-text' : 'text-text-muted'
                }`
              }
            >
              <i className={`${item.icone} text-[15px]`} aria-hidden />
              {item.rotulo}
            </NavLink>
          ))}
          <NavLink
            to="/app/coordenacao/perfil"
            className={({ isActive }) =>
              `flex flex-1 flex-col items-center gap-1 py-2 text-[11px] ${
                isActive ? 'font-bold text-brand-text' : 'text-text-muted'
              }`
            }
          >
            <i className="fa-solid fa-user text-[15px]" aria-hidden />
            Perfil
          </NavLink>
        </nav>

        <InstallPrompt />
      </div>
    </div>
  )
}

/** Foto quando existe; iniciais quando não. Nunca um boneco genérico. */
export function AvatarDoUsuario({
  perfil,
  tamanho = 'sm',
}: {
  perfil: MeuPerfilCoordenacao | null
  tamanho?: 'sm' | 'lg'
}) {
  const classe = tamanho === 'lg' ? 'h-[84px] w-[84px] text-2xl' : 'h-8 w-8 text-[11px]'

  if (perfil?.avatar_url) {
    return (
      <img
        src={perfil.avatar_url}
        alt={perfil.nome}
        draggable={false}
        className={`${classe} shrink-0 rounded-full object-cover`}
      />
    )
  }
  return (
    <div
      className={`${classe} flex shrink-0 items-center justify-center rounded-full bg-brand-soft font-bold text-brand-text`}
      aria-hidden
    >
      {iniciais(perfil?.nome)}
    </div>
  )
}

function iniciais(nome?: string | null) {
  if (!nome) return '·'
  const partes = nome.trim().split(/\s+/)
  return ((partes[0]?.[0] ?? '') + (partes[1]?.[0] ?? '')).toUpperCase()
}
