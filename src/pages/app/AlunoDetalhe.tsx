import { useMemo } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { Badge, Button, Card, EmptyState, ScreenHeader, Skeleton } from '../../components/ui'
import type { SessaoAula } from '../../lib/api'
import { hojeBRT } from '../../lib/date'
import { AppFrame } from './AppFrame'
import { useCarteira } from '../../features/alunos/useCarteira'
import { horarioAluno, qualidadeLabel } from '../../features/alunos/carteira'
import { useSessoes } from '../../features/agenda/useSessoes'
import { horaSessao, podeGravar, tituloSessao } from '../../features/agenda/sessao'

/**
 * /app/aluno/:alunoId — detalhe do aluno (a partir da carteira).
 *
 * Mostra as matrículas do aluno e, quando ELE tem uma aula na janela de
 * gravação AGORA, o atalho "Gravar aula de hoje" (grava aquela aula, sem
 * perguntar qual — regra do Alf: nunca deixar escolher do histórico). Fora da
 * janela, a ação aparece desabilitada com o motivo.
 */
export default function AlunoDetalhePage() {
  const { alunoId } = useParams()
  const navigate = useNavigate()
  const idNum = Number(alunoId)

  const { estado, recarregar } = useCarteira()
  const { estado: estadoSessoes } = useSessoes(hojeBRT())

  const matriculas = estado.fase === 'ok' ? estado.alunos.filter((a) => a.aluno_id === idNum) : []
  const aluno = matriculas[0]

  // Sessão de HOJE deste aluno que está na janela de gravação (a primeira).
  const sessaoGravavel = useMemo<SessaoAula | null>(() => {
    if (estadoSessoes.fase !== 'ok') return null
    return (
      estadoSessoes.sessoes.find(
        (s) => podeGravar(s) && s.alunos.some((al) => al.aluno_id === idNum),
      ) ?? null
    )
  }, [estadoSessoes, idNum])

  return (
    <AppFrame>
      <ScreenHeader
        title={aluno?.aluno_nome ?? 'Aluno'}
        subtitle={aluno?.unidade ?? undefined}
        onBack={() => navigate(-1)}
      />

      <div className="flex-1 overflow-y-auto px-4 pb-10 pt-1">
        {estado.fase === 'carregando' && <DetalheSkeleton />}

        {estado.fase === 'erro' && (
          <EmptyState
            icon="fa-solid fa-triangle-exclamation"
            title="Não consegui carregar"
            description="Deu um problema ao buscar os dados do aluno. Verifica a conexão e tenta de novo."
            action={
              <Button size="sm" onClick={recarregar}>
                <i className="fa-solid fa-rotate-right" aria-hidden="true" /> Tentar de novo
              </Button>
            }
          />
        )}

        {estado.fase === 'ok' && !aluno && (
          <EmptyState
            icon="fa-solid fa-user-slash"
            title="Aluno não encontrado"
            description="Esse aluno não está na sua carteira agora. Volta e escolhe pela lista."
          />
        )}

        {estado.fase === 'ok' && aluno && (
          <>
            {/* Cabeçalho do aluno */}
            <div className="mb-3 flex flex-col items-center gap-2 rounded-lg border border-border-subtle bg-bg-surface px-4 py-6">
              <div className="flex h-[72px] w-[72px] items-center justify-center rounded-full bg-brand-soft text-2xl font-extrabold text-brand-text">
                {aluno.aluno_nome.charAt(0).toUpperCase()}
              </div>
              <b className="text-center text-lg font-extrabold leading-tight">{aluno.aluno_nome}</b>
              {aluno.unidade && <span className="text-[12.5px] text-text-secondary">{aluno.unidade}</span>}
            </div>

            {/* Gravar aula de hoje — só quando há aula na janela */}
            <GravarHoje
              carregando={estadoSessoes.fase === 'carregando'}
              sessao={sessaoGravavel}
              onGravar={(s) => navigate(`/app/gravar/${s.aula_id_ancora}`, { state: { sessao: s } })}
            />

            {/* Matrículas do aluno (curso, horário, jornada) */}
            <Card title={matriculas.length > 1 ? 'Matrículas' : 'Matrícula'} icon="fa-solid fa-graduation-cap">
              {matriculas.map((m, i) => {
                const q = qualidadeLabel(m.qualidade)
                const horario = horarioAluno(m)
                return (
                  <div
                    key={`${m.curso}-${i}`}
                    className="flex items-center gap-3 border-b border-border-subtle py-[11px] last:border-b-0"
                  >
                    <div className="min-w-0 flex-1">
                      <b className="block truncate text-sm">{m.curso ?? 'Sem curso'}</b>
                      <span className="block truncate text-xs text-text-secondary">
                        {[horario, m.jornada_label].filter(Boolean).join(' · ') || 'sem horário definido'}
                      </span>
                    </div>
                    {q && (
                      <Badge variant="warn" icon="fa-solid fa-circle-info">
                        {q}
                      </Badge>
                    )}
                  </div>
                )
              })}
            </Card>
          </>
        )}
      </div>
    </AppFrame>
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

function DetalheSkeleton() {
  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-col items-center gap-2 rounded-lg border border-border-subtle bg-bg-surface px-4 py-6">
        <Skeleton className="h-[72px] w-[72px] rounded-full" />
        <Skeleton className="h-4 w-32" />
      </div>
      <Skeleton className="h-16 w-full rounded-lg" />
      <Skeleton className="h-24 w-full rounded-lg" />
    </div>
  )
}
