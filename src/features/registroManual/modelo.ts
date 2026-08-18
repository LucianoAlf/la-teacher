export const CAMPOS_MANUAIS = [
  'repertorio',
  'atividades',
  'objetivo',
  'observacao',
  'dever_casa',
  'progresso',
] as const

export type CampoManual = (typeof CAMPOS_MANUAIS)[number]
export type CamposManuais = Partial<Record<CampoManual, string>>

export interface FatiaManual {
  id: string
  alunoId: number
  alunoNome: string
  alunoFotoUrl?: string | null
  versao: number
  campos: CamposManuais
}

export interface OperacaoCopia {
  origemId: string
  destinos: string[]
  campos: CampoManual[]
}

export interface SobrescritaManual {
  destinoId: string
  destinoNome: string
  campos: CampoManual[]
}

export function limparCamposManuais(campos: Record<string, unknown>): CamposManuais {
  return CAMPOS_MANUAIS.reduce<CamposManuais>((resultado, chave) => {
    const valor = campos[chave]
    if (typeof valor === 'string') resultado[chave] = valor
    return resultado
  }, {})
}

export function detectarSobrescritas(
  fatias: FatiaManual[],
  operacao: OperacaoCopia,
): SobrescritaManual[] {
  const origem = fatias.find((fatia) => fatia.id === operacao.origemId)
  if (!origem) return []
  const campos = operacao.campos.filter((chave) => CAMPOS_MANUAIS.includes(chave))
  const destinos = new Set(operacao.destinos)

  return fatias.flatMap((fatia) => {
    if (fatia.id === origem.id || !destinos.has(fatia.id)) return []
    const preenchidos = campos.filter((chave) => {
      const atual = fatia.campos[chave]?.trim()
      const novo = origem.campos[chave]?.trim()
      return Boolean(atual && novo && atual !== novo)
    })
    return preenchidos.length > 0
      ? [{ destinoId: fatia.id, destinoNome: fatia.alunoNome, campos: preenchidos }]
      : []
  })
}

export function aplicarCopia(fatias: FatiaManual[], operacao: OperacaoCopia): FatiaManual[] {
  const origem = fatias.find((fatia) => fatia.id === operacao.origemId)
  if (!origem) return fatias
  const destinos = new Set(operacao.destinos)
  const campos = operacao.campos.filter((chave) => CAMPOS_MANUAIS.includes(chave))

  return fatias.map((fatia) => {
    const atuais = limparCamposManuais(fatia.campos as Record<string, unknown>)
    if (fatia.id === origem.id || !destinos.has(fatia.id)) return { ...fatia, campos: atuais }
    const novos = { ...atuais }
    for (const chave of campos) {
      const valor = origem.campos[chave]
      // Copiar serve para reaproveitar conteúdo comum, nunca para apagar o que
      // já foi digitado em outro aluno por causa de um campo vazio na origem.
      if (valor?.trim()) novos[chave] = valor
    }
    return { ...fatia, campos: novos }
  })
}

export function contarDiferencasRascunho(
  troncoLocal: Record<string, string>,
  troncoServidor: Record<string, string>,
  fatiasLocais: FatiaManual[],
  fatiasServidor: FatiaManual[],
): number {
  const chavesTronco = new Set([...Object.keys(troncoLocal), ...Object.keys(troncoServidor)])
  let total = [...chavesTronco].filter((chave) =>
    (troncoLocal[chave] ?? '').trim() !== (troncoServidor[chave] ?? '').trim()).length
  const servidorPorId = new Map(fatiasServidor.map((fatia) => [fatia.id, fatia]))

  for (const local of fatiasLocais) {
    const servidor = servidorPorId.get(local.id)
    if (!servidor) {
      total += CAMPOS_MANUAIS.filter((chave) => Boolean(local.campos[chave]?.trim())).length
      continue
    }
    total += CAMPOS_MANUAIS.filter((chave) =>
      (local.campos[chave] ?? '').trim() !== (servidor.campos[chave] ?? '').trim()).length
  }
  return total
}

export function mesclarCacheComRoster(
  fatiasLocais: FatiaManual[],
  fatiasServidor: FatiaManual[],
): FatiaManual[] {
  const localPorId = new Map(fatiasLocais.map((fatia) => [fatia.id, fatia]))
  return fatiasServidor.map((servidor) => {
    const local = localPorId.get(servidor.id)
    return local ? { ...servidor, campos: limparCamposManuais(local.campos as Record<string, unknown>) } : servidor
  })
}

/** Estados do selo de salvamento do caderno manual. */
export type EstadoSalvamento = 'salvo' | 'salvando' | 'local' | 'nao_salvo' | 'conflito'

/**
 * Para onde o selo vai quando o professor digita — o estado ANTERIOR manda.
 *
 * Uma tecla quase nunca é notícia nova. Antes, toda tecla publicava
 * `nao_salvo` e o gravador local devolvia `local` ~1ms depois: medido no
 * harness, 37 teclas viravam 76 trocas no cabeçalho, o rótulo pulando entre
 * 71,7px ("Não salvo") e 109px ("Só neste aparelho"). Era a tremida.
 *
 * - `local` fica: o texto JÁ está guardado neste aparelho; digitar mais não
 *   desfaz isso, e re-anunciar é só barulho.
 * - `conflito` fica: é uma decisão que o professor ainda deve ("usar servidor"
 *   ou "manter o que digitei"). Apagar por causa de uma tecla escondia os dois
 *   botões, destravava o "Revisar e confirmar" e fazia a página pular.
 * - o resto (`salvo`, `salvando`) vira `nao_salvo`: aí a notícia mudou de
 *   verdade — saiu do que estava no servidor.
 */
export function seloAoEditar(atual: EstadoSalvamento): EstadoSalvamento {
  if (atual === 'local' || atual === 'conflito') return atual
  return 'nao_salvo'
}

/**
 * Para onde o selo vai quando o gravador local (IndexedDB) devolve resposta.
 *
 * Esta é a SEGUNDA porta que publica estado a cada tecla, e consertar só a
 * síncrona não bastou: medido no harness em 18/08/2026, com o conflito na tela
 * uma única tecla ainda apagava o banner por aqui — junto com os dois botões de
 * decisão e a trava do "Revisar e confirmar".
 *
 * `conflito` manda em cima de tudo enquanto o professor não decidir. O resto é
 * o que já era: guardou → `local`; não guardou → `nao_salvo`.
 */
export function seloAoGuardarLocal(atual: EstadoSalvamento, guardado: boolean): EstadoSalvamento {
  if (atual === 'conflito') return 'conflito'
  return guardado ? 'local' : 'nao_salvo'
}
