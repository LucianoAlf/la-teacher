import { Select, type OpcaoSelect } from '../../../components/ui'
import type { CoordenacaoEmAberto } from '../../../lib/api'

/** O recorte que a coordenação está olhando. `null` = tudo. */
export interface FiltroPainel {
  unidadeId: string | null
  /** CHAVE agrupada do curso ("bateria"), nunca o nome cru. */
  curso: string | null
}

export const SEM_FILTRO: FiltroPainel = { unidadeId: null, curso: null }

/**
 * Filtros de unidade e curso da faixa do topo.
 *
 * As opções vêm da PRÓPRIA RPC, não de uma tabela de cadastro: assim a lista só
 * oferece o que tem pendência de verdade, e cada opção mostra quantas aulas
 * representa — a coordenação decide onde olhar antes de clicar.
 *
 * Cada faceta ignora o próprio filtro e respeita a outra (071). É o que evita o
 * beco: escolher "Barra", a lista de cursos encolher para os cursos da Barra, e
 * não haver como voltar pra "Todas" sem recarregar.
 *
 * O rótulo do curso vem SEM a modalidade ("Bateria", não "Bateria T") porque o
 * filtro age no grupo inteiro. Rótulo que promete menos do que o clique faz é a
 * mesma mentira do selo verde de presença.
 */
export function FiltrosPainel({
  opcoes,
  filtro,
  aoMudar,
}: {
  opcoes: CoordenacaoEmAberto['filtros'] | null
  filtro: FiltroPainel
  aoMudar: (f: FiltroPainel) => void
}) {
  // Enquanto a primeira carga não volta não há o que oferecer — e um select
  // vazio piscando no topo é pior que um espaço vazio.
  if (!opcoes) return null

  const unidades: OpcaoSelect[] = [
    { valor: '', rotulo: 'Todas as unidades' },
    ...opcoes.unidades.map((u) => ({ valor: u.unidade_id, rotulo: u.nome, sufixo: u.aulas })),
  ]
  const cursos: OpcaoSelect[] = [
    { valor: '', rotulo: 'Todos os cursos' },
    ...opcoes.cursos.map((c) => ({ valor: c.chave, rotulo: c.nome, sufixo: c.aulas })),
  ]

  const ativo = filtro.unidadeId !== null || filtro.curso !== null

  return (
    // Linha de ferramentas da TELA, entre os KPIs e a fila — não no chrome do
    // topo. O Alf cravou a regra: a faixa flutuante é do frame (página, data,
    // tema, perfil); o que mexe no CONTEÚDO mora junto do conteúdo. E a linha
    // é uma barra com nome ("Filtrar"), não dois selects soltos: é aqui que os
    // próximos controles da tela vão morar.
    <div className="mb-3.5 flex flex-wrap items-center gap-2">
      <span className="flex items-center gap-2 text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">
        <i className="fa-solid fa-filter text-[10px] text-brand-text" aria-hidden="true" />
        Filtrar
      </span>
      <Select
        size="sm"
        className="w-[172px]"
        rotuloAcessivel="Filtrar por unidade"
        opcoes={unidades}
        valor={filtro.unidadeId ?? ''}
        aoEscolher={(v) => aoMudar({ ...filtro, unidadeId: v || null })}
      />
      <Select
        size="sm"
        className="w-[172px]"
        rotuloAcessivel="Filtrar por curso"
        opcoes={cursos}
        valor={filtro.curso ?? ''}
        aoEscolher={(v) => aoMudar({ ...filtro, curso: v || null })}
      />
      {/* Sai do recorte num toque. Só existe quando há recorte: botão de
          limpar com nada pra limpar ensina a não ler os botões. */}
      {ativo && (
        <button
          type="button"
          onClick={() => aoMudar(SEM_FILTRO)}
          className="text-[12px] text-text-secondary underline-offset-2 hover:text-text-primary hover:underline"
        >
          limpar
        </button>
      )}
    </div>
  )
}
