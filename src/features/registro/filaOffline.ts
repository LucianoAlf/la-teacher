import { useCallback, useEffect, useState } from 'react'
import { retryAutomaticoPermitido } from './camposCanonicos'

/**
 * Fila local de áudios (IndexedDB). O blob só sai daqui depois de enviado ou de
 * uma ação explícita do professor. Cada item novo pertence a uma conta única.
 */
export interface ItemFilaLocal {
  id: string
  /** Obrigatório nos itens novos; impede exibir ou reenviar áudio de outra conta. */
  ownerUserId: string
  aulaId: number
  /** Rótulo humano da aula (para a UI da fila). */
  aulaLabel: string
  blob: Blob
  mime: string
  duracaoSegundos: number
  /** Não nulo = correção por voz (modo complementar). */
  registroId?: string | null
  criadoEm: string
  /** Chave estável da intenção; novas entradas sempre a recebem antes do upload. */
  chaveIntencao?: string | null
  /** Caminho estável no Storage; só fica nulo em entradas legadas em quarentena. */
  storagePath?: string | null
  /** Mensagem real da última tentativa; não transforma erro permanente em offline. */
  ultimaFalha?: string | null
  tentativas?: number
  ultimaTentativaEm?: string | null
  /** Só é true quando a falha foi comprovadamente transitória. */
  retryAutomatico?: boolean
  /** O banco recusou o lançamento: preserve o Blob, mas nunca o reenvie. */
  falhaTerminal?: boolean
  /** Código bruto devolvido pela validação do motor, para suporte/auditoria. */
  codigoFalhaTerminal?: string | null
}

/** A versão anterior não tinha ownerUserId: esses blobs são preservados, mas não reutilizados. */
type ItemFilaPersistido = Omit<ItemFilaLocal, 'ownerUserId'> & { ownerUserId?: string | null }

const DB_NOME = 'la-teacher'
const STORE = 'fila-audios'
const VERSAO_DB = 4
export const EVENTO_FILA = 'la-teacher:fila-audios-mudou'

function normalizar(item: ItemFilaPersistido): ItemFilaPersistido {
  const falhaTerminal = item.falhaTerminal === true
  return {
    ...item,
    ownerUserId: typeof item.ownerUserId === 'string' && item.ownerUserId ? item.ownerUserId : null,
    chaveIntencao: item.chaveIntencao ?? null,
    storagePath: item.storagePath ?? null,
    ultimaFalha: item.ultimaFalha ?? null,
    tentativas: Math.max(0, item.tentativas ?? 0),
    ultimaTentativaEm: item.ultimaTentativaEm ?? null,
    // Entradas sem dono não carregam evidência suficiente para reenvio automático.
    retryAutomatico: falhaTerminal ? false : item.retryAutomatico === true,
    falhaTerminal,
    codigoFalhaTerminal: typeof item.codigoFalhaTerminal === 'string' ? item.codigoFalhaTerminal : null,
  }
}

/** Campos persistidos quando o motor recusa a intenção de forma definitiva. */
export function estadoTerminalFila({
  codigo,
  mensagem,
  tentativas,
}: {
  codigo: string
  mensagem: string
  tentativas?: number | null
}): Pick<ItemFilaLocal, 'codigoFalhaTerminal' | 'falhaTerminal' | 'retryAutomatico' | 'tentativas' | 'ultimaFalha'> {
  return {
    codigoFalhaTerminal: codigo,
    falhaTerminal: true,
    retryAutomatico: false,
    tentativas: Math.max(0, tentativas ?? 0) + 1,
    ultimaFalha: mensagem,
  }
}

/** Defesa em profundidade: estado terminal nunca pode acionar novo upload. */
export function itemPodeSerReenviado({ falhaTerminal }: Pick<ItemFilaLocal, 'falhaTerminal'>): boolean {
  return falhaTerminal !== true
}

function itemDoUsuario(item: ItemFilaPersistido | undefined, ownerUserId: string): ItemFilaLocal | null {
  if (!item) return null
  const normalizado = normalizar(item)
  return normalizado.ownerUserId === ownerUserId ? (normalizado as ItemFilaLocal) : null
}

function abrir(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NOME, VERSAO_DB)
    req.onupgradeneeded = () => {
      // IndexedDB armazena objetos sem schema por coluna. Não recriar o store
      // mantém cada Blob gravado pela v1; a v3 apenas acrescenta metadados.
      if (!req.result.objectStoreNames.contains(STORE)) {
        req.result.createObjectStore(STORE, { keyPath: 'id' })
      }
      // A v4 acrescenta o cache de transporte da ficha manual. Criar os dois
      // stores aqui também mantém instalações novas independentes da ordem em
      // que áudio ou caderno sejam abertos pela primeira vez.
      if (!req.result.objectStoreNames.contains('rascunhos-manuais')) {
        req.result.createObjectStore('rascunhos-manuais', { keyPath: 'id' })
      }
    }
    req.onsuccess = () => resolve(req.result)
    req.onerror = () => reject(req.error ?? new Error('Não consegui abrir a fila local'))
    req.onblocked = () => reject(new Error('A fila local está sendo usada por outra aba'))
  })
}

/**
 * Só confirma a operação depois de `transaction.oncomplete`: sucesso da
 * requisição não prova que a transação inteira foi persistida.
 */
