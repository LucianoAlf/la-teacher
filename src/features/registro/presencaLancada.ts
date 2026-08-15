/**
 * Presença JÁ lançada, na tela de registro.
 *
 * Regra da casa (Alf, 15/08/2026): quem dá presença é a SECRETARIA — lança no
 * Emusys / LA Report — e é a resposta dela que prevalece. O professor lança
 * CONTEÚDO. Quando a presença já está dada, ela aparece aqui com o carimbo de
 * quem lançou e o professor NÃO mexe; se discorda, fala com a secretaria e elas
 * corrigem na fonte.
 *
 * Antes disso a tela montava a presença só com o que o Fábio ouviu no áudio,
 * sem olhar o que já havia sido lançado — então o professor era obrigado a
 * "dar presença de novo", e o que ele mexia ali não valia nada (o banco,
 * corretamente, preservava a resposta da secretaria).
 *
 * Quem decide se está travada é o BANCO (`fn_presenca_fecha_chamada`, a régua
 * canônica: fonte humana forte OU emusys='presente'). Aqui a gente só lê o
 * veredito — nunca recalcula a régua no cliente.
 */

/** Só os campos que a RPC `app_registro_completo` acrescenta por fatia. */
export interface FatiaComPresenca {
  presenca_lancada?: string | null
  presenca_fonte?: string | null
  presenca_travada?: boolean | null
}

export interface PresencaLancada {
  /** true = o professor não edita a presença desta fatia. */
  travada: boolean
  /** O que mostrar no cabeçalho da fatia. */
  estado: 'presente' | 'faltou' | null
  /** De quem veio, em português — vai como selo ao lado do estado. */
  carimbo: string | null
}

const CARIMBO: Record<string, string> = {
  agenda_secretaria: 'Lançada pela secretaria',
  emusys: 'Lançada no Emusys',
  manual: 'Lançada pela coordenação',
  professor_la_teacher: 'Lançada por você',
  fabio_audio: 'Lançada por você',
  professor_whatsapp: 'Lançada por você',
}

export function lerPresencaLancada(fatia: FatiaComPresenca): PresencaLancada {
  // Sem trava, a tela segue como sempre foi: o professor declara a falta dele.
  // Não inventamos estado a partir de uma presença que não fecha a chamada — é
  // o caso do `ausente` do Emusys, ambíguo desde a migração.
  if (fatia.presenca_travada !== true) return { travada: false, estado: null, carimbo: null }

  const lancada = fatia.presenca_lancada
  const estado = lancada === 'presente' ? 'presente' : lancada ? 'faltou' : null
  if (estado === null) return { travada: false, estado: null, carimbo: null }

  return {
    travada: true,
    estado,
    carimbo: CARIMBO[fatia.presenca_fonte ?? ''] ?? 'Já lançada',
  }
}
