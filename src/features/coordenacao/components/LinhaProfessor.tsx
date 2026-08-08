import { useState } from 'react'
import { Avatar, Badge } from '../../../components/ui'
import { BotaoRecado } from './BotaoRecado'
import { AulasEmAberto } from './AulasEmAberto'
import type { CoordenacaoLinha } from '../../../lib/api'

/** Atraso a partir do qual o caso vira "não pode esperar". */
export const ATRASO_URGENTE = 3

/**
 * Uma linha da fila — e ela é um CARD, não uma célula de tabela.
 *
 * A tela nasceu como tabela e o Alf matou na hora certa: *"esse formato
 * tabelona, meio Excel... essa parte dos professores aí, pensa que eles são os
 * nossos ouros"*. Duas coisas estavam erradas:
 *
 * 1. **Hierarquia invertida.** O painel inteiro tem uma tese — o professor é a
 *    LINHA — e o professor era o elemento MENOS destacado dela: 12,5px regular,
 *    o mesmo peso dos números ao lado. Agora é foto de 40px + nome de 15px.
 * 2. **Célula que depende de cabeçalho.** Na linha 12 de uma tabela, "37 | 37 |
 *    5d" não se explica: o cabeçalho já saiu da tela. Cada número virou selo
 *    com a unidade dentro ("21 aulas"), então qualquer linha se lê sozinha.
 *
 * O tom é UM por linha, não um por selo: ou a pessoa está urgente (vermelho) ou
 * está pendente (amarelo). Dois selos brigando de cor na mesma linha fazem a
 * coordenação escolher por susto, não por prioridade.
 */
export function LinhaProfessor({
  p,
  aviso,
}: {
  p: CoordenacaoLinha
  aviso: (m: string) => void
}) {
  const [aberto, setAberto] = useState(false)
  const urgente = p.pior_atraso >= ATRASO_URGENTE
  const tom = urgente ? 'danger' : 'warn'

  const legenda = [p.unidades, p.cursos].filter(Boolean).join(' · ')

  return (
    <div className="mb-2 overflow-hidden rounded-lg border border-border-subtle bg-bg-surface shadow-card last:mb-0">
      {/* `flex-wrap` no lugar de dois blocos md:hidden/hidden md:flex: a mesma
          marcação serve celular e desktop, e o que muda é só onde quebra. */}
      <div className="flex flex-wrap items-center gap-x-3 gap-y-2 px-3.5 py-3">
        <button
          type="button"
          onClick={() => setAberto((v) => !v)}
          aria-expanded={aberto}
          className="flex min-w-[200px] flex-1 items-center gap-3 text-left"
        >
          <i
            className={`fa-solid fa-chevron-right w-3 flex-none text-[11px] text-text-muted transition-transform ${
              aberto ? 'rotate-90' : ''
            }`}
            aria-hidden
          />
          <Avatar fotoUrl={p.foto_url} nome={p.professor_nome} />
          <span className="min-w-0">
            <b className="block truncate text-[15px] font-bold leading-tight text-text-primary">
              {p.professor_nome}
            </b>
            <span className="mt-[3px] block truncate text-[12px] leading-tight text-text-secondary">
              {legenda}
            </span>
          </span>
        </button>

        <div className="flex flex-none items-center gap-1.5">
          <Badge variant={tom} icon="fa-solid fa-clipboard-list">
            {p.aulas} {p.aulas === 1 ? 'aula' : 'aulas'}
          </Badge>
          {/* Alunos é CONTEXTO, não estado — por isso sem cor. Antes da 070
              este número saía quase igual ao de aulas em toda linha (a view tem
              uma linha por par aluno-aula); agora ele só se destaca quando há
              turma de verdade, que é quando informa alguma coisa. */}
          <Badge variant="neutro" icon="fa-solid fa-user-group">
            {p.alunos} {p.alunos === 1 ? 'aluno' : 'alunos'}
          </Badge>
          <Badge variant={tom} icon="fa-regular fa-clock">
            {p.pior_atraso} {p.pior_atraso === 1 ? 'dia' : 'dias'}
          </Badge>
        </div>

        <BotaoRecado professor={p} aviso={aviso} />
      </div>

      {aberto && (
        <div className="border-t border-border-subtle">
          <AulasEmAberto professorId={p.professor_id} />
        </div>
      )}
    </div>
  )
}
