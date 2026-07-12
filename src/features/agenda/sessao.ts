import type { AlunoSessao, SessaoAula } from '../../lib/api'
import { formatHoraBRT } from '../../lib/date'

/**
 * Regras de apresentação da agenda por SESSÃO.
 *
 * O banco (contrato v4) devolve 1 sessão POR AULA CRUA do espelho — e o
 * Emusys representa a mesma aula real de forma redundante: 1 aula de turma
 * + 1 aula individual POR aluno no mesmo horário. agruparSessoes() refaz no
 * cliente a visão do professor (1 aula real = 1 linha), regra herdada do
 * contrato v3 (docs/contrato-agenda-sessao.md), e reconstrói o aula_id_alvo
 * de cada aluno (a individual paralela dele — alvo da fatia do Fábio).
 */

const MIN = 60_000
/** A chamada abre 15 min antes da aula e fecha 24h após o fim (regra do banco). */
const ANTECEDENCIA_CHAMADA_MS = 15 * MIN
const JANELA_POS_AULA_MS = 24 * 60 * MIN

export type StatusSessao = 'chamada_feita' | 'agora' | 'pendente' | 'perdida' | 'futura' | 'faltaram'
export type JanelaChamada = 'antes' | 'aberta' | 'encerrada'

function jaComecou(s: SessaoAula, now: Date): boolean {
  return new Date(s.data_hora_inicio) <= now
}

function jaTerminou(s: SessaoAula, now: Date): boolean {
  return s.data_hora_fim ? new Date(s.data_hora_fim) <= now : jaComecou(s, now)
}

// ---------------------------------------------------------------------------
// Agrupamento (v3 no cliente, sobre dados v4)
// ---------------------------------------------------------------------------

/**
 * Colapsa as aulas cruas de um dia em sessões reais:
 *  · aula de turma absorve as individuais paralelas dos MESMOS alunos
 *    (cada aluno ganha aula_id_alvo = a individual dele);
 *  · turma de 1 aluno com individual paralela aparece como individual (v3);
 *  · a CHAMADA grava sempre na aula de TURMA do slot (aula_id_chamada) —
 *    regra do banco ('chamada_somente_na_aula_ancora'); avulsa fica sem porta.
 */
export function agruparSessoes(cruas: SessaoAula[]): SessaoAula[] {
  const porSlot = new Map<string, SessaoAula[]>()
  for (const s of cruas) {
    const lista = porSlot.get(s.data_hora_inicio) ?? []
    lista.push(s)
    porSlot.set(s.data_hora_inicio, lista)
  }

  const resultado: SessaoAula[] = []
  for (const slot of porSlot.values()) {
    const turmas = slot.filter((s) => s.tipo === 'turma')
    const individuais = slot.filter((s) => s.tipo === 'individual')
    const absorvidas = new Set<number>()

    for (const t of turmas) {
      // casa cada aluno da turma com a individual paralela dele
      const alunos: AlunoSessao[] = t.alunos.map((a) => {
        const par = individuais.find(
          (i) =>
            !absorvidas.has(i.aula_id_ancora) &&
            i.alunos.length === 1 &&
            i.alunos[0].aluno_id != null &&
            i.alunos[0].aluno_id === a.aluno_id,
        )
        if (par) absorvidas.add(par.aula_id_ancora)
        return { ...a, aula_id_alvo: par?.aula_id_ancora ?? t.aula_id_ancora }
      })
      const agrupadas = [t.aula_id_ancora, ...alunos.map((a) => a.aula_id_alvo!).filter((id) => id !== t.aula_id_ancora)]

      if (alunos.length === 1 && alunos[0].aula_id_alvo !== t.aula_id_ancora) {
        // turma de 1: a linha visível é a individual do aluno (regra v3),
        // mas a CHAMADA grava na aula de turma (regra do banco)
        const par = individuais.find((i) => i.aula_id_ancora === alunos[0].aula_id_alvo)!
        resultado.push({
          ...par,
          alunos: par.alunos.map((a) => ({ ...a, aula_id_alvo: par.aula_id_ancora })),
          aulas_agrupadas: agrupadas,
          aula_id_chamada: t.aula_id_ancora,
        })
      } else {
        resultado.push({ ...t, alunos, aulas_agrupadas: agrupadas, aula_id_chamada: t.aula_id_ancora })
      }
    }

    for (const i of individuais) {
      if (absorvidas.has(i.aula_id_ancora)) continue
      resultado.push({
        ...i,
        alunos: i.alunos.map((a) => ({ ...a, aula_id_alvo: i.aula_id_ancora })),
        aulas_agrupadas: [i.aula_id_ancora],
        aula_id_chamada: null, // sem turma paralela → o banco não aceita chamada aqui
      })
    }
  }

  return resultado.sort(
    (a, b) => a.data_hora_inicio.localeCompare(b.data_hora_inicio) || a.aula_id_ancora - b.aula_id_ancora,
  )
}

