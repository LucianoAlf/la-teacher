import { useState } from 'react'
import { Avatar, Badge } from '../../../components/ui'
import { BotaoRecado } from './BotaoRecado'
import { AulasEmAberto } from './AulasEmAberto'
import type { FiltroPainel } from './FiltrosPainel'
import type { CoordenacaoLinha } from '../../../lib/api'

/** Atraso a partir do qual o caso vira "não pode esperar". */
export const ATRASO_URGENTE = 3

/** Quantos cursos cabem antes de a legenda virar parede. */
const CURSOS_VISIVEIS = 3

/**
 * "Canto, Canto IND, Musicalização Infantil +5".
 *
 * A Leticia dá oito cursos: a lista inteira estourava a linha e o navegador
 * cortava com reticências, o que esconde a CONTAGEM. Dizer "+5" informa que
 * tem mais; "…" só informa que não coube.
 */
function resumirCursos(cursos: string | null): string | null {
  if (!cursos) return null
  const lista = cursos.split(', ').filter(Boolean)
  if (lista.length <= CURSOS_VISIVEIS) return cursos
  return `${lista.slice(0, CURSOS_VISIVEIS).join(', ')} +${lista.length - CURSOS_VISIVEIS}`
}

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
 *
 * `filtro` desce até aqui só pra chegar no `AulasEmAberto`: o expandir precisa
 * ver o MESMO recorte que gerou o selo da linha.
 */
export function LinhaProfessor({
  p,
  filtro,
  aviso,
}: {
  p: CoordenacaoLinha
  filtro: FiltroPainel
  aviso: (m: string) => void
}) {
  const [aberto, setAberto] = useState(false)
  const urgente = p.pior_atraso >= ATRASO_URGENTE
  const tom = urgente ? 'danger' : 'warn'

  const legenda = [p.unidades, resumirCursos(p.cursos)].filter(Boolean).join(' · ')

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

        {/* Todo selo desta linha mede o MESMO recorte: a pendência da janela.
            O de alunos diz "afetados" por escrito porque foi lido como
            carteira — o Alf viu "22 alunos" no Gabriel Antony (36 na carteira)
            e achou o número errado. Número certo com rótulo ambíguo É defeito. */}
        <div className="flex flex-none items-center gap-1.5">
          <Badge
            variant={tom}
            icon="fa-solid fa-clipboard-list"
            title="Aulas dos últimos 7 dias ainda sem lançamento"
          >
            {p.aulas} {p.aulas === 1 ? 'aula em aberto' : 'aulas em aberto'}
          </Badge>
          {/* Alunos é CONTEXTO, não estado — por isso sem cor. Só se destaca
              de "aulas" quando há turma, que é quando informa alguma coisa. */}
          <Badge
            variant="neutro"
            icon="fa-solid fa-user-group"
            title="Alunos com aula sem lançamento na janela — não é a carteira do professor"
          >
            {p.alunos} {p.alunos === 1 ? 'aluno afetado' : 'alunos afetados'}
          </Badge>
          <Badge
            variant={tom}
            icon="fa-regular fa-clock"
            title="Há quantos dias a aula mais antiga espera lançamento"
          >
            {p.pior_atraso} {p.pior_atraso === 1 ? 'dia parado' : 'dias parado'}
          </Badge>
        </div>

        <BotaoRecado professor={p} aviso={aviso} />
      </div>

      {aberto && (
        <div className="border-t border-border-subtle">
          <AulasEmAberto professorId={p.professor_id} filtro={filtro} />
        </div>
      )}
    </div>
  )
}
