import { Card, EmptyState, Skeleton } from '../../../components/ui'
import { BotaoRecado } from './BotaoRecado'
import type { CoordenacaoLinha } from '../../../lib/api'

/** Atraso a partir do qual o caso vira "não pode esperar" (plantão do celular). */
export const ATRASO_URGENTE = 3
/** Teto do plantão. Lista de plantão que rola deixa de ser plantão. */
export const TETO_PLANTAO = 8

/**
 * A fila de quem está com lançamento em aberto.
 *
 * A ordem vem PRONTA da RPC (067) e não se reordena aqui. Isso não é detalhe: o
 * painel de equipe já foi ao ar com a tela escrevendo "por urgência" em cima de
 * uma lista alfabética, e ninguém percebeu — lista ordenada errado parece lista
 * ordenada.
 *
 * Desktop e celular mostram COISAS DIFERENTES do mesmo dado, de propósito. No
 * computador a coordenação varre a lista inteira; no celular ela está andando
 * pela escola e só quer o que não pode esperar.
 *
 * Superfície, título e vazio são os do DS (`Card`, `EmptyState`). A primeira
 * versão desenhava os três à mão — e o título da tabela saía 13px sem caixa
 * alta em `text-primary`, quando todo cabeçalho de card do app é 13px caixa
 * alta com tracking em `text-secondary`.
 */
export function FilaEmAberto({
  linhas,
  carregando,
  aviso,
}: {
  linhas: CoordenacaoLinha[]
  carregando: boolean
  aviso: (m: string) => void
}) {
  const plantao = linhas.filter((p) => p.pior_atraso >= ATRASO_URGENTE).slice(0, TETO_PLANTAO)

  return (
    <>
      {/* ── Desktop: a lista inteira ─────────────────────────────────────── */}
      <div className="hidden md:block">
        <Card
          title="Quem está em aberto"
          icon="fa-solid fa-list-check"
          right={linhas.length > 0 ? 'ordenado por urgência' : undefined}
        >
          {carregando ? (
            <div className="space-y-2">
              <Skeleton className="h-8 w-full" />
              <Skeleton className="h-8 w-full" />
              <Skeleton className="h-8 w-full" />
            </div>
          ) : linhas.length === 0 ? (
            <EmptyState
              icon="fa-solid fa-circle-check"
              title="Ninguém com lançamento em aberto"
              description="Nos últimos 7 dias a equipe lançou tudo. Volta amanhã ou aumenta a janela."
            />
          ) : (
            /* Linhas com `px-1`, como as do Card "Semana" no Meu ponto: o
               respiro das laterais é o padding do próprio Card. */
            <table className="w-full table-fixed border-collapse text-[12.5px]">
              <thead>
                <tr className="text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">
                  <th className="w-[36%] px-1 py-2 text-left font-bold">Professor</th>
                  <th className="w-[13%] px-1 py-2 text-right font-bold">Em aberto</th>
                  <th className="w-[11%] px-1 py-2 text-right font-bold">Alunos</th>
                  <th className="w-[11%] px-1 py-2 text-right font-bold">Atraso</th>
                  <th className="w-[29%] px-1 py-2 text-right font-bold">Ação</th>
                </tr>
              </thead>
              <tbody>
                {linhas.map((p) => (
                  <tr key={p.professor_id} className="border-t border-border-subtle hover:bg-bg-hover">
                    <td className="px-1 py-2.5">
                      <span className="block truncate text-text-primary">{p.professor_nome}</span>
                      <span className="block truncate text-[11px] text-text-muted">{p.unidades}</span>
                    </td>
                    <td className="px-1 py-2.5 text-right font-bold text-danger-text">{p.em_aberto}</td>
                    <td className="px-1 py-2.5 text-right text-text-secondary">{p.alunos}</td>
                    <td className={`px-1 py-2.5 text-right ${corDoAtraso(p.pior_atraso)}`}>
                      {p.pior_atraso}d
                    </td>
                    <td className="px-1 py-2.5 text-right">
                      <BotaoRecado professor={p} aviso={aviso} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </Card>
      </div>

      {/* ── Celular: só o que pede decisão agora ──────────────────────────── */}
      <div className="md:hidden">
        <p className="mb-2 text-[13px] font-bold uppercase tracking-[.5px] text-text-secondary">
          Precisa de decisão agora
        </p>

        {carregando ? (
          <div className="space-y-2">
            <Skeleton className="h-20 w-full rounded-lg" />
            <Skeleton className="h-20 w-full rounded-lg" />
          </div>
        ) : plantao.length === 0 ? (
          <EmptyState
            icon="fa-solid fa-mug-hot"
            title={`Nada parado há ${ATRASO_URGENTE} dias ou mais`}
            description="O painel completo, com a fila inteira, está no computador."
          />
        ) : (
          <>
            {plantao.map((p) => (
              <Card key={p.professor_id} className="mb-2">
                <p className="text-sm font-semibold text-text-primary">{p.professor_nome}</p>
                <p className="mt-0.5 text-[12.5px] text-text-secondary">
                  <span className={corDoAtraso(p.pior_atraso)}>{p.em_aberto} em aberto</span> ·{' '}
                  {p.pior_atraso} dias · {p.unidades}
                </p>
                <div className="mt-2.5">
                  <BotaoRecado professor={p} aviso={aviso} />
                </div>
              </Card>
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

function corDoAtraso(dias: number) {
  return dias >= ATRASO_URGENTE ? 'font-bold text-danger-text' : 'text-text-secondary'
}
