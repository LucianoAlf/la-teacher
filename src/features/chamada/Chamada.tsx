import { useState, type ReactNode } from 'react'
import { useLocation, useNavigate, useParams } from 'react-router-dom'
import { Badge, Button, EmptyState, ScreenHeader, Skeleton } from '../../components/ui'
import {
  registrarPresencas,
  type AlunoSessao,
  type ErroChamada,
  type ResultadoChamada,
  type SessaoAula,
} from '../../lib/api'
import { AppFrame } from '../../pages/app/AppFrame'
import {
  chamadaCompleta,
  cursoAmigavel,
  horaSessao,
  janelaChamada,
  presencaExibida,
  primeiroNome,
  tituloSessao,
} from '../agenda/sessao'
import { useSessaoDaAula } from './useSessaoDaAula'

const ERRO_TEXTO: Record<ErroChamada | 'desconhecido', string> = {
  sem_professor_vinculado: 'Seu acesso não está ativado. Fala com a coordenação.',
  aula_nao_pertence_ao_professor: 'Essa aula não está na sua agenda.',
  aula_cancelada: 'Essa aula foi cancelada — não tem chamada.',
  chamada_ainda_nao_disponivel: 'A chamada abre 15 minutos antes da aula.',
  janela_de_chamada_encerrada: 'A janela de chamada (24h após a aula) já fechou. Fala com a coordenação.',
  roster_nao_sincronizado: 'A lista de alunos desta aula ainda não sincronizou. Tenta de novo em alguns minutos.',
  roster_incompleto: 'Tem aluno sem cadastro conciliado nesta aula — bloqueei pra não gravar chamada parcial.',
  aluno_ausente_fora_do_roster: 'A lista de alunos mudou desde que você abriu. Recarrega e confere de novo.',
  chamada_somente_na_aula_ancora: 'A chamada desta aula grava pela aula de turma. Abre ela pela agenda e tenta de novo.',
  desconhecido: 'Deu um problema ao enviar. Confere a conexão e tenta de novo.',
}

/** /app/chamada/:aulaId — presença em lote (o coração do MVP). */
export default function ChamadaPage() {
  const { aulaId } = useParams()
  const navigate = useNavigate()
  const { state } = useLocation() as { state?: { sessao?: SessaoAula } }
  // só confia no state se ele é mesmo desta aula (URL editada na mão ≠ state)
  const inicial =
    state?.sessao &&
    (state.sessao.aula_id_ancora === Number(aulaId) || state.sessao.aulas_agrupadas?.includes(Number(aulaId)))
      ? state.sessao
      : undefined
  const { estado, recarregar } = useSessaoDaAula(Number(aulaId), inicial)

  return (
    <AppFrame>
      <ScreenHeader title="Chamada" onBack={() => navigate(-1)} />
      {estado.fase === 'carregando' && (
        <div className="space-y-3 px-4 py-3">
          {[0, 1, 2].map((i) => (
            <Skeleton key={i} className="h-12 w-full" />
          ))}
        </div>
      )}
      {estado.fase === 'erro' && (
        <EmptyState
          icon="fa-solid fa-triangle-exclamation"
          title="Não consegui carregar"
          description="Verifica a conexão e tenta de novo."
          action={
            <Button size="sm" onClick={recarregar}>
              <i className="fa-solid fa-rotate-right" aria-hidden="true" /> Tentar de novo
            </Button>
          }
        />
      )}
      {estado.fase === 'sem_vinculo' && (
        <EmptyState
          icon="fa-solid fa-id-badge"
          title="Acesso não ativado"
          description="Fala com a coordenação pra vincular seu login a um professor."
        />
      )}
      {estado.fase === 'nao_encontrada' && (
        <EmptyState
          icon="fa-solid fa-calendar-xmark"
          title="Aula não encontrada"
          description="Só dá pra fazer chamada de aulas de hoje ou de ontem (a janela fecha em 24h). Procura a aula na agenda."
          action={
            <Button size="sm" variant="ghost" onClick={() => navigate('/app/agenda')}>
              <i className="fa-solid fa-calendar" aria-hidden="true" /> Abrir agenda
            </Button>
          }
        />
      )}
      {estado.fase === 'ok' && <Conteudo sessao={estado.sessao} onRecarregar={recarregar} />}
    </AppFrame>
  )
}

// ---------------------------------------------------------------------------

function ContextoAula({ sessao }: { sessao: SessaoAula }) {
  return (
    <div className="mx-4 mb-3 flex items-center gap-[11px] rounded-lg border border-[color:var(--brand-border)] bg-bg-surface px-[14px] py-[13px]">
      <div className="flex h-[38px] w-[38px] flex-none items-center justify-center rounded-md bg-brand-soft text-base text-brand-text">
        <i className={sessao.tipo === 'turma' ? 'fa-solid fa-users' : 'fa-solid fa-user'} aria-hidden="true" />
      </div>
      <div className="min-w-0">
        <b className="block truncate text-[14.5px]">{tituloSessao(sessao)}</b>
        <span className="block truncate text-xs text-text-secondary">
          {[cursoAmigavel(sessao.curso), `${horaSessao(sessao)}`].join(' · ')}
        </span>
      </div>
    </div>
  )
}

