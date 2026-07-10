import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Button, Card, EmptyState, ScreenHeader, Skeleton } from '../../components/ui'
import { meuPonto, type PontoDia } from '../../lib/api'
import {
  addDias,
  diasDaSemana,
  formatDiaCurto,
  formatHoraTimestampBRT,
  hojeBRT,
  inicioSemana,
} from '../../lib/date'
import { AppFrame } from './AppFrame'

/** 195 → "3h15" (linguagem de relógio, não de decimal). */
export function fmtMinutos(min: number): string {
  const h = Math.floor(min / 60)
  const m = min % 60
  return m === 0 ? `${h}h` : `${h}h${String(m).padStart(2, '0')}`
}

type Estado = { fase: 'carregando' } | { fase: 'ok'; dias: PontoDia[] } | { fase: 'erro' }

/** /app/ponto — horas creditadas do professor, derivadas da chamada. Só leitura. */
export default function PontoPage() {
  const navigate = useNavigate()
  const [ref, setRef] = useState<string>(hojeBRT())
  const [estado, setEstado] = useState<Estado>({ fase: 'carregando' })
  const [tentativa, setTentativa] = useState(0)

  const dias = diasDaSemana(ref)
  const semanaAtual = inicioSemana(hojeBRT()) === dias[0]

  useEffect(() => {
    let vivo = true
    setEstado({ fase: 'carregando' })
    meuPonto(dias[0], dias[6])
      .then((r) => vivo && setEstado({ fase: 'ok', dias: r }))
      .catch(() => vivo && setEstado({ fase: 'erro' }))
    return () => {
      vivo = false
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dias[0], tentativa])

  const total = estado.fase === 'ok' ? estado.dias.reduce((n, d) => n + d.minutos_creditados, 0) : 0

  return (
    <AppFrame>
      <ScreenHeader
        title="Meu ponto"
        subtitle="Horas creditadas pelas chamadas — só leitura"
        onBack={() => navigate(-1)}
      />

      <div className="flex-1 overflow-y-auto px-4 pb-8 pt-1">
        {/* Navegação de semana */}
        <div className="mb-3 flex items-center gap-2 rounded-lg border border-border-subtle bg-bg-surface px-2 py-2">
          <button
            type="button"
            aria-label="Semana anterior"
            className="flex h-9 w-9 items-center justify-center rounded-md text-text-secondary"
            onClick={() => setRef(addDias(ref, -7))}
          >
            <i className="fa-solid fa-chevron-left" aria-hidden="true" />
          </button>
          <div className="flex-1 text-center">
            <b className="block text-sm">
              {formatDiaCurto(dias[0])} — {formatDiaCurto(dias[6])}
            </b>
            {!semanaAtual && (
              <button type="button" className="text-[11.5px] font-semibold text-brand-text" onClick={() => setRef(hojeBRT())}>
                voltar pra semana atual
              </button>
            )}
          </div>
          <button
            type="button"
            aria-label="Próxima semana"
            className="flex h-9 w-9 items-center justify-center rounded-md text-text-secondary"
            onClick={() => setRef(addDias(ref, 7))}
          >
            <i className="fa-solid fa-chevron-right" aria-hidden="true" />
          </button>
        </div>

        {estado.fase === 'carregando' && (
          <div className="space-y-3">
            {[0, 1, 2].map((i) => (
              <Skeleton key={i} className="h-12 w-full" />
            ))}
          </div>
        )}

        {estado.fase === 'erro' && (
          <EmptyState
            icon="fa-solid fa-triangle-exclamation"
            title="Não consegui carregar"
            description="Verifica a conexão e tenta de novo."
            action={
              <Button size="sm" onClick={() => setTentativa((t) => t + 1)}>
                <i className="fa-solid fa-rotate-right" aria-hidden="true" /> Tentar de novo
              </Button>
            }
          />
        )}

        {estado.fase === 'ok' && estado.dias.length === 0 && (
          <EmptyState
            icon="fa-solid fa-stopwatch"
            title="Sem horas nesta semana"
            description="As horas do ponto nascem das chamadas feitas nas aulas. Fez a chamada, a hora aparece aqui."
          />
        )}

        {estado.fase === 'ok' && estado.dias.length > 0 && (
          <Card title="Semana" icon="fa-solid fa-stopwatch" right={fmtMinutos(total)}>
            {estado.dias.map((d) => (
              <div key={d.data_aula} className="flex items-center gap-3 border-b border-border-subtle px-1 py-3 last:border-b-0">
                <span className="w-[74px] flex-none text-[12.5px] font-bold text-text-secondary">
                  {formatDiaCurto(d.data_aula)}
                </span>
                <span className="min-w-0 flex-1 truncate text-[12.5px] text-text-secondary">
                  {d.minutos_creditados > 0
                    ? `${d.aulas_creditadas} aula(s) · ${formatHoraTimestampBRT(d.inicio_creditado)}–${formatHoraTimestampBRT(d.fim_creditado)}`
                    : 'sem chamada registrada'}
                </span>
                <b className="text-sm">{fmtMinutos(d.minutos_creditados)}</b>
              </div>
            ))}
          </Card>
        )}

        <p className="mt-3 flex items-start gap-2 text-[12px] leading-relaxed text-text-secondary">
          <i className="fa-solid fa-circle-info mt-[2px] text-brand-text" aria-hidden="true" />
          <span>
            O ponto é derivado das presenças das suas aulas — aqui é <b>só leitura</b>. Achou divergência? Fala com a
            coordenação.
          </span>
        </p>
      </div>
    </AppFrame>
  )
}
