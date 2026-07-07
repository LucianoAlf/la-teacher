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

// ---- Shapes leves do retorno (o detalhe fino das aulas vem no P3) ----

export interface AgendaAula {
  aula_local_id: number
  aula_emusys_id: number | null
  data_aula: string
  data_hora_inicio: string | null
  data_hora_fim: string | null
  horario_inicio_brt: string | null
  horario_fim_brt: string | null
  aula_tipo: string | null
  aula_categoria: string | null
  turma_nome: string | null
  curso_nome: string | null
  aluno_nome: string | null
  qtd_alunos: number | null
  presenca_status: string | null
  cancelada: boolean | null
  anotacoes: string | null
  anotacoes_fabio: string | null
  qualidade_contexto: string | null
  [k: string]: unknown
}

export interface Agenda {
  data: string
  total: number
  aulas: AgendaAula[]
}

export interface CarteiraAluno {
  aluno_id: number
  aluno_nome: string
  aluno_status: string | null
  curso: string | null
  tipo_matricula: string | null
  dia_aula: string | null
  horario_aula: string | null
  responsavel: string | null
  qualidade: string | null
}

// ---------------------------------------------------------------------------

/** Agenda do professor logado numa data (default: hoje, resolvido no banco). */
export async function minhaAgenda(data?: string): Promise<Agenda | RpcErro> {
  const { data: res, error } = await supabase.rpc('app_minha_agenda', data ? { p_data: data } : {})
  if (error) throw error
  if (isSemVinculo(res)) return res
  return res as unknown as Agenda
}

/** Carteira (alunos) do professor logado. Nunca retorna dado financeiro. */
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
