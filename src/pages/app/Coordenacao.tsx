import { useCallback, useEffect, useState } from 'react'
import { CoordenacaoFrame } from './CoordenacaoFrame'
import { EmptyState, Toast, useToast } from '../../components/ui'
import { PainelNumero } from '../../features/coordenacao/components/PainelNumero'
import { FilaEmAberto } from '../../features/coordenacao/components/FilaEmAberto'
import { coordenacaoEmAberto, type CoordenacaoEmAberto } from '../../lib/api'

const HOJE = new Intl.DateTimeFormat('pt-BR', {
  weekday: 'short',
  day: 'numeric',
  month: 'long',
}).format(new Date())

/**
 * Painel da coordenação — bloco 1: quem está com lançamento em aberto.
 *
 * Esta página COMPÕE: casca, faixa de números e fila. Ela não estiliza nada —
 * é a regra do `docs/frontend-tokens.md` ("página não estiliza"), e existe pra
 * que o segundo painel não recomece a inventar tabela do zero.
 */
export default function CoordenacaoPage() {
  const { message, visible, show } = useToast()
  const [dados, setDados] = useState<CoordenacaoEmAberto | null>(null)
  const [erro, setErro] = useState<string | null>(null)

  const carregar = useCallback(() => {
    setErro(null)
    coordenacaoEmAberto(7, null)
      .then(setDados)
      .catch((e: unknown) => {
        const msg = String((e as { message?: string })?.message ?? e)
        setErro(
          msg.includes('apenas_admin')
            ? 'Essa área é da coordenação.'
            : 'Não consegui carregar o painel agora.',
        )
      })
  }, [])

  useEffect(carregar, [carregar])

  const r = dados?.resumo
  const fila = dados?.professores ?? []

  return (
    <CoordenacaoFrame
      titulo="Coordenação"
      acaoTopo={<span className="text-[11.5px] text-text-muted">{HOJE}</span>}
    >
      <div className="p-4">
        {erro ? (
          <EmptyState
            icon="fa-solid fa-triangle-exclamation"
            title={erro}
            description="Recarrega a página e tenta de novo."
          />
        ) : (
          <>
            <div className="mb-3.5 grid grid-cols-2 gap-2.5 md:grid-cols-4">
              <PainelNumero
                rotulo="Sem lançamento · 7 dias"
                valor={r?.sem_lancamento}
                tom="perigo"
                carregando={!dados}
              />
              <PainelNumero
                rotulo="Professores afetados"
                valor={r?.professores}
                sufixo={r ? ` de ${r.professores_ativos}` : undefined}
                carregando={!dados}
              />
              <PainelNumero
                rotulo="Só de ontem"
                valor={r?.ontem}
                tom="atencao"
                carregando={!dados}
              />
              <PainelNumero rotulo="Na fila" valor={dados ? fila.length : undefined} carregando={!dados} />
            </div>

            <FilaEmAberto linhas={fila} carregando={!dados} aviso={show} />
          </>
        )}
      </div>

      <Toast message={message} visible={visible} />
    </CoordenacaoFrame>
  )
}
