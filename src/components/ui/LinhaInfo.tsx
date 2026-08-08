/**
 * Linha de dado só-leitura (rótulo à esquerda, valor à direita).
 *
 * Vivia inline na tela Meu perfil do professor. Foi EXTRAÍDA quando o perfil da
 * coordenação precisou da mesma lista: a minha versão tinha virado
 * `justify-between` com o rótulo em 12,5px e o valor em 13px, dizendo "não
 * informado" onde a do professor diz "—". Mesmo dado, duas caras.
 *
 * Vazio NÃO some: uma linha ausente parece campo que não existe; "—" diz que
 * existe e está em branco.
 */
export function LinhaInfo({ rotulo, valor }: { rotulo: string; valor: string | null }) {
  return (
    <div className="flex items-center gap-3 border-b border-border-subtle px-[14px] py-3 last:border-b-0">
      <span className="w-[76px] flex-none text-[12.5px] font-bold text-text-secondary">{rotulo}</span>
      <span className="min-w-0 flex-1 truncate text-sm text-text-primary">{valor || '—'}</span>
    </div>
  )
}

/** Cabeçalho de seção de uma lista de informações (caixa alta, tracking .5px). */
export function TituloSecao({ children }: { children: React.ReactNode }) {
  return (
    <div className="border-b border-border-subtle px-[14px] py-3">
      <span className="text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">
        {children}
      </span>
    </div>
  )
}
