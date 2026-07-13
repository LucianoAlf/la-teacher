import { useRegisterSW } from 'virtual:pwa-register/react'

/**
 * Aviso de "nova versão disponível". Com registerType:'prompt', o service worker
 * baixa a versão nova mas NÃO troca sozinho — assim o professor nunca fica num
 * app com código velho sem saber (foi o que mordeu duas vezes no piloto). Quando
 * há versão nova, `useRegisterSW` liga `needRefresh`; tocar "Atualizar" chama
 * `updateServiceWorker(true)` (troca o SW e recarrega na hora).
 */
export function AtualizacaoDisponivel() {
  const {
    needRefresh: [needRefresh, setNeedRefresh],
    updateServiceWorker,
  } = useRegisterSW()

  return (
    <BannerNovaVersao
      show={needRefresh}
      onAtualizar={() => void updateServiceWorker(true)}
      onFechar={() => setNeedRefresh(false)}
    />
  )
}

/**
 * Parte visual, isolada pra teste. Pílula fixa EMBAIXO (flutuando acima da barra
 * de navegação, na zona do polegar) — no topo virava "paisagem" e passava batido.
 */
export function BannerNovaVersao({
  show,
  onAtualizar,
  onFechar,
}: {
  show: boolean
  onAtualizar: () => void
  onFechar: () => void
}) {
  if (!show) return null
  return (
    <div
      role="status"
      className="fixed inset-x-0 bottom-[calc(88px_+_env(safe-area-inset-bottom))] z-[60] flex justify-center px-3"
    >
      <div className="flex w-full max-w-[420px] items-center gap-2 rounded-full border border-border-subtle bg-bg-surface px-[14px] py-[10px] shadow-fab">
        <i className="fa-solid fa-arrows-rotate text-[14px] text-brand-text" aria-hidden="true" />
        <span className="flex-1 text-[13px] font-semibold text-text-primary">Nova versão disponível</span>
        <button
          type="button"
          onClick={onAtualizar}
          className="rounded-full bg-brand px-[20px] py-[9px] text-[14px] font-bold text-on-brand transition-transform active:scale-95"
        >
          Atualizar
        </button>
        <button
          type="button"
          onClick={onFechar}
          aria-label="Agora não"
          className="px-1 text-text-muted"
        >
          <i className="fa-solid fa-xmark" aria-hidden="true" />
        </button>
      </div>
    </div>
  )
}
