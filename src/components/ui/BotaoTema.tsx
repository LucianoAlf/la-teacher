import { Moon, Sun } from 'lucide-react'
import { useTheme } from '../../lib/theme'

/**
 * Toggle de tema claro/escuro — sol no escuro (clarear), lua no claro (escurecer).
 *
 * Nasceu inline no `AppHeader` (tela do professor) e foi EXTRAÍDO pra cá quando
 * o painel da coordenação precisou do mesmo botão. O caminho errado seria
 * recriar: um segundo toggle com outro ícone e outra caixa vira um segundo
 * design system, e aí a mesma ação passa a ter duas caras no mesmo app.
 *
 * Ícone é `lucide-react` de propósito — é o que o header já usa. Font Awesome
 * fica pros itens de menu e badges, que é onde o app já o usa.
 */
export function BotaoTema({ className }: { className?: string }) {
  const { theme, toggle } = useTheme()

  return (
    <button
      type="button"
      aria-label={theme === 'dark' ? 'Mudar para tema claro' : 'Mudar para tema escuro'}
      onClick={toggle}
      className={`flex h-8 w-8 flex-none items-center justify-center rounded-full border border-border-subtle bg-bg-surface text-text-secondary transition-colors hover:bg-bg-hover ${className ?? ''}`}
    >
      {theme === 'dark' ? <Sun size={14} aria-hidden="true" /> : <Moon size={14} aria-hidden="true" />}
    </button>
  )
}
