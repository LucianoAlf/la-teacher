import { supabase } from '../../lib/supabase'
import {
  enfileirarAudio,
  enfileirarAudioExperimental,
  ERROS_AUDIO_EXPERIMENTAL,
  ERROS_GRAVACAO,
  ErroAudioExperimentalConhecido,
  ErroGravacaoConhecido,
  type EnfileirarResultado,
  type ErroAudioExperimental,
  type ErroGravacao,
} from '../../lib/api'
import { extensaoDoMime } from '../../lib/audio'
import { proximaTentativaAutomatica } from './camposCanonicos'
import {
  buscarNaFila,
  atualizarItemFila,
  descartarItemFila as descartarItemFilaPersistido,
  itemPodeSerReenviado,
  listarFila,
  registrarFalhaFila,
  registrarFalhaTerminalFila,
  salvarNaFila,
  type DestinoFila,
  type ItemFilaLocal,
} from './filaOffline'

const BUCKET = 'fabio-audios'

export interface DadosEnvio {
  aulaId: number
  aulaLabel: string
  blob: Blob
  mime: string
  duracaoSegundos: number
  /** Não nulo = correção por voz (modo complementar) do registro. */
  registroId?: string | null
}

export interface DadosEnvioExperimental {
  vinculoId: number
  aulaLabel: string
  blob: Blob
  mime: string
  duracaoSegundos: number
}

type DadosNovoItemFila = {
  id?: string
  ownerUserId: string
  aulaLabel: string
  blob: Blob
  mime: string
  duracaoSegundos: number
  chaveIntencao?: string
  destino: DestinoFila
}

export type AceiteFila =
  | { tipo: 'aula'; resultado: EnfileirarResultado }
  | { tipo: 'experimental'; audioId: string; vinculoId: number }

export type DestinoRetomadaExperimental = {
  tela: 'experimental'
  audioId: string
  vinculoId: number
}

export type ResultadoFila =
  | { ok: true; resultado: AceiteFila }
  | {
      ok: false
      mensagem: string
      retryAutomatico: boolean
      tentativas: number
      falhaTerminal?: boolean
      codigoFalhaTerminal?: string | null
    }

export type ResultadoEnvio =
  | { ok: true; resultado: EnfileirarResultado }
  | { ok: false; guardadoOffline: true; itemFilaId: string; mensagem: string; retryAutomatico: boolean; tentativas: number }
  | { ok: false; guardadoOffline: false; mensagem: string }
  /** Erro de validação (aula fora da janela etc.) — permanente, não vai pra fila. */
  | { ok: false; erroGravacao: ErroGravacao }

export type ResultadoEnvioExperimental =
  | { ok: true; audioId: string }
  | { ok: false; guardadoOffline: true; itemFilaId: string; mensagem: string; retryAutomatico: boolean; tentativas: number; erroGravacao?: ErroAudioExperimental }
  | { ok: false; guardadoOffline: false; mensagem: string }

/** Resultado explícito do descarte: nunca afirma remoção enquanto há upload em voo. */
export type ResultadoDescarteFila = { ok: true } | { ok: false; mensagem: string }

function mensagemDoErro(erro: unknown): string {
  if (erro instanceof Error && erro.message.trim()) return erro.message.trim()
  if (typeof erro === 'object' && erro && 'message' in erro && typeof erro.message === 'string' && erro.message.trim()) {
    return erro.message.trim()
  }
  return 'Falha desconhecida ao enviar o áudio'
}

/** Conservador: só rede/timeout comprováveis merecem retry automático. */
function falhaComprovadamenteTransitoria(erro: unknown): boolean {
  if (typeof navigator !== 'undefined' && navigator.onLine === false) return true
  const nome = erro instanceof Error ? erro.name : ''
  const mensagem = mensagemDoErro(erro).toLocaleLowerCase('pt-BR')
  if (nome === 'AbortError' || nome === 'TimeoutError') return true
  return /(^|\b)(network|offline|timeout|timed out|failed to fetch|fetch failed|econnreset|enotfound|socket)(\b|$)/i.test(mensagem)
}

