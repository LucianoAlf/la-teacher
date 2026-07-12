/**
 * Fábio colorido (o avatar do login/header) — pros spots onde ele é PROTAGONISTA:
 * tela de processando, loading. É o personagem inteiro, com respiro. Substitui o
 * robô genérico: onde o app diz "o Fábio está…", aparece o Fábio de verdade.
 */
export function FabioAvatar({ className, alt }: { className?: string; alt?: string }) {
  return (
    <img
      src="/brand/fabio-avatar.svg"
      alt={alt ?? ''}
      aria-hidden={alt ? undefined : true}
      draggable={false}
      className={className}
    />
  )
}
