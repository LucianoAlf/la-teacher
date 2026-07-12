import type { ReactNode } from 'react'
import type { SessaoAula } from '../../lib/api'
import { AulaRow, Badge, type AulaStatus } from '../../components/ui'
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

/** Uma SESSÃO = uma linha: turma agrupada com nomes, individual com a pessoa. */
export function SessaoRow({ sessao, now = new Date(), onAbrir, onGravar }: Props) {
  const status = statusSessao(sessao, now)
  const parcial = sessao.n_registradas > 0 && sessao.n_registradas < sessao.n_alunos
  const mostrarGravar = onGravar != null && podeGravar(sessao, now)
  const registrada = aulaRegistrada(sessao)

  let dot: AulaStatus | undefined
  let badge: ReactNode

  if (status === 'chamada_feita') {
    dot = 'ok'
    badge = (
      <Badge variant="ok" icon="fa-solid fa-check">
        Chamada feita
      </Badge>
    )
  } else if (status === 'agora') {
    dot = 'now'
    badge = (
      <Badge variant="brand" icon="fa-solid fa-list-check">
        Fazer chamada
      </Badge>
    )
  } else if (status === 'pendente') {
    badge = (
      <Badge variant="warn" icon="fa-solid fa-clock">
        {parcial ? `${sessao.n_registradas} de ${sessao.n_alunos}` : 'Sem chamada'}
      </Badge>
    )
  } else if (status === 'perdida') {
    badge = (
      <Badge variant="info" icon="fa-solid fa-lock">
        Janela encerrada
      </Badge>
    )
  } else if (status === 'faltaram') {
    badge = (
      <Badge variant="danger" icon="fa-solid fa-user-xmark">
        {sessao.n_alunos > 1 ? 'Faltaram' : 'Faltou'}
      </Badge>
    )
  } else {
    dot = 'next'
  }

  return (
    <AulaRow
      hora={horaSessao(sessao)}
      titulo={tituloSessao(sessao)}
      detalhe={subtituloSessao(sessao)}
      badge={
        registrada ? (
          <span className="flex items-center gap-1.5">
            {badge}
            <span
              className="flex h-[26px] flex-none items-center gap-1 rounded-full bg-brand-soft px-2 text-[11px] font-semibold text-brand-text"
              title="Esta aula já tem relatório do Fábio"
              aria-label="Aula já registrada pelo Fábio"
            >
              <i className="fa-solid fa-clipboard-check text-[11px]" aria-hidden="true" />
            </span>
          </span>
        ) : (
          badge
        )
      }
      status={dot}
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
