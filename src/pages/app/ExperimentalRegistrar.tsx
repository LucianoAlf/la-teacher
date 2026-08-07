import { useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { AppFrame } from './AppFrame'
import { Button, Card, EmptyState, ScreenHeader, Skeleton, Toast, useToast } from '../../components/ui'
import { BlocoInterno } from '../../features/experimental/BlocoInterno'
import { useExperimental } from '../../features/experimental/useExperimental'
import { registrarExperimental } from '../../lib/api'

/**
 * Registrar a experimental.
 *
 * Os quatro campos NÃO são iguais, e a tela diz isso: cada um traz escrito
 * quem vai ler. Dois podem chegar na família, um fica no prontuário, e o
 * quarto é comercial — esse mora em bloco próprio (BlocoInterno).
 *
 * Salvar aqui NÃO dispara nada: o registro nasce 'aguardando_confirmacao'. É
 * a tela seguinte que confirma, porque confirmar manda mensagem pra outra
 * pessoa e isso não pode acontecer no meio de uma digitação.
 */
export default function ExperimentalRegistrarPage() {
  const { vinculoId } = useParams<{ vinculoId: string }>()
  const navigate = useNavigate()
  const { estado } = useExperimental(vinculoId ? Number(vinculoId) : null)
  const { message, visible, show } = useToast()

  const [pedagogica, setPedagogica] = useState('')
  const [familia, setFamilia] = useState('')
  const [proximos, setProximos] = useState('')
  const [conversao, setConversao] = useState('')
  const [salvando, setSalvando] = useState(false)

  // Reabre o que ele já tinha escrito — perder texto digitado depois de uma
  // aula é o jeito mais rápido de ninguém mais registrar nada.
  useEffect(() => {
    if (estado.fase !== 'pronto') return
    const r = estado.dados.registro
    if (!r) return
    setPedagogica(r.anotacao_pedagogica ?? '')
    setFamilia(r.devolutiva_familia ?? '')
    setProximos(r.proximos_passos ?? '')
    setConversao(r.leitura_de_conversao ?? '')
  }, [estado])

  if (estado.fase === 'carregando') {
    return (
      <AppFrame>
        <ScreenHeader title="Registrar" onBack={() => navigate(-1)} />
        <div className="space-y-3 px-4">
          <Skeleton className="h-24 w-full rounded-lg" />
          <Skeleton className="h-24 w-full rounded-lg" />
        </div>
      </AppFrame>
    )
  }

  if (estado.fase === 'erro') {
    return (
      <AppFrame>
        <ScreenHeader title="Registrar" onBack={() => navigate(-1)} />
        <EmptyState
          icon="fa-solid fa-circle-exclamation"
          title="Não deu pra abrir"
          description={estado.mensagem}
        />
      </AppFrame>
    )
  }

  const dados = estado.dados
  const jaConfirmado = dados.registro?.status === 'confirmado'
  const podeSalvar = pedagogica.trim().length > 0 || familia.trim().length > 0

  async function salvar() {
    if (salvando) return
    setSalvando(true)
    try {
      await registrarExperimental({
        vinculoId: dados.vinculo_id,
        anotacaoPedagogica: pedagogica.trim(),
        devolutivaFamilia: familia.trim(),
        proximosPassos: proximos.trim(),
        leituraDeConversao: conversao.trim(),
      })
      navigate(`/app/experimental/${dados.vinculo_id}/confirmar`)
    } catch (e: unknown) {
      const msg = String((e as { message?: string })?.message ?? e)
      show(
        msg.includes('aula_de_outro_professor')
          ? 'Essa aula não é da sua agenda.'
          : msg.includes('experimental_faltou') || msg.includes('estado')
            ? 'Essa experimental não está num estado que aceita registro.'
            : 'Não consegui salvar agora. Tenta de novo.',
      )
      setSalvando(false)
    }
  }

  return (
    <AppFrame>
      <ScreenHeader
        title="Registrar experimental"
        subtitle={`${dados.nome_aluno} · ${dados.hora}`}
        onBack={() => navigate(-1)}
      />

      <div className="flex-1 space-y-3 overflow-y-auto px-4 pb-[calc(24px_+_env(safe-area-inset-bottom))]">
        {jaConfirmado && (
          <Card title="Já confirmada" icon="fa-solid fa-check">
            <p className="text-[13.5px] leading-relaxed text-text-secondary">
              Esta aula já foi registrada e a devolutiva já saiu pro comercial. Se você salvar de
              novo, o texto anterior é substituído — e o comercial recebe um aviso de correção.
            </p>
          </Card>
        )}

        <CampoTexto
          rotulo="Como foi a aula"
          quem="vai pro prontuário do aluno"
          valor={pedagogica}
          onChange={setPedagogica}
          placeholder="O que vocês trabalharam, como ele respondeu…"
        />

        <CampoTexto
          rotulo="O que contar pra família"
          quem="pode ser repassado"
          valor={familia}
          onChange={setFamilia}
          placeholder="O que a mãe/o pai vai gostar de ouvir e é verdade."
        />

        <CampoTexto
          rotulo="Próximos passos"
          quem="pode ser repassado"
          valor={proximos}
          onChange={setProximos}
          placeholder="Por onde começar se ele continuar."
        />

        <BlocoInterno titulo="Leitura de conversão">
          <textarea
            className="min-h-[88px] w-full resize-y rounded-md border border-border-strong bg-bg-inset px-3 py-2 text-[13.5px] leading-relaxed text-text-primary outline-none placeholder:text-text-muted focus:ring-2 focus:ring-brand"
            value={conversao}
            onChange={(e) => setConversao(e.target.value)}
            placeholder="O que você sentiu sobre a decisão da família."
            aria-label="Leitura de conversão — uso interno"
          />
        </BlocoInterno>

        <div className="pt-1">
          <Button onClick={salvar} disabled={!podeSalvar || salvando}>
            {salvando ? 'Salvando…' : 'Revisar antes de enviar'}
          </Button>
          <p className="mt-2 text-center text-[11.5px] text-text-muted">
            Salvar aqui não envia nada. Você confere na próxima tela.
          </p>
        </div>
      </div>

      <Toast message={message} visible={visible} />
    </AppFrame>
  )
}

/** Campo com o DESTINATÁRIO escrito no rótulo — a fronteira precisa ser lida,
 *  não deduzida. */
function CampoTexto({
  rotulo,
  quem,
  valor,
  onChange,
  placeholder,
}: {
  rotulo: string
  quem: string
  valor: string
  onChange: (v: string) => void
  placeholder: string
}) {
  return (
    <label className="block">
      <span className="mb-[6px] block text-[11.5px] font-bold uppercase tracking-[.5px] text-text-secondary">
        {rotulo}{' '}
        <span className="font-medium normal-case tracking-normal text-text-muted">· {quem}</span>
      </span>
      <textarea
        className="min-h-[88px] w-full resize-y rounded-md border border-border-strong bg-bg-inset px-3 py-2 text-[13.5px] leading-relaxed text-text-primary outline-none placeholder:text-text-muted focus:ring-2 focus:ring-brand"
        value={valor}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
      />
    </label>
  )
}
