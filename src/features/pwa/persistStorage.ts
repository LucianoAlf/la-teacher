/**
 * Bug do Matheus (piloto, 13/07): o app pedia login TODA vez que reabria —
 * o LA Organizer, no mesmo iPhone/iOS, mantinha a sessão. Comparação 1:1 com o
 * repo do Organizer descartou duas causas: (1) config do cliente Supabase —
 * idêntica (persistSession/autoRefreshToken/detectSessionInUrl); (2) manifest
 * servido com Content-Type errado — confirmado correto em produção.
 *
 * O dado que sobrou (auth.refresh_tokens do Matheus): a esmagadora maioria das
 * entradas é LOGIN NOVO (parent null), quase nenhuma é renovação de sessão
 * (parent preenchido) — ou seja, o localStorage não está sobrevivendo entre
 * reaberturas do PWA, não é só o token expirando no tempo normal.
 *
 * Causa mais provável: iOS/Safari evita guardar dados de origem com "baixo
 * engajamento" sob pressão de armazenamento — o LA Teacher foi instalado hoje;
 * o Organizer é usado todo dia há meses. `navigator.storage.persist()` pede ao
 * navegador pra NÃO descartar o storage desta origem (localStorage incluso).
 * Suportado no Safari iOS 15.2+; em navegadores sem suporte, é no-op seguro.
 */
export function pedirArmazenamentoPersistente(): void {
  if (!navigator.storage?.persist) return
  void navigator.storage.persist()
}