function Aviso({ icone, children, tom = 'info' }: { icone: string; children: ReactNode; tom?: 'info' | 'warn' | 'danger' }) {
  const cores =
    tom === 'danger'
      ? 'border-border-subtle bg-danger-soft text-danger-text'
      : tom === 'warn'
        ? 'border-border-subtle bg-warning-soft text-warning-text'
        : 'border-border-subtle bg-bg-inset text-text-secondary'
  return (
    <div className={`mx-4 mb-3 flex items-start gap-2 rounded-md border px-3 py-[10px] text-[12.5px] leading-relaxed ${cores}`}>
      <i className={`${icone} mt-[2px]`} aria-hidden="true" />
      <span>{children}</span>
    </div>
  )
}

function LinhaAluno({
  aluno,
  modo,
  ausente,
  onToggle,
}: {
  aluno: AlunoSessao
  modo: 'interativa' | 'leitura'
  ausente?: boolean
  onToggle?: () => void
}) {
  const presenca = presencaExibida(aluno)
  return (
    <button
      type="button"
      disabled={modo === 'leitura'}
      onClick={onToggle}
      className="flex w-full items-center gap-3 border-b border-border-subtle px-4 py-3 text-left last:border-b-0 disabled:cursor-default"
    >
      <span className="flex h-9 w-9 flex-none items-center justify-center rounded-full bg-brand-soft text-[13px] font-extrabold text-brand-text">
        {aluno.nome.charAt(0).toUpperCase()}
      </span>
      <span className="min-w-0 flex-1 truncate text-sm font-semibold">{aluno.nome}</span>
      {modo === 'interativa' ? (
        ausente ? (
          <Badge variant="danger" icon="fa-solid fa-user-xmark">
            Faltou
          </Badge>
        ) : (
          <Badge variant="ok" icon="fa-solid fa-check">
            Presente
          </Badge>
        )
      ) : (
        <span className="flex items-center gap-2">
          {aluno.justificada && presenca === 'faltou' && (
            <Badge variant="info" icon="fa-solid fa-file-circle-check">
              justificada
            </Badge>
          )}
          {presenca === 'faltou' ? (
            <Badge variant="danger" icon="fa-solid fa-user-xmark">
              Faltou
            </Badge>
          ) : presenca === 'presente' ? (
            <Badge variant="ok" icon="fa-solid fa-check">
              Presente
            </Badge>
          ) : (
            <Badge variant="warn" icon="fa-solid fa-clock">
              A confirmar
            </Badge>
          )}
        </span>
      )}
    </button>
  )
}

// ---------------------------------------------------------------------------

type Fase = 'lista' | 'confirmando' | 'enviando' | 'sucesso'