// ---------------------------------------------------------------------------
// Estado da sessão / chamada
// ---------------------------------------------------------------------------

/** Presença como o professor lê: 'a_confirmar' = chamada ainda não feita. */
export function presencaExibida(a: AlunoSessao): 'presente' | 'faltou' | 'aguardando' {
  if (a.presenca === 'falta') return 'faltou'
  if (a.presenca === 'presente') return 'presente'
  return 'aguardando'
}

/**
 * true quando TODOS os alunos já têm PRESENÇA lançada (chamada feita).
 * Usa tem_presenca_registrada — NUNCA tem_registro: esse é o relatório do
 * Fábio (anotacoes_fabio), e gravar o áudio não é dar chamada. Confundir os
 * dois trancava a tela de chamada depois de gravar (aluno levava falta falsa).
 */
export function chamadaCompleta(s: SessaoAula): boolean {
  return s.alunos.length > 0 && s.alunos.every((a) => a.tem_presenca_registrada)
}

/** Janela de chamada da aula (regra espelhada da RPC do banco). */
export function janelaChamada(s: SessaoAula, now: Date = new Date()): JanelaChamada {
  const inicio = new Date(s.data_hora_inicio).getTime()
  const fim = s.data_hora_fim ? new Date(s.data_hora_fim).getTime() : inicio
  const t = now.getTime()
  if (t < inicio - ANTECEDENCIA_CHAMADA_MS) return 'antes'
  if (t > fim + JANELA_POS_AULA_MS) return 'encerrada'
  return 'aberta'
}

export function statusSessao(s: SessaoAula, now: Date = new Date()): StatusSessao {
  if (chamadaCompleta(s)) {
    return s.alunos.every((a) => a.presenca === 'falta') ? 'faltaram' : 'chamada_feita'
  }
  if (!jaComecou(s, now)) return 'futura'
  if (!jaTerminou(s, now)) return 'agora'
  return janelaChamada(s, now) === 'encerrada' ? 'perdida' : 'pendente'
}

/**
 * Pode gravar a aula AGORA? Regra de janela do CLIENTE — a RPC de gravação
 * (app_enfileirar_audio) NÃO valida horário (só a de chamada valida), então a
 * trava é aqui: grava-se a partir do momento em que a aula começa até 24h depois
 * (mesma janela da chamada), exceto se todo mundo faltou (Alma: sem conteúdo).
 *  · 'futura'  → nada aconteceu ainda, nada pra registrar;
 *  · 'faltaram'→ ninguém veio, não há conteúdo;
 *  · 'perdida' → passou das 24h, é assunto da coordenação.
 */
export function podeGravar(s: SessaoAula, now: Date = new Date()): boolean {
  const st = statusSessao(s, now)
  return st === 'agora' || st === 'pendente' || st === 'chamada_feita'
}

// ---------------------------------------------------------------------------
// Textos
// ---------------------------------------------------------------------------

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
  if (s.tipo === 'turma') {
    return s.n_alunos > 0 ? `${cursoAmigavel(s.curso)} · turma de ${s.n_alunos}` : `${cursoAmigavel(s.curso)} · turma`
  }
  return s.alunos[0]?.nome ?? `${cursoAmigavel(s.curso)} · Individual`
}

/** Subtítulo: turma → nomes ("faltou" marcado); individual → curso. */
export function subtituloSessao(s: SessaoAula): string {
  if (s.tipo === 'turma') {
    if (s.alunos.length === 0) return 'lista de alunos a sincronizar'
    const nomes = s.alunos.map((a) =>
      presencaExibida(a) === 'faltou' ? `${primeiroNome(a.nome)} (faltou)` : primeiroNome(a.nome),
    )
    if (nomes.length <= 1) return nomes.join('')
    return `${nomes.slice(0, -1).join(', ')} e ${nomes[nomes.length - 1]}`
  }
  return `${cursoAmigavel(s.curso)} · Individual`
}

export function horaSessao(s: SessaoAula): string {
  return formatHoraBRT(s.hora)
}

/** Nº de sessões do dia com a chamada fechada (contador honesto do card). */
export function contarChamadasFeitas(sessoes: SessaoAula[], now: Date = new Date()): number {
  return sessoes.filter((s) => {
    const st = statusSessao(s, now)
    return st === 'chamada_feita' || st === 'faltaram'
  }).length
}
