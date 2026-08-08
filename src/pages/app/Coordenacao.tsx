import { useCallback, useEffect, useState } from 'react'
import { CoordenacaoFrame } from './CoordenacaoFrame'
import { EmptyState, Skeleton, Toast, useToast } from '../../components/ui'
import {
  coordenacaoEmAberto,
  coordenacaoRecado,
  type CoordenacaoEmAberto,
  type CoordenacaoLinha,
} from '../../lib/api'

/** Atraso a partir do qual o caso vira "não pode esperar" (plantão do celular). */
const ATRASO_URGENTE = 3
/** Teto do plantão. Lista de plantão que rola deixa de ser plantão. */
const TETO_PLANTAO = 8

const HOJE = new Intl.DateTimeFormat('pt-BR', {
  weekday: 'short',
  day: 'numeric',
  month: 'long',
}).format(new Date())

/**
 * Painel da coordenação — bloco 1: quem está com lançamento em aberto.
 *
 * A fila vem ordenada por urgência DA RPC (065) e não se reordena aqui. Isso não
 * é detalhe: o painel de equipe já foi ao ar com a tela escrevendo "por urgência"
 * em cima de uma lista alfabética, e ninguém percebeu — lista ordenada errado
 * parece lista ordenada.
 *
 * Desktop e celular mostram COISAS DIFERENTES do mesmo dado, de propósito. No
 * computador a coordenação varre a lista inteira; no celular ela está andando
 * pela escola e só quer o que não pode esperar. Espremer a tabela de cinco
 * colunas em 375px daria rolagem lateral, que é o jeito mais rápido de alguém
 * parar de abrir o painel.
 */
