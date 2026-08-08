import { useEffect, useState, type ReactNode } from 'react'
import { NavLink, useLocation, useNavigate } from 'react-router-dom'
import { Avatar, BotaoTema, BotaoVoltar, FabioAvatar, TabBar } from '../../components/ui'
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
 *
 * O que MUDA em relação ao app do professor é só o esqueleto (sidebar × coluna
 * de 430px). Tudo que aparece dentro — avatar, toggle de tema, data, barra do
 * rodapé — é o mesmo componente e o mesmo tamanho, senão viram dois apps.
 */

const COLAPSADA_KEY = 'la-coord-sidebar-colapsada'

const ITENS = [
  { id: 'painel', para: '/app/coordenacao', rotulo: 'Painel', icone: 'fa-solid fa-table-columns' },
  { id: 'equipe', para: '/app/equipe', rotulo: 'Equipe', icone: 'fa-solid fa-users' },
] as const

/** Rodapé do celular: as mesmas seções da sidebar + o perfil (que no desktop é a foto). */
const ABAS = [
  ...ITENS.map((i) => ({ id: i.id, label: i.rotulo, icon: i.icone })),
  { id: 'perfil', label: 'Perfil', icon: 'fa-solid fa-user' },
]
const ROTA: Record<string, string> = {
  painel: '/app/coordenacao',
  equipe: '/app/equipe',
  perfil: '/app/coordenacao/perfil',
}

export function CoordenacaoFrame({
  titulo,
  icone,
  subtitulo,
  aoVoltar,
  children,
}: {
  /** Nome da PÁGINA — o mesmo do item da sidebar ("Painel", "Equipe"). */
  titulo: string
  icone?: string
  subtitulo?: string
  /**
   * Saída, pras telas que não estão na navegação (o perfil). É o mesmo botão
   * redondo do `ScreenHeader` do professor — não um link de texto.
   */
  aoVoltar?: () => void
  children: ReactNode
}) {
  const nav = useNavigate()
  const { pathname } = useLocation()
  const abaAtiva = pathname.startsWith('/app/coordenacao/perfil')
    ? 'perfil'
    : pathname.startsWith('/app/equipe')
      ? 'equipe'
      : 'painel'

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
            Mesmo desenho do TOM no LA Organizer, e o mesmo avatar de 44px que o
            AppHeader do professor usa. */}
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

      {/* ── Coluna principal ─────────────────────────────────────────────
          `relative` porque a TabBar do DS se posiciona no rodapé do container
          posicionado mais próximo — igual ao AppFrame do professor. */}
      <div className="relative flex min-w-0 flex-1 flex-col">
        {/* Faixa flutuante: nome da PÁGINA à esquerda (o mesmo rótulo do item
            ativo na sidebar), data e perfil à direita. Sem fundo, sem borda. */}
        <div className="flex shrink-0 items-center justify-between gap-3 px-5 pb-2 pt-6">
          <div className="flex min-w-0 items-center gap-2.5">
            {aoVoltar ? <BotaoVoltar onClick={aoVoltar} /> : null}
            {icone ? (
              <i className={`${icone} text-[15px] text-text-secondary`} aria-hidden />
            ) : null}
            {/* Mesma tipografia do título do AppHeader: extrabold com tracking
                negativo. É o que o app do professor já usa. */}
            <span className="truncate text-[17px] font-extrabold tracking-[-.3px] text-text-primary">
              {titulo}
            </span>
            {subtitulo ? (
              <span className="truncate text-[12.5px] text-text-secondary">{subtitulo}</span>
            ) : null}
          </div>

          {/* Só CHROME aqui: data, tema, quem está logado. Filtro é ferramenta
              da tela e mora nela — já esteve aqui em cima e o Alf devolveu:
              "lá é específico pro perfil, tema e nome da página". */}
          <div className="flex shrink-0 items-center gap-3">
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

        {/* Só o miolo rola — a moldura não cresce com o conteúdo. O respiro de
            baixo no celular é a altura da TabBar (72px + safe-area). */}
        <main className="min-h-0 flex-1 overflow-y-auto pb-[calc(80px_+_env(safe-area-inset-bottom))] md:pb-0">
          {children}
        </main>

        {/* Navegação do celular: a TabBar do DS, a mesma do app do professor —
            72px, `env(safe-area-inset-bottom)` e 10,5px semibold. A versão
            anterior era um <nav> meu, mais baixo e sem safe-area: no iPhone os
            rótulos ficavam embaixo da barra de gestos. Sem vão central porque
            aqui não existe FAB. */}
        <div className="md:hidden">
          <TabBar
            items={ABAS}
            activeId={abaAtiva}
            fabGap={false}
            onSelect={(id) => nav(ROTA[id])}
          />
        </div>

        <InstallPrompt />
      </div>
    </div>
  )
}

/**
 * A foto de quem está logado — só o `Avatar` do DS com os tamanhos do app do
 * professor: 40px no topo (AppHeader) e 92px no perfil (Meu perfil).
 *
 * Já teve corpo próprio aqui, com `bg-brand-soft` inventado no lugar dos tokens
 * `--avatar-grad`/`--avatar-fg` — a mesma pessoa com duas caras conforme a
 * tela. Virou casca fina quando a fila do painel virou o TERCEIRO lugar a
 * precisar de foto-com-fallback.
 */
export function AvatarDoUsuario({
  perfil,
  tamanho = 'sm',
}: {
  perfil: MeuPerfilCoordenacao | null
  tamanho?: 'sm' | 'lg'
}) {
  return (
    <Avatar
      fotoUrl={perfil?.avatar_url}
      nome={perfil?.nome}
      tamanho={tamanho === 'lg' ? 'h-[92px] w-[92px] text-3xl' : 'h-10 w-10 text-[15px]'}
    />
  )
}
