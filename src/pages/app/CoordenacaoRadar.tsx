import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { EmptyState, Skeleton } from '../../components/ui'
import { FiltrosRadar } from '../../features/coordenacao/components/FiltrosRadar'
import { LinhaRadar } from '../../features/coordenacao/components/LinhaRadar'
import { ModalAlunoRadar } from '../../features/coordenacao/components/ModalAlunoRadar'
import { PainelNumero } from '../../features/coordenacao/components/PainelNumero'
import { pct } from '../../features/coordenacao/sinaisRadar'
import {
  coordenacaoRadar,
  SEM_FILTRO_RADAR,
  type FiltroRadar,
  type RadarLinha,
  type RadarResposta,
} from '../../lib/api'
import { dataDoDia } from '../../lib/datas'
import { CoordenacaoFrame } from './CoordenacaoFrame'

/**
 * Mesa do Radar — "quem eu procuro esta semana, e por quê?".
 *
 * Compõe, não estiliza (`docs/frontend-tokens.md`). Backend: `app_coordenacao_radar`.
 */
export default function CoordenacaoRadarPage() {
  const [dados, setDados] = useState<RadarResposta | null>(null)
  const [erro, setErro] = useState<string | null>(null)
  const [filtro, setFiltro] = useState<FiltroRadar>(SEM_FILTRO_RADAR)
  const [aberto, setAberto] = useState<RadarLinha | null>(null)

  const carregar = useCallback(() => {
    setErro(null)
    coordenacaoRadar(filtro)
      .then(setDados)
      .catch((e: unknown) => {
        const msg = String((e as { message?: string })?.message ?? e)
        setErro(
          msg.includes('apenas_admin')
            ? 'Essa área é da coordenação.'
            : 'Não consegui carregar o Radar agora.',
        )
      })
  }, [filtro])

  useEffect(carregar, [carregar])

  const r = dados?.resumo
  const carregando = !dados
  const temFiltro =
    filtro.status != null || filtro.unidadeId != null || filtro.professorId != null

  return (
    <CoordenacaoFrame titulo="Radar" icone="fa-solid fa-satellite-dish">
      <div className="px-5 pb-5 pt-3">
        {erro ? (
          <EmptyState
            icon="fa-solid fa-triangle-exclamation"
            title={erro}
            description="Recarrega a página e tenta de novo."
          />
        ) : (
          <>
            <p className="mb-4 text-[11.5px] leading-snug text-text-muted">
              Absenteísmo desde {dados ? dataDoDia(dados.resumo.base_desde) : '…'} ·{' '}
              {dados?.resumo.aulas_por_aluno ?? '—'}{' '}
              {dados?.resumo.aulas_por_aluno === 1 ? 'aula' : 'aulas'} por aluno em média
              {dados?.resumo.aulas_por_aluno != null && dados.resumo.aulas_por_aluno < 4
                ? ' — ainda enchendo'
                : ''}
            </p>

            <div className="mb-6 grid grid-cols-2 gap-2.5 md:grid-cols-4">
              <PainelNumero
                rotulo="Crítico"
                valor={r?.criticos}
                tom="perigo"
                carregando={carregando}
              />
              <PainelNumero
                rotulo="Atenção"
                valor={r?.atencao}
                tom="atencao"
                carregando={carregando}
              />
              <PainelNumero
                rotulo="Avisaram que saem"
                valor={r?.avisaram_que_saem}
                carregando={carregando}
              />
              <PainelNumero
                rotulo="Absenteísmo"
                valor={
                  r?.absenteismo_media == null ? undefined : Math.round(r.absenteismo_media)
                }
                sufixo={
                  r
                    ? `% méd · ${pct(r.absenteismo_mediana)} med`
                    : undefined
                }
                carregando={carregando}
              />
            </div>

            <FiltrosRadar
              opcoes={dados?.filtros ?? null}
              filtro={filtro}
              aoMudar={setFiltro}
            />

            {carregando ? (
              <div className="space-y-2">
                <Skeleton className="h-[92px] w-full rounded-lg" />
                <Skeleton className="h-[92px] w-full rounded-lg" />
              </div>
            ) : dados.linhas.length === 0 ? (
              <EmptyState
                icon={
                  temFiltro
                    ? 'fa-solid fa-filter-circle-xmark'
                    : r && r.alunos > 0
                      ? 'fa-solid fa-heart'
                      : 'fa-regular fa-clock'
                }
                title={
                  temFiltro
                    ? 'Ninguém neste recorte'
                    : r && r.alunos > 0
                      ? 'Ninguém precisando de atenção'
                      : 'Ainda não há alunos na coorte do Radar'
                }
                description={
                  temFiltro
                    ? 'Tenta afrouxar um dos filtros acima.'
                    : r && r.alunos > 0
                      ? 'Quem está em crítico, atenção ou sem nota suficiente aparece aqui conforme o filtro.'
                      : 'Entram alunos cujo professor está ativo e com usuário no app.'
                }
              />
            ) : (
              <>
                <span className="mb-3 flex items-center gap-2 text-[13px] font-bold uppercase tracking-[.5px] text-text-secondary">
                  <i className="fa-solid fa-user-group text-xs text-brand-text" aria-hidden />
                  Alunos
                  <span className="font-normal normal-case tracking-normal text-text-muted">
                    {dados.total_lista}
                  </span>
                </span>
                {dados.linhas.map((linha) => (
                  <LinhaRadar
                    key={`${linha.aluno_id}-${linha.professor_id}`}
                    linha={linha}
                    config={dados.config}
                    medias={dados.medias}
                    baseDesde={dados.resumo.base_desde}
                    aoAbrir={setAberto}
                  />
                ))}
                {dados.truncado ? (
                  <p className="mt-3 text-[11.5px] text-text-muted">
                    Mostrando {dados.linhas.length} de {dados.total_lista}. Usa os filtros pra
                    ver o resto.
                  </p>
                ) : null}
              </>
            )}

            <p className="mt-6 text-[11.5px] text-text-muted">
              <Link
                to="/app/coordenacao/reguas"
                className="text-brand-text underline-offset-2 hover:underline"
              >
                Réguas
              </Link>
              {' · '}
              pesos e faixas que alimentam a nota
            </p>
          </>
        )}
      </div>

      {aberto && dados ? (
        <ModalAlunoRadar
          linha={aberto}
          medias={dados.medias}
          config={dados.config}
          baseDesde={dados.resumo.base_desde}
          aoFechar={() => setAberto(null)}
        />
      ) : null}
    </CoordenacaoFrame>
  )
}
