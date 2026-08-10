import { useCallback, useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { EmptyState, Skeleton } from '../../components/ui'
import {
  radarConfig,
  salvarRadarConfig,
  type RadarConfigItem,
} from '../../lib/api'
import { CoordenacaoFrame } from './CoordenacaoFrame'

const ORDEM_GRUPO = ['pesos', 'faixas', 'absenteismo', 'base', 'consecutivas'] as const

const ROTULO_GRUPO: Record<string, string> = {
  pesos: 'Pesos',
  faixas: 'Faixas da nota',
  absenteismo: 'Absenteísmo',
  base: 'Base mínima',
  consecutivas: 'Faltas consecutivas',
}

/**
 * Réguas do Radar — pesos e limiares editáveis.
 *
 * Copy proibida: "recomendado", "padrão do sistema", "sugerido". O default é
 * ponto de partida ("de fábrica: 25"), não verdade.
 *
 * Salva no blur; em erro, reverte o valor na tela.
 */
export default function CoordenacaoReguasPage() {
  const nav = useNavigate()
  const [itens, setItens] = useState<RadarConfigItem[] | null>(null)
  const [erro, setErro] = useState<string | null>(null)
  const [toast, setToast] = useState<string | null>(null)
  const [rascunho, setRascunho] = useState<Record<string, string>>({})

  const carregar = useCallback(() => {
    setErro(null)
    radarConfig()
      .then((r) => {
        setItens(r.itens)
        const mapa: Record<string, string> = {}
        for (const i of r.itens) mapa[i.chave] = String(i.valor)
        setRascunho(mapa)
      })
      .catch((e: unknown) => {
        const msg = String((e as { message?: string })?.message ?? e)
        setErro(
          msg.includes('apenas_admin')
            ? 'Essa área é da coordenação.'
            : 'Não consegui carregar as réguas agora.',
        )
      })
  }, [])

  useEffect(carregar, [carregar])

  useEffect(() => {
    if (!toast) return
    const t = window.setTimeout(() => setToast(null), 2500)
    return () => window.clearTimeout(t)
  }, [toast])

  const grupos = useMemo(() => {
    if (!itens) return []
    const chaves = new Set(itens.map((i) => i.grupo))
    const ordenados = [
      ...ORDEM_GRUPO.filter((g) => chaves.has(g)),
      ...[...chaves].filter((g) => !(ORDEM_GRUPO as readonly string[]).includes(g)),
    ]
    return ordenados.map((grupo) => ({
      grupo,
      itens: itens.filter((i) => i.grupo === grupo),
    }))
  }, [itens])

  async function salvar(item: RadarConfigItem) {
    const bruto = rascunho[item.chave]
    const valor = Number(bruto)
    if (!Number.isFinite(valor)) {
      setRascunho((m) => ({ ...m, [item.chave]: String(item.valor) }))
      setToast('Valor válido, por favor.')
      return
    }
    if (valor === item.valor) return
    try {
      await salvarRadarConfig(item.chave, valor)
      setItens((lista) =>
        lista
          ? lista.map((i) =>
              i.chave === item.chave
                ? { ...i, valor, mexido: valor !== i.fabrica }
                : i,
            )
          : lista,
      )
      setToast(`Salvo: ${item.rotulo}`)
    } catch {
      setRascunho((m) => ({ ...m, [item.chave]: String(item.valor) }))
      setToast('Não deu pra salvar — voltei o valor anterior.')
    }
  }

  return (
    <CoordenacaoFrame
      titulo="Réguas"
      icone="fa-solid fa-sliders"
      aoVoltar={() => nav('/app/coordenacao/radar')}
    >
      <div className="px-5 pb-5 pt-3">
        <p className="mb-6 text-[13px] leading-relaxed text-text-muted">
          Estas réguas são de gestão, não do sistema. Elas podem começar frouxas e
          apertar conforme a equipe amadurece — cada mudança fica registrada com quem
          mudou e quando.
        </p>

        {toast ? (
          <p
            className="mb-4 rounded-md border border-border-subtle bg-bg-inset px-3 py-2 text-[12.5px] text-text-secondary"
            role="status"
          >
            {toast}
          </p>
        ) : null}

        {erro ? (
          <EmptyState
            icon="fa-solid fa-triangle-exclamation"
            title={erro}
            description="Recarrega a página e tenta de novo."
          />
        ) : !itens ? (
          <div className="space-y-3">
            <Skeleton className="h-24 w-full rounded-lg" />
            <Skeleton className="h-24 w-full rounded-lg" />
          </div>
        ) : (
          grupos.map(({ grupo, itens: doGrupo }) => (
            <section key={grupo} className="mb-8">
              <h2 className="mb-3 text-[13px] font-bold uppercase tracking-[.5px] text-text-secondary">
                {ROTULO_GRUPO[grupo] ?? grupo}
              </h2>
              <ul className="space-y-3">
                {doGrupo.map((item) => (
                  <li
                    key={item.chave}
                    className="flex flex-wrap items-center gap-3 rounded-lg border border-border-subtle bg-bg-surface px-3.5 py-3 shadow-card"
                  >
                    <div className="min-w-[160px] flex-1">
                      <p className="text-[14px] font-semibold text-text-primary">{item.rotulo}</p>
                      <p className="text-[11.5px] text-text-muted">
                        de fábrica: {item.fabrica}
                        {item.mexido ? (
                          <span className="ml-2 text-[10px] font-bold uppercase tracking-[.5px] text-brand-text">
                            mexido
                          </span>
                        ) : null}
                      </p>
                    </div>
                    <input
                      type="number"
                      inputMode="decimal"
                      className="w-24 rounded-md border border-border-strong bg-bg-inset px-3 py-2 text-right text-sm text-text-primary focus-visible:border-brand"
                      value={rascunho[item.chave] ?? ''}
                      onChange={(e) =>
                        setRascunho((m) => ({ ...m, [item.chave]: e.target.value }))
                      }
                      onBlur={() => void salvar(item)}
                      aria-label={item.rotulo}
                    />
                  </li>
                ))}
              </ul>
            </section>
          ))
        )}
      </div>
    </CoordenacaoFrame>
  )
}
