import { supabase } from '../../lib/supabase'

/**
 * Entrar com o WhatsApp e um código de 6 dígitos.
 *
 * Sem senha de propósito: o professor já conversa com o Fábio naquele número
 * todo dia, e o código chega na mesma conversa. Senha é a primeira coisa que 44
 * pessoas esquecem numa segunda-feira — e "esqueci minha senha" por e-mail não
 * ajuda quem nem sabe qual e-mail a escola cadastrou.
 */

/** Motivos que a edge function devolve. Recusa é sempre `nao_encontrado`. */
export type MotivoRecusa =
  | 'nao_encontrado'
  | 'telefone_invalido'
  | 'muitas_tentativas'
  | 'nao_consegui_enviar'
  | 'indisponivel'
  | 'rede'

export interface PedidoAceito {
  ok: true
  /** Necessário pro segundo passo — o professor nunca vê nem digita. */
  email: string
  primeiro_nome: string
  telefone_mascarado: string
}
export type PedidoResultado = PedidoAceito | { ok: false; motivo: MotivoRecusa; espere_min?: number }

export async function pedirCodigo(telefone: string): Promise<PedidoResultado> {
  try {
    const { data, error } = await supabase.functions.invoke('professor-entrar', {
      body: { telefone: telefone.replace(/\D/g, '') },
    })
    // A function responde 200 mesmo recusando — o status HTTP não pode virar
    // mais um jeito de distinguir "não existe" de "não liberado".
    if (error && !data) return { ok: false, motivo: 'rede' }
    if (!data?.ok) return { ok: false, motivo: data?.motivo ?? 'indisponivel', espere_min: data?.espere_min }
    return data as PedidoAceito
  } catch {
    return { ok: false, motivo: 'rede' }
  }
}

export type FalhaCodigo = 'codigo_errado' | 'expirado' | 'rede'

/**
 * `type: 'email'` e não `'magiclink'`: o `admin/generate_link` devolve um
 * `email_otp`, e é esse tipo que o verifyOtp espera. Com 'magiclink' ele
 * espera o hash de um link clicado — e falha com uma mensagem que não ajuda.
 */
export async function entrarComCodigo(email: string, codigo: string): Promise<{ falha: FalhaCodigo | null }> {
  const token = codigo.replace(/\D/g, '').trim()
  if (!email || !token) return { falha: 'codigo_errado' }
  try {
    const { error } = await supabase.auth.verifyOtp({ email, token, type: 'email' })
    if (!error) return { falha: null }
    const msg = (error.message || '').toLowerCase()
    if (msg.includes('expired')) return { falha: 'expirado' }
    if (msg.includes('invalid') || msg.includes('token')) return { falha: 'codigo_errado' }
    return { falha: 'rede' }
  } catch {
    return { falha: 'rede' }
  }
}
