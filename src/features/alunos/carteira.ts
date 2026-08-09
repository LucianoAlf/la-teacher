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
 * Quantos ALUNOS a carteira tem — não quantas linhas.
 *
 * A carteira vem no grão matrícula/disciplina: quem faz Canto e Violão com o
 * mesmo professor ocupa duas linhas. Contar linhas fazia a tela dizer 57
 * enquanto a mesa do feedback (que colapsa por aluno) dizia 51, e o card
 * "Feedback do mês" leva de uma tela pra outra — o professor via o número
 * mudar sozinho no caminho. Medido em 09/08: 5 dos 6 professores com login
 * viam números diferentes, até 6 de diferença.
 */
export function contarAlunos(alunos: CarteiraAluno[]): number {
  return contarUnicos(alunos)
}

/**
 * `aluno_id` é anulável (`CarteiraAluno`). Jogar todos os nulos num Set os
 * fundiria num aluno só — dois cadastros incompletos diferentes virariam "1".
 * Sem id não dá pra saber se são a mesma pessoa, então cada linha nula conta
 * por si: superestimar de leve é melhor do que sumir com aluno da contagem.
 */
function contarUnicos(alunos: CarteiraAluno[]): number {
  const ids = new Set<number>()
  let semId = 0
  for (const a of alunos) {
    if (a.aluno_id == null) semId += 1
    else ids.add(a.aluno_id)
  }
  return ids.size + semId
}

/**
 * Unidades distintas da carteira, com contagem, em ordem alfabética pt-BR.
 * Só faz sentido oferecer o filtro quando há mais de uma (professor multiunidade).
 * Alunos sem unidade caem em "Sem unidade" (só aparece se realmente existir).
 *
 * Conta aluno, não linha, pelo mesmo motivo de `contarAlunos`. A soma dos
 * chips pode passar do total de "Todas" quando o mesmo aluno estuda em duas
 * unidades — o número do chip responde "quantos eu vejo se filtrar por esta",
 * e essa resposta continua certa.
 */
export function contarPorUnidade(alunos: CarteiraAluno[]): UnidadeContagem[] {
  const map = new Map<string, CarteiraAluno[]>()
  for (const a of alunos) {
    const u = a.unidade ?? 'Sem unidade'
    if (!map.has(u)) map.set(u, [])
    map.get(u)!.push(a)
  }
  return [...map.entries()]
    .map(([unidade, lista]) => ({ unidade, total: contarUnicos(lista) }))
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
