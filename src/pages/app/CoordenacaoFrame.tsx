import type { ReactNode } from 'react'
import { NavLink } from 'react-router-dom'
import { InstallPrompt } from '../../features/pwa/InstallPrompt'

/**
 * Moldura das telas da COORDENAÇÃO — e ela existe porque o `AppFrame` não serve.
 *
 * O AppFrame é `max-w-[430px]`: ele é a moldura do celular do professor, e usá-lo
 * no desktop transforma a tela numa coluna estreita no meio de 1300px. Foi
 * exatamente o que aconteceu com o `/app/equipe`, onde seis professores ocupavam
 * a tela inteira rolando.
 *
 * Aqui o layout troca por breakpoint, não por JS:
 *  - celular: sem sidebar, conteúdo em largura cheia, navegação no rodapé
 *  - md+ : sidebar fixa de 196px, topbar de 46px, conteúdo em largura cheia
 *
 * O padrão do shell é o do LA Organizer (`web/src/components/DesktopShell.tsx`):
 * a moldura ocupa a altura da janela e NÃO cresce com o conteúdo — só o `<main>`
 * rola. É isso que evita a faixa vazia embaixo quando a lista é curta.
 *
 * O que NÃO foi copiado dele de propósito: a coluna de leitura de 720px. As
 * telas do Organizer são de ler e responder; esta é de varrer uma lista e agir,
 * que é o uso oposto — e uma tabela de cinco colunas em 720px trunca nome de
 * professor.
 */

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
  return (
    <div className="flex h-svh overflow-hidden bg-bg-app">
      {/* ── Sidebar: só md+ ─────────────────────────────────────────────── */}
      <aside className="hidden w-[196px] shrink-0 flex-col border-r border-border-subtle bg-bg-surface md:flex">
        <div className="border-b border-border-subtle p-4">
          <div className="font-brand text-[17px] font-black tracking-tight text-text-primary">
            <span className="text-la-pink">LA</span> teacher
          </div>
          {/* Diz em um segundo que esta NÃO é a tela do professor. */}
          <div className="mt-[3px] text-[10px] uppercase tracking-wider text-text-muted">
            Coordenação
          </div>
        </div>

        <nav className="flex-1 p-2">
          {ITENS.map((item) => (
            <NavLink
              key={item.para}
              to={item.para}
              className={({ isActive }) =>
                `mb-[3px] flex items-center gap-[10px] rounded-sm px-[11px] py-[9px] text-[13px] ${
                  isActive
                    ? 'bg-brand-soft font-medium text-brand-text'
                    : 'text-text-secondary hover:bg-bg-hover'
                }`
              }
            >
              <i className={`${item.icone} w-[15px] text-center`} aria-hidden />
              {item.rotulo}
            </NavLink>
          ))}
        </nav>

        {/* Perfil fica no rodapé da sidebar, não numa aba: a coordenação vem
            aqui pra trabalhar, não pra se configurar. */}
        <NavLink
          to="/app/perfil"
          className="flex items-center gap-[9px] border-t border-border-subtle p-3 text-text-secondary hover:bg-bg-hover"
        >
          <i className="fa-solid fa-user w-[15px] text-center text-[13px]" aria-hidden />
          <span className="text-[12px]">Meu perfil</span>
        </NavLink>
      </aside>

      {/* ── Coluna principal ─────────────────────────────────────────────── */}
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex h-[46px] shrink-0 items-center justify-between gap-3 border-b border-border-subtle bg-bg-surface px-4">
          <div className="min-w-0">
            <span className="text-[14.5px] font-medium text-text-primary">{titulo}</span>
            {subtitulo ? (
              <span className="ml-2 text-[11.5px] text-text-secondary">{subtitulo}</span>
            ) : null}
          </div>
          {acaoTopo ? <div className="flex shrink-0 items-center gap-2">{acaoTopo}</div> : null}
        </header>

        {/* Só o miolo rola — a moldura não cresce com o conteúdo. */}
        <main className="min-h-0 flex-1 overflow-y-auto">{children}</main>

        {/* Navegação do celular. No desktop ela some: quem navega é a sidebar. */}
        <nav className="flex shrink-0 border-t border-border-subtle bg-bg-surface md:hidden">
          {ITENS.map((item) => (
            <NavLink
              key={item.para}
              to={item.para}
              className={({ isActive }) =>
                `flex flex-1 flex-col items-center gap-1 py-2 text-[11px] ${
                  isActive ? 'text-brand-text' : 'text-text-muted'
                }`
              }
            >
              <i className={`${item.icone} text-[15px]`} aria-hidden />
              {item.rotulo}
            </NavLink>
          ))}
        </nav>

        <InstallPrompt />
      </div>
    </div>
  )
}
