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

type ErroPg = { message?: string } | null

// Tabela criada DEPOIS da última geração de src/types/db.ts — ainda não está
// no union tipado do client (mesmo caso do rpcSolta em api.ts). Cast pontual
// com o contrato conferido no banco; remover quando o db.ts for regenerado.
interface TabelaChat {
  select: (cols: '*') => {
    eq: (col: 'professor_id', v: number) => {
      order: (
        col: 'criado_em',
        opts: { ascending: boolean },
      ) => PromiseLike<{ data: ChatMensagem[] | null; error: ErroPg }>
    }
  }
  insert: (row: { professor_id: number; role: 'professor'; content: string }) => {
    select: (cols: '*') => {
      single: () => PromiseLike<{ data: ChatMensagem | null; error: ErroPg }>
    }
  }
}
const tabelaChat = supabase.from.bind(supabase) as unknown as (
  t: 'fabio_chat_mensagens',
) => TabelaChat

/** Histórico completo da conversa do professor, mais antigas primeiro. */
export async function carregarMensagens(professorId: number): Promise<ChatMensagem[]> {
  const { data, error } = await tabelaChat('fabio_chat_mensagens')
    .select('*')
    .eq('professor_id', professorId)
    .order('criado_em', { ascending: true })
  if (error) throw error
  return data ?? []
}

/**
 * Envia uma mensagem do professor (insert direto; channel/kind têm DEFAULT
 * 'app'/'text' no banco). Devolve a linha gravada — o id serve pra deduplicar
 * quando o Realtime ecoar o próprio insert.
 */
export async function enviarMensagem(professorId: number, texto: string): Promise<ChatMensagem> {
  const { data, error } = await tabelaChat('fabio_chat_mensagens')
    .insert({ professor_id: professorId, role: 'professor', content: texto })
    .select('*')
    .single()
  if (error || !data) throw error ?? new Error('insert_sem_retorno')
  return data
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
