import { createClient } from '@supabase/supabase-js'
import type { Database } from '../types/db'

const url = import.meta.env.VITE_SUPABASE_URL
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!url || !anonKey) {
  // Falha cedo e clara em vez de erro obscuro no primeiro request.
  throw new Error(
    'Supabase não configurado: defina VITE_SUPABASE_URL e VITE_SUPABASE_ANON_KEY no .env (ver .env.example).',
  )
}

/**
 * Client único do app, tipado pelo schema do LA Report (src/types/db.ts).
 * Regra de fronteira: o cliente NUNCA faz select direto em tabela —
 * todo dado passa pelas RPCs app_* expostas em src/lib/api.ts.
 */
// Config idêntica à do LA Organizer (confirmado comparando os dois repos) —
// não é aqui que mora o bug do "pede login toda vez que reabre" (ver
// src/features/pwa/persistStorage.ts pra causa real + fix).
export const supabase = createClient<Database>(url, anonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
})
