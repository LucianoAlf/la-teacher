import { supabase } from '../../lib/supabase'

/**
 * Chat do Fábio — dual-channel: app e WhatsApp espelhados na MESMA conversa
 * (fabio_chat_mensagens). Aqui é acesso direto à tabela, EXCEÇÃO consciente à
 * regra "só RPC app_*" de src/lib/api.ts: o Realtime só assina TABELA
 * (postgres_changes), não RPC — e é ele que empurra a resposta do Fábio sem
 * polling. A segurança continua no banco, pelo mesmo mecanismo das RPCs:
 * RLS com fn_professor_do_usuario() — select só das próprias mensagens,
 * insert só com role='professor' e channel='app'.
 */

export interface ChatMensagem {
  id: string
  professor_id: number
  role: 'professor' | 'fabio'
  kind: 'text' | 'image' | 'audio'
  content: string | null
  media_url: string | null
  /** 'whatsapp' = mensagem que também está no celular do professor. */
  channel: 'app' | 'whatsapp'
  criado_em: string
}

// As colunas role/kind/channel são TEXT no banco (não enums), então o tipo
// gerado as marca como `string`. O app trabalha com uniões mais estreitas
// (ChatMensagem) — o cast na fronteira estreita esse texto, contrato garantido
// pelos DEFAULTs/CHECKs da tabela.

/** Histórico completo da conversa do professor, mais antigas primeiro. */
export async function carregarMensagens(professorId: number): Promise<ChatMensagem[]> {
  const { data, error } = await supabase
    .from('fabio_chat_mensagens')
    .select('*')
    .eq('professor_id', professorId)
    .order('criado_em', { ascending: true })
  if (error) throw error
  return (data ?? []) as ChatMensagem[]
}

/**
 * Envia uma mensagem do professor (insert direto; channel/kind têm DEFAULT
 * 'app'/'text' no banco). Devolve a linha gravada — o id serve pra deduplicar
 * quando o Realtime ecoar o próprio insert.
 */
export async function enviarMensagem(professorId: number, texto: string): Promise<ChatMensagem> {
  const { data, error } = await supabase
    .from('fabio_chat_mensagens')
    .insert({ professor_id: professorId, role: 'professor', content: texto })
    .select('*')
    .single()
  if (error || !data) throw error ?? new Error('insert_sem_retorno')
  return data as ChatMensagem
}

/**
 * Assina INSERTs da conversa via Realtime (o Postgres empurra a resposta do
 * Fábio — nada de polling). Devolve a função de cancelamento pro cleanup.
 */
export function assinarMensagens(
  professorId: number,
  onNova: (m: ChatMensagem) => void,
): () => void {
  const canal = supabase
    .channel(`fabio-chat-${professorId}`)
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'fabio_chat_mensagens',
        filter: `professor_id=eq.${professorId}`,
      },
      (payload) => onNova(payload.new as ChatMensagem),
    )
    .subscribe()
  return () => {
    void supabase.removeChannel(canal)
  }
}
