import { Skeleton } from '../../../components/ui'
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
      <div className="hidden overflow-hidden rounded-md border border-border-subtle bg-bg-surface md:block">
        <div className="flex items-center justify-between border-b border-border-subtle px-3.5 py-2.5">
          <span className="text-[13px] font-bold text-text-primary">Quem está em aberto</span>
          <span className="text-[11px] text-text-muted">ordenado por urgência</span>
        </div>

        {carregando ? (
          <div className="space-y-2 p-3.5">
            <Skeleton className="h-8 w-full" />
            <Skeleton className="h-8 w-full" />
            <Skeleton className="h-8 w-full" />
          </div>
        ) : linhas.length === 0 ? (
          <p className="px-3.5 py-8 text-center text-[13px] text-text-secondary">
            Ninguém com lançamento em aberto nos últimos 7 dias.
          </p>
        ) : (
          <table className="w-full table-fixed border-collapse text-[12.5px]">
            <thead>
              <tr className="text-[10px] uppercase tracking-wider text-text-secondary">
                <th className="w-[36%] px-3.5 py-2 text-left font-normal">Professor</th>
                <th className="w-[13%] px-1 py-2 text-right font-normal">Em aberto</th>
                <th className="w-[11%] px-1 py-2 text-right font-normal">Alunos</th>
                <th className="w-[11%] px-1 py-2 text-right font-normal">Atraso</th>
                <th className="w-[29%] px-3.5 py-2 text-right font-normal">Ação</th>
              </tr>
            </thead>
            <tbody>
              {linhas.map((p) => (
                <tr key={p.professor_id} className="border-t border-border-subtle hover:bg-bg-hover">
                  <td className="px-3.5 py-2.5">
                    <span className="block truncate text-text-primary">{p.professor_nome}</span>
                    <span className="block text-[10.5px] text-text-muted">{p.unidades}</span>
                  </td>
                  <td className="px-1 py-2.5 text-right font-bold text-danger-text">{p.em_aberto}</td>
                  <td className="px-1 py-2.5 text-right text-text-secondary">{p.alunos}</td>
                  <td className={`px-1 py-2.5 text-right ${corDoAtraso(p.pior_atraso)}`}>
                    {p.pior_atraso}d
                  </td>
                  <td className="px-3.5 py-2.5 text-right">
                    <BotaoRecado professor={p} aviso={aviso} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* ── Celular: só o que pede decisão agora ──────────────────────────── */}
      <div className="md:hidden">
        <p className="mb-2 text-[13px] font-bold text-text-primary">Precisa de decisão agora</p>

        {carregando ? (
          <div className="space-y-2">
            <Skeleton className="h-20 w-full" />
            <Skeleton className="h-20 w-full" />
          </div>
        ) : plantao.length === 0 ? (
          <p className="text-[13px] text-text-secondary">
            Nada atrasado há {ATRASO_URGENTE} dias ou mais. O painel completo está no computador.
          </p>
        ) : (
          <>
            {plantao.map((p) => (
              <div
                key={p.professor_id}
                className="mb-2 rounded-md border border-border-subtle bg-bg-surface p-3"
              >
                <p className="text-[14px] text-text-primary">{p.professor_nome}</p>
                <p className="mt-0.5 text-[12px] text-text-secondary">
                  <span className={corDoAtraso(p.pior_atraso)}>{p.em_aberto} em aberto</span> ·{' '}
                  {p.pior_atraso} dias · {p.unidades}
                </p>
                <div className="mt-2.5">
                  <BotaoRecado professor={p} aviso={aviso} />
                </div>
              </div>
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
