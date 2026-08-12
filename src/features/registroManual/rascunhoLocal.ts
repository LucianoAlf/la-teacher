import type { CamposManuais } from './modelo'

const DB_NOME = 'la-teacher'
const VERSAO_DB = 4
const STORE = 'rascunhos-manuais'
const STORE_AUDIO = 'fila-audios'

export interface CacheRascunhoManual {
  id: string
  ownerUserId: string
  aulaId: number
  registroId: string
  versao: number
  troncoCampos: Record<string, string>
  fatias: Array<{
    id: string
    alunoId: number
    alunoNome: string
    alunoFotoUrl?: string | null
    versao: number
    campos: CamposManuais
  }>
  atualizadoEm: string
  /** Cache é sempre transporte local; nunca significa persistência canônica. */
  estado: 'local'
}

export function chaveCacheManual(ownerUserId: string, aulaId: number): string {
  return `${ownerUserId}:${aulaId}`
}

export function normalizarCacheManual(item: Omit<CacheRascunhoManual, 'estado'> & { estado?: unknown }): CacheRascunhoManual {
  return { ...item, estado: 'local' }
}

function abrir(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NOME, VERSAO_DB)
    req.onupgradeneeded = () => {
      if (!req.result.objectStoreNames.contains(STORE_AUDIO)) {
        req.result.createObjectStore(STORE_AUDIO, { keyPath: 'id' })
      }
      if (!req.result.objectStoreNames.contains(STORE)) {
        req.result.createObjectStore(STORE, { keyPath: 'id' })
      }
    }
    req.onsuccess = () => resolve(req.result)
    req.onerror = () => reject(req.error ?? new Error('Não consegui abrir o rascunho local'))
    req.onblocked = () => reject(new Error('O rascunho local está aberto em outra aba'))
  })
}

function tx<T>(modo: IDBTransactionMode, fn: (store: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  return abrir().then((db) => new Promise<T>((resolve, reject) => {
    let resultado: T
    const transacao = db.transaction(STORE, modo)
    const req = fn(transacao.objectStore(STORE))
    req.onsuccess = () => { resultado = req.result }
    transacao.oncomplete = () => { db.close(); resolve(resultado) }
    transacao.onerror = () => { db.close(); reject(transacao.error ?? req.error) }
    transacao.onabort = () => { db.close(); reject(transacao.error ?? new Error('Rascunho local interrompido')) }
  }))
}

export async function salvarCacheManual(item: CacheRascunhoManual): Promise<void> {
  await tx('readwrite', (store) => store.put(normalizarCacheManual(item)))
}

export async function buscarCacheManual(ownerUserId: string, aulaId: number): Promise<CacheRascunhoManual | null> {
  const item = await tx('readonly', (store) => store.get(chaveCacheManual(ownerUserId, aulaId)) as IDBRequest<CacheRascunhoManual | undefined>)
  return item?.ownerUserId === ownerUserId ? normalizarCacheManual(item) : null
}

export async function removerCacheManual(ownerUserId: string, aulaId: number): Promise<void> {
  await tx('readwrite', (store) => store.delete(chaveCacheManual(ownerUserId, aulaId)))
}
