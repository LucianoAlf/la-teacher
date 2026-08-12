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
/** A chamada abre 15 min antes da aula e fecha JANELA_POS_AULA_DIAS após o fim. */
const ANTECEDENCIA_CHAMADA_MS = 15 * MIN
/**
 * ESPELHO de `fn_janela_registro_dias()` no banco (migration 084). O dono do
 * número é o banco: `fn_registrar_presencas_core` e `app_enfileirar_audio`
 * recusam fora dela, e `fn_pendencias_escalonadas` usa a mesma régua pra
 * decidir o que sobe pra coordenação. Mudou lá, muda aqui — senão o app volta
 * a oferecer botão que o servidor recusa (ou a esconder botão que funciona).
 *
 * Era 3. Virou 7 em 10/08, depois que a professora Daiana tentou lançar as
 * aulas de 04 e 05/08 na noite de 08/08 e encontrou um cadeado — a janela
 * tinha fechado poucas horas antes, e ela foi pro WhatsApp.
 */
export const JANELA_POS_AULA_DIAS = 7
const JANELA_POS_AULA_MS = JANELA_POS_AULA_DIAS * 24 * 60 * MIN

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
  for (const slotCru of porSlot.values()) {
    const slot = reduzirDuplicatasOperacionais(slotCru)
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
      const temRascunho = slot.some(
        (aula) => agrupadas.includes(aula.aula_id_ancora) && aula.tem_rascunho === true,
      )

      if (alunos.length === 1 && alunos[0].aula_id_alvo !== t.aula_id_ancora) {
        // turma de 1: a linha visível é a individual do aluno (regra v3),
        // mas a CHAMADA grava na aula de turma (regra do banco)
        const par = individuais.find((i) => i.aula_id_ancora === alunos[0].aula_id_alvo)!
        resultado.push({
          ...par,
          alunos: par.alunos.map((a) => ({ ...a, aula_id_alvo: par.aula_id_ancora })),
          aulas_agrupadas: agrupadas,
          aula_id_chamada: t.aula_id_ancora,
          tem_rascunho: temRascunho,
        })
      } else {
        resultado.push({ ...t, alunos, aulas_agrupadas: agrupadas, aula_id_chamada: t.aula_id_ancora, tem_rascunho: temRascunho })
      }
    }

    for (const i of individuais) {
      if (absorvidas.has(i.aula_id_ancora)) continue
      resultado.push({
        ...i,
        alunos: i.alunos.map((a) => ({ ...a, aula_id_alvo: i.aula_id_ancora })),
        aulas_agrupadas: [i.aula_id_ancora],
        // Individual STANDALONE (sem turma pareada — ex.: aula reagendada): a
        // própria individual é a âncora da chamada. O banco agora aceita
        // (app_registrar_presencas_aula permite individual sem turma irmã).
        aula_id_chamada: i.aula_id_ancora,
      })
    }
  }

  return resultado.sort(
    (a, b) => a.data_hora_inicio.localeCompare(b.data_hora_inicio) || a.aula_id_ancora - b.aula_id_ancora,
  )
}

/**
 * Defesa para payloads legados: o Emusys pode manter uma turma vazia antiga
 * junto da aula atual do mesmo curso/horário. A RPC canônica já resolve isso no
 * banco; esta redução impede que um cache ou cliente antigo volte a exibir a
 * âncora vazia.
 */
function reduzirDuplicatasOperacionais(slot: SessaoAula[]): SessaoAula[] {
  const porCursoEDuracao = new Map<string, SessaoAula[]>()
  for (const sessao of slot) {
    const chave = `${sessao.data_hora_fim ?? ''}\u0000${sessao.curso ?? ''}`
    const candidatas = porCursoEDuracao.get(chave) ?? []
    candidatas.push(sessao)
    porCursoEDuracao.set(chave, candidatas)
  }

  return [...porCursoEDuracao.values()].flatMap((candidatas) => {
    const turmas = candidatas.filter((sessao) => sessao.tipo === 'turma')
    const individuais = candidatas.filter((sessao) => sessao.tipo === 'individual')
    if (turmas.length === 0) return individuais

    const melhorTurma = [...turmas].sort(
      (a, b) => b.alunos.length - a.alunos.length || b.aula_id_ancora - a.aula_id_ancora,
    )[0]
    const maiorRosterIndividual = individuais.reduce(
      (maior, sessao) => Math.max(maior, sessao.alunos.length),
      0,
    )

    if (melhorTurma.alunos.length === 0 && maiorRosterIndividual > 0) {
      return individuais
    }
    return [melhorTurma, ...individuais]
  })
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

/**
 * true = a aula já tem RELATÓRIO do Fábio (anotacoes_fabio) pra algum aluno —
 * é o `tem_registro` por aluno (relatório, NÃO presença). Gravar de novo em cima
 * disso substitui em silêncio se o professor não perceber; por isso a UI precisa
 * mostrar "Registrada" e avisar antes de regravar.
 */
export function aulaRegistrada(s: SessaoAula): boolean {
  return s.alunos.some((a) => a.tem_registro)
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
 * Pode gravar a aula AGORA? Janela do CLIENTE espelhando o SERVIDOR — tanto
 * app_enfileirar_audio (gravação) quanto a RPC de chamada validam
 * `fn_janela_registro_dias()` no banco. O guard de janela aqui alinha o mic com
 * o servidor: não mostra botão que o backend vai recusar (antes o mic aparecia
 * em aula fora da janela e só estourava 'janela_encerrada' na hora de enviar).
 * Grava-se do início da aula até JANELA_POS_AULA_DIAS depois, exceto se todo
 * mundo faltou (Alma: sem conteúdo).
 *  · 'futura'  → nada aconteceu ainda, nada pra registrar;
 *  · 'faltaram'→ ninguém veio, não há conteúdo;
 *  · 'perdida' → passou do prazo, é assunto da coordenação.
 */
export function podeGravar(s: SessaoAula, now: Date = new Date()): boolean {
  if (janelaChamada(s, now) === 'encerrada') return false
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
