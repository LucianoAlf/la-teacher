import { useEffect, useState, type ReactNode } from 'react'
import { NavLink } from 'react-router-dom'
import { BotaoTema, FabioAvatar } from '../../components/ui'
import { InstallPrompt } from '../../features/pwa/InstallPrompt'
import { dataLonga } from '../../lib/datas'
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
 *  - md+ : sidebar fixa (colapsável), conteúdo em largura cheia
 *
 * Padrão do shell copiado do LA Organizer (`web/src/components/DesktopShell.tsx`):
 * a moldura ocupa a janela e NÃO cresce com o conteúdo — só o `<main>` rola. O
 * que NÃO foi copiado, de propósito: a coluna de leitura de 720px. As telas dele
 * são de ler e responder; esta é de varrer uma lista e agir.
 *
 * NÃO TEM BARRA DE CABEÇALHO (pedido do Alf, 08/08). Nome da página, data e
 * quem está logado flutuam sobre o conteúdo, sem fundo e sem borda: barra de
 * chrome rouba altura de um painel feito pra caber a lista inteira.
 */

const COLAPSADA_KEY = 'la-coord-sidebar-colapsada'


const ITENS = [
  { para: '/app/coordenacao', rotulo: 'Painel', icone: 'fa-solid fa-table-columns' },
  { para: '/app/equipe', rotulo: 'Equipe', icone: 'fa-solid fa-users' },
] as const

export function CoordenacaoFrame({
  titulo,
  icone,
  subtitulo,
  acaoTopo,
  children,
}: {
  /** Nome da PÁGINA — o mesmo do item da sidebar ("Painel", "Equipe"). */
  titulo: string
  icone?: string
  subtitulo?: string
  /** Extras do topo direito: filtro de unidade, de curso, o que a tela precisar. */
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
        className={`relative hidden shrink-0 flex-col border-r border-border-subtle bg-bg-surface transition-[width] duration-150 md:flex ${
          colapsada ? 'w-[72px]' : 'w-[228px]'
        }`}
      >
        {/* Na PONTA, sobreposto: o chevron é controle da moldura, não item de
            menu, e não pode gastar uma linha da sidebar. */}
        <button
          onClick={() => setColapsada((v) => !v)}
          aria-label={colapsada ? 'Expandir menu' : 'Recolher menu'}
          className={`absolute right-1 top-1 z-10 flex h-5 w-5 items-center justify-center rounded-sm text-text-muted hover:bg-bg-hover hover:text-text-secondary ${
            colapsada ? 'right-1/2 translate-x-1/2' : ''
          }`}
        >
          <i
            className={`fa-solid ${colapsada ? 'fa-chevron-right' : 'fa-chevron-left'} text-[10px]`}
            aria-hidden
          />
        </button>

        {/* O Fábio é a cara do app: o nome dele em cima, o produto embaixo.
            Mesmo desenho do TOM no LA Organizer. */}
        <div
          className={`flex items-center gap-3 px-3.5 pb-5 pt-8 ${colapsada ? 'justify-center' : ''}`}
        >
          <FabioAvatar className="h-11 w-11 shrink-0" alt="Fábio" />
          {!colapsada && (
            <div className="min-w-0">
              <div className="truncate text-[17px] font-extrabold leading-tight tracking-[-.3px] text-text-primary">
                Fábio
              </div>
              <div className="truncate text-[12.5px] leading-tight text-text-secondary">
                LA Teacher
              </div>
            </div>
          )}
        </div>

        <nav className="flex-1 px-2">
          {ITENS.map((item) => (
            <NavLink
              key={item.para}
              to={item.para}
              title={colapsada ? item.rotulo : undefined}
              className={({ isActive }) =>
                `mb-1 flex items-center gap-3 rounded-sm px-3 py-2.5 text-[13.5px] ${
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
      </aside>

      {/* ── Coluna principal ─────────────────────────────────────────────── */}
      <div className="flex min-w-0 flex-1 flex-col">
        {/* Faixa flutuante: nome da PÁGINA à esquerda (o mesmo rótulo do item
            ativo na sidebar), data e perfil à direita. Sem fundo, sem borda. */}
        <div className="flex shrink-0 items-center justify-between gap-3 px-5 pb-2 pt-6">
          <div className="flex min-w-0 items-center gap-2.5">
            {icone ? (
              <i className={`${icone} text-[15px] text-text-secondary`} aria-hidden />
            ) : null}
            {/* Mesma tipografia do título do AppHeader: extrabold com tracking
                negativo. É o que o app do professor já usa. */}
            <span className="truncate text-[17px] font-extrabold tracking-[-.3px] text-text-primary">
              {titulo}
            </span>
            {subtitulo ? (
              <span className="truncate text-[12px] text-text-secondary">{subtitulo}</span>
            ) : null}
          </div>

          <div className="flex shrink-0 items-center gap-3">
            {acaoTopo}
            <span className="hidden text-[13px] text-text-secondary sm:inline">{dataLonga()}</span>

            <BotaoTema />

            <NavLink
              to="/app/coordenacao/perfil"
              title={perfil?.nome ?? 'Meu perfil'}
              className="hidden hover:opacity-80 md:block"
            >
              <AvatarDoUsuario perfil={perfil} />
            </NavLink>
          </div>
        </div>

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
  const classe = tamanho === 'lg' ? 'h-[92px] w-[92px] text-2xl' : 'h-9 w-9 text-[12px]'

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
  // `--avatar-grad` / `--avatar-fg` são os tokens que a foto do professor já
  // usa no AppHeader e no Meu perfil. Eu tinha inventado `bg-brand-soft` aqui —
  // e aí a mesma pessoa teria duas caras conforme a tela.
  return (
    <div
      className={`${classe} flex shrink-0 items-center justify-center rounded-full bg-[var(--avatar-grad)] font-extrabold text-[color:var(--avatar-fg)]`}
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
