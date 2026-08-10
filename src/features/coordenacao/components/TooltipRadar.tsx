import { useId, useState, type ReactNode } from 'react'

/**
 * Tooltip do Radar — obrigatório, não enfeite (pedido do Alf, 10/08).
 *
 * Todo número do Radar aparece com a base dele. O "21% de presença" da tela do
 * LA Report não diz de quantas aulas saiu, e é exatamente por isso que ninguém
 * percebeu que ele vinha de linhas dobradas.
 *
 * Abre no hover E no foco: quem navega por teclado tem que alcançar a mesma
 * informação, senão o dado só existe pra quem usa mouse.
 */
export function TooltipRadar({
  children,
  conteudo,
}: {
  children: ReactNode
  conteudo: ReactNode
}) {
  const [aberto, setAberto] = useState(false)
  const id = useId()

  return (
    <span className="relative inline-flex">
      <span
        tabIndex={0}
        aria-describedby={aberto ? id : undefined}
        onMouseEnter={() => setAberto(true)}
        onMouseLeave={() => setAberto(false)}
        onFocus={() => setAberto(true)}
        onBlur={() => setAberto(false)}
        className="cursor-help underline decoration-dotted underline-offset-4"
      >
        {children}
      </span>
      {aberto ? (
        <span
          id={id}
          role="tooltip"
          className="absolute left-0 top-full z-20 mt-1 w-max max-w-xs rounded-lg border border-border-subtle bg-bg-surface p-3 text-xs leading-relaxed text-text-primary shadow-card"
        >
          {conteudo}
        </span>
      ) : null}
    </span>
  )
}
