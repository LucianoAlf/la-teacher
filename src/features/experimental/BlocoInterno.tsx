import type { ReactNode } from 'react'

/**
 * O bloco que NÃO pode chegar na família.
 *
 * A fronteira não é só de dado — o banco já garante que a leitura de conversão
 * só existe na view comercial (037) e só sai depois da régua na mensagem do
 * WhatsApp (044). Aqui ela é de PERCEPÇÃO: o professor precisa sentir que está
 * escrevendo em outro lugar.
 *
 * Se os quatro campos parecerem iguais, ele escreve com linguagem de venda no
 * campo que a família lê — ou escreve a leitura comercial ali. Âmbar, cadeado,
 * moldura própria e a frase escrita embaixo existem por isso, não por enfeite.
 */
export function BlocoInterno({
  titulo,
  children,
  nota = 'Vai só pro consultor comercial — nunca pra família.',
}: {
  titulo: string
  children: ReactNode
  nota?: string
}) {
  return (
    <section className="rounded-lg border border-warning/40 bg-warning-soft p-[14px]">
      <h3 className="mb-[10px] flex items-center gap-2 text-[13px] font-bold uppercase tracking-[.5px] text-warning-text">
        <i className="fa-solid fa-lock text-xs" aria-hidden="true" />
        {titulo}
      </h3>
      {children}
      <p className="mt-[10px] text-[11.5px] leading-snug text-text-muted">{nota}</p>
    </section>
  )
}
