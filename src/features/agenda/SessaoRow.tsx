import type { ReactNode } from 'react'
import type { SessaoAula } from '../../lib/api'
import { AulaRow, Badge, type AulaStatus } from '../../components/ui'
import { horaSessao, statusSessao, subtituloSessao, tituloSessao } from './sessao'

interface Props {
  sessao: SessaoAula
  now?: Date
  /** Abrir a gravação desta sessão (o áudio vai pra aula_id_ancora). */
  onGravar?: (sessao: SessaoAula) => void
}

/** Uma SESSÃO = uma linha: turma agrupada com nomes, individual com a pessoa. */
export function SessaoRow({ sessao, now = new Date(), onGravar }: Props) {
  const status = statusSessao(sessao, now)
  const parcial = sessao.n_registradas > 0 && sessao.n_registradas < sessao.n_alunos

  let dot: AulaStatus | undefined
  let badge: ReactNode

  if (status === 'registrada') {
    dot = 'ok'
    badge = (
      <Badge variant="ok" icon="fa-solid fa-check">
        Registrada
      </Badge>
    )
  } else if (status === 'agora') {
    dot = 'now'
    badge = (
      <Badge variant="brand" icon="fa-solid fa-microphone">
        Registrar
      </Badge>
    )
  } else if (status === 'pendente') {
    badge = (
      <Badge variant="warn" icon="fa-solid fa-clock">
        {parcial ? `${sessao.n_registradas} de ${sessao.n_alunos}` : 'Sem registro'}
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

  // registrada/faltaram: nada a gravar (ausente não recebe conteúdo — Alma)
  const clicavel = status !== 'registrada' && status !== 'faltaram' && onGravar ? () => onGravar(sessao) : undefined

  return (
    <AulaRow
      hora={horaSessao(sessao)}
      titulo={tituloSessao(sessao)}
      detalhe={subtituloSessao(sessao, now)}
      badge={badge}
      status={dot}
      onClick={clicavel}
    />
  )
}
