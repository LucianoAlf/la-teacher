import type { AlunoSessao, SessaoAula } from '../../lib/api'
import { formatHoraBRT } from '../../lib/date'

/**
 * Regras de apresentação da agenda por SESSÃO (contrato v3).
 * O professor pensa em "aulas", não em linhas do espelho.
 */

export type StatusSessao = 'registrada' | 'agora' | 'pendente' | 'futura' | 'faltaram'

function jaComecou(s: SessaoAula, now: Date): boolean {
  return new Date(s.data_hora_inicio) <= now
}

function jaTerminou(s: SessaoAula, now: Date): boolean {
  return s.data_hora_fim ? new Date(s.data_hora_fim) <= now : jaComecou(s, now)
}

/**
 * "ausente" numa aula que ainda não aconteceu NÃO é falta — é presença não
 * lançada (o sync do Emusys é retroativo). Só vira "faltou" depois da aula.
 */
export function presencaExibida(a: AlunoSessao, s: SessaoAula, now: Date = new Date()): 'presente' | 'faltou' | 'aguardando' {
  if (!jaTerminou(s, now)) return 'aguardando'
  return a.presenca === 'ausente' ? 'faltou' : 'presente'
}

/** Alunos que ainda DEVEM registro: presentes (ou sem presença lançada) sem anotação. */
export function alunosPendentes(s: SessaoAula, now: Date = new Date()): AlunoSessao[] {
  return s.alunos.filter((a) => !a.tem_registro && presencaExibida(a, s, now) !== 'faltou')
}

export function statusSessao(s: SessaoAula, now: Date = new Date()): StatusSessao {
  if (s.alunos.length > 0 && s.alunos.every((a) => a.tem_registro)) return 'registrada'
  if (!jaComecou(s, now)) return 'futura'
  if (!jaTerminou(s, now)) return 'agora'
  if (alunosPendentes(s, now).length > 0) return 'pendente'
  // passado, ninguém devendo registro: houve registro parcial → registrada;
  // ninguém registrado (todos faltaram) → estado próprio, sem fingir registro
  return s.n_registradas > 0 ? 'registrada' : 'faltaram'
}

/** "Canto T" → "Canto" (sufixo técnico do Emusys fora da UI). */
export function cursoAmigavel(curso: string | null | undefined): string {
  if (!curso) return 'Aula'
  return curso.replace(/\s+T$/, '')
}

export function primeiroNome(nome: string): string {
  return nome.trim().split(/\s+/)[0]
}

/** Título da linha: turma → "Canto · turma de 3"; individual → nome do aluno. */
export function tituloSessao(s: SessaoAula): string {
  if (s.tipo === 'turma') return `${cursoAmigavel(s.curso)} · turma de ${s.n_alunos}`
  return s.alunos[0]?.nome ?? cursoAmigavel(s.curso)
}

/** Subtítulo: turma → nomes ("faltou" marcado após a aula); individual → curso. */
export function subtituloSessao(s: SessaoAula, now: Date = new Date()): string {
  if (s.tipo === 'turma') {
    const nomes = s.alunos.map((a) =>
      presencaExibida(a, s, now) === 'faltou' ? `${primeiroNome(a.nome)} (faltou)` : primeiroNome(a.nome),
    )
    if (nomes.length <= 1) return nomes.join('')
    return `${nomes.slice(0, -1).join(', ')} e ${nomes[nomes.length - 1]}`
  }
  return `${cursoAmigavel(s.curso)} · Individual`
}

export function horaSessao(s: SessaoAula): string {
  return formatHoraBRT(s.hora)
}

/** Nº de sessões do dia totalmente registradas (contador honesto do card). */
export function contarSessoesRegistradas(sessoes: SessaoAula[], now: Date = new Date()): number {
  return sessoes.filter((s) => statusSessao(s, now) === 'registrada').length
}
