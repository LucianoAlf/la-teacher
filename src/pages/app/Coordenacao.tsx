import { useCallback, useEffect, useState } from 'react'
import { CoordenacaoFrame } from './CoordenacaoFrame'
import { EmptyState, Toast, useToast } from '../../components/ui'
import { PainelNumero } from '../../features/coordenacao/components/PainelNumero'
import { FilaEmAberto } from '../../features/coordenacao/components/FilaEmAberto'
import {
  FiltrosPainel,
  SEM_FILTRO,
  type FiltroPainel,
} from '../../features/coordenacao/components/FiltrosPainel'
import { coordenacaoEmAberto, type CoordenacaoEmAberto } from '../../lib/api'

/**
 * Painel da coordenação — bloco 1: quem está com lançamento em aberto.
 *
 * Esta página COMPÕE: casca, filtros, faixa de números e fila. Ela não estiliza
 * nada — é a regra do `docs/frontend-tokens.md` ("página não estiliza"), e
 * existe pra que o segundo painel não recomece a inventar tabela do zero.
 */
export default function CoordenacaoPage() {
  const { message, visible, show } = useToast()
  const [dados, setDados] = useState<CoordenacaoEmAberto | null>(null)
  const [erro, setErro] = useState<string | null>(null)
  const [filtro, setFiltro] = useState<FiltroPainel>(SEM_FILTRO)

  const carregar = useCallback(() => {
    setErro(null)
    coordenacaoEmAberto(7, filtro.unidadeId, filtro.curso)
      .then(setDados)
      .catch((e: unknown) => {
        const msg = String((e as { message?: string })?.message ?? e)
        setErro(
          msg.includes('apenas_admin')
            ? 'Essa área é da coordenação.'
            : 'Não consegui carregar o painel agora.',
        )
      })
  }, [filtro.unidadeId, filtro.curso])

  useEffect(carregar, [carregar])

  const r = dados?.resumo
  const fila = dados?.professores ?? []
  // Ao trocar o filtro os dados antigos continuam na tela até a resposta nova.
  // Zerar aqui faria a fila piscar em branco a cada escolha.
  const carregando = !dados

  return (
    <CoordenacaoFrame titulo="Painel" icone="fa-solid fa-table-columns">
      {/* Respiro entre a faixa flutuante e os números: sem ele os KPIs colam no
          nome da página e a tela parece começar no meio. */}
      <div className="px-5 pb-5 pt-3">
        {erro ? (
          <EmptyState
            icon="fa-solid fa-triangle-exclamation"
            title={erro}
            description="Recarrega a página e tenta de novo."
          />
        ) : (
          <>
            {/* Respiro entre os três andares (KPIs → filtro → fila): 24px, o
                `--s-6` da escala. Com 14px os blocos liam como um bloco só —
                apontado pelo Alf com a tela na mão. */}
            <div className="mb-6 grid grid-cols-2 gap-2.5 md:grid-cols-4">
              {/* "Aulas" no rótulo porque a unidade mudou na 070: antes isso
                  contava pares aluno-aula e dava 847 onde o trabalho real da
                  equipe eram 624 aulas. Número grande sem unidade é o que
                  deixou a fila com "50 em aberto / 49 alunos" sem sentido. */}
              <PainelNumero
                rotulo="Aulas sem lançamento · 7 dias"
                valor={r?.sem_lancamento}
                tom="perigo"
                carregando={carregando}
              />
              <PainelNumero
                rotulo="Professores afetados"
                valor={r?.professores}
                sufixo={r ? ` de ${r.professores_ativos}` : undefined}
                carregando={carregando}
              />
              <PainelNumero
                rotulo="Aulas só de ontem"
                valor={r?.ontem}
                tom="atencao"
                carregando={carregando}
              />
              <PainelNumero
                rotulo="Na fila"
                valor={dados ? fila.length : undefined}
                carregando={carregando}
              />
            </div>

            {/* Os filtros valem pra TELA inteira (KPIs inclusive), mas moram
                abaixo dos números: resumo primeiro, ferramenta depois. */}
            <FiltrosPainel opcoes={dados?.filtros ?? null} filtro={filtro} aoMudar={setFiltro} />

            <FilaEmAberto linhas={fila} filtro={filtro} carregando={carregando} aviso={show} />
          </>
        )}
      </div>

      <Toast message={message} visible={visible} />
    </CoordenacaoFrame>
  )
}
