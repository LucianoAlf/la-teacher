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
  aula_id?: number
  data_hora_inicio?: string
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

/**
 * Confirma um registro → grava via porta única registrar_aula_fabio.
 * A RPC LANÇA exceção (sem vínculo, registro inválido etc.) — vira throw aqui.
 */
export async function confirmarRegistro(registroId: string): Promise<unknown> {
  const { data: res, error } = await supabase.rpc('app_confirmar_registro', { p_registro_id: registroId })
  if (error) throw error
  return res
}
