import type { CarteiraAluno } from '../../lib/api'
import { Badge } from '../../components/ui'
import { horarioAluno, qualidadeLabel } from './carteira'

/** Célula de aluno na carteira: avatar, nome, dia/horário e badge de qualidade. */
export function AlunoRow({ aluno }: { aluno: CarteiraAluno }) {
  const qualidade = qualidadeLabel(aluno.qualidade)
  const horario = horarioAluno(aluno)

  return (
    <div className="flex items-center gap-3 border-b border-border-subtle px-1 py-[11px] last:border-b-0">
      <span className="flex h-9 w-9 flex-none items-center justify-center rounded-full bg-brand-soft text-[13px] font-extrabold text-brand-text">
        {aluno.aluno_nome.charAt(0).toUpperCase()}
      </span>
      <div className="min-w-0 flex-1">
        <b className="block truncate text-sm font-semibold">{aluno.aluno_nome}</b>
        <span className="block truncate text-xs text-text-secondary">
          {[horario, aluno.tipo_matricula].filter(Boolean).join(' · ')}
        </span>
      </div>
      {qualidade && (
        <Badge variant="warn" icon="fa-solid fa-circle-info">
          {qualidade}
        </Badge>
      )}
    </div>
  )
}
