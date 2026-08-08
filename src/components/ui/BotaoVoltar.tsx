/**
 * Botão de voltar do app — círculo de 36px com borda, seta à esquerda.
 *
 * Vivia dentro do `ScreenHeader` e foi EXTRAÍDO quando o perfil da coordenação
 * precisou de uma saída. A moldura da coordenação não usa `ScreenHeader` (o
 * nome da página já flutua no topo), e sem extrair eu tinha escrito um link de
 * texto "← Voltar pro painel" — uma segunda gramática de voltar, que não existe
 * em nenhuma outra tela do app.
 */
export function BotaoVoltar({ onClick, className }: { onClick: () => void; className?: string }) {
  return (
    <button
      type="button"
      aria-label="Voltar"
      onClick={onClick}
      className={`flex h-9 w-9 flex-none items-center justify-center rounded-full border border-border-subtle bg-bg-surface text-text-secondary transition-colors hover:bg-bg-hover ${className ?? ''}`}
    >
      <i className="fa-solid fa-arrow-left" aria-hidden="true" />
    </button>
  )
}
