import { useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { AppFrame } from './AppFrame'
import { Button, Card, EmptyState, ScreenHeader, Skeleton, Toast, useToast } from '../../components/ui'
import { BlocoInterno } from '../../features/experimental/BlocoInterno'
import { useExperimental } from '../../features/experimental/useExperimental'
import { confirmarRegistroExperimental, type ResultadoConfirmacao } from '../../lib/api'

/**
 * Confirmar é um ATO, não um botão.
 *
 * Ele dispara três coisas de uma vez, e uma delas manda mensagem pra outra
 * pessoa. Então a tela diz o que VAI acontecer antes de acontecer, com o nome
 * de quem recebe — não "o comercial".
 *
 * Depois, ela mostra o que ACONTECEU. Se o aviso não saiu porque a unidade não
 * tem comercial cadastrado, isso aparece: fingir que enviou seria pior que o
 * problema.
 */
export default function ExperimentalConfirmarPage() {
  const { vinculoId } = useParams<{ vinculoId: string }>()
  const navigate = useNavigate()
  const { estado, recarregar } = useExperimental(vinculoId ? Number(vinculoId) : null)
  const { message, visible, show } = useToast()
  const [enviando, setEnviando] = useState(false)
  const [feito, setFeito] = useState<ResultadoConfirmacao | null>(null)

  if (estado.fase === 'carregando') {
    return (
      <AppFrame>
        <ScreenHeader title="Confere antes de enviar" onBack={() => navigate(-1)} />
        <div className="space-y-3 px-4">
          <Skeleton className="h-28 w-full rounded-lg" />
          <Skeleton className="h-24 w-full rounded-lg" />
        </div>
      </AppFrame>
    )
  }

  if (estado.fase === 'erro') {
    return (
      <AppFrame>
        <ScreenHeader title="Confere antes de enviar" onBack={() => navigate(-1)} />
        <EmptyState
          icon="fa-solid fa-circle-exclamation"
          title="Não deu pra abrir"
          description={estado.mensagem}
        />
      </AppFrame>
    )
  }

  const dados = estado.dados
  const reg = dados.registro

  if (!reg) {
    return (
      <AppFrame>
        <ScreenHeader title="Confere antes de enviar" onBack={() => navigate(-1)} />
        <EmptyState
          icon="fa-solid fa-pen"
          title="Ainda não há o que confirmar"
          description="Escreve o registro da aula primeiro — depois você confere aqui e envia."
          action={
            <Button onClick={() => navigate(`/app/experimental/${dados.vinculo_id}/registrar`)}>
              Escrever o registro
            </Button>
          }
        />
      </AppFrame>
    )
  }

  async function confirmar() {
    if (enviando || !reg) return
    setEnviando(true)
    try {
      const r = await confirmarRegistroExperimental(reg.id)
      setFeito(r)
      recarregar()
    } catch (e: unknown) {
      const msg = String((e as { message?: string })?.message ?? e)
      show(
        msg.includes('aula_de_outro_professor')
          ? 'Essa aula não é da sua agenda.'
          : msg.includes('registro_descartado')
            ? 'Este registro foi substituído por outro. Abre de novo pra ver o atual.'
            : 'Não consegui enviar agora. Nada foi gravado — pode tentar de novo.',
      )
      setEnviando(false)
    }
  }

  // ── Depois de confirmar: o que ACONTECEU ─────────────────────────────────
  if (feito) {
    const semDestinatario = feito.aviso_motivo === 'sem_destinatario'
    return (
      <AppFrame>
        <ScreenHeader title="Pronto" subtitle={dados.nome_aluno} />
        <div className="flex-1 space-y-3 overflow-y-auto px-4">
          <Card title="O que aconteceu" icon="fa-solid fa-check">
            <ul className="space-y-[9px] text-[13.5px] text-text-primary">
              <Item ok>presença da {primeiroNome(dados.nome_aluno)} registrada</Item>
              <Item ok>a aula entrou no prontuário dela</Item>
              {semDestinatario ? (
                <Item ok={false}>
                  o comercial desta unidade ainda não está cadastrado — a devolutiva ficou
                  guardada e sai sozinha quando cadastrarem
                </Item>
              ) : (
                <Item ok>a devolutiva foi pro comercial da unidade</Item>
              )}
            </ul>
          </Card>
          <Button onClick={() => navigate('/app/agenda')}>Voltar pra agenda</Button>
        </div>
        <Toast message={message} visible={visible} />
      </AppFrame>
    )
  }

  // ── Antes: o que VAI acontecer ───────────────────────────────────────────
  return (
    <AppFrame>
      <ScreenHeader
        title="Confere antes de enviar"
        subtitle={`${dados.nome_aluno} · ${dados.hora}`}
        onBack={() => navigate(-1)}
      />

      <div className="flex-1 space-y-3 overflow-y-auto px-4 pb-[calc(24px_+_env(safe-area-inset-bottom))]">
        <Card title="Ao confirmar, acontece isto" icon="fa-solid fa-bolt">
          <ul className="space-y-[9px] text-[13.5px] text-text-primary">
            <Item ok>presença da {primeiroNome(dados.nome_aluno)} fica registrada</Item>
            <Item ok>a aula entra no prontuário dela</Item>
            <Item ok>o comercial da unidade recebe a devolutiva no WhatsApp</Item>
          </ul>
        </Card>

        {(reg.devolutiva_familia || reg.proximos_passos) && (
          <Card title="A família pode receber" icon="fa-solid fa-people-roof">
            {reg.devolutiva_familia && (
              <p className="text-[13.5px] leading-relaxed text-text-primary">
                {reg.devolutiva_familia}
              </p>
            )}
            {reg.proximos_passos && (
              <p className="mt-[9px] text-[13.5px] leading-relaxed text-text-primary">
                {reg.proximos_passos}
              </p>
            )}
          </Card>
        )}

        {reg.leitura_de_conversao && (
          <BlocoInterno titulo="Só a escola vê">
            <p className="text-[13.5px] leading-relaxed text-text-primary">
              {reg.leitura_de_conversao}
            </p>
          </BlocoInterno>
        )}

        <div className="space-y-2 pt-1">
          <Button onClick={confirmar} disabled={enviando}>
            {enviando ? 'Enviando…' : 'Confirmar e enviar'}
          </Button>
          <Button
            variant="ghost"
            onClick={() => navigate(`/app/experimental/${dados.vinculo_id}/registrar`)}
          >
            Voltar e ajustar
          </Button>
        </div>
      </div>

      <Toast message={message} visible={visible} />
    </AppFrame>
  )
}

function Item({ ok, children }: { ok: boolean; children: React.ReactNode }) {
  return (
    <li className="flex gap-[10px]">
      <i
        className={
          ok
            ? 'fa-solid fa-check mt-[3px] flex-none text-success-text'
            : 'fa-solid fa-clock mt-[3px] flex-none text-warning-text'
        }
        aria-hidden="true"
      />
      <span className={ok ? undefined : 'text-warning-text'}>{children}</span>
    </li>
  )
}

function primeiroNome(nome: string): string {
  return nome.trim().split(/\s+/)[0] ?? nome
}