async function usuarioDoUpload(): Promise<string> {
  const { data: sess } = await supabase.auth.getSession()
  const uid = sess.session?.user.id
  if (!uid) throw new Error('Sem sessão para enviar este áudio')
  return uid
}

/** Cria a intenção pura; quem chama a persiste antes de tocar no Storage. */
export function criarItemFilaLocal(dados: DadosNovoItemFila): ItemFilaLocal {
  const chaveIntencao = dados.chaveIntencao ?? crypto.randomUUID()
  const id = dados.id ?? crypto.randomUUID()
  const storagePath = dados.destino.tipo === 'experimental'
    ? `${dados.ownerUserId}/exp-${dados.destino.vinculoId}/${chaveIntencao}.${extensaoDoMime(dados.mime)}`
    : `${dados.ownerUserId}/${dados.destino.aulaId}/${chaveIntencao}.${extensaoDoMime(dados.mime)}`
  return {
    id,
    ownerUserId: dados.ownerUserId,
    destino: dados.destino,
    aulaLabel: dados.aulaLabel,
    blob: dados.blob,
    mime: dados.mime,
    duracaoSegundos: dados.duracaoSegundos,
    criadoEm: new Date().toISOString(),
    chaveIntencao,
    storagePath,
    ultimaFalha: null,
    tentativas: 0,
    ultimaTentativaEm: null,
    retryAutomatico: false,
  }
}

export type ClassificacaoFalhaFila =
  | { tipo: 'transitoria' }
  | { tipo: 'terminal'; codigo: ErroGravacao | ErroAudioExperimental }

/** A porta persistida decide como interpretar a recusa; texto humano nunca decide destino. */
export function classificarFalhaFila(item: Pick<ItemFilaLocal, 'destino'>, erro: unknown): ClassificacaoFalhaFila {
  if (item.destino.tipo === 'aula' && erro instanceof ErroGravacaoConhecido) {
    return { tipo: 'terminal', codigo: erro.codigo }
  }
  if (item.destino.tipo === 'experimental' && erro instanceof ErroAudioExperimentalConhecido) {
    return { tipo: 'terminal', codigo: erro.codigo }
  }
  const mensagem = mensagemDoErro(erro)
  const conhecidos = item.destino.tipo === 'experimental' ? ERROS_AUDIO_EXPERIMENTAL : ERROS_GRAVACAO
  const codigo = conhecidos.find((valor) => mensagem.includes(valor))
  return codigo
    ? { tipo: 'terminal', codigo }
    : { tipo: 'transitoria' }
}

/** Cria e persiste a identidade do envio antes de qualquer chamada de Storage. */
async function novoItemFila(dados: DadosEnvio | DadosEnvioExperimental): Promise<ItemFilaLocal> {
  const ownerUserId = await usuarioDoUpload()
  const destino: DestinoFila = 'vinculoId' in dados
    ? { tipo: 'experimental', vinculoId: dados.vinculoId }
    : { tipo: 'aula', aulaId: dados.aulaId, registroId: dados.registroId ?? null }
  return criarItemFilaLocal({ ...dados, ownerUserId, destino })
}

/** Novos caminhos sempre pertencem à mesma conta que criou o áudio. */
async function garantirIdentidadeDeUpload(item: ItemFilaLocal, ownerUserId: string): Promise<ItemFilaLocal> {
  if (item.ownerUserId !== ownerUserId) throw new Error('Esse áudio não pertence à sessão atual')
  if (item.storagePath && item.chaveIntencao) return item

  // Itens sem dono são quarentenados por filaOffline e nunca chegam aqui. Este
  // ramo só protege uma entrada nova interrompida antes de receber o caminho.
  const chaveIntencao = item.chaveIntencao ?? crypto.randomUUID()
  const storagePath = item.storagePath ?? (item.destino.tipo === 'experimental'
    ? `${ownerUserId}/exp-${item.destino.vinculoId}/${chaveIntencao}.${extensaoDoMime(item.mime)}`
    : `${ownerUserId}/${item.destino.aulaId}/${chaveIntencao}.${extensaoDoMime(item.mime)}`)
  const atualizado = await atualizarItemFila(item.id, ownerUserId, { chaveIntencao, storagePath })
  if (!atualizado) throw new Error('Esse áudio não está mais disponível nesta sessão')
  return atualizado
}

