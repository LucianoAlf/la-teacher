import type { CarteiraAluno } from '../../lib/api'
import { formatHoraBRT } from '../../lib/date'

/** Remove acentos e caixa para busca tolerante ("joao" acha "João"). */
export function normalizar(s: string): string {
  return s
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .trim()
}

// Traduz o código técnico de qualidade_contexto para algo que o professor entende.
const QUALIDADE_LABEL: Record<string, string> = {
  aluno_sem_id_emusys: 'cadastro incompleto',
  sem_matricula_ativa: 'matrícula a confirmar',
  sem_contexto: 'cadastro incompleto',
}

/** null quando está 'ok'; senão texto amigável (nunca o código cru). */
export function qualidadeLabel(q: string | null | undefined): string | null {
  if (!q || q === 'ok') return null
  return QUALIDADE_LABEL[q] ?? 'cadastro incompleto'
}

/** "Terça · 15h" a partir de dia_aula + horario_aula (canônica manda "Terça-feira"). */
export function horarioAluno(a: CarteiraAluno): string {
  const dia = (a.dia_aula ?? '').replace(/-feira$/i, '')
  const hora = a.horario_aula ? formatHoraBRT(a.horario_aula) : ''
  return [dia, hora].filter(Boolean).join(' · ')
}

export interface GrupoCurso {
  curso: string
  alunos: CarteiraAluno[]
}

export interface UnidadeContagem {
  unidade: string
  total: number
}

/**
 * Unidades distintas da carteira, com contagem, em ordem alfabética pt-BR.
 * Só faz sentido oferecer o filtro quando há mais de uma (professor multiunidade).
 * Alunos sem unidade caem em "Sem unidade" (só aparece se realmente existir).
 */
export function contarPorUnidade(alunos: CarteiraAluno[]): UnidadeContagem[] {
  const map = new Map<string, number>()
  for (const a of alunos) {
    const u = a.unidade ?? 'Sem unidade'
    map.set(u, (map.get(u) ?? 0) + 1)
  }
  return [...map.entries()]
    .map(([unidade, total]) => ({ unidade, total }))
    .sort((a, b) => a.unidade.localeCompare(b.unidade, 'pt'))
}

/** Agrupa a carteira por curso (grupos e alunos em ordem alfabética pt-BR). */
export function agruparPorCurso(alunos: CarteiraAluno[]): GrupoCurso[] {
  const map = new Map<string, CarteiraAluno[]>()
  for (const a of alunos) {
    const c = a.curso ?? 'Sem curso'
    if (!map.has(c)) map.set(c, [])
    map.get(c)!.push(a)
  }
  return [...map.entries()]
    .map(([curso, lista]) => ({
      curso,
      alunos: [...lista].sort((x, y) => x.aluno_nome.localeCompare(y.aluno_nome, 'pt')),
    }))
    .sort((a, b) => a.curso.localeCompare(b.curso, 'pt'))
}
