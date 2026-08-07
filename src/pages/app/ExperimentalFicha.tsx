import { useNavigate, useParams } from 'react-router-dom'
import { AppFrame } from './AppFrame'
import { Badge, Button, Card, EmptyState, ScreenHeader, Skeleton } from '../../components/ui'
import { useExperimental } from '../../features/experimental/useExperimental'
import type { ExperimentalDoProfessor } from '../../lib/api'
import { dataBRTDoTimestamp, formatDiaCurto } from '../../lib/date'

/**
 * A ficha da experimental — o que o professor lê ANTES de entrar na sala.
 *
 * A ordem da tela é a ordem do uso: primeiro a dica (o que fazer daqui a
 * pouco), depois o contexto (de onde ela saiu), e o botão de registrar por
 * último — ele só interessa quando a aula acabou.
 */
export default function ExperimentalFichaPage() {
  const { vinculoId } = useParams<{ vinculoId: string }>()
  const navigate = useNavigate()
  const { estado } = useExperimental(vinculoId ? Number(vinculoId) : null)

  return (
    <AppFrame>
      <ScreenHeader
        title={estado.fase === 'pronto' ? estado.dados.nome_aluno : 'Experimental'}
        subtitle={
          estado.fase === 'pronto'
            ? `${formatDiaCurto(dataBRTDoTimestamp(estado.dados.data_hora_inicio))} · ${estado.dados.hora}${
                estado.dados.curso ? ` · ${estado.dados.curso}` : ''
              }`
            : undefined
        }
        onBack={() => navigate(-1)}
      />

      <div className="flex-1 space-y-3 overflow-y-auto px-4 pb-[calc(24px_+_env(safe-area-inset-bottom))]">
        {estado.fase === 'carregando' && (
          <>
            <Skeleton className="h-28 w-full rounded-lg" />
            <Skeleton className="h-24 w-full rounded-lg" />
          </>
        )}

        {estado.fase === 'erro' && (
          <EmptyState
            icon="fa-solid fa-circle-exclamation"
            title="Não deu pra abrir"
            description={estado.mensagem}
          />
        )}

        {estado.fase === 'pronto' && <Conteudo dados={estado.dados} />}
      </div>
    </AppFrame>
  )
}

function Conteudo({ dados }: { dados: ExperimentalDoProfessor }) {
  const navigate = useNavigate()
  const ctx = dados.contexto
  const jaConfirmado = dados.registro?.status === 'confirmado'
  const temRascunho = dados.registro != null && !jaConfirmado

  return (
    <>
      <div className="flex flex-wrap items-center gap-2 pt-1">
        <Badge variant="info" icon="fa-solid fa-star">
          Experimental
        </Badge>
        {ctx?.idade != null && <Badge variant="brand" outline>{ctx.idade} anos</Badge>}
        {dados.unidade_nome && (
          <span className="text-xs text-text-secondary">{dados.unidade_nome}</span>
        )}
      </div>

      {/* A DICA primeiro: é o que ele vai usar daqui a pouco. Some quando não
          existe — dica inventada é pior que nenhuma (046). */}
      {dados.como_conduzir && (
        <section className="rounded-lg border border-brand-border bg-brand-soft p-[14px]">
          <h3 className="mb-[10px] flex items-center gap-2 text-[13px] font-bold uppercase tracking-[.5px] text-brand-text">
            <i className="fa-solid fa-lightbulb text-xs" aria-hidden="true" />
            Como conduzir essa aula
          </h3>
          <p className="text-[13.5px] leading-relaxed text-text-primary">{dados.como_conduzir}</p>
        </section>
      )}

      {ctx?.quem_e_esse_aluno?.historia && (
        <Card title="Quem é" icon="fa-solid fa-user">
          <p className="text-[13.5px] leading-relaxed text-text-primary">
            {ctx.quem_e_esse_aluno.historia}
          </p>
          {ctx.quem_e_esse_aluno.nivel_declarado && (
            <p className="mt-2 text-xs text-text-secondary">
              Nível declarado: {ctx.quem_e_esse_aluno.nivel_declarado.replace(/_/g, ' ')}
              {ctx.quem_e_esse_aluno.de_quem_partiu &&
                ` · vontade partiu ${ctx.quem_e_esse_aluno.de_quem_partiu}`}
            </p>
          )}
        </Card>
      )}

      {ctx?.ganchos_de_conexao && ctx.ganchos_de_conexao.length > 0 && (
        <Card title="Ganchos pra puxar" icon="fa-solid fa-link">
          <ul className="space-y-[6px]">
            {ctx.ganchos_de_conexao.map((g) => (
              <li key={g} className="flex gap-2 text-[13.5px] leading-relaxed text-text-primary">
                <span className="text-brand-text" aria-hidden="true">
                  ·
                </span>
                {g}
              </li>
            ))}
          </ul>
        </Card>
      )}

      {ctx?.para_a_devolutiva?.o_que_a_familia_espera && (
        <Card title="O que a família espera" icon="fa-solid fa-comment">
          <p className="text-[13.5px] leading-relaxed text-text-primary">
            {ctx.para_a_devolutiva.o_que_a_familia_espera}
          </p>
        </Card>
      )}

      {ctx?.alertas && ctx.alertas.length > 0 && (
        <Card title="Atenção" icon="fa-solid fa-triangle-exclamation">
          <ul className="space-y-[6px]">
            {ctx.alertas.map((a) => (
              <li key={`${a.tipo}-${a.texto}`} className="text-[13.5px] leading-relaxed text-warning-text">
                {a.texto}
              </li>
            ))}
          </ul>
        </Card>
      )}

      {/* Sem contexto nenhum: dizer isso é melhor que uma tela vazia que
          parece quebrada. */}
      {!dados.como_conduzir && !ctx?.quem_e_esse_aluno?.historia && !ctx?.ganchos_de_conexao?.length && (
        <EmptyState
          icon="fa-solid fa-circle-info"
          title="Ainda sem contexto"
          description="A conversa da recepção não trouxe nada sobre essa pessoa. Você entra sem histórico — e o que você registrar depois vira o começo dele."
        />
      )}

      <div className="space-y-2 pt-1">
        <Button onClick={() => navigate(`/app/experimental/${dados.vinculo_id}/registrar`)}>
          <i className="fa-solid fa-pen-to-square mr-2" aria-hidden="true" />
          {jaConfirmado ? 'Ver o registro' : temRascunho ? 'Continuar o registro' : 'Registrar a aula'}
        </Button>
        {jaConfirmado && (
          <p className="text-center text-xs text-success-text">
            <i className="fa-solid fa-check mr-1" aria-hidden="true" />
            Registrada e enviada ao comercial
          </p>
        )}
      </div>
    </>
  )
}
