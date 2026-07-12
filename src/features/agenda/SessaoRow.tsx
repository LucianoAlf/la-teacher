import type { ReactNode } from 'react'
import type { SessaoAula } from '../../lib/api'
import { AulaRow, Badge, type AulaStatus } from '../../components/ui'
import { horaSessao, podeGravar, statusSessao, subtituloSessao, tituloSessao } from './sessao'

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
      badge={badge}
      status={dot}
      action={
        mostrarGravar ? (
          <button
            type="button"
            aria-label={`Gravar aula — ${tituloSessao(sessao)}`}
            title="Gravar aula"
            className="flex h-8 w-8 flex-none items-center justify-center rounded-full bg-brand-soft text-brand-text transition-transform active:scale-90"
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
