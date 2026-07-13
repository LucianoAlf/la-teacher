import { useState, type FormEvent } from 'react'
import { Button, FabioAvatar } from '../../components/ui'
import { AppFrame } from '../../pages/app/AppFrame'
import {
  concluirOnboarding,
  confirmarMeuWhatsapp,
  ErroConfirmarWhatsapp,
  type MeuOnboarding,
} from '../../lib/api'

/**
 * Fluxo pós-login: no máximo 2 telas (a regra é "menos é mais" — o professor
 * abre isso saindo da sala). WhatsApp só aparece se precisar confirmar.
 */
export function OnboardingFlow({
  dados,
  onConcluir,
}: {
  dados: MeuOnboarding
  onConcluir: () => void
}) {
  const [passo, setPasso] = useState<'whatsapp' | 'bemvindo'>(
    dados.precisa_confirmar_whatsapp ? 'whatsapp' : 'bemvindo',
  )

  if (passo === 'whatsapp') {
    return <ConfirmarWhatsapp dados={dados} onPronto={() => setPasso('bemvindo')} />
  }
  return <BemVindo dados={dados} onConcluir={onConcluir} />
}

// Formata só pra exibir/pré-preencher (a RPC canoniza qualquer coisa).
function formatarBr(bruto: string | null): string {
  const d = (bruto ?? '').replace(/\D/g, '').replace(/^55/, '')
  if (d.length === 11) return `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`
  if (d.length === 10) return `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`
  return bruto ?? ''
}

// --- Tela 1 · Confirmar o WhatsApp -------------------------------------------
function ConfirmarWhatsapp({
  dados,
  onPronto,
}: {
  dados: MeuOnboarding
  onPronto: () => void
}) {
  const [valor, setValor] = useState(formatarBr(dados.whatsapp_sugerido))
  const [erro, setErro] = useState<string | null>(null)
  const [salvando, setSalvando] = useState(false)

  async function salvar(e: FormEvent) {
    e.preventDefault()
    setErro(null)
    setSalvando(true)
    try {
      await confirmarMeuWhatsapp(valor)
      onPronto()
    } catch (err) {
      if (err instanceof ErroConfirmarWhatsapp) {
        setErro(
          err.motivo === 'ja_usado'
            ? 'Esse número já está no cadastro de outro professor. Fala com a coordenação.'
            : 'Faltou o DDD ou o número. Confere?',
        )
      } else {
        setErro('Não consegui salvar agora. Tenta de novo.')
      }
      setSalvando(false)
    }
  }

  return (
    <AppFrame>
      <div className="flex flex-1 flex-col overflow-y-auto px-6 pt-[calc(24px_+_env(safe-area-inset-top))]">
        <div className="flex flex-1 flex-col justify-center">
          <FabioAvatar className="h-[72px] w-[72px]" alt="Fábio" />
          <h1 className="mt-5 text-[23px] font-extrabold leading-tight tracking-[-.3px]">
            Confirma teu WhatsApp, {dados.primeiro_nome}?
          </h1>
          <p className="mt-2 text-[14px] leading-relaxed text-text-secondary">
            É por aqui que eu te mando o briefing da aula e te aviso dos registros pendentes.
          </p>

          <form onSubmit={(e) => void salvar(e)} className="mt-6">
            <div className="relative">
              <i
                className="fa-brands fa-whatsapp pointer-events-none absolute left-[14px] top-1/2 -translate-y-1/2 text-[17px] text-text-muted"
                aria-hidden="true"
              />
              <input
                type="tel"
                inputMode="tel"
                autoComplete="tel"
                value={valor}
                onChange={(e) => setValor(e.target.value)}
                placeholder="(21) 99999-9999"
                aria-label="Seu número de WhatsApp"
                className="w-full rounded-md border border-border-strong bg-bg-inset py-[13px] pl-11 pr-3 text-[15px] text-text-primary placeholder:text-text-muted focus-visible:border-brand"
              />
            </div>

            {erro && (
              <p className="mt-3 flex items-start gap-2 rounded-md bg-danger-soft px-3 py-[10px] text-[13px] font-semibold text-danger-text">
                <i className="fa-solid fa-circle-exclamation mt-[2px]" aria-hidden="true" />
                <span>{erro}</span>
              </p>
            )}
          </form>
        </div>

        <div className="pb-[calc(24px_+_env(safe-area-inset-bottom))] pt-3">
          <Button block disabled={salvando} onClick={(e) => void salvar(e as unknown as FormEvent)}>
            {salvando ? (
              <>
                <i className="fa-solid fa-spinner fa-spin" aria-hidden="true" /> Confirmando…
              </>
            ) : (
              <>
                É esse <i className="fa-solid fa-arrow-right" aria-hidden="true" />
              </>
            )}
          </Button>
          <p className="mt-3 text-center text-[12px] leading-relaxed text-text-muted">
            Errado? Corrige aqui mesmo — é a chance de acertar sem ninguém caçar número.
          </p>
        </div>
      </div>
    </AppFrame>
  )
}