export default function CoordenacaoPage() {
  const { message, visible, show } = useToast()
  const [dados, setDados] = useState<CoordenacaoEmAberto | null>(null)
  const [erro, setErro] = useState<string | null>(null)

  const carregar = useCallback(() => {
    setErro(null)
    coordenacaoEmAberto(7, null)
      .then(setDados)
      .catch((e: unknown) => {
        const msg = String((e as { message?: string })?.message ?? e)
        setErro(
          msg.includes('apenas_admin')
            ? 'Essa área é da coordenação.'
            : 'Não consegui carregar o painel agora.',
        )
      })
  }, [])

  useEffect(carregar, [carregar])

  const r = dados?.resumo
  const fila = dados?.professores ?? []
  const plantao = fila.filter((p) => p.pior_atraso >= ATRASO_URGENTE).slice(0, TETO_PLANTAO)

  return (
    <CoordenacaoFrame
      titulo="Coordenação"
      acaoTopo={<span className="text-[11.5px] text-text-muted">{HOJE}</span>}
    >
      <div className="p-4">
        {erro ? (
          <EmptyState icon="fa-solid fa-triangle-exclamation" title={erro} description="Recarrega a página e tenta de novo." />
        ) : (
          <>
            <div className="mb-3.5 grid grid-cols-2 gap-2.5 md:grid-cols-4">
              <Numero rotulo="Sem lançamento · 7 dias" valor={r?.sem_lancamento} tom="perigo" carregando={!dados} />
              <Numero
                rotulo="Professores afetados"
                valor={r?.professores}
                sufixo={r ? ` de ${r.professores_ativos}` : undefined}
                carregando={!dados}
              />
              <Numero rotulo="Só de ontem" valor={r?.ontem} tom="atencao" carregando={!dados} />
              <Numero rotulo="Na fila" valor={dados ? fila.length : undefined} carregando={!dados} />
            </div>

            {/* ── Desktop: a lista inteira ───────────────────────────────── */}
            <div className="hidden overflow-hidden rounded-md border border-border-subtle bg-bg-surface md:block">
              <div className="flex items-center justify-between border-b border-border-subtle px-3.5 py-2.5">
                <span className="text-[12.5px] font-medium text-text-primary">Quem está em aberto</span>
                <span className="text-[11px] text-text-muted">ordenado por urgência</span>
              </div>

              {!dados ? (
                <div className="space-y-2 p-3.5">
                  <Skeleton className="h-8 w-full" />
                  <Skeleton className="h-8 w-full" />
                  <Skeleton className="h-8 w-full" />
                </div>
              ) : fila.length === 0 ? (
                <div className="px-3.5 py-8 text-center text-[13px] text-text-secondary">
                  Ninguém com lançamento em aberto nos últimos 7 dias.
                </div>
              ) : (
                <table className="w-full table-fixed border-collapse text-[12px]">
                  <thead>
                    <tr className="text-[10px] text-text-secondary">
                      <th className="w-[36%] px-3.5 py-[7px] text-left font-normal">PROFESSOR</th>
                      <th className="w-[14%] px-1 py-[7px] text-right font-normal">EM ABERTO</th>
                      <th className="w-[11%] px-1 py-[7px] text-right font-normal">ALUNOS</th>
                      <th className="w-[11%] px-1 py-[7px] text-right font-normal">ATRASO</th>
                      <th className="w-[28%] px-3.5 py-[7px] text-right font-normal">AÇÃO</th>
                    </tr>
                  </thead>
                  <tbody>
                    {fila.map((p) => (
                      <tr key={p.professor_id} className="border-t border-border-subtle">
                        <td className="px-3.5 py-2.5">
                          <div className="truncate text-text-primary">{p.professor_nome}</div>
                          <div className="text-[10px] text-text-muted">{p.unidades}</div>
                        </td>
                        <td className="px-1 py-2.5 text-right font-medium text-danger-text">{p.em_aberto}</td>
                        <td className="px-1 py-2.5 text-right text-text-secondary">{p.alunos}</td>
                        <td
                          className={`px-1 py-2.5 text-right ${
                            p.pior_atraso >= ATRASO_URGENTE
                              ? 'font-medium text-danger-text'
                              : 'text-text-secondary'
                          }`}
                        >
                          {p.pior_atraso}d
                        </td>
                        <td className="px-3.5 py-2.5 text-right">
                          <BotaoRecado professor={p} aviso={show} />
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </div>

            {/* ── Celular: só o que pede decisão agora ───────────────────── */}
            <div className="md:hidden">
              <p className="mb-2 text-[13px] font-medium text-text-primary">Precisa de decisão agora</p>

              {!dados ? (
                <div className="space-y-2">
                  <Skeleton className="h-20 w-full" />
                  <Skeleton className="h-20 w-full" />
                </div>
              ) : plantao.length === 0 ? (
                <p className="text-[13px] text-text-secondary">
                  Nada atrasado há {ATRASO_URGENTE} dias ou mais. O painel completo está no
                  computador.
                </p>
              ) : (
                <>
                  {plantao.map((p) => (
                    <div
                      key={p.professor_id}
                      className="mb-2 rounded-md border border-border-subtle bg-bg-surface p-3"
                    >
                      <p className="text-[14px] text-text-primary">{p.professor_nome}</p>
                      <p className="text-[12px] text-text-secondary">
                        {p.em_aberto} em aberto · {p.pior_atraso} dias · {p.unidades}
                      </p>
                      <div className="mt-2">
                        <BotaoRecado professor={p} aviso={show} />
                      </div>
                    </div>
                  ))}
                  {/* Diz o que ficou de fora em vez de fingir que a lista é essa. */}
                  {fila.length > plantao.length ? (
                    <p className="mt-3 text-center text-[11.5px] text-text-muted">
                      mais {fila.length - plantao.length} com menos de {ATRASO_URGENTE} dias — no
                      computador aparece a lista toda
                    </p>
                  ) : null}
                </>
              )}
            </div>
          </>
        )}
      </div>

      <Toast message={message} visible={visible} />
    </CoordenacaoFrame>
  )
}

function Numero({
  rotulo,
  valor,
  sufixo,
  tom,
  carregando,
}: {
  rotulo: string
  valor?: number
  sufixo?: string
  tom?: 'perigo' | 'atencao'
  carregando?: boolean
}) {
  const cor =
    tom === 'perigo' ? 'text-danger-text' : tom === 'atencao' ? 'text-warning-text' : 'text-text-primary'
  return (
    <div className="rounded-md bg-bg-surface p-3">
      <p className="mb-1 text-[10.5px] text-text-secondary">{rotulo}</p>
      {carregando ? (
        <Skeleton className="h-7 w-16" />
      ) : (
        <p className={`text-[23px] font-medium leading-tight ${cor}`}>
          {valor ?? '—'}
          {sufixo ? <span className="text-[12px] text-text-muted">{sufixo}</span> : null}
        </p>
      )}
    </div>
  )
}

type EstadoRecado = 'parado' | 'enviando' | 'enviado' | 'ja_cobrado' | 'pausa' | 'erro'

/**
 * O botão nunca diz "enviado" antes do banco confirmar. E cada recusa tem texto
 * PRÓPRIO: "já cobrado hoje" e "professor de férias" são situações diferentes, e
 * as duas viram um "não deu" genérico se a tela não separar.
 *
 * Cobrança não tem janela de silêncio: `fn_fabio_pode_notificar` dá bypass
 * estrutural pra categoria `governanca` — só férias (`pausa_ate`) barra.
 */
function BotaoRecado({
  professor,
  aviso,
}: {
  professor: CoordenacaoLinha
  aviso: (m: string) => void
}) {
  const [estado, setEstado] = useState<EstadoRecado>('parado')

  async function mandar() {
    setEstado('enviando')
    try {
      const texto =
        `Oi! Aqui é o Fábio 🎧\n\n` +
        `Ficaram *${professor.em_aberto} lançamentos em aberto* na sua agenda ` +
        `(o mais antigo tem ${professor.pior_atraso} dias). ` +
        `Consegue dar uma olhada hoje?\n\n` +
        `É rapidinho pelo app: https://la-teacher.vercel.app`

      const r = await coordenacaoRecado(professor.professor_id, texto)

      if (!r.ok) {
        setEstado('erro')
        aviso(r.erro === 'apenas_admin' ? 'Só a coordenação manda recado.' : 'Não consegui agora.')
        return
      }
      if (r.enviado) {
        setEstado('enviado')
        aviso(`${primeiroNome(professor.professor_nome)} recebeu o recado no WhatsApp.`)
        return
      }
      if (r.motivo === 'ja_cobrado_hoje') {
        setEstado('ja_cobrado')
        aviso('O Fábio já cobrou esse professor hoje. Amanhã dá pra insistir.')
      } else if (r.motivo === 'professor_em_pausa') {
        setEstado('pausa')
        aviso('Esse professor está de férias no Fábio.')
      } else if (r.motivo === 'sem_whatsapp') {
        setEstado('erro')
        aviso('Esse professor não tem WhatsApp no cadastro.')
      } else {
        setEstado('erro')
        aviso('A mensagem não saiu no WhatsApp. Confere o número.')
      }
    } catch {
      setEstado('erro')
      aviso('Não consegui agora. Tenta de novo.')
    }
  }

  if (estado === 'enviado') {
    return <span className="text-[11px] text-success-text">recado enviado</span>
  }
  if (estado === 'ja_cobrado') {
    return <span className="text-[11px] text-text-muted">o Fábio já cobrou hoje</span>
  }
  if (estado === 'pausa') {
    return <span className="text-[11px] text-text-muted">de férias</span>
  }

  return (
    <button
      onClick={mandar}
      disabled={estado === 'enviando'}
      className="rounded-sm border border-brand-border px-2.5 py-1 text-[11px] text-brand-text disabled:opacity-50"
    >
      {estado === 'enviando' ? 'enviando…' : estado === 'erro' ? 'tentar de novo' : 'mandar recado'}
    </button>
  )
}

function primeiroNome(nome: string) {
  return nome.trim().split(' ')[0]
}
