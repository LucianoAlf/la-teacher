import { EmptyState, Skeleton } from '../../../components/ui'
import { LinhaProfessor, ATRASO_URGENTE } from './LinhaProfessor'
import type { CoordenacaoLinha } from '../../../lib/api'
import type { FiltroPainel } from './FiltrosPainel'

/** Teto do plantão. Lista de plantão que rola deixa de ser plantão. */
export const TETO_PLANTAO = 8

export { ATRASO_URGENTE }

/**
 * A fila de quem está com lançamento em aberto.
 *
 * A ordem vem PRONTA da RPC (070) e não se reordena aqui. Isso não é detalhe: o
 * painel de equipe já foi ao ar com a tela escrevendo "por urgência" em cima de
 * uma lista alfabética, e ninguém percebeu — lista ordenada errado parece lista
 * ordenada.
 *
 * Desktop e celular mostram COISAS DIFERENTES do mesmo dado, de propósito. No
 * computador a coordenação varre a lista inteira; no celular ela está andando
 * pela escola e só quer o que não pode esperar. A LINHA, porém, é a mesma nos
 * dois — o card se reorganiza sozinho por `flex-wrap`.
 *
 * O cabeçalho da seção usa a tipografia de título de card do DS (13px, caixa
 * alta, tracking .5px) SEM envelopar tudo num `Card`: as linhas já são cards, e
 * card dentro de card vira moldura dentro de moldura.
 */
export function FilaEmAberto({
  linhas,
  filtro,
  carregando,
  aviso,
}: {
  linhas: CoordenacaoLinha[]
  filtro: FiltroPainel
  carregando: boolean
  aviso: (m: string) => void
}) {
  // Plantão é só o COBRÁVEL: pior_atraso null = tudo no Emusys, e isso não
  // toca o celular de ninguém (072).
  const plantao = linhas
    .filter((p) => (p.pior_atraso ?? 0) >= ATRASO_URGENTE)
    .slice(0, TETO_PLANTAO)

  if (carregando) {
    return (
      <>
        <Cabecalho />
        <div className="space-y-2">
          <Skeleton className="h-[70px] w-full rounded-lg" />
          <Skeleton className="h-[70px] w-full rounded-lg" />
          <Skeleton className="h-[70px] w-full rounded-lg" />
        </div>
      </>
    )
  }

  return (
    <>
      {/* ── Desktop: a lista inteira ─────────────────────────────────────── */}
      <div className="hidden md:block">
        {/* A janela no cabeçalho: os selos das linhas dizem "em aberto" e
            "afetados", e é AQUI que se aprende em aberto DESDE QUANDO. */}
        <Cabecalho direita={linhas.length > 0 ? 'últimos 7 dias · por urgência' : undefined} />
        {linhas.length === 0 ? (
          <EmptyState
            icon="fa-solid fa-circle-check"
            title="Ninguém com lançamento em aberto"
            description="Nos últimos 7 dias a equipe lançou tudo. Volta amanhã ou aumenta a janela."
          />
        ) : (
          linhas.map((p) => (
            <LinhaProfessor key={p.professor_id} p={p} filtro={filtro} aviso={aviso} />
          ))
        )}
      </div>

      {/* ── Celular: só o que pede decisão agora ──────────────────────────── */}
      <div className="md:hidden">
        <Cabecalho titulo="Precisa de decisão agora" icone="fa-solid fa-bolt" />
        {plantao.length === 0 ? (
          <EmptyState
            icon="fa-solid fa-mug-hot"
            title={`Nada parado há ${ATRASO_URGENTE} dias ou mais`}
            description="O painel completo, com a fila inteira, está no computador."
          />
        ) : (
          <>
            {plantao.map((p) => (
              <LinhaProfessor key={p.professor_id} p={p} filtro={filtro} aviso={aviso} />
            ))}
            {/* Diz o que ficou de fora em vez de fingir que a lista é essa. */}
            {linhas.length > plantao.length ? (
              <p className="mt-3 text-center text-[11.5px] text-text-muted">
                mais {linhas.length - plantao.length} com menos de {ATRASO_URGENTE} dias — no
                computador aparece a lista toda
              </p>
            ) : null}
          </>
        )}
      </div>
    </>
  )
}

function Cabecalho({
  titulo = 'Quem está em aberto',
  icone = 'fa-solid fa-list-check',
  direita,
}: {
  titulo?: string
  icone?: string
  direita?: string
}) {
  return (
    <div className="mb-3 flex items-baseline justify-between gap-3">
      <span className="flex items-center gap-2 text-[13px] font-bold uppercase tracking-[.5px] text-text-secondary">
        <i className={`${icone} text-xs text-brand-text`} aria-hidden />
        {titulo}
      </span>
      {direita ? <span className="text-[11.5px] text-text-muted">{direita}</span> : null}
    </div>
  )
}