// --- Tela 2 · Boas-vindas com o dado dele ------------------------------------
function BemVindo({
  dados,
  onConcluir,
}: {
  dados: MeuOnboarding
  onConcluir: () => void
}) {
  const [entrando, setEntrando] = useState(false)

  async function comecar() {
    setEntrando(true)
    try {
      await concluirOnboarding()
    } catch {
      /* fail-open: mesmo se não gravar, deixa entrar (vê o onboarding de novo depois) */
    } finally {
      onConcluir()
    }
  }

  return (
    <AppFrame>
      <div className="flex flex-1 flex-col overflow-y-auto px-6 pt-[calc(24px_+_env(safe-area-inset-top))]">
        <div className="flex flex-1 flex-col justify-center">
          <FabioAvatar className="h-[80px] w-[80px] animate-bob" alt="Fábio" />
          <h1 className="mt-5 text-[24px] font-extrabold leading-tight tracking-[-.3px]">
            Prontinho, {dados.primeiro_nome}.
            <br />
            Seus {dados.meus_alunos} alunos já estão aqui.
          </h1>
          <p className="mt-2 text-[14px] leading-relaxed text-text-secondary">
            {dados.meus_cursos} {dados.meus_cursos === 1 ? 'curso' : 'cursos'}, já organizados por
            unidade. Você faz só duas coisas aqui:
          </p>

          <div className="mt-6 grid grid-cols-2 gap-3">
            <AcaoCard icon="fa-solid fa-clipboard-check" titulo="Dar chamada" legenda="quem veio, num toque" />
            <AcaoCard icon="fa-solid fa-microphone" titulo="Gravar a aula" legenda="você fala, o Fábio escreve" />
          </div>
        </div>

        <div className="pb-[calc(24px_+_env(safe-area-inset-bottom))] pt-3">
          <Button block disabled={entrando} onClick={() => void comecar()}>
            {entrando ? (
              <>
                <i className="fa-solid fa-spinner fa-spin" aria-hidden="true" /> Abrindo…
              </>
            ) : (
              <>
                Começar <i className="fa-solid fa-arrow-right" aria-hidden="true" />
              </>
            )}
          </Button>
        </div>
      </div>
    </AppFrame>
  )
}

function AcaoCard({ icon, titulo, legenda }: { icon: string; titulo: string; legenda: string }) {
  return (
    <div className="flex flex-col gap-2 rounded-lg border border-border-subtle bg-bg-surface p-4">
      <span className="flex h-10 w-10 items-center justify-center rounded-full bg-brand-soft text-[17px] text-brand-text">
        <i className={icon} aria-hidden="true" />
      </span>
      <b className="text-[14px] leading-tight text-text-primary">{titulo}</b>
      <span className="text-[12px] leading-snug text-text-secondary">{legenda}</span>
    </div>
  )
}