function Conteudo({ sessao, onRecarregar }: { sessao: SessaoAula; onRecarregar: () => void }) {
  const navigate = useNavigate()
  const [fase, setFase] = useState<Fase>('lista')
  const [ausentes, setAusentes] = useState<ReadonlySet<number>>(new Set())
  const [resultado, setResultado] = useState<ResultadoChamada | null>(null)
  const [erro, setErro] = useState<string | null>(null)

  const janela = janelaChamada(sessao)
  const enviada = chamadaCompleta(sessao)
  const semRoster = sessao.n_alunos === 0
  // o banco só aceita chamada na aula de TURMA do slot (âncora oficial)
  const semPortaChamada = sessao.aula_id_chamada == null
  const naoConciliados = sessao.alunos.filter((a) => a.aluno_id == null)

  // ---- sucesso ----
  if (fase === 'sucesso' && resultado) {
    return (
      <div className="flex flex-1 flex-col">
        <ContextoAula sessao={sessao} />
        <EmptyState
          icon="fa-solid fa-clipboard-check"
          title="Chamada enviada ✓"
          description={`${resultado.total_roster - ausentes.size} presente(s) e ${ausentes.size} falta(s) registradas. Correções, só com a coordenação.`}
          action={
            <Button size="sm" onClick={() => navigate(-1)}>
              Voltar
            </Button>
          }
        />
      </div>
    )
  }

  const toggle = (id: number) =>
    setAusentes((atual) => {
      const novo = new Set(atual)
      if (novo.has(id)) novo.delete(id)
      else novo.add(id)
      return novo
    })

  async function enviar() {
    if (sessao.aula_id_chamada == null) return
    setFase('enviando')
    setErro(null)
    const r = await registrarPresencas(sessao.aula_id_chamada, [...ausentes])
    if (!r.ok) {
      setErro(ERRO_TEXTO[r.erro])
      setFase('lista')
      return
    }
    if (r.resultado.chamada_ja_enviada) {
      setErro('Alguém já tinha enviado a chamada desta aula — nada foi sobrescrito.')
      setFase('lista')
      onRecarregar()
      return
    }
    setResultado(r.resultado)
    setFase('sucesso')
  }

  const interativa = !enviada && !semRoster && naoConciliados.length === 0 && janela === 'aberta' && !semPortaChamada

  return (
    <div className="flex flex-1 flex-col">
      <ContextoAula sessao={sessao} />

      {/* Avisos de estado (sempre honestos, nunca tela branca) */}
      {enviada && (
        <Aviso icone="fa-solid fa-lock">
          Chamada já registrada. O app não edita presença depois de enviada — <b>correção é com a coordenação</b>.
        </Aviso>
      )}
      {!enviada && semRoster && (
        <Aviso icone="fa-solid fa-cloud-arrow-down" tom="warn">
          A lista de alunos desta aula ainda não sincronizou do Emusys. Sem lista, sem chamada — tenta de novo mais tarde.
        </Aviso>
      )}
      {!enviada && !semRoster && naoConciliados.length > 0 && (
        <Aviso icone="fa-solid fa-user-slash" tom="danger">
          {naoConciliados.length === 1 ? 'Um aluno está' : `${naoConciliados.length} alunos estão`} sem cadastro
          conciliado: <b>{naoConciliados.map((a) => primeiroNome(a.nome)).join(', ')}</b>. A chamada fica bloqueada
          pra não gravar lote parcial — avisa a coordenação.
        </Aviso>
      )}
      {!enviada && !semRoster && naoConciliados.length === 0 && janela === 'antes' && (
        <Aviso icone="fa-solid fa-clock">A chamada abre 15 minutos antes da aula. Volta aqui na hora. 😉</Aviso>
      )}
      {!enviada && !semRoster && naoConciliados.length === 0 && janela === 'encerrada' && (
        <Aviso icone="fa-solid fa-lock" tom="warn">
          A janela de chamada fechou (24h após a aula). Agora só a coordenação pode lançar.
        </Aviso>
      )}
      {!enviada && janela === 'aberta' && naoConciliados.length === 0 && !semRoster && semPortaChamada && (
        <Aviso icone="fa-solid fa-user-lock" tom="warn">
          Esta aula individual não tem a aula de turma pareada no Emusys — a chamada dela ainda não passa pelo app.
          Avisa a coordenação.
        </Aviso>
      )}
      {erro && (
        <Aviso icone="fa-solid fa-triangle-exclamation" tom="danger">
          {erro}
        </Aviso>
      )}

      {/* Lista de alunos */}
      {!semRoster && (
        <div className="mx-4 overflow-hidden rounded-lg border border-border-subtle bg-bg-surface">
          {sessao.alunos.map((a, i) => (
            <LinhaAluno
              key={a.aluno_id ?? `nc-${i}`}
              aluno={a}
              modo={interativa && fase === 'lista' ? 'interativa' : 'leitura'}
              ausente={a.aluno_id != null && ausentes.has(a.aluno_id)}
              onToggle={a.aluno_id != null ? () => toggle(a.aluno_id!) : undefined}
            />
          ))}
        </div>
      )}

      {interativa && fase === 'lista' && (
        <>
          <p className="mx-4 mt-2 text-[12px] leading-relaxed text-text-secondary">
            <i className="fa-solid fa-hand-pointer text-brand-text" aria-hidden="true" /> Todo mundo começa como{' '}
            <b>presente</b> — toca em quem faltou. Depois de enviar, não dá pra editar pelo app.
          </p>
          <div className="mx-4 mb-6 mt-3 flex items-center gap-3">
            <span className="text-[13px] font-semibold text-text-secondary">
              {sessao.n_alunos - ausentes.size} presente(s) · {ausentes.size} falta(s)
            </span>
            <Button className="ml-auto" onClick={() => setFase('confirmando')}>
              <i className="fa-solid fa-paper-plane" aria-hidden="true" /> Enviar chamada
            </Button>
          </div>
        </>
      )}

      {fase === 'confirmando' && (
        <div className="mx-4 mt-3 rounded-lg border border-[color:var(--brand-border)] bg-bg-surface p-4">
          <b className="block text-[14.5px]">Confirma a chamada?</b>
          <p className="mt-1 text-[12.5px] leading-relaxed text-text-secondary">
            {sessao.n_alunos - ausentes.size} presente(s), {ausentes.size} falta(s)
            {ausentes.size > 0 && (
              <>
                {' '}
                — falta de{' '}
                <b>
                  {sessao.alunos
                    .filter((a) => a.aluno_id != null && ausentes.has(a.aluno_id))
                    .map((a) => primeiroNome(a.nome))
                    .join(', ')}
                </b>
              </>
            )}
            . Depois de enviar, <b>não dá pra editar pelo app</b> — correção é com a coordenação.
          </p>
          <div className="mt-3 flex gap-2">
            <Button variant="ghost" onClick={() => setFase('lista')}>
              Voltar
            </Button>
            <Button className="flex-1" onClick={() => void enviar()}>
              <i className="fa-solid fa-check" aria-hidden="true" /> Enviar agora
            </Button>
          </div>
        </div>
      )}

      {fase === 'enviando' && (
        <p className="mx-4 mt-4 text-center text-[13px] text-text-secondary">
          <i className="fa-solid fa-cloud-arrow-up fa-bounce" aria-hidden="true" /> Enviando a chamada…
        </p>
      )}
    </div>
  )
}
