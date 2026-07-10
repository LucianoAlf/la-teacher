// Utilitários de data em BRT (America/Sao_Paulo). O app do professor pensa
// sempre no fuso de Brasília, independente do relógio do dispositivo.

const TZ = 'America/Sao_Paulo'
const DIAS = ['domingo', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado']
const DIAS_CURTO = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb']
const MESES = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
]

/** Data de hoje em BRT como 'YYYY-MM-DD'. */
export function hojeBRT(): string {
  // en-CA formata como ISO (YYYY-MM-DD).
  return new Intl.DateTimeFormat('en-CA', { timeZone: TZ }).format(new Date())
}

function parse(iso: string): { y: number; m: number; d: number } {
  const [y, m, d] = iso.split('-').map(Number)
  return { y, m, d }
}

/** Soma n dias a uma data 'YYYY-MM-DD' (n pode ser negativo). Volta 'YYYY-MM-DD'. */
export function addDias(iso: string, n: number): string {
  const { y, m, d } = parse(iso)
  const t = new Date(Date.UTC(y, m - 1, d) + n * 86_400_000)
  const mm = String(t.getUTCMonth() + 1).padStart(2, '0')
  const dd = String(t.getUTCDate()).padStart(2, '0')
  return `${t.getUTCFullYear()}-${mm}-${dd}`
}

function diaSemana(iso: string): number {
  const { y, m, d } = parse(iso)
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay()
}

/** "Segunda, 6 de julho de 2026". */
export function formatExtenso(iso: string): string {
  const { d, m, y } = parse(iso)
  const dia = DIAS[diaSemana(iso)]
  const cap = dia.charAt(0).toUpperCase() + dia.slice(1)
  return `${cap}, ${d} de ${MESES[m - 1]} de ${y}`
}

/** "Qui, 02/07". */
export function formatDiaCurto(iso: string): string {
  const { d, m } = parse(iso)
  return `${DIAS_CURTO[diaSemana(iso)]}, ${String(d).padStart(2, '0')}/${String(m).padStart(2, '0')}`
}

/** "15:00:00" → "15h"; "15:30:00" → "15:30". */
export function formatHoraBRT(time: string | null | undefined): string {
  if (!time) return '--'
  const [h, mm] = time.split(':')
  return mm === '00' ? `${Number(h)}h` : `${Number(h)}:${mm}`
}

/** Timestamp ISO (timestamptz) → data 'YYYY-MM-DD' em BRT. */
export function dataBRTDoTimestamp(iso: string): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: TZ }).format(new Date(iso))
}

/** Timestamp ISO (timestamptz) → "HH:MM" em BRT. */
export function formatHoraTimestampBRT(iso: string | null | undefined): string {
  if (!iso) return '--'
  return new Intl.DateTimeFormat('pt-BR', { timeZone: TZ, hour: '2-digit', minute: '2-digit' }).format(new Date(iso))
}

export function isHoje(iso: string): boolean {
  return iso === hojeBRT()
}

/** Segunda-feira da semana que contém `iso` (semana começa na segunda). */
export function inicioSemana(iso: string): string {
  const offset = (diaSemana(iso) + 6) % 7 // 0 se já é segunda
  return addDias(iso, -offset)
}

/** Os 7 dias (segunda→domingo) da semana que contém `iso`. */
export function diasDaSemana(iso: string): string[] {
  const seg = inicioSemana(iso)
  return Array.from({ length: 7 }, (_, i) => addDias(seg, i))
}

/** Letra do dia da semana (S T Q Q S S D) para strip compacta. */
export function inicialDiaSemana(iso: string): string {
  return ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'][diaSemana(iso)]
}

/** Dia do mês (1-31). */
export function diaDoMes(iso: string): number {
  return parse(iso).d
}
