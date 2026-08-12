/** Helpers puros para a UI não inventar uma segunda fonte de verdade. */

function textoNormalizado(texto: string | null | undefined): string {
  return (texto ?? '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLocaleLowerCase('pt-BR')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
    .replace(/\s+/g, ' ')
}

/** Nunca repete o mesmo erro de rede indefinidamente em segundo plano. */
export const LIMITE_TENTATIVAS_AUTOMATICAS = 3
/** Primeira e segunda novas tentativas, depois o áudio pede decisão humana. */
export const RETRY_AUTOMATICO_ATRASOS_MS = [15_000, 60_000] as const

/**
 * O contador inclui a tentativa que acabou de falhar. Ao atingir o teto, o
 * áudio continua preservado, mas só uma ação explícita do professor tenta de
 * novo. Esta função não decide se um erro é transitório — isso é evidência do
 * transporte, fora da UI.
 */
export function retryAutomaticoPermitido({
  transitoria,
  tentativas,
}: {
  transitoria: boolean
  tentativas: number | null | undefined
}): boolean {
  return transitoria && Math.max(0, tentativas ?? 0) < LIMITE_TENTATIVAS_AUTOMATICAS
}

/**
 * Horário da próxima tentativa automática. `null` significa que o áudio não
 * deve ser reenviado em segundo plano: ele fica preservado para decisão humana.
 */
export function proximaTentativaAutomatica(
  {
    retryAutomatico,
    tentativas,
    ultimaTentativaEm,
  }: {
    retryAutomatico?: boolean | null
    tentativas?: number | null
    ultimaTentativaEm?: string | null
  },
  agoraEmMs = Date.now(),
): number | null {
  const quantidade = Math.max(0, tentativas ?? 0)
  if (!retryAutomatico || !retryAutomaticoPermitido({ transitoria: true, tentativas: quantidade })) return null

  const indice = Math.min(Math.max(quantidade - 1, 0), RETRY_AUTOMATICO_ATRASOS_MS.length - 1)
  const atraso = RETRY_AUTOMATICO_ATRASOS_MS[indice]
  const ultimaEmMs = ultimaTentativaEm ? Date.parse(ultimaTentativaEm) : Number.NaN
  const base = Number.isFinite(ultimaEmMs) ? ultimaEmMs : agoraEmMs
  return Math.max(agoraEmMs, base + atraso)
}

/** Compara texto só para evitar repetição visual, nunca para decidir escrita. */
export function textoEquivalente(a: string | null | undefined, b: string | null | undefined): boolean {
  const normalizadoA = textoNormalizado(a)
  const normalizadoB = textoNormalizado(b)
  return Boolean(normalizadoA) && normalizadoA === normalizadoB
}

/** Repertório individual só acrescenta informação se não duplicar o da turma. */
export function repertorioIndividualVisivel(
  repertorioTurma: string | null | undefined,
  repertorioIndividual: string | null | undefined,
): boolean {
  return Boolean(textoNormalizado(repertorioIndividual)) && !textoEquivalente(repertorioTurma, repertorioIndividual)
}

/** Nome curto do header, já com a precedência resolvida por quem chama. */
export function nomeCabecalho({ nome, email }: { nome?: string | null; email?: string | null }): string {
  const nomeLimpo = nome?.trim()
  if (nomeLimpo) return nomeLimpo.split(/\s+/)[0]

  const local = email?.trim().split('@')[0]?.split(/[._-]/)[0]
  if (!local) return 'Professor'
  return local.charAt(0).toLocaleUpperCase('pt-BR') + local.slice(1)
}

/** Estado do relatório na agenda, sem confundir rascunho com aula confirmada. */
export function rotuloRegistro({
  temRegistro,
  temRascunho,
}: {
  temRegistro: boolean
  temRascunho?: boolean
}): 'Registrada' | 'Rascunho pronto' | 'Sem registro' {
  if (temRascunho) return 'Rascunho pronto'
  if (temRegistro) return 'Registrada'
  return 'Sem registro'
}

/** Texto direto para a fila: sem transformar uma falha real em "sem conexão". */
export function descreverFalhaFila({
  ultimaFalha,
  tentativas,
}: {
  ultimaFalha?: string | null
  tentativas?: number | null
}): string {
  const quantidade = Math.max(0, tentativas ?? 0)
  const sufixo = quantidade === 1 ? '1 tentativa' : `${quantidade} tentativas`
  const esperaDecisao = quantidade >= LIMITE_TENTATIVAS_AUTOMATICAS ? ' · aguarda sua decisão' : ''
  return ultimaFalha?.trim() ? `${ultimaFalha.trim()} · ${sufixo}${esperaDecisao}` : `${sufixo}${esperaDecisao}`
}

/**
 * Impressão SHA-256 estável da intenção de editar uma devolutiva. Ela permite
 * guardar somente a chave de idempotência no navegador — nunca o texto
 * pedagógico, nem o motivo em claro. O banco continua sendo o árbitro auditado.
 */
export async function assinaturaIntencaoDevolutiva({
  devolutivaId,
  textoNormal,
  textoApoioCasa,
  motivo,
}: {
  devolutivaId: string
  textoNormal: string
  textoApoioCasa: string
  motivo: string
}): Promise<string> {
  const fonte = [devolutivaId, textoNormal.trim(), textoApoioCasa.trim(), motivo.trim()]
    .map((valor) => `${valor.length}:${valor}`)
    .join('\u001f')
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(fonte))
  return `v1-${Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('')}`
}