/**
 * Chama a porta determinada pela intenção já persistida. O reenvio nunca usa
 * rótulo de tela para decidir se é aula comum ou experimental.
 */
export async function enfileirarDestinoFila(
  item: ItemFilaLocal,
  deps: {
    enfileirarAula: typeof enfileirarAudio
    enfileirarExperimental: typeof enfileirarAudioExperimental
  } = { enfileirarAula: enfileirarAudio, enfileirarExperimental: enfileirarAudioExperimental },
): Promise<AceiteFila> {
  if (!item.storagePath) throw new Error('Áudio sem caminho de Storage')
  if (item.destino.tipo === 'experimental') {
    const resultado = await deps.enfileirarExperimental(
      item.destino.vinculoId,
      item.storagePath,
      item.duracaoSegundos,
    )
    return { tipo: 'experimental', audioId: resultado.audio_id, vinculoId: resultado.vinculo_id }
  }
  const resultado = await deps.enfileirarAula(
    item.destino.aulaId,
    item.storagePath,
    item.duracaoSegundos,
    item.destino.registroId,
  )
  return { tipo: 'aula', resultado }
}

/** Sobe e enfileira a intenção preservada; replay repete o mesmo objeto. */
async function subirEEnfileirar(item: ItemFilaLocal, ownerUserId: string): Promise<AceiteFila> {
  const pronto = await garantirIdentidadeDeUpload(item, ownerUserId)
  const { error: upErro } = await supabase.storage.from(BUCKET).upload(pronto.storagePath!, pronto.blob, {
    contentType: pronto.mime.split(';')[0] || 'audio/webm',
    // A deduplicação decisiva do enfileiramento por storage_path entra no 095
    // antes do deploy. O upsert só impede duplicar o objeto do Storage.
    upsert: true,
  })
  if (upErro) throw upErro
  return enfileirarDestinoFila(pronto)
}

export function destinoRetomadaFila(resultado: AceiteFila): DestinoRetomadaExperimental | null {
  return resultado.tipo === 'experimental'
    ? { tela: 'experimental', audioId: resultado.audioId, vinculoId: resultado.vinculoId }
    : null
}

/**
 * Evita que botão manual, timer e evento `online` processem o mesmo Blob em
 * paralelo. A guarda é por item e sempre é liberada em `finally`.
 */
const itensEmEnvio = new Set<string>()

let sincronizando = false
let listenerLigado = false
let ownerDaSincronizacao: string | null = null
let timerRetry: ReturnType<typeof setTimeout> | null = null
let timerRetryOwner: string | null = null
let timerRetryEm: number | null = null
let listenerOnline: (() => void) | null = null
let cicloDaSincronizacao = 0

function cancelarTimerRetry() {
  if (timerRetry !== null) clearTimeout(timerRetry)
  timerRetry = null
  timerRetryOwner = null
  timerRetryEm = null
}

/** Consome rejeições de trabalho disparado por eventos; a UI continua funcional. */
function executarEmSegundoPlano(promessa: Promise<unknown>): void {
  void promessa.catch(() => {
    // A fila já persiste a falha de upload. Falha de agendamento não pode virar
    // rejeição não tratada nem reativar uma sessão que já saiu do app.
  })
}

