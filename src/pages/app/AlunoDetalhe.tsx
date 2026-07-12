import { useEffect, useMemo, useState, type ReactNode } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { Button, Card, EmptyState, ScreenHeader, Skeleton } from '../../components/ui'
import {
  alunoFicha,
  FORA_DA_CARTEIRA,
  type AlunoFicha,
  type AlunoFichaPerfil,
  type AlunoFichaPresenca,
  type AlunoFichaRegistro,
  type SessaoAula,
} from '../../lib/api'
import { hojeBRT } from '../../lib/date'
import { cx } from '../../lib/cx'
import { AppFrame } from './AppFrame'
import { useSessoes } from '../../features/agenda/useSessoes'
import { horaSessao, podeGravar, tituloSessao } from '../../features/agenda/sessao'

type Estado =
  | { fase: 'carregando' }
  | { fase: 'erro' }
  | { fase: 'fora' }
  | { fase: 'ok'; ficha: AlunoFicha }

/**
 * /app/aluno/:alunoId — ficha completa do aluno (app_aluno_ficha, scoped ao
 * professor). Blocos: identidade, gravar aula de hoje, responsável, jornada,
 * presença e histórico pedagógico. Sem financeiro, sem anamnese, sem score.
 */
export default function AlunoDetalhePage() {
  const { alunoId } = useParams()
  const navigate = useNavigate()
  const idNum = Number(alunoId)

  const [estado, setEstado] = useState<Estado>({ fase: 'carregando' })
  const { estado: estadoSessoes } = useSessoes(hojeBRT())

  async function carregar() {
    setEstado({ fase: 'carregando' })
    try {
      const res = await alunoFicha(idNum)
      setEstado(res === FORA_DA_CARTEIRA ? { fase: 'fora' } : { fase: 'ok', ficha: res })
    } catch {
      setEstado({ fase: 'erro' })
    }
  }

  useEffect(() => {
    void carregar()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [idNum])

  // Sessão de HOJE deste aluno que está na janela de gravação (a primeira).
  const sessaoGravavel = useMemo<SessaoAula | null>(() => {
    if (estadoSessoes.fase !== 'ok') return null
    return estadoSessoes.sessoes.find((s) => podeGravar(s) && s.alunos.some((a) => a.aluno_id === idNum)) ?? null
  }, [estadoSessoes, idNum])

  const perfil = estado.fase === 'ok' ? estado.ficha.perfil : null

  return (
    <AppFrame>
      <ScreenHeader
        title={perfil?.nome ?? 'Aluno'}
        subtitle={perfil?.unidade ?? undefined}
        onBack={() => navigate(-1)}
      />

      <div className="flex-1 overflow-y-auto px-4 pb-10 pt-1">
        {estado.fase === 'carregando' && <FichaSkeleton />}

        {estado.fase === 'erro' && (
          <EmptyState
            icon="fa-solid fa-triangle-exclamation"
            title="Não consegui carregar"
            description="Deu um problema ao buscar a ficha do aluno. Verifica a conexão e tenta de novo."
            action={
              <Button size="sm" onClick={() => void carregar()}>
                <i className="fa-solid fa-rotate-right" aria-hidden="true" /> Tentar de novo
              </Button>
            }
          />
        )}

        {estado.fase === 'fora' && (
          <EmptyState
            icon="fa-solid fa-user-slash"
            title="Aluno não está na sua carteira"
            description="Você só vê a ficha de alunos que dá aula. Volta e escolhe pela lista."
          />
        )}

        {estado.fase === 'ok' && (
          <FichaConteudo
            ficha={estado.ficha}
            sessaoCarregando={estadoSessoes.fase === 'carregando'}
            sessaoGravavel={sessaoGravavel}
            onGravar={(s) => navigate(`/app/gravar/${s.aula_id_ancora}`, { state: { sessao: s } })}
          />
        )}
      </div>
    </AppFrame>
  )
}

/** Conteúdo da ficha (os 6 blocos) — separado do carregamento pra ser testável. */
export function FichaConteudo({
  ficha,
  sessaoCarregando,
  sessaoGravavel,
  onGravar,
}: {
  ficha: AlunoFicha
  sessaoCarregando: boolean
  sessaoGravavel: SessaoAula | null
  onGravar: (s: SessaoAula) => void
}) {
  return (
    <>
      <Identidade perfil={ficha.perfil} />
      <GravarHoje carregando={sessaoCarregando} sessao={sessaoGravavel} onGravar={onGravar} />
      <Responsaveis lista={ficha.responsaveis} />
      <Jornada jornada={ficha.minha_jornada} outros={ficha.outros_cursos} />
      <Presenca lista={ficha.presenca_recente} />
      <Historico lista={ficha.historico_pedagogico} />
    </>
  )
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function classificacaoLabel(c: string | null): string | null {
  const up = (c ?? '').toUpperCase()
  if (up === 'LAMK') return 'Kids'
  if (up === 'EMLA') return 'School'
  return null
}

function tempoDeCasa(meses: number | null): string | null {
  if (meses == null || meses < 0) return null
  const anos = Math.floor(meses / 12)
  const m = meses % 12
  const partes: string[] = []
  if (anos > 0) partes.push(`${anos} ${anos === 1 ? 'ano' : 'anos'}`)
  if (m > 0) partes.push(`${m} ${m === 1 ? 'mês' : 'meses'}`)
  if (partes.length === 0) return 'entrou este mês'
  return `${partes.join(' e ')} de casa`
}

/** "faz 15 em 8 dias" quando o aniversário está dentro de `janela` dias; senão null. */
function aniversarioProximo(nascISO: string | null, janela = 30): { texto: string; hoje: boolean } | null {
  if (!nascISO) return null
  const hoje = new Date()
  hoje.setHours(0, 0, 0, 0)
  const nasc = new Date(`${nascISO}T00:00:00`)
  if (Number.isNaN(nasc.getTime())) return null
  const proximo = new Date(hoje.getFullYear(), nasc.getMonth(), nasc.getDate())
  if (proximo < hoje) proximo.setFullYear(hoje.getFullYear() + 1)
  const diff = Math.round((proximo.getTime() - hoje.getTime()) / 86_400_000)
  if (diff > janela) return null
  const idade = proximo.getFullYear() - nasc.getFullYear()
  if (diff === 0) return { texto: `faz ${idade} hoje! 🎂`, hoje: true }
  return { texto: `faz ${idade} em ${diff} ${diff === 1 ? 'dia' : 'dias'}`, hoje: false }
}

function diasDesde(dataISO: string): string {
  const hoje = new Date()
  hoje.setHours(0, 0, 0, 0)
  const d = new Date(`${dataISO}T00:00:00`)
  const diff = Math.round((hoje.getTime() - d.getTime()) / 86_400_000)
  if (diff <= 0) return 'hoje'
  if (diff === 1) return 'ontem'
  return `há ${diff} dias`
}

function dataCurta(dataISO: string): string {
  const d = new Date(`${dataISO}T00:00:00`)
  if (Number.isNaN(d.getTime())) return dataISO
  return d.toLocaleDateString('pt-BR', { day: '2-digit', month: 'short' })
}

const ehPresente = (s: string | null) => (s ?? '').toLowerCase() === 'presente'
const ehFalta = (s: string | null) => {
  const v = (s ?? '').toLowerCase()
  return v === 'falta' || v === 'ausente'
}

// ---------------------------------------------------------------------------
// Blocos
// ---------------------------------------------------------------------------

function Identidade({ perfil }: { perfil: AlunoFichaPerfil }) {
  const classe = classificacaoLabel(perfil.classificacao)
  const casa = tempoDeCasa(perfil.meses_de_casa)
  const aniversario = aniversarioProximo(perfil.data_nascimento)

  return (
    <div className="mb-3 flex flex-col items-center gap-2 rounded-lg border border-border-subtle bg-bg-surface px-4 py-6">
      {perfil.foto_url ? (
        <img
          src={perfil.foto_url}
          alt={perfil.nome}
          className="h-[84px] w-[84px] flex-none rounded-full object-cover"
        />
      ) : (
        <div className="flex h-[84px] w-[84px] items-center justify-center rounded-full bg-brand-soft text-3xl font-extrabold text-brand-text">
          {perfil.nome.charAt(0).toUpperCase()}
        </div>
      )}
      <b className="text-center text-lg font-extrabold leading-tight">{perfil.nome}</b>

      <div className="mt-1 flex flex-wrap justify-center gap-[6px]">
        {perfil.idade != null && <Chip>{`${perfil.idade} anos${classe ? ` · ${classe}` : ''}`}</Chip>}
        {perfil.unidade && <Chip>{perfil.unidade}</Chip>}
        {casa && <Chip>{casa}</Chip>}
        {perfil.is_retorno && (
          <Chip icon="fa-solid fa-arrow-rotate-left">retornou</Chip>
        )}
        {aniversario && (
          <span className="inline-flex items-center gap-[5px] rounded-full border border-warning bg-warning-soft px-[10px] py-[3px] text-[12px] font-semibold text-warning-text">
            <i className="fa-solid fa-cake-candles" aria-hidden="true" /> {aniversario.texto}
          </span>
        )}
      </div>
    </div>
  )
}

function Chip({ children, icon }: { children: ReactNode; icon?: string }) {
  return (
    <span className="inline-flex items-center gap-[5px] rounded-full border border-border-subtle bg-bg-inset px-[10px] py-[3px] text-[12px] text-text-secondary">
      {icon && <i className={cx(icon, 'text-[11px]')} aria-hidden="true" />}
      {children}
    </span>
  )
}

/** Bloco "Gravar aula de hoje": botão quando na janela, motivo quando não. */
function GravarHoje({
  carregando,
  sessao,
  onGravar,
}: {
  carregando: boolean
  sessao: SessaoAula | null
  onGravar: (s: SessaoAula) => void
}) {
  if (carregando) {
    return (
      <div className="mb-3 flex items-center gap-3 rounded-lg border border-border-subtle bg-bg-surface px-4 py-[14px]">
        <Skeleton className="h-9 w-9 rounded-full" />
        <Skeleton className="h-4 w-40" />
      </div>
    )
  }

  if (sessao) {
    return (
      <div className="mb-3 rounded-lg border border-[color:var(--brand-border)] bg-brand-soft px-4 py-4">
        <div className="mb-3 flex items-center gap-[11px]">
          <div className="flex h-[38px] w-[38px] flex-none items-center justify-center rounded-md bg-brand text-base text-on-brand">
            <i className="fa-solid fa-microphone" aria-hidden="true" />
          </div>
          <div className="min-w-0">
            <b className="block text-sm">Aula acontecendo agora</b>
            <span className="block truncate text-xs text-text-secondary">
              {[tituloSessao(sessao), horaSessao(sessao)].filter(Boolean).join(' · ')}
            </span>
          </div>
        </div>
        <Button block onClick={() => onGravar(sessao)}>
          <i className="fa-solid fa-microphone" aria-hidden="true" /> Gravar aula de hoje
        </Button>
      </div>
    )
  }

  return (
    <div className="mb-3 flex items-start gap-3 rounded-lg border border-border-subtle bg-bg-surface px-4 py-[14px]">
      <div className="flex h-9 w-9 flex-none items-center justify-center rounded-full bg-bg-inset text-text-muted">
        <i className="fa-solid fa-microphone-slash" aria-hidden="true" />
      </div>
      <div className="min-w-0">
        <b className="block text-[13.5px] text-text-secondary">Sem aula aberta pra registrar agora</b>
        <span className="block text-[12px] leading-relaxed text-text-muted">
          A gravação abre quando começa uma aula sua com este aluno (fica disponível até 24h depois).
        </span>
      </div>
    </div>
  )
}

function Responsaveis({ lista }: { lista: AlunoFicha['responsaveis'] }) {
  const ordenada = [...lista].sort((a, b) => Number(b.principal) - Number(a.principal))
  if (ordenada.length === 0) return null
  return (
    <Card title="Responsável" icon="fa-solid fa-user-shield">
      {ordenada.map((r, i) => (
        <div
          key={`${r.nome}-${i}`}
          className="flex items-center gap-3 border-b border-border-subtle py-[10px] last:border-b-0"
        >
          <span className="min-w-0 flex-1 truncate text-sm">{r.nome ?? '—'}</span>
          {r.parentesco && <span className="text-[12px] text-text-secondary">{r.parentesco}</span>}
        </div>
      ))}
    </Card>
  )
}

function Jornada({
  jornada,
  outros,
}: {
  jornada: AlunoFicha['minha_jornada']
  outros: AlunoFicha['outros_cursos']
}) {
  return (
    <Card title="Jornada" icon="fa-solid fa-graduation-cap">
      {jornada.length === 0 && <p className="py-1 text-sm text-text-secondary">Sem matrícula ativa com você.</p>}

      {jornada.map((j, i) => (
        <div key={`${j.curso}-${i}`} className="border-b border-border-subtle py-3 last:border-b-0">
          <div className="flex items-baseline justify-between gap-2">
            <div className="min-w-0">
              <b className="text-sm">{j.curso ?? 'Curso'}</b>
              <span className="text-xs text-text-secondary">
                {[j.dia_aula, j.horario].filter(Boolean).join(' · ') && ` · ${[j.dia_aula, j.horario].filter(Boolean).join(' · ')}`}
              </span>
            </div>
            {j.jornada_label && <span className="flex-none text-[13px] font-semibold">{j.jornada_label}</span>}
          </div>
          {j.percentual != null && (
            <div className="mt-2 h-[6px] overflow-hidden rounded-full bg-bg-inset">
              <div className="h-full rounded-full bg-brand" style={{ width: `${Math.min(100, j.percentual)}%` }} />
            </div>
          )}
        </div>
      ))}

      {outros.length > 0 && (
        <div className="mt-1 flex flex-col gap-[6px] pt-3">
          {outros.map((o, i) => (
            <div key={`${o.curso}-${i}`} className="flex items-center gap-2 text-[13px] text-text-secondary">
              <i className="fa-solid fa-music text-[13px]" aria-hidden="true" />
              Também faz {o.curso}
              {o.professor && <span className="text-text-muted">· {o.professor}</span>}
            </div>
          ))}
        </div>
      )}
    </Card>
  )
}

function Presenca({ lista }: { lista: AlunoFichaPresenca[] }) {
  if (lista.length === 0) {
    return (
      <Card title="Presença" icon="fa-solid fa-calendar-check">
        <p className="py-1 text-sm text-text-secondary">Sem presença registrada ainda.</p>
      </Card>
    )
  }

  const presentes = lista.filter((p) => ehPresente(p.status)).length
  const faltas = lista.filter((p) => ehFalta(p.status)).length
  const base = presentes + faltas
  const pct = base > 0 ? Math.round((presentes / base) * 100) : null
  // lista vem em ordem decrescente (recente → antigo); a tirinha mostra antigo → recente.
  const tirinha = [...lista].reverse()

  return (
    <Card title="Presença" icon="fa-solid fa-calendar-check">
      <div className="mb-3 flex flex-wrap gap-[5px]">
        {tirinha.map((p, i) => (
          <span
            key={`${p.data}-${i}`}
            title={`${dataCurta(p.data)} · ${p.status ?? '—'}`}
            className={cx(
              'h-[11px] w-[11px] rounded-full',
              ehPresente(p.status) ? 'bg-success' : ehFalta(p.status) ? 'bg-danger' : 'bg-border-strong',
            )}
          />
        ))}
      </div>
      <div className="flex items-center gap-2 border-b border-border-subtle py-[6px] text-[13px]">
        <i className="fa-solid fa-chart-simple text-[13px] text-text-secondary" aria-hidden="true" />
        Presença recente
        <span className="ml-auto font-semibold">{pct != null ? `${pct}%` : '—'}</span>
      </div>
      <div className="flex items-center gap-2 py-[6px] text-[13px]">
        <i className="fa-solid fa-clock text-[13px] text-text-secondary" aria-hidden="true" />
        Última aula
        <span className="ml-auto font-semibold">{diasDesde(lista[0].data)}</span>
      </div>
    </Card>
  )
}

function Historico({ lista }: { lista: AlunoFichaRegistro[] }) {
  if (lista.length === 0) {
    return (
      <Card title="Histórico pedagógico" icon="fa-solid fa-clock-rotate-left">
        <EmptyState
          icon="fa-solid fa-book-open"
          title="Sem registros ainda"
          description="Conforme você registra as aulas, o histórico deste aluno aparece aqui — inclusive o que ficou de professores anteriores."
        />
      </Card>
    )
  }

  return (
    <Card title="Histórico pedagógico" icon="fa-solid fa-clock-rotate-left">
      {lista.map((r, i) => (
        <div key={`${r.data}-${i}`} className="border-b border-border-subtle py-3 last:border-b-0">
          <div className="mb-1 flex items-center gap-2">
            <span className="text-[12px] text-text-secondary">
              {dataCurta(r.data)}
              {r.curso ? ` · ${r.curso}` : ''}
            </span>
            {r.origem === 'fabio' && (
              <i
                className="fa-solid fa-wand-magic-sparkles text-[11px] text-brand-text"
                title="Registro do Fábio"
                aria-label="Registro do Fábio"
              />
            )}
            <span
              className={cx(
                'ml-auto rounded-full px-2 py-[1px] text-[11px] font-semibold',
                r.foi_voce ? 'bg-brand-soft text-brand-text' : 'bg-bg-inset text-text-secondary',
              )}
            >
              {r.foi_voce ? 'você' : 'prof. anterior'}
            </span>
          </div>
          <p className="whitespace-pre-line text-[13px] leading-relaxed text-text-primary">{r.texto ?? '—'}</p>
        </div>
      ))}
    </Card>
  )
}

function FichaSkeleton() {
  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-col items-center gap-2 rounded-lg border border-border-subtle bg-bg-surface px-4 py-6">
        <Skeleton className="h-[84px] w-[84px] rounded-full" />
        <Skeleton className="h-4 w-40" />
        <Skeleton className="h-4 w-56" />
      </div>
      <Skeleton className="h-16 w-full rounded-lg" />
      <Skeleton className="h-28 w-full rounded-lg" />
      <Skeleton className="h-28 w-full rounded-lg" />
    </div>
  )
}
