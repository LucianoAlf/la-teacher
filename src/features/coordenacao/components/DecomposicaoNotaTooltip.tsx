import type { RadarLinha } from '../../../lib/api'
import {
  COR_STATUS,
  ROTULO_STATUS,
  motivoSemDado,
  rotuloSinal,
  valorSinal,
} from '../sinaisRadar'

/**
 * Conteúdo do tooltip do score — a decomposição da nota.
 *
 * O defeito era LAYOUT, não falta de dado: um `flex justify-between` com
 * "Absenteísmo · 100% · 2 de 2 aulas" de um lado e "contribuiu 0 de 53.3" do
 * outro, dentro de `max-w-xs`, quebrava no meio da palavra. O Alf pediu
 * organizado — e pediu pra NÃO tirar informação (10/08/2026).
 *
 * Cada sinal fica em dois andares, os dois intactos:
 * 1. nome do sinal · contribuição (ou "fora da conta")
 * 2. o detalhe (valor tipado, ou o motivo de estar fora)
 */
export function DecomposicaoNotaTooltip({ linha }: { linha: RadarLinha }) {
  return (
    <div className="w-[300px]">
      <p className={`text-[13px] font-extrabold leading-snug ${COR_STATUS[linha.status]}`}>
        {linha.nota.nota ?? '—'} · {ROTULO_STATUS[linha.status]}
      </p>

      <ul className="mt-3 space-y-2.5">
        {linha.nota.decomposicao.map((d) => {
          const detalhe = d.sem_dado
            ? motivoSemDado(d.sinal)
            : valorSinal(d.sinal, linha, d.valor)
          const contribuicao = d.sem_dado
            ? 'fora da conta'
            : `contribuiu ${d.contribuiu} de ${d.de}`

          return (
            <li key={d.sinal}>
              <div className="flex items-baseline justify-between gap-3">
                <p
                  className={`min-w-0 text-[12px] font-semibold leading-snug ${
                    d.sem_dado ? 'text-text-muted' : 'text-text-primary'
                  }`}
                >
                  {rotuloSinal(d.sinal)}
                </p>
                <p
                  className={`shrink-0 whitespace-nowrap text-[11px] tabular-nums leading-snug ${
                    d.sem_dado ? 'text-text-muted' : 'text-text-secondary'
                  }`}
                >
                  {contribuicao}
                </p>
              </div>
              {detalhe ? (
                <p
                  className={`mt-0.5 text-[11.5px] leading-snug ${
                    d.sem_dado ? 'text-text-muted' : 'text-text-secondary'
                  }`}
                >
                  {detalhe}
                </p>
              ) : null}
            </li>
          )
        })}
      </ul>

      <p className="mt-3 border-t border-border-subtle pt-2 text-[11px] leading-snug text-text-muted">
        apurada em {linha.nota.sinais_apurados} de {linha.nota.sinais_totais} sinais
        {!linha.nota.suficiente ? ' · insuficiente' : ''}
      </p>
    </div>
  )
}