/** Agenda somente o primeiro áudio elegível, com backoff e sem duplicar timer. */
async function agendarProximoRetry(ownerUserId: string): Promise<void> {
  if (ownerDaSincronizacao !== ownerUserId) return
  if (typeof navigator !== 'undefined' && navigator.onLine === false) return

  const proximoEm = (await listarFila(ownerUserId))
    .map((item) => proximaTentativaAutomatica(item))
    .filter((quando): quando is number => quando !== null)
    .reduce<number | null>((maisCedo, quando) => (maisCedo === null || quando < maisCedo ? quando : maisCedo), null)

  if (proximoEm === null) {
    if (timerRetryOwner === ownerUserId) cancelarTimerRetry()
    return
  }
  if (timerRetry !== null && timerRetryOwner === ownerUserId && timerRetryEm === proximoEm) return

  cancelarTimerRetry()
  timerRetryOwner = ownerUserId
  timerRetryEm = proximoEm
  timerRetry = setTimeout(() => {
    timerRetry = null
    timerRetryOwner = null
    timerRetryEm = null
    if (ownerDaSincronizacao === ownerUserId) executarEmSegundoPlano(esvaziarFilaLocal(ownerUserId))
  }, Math.max(0, proximoEm - Date.now()))
}

/**
 * Persiste o áudio antes de tentar. Se falhar, o Blob fica intacto com erro
 * factual; só falhas transitórias entram no retry automático com backoff.
 */
export async function enviarAudio(dados: DadosEnvio): Promise<ResultadoEnvio> {
  let item: ItemFilaLocal
  try {
    item = await novoItemFila(dados)
    await salvarNaFila(item)
  } catch (erro) {
    return { ok: false, guardadoOffline: false, mensagem: mensagemDoErro(erro) }
  }

  itensEmEnvio.add(item.id)
  try {
    try {
      const aceite = await subirEEnfileirar(item, item.ownerUserId)
      if (aceite.tipo !== 'aula') throw new Error('Destino de fila incompatível com aula')
      await descartarItemFilaPersistido(item.id, item.ownerUserId)
      return { ok: true, resultado: aceite.resultado }
    } catch (erro) {
      if (erro instanceof ErroGravacaoConhecido) {
        await descartarItemFilaPersistido(item.id, item.ownerUserId)
        return { ok: false, erroGravacao: erro.codigo }
      }
      const atualizado = await registrarFalhaFila(item.id, item.ownerUserId, {
        mensagem: mensagemDoErro(erro),
        transitoria: falhaComprovadamenteTransitoria(erro),
      })
      if (!atualizado) return { ok: false, guardadoOffline: false, mensagem: 'Não consegui preservar o áudio localmente' }
      if (atualizado.retryAutomatico) executarEmSegundoPlano(agendarProximoRetry(item.ownerUserId))
      return {
        ok: false,
        guardadoOffline: true,
        itemFilaId: atualizado.id,
        mensagem: atualizado.ultimaFalha ?? 'Falha desconhecida ao enviar o áudio',
        retryAutomatico: atualizado.retryAutomatico === true,
        tentativas: atualizado.tentativas ?? 0,
      }
    }
  } finally {
    itensEmEnvio.delete(item.id)
  }
}

/**
 * A experimental usa exatamente o mesmo motor durável da aula comum. A diferença
 * está somente na porta autenticada que a intenção já gravou em `destino`.
 */
