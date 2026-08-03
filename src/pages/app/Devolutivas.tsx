import { useCallback, useEffect, useState } from 'react'
import { Badge, Button, Card, EmptyState, Toast, useToast } from '../../components/ui'
import {
  definirDestinatarioDevolutiva,
  devolutivasAguardando,
  devolutivasPendentes,
  marcarDevolutiva,
  salvarTextoDevolutiva,
  type AcaoDevolutiva,
  type DevolutivaAguardando,
  type DevolutivaPendente,
} from '../../lib/api'
import { AppFrame } from './AppFrame'
import { AppHeader } from './AppHeader'
import { AppNav } from './AppNav'

type Versao = 'normal' | 'apoio_casa'

/** Texto que está na tela agora: o editado pelo professor vence o do Fábio. */
function textoAtual(d: DevolutivaPendente, versao: Versao, rascunho: string | undefined): string {
  if (rascunho !== undefined) return rascunho
  if (versao === 'apoio_casa' && d.texto_apoio_casa) return d.texto_apoio_casa
  return d.texto_normal
}

function CardDevolutiva({
  devolutiva,
  onAviso,
  onSumir,
}: {
  devolutiva: DevolutivaPendente
  onAviso: (m: string) => void
  onSumir: (id: string) => void
}) {
  const [versao, setVersao] = useState<Versao>('normal')
  const [editando, setEditando] = useState(false)
  const [rascunho, setRascunho] = useState<string | undefined>(undefined)
  const [salvando, setSalvando] = useState(false)

  const texto = textoAtual(devolutiva, versao, rascunho)
  const paraQuem =
    devolutiva.destinatario === 'responsavel'
      ? devolutiva.destinatario_nome || 'o responsável'
      : devolutiva.aluno_primeiro_nome

  const carimbar = async (acao: AcaoDevolutiva) => {
    try {
      await marcarDevolutiva(devolutiva.id, acao)
    } catch {
      // O carimbo é telemetria da entrega, não a entrega. Se ele falhar, o
      // professor já copiou/compartilhou — não faz sentido bloquear a ação
      // dele nem assustar com erro. Some pro usuário, aparece no banco.
    }
  }

  const copiar = async () => {
    try {
      await navigator.clipboard.writeText(texto)
      onAviso('Copiado! É só colar no WhatsApp 📋')
      void carimbar('copiada')
    } catch {
      onAviso('Não consegui copiar aqui — segura no texto e copia na mão')
    }
  }

  const compartilhar = async () => {
    if (!navigator.share) {
      void copiar()
      return
    }
    try {
      await navigator.share({ text: texto })
      void carimbar('compartilhada')
    } catch {
      // usuário cancelou o menu de compartilhar: não é erro
    }
  }

  const salvar = async () => {
    if (rascunho === undefined) {
      setEditando(false)
      return
    }
    const limpo = rascunho.trim()
    if (!limpo) {
      onAviso('O texto não pode ficar vazio')
      return
    }
    setSalvando(true)
    try {
      await salvarTextoDevolutiva(devolutiva.id, limpo)
      onAviso('Ajuste salvo ✓')
      setEditando(false)
    } catch {
      onAviso('Não consegui salvar agora. Tenta de novo?')
    } finally {
      setSalvando(false)
    }
  }

  const jaMandei = async () => {
    try {
      await marcarDevolutiva(devolutiva.id, 'enviada')
      onSumir(devolutiva.id)
    } catch {
      onAviso('Não consegui marcar agora. Tenta de novo?')
    }
  }

  return (
    <Card
      title={devolutiva.aluno_nome}
      icon="fa-solid fa-comment-dots"
      right={devolutiva.curso ?? undefined}
    >
      <div className="space-y-[10px] px-1 py-1">
        <div className="flex flex-wrap items-center gap-2">
          <Badge variant="info" icon="fa-solid fa-arrow-right">
            para {paraQuem}
          </Badge>
          {devolutiva.editada_em && (
            <Badge variant="ok" icon="fa-solid fa-pen">
              você ajustou
            </Badge>
          )}
        </div>

        {/* As duas versões. A de apoio pede prática em casa — pedindo, nunca
            cobrando. Fica na mão do professor escolher o tom do dia. */}
        {devolutiva.texto_apoio_casa && !editando && (
          <div className="flex gap-1 rounded-md bg-bg-app p-1">
            {(
              [
                ['normal', 'Direto'],
                ['apoio_casa', 'Com prática em casa'],
              ] as [Versao, string][]
            ).map(([id, rotulo]) => (
              <button
                key={id}
                type="button"
                onClick={() => setVersao(id)}
                className={`flex-1 rounded px-2 py-[6px] text-[12.5px] font-bold ${
                  versao === id
                    ? 'bg-bg-surface text-text-primary shadow-sm'
                    : 'text-text-secondary'
                }`}
              >
                {rotulo}
              </button>
            ))}
          </div>
        )}

        {editando ? (
          <textarea
            value={texto}
            onChange={(e) => setRascunho(e.target.value)}
            rows={7}
            className="w-full rounded-md border border-border-subtle bg-bg-app p-3 text-[14px] leading-[1.5] text-text-primary"
            autoFocus
          />
        ) : (
          <p className="whitespace-pre-wrap rounded-md bg-bg-app p-3 text-[14px] leading-[1.5] text-text-primary">
            {texto}
          </p>
        )}

        {editando ? (
          <div className="flex gap-2">
            <Button size="sm" onClick={salvar} disabled={salvando}>
              <i className="fa-solid fa-check" aria-hidden="true" /> {salvando ? 'Salvando…' : 'Salvar'}
            </Button>
            <Button
              size="sm"
              variant="ghost"
              onClick={() => {
                setRascunho(undefined)
                setEditando(false)
              }}
            >
              Cancelar
            </Button>
          </div>
        ) : (
          <>
            <div className="flex flex-wrap gap-2">
              <Button size="sm" onClick={compartilhar}>
                <i className="fa-solid fa-share-nodes" aria-hidden="true" /> Compartilhar
              </Button>
              <Button size="sm" variant="ghost" onClick={copiar}>
                <i className="fa-regular fa-copy" aria-hidden="true" /> Copiar
              </Button>
              <Button size="sm" variant="ghost" onClick={() => setEditando(true)}>
                <i className="fa-solid fa-pen" aria-hidden="true" /> Ajustar
              </Button>
            </div>
            {/* Separado dos outros de propósito: é o botão que tira o card da
                tela e responde "chegou?" pra casa inteira. Não pode ser
                clicado sem querer junto com "copiar". */}
            <button
              type="button"
              onClick={jaMandei}
              className="w-full rounded-md border border-success-text px-3 py-[9px] text-[13px] font-bold text-success-text"
            >
              <i className="fa-solid fa-paper-plane" aria-hidden="true" /> Já mandei
            </button>
          </>
        )}
      </div>
    </Card>
  )
}