function tx<T>(modo: IDBTransactionMode, fn: (store: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  return abrir().then(
    (db) =>
      new Promise<T>((resolve, reject) => {
        let resultado: T
        let erroDaRequisicao: DOMException | null = null
        let finalizado = false
        const fechar = () => db.close()
        const falhar = (erro: unknown) => {
          if (finalizado) return
          finalizado = true
          fechar()
          reject(erro)
        }

        let transacao: IDBTransaction
        try {
          transacao = db.transaction(STORE, modo)
          const requisicao = fn(transacao.objectStore(STORE))
          requisicao.onsuccess = () => {
            resultado = requisicao.result
          }
          requisicao.onerror = () => {
            erroDaRequisicao = requisicao.error
          }
        } catch (erro) {
          falhar(erro)
          return
        }

        transacao.oncomplete = () => {
          if (erroDaRequisicao) {
            falhar(erroDaRequisicao)
            return
          }
          if (finalizado) return
          finalizado = true
          fechar()
          resolve(resultado)
        }
        transacao.onerror = () => falhar(transacao.error ?? erroDaRequisicao ?? new Error('Falha na fila local'))
        transacao.onabort = () => falhar(transacao.error ?? erroDaRequisicao ?? new Error('Fila local interrompida'))
      }),
  )
}

function avisarMudanca() {
  window.dispatchEvent(new CustomEvent(EVENTO_FILA))
}

export async function salvarNaFila(item: ItemFilaLocal): Promise<void> {
  await tx('readwrite', (store) => store.put(normalizar(item)))
  avisarMudanca()
}

/** Itens legados sem ownerUserId ficam preservados no banco, mas em quarentena. */
export async function listarFila(ownerUserId: string): Promise<ItemFilaLocal[]> {
  const itens = await tx('readonly', (store) => store.getAll() as IDBRequest<ItemFilaPersistido[]>)
  return itens
    .map((item) => itemDoUsuario(item, ownerUserId))
    .filter((item): item is ItemFilaLocal => item !== null)
}

export async function buscarNaFila(id: string, ownerUserId: string): Promise<ItemFilaLocal | null> {
  const item = await tx('readonly', (store) => store.get(id) as IDBRequest<ItemFilaPersistido | undefined>)
  return itemDoUsuario(item, ownerUserId)
}

export async function atualizarItemFila(
  id: string,
  ownerUserId: string,
  campos: Partial<Omit<ItemFilaLocal, 'id' | 'ownerUserId'>>,
): Promise<ItemFilaLocal | null> {
  const item = await buscarNaFila(id, ownerUserId)
  if (!item) return null
  const atualizado: ItemFilaLocal = { ...item, ...campos, id: item.id, ownerUserId: item.ownerUserId }
  await salvarNaFila(atualizado)
  return atualizado
}

/** Registra a falha sem apagar o áudio e interrompe/permite o reenvio automático. */
export async function registrarFalhaFila(
  id: string,
  ownerUserId: string,
  { mensagem, transitoria }: { mensagem: string; transitoria: boolean },
): Promise<ItemFilaLocal | null> {
  const item = await buscarNaFila(id, ownerUserId)
  if (!item) return null
  if (!itemPodeSerReenviado(item)) return item
  const tentativas = (item.tentativas ?? 0) + 1
  return atualizarItemFila(id, ownerUserId, {
    ultimaFalha: mensagem,
    tentativas,
    ultimaTentativaEm: new Date().toISOString(),
    retryAutomatico: retryAutomaticoPermitido({ transitoria, tentativas }),
  })
}

/** Mantém o Blob após recusa semântica e bloqueia toda nova tentativa. */
export async function registrarFalhaTerminalFila(
  id: string,
  ownerUserId: string,
  { codigo, mensagem }: { codigo: string; mensagem: string },
): Promise<ItemFilaLocal | null> {
  const item = await buscarNaFila(id, ownerUserId)
  if (!item) return null
  return atualizarItemFila(id, ownerUserId, {
    ...estadoTerminalFila({ codigo, mensagem, tentativas: item.tentativas }),
    ultimaTentativaEm: new Date().toISOString(),
  })
}

/** Ação explícita: só a conta dona pode descartar o Blob local conscientemente. */
export async function descartarItemFila(id: string, ownerUserId: string): Promise<boolean> {
  const item = await buscarNaFila(id, ownerUserId)
  if (!item) return false
  await tx('readwrite', (store) => store.delete(id) as IDBRequest<undefined>)
  avisarMudanca()
  return true
}

/** @deprecated Use descartarItemFila para deixar claro que é uma ação humana. */
export const removerDaFila = descartarItemFila

export async function contarFila(ownerUserId: string): Promise<number> {
  return (await listarFila(ownerUserId)).length
}

/** Itens e recarga reativos, sempre filtrados pela sessão atual. */
export function useFilaOffline(ownerUserId: string | null | undefined): { itens: ItemFilaLocal[]; recarregar: () => void } {
  const [itens, setItens] = useState<ItemFilaLocal[]>([])
  const recarregar = useCallback(() => {
    if (!ownerUserId) {
      setItens([])
      return
    }
    void listarFila(ownerUserId).then(setItens).catch(() => setItens([]))
  }, [ownerUserId])

  useEffect(() => {
    recarregar()
    window.addEventListener(EVENTO_FILA, recarregar)
    return () => window.removeEventListener(EVENTO_FILA, recarregar)
  }, [recarregar])

  return { itens, recarregar }
}

/** Número de áudios da conta atual preservados localmente. */
export function useFilaOfflineCount(ownerUserId: string | null | undefined): number {
  return useFilaOffline(ownerUserId).itens.length
}
