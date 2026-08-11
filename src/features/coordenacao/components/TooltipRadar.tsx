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
 *
 * SEM SUBLINHADO PONTILHADO (Alf, 10/08/2026 — "esses pontinhos embaixo dos
 * números não tá legal", e ele está certo: pontilhado embaixo de número lê como
 * erro de digitação). O gancho visual saiu porque a informação deixou de
 * depender dele: a base de cada número agora está no próprio texto da célula
 * ("1 de 2", "67% · 2/3"), o card do aluno abre com um clique em qualquer parte
 * da linha, e no celular — que nunca teve hover — o tooltip já era invisível.
 * O que sobra aqui é o EXTRA de quem passa o mouse, não o único caminho.
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
        className="cursor-help"
      >
        {children}
      </span>
      {aberto ? (
        <span
          id={id}
          role="tooltip"
          className="absolute left-0 top-full z-20 mt-1.5 w-max max-w-none rounded-lg border border-border-subtle bg-bg-surface p-3.5 text-xs leading-relaxed text-text-primary shadow-card"
        >
          {conteudo}
        </span>
      ) : null}
    </span>
  )
}