/**
 * Card de quem ficou travada esperando decisão.
 *
 * O Fábio decide o destinatário pela idade — abaixo de 15 fala com o
 * responsável, acima com o aluno. Quando a idade cadastrada é impossível ele
 * NÃO chuta: para e pergunta. Sem esta tela a devolutiva ficaria presa pra
 * sempre, em silêncio, até expirar em 7 dias.
 */
function CardAguardando({
  devolutiva,
  onAviso,
  onDecidiu,
}: {
  devolutiva: DevolutivaAguardando
  onAviso: (m: string) => void
  onDecidiu: (id: string) => void
}) {
  const [enviando, setEnviando] = useState(false)

  const decidir = async (destinatario: 'responsavel' | 'aluno') => {
    setEnviando(true)
    try {
      await definirDestinatarioDevolutiva(devolutiva.id, destinatario)
      onDecidiu(devolutiva.id)
    } catch {
      onAviso('Não consegui registrar agora. Tenta de novo?')
      setEnviando(false)
    }
  }

  return (
    <Card
      title={devolutiva.aluno_nome}
      icon="fa-solid fa-circle-question"
      right={devolutiva.curso ?? undefined}
    >
      <div className="space-y-[10px] px-1 py-1">
        <Badge variant="warn" icon="fa-solid fa-clock">
          esperando você decidir
        </Badge>
        <p className="text-[13px] text-text-secondary">
          Escrevi a devolutiva, mas não consegui saber para quem mandar
          {devolutiva.idade_cadastrada !== null
            ? ` — o cadastro diz ${devolutiva.idade_cadastrada} ano(s), e isso não parece certo`
            : ''}
          . Manda para quem?
        </p>
        <div className="flex gap-2">
          <button
            type="button"
            disabled={enviando}
            onClick={() => decidir('responsavel')}
            className="flex-1 rounded-md border border-brand-text px-3 py-[9px] text-[13px] font-bold text-brand-text disabled:opacity-50"
          >
            <i className="fa-solid fa-user-shield" aria-hidden="true" />{' '}
            {devolutiva.responsavel_nome
              ? `Para ${devolutiva.responsavel_nome.split(' ')[0]}`
              : 'Para o responsável'}
          </button>
          <button
            type="button"
            disabled={enviando}
            onClick={() => decidir('aluno')}
            className="flex-1 rounded-md border border-border-subtle px-3 py-[9px] text-[13px] font-bold text-text-primary disabled:opacity-50"
          >
            <i className="fa-solid fa-user" aria-hidden="true" /> Para{' '}
            {devolutiva.aluno_primeiro_nome}
          </button>
        </div>
        <p className="text-[11.5px] text-text-muted">
          Eu reescrevo o texto para quem vai ler — muda o jeito de falar.
        </p>
      </div>
    </Card>
  )
}

