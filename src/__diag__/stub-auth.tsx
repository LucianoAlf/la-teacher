// Dublê de sessão para o harness de diagnóstico. Nenhuma credencial real.
export function useAuth() {
  return { session: { user: { id: 'diag-user-0000' } } } as never
}
export function AuthProvider({ children }: { children: React.ReactNode }) {
  return <>{children}</>
}
