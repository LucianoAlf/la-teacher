import { Select } from '../../../components/ui'
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

  return (
    <div className="flex items-center gap-2">
      <Select
        size="sm"
        aria-label="Filtrar por unidade"
        value={filtro.unidadeId ?? ''}
        onChange={(e) => aoMudar({ ...filtro, unidadeId: e.target.value || null })}
      >
        <option value="">Todas as unidades</option>
        {opcoes.unidades.map((u) => (
          <option key={u.unidade_id} value={u.unidade_id}>
            {u.nome} · {u.aulas}
          </option>
        ))}
      </Select>

      <Select
        size="sm"
        aria-label="Filtrar por curso"
        value={filtro.curso ?? ''}
        onChange={(e) => aoMudar({ ...filtro, curso: e.target.value || null })}
      >
        <option value="">Todos os cursos</option>
        {opcoes.cursos.map((c) => (
          <option key={c.chave} value={c.chave}>
            {c.nome} · {c.aulas}
          </option>
        ))}
      </Select>
    </div>
  )
}