export async function enviarAudioExperimental(dados: DadosEnvioExperimental): Promise<ResultadoEnvioExperimental> {
  let item: ItemFilaLocal
  try {
    item = await novoItemFila(dados)
    await salvarNaFila(item)
  } catch (erro) {
    return { ok: false, guardadoOffline: false, mensagem: mensagemDoErro(erro) }
  }

  itensEmEnvio.add(item.id)
  try {
    try {
      const aceite = await subirEEnfileirar(item, item.ownerUserId)
      if (aceite.tipo !== 'experimental') throw new Error('Destino de fila incompatível com experimental')
      await descartarItemFilaPersistido(item.id, item.ownerUserId)
      return { ok: true, audioId: aceite.audioId }
    } catch (erro) {
      const classificacao = classificarFalhaFila(item, erro)
      if (classificacao.tipo === 'terminal') {
        const atualizado = await registrarFalhaTerminalFila(item.id, item.ownerUserId, {
          codigo: classificacao.codigo,
          mensagem: mensagemDoErro(erro),
        })
        return {
          ok: false,
          guardadoOffline: true,
          itemFilaId: atualizado?.id ?? item.id,
          mensagem: atualizado?.ultimaFalha ?? mensagemDoErro(erro),
          retryAutomatico: false,
          tentativas: atualizado?.tentativas ?? 1,
          erroGravacao: classificacao.codigo as ErroAudioExperimental,
        }
      }
      const atualizado = await registrarFalhaFila(item.id, item.ownerUserId, {
        mensagem: mensagemDoErro(erro),
        transitoria: falhaComprovadamenteTransitoria(erro),
      })
      if (!atualizado) return { ok: false, guardadoOffline: false, mensagem: 'Não consegui preservar o áudio localmente' }
      if (atualizado.retryAutomatico) executarEmSegundoPlano(agendarProximoRetry(item.ownerUserId))
      return {
        ok: false,
        guardadoOffline: true,
        itemFilaId: atualizado.id,
        mensagem: atualizado.ultimaFalha ?? 'Falha desconhecida ao enviar o áudio',
        retryAutomatico: atualizado.retryAutomatico === true,
        tentativas: atualizado.tentativas ?? 0,
      }
    }
  } finally {
    itensEmEnvio.delete(item.id)
  }
}

/** Ação explícita: tenta novamente um único áudio da conta autenticada. */
export async function tentarNovamenteItemFila(id: string, ownerUserId: string | null | undefined): Promise<ResultadoFila> {
  if (!ownerUserId) {
    return { ok: false, mensagem: 'Sua sessão não está disponível para reenviar este áudio', retryAutomatico: false, tentativas: 0 }
  }
  if (itensEmEnvio.has(id)) {
    return { ok: false, mensagem: 'Este áudio já está em uma ação; aguarde antes de tentar de novo', retryAutomatico: false, tentativas: 0 }
  }

  itensEmEnvio.add(id)
  try {
    const usuarioAtual = await usuarioDoUpload()
    if (usuarioAtual !== ownerUserId) {
      return { ok: false, mensagem: 'Sua sessão mudou; esse áudio não pode ser reenviado aqui', retryAutomatico: false, tentativas: 0 }
    }
    const item = await buscarNaFila(id, ownerUserId)
    if (!item) {
      return { ok: false, mensagem: 'Esse áudio não está disponível nesta sessão', retryAutomatico: false, tentativas: 0 }
    }
    if (!itemPodeSerReenviado(item)) {
      return {
        ok: false,
        mensagem: item.ultimaFalha ?? 'O motor recusou este lançamento',
        retryAutomatico: false,
        tentativas: item.tentativas ?? 0,
        falhaTerminal: true,
        codigoFalhaTerminal: item.codigoFalhaTerminal ?? null,
      }
    }

    try {
      const resultado = await subirEEnfileirar(item, ownerUserId)
      await descartarItemFilaPersistido(id, ownerUserId)
      return { ok: true, resultado }
    } catch (erro) {
      const mensagem = mensagemDoErro(erro)
      const classificacao = classificarFalhaFila(item, erro)
      if (classificacao.tipo === 'terminal') {
        const atualizado = await registrarFalhaTerminalFila(id, ownerUserId, {
          codigo: classificacao.codigo,
          mensagem,
        })
        return {
          ok: false,
          mensagem: atualizado?.ultimaFalha ?? mensagem,
          retryAutomatico: false,
          tentativas: atualizado?.tentativas ?? (item.tentativas ?? 0) + 1,
          falhaTerminal: true,
          codigoFalhaTerminal: atualizado?.codigoFalhaTerminal ?? classificacao.codigo,
        }
      }
      const atualizado = await registrarFalhaFila(id, ownerUserId, {
        mensagem,
        transitoria: falhaComprovadamenteTransitoria(erro),
      })
      if (atualizado?.retryAutomatico) executarEmSegundoPlano(agendarProximoRetry(ownerUserId))
      return {
        ok: false,
        mensagem,
        retryAutomatico: atualizado?.retryAutomatico === true,
        tentativas: atualizado?.tentativas ?? item.tentativas ?? 0,
      }
    }
  } finally {
    itensEmEnvio.delete(id)
  }
}