/** /app/devolutivas — o que o Fábio escreveu, pro professor conferir e mandar. */
export default function DevolutivasPage() {
  const { message, visible, show } = useToast()
  const [itens, setItens] = useState<DevolutivaPendente[] | null>(null)
  const [aguardando, setAguardando] = useState<DevolutivaAguardando[]>([])
  const [erro, setErro] = useState(false)

  const carregar = useCallback(async () => {
    setErro(false)
    try {
      const [pendentes, travadas] = await Promise.all([
        devolutivasPendentes(),
        devolutivasAguardando(),
      ])
      setItens(pendentes)
      setAguardando(travadas)
    } catch {
      setErro(true)
      setItens([])
    }
  }, [])

  useEffect(() => {
    void carregar()
  }, [carregar])

  const sumir = (id: string) => {
    setItens((atual) => (atual ?? []).filter((d) => d.id !== id))
    show('Boa! Devolutiva entregue 🎵')
  }

  return (
    <AppFrame>
      <AppHeader />

      <div className="flex-1 space-y-3 overflow-y-auto px-4 pb-[calc(96px_+_env(safe-area-inset-bottom))] pt-2">
        <div>
          <h1 className="text-[17px] font-bold text-text-primary">Devolutivas</h1>
          <p className="text-[13px] text-text-secondary">
            Eu escrevi a partir do seu registro. Confere, ajusta se quiser — quem manda é você.
          </p>
        </div>

        {itens === null && (
          <p className="py-8 text-center text-[13px] text-text-secondary">Carregando…</p>
        )}

        {/* Primeiro o que depende de uma decisão dele: está bloqueando a
            devolutiva de sair, e expira em 7 dias se ninguém responder. */}
        {aguardando.map((d) => (
          <CardAguardando
            key={d.id}
            devolutiva={d}
            onAviso={show}
            onDecidiu={(id) => {
              setAguardando((atual) => atual.filter((x) => x.id !== id))
              show('Beleza! Vou reescrever para quem vai ler 🎵')
            }}
          />
        ))}

        {erro && (
          <Card title="Não consegui carregar" icon="fa-solid fa-triangle-exclamation">
            <div className="p-3">
              <Button size="sm" variant="ghost" onClick={() => void carregar()}>
                Tentar de novo
              </Button>
            </div>
          </Card>
        )}

        {itens !== null && !erro && itens.length === 0 && aguardando.length === 0 && (
          <Card title="Devolutivas" icon="fa-solid fa-comment-dots">
            <EmptyState
              icon="fa-solid fa-mug-hot"
              title="Nada pendente 🎉"
              description="Quando você registrar uma aula, eu escrevo a devolutiva e ela aparece aqui pra você conferir."
            />
          </Card>
        )}

        {(itens ?? []).map((d) => (
          <CardDevolutiva key={d.id} devolutiva={d} onAviso={show} onSumir={sumir} />
        ))}
      </div>

      <AppNav onMais={() => show('Mais ferramentas chegam em breve 🧰')} />
      <Toast message={message} visible={visible} />
    </AppFrame>
  )
}
