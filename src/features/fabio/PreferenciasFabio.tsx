import { useEffect, useState } from 'react'
import { cx } from '../../lib/cx'
import { SOMENTE_LEITURA } from '../../lib/config'
import {
  atualizarPreferenciaFabio,
  minhasPreferenciasFabio,
  type CanalPreferido,
  type PreferenciasFabio as Prefs,
} from '../../lib/api'
import { Skeleton } from '../../components/ui'

const CANAIS: { valor: CanalPreferido; rotulo: string; icone: string }[] = [
  { valor: 'app', rotulo: 'App', icone: 'fa-solid fa-mobile-screen' },
  { valor: 'whatsapp', rotulo: 'WhatsApp', icone: 'fa-brands fa-whatsapp' },
  { valor: 'ambos', rotulo: 'Ambos', icone: 'fa-solid fa-bell' },
]

/**
 * Seção "Como o Fábio te avisa" da tela de Perfil. Salva INCREMENTAL — cada
 * controle chama a RPC só com o campo que mudou (app_atualizar_preferencia_fabio),
 * com update otimista e reversão no erro. Busca independente (bônus da tela):
 * se falhar, some sem quebrar o Perfil. Só expõe canal e domingo — o resto das
 * preferências do banco fica reservado de propósito.
 */
export function PreferenciasFabio({ onToast }: { onToast: (m: string) => void }) {
  // undefined = carregando; null = deu erro (some da tela).
  const [prefs, setPrefs] = useState<Prefs | null | undefined>(undefined)
  const [salvando, setSalvando] = useState<keyof Prefs | null>(null)

  useEffect(() => {
    let vivo = true
    minhasPreferenciasFabio()
      .then((p) => vivo && setPrefs(p))
      .catch(() => vivo && setPrefs(null)) // seção é bônus — nunca quebra o Perfil
    return () => {
      vivo = false
    }
  }, [])

  if (prefs === null) return null
  if (prefs === undefined) {
    return (
      <section className="mt-3 overflow-hidden rounded-lg border border-border-subtle bg-bg-surface">
        <Cabecalho />
        <div className="space-y-3 px-[14px] py-4">
          <Skeleton className="h-9 w-full" />
          <Skeleton className="h-9 w-2/3" />
        </div>
      </section>
    )
  }

  /** Grava um campo com update otimista; reverte e avisa se o banco recusar. */
  async function salvar<K extends keyof Prefs>(campo: K, valor: Prefs[K]) {
    if (!prefs || prefs[campo] === valor) return
    if (SOMENTE_LEITURA) {
      onToast('Modo demonstração — ajuste desligado 🔒')
      return
    }
    const anterior = prefs
    setPrefs({ ...prefs, [campo]: valor })
    setSalvando(campo)
    try {
      await atualizarPreferenciaFabio({ [campo]: valor })
      onToast('Preferência salva ✓')
    } catch {
      setPrefs(anterior) // reverte pro estado real do banco
      onToast('Não consegui salvar. Tenta de novo.')
    } finally {
      setSalvando(null)
    }
  }

  return (
    <section className="mt-3 overflow-hidden rounded-lg border border-border-subtle bg-bg-surface">
      <Cabecalho />

      <div className="flex flex-col gap-5 px-[14px] py-4">
        {/* Canal — por onde o Fábio fala */}
        <div className="flex flex-col gap-[10px]">
          <span className="text-[12.5px] font-bold text-text-secondary">Onde quero receber</span>
          <div
            role="radiogroup"
            aria-label="Canal de mensagens do Fábio"
            className="flex gap-1 rounded-md border border-border-subtle bg-bg-inset p-1"
          >
            {CANAIS.map((c) => {
              const ativo = prefs.canal_preferido === c.valor
              return (
                <button
                  key={c.valor}
                  type="button"
                  role="radio"
                  aria-checked={ativo}
                  disabled={salvando === 'canal_preferido'}
                  onClick={() => void salvar('canal_preferido', c.valor)}
                  className={cx(
                    'flex flex-1 items-center justify-center gap-[6px] rounded-[6px] py-2 text-[12.5px] font-semibold transition-colors',
                    ativo
                      ? 'bg-bg-surface text-brand-text shadow-card'
                      : 'text-text-secondary active:bg-bg-hover',
                  )}
                >
                  <i className={c.icone} aria-hidden="true" />
                  {c.rotulo}
                </button>
              )
            })}
          </div>
        </div>

        {/* Domingo — lembrete no fim de semana */}
        <label className="flex cursor-pointer items-center gap-3">
          <div className="min-w-0 flex-1">
            <span className="block text-[13.5px] font-semibold text-text-primary">
              Lembretes no domingo
            </span>
            <span className="block text-[12px] text-text-secondary">
              Receber avisos do Fábio também aos domingos
            </span>
          </div>
          <Toggle
            ligado={prefs.recebe_domingo}
            aoTrocar={(v) => void salvar('recebe_domingo', v)}
            desabilitado={salvando === 'recebe_domingo'}
            rotulo="Lembretes no domingo"
          />
        </label>
      </div>
    </section>
  )
}

function Cabecalho() {
  return (
    <div className="border-b border-border-subtle px-[14px] py-3">
      <span className="text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">
        Como o Fábio te avisa
      </span>
    </div>
  )
}

/** Interruptor liga/desliga (protótipo .switch) — teal quando ligado. */
function Toggle({
  ligado,
  aoTrocar,
  desabilitado,
  rotulo,
}: {
  ligado: boolean
  aoTrocar: (v: boolean) => void
  desabilitado?: boolean
  rotulo: string
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={ligado}
      aria-label={rotulo}
      disabled={desabilitado}
      onClick={() => aoTrocar(!ligado)}
      className={cx(
        'relative h-[26px] w-[46px] flex-none rounded-full transition-colors disabled:opacity-60',
        ligado ? 'bg-brand' : 'bg-border-strong',
      )}
    >
      <span
        className={cx(
          'absolute top-[3px] h-5 w-5 rounded-full bg-bg-surface transition-transform',
          ligado ? 'translate-x-[23px]' : 'translate-x-[3px]',
        )}
      />
    </button>
  )
}
