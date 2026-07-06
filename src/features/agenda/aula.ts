import type { AgendaAula } from '../../lib/api'
import { formatHoraBRT } from '../../lib/date'

export type StatusAula = 'registrada' | 'agora' | 'sem_registro' | 'futura'

/** Registro existe se anotacoes_fabio OU anotacoes está preenchida. */
export function temRegistro(a: AgendaAula): boolean {
  const f = a.anotacoes_fabio?.trim()
  const n = a.anotacoes?.trim()
  return Boolean(f || n)
}

/**
 * Status derivado (P3): registrada → agora (em andamento) → sem_registro
 * (passou e ninguém registrou) → futura. `now` injetável para testes.
 */
export function statusAula(a: AgendaAula, now: Date = new Date()): StatusAula {
  if (temRegistro(a)) return 'registrada'
  const ini = a.data_hora_inicio ? new Date(a.data_hora_inicio) : null
  const fim = a.data_hora_fim ? new Date(a.data_hora_fim) : null
  if (ini && fim && ini <= now && now < fim) return 'agora'
  if (fim && now >= fim) return 'sem_registro'
  return 'futura'
}

/** Nome de exibição: aluno (individual) ou turma. */
export function nomeAula(a: AgendaAula): string {
  if (a.aula_tipo === 'individual' && a.aluno_nome) return a.aluno_nome
  return a.turma_nome || a.aluno_nome || a.curso_nome || 'Aula'
}

/** Linha secundária: curso + tipo (turma mostra nº de alunos). */
export function detalheAula(a: AgendaAula): string {
  const partes: string[] = []
  if (a.curso_nome) partes.push(a.curso_nome)
  if (a.aula_tipo === 'individual') {
    partes.push('Individual')
  } else if (a.turma_nome) {
    partes.push(a.qtd_alunos && a.qtd_alunos > 1 ? `Turma · ${a.qtd_alunos} alunos` : 'Turma')
  }
  return partes.join(' · ')
}

export function horaAula(a: AgendaAula): string {
  return formatHoraBRT(a.horario_inicio_brt)
}

export function contarRegistradas(aulas: AgendaAula[]): number {
  return aulas.filter(temRegistro).length
}
