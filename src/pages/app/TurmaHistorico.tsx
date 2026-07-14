import { useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { Button, EmptyState, ScreenHeader, Skeleton } from '../../components/ui'
import { cx } from '../../lib/cx'
import {
  historicoTurma,
  TURMA_NAO_SUA,
  type HistoricoTurma,
  type HistoricoTurmaSessao,
  type RepertorioAluno,
} from '../../lib/api'
import { LabelSecao, ParagrafoRegistro, SecaoRegistro } from '../../features/ficha/registroSecoes'
import { AppFrame } from './AppFrame'

type Estado =
  | { fase: 'carregando' }
  | { fase: 'erro' }
  | { fase: 'nao_sua' }
  | { fase: 'ok'; historico: HistoricoTurma }

function dataCurta(dataISO: string): string {
  const d = new Date(`${dataISO}T00:00:00`)
  if (Number.isNaN(d.getTime())) return dataISO
  return d.toLocaleDateString('pt-BR', { day: '2-digit', month: 'short' })
}

/**
 * /app/turma/:turmaNome — "o que eu dei nessa turma nas últimas aulas", sem ir
 * aluno por aluno (app_historico_turma). Sessões mais recentes primeiro. Aberta
 * pelo atalho na tela de Chamada da turma. Não mexe na ficha do aluno.
 */
export default function TurmaHistoricoPage() {
  const { turmaNome } = useParams()
  const navigate = useNavigate()
  const [estado, setEstado] = useState<Estado>({ fase: 'carregando' })

  useEffect(() => {
    let vivo = true
    setEstado({ fase: 'carregando' })
    historicoTurma(turmaNome ?? '')
      .then((res) => {
        if (!vivo) return
        setEstado(res === TURMA_NAO_SUA ? { fase: 'nao_sua' } : { fase: 'ok', historico: res })
      })
      .catch(() => vivo && setEstado({ fase: 'erro' }))
    return () => {
      vivo = false
    }
  }, [turmaNome])

  const curso = estado.fase === 'ok' ? estado.historico.curso : null

  return (
    <AppFrame>
      <ScreenHeader title="Histórico da turma" subtitle={curso ?? undefined} onBack={() => navigate(-1)} />

      <div className="flex-1 overflow-y-auto px-4 pb-10 pt-1">
        {estado.fase === 'carregando' && (
          <div className="space-y-3">
            {[0, 1].map((i) => (
              <Skeleton key={i} className="h-24 w-full" />
            ))}
          </div>
        )}

        {estado.fase === 'erro' && (
          <EmptyState
            icon="fa-solid fa-triangle-exclamation"
            title="Não consegui carregar"
            description="Deu um problema ao buscar o histórico da turma. Verifica a conexão e tenta de novo."
            action={
              <Button size="sm" onClick={() => navigate(0)}>
                <i className="fa-solid fa-rotate-right" aria-hidden="true" /> Tentar de novo
              </Button>
            }
          />
        )}

        {estado.fase === 'nao_sua' && (
          <EmptyState
            icon="fa-solid fa-user-lock"
            title="Turma não é sua"
            description="Você só vê o histórico de turmas que dá aula. Volta e escolhe pela agenda."
          />
        )}

        {estado.fase === 'ok' && <Conteudo historico={estado.historico} />}
      </div>
    </AppFrame>
  )
}

// ---------------------------------------------------------------------------

function Conteudo({ historico }: { historico: HistoricoTurma }) {
  const { alunos_atuais, sessoes } = historico

  return (
    <>
      {/* Identidade da turma: alunos atuais (o que diz ao professor qual turma é) */}
      {alunos_atuais.length > 0 && (
        <div className="mb-3 flex items-start gap-[11px] rounded-lg border border-border-subtle bg-bg-surface px-[14px] py-3">
          <div className="flex h-9 w-9 flex-none items-center justify-center rounded-full bg-brand-soft text-brand-text">
            <i className="fa-solid fa-users" aria-hidden="true" />
          </div>
          <div className="min-w-0">
            <span className="block text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">
              {alunos_atuais.length === 1 ? 'Aluno' : `${alunos_atuais.length} alunos`}
            </span>
            <span className="block text-sm text-text-primary">{alunos_atuais.join(', ')}</span>
          </div>
        </div>
      )}

      {sessoes.length === 0 ? (
        <EmptyState
          icon="fa-solid fa-book-open"
          title="Sem aulas registradas"
          description="Assim que você registrar aulas desta turma, o histórico aparece aqui."
        />
      ) : (
        <div className="overflow-hidden rounded-lg border border-border-subtle bg-bg-surface px-[14px]">
          {sessoes.map((s, i) => (
            <SessaoItem key={`${s.data}-${i}`} s={s} primeiro={i === 0} />
          ))}
        </div>
      )}
    </>
  )
}

function SessaoItem({ s, primeiro }: { s: HistoricoTurmaSessao; primeiro?: boolean }) {
  return (
    <div className={cx('py-3', !primeiro && 'border-t border-border-subtle')}>
      <div className="mb-2 flex items-center gap-2">
        <span className="text-[12px] text-text-secondary">{dataCurta(s.data)}</span>
        {primeiro && (
          <span className="rounded-full bg-brand-soft px-2 py-[1px] text-[10px] font-bold uppercase tracking-[.4px] text-brand-text">
            última aula
          </span>
        )}
        {s.origem === 'fabio' && (
          <i
            className="fa-solid fa-wand-magic-sparkles text-[11px] text-brand-text"
            title="Registro do Fábio"
            aria-label="Registro do Fábio"
          />
        )}
      </div>

      {s.origem === 'fabio' ? (
        <div className="flex flex-col gap-3">
          {s.objetivo && <SecaoRegistro rotulo="Objetivo" valor={s.objetivo} />}
          {s.conteudo && <SecaoRegistro rotulo="Conteúdo" valor={s.conteudo} />}
          <RepertorioSessao turma={s.repertorio_turma} porAluno={s.repertorio_por_aluno} />
          {s.dever_casa && <SecaoRegistro rotulo="Dever de casa" valor={s.dever_casa} />}
        </div>
      ) : (
        <ParagrafoRegistro texto={s.texto_legado ?? '—'} />
      )}
    </div>
  )
}

/** Repertório da sessão: o da turma e/ou o de cada aluno (recital). Coexistem. */
function RepertorioSessao({ turma, porAluno }: { turma: string | null; porAluno: RepertorioAluno[] }) {
  if (!turma && porAluno.length === 0) return null
  return (
    <div>
      <LabelSecao rotulo="Repertório" />
      {turma && (
        <p className="whitespace-pre-line text-[13px] leading-relaxed text-text-primary">{turma}</p>
      )}
      {porAluno.length > 0 && (
        <div className={cx('flex flex-col gap-[3px]', turma && 'mt-[6px]')}>
          {porAluno.map((r, i) => (
            <p
              key={`${r.aluno}-${i}`}
              className="flex items-start gap-[7px] text-[13px] leading-relaxed text-text-primary"
            >
              <i className="fa-solid fa-music mt-[4px] flex-none text-[10px] text-brand-text" aria-hidden="true" />
              <span>
                <b className="font-semibold">{r.primeiro_nome}:</b> {r.repertorio}
              </span>
            </p>
          ))}
        </div>
      )}
    </div>
  )
}
