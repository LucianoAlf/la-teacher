import { supabase } from './supabase'

/**
 * Camada de dados do app: SOMENTE wrappers das RPCs app_*.
 * Proibido `supabase.from('tabela')` em qualquer lugar do cliente —
 * a segurança é resolvida no banco via auth.uid() (ver 001-fundacao-fabio.sql).
 */

/** Erro que a RPC devolve quando o usuário logado não tem professor vinculado. */
export const SEM_VINCULO = 'sem_professor_vinculado' as const

export type RpcErro = { erro: string }

export function isSemVinculo(v: unknown): v is RpcErro {
  return typeof v === 'object' && v !== null && (v as RpcErro).erro === SEM_VINCULO
}

// ---- Agenda por SESSÃO (contrato v3 — app_minha_agenda_sessao) ----
// 1 sessão = 1 aula real. Turma agrupada com alunos nomeados; cada aluno
// aponta pra própria aula individual (aula_id_alvo) — é nela que a fatia
// do Fábio grava (nunca na âncora, senão o texto vaza entre alunos).

export interface AlunoSessao {
  aluno_id: number
  nome: string
  /** Aula individual do aluno — alvo da gravação da fatia dele. */
  aula_id_alvo: number
  /** Presença crua ('presente'|'ausente'). Em aula futura, 'ausente' = ainda não lançada, NÃO "faltou". */
  presenca: string
  tem_registro: boolean
}

export interface SessaoAula {
  hora: string
  hora_fim: string | null
  data_hora_inicio: string
  data_hora_fim: string | null
  curso: string | null
  turma_nome: string | null
  tipo: 'turma' | 'individual'
  /** A aula da sessão — o áudio da gravação é enfileirado com este id. */
  aula_id_ancora: number
  n_alunos: number
  n_registradas: number
  alunos: AlunoSessao[]
}

/**
 * Linha da carteira — uma por MATRÍCULA/DISCIPLINA (jornada canônica).
 * Um aluno com dois cursos aparece duas vezes, cada um com a própria régua.
 */
export interface CarteiraAluno {
  aluno_id: number | null
  aluno_nome: string
  curso: string | null
  status_matricula: string | null
  dia_aula: string | null
  horario_aula: string | null
  /** Unidade da matrícula (professor pode ser multiunidade). */
  unidade: string | null
  /** Posição na jornada — "Aula 20/40". */
  jornada_label: string | null
  nr_aulas_passadas: number | null
  nr_aulas_contratadas: number | null
  percentual_presenca_contrato: number | null
  qualidade: string | null
}

// ---------------------------------------------------------------------------

/** Sessões de aula do professor logado numa data (default: hoje, resolvido no banco). */
export async function minhaAgendaSessao(data?: string): Promise<SessaoAula[] | RpcErro> {
  const { data: res, error } = await supabase.rpc('app_minha_agenda_sessao', data ? { p_data: data } : {})
  if (error) throw error
  if (isSemVinculo(res)) return res
  return (res as unknown as SessaoAula[]) ?? []
}

/**
 * Carteira do professor logado — lê a jornada canônica
 * (vw_jornada_professor_atual, via porta guardada no banco).
 * Nunca retorna dado financeiro nem contato (telefone/whatsapp).
 */
export async function minhaCarteira(): Promise<CarteiraAluno[] | RpcErro> {
  const { data: res, error } = await supabase.rpc('app_minha_carteira')
  if (error) throw error
  if (isSemVinculo(res)) return res
  return res as unknown as CarteiraAluno[]
}

/** Registros do professor logado, opcionalmente filtrados por status. */
export async function meusRegistros(status?: string): Promise<unknown[]> {
  const { data: res, error } = await supabase.rpc('app_meus_registros', status ? { p_status: status } : {})
  if (error) throw error
  return (res as unknown[]) ?? []
}

export interface PendenciaConfirmacao {
  fatia_id: string
  aluno_id: number | null
  motivo: string
}

export interface ConfirmacaoResultado {
  registro_id: string
  gravadas: number
  ausentes_puladas: number
  pendencias: PendenciaConfirmacao[]
}

/**
 * Confirma um registro → grava POR ALUNO via porta única registrar_aula_fabio
 * (fatias presentes com texto; ausentes são puladas). LANÇA exceção em erro.
 */
export async function confirmarRegistro(registroId: string): Promise<ConfirmacaoResultado> {
  const { data: res, error } = await supabase.rpc('app_confirmar_registro', { p_registro_id: registroId })
  if (error) throw error
  return res as unknown as ConfirmacaoResultado
}

// ---------------------------------------------------------------------------
// Sprint 3 · motor de registro
// ---------------------------------------------------------------------------

/** Linha de fabio_registros_aula (tronco ou fatia) como a RPC devolve. */
export interface RegistroRow {
  id: string
  aula_id: number | null
  aluno_id: number | null
  parent_id: string | null
  molde: 'A' | 'B' | 'C'
  campos: Record<string, unknown>
  texto_consolidado: string | null
  status: string
  origem: string
  criado_em: string
  [k: string]: unknown
}

export interface AulaContexto {
  data_aula: string | null
  hora: string | null
  turma: string | null
  curso: string | null
  tipo: string | null
}

export interface RegistroCompleto {
  tronco: RegistroRow
  fatias: RegistroRow[]
  aula: AulaContexto | null
}

/** Tronco + fatias + contexto da aula. Erros da RPC: sem_professor | nao_encontrado. */
export async function registroCompleto(registroId: string): Promise<RegistroCompleto | RpcErro> {
  const { data: res, error } = await supabase.rpc('app_registro_completo', { p_registro_id: registroId })
  if (error) throw error
  const obj = res as unknown as RegistroCompleto | RpcErro
  return obj
}

/** Registros (troncos) do professor aguardando confirmação, mais recentes primeiro. */
export async function registrosPendentes(): Promise<RegistroRow[]> {
  const { data: res, error } = await supabase.rpc('app_registros_pendentes')
  if (error) throw error
  return (res as unknown as RegistroRow[]) ?? []
}

/**
 * Atualiza texto e/ou campos (merge) de um tronco/fatia em edição.
 * Só o dono, só em rascunho/aguardando_confirmacao. LANÇA exceção em erro.
 */
export async function atualizarFatia(
  id: string,
  texto: string | null,
  campos: Record<string, unknown> | null,
): Promise<RegistroRow> {
  const { data: res, error } = await supabase.rpc('app_atualizar_fatia', {
    p_id: id,
    ...(texto != null ? { p_texto: texto } : {}),
    ...(campos != null ? { p_campos: campos as never } : {}),
  })
  if (error) throw error
  return res as unknown as RegistroRow
}

export interface EnfileirarResultado {
  audio_id: string
  status: 'pendente'
  modo: 'novo' | 'complementar'
  registro_id: string | null
}

/**
 * Enfileira um áudio gravado (fabio_fila_audios) para o Fábio processar.
 * A RPC resolve professor e unidade via auth.uid(); `registroId` não nulo
 * marca correção por voz (modo complementar). LANÇA exceção em erro.
 */
export async function enfileirarAudio(
  aulaId: number,
  storagePath: string,
  duracaoSegundos: number,
  registroId: string | null = null,
): Promise<EnfileirarResultado> {
  const { data: res, error } = await supabase.rpc('app_enfileirar_audio', {
    p_aula_id: aulaId,
    p_storage_path: storagePath,
    p_duracao_segundos: duracaoSegundos,
    ...(registroId ? { p_registro_id: registroId } : {}),
  })
  if (error) throw error
  return res as unknown as EnfileirarResultado
}
