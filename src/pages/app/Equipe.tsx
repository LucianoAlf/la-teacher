import { useCallback, useEffect, useState } from 'react'
import { AppFrame } from './AppFrame'
import { Badge, Button, EmptyState, ScreenHeader, Skeleton, Toast, useToast } from '../../components/ui'
import {
  liberarAcessoProfessor,
  professoresParaLiberar,
  type ProfessorParaLiberar,
} from '../../lib/api'

/**
 * Painel da equipe — liberar o acesso dos professores.
 *
 * A ordem da lista não é alfabética: vem quem AINDA NÃO tem acesso primeiro, e
 * dentro disso a RPC devolve quantas experimentais cada um tem marcadas pros
 * próximos 7 dias. Não é enfeite — é a fila de quem ganha mais em entrar hoje.
 * Uma lista alfabética faria a coordenação liberar por acaso.
 *
 * Liberar manda WhatsApp pra uma pessoa de verdade, então o botão pede
 * confirmação. E reenviar pra quem já tem acesso é permitido de propósito:
 * "perdi a mensagem" é o pedido mais comum depois do primeiro dia.
 */
export default function EquipePage() {
  const { message, visible, show } = useToast()
  const [lista, setLista] = useState<ProfessorParaLiberar[] | null>(null)
  const [erro, setErro] = useState<string | null>(null)
  const [enviando, setEnviando] = useState<number | null>(null)
  const [confirmando, setConfirmando] = useState<ProfessorParaLiberar | null>(null)

  const carregar = useCallback(() => {
    professoresParaLiberar()
      .then(setLista)
      .catch(() => setErro('Não consegui carregar a equipe agora.'))
  }, [])

  useEffect(carregar, [carregar])

  async function liberar(p: ProfessorParaLiberar) {
    setConfirmando(null)
    setEnviando(p.professor_id)
    try {
      const r = await liberarAcessoProfessor(p.professor_id)
      if (!r.ok) {
        show(
          r.erro === 'professor_sem_whatsapp'
            ? 'Esse professor não tem WhatsApp no cadastro.'
            : r.erro === 'apenas_admin'
              ? 'Só a coordenação pode liberar acesso.'
              : 'Não consegui liberar agora. Tenta de novo.',
        )
        return
      }
      // "Liberado" sem convite é acesso que a pessoa não sabe que tem — então a
      // tela conta as duas coisas separadas, não um "pronto" genérico.
      show(
        r.convite_enviado
          ? `${p.primeiro_nome} recebeu o convite no WhatsApp.`
          : `Acesso liberado, mas o convite NÃO saiu no WhatsApp. Confere o número.`,
      )
      carregar()
    } finally {
      setEnviando(null)
    }
  }

  const semAcesso = lista?.filter((p) => !p.liberado) ?? []
  const comAcesso = lista?.filter((p) => p.liberado) ?? []

  return (
    <AppFrame>
      {/* Sem seta de voltar: pra coordenação esta É a home. O /app manda de
          volta pra cá (a agenda de lá é do professor), então uma seta faria o
          caminho voltar pra própria tela — que parece travamento. */}
      <ScreenHeader
        title="Equipe"
        subtitle={lista ? `${comAcesso.length} com acesso · ${semAcesso.length} sem` : undefined}
      />

      <div className="flex-1 space-y-3 overflow-y-auto px-4 pb-[calc(24px_+_env(safe-area-inset-bottom))]">
        {!lista && !erro && (
          <>
            <Skeleton className="h-16 w-full rounded-lg" />
            <Skeleton className="h-16 w-full rounded-lg" />
            <Skeleton className="h-16 w-full rounded-lg" />
          </>
        )}

        {erro && (
          <EmptyState icon="fa-solid fa-triangle-exclamation" title="Não deu pra abrir" description={erro} />
        )}

        {lista && semAcesso.length > 0 && (
          <>
            <p className="pt-1 text-[11.5px] font-bold uppercase tracking-[.5px] text-text-secondary">
              Ainda sem acesso
            </p>
            {semAcesso.map((p) => (
              <Linha
                key={p.professor_id}
                p={p}
                enviando={enviando === p.professor_id}
                onLiberar={() => setConfirmando(p)}
              />
            ))}
          </>
        )}

        {lista && comAcesso.length > 0 && (
          <>
            <p className="pt-3 text-[11.5px] font-bold uppercase tracking-[.5px] text-text-secondary">
              Já entram no app
            </p>
            {comAcesso.map((p) => (
              <Linha
                key={p.professor_id}
                p={p}
                enviando={enviando === p.professor_id}
                onLiberar={() => setConfirmando(p)}
              />
            ))}
          </>
        )}
      </div>

      {/* Confirmar antes: o toque manda mensagem no WhatsApp de uma pessoa. */}
      {confirmando && (
        <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/60 p-4">
          <div className="w-full max-w-[420px] rounded-lg border border-border-subtle bg-bg-surface p-4">
            <b className="block text-[15px]">
              {confirmando.liberado ? 'Reenviar convite' : 'Liberar acesso'} — {confirmando.primeiro_nome}
            </b>
            <p className="mt-2 text-[13px] leading-relaxed text-text-secondary">
              {confirmando.liberado
                ? 'Ele já tem acesso. Vou mandar o convite de novo no WhatsApp, com o link e o passo a passo de instalar.'
                : 'Vou criar o acesso e mandar o convite no WhatsApp dele agora, com o link e o passo a passo de instalar no celular.'}
            </p>
            <div className="mt-4 flex gap-2">
              <Button block onClick={() => void liberar(confirmando)}>
                <i className="fa-brands fa-whatsapp mr-2" aria-hidden="true" />
                {confirmando.liberado ? 'Reenviar' : 'Liberar e enviar'}
              </Button>
              <Button block variant="ghost" onClick={() => setConfirmando(null)}>
                Cancelar
              </Button>
            </div>
          </div>
        </div>
      )}

      <Toast message={message} visible={visible} />
    </AppFrame>
  )
}

function Linha({
  p, enviando, onLiberar,
}: { p: ProfessorParaLiberar; enviando: boolean; onLiberar: () => void }) {
  return (
    <div className="flex items-center gap-3 rounded-lg border border-border-subtle bg-bg-surface px-3 py-[11px]">
      <div className="min-w-0 flex-1">
        <b className="block truncate text-[14px]">{p.nome}</b>
        <div className="mt-[3px] flex flex-wrap items-center gap-[6px]">
          {p.experimentais_7d > 0 && (
            <Badge variant="info" icon="fa-solid fa-star">
              {p.experimentais_7d} experimental{p.experimentais_7d > 1 ? 'is' : ''} essa semana
            </Badge>
          )}
          {!p.tem_whatsapp && (
            <span className="text-[11.5px] text-warning-text">
              <i className="fa-solid fa-triangle-exclamation" aria-hidden="true" /> sem WhatsApp no cadastro
            </span>
          )}
          {p.liberado && !p.ultimo_acesso && (
            <span className="text-[11.5px] text-text-muted">liberado, ainda não entrou</span>
          )}
        </div>
      </div>
      <Button
        size="sm"
        variant={p.liberado ? 'ghost' : 'primary'}
        disabled={enviando || !p.tem_whatsapp}
        onClick={onLiberar}
      >
        {enviando ? '…' : p.liberado ? 'Reenviar' : 'Liberar'}
      </Button>
    </div>
  )
}