/**
 * Ação explícita de descarte. Ela usa exatamente o mesmo lock dos uploads: se
 * houver RPC em voo, o Blob não é removido e a UI recebe esse estado honesto.
 */
export async function descartarItemFila(id: string, ownerUserId: string | null | undefined): Promise<ResultadoDescarteFila> {
  if (!ownerUserId) return { ok: false, mensagem: 'Sua sessão não está disponível para descartar este áudio' }
  if (itensEmEnvio.has(id)) {
    return { ok: false, mensagem: 'Este áudio já está sendo enviado; aguarde a conclusão antes de descartá-lo. Nada foi removido.' }
  }

  itensEmEnvio.add(id)
  try {
    const usuarioAtual = await usuarioDoUpload()
    if (usuarioAtual !== ownerUserId) {
      return { ok: false, mensagem: 'Sua sessão mudou; esse áudio não pode ser descartado aqui' }
    }
    const descartado = await descartarItemFilaPersistido(id, ownerUserId)
    return descartado
      ? { ok: true }
      : { ok: false, mensagem: 'Esse áudio não está disponível nesta sessão' }
  } finally {
    itensEmEnvio.delete(id)
  }
}

// ---------------------------------------------------------------------------
// Sincronização em background da fila local
// ---------------------------------------------------------------------------

/** Tenta em background somente o item da sessão cuja hora de retry já chegou. */
export async function esvaziarFilaLocal(ownerUserId?: string): Promise<number> {
  const usuarioAtual = await usuarioDoUpload()
  if (ownerUserId && ownerUserId !== usuarioAtual) return 0
  const ownerAtual = usuarioAtual
  if (sincronizando) return 0
  sincronizando = true
  let enviados = 0
  try {
    const agora = Date.now()
    const itens = await listarFila(ownerAtual)
    for (const item of itens.sort((a, b) => a.criadoEm.localeCompare(b.criadoEm))) {
      const proximoEm = proximaTentativaAutomatica(item, agora)
      if (proximoEm === null || proximoEm > agora) continue

      const resultado = await tentarNovamenteItemFila(item.id, ownerAtual)
      if (resultado.ok) {
        enviados++
        continue
      }
      // Uma falha transitória já recebeu novo backoff; não martelar a fila toda.
      if (resultado.retryAutomatico) break
    }
  } finally {
    sincronizando = false
    if (ownerDaSincronizacao === ownerAtual) executarEmSegundoPlano(agendarProximoRetry(ownerAtual))
  }
  return enviados
}

/** Liga o reenvio automático apenas para a conta autenticada e seus próprios blobs. */
/** Desliga os recursos em segundo plano quando o professor sai do contexto autorizado. */
export function pararSincronizacaoFila(): void {
  cicloDaSincronizacao += 1
  ownerDaSincronizacao = null
  cancelarTimerRetry()
  if (listenerOnline) {
    window.removeEventListener('online', listenerOnline)
    listenerOnline = null
  }
  listenerLigado = false
}

export function iniciarSincronizacaoFila(): void {
  const ciclo = ++cicloDaSincronizacao
  void usuarioDoUpload()
    .then((ownerUserId) => {
      if (ciclo !== cicloDaSincronizacao) return
      if (ownerDaSincronizacao !== ownerUserId) {
        ownerDaSincronizacao = ownerUserId
        cancelarTimerRetry()
      }
      if (!listenerLigado) {
        listenerLigado = true
        listenerOnline = () => {
          const ownerAtual = ownerDaSincronizacao
          if (ownerAtual) executarEmSegundoPlano(agendarProximoRetry(ownerAtual))
        }
        window.addEventListener('online', listenerOnline)
      }
      executarEmSegundoPlano(esvaziarFilaLocal(ownerUserId))
    })
    .catch(() => {
      if (ciclo !== cicloDaSincronizacao) return
      // Sem sessão não existe conta autorizada para ler nem reenviar a fila.
      pararSincronizacaoFila()
    })
}
