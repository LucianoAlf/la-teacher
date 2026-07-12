import type { ReactNode } from 'react'
import type { SessaoAula } from '../../lib/api'
import { AulaRow, Badge } from '../../components/ui'
import { cx } from '../../lib/cx'
import { aulaRegistrada, horaSessao, podeGravar, statusSessao, subtituloSessao, tituloSessao } from './sessao'

interface Props {
  sessao: SessaoAula
  now?: Date
  /** Abrir a sessão (Home/Agenda → chamada; picker de gravação → gravador). */
  onAbrir?: (sessao: SessaoAula) => void
  /** Gravar a aula direto da linha (mostra o botão de microfone quando na janela). */
  onGravar?: (sessao: SessaoAula) => void
}

/**
 * Uma SESSÃO = uma linha. Mostra DOIS estados no mesmo peso visual, lidos de
 * relance sem tocar: CHAMADA (operacional, reversível) e REGISTRO (o prontuário
 * do aluno — o que o professor pode destruir sem querer, então grita igual).
 * Verde = feito, âmbar = falta. Só a partir do momento em que a aula começa.
 */
export function SessaoRow({ sessao, now = new Date(), onAbrir, onGravar }: Props) {
  const status = statusSessao(sessao, now)
  const parcial = sessao.n_registradas > 0 && sessao.n_registradas < sessao.n_alunos
  const mostrarGravar = onGravar != null && podeGravar(sessao, now)
  const registrada = aulaRegistrada(sessao)
  const comecou = status !== 'futura'

  // Estado da CHAMADA
  let chamadaBadge: ReactNode
  if (status === 'chamada_feita') {
    chamadaBadge = (
      <Badge variant="ok" icon="fa-solid fa-check">
        Chamada
      </Badge>
    )
  } else if (status === 'faltaram') {
    chamadaBadge = (
      <Badge variant="danger" icon="fa-solid fa-user-xmark">
        {sessao.n_alunos > 1 ? 'Faltaram' : 'Faltou'}
      </Badge>
    )
  } else if (status === 'perdida') {
    chamadaBadge = (
      <Badge variant="info" icon="fa-solid fa-lock">
        Encerrada
      </Badge>
    )
  } else if (comecou) {
    chamadaBadge = (
      <Badge variant="warn" icon="fa-solid fa-clock">
        {parcial ? `${sessao.n_registradas} de ${sessao.n_alunos}` : 'Sem chamada'}
      </Badge>
    )
  }

  // Estado do REGISTRO (prontuário) — não se aplica quando todos faltaram (sem conteúdo).
  let registroBadge: ReactNode
  if (comecou && status !== 'faltaram') {
    registroBadge = registrada ? (
      <Badge variant="ok" icon="fa-solid fa-clipboard-check">
        Registrada
      </Badge>
    ) : (
      <Badge variant="warn" icon="fa-solid fa-microphone">
        Sem registro
      </Badge>
    )
  }

  return (
    <AulaRow
      hora={horaSessao(sessao)}
      titulo={tituloSessao(sessao)}
      detalhe={subtituloSessao(sessao)}
      badge={
        chamadaBadge || registroBadge ? (
          <span className="flex flex-none flex-col items-end gap-1">
            {chamadaBadge}
            {registroBadge}
          </span>
        ) : undefined
      }
      status={status === 'futura' ? 'next' : undefined}
      action={
        mostrarGravar ? (
          <button
            type="button"
            aria-label={`${registrada ? 'Regravar' : 'Gravar'} aula — ${tituloSessao(sessao)}`}
            title={registrada ? 'Regravar — esta aula já tem relatório do Fábio' : 'Gravar aula'}
            className={cx(
              'flex h-8 w-8 flex-none items-center justify-center rounded-full transition-transform active:scale-90',
              registrada ? 'border border-brand text-brand-text' : 'bg-brand-soft text-brand-text',
            )}
            onClick={(e) => {
              e.stopPropagation()
              onGravar!(sessao)
            }}
          >
            <i className="fa-solid fa-microphone text-[13px]" aria-hidden="true" />
          </button>
        ) : undefined
      }
      onClick={onAbrir ? () => onAbrir(sessao) : undefined}
    />
  )
}
