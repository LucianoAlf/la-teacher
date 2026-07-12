import { Fragment, type ReactNode } from 'react'
import { cx } from '../../lib/cx'

export interface TabItem {
  id: string
  label: string
  /** Classe de ícone FontAwesome (ex.: "fa-solid fa-house"). */
  icon?: string
  /** Ícone custom (SVG) — tem prioridade sobre `icon`. Deve usar currentColor. */
  node?: ReactNode
}

export interface TabBarProps {
  items: TabItem[]
  activeId: string
  onSelect: (id: string) => void
  /** Abre um vão central para o Fab (default: true, como no protótipo). */
  fabGap?: boolean
}

/** Navegação inferior (protótipo .tabbar). */
export function TabBar({ items, activeId, onSelect, fabGap = true }: TabBarProps) {
  const gapAfter = fabGap ? Math.ceil(items.length / 2) - 1 : -1

  return (
    <nav className="absolute inset-x-0 bottom-0 z-40 flex h-[calc(72px_+_env(safe-area-inset-bottom))] items-stretch border-t border-border-subtle bg-bg-surface pb-[env(safe-area-inset-bottom)]">
      {items.map((item, i) => (
        <Fragment key={item.id}>
          <button
            type="button"
            className={cx(
              'flex flex-1 flex-col items-center justify-center gap-1 border-0 bg-transparent font-sans text-[10.5px] font-semibold',
              item.id === activeId ? 'text-brand-text' : 'text-text-muted',
            )}
            onClick={() => onSelect(item.id)}
            aria-current={item.id === activeId ? 'page' : undefined}
          >
            {item.node ? (
              <span className="flex h-[21px] items-center justify-center">{item.node}</span>
            ) : (
              <i className={cx(item.icon, 'text-[17px]')} aria-hidden="true" />
            )}
            {item.label}
          </button>
          {i === gapAfter && <span className="flex-1" aria-hidden="true" />}
        </Fragment>
      ))}
    </nav>
  )
}
