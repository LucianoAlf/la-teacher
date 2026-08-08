import { useEffect, useId, useRef, useState } from 'react'
import { cx } from '../../lib/cx'

export interface OpcaoSelect {
  valor: string
  rotulo: string
  /** Número à direita ("143"). Fica em `text-muted`, separado do rótulo. */
  sufixo?: string | number
}

export interface SelectProps {
  opcoes: OpcaoSelect[]
  /** `''` = nenhuma escolha; casa com o `valor` da opção "todas". */
  valor: string
  aoEscolher: (valor: string) => void
  /** Obrigatório: o gatilho não tem `<label>` visível. */
  rotuloAcessivel: string
  size?: 'md' | 'sm'
  className?: string
}

/**
 * Campo de escolha do DS.
 *
 * ⚠️ **NÃO é um `<select>` nativo, e a primeira versão era.** Um `<select>`
 * aceita CSS na caixa FECHADA, mas a lista aberta quem desenha é o sistema
 * operacional: no Windows ela sai branca, com azul de seleção e fonte do
 * sistema, ignorando todos os tokens. O Alf viu na hora — a tela inteira em
 * tema escuro e um retângulo branco do Windows por cima.
 *
 * O popup aqui é o MESMO do menu de perfil do `AppHeader`: `rounded-xl`, borda
 * `border-subtle`, fundo `bg-surface`, `shadow-fab`, e itens separados por
 * `border-b`. Não é receita nova.
 *
 * **Fechar clicando fora é `pointerdown` no document, nunca um backdrop
 * `fixed inset-0` irmão.** Isso está cicatrizado no projeto: no `AppFrame`, com
 * duas camadas de `overflow-hidden`, o backdrop `fixed` rouba o toque dos itens
 * no iOS Safari — o menu abria e nenhum item respondia (bug real, 11/07).
 */
export function Select({
  opcoes,
  valor,
  aoEscolher,
  rotuloAcessivel,
  size = 'md',
  className,
}: SelectProps) {
  const [aberto, setAberto] = useState(false)
  const [focado, setFocado] = useState(0)
  const caixaRef = useRef<HTMLDivElement>(null)
  const listaRef = useRef<HTMLUListElement>(null)
  const id = useId()

  const escolhida = opcoes.find((o) => o.valor === valor) ?? opcoes[0]
  const indiceAtual = Math.max(0, opcoes.findIndex((o) => o.valor === valor))

  // Fecha ao tocar fora — ver o aviso no cabeçalho sobre backdrop `fixed`.
  useEffect(() => {
    if (!aberto) return
    function fechar(e: PointerEvent) {
      if (caixaRef.current && !caixaRef.current.contains(e.target as Node)) setAberto(false)
    }
    document.addEventListener('pointerdown', fechar)
    return () => document.removeEventListener('pointerdown', fechar)
  }, [aberto])

  // Abrir já com o cursor na opção vigente: quem abre quer mudar a partir dela.
  useEffect(() => {
    if (aberto) setFocado(indiceAtual)
  }, [aberto, indiceAtual])

  // Rolar a opção focada pra dentro da vista — com 20 cursos a lista rola.
  useEffect(() => {
    if (!aberto) return
    listaRef.current?.children[focado]?.scrollIntoView({ block: 'nearest' })
  }, [aberto, focado])

  function escolher(i: number) {
    const o = opcoes[i]
    if (!o) return
    aoEscolher(o.valor)
    setAberto(false)
  }

  function noTeclado(e: React.KeyboardEvent) {
    if (e.key === 'Escape') {
      setAberto(false)
      return
    }
    if (!aberto) {
      if (e.key === 'ArrowDown' || e.key === 'Enter' || e.key === ' ') {
        e.preventDefault()
        setAberto(true)
      }
      return
    }
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      setFocado((i) => Math.min(i + 1, opcoes.length - 1))
    } else if (e.key === 'ArrowUp') {
      e.preventDefault()
      setFocado((i) => Math.max(i - 1, 0))
    } else if (e.key === 'Home') {
      e.preventDefault()
      setFocado(0)
    } else if (e.key === 'End') {
      e.preventDefault()
      setFocado(opcoes.length - 1)
    } else if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault()
      escolher(focado)
    }
  }

  return (
    <div ref={caixaRef} className={cx('relative', className)}>
      <button
        type="button"
        role="combobox"
        aria-haspopup="listbox"
        aria-expanded={aberto}
        aria-controls={`${id}-lista`}
        aria-label={rotuloAcessivel}
        onClick={() => setAberto((v) => !v)}
        onKeyDown={noTeclado}
        className={cx(
          'flex w-full items-center gap-2 rounded-md border border-border-strong bg-bg-inset text-text-primary transition-colors hover:bg-bg-hover focus-visible:border-brand focus-visible:outline-none',
          size === 'md' ? 'px-[14px] py-[11px] text-sm' : 'px-[10px] py-[6px] text-[12.5px]',
        )}
      >
        <span className="min-w-0 flex-1 truncate text-left">{escolhida?.rotulo}</span>
        {escolhida?.sufixo !== undefined && (
          <span className="flex-none text-text-muted">{escolhida.sufixo}</span>
        )}
        <i
          className={cx(
            'fa-solid fa-chevron-down flex-none text-[10px] text-text-secondary transition-transform',
            aberto && 'rotate-180',
          )}
          aria-hidden="true"
        />
      </button>

      {aberto && (
        <ul
          ref={listaRef}
          id={`${id}-lista`}
          role="listbox"
          aria-label={rotuloAcessivel}
          tabIndex={-1}
          className="absolute right-0 top-[calc(100%+6px)] z-50 max-h-[320px] min-w-full overflow-y-auto whitespace-nowrap rounded-xl border border-border-subtle bg-bg-surface shadow-fab"
        >
          {opcoes.map((o, i) => {
            const selecionada = o.valor === valor
            return (
              <li key={o.valor} role="option" aria-selected={selecionada}>
                <button
                  type="button"
                  onClick={() => escolher(i)}
                  onMouseEnter={() => setFocado(i)}
                  className={cx(
                    'flex w-full items-center gap-3 border-b border-border-subtle px-[14px] py-[9px] text-left text-[13px] last:border-b-0',
                    selecionada ? 'font-bold text-brand-text' : 'text-text-primary',
                    i === focado && 'bg-bg-hover',
                  )}
                >
                  <i
                    className={cx(
                      'fa-solid fa-check w-[12px] flex-none text-[10px]',
                      selecionada ? 'text-brand-text' : 'invisible',
                    )}
                    aria-hidden="true"
                  />
                  <span className="flex-1">{o.rotulo}</span>
                  {o.sufixo !== undefined && (
                    <span className="flex-none text-[12px] text-text-muted">{o.sufixo}</span>
                  )}
                </button>
              </li>
            )
          })}
        </ul>
      )}
    </div>
  )
}
