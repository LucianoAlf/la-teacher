import { Select, type OpcaoSelect } from '../../../components/ui'
import type { FiltroRadar, RadarResposta } from '../../../lib/api'

const ROTULO_STATUS: Record<string, string> = {
  critico: 'Crítico',
  atencao: 'Atenção',
  saudavel: 'Saudável',
  sem_nota: 'Sem nota',
}

/**
 * Recortes do Radar: status, unidade e professor.
 *
 * Contagens vêm da própria RPC — cada faceta ignora o próprio filtro (087).
 */
export function FiltrosRadar({
  opcoes,
  filtro,
  aoMudar,
}: {
  opcoes: RadarResposta['filtros'] | null
  filtro: FiltroRadar
  aoMudar: (f: FiltroRadar) => void
}) {
  if (!opcoes) return null

  const status: OpcaoSelect[] = [
    { valor: '', rotulo: 'Todos os status' },
    ...opcoes.status.map((s) => ({
      valor: s.status,
      rotulo: ROTULO_STATUS[s.status] ?? s.status,
      sufixo: s.alunos,
    })),
  ]
  const unidades: OpcaoSelect[] = [
    { valor: '', rotulo: 'Todas as unidades' },
    ...opcoes.unidades.map((u) => ({
      valor: u.unidade_id,
      rotulo: u.unidade,
      sufixo: u.alunos,
    })),
  ]
  const professores: OpcaoSelect[] = [
    { valor: '', rotulo: 'Todos os professores' },
    ...opcoes.professores.map((p) => ({
      valor: String(p.professor_id),
      rotulo: p.professor,
      sufixo: p.alunos,
    })),
  ]

  return (
    // Celular: duas colunas de largura igual (o professor, que é o rótulo mais
    // longo, ocupa a linha inteira). Antes era o mesmo `flex-wrap` do desktop e
    // os três campos quebravam em larguras diferentes a cada recorte.
    <div className="mb-6 grid grid-cols-2 items-center gap-2 md:flex md:flex-wrap">
      <span className="col-span-2 flex items-center gap-2 text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary md:col-auto">
        <i className="fa-solid fa-filter text-[10px] text-brand-text" aria-hidden />
        Filtrar
      </span>
      <Select
        opcoes={status}
        valor={filtro.status ?? ''}
        aoEscolher={(v) =>
          aoMudar({
            ...filtro,
            status: v === '' ? null : (String(v) as FiltroRadar['status']),
          })
        }
        rotuloAcessivel="Filtrar por status"
        size="sm"
      />
      <Select
        opcoes={unidades}
        valor={filtro.unidadeId ?? ''}
        aoEscolher={(v) => aoMudar({ ...filtro, unidadeId: v === '' ? null : String(v) })}
        rotuloAcessivel="Filtrar por unidade"
        size="sm"
      />
      <Select
        opcoes={professores}
        valor={filtro.professorId != null ? String(filtro.professorId) : ''}
        aoEscolher={(v) => aoMudar({ ...filtro, professorId: v === '' ? null : Number(v) })}
        rotuloAcessivel="Filtrar por professor"
        size="sm"
        className="col-span-2 md:col-auto"
      />
    </div>
  )
}
