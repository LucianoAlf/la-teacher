import { Select, type OpcaoSelect } from '../../../components/ui'
import type {
  CoordenacaoFeedbackMes,
  CoracaoFiltro,
  FiltroSemaforo,
} from '../../../lib/api'

const ROTULO_CORACAO: Record<CoracaoFiltro, string> = {
  vermelho: 'Crítico',
  amarelo: 'Atenção',
  verde: 'Saudável',
  sem_resposta: 'Sem resposta',
}

/**
 * Os três recortes do semáforo: unidade, coração e professor.
 *
 * As opções vêm da PRÓPRIA RPC, com a contagem de alunos de cada uma — a
 * coordenação decide onde olhar antes de clicar, e o seletor só oferece o que
 * existe de verdade.
 *
 * Cada faceta ignora o próprio filtro e respeita as outras (079, herdando a
 * regra da 071). É o que evita o beco: escolher "Barra", a lista de professores
 * encolher pros da Barra, e não haver como voltar sem recarregar. Escolher um
 * professor, por outro lado, ENCOLHE o seletor de unidade para as unidades
 * dele — porque ali a promessa é verdadeira: não há aluno dele em outra.
 *
 * Escolher um coração muda a REGRA DA LISTA, não só o recorte: passa a mostrar
 * o grupo inteiro daquele coração (inclusive o verde calado, que a lista padrão
 * esconde). Por isso o rótulo do bloco muda junto, na página.
 */
export function FiltrosSemaforo({
  opcoes,
  filtro,
  aoMudar,
}: {
  opcoes: CoordenacaoFeedbackMes['filtros'] | null
  filtro: FiltroSemaforo
  aoMudar: (f: FiltroSemaforo) => void
}) {
  // Enquanto a primeira carga não volta não há o que oferecer, e três selects
  // vazios piscando no topo são piores que um espaço vazio.
  if (!opcoes) return null

  const unidades: OpcaoSelect[] = [
    { valor: '', rotulo: 'Todas as unidades' },
    ...opcoes.unidades.map((u) => ({ valor: u.unidade_id, rotulo: u.nome, sufixo: u.alunos })),
  ]
  const coracoes: OpcaoSelect[] = [
    { valor: '', rotulo: 'Precisam de olho' },
    ...opcoes.coracoes.map((c) => ({
      valor: c.valor,
      rotulo: ROTULO_CORACAO[c.valor] ?? c.valor,
      sufixo: c.alunos,
    })),
  ]
  const professores: OpcaoSelect[] = [
    { valor: '', rotulo: 'Todos os professores' },
    ...opcoes.professores.map((p) => ({
      valor: String(p.professor_id),
      rotulo: p.nome,
      sufixo: p.alunos,
    })),
  ]

  return (
    // Linha de ferramentas da TELA, entre os números e a lista — não no chrome
    // do topo. Regra do Alf: a faixa flutuante é do frame; o que mexe no
    // CONTEÚDO mora junto do conteúdo.
    <div className="mb-6 flex flex-wrap items-center gap-2">
      <span className="flex items-center gap-2 text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">
        <i className="fa-solid fa-filter text-[10px] text-brand-text" aria-hidden />
        Filtrar
      </span>
      <Select
        opcoes={coracoes}
        valor={filtro.coracao ?? ''}
        aoEscolher={(v) =>
          aoMudar({ ...filtro, coracao: v === '' ? null : (String(v) as CoracaoFiltro) })
        }
        rotuloAcessivel="Filtrar por coração"
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
      />
    </div>
  )
}
