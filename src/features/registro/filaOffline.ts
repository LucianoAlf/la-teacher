import { useEffect, useState } from 'react'

/**
 * Fila local de áudios (IndexedDB) — offline-first.
 * Gravou sem rede? O blob + metadados ficam aqui até a conexão voltar;
 * o uploader (uploadAudio.iniciarSincronizacaoFila) esvazia sozinho.
 */

export interface ItemFilaLocal {
  id: string
  aulaId: number
  /** Rótulo humano da aula (pra UI da fila). */
  aulaLabel: string
  blob: Blob
  mime: string
  duracaoSegundos: number
  criadoEm: string
}

const DB_NOME = 'la-teacher'
const STORE = 'fila-audios'
export const EVENTO_FILA = 'la-teacher:fila-audios-mudou'

function abrir(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NOME, 1)
    req.onupgradeneeded = () => {
      if (!req.result.objectStoreNames.contains(STORE)) {
        req.result.createObjectStore(STORE, { keyPath: 'id' })
      }
    }
    req.onsuccess = () => resolve(req.result)
    req.onerror = () => reject(req.error)
  })
}

function tx<T>(modo: IDBTransactionMode, fn: (store: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  return abrir().then(
    (db) =>
      new Promise<T>((resolve, reject) => {
        const t = db.transaction(STORE, modo)
        const req = fn(t.objectStore(STORE))
        req.onsuccess = () => resolve(req.result)
        req.onerror = () => reject(req.error)
        t.oncomplete = () => db.close()
      }),
  )
}

function avisarMudanca() {
  window.dispatchEvent(new CustomEvent(EVENTO_FILA))
}

export async function salvarNaFila(item: ItemFilaLocal): Promise<void> {
  await tx('readwrite', (s) => s.put(item))
  avisarMudanca()
}

export function listarFila(): Promise<ItemFilaLocal[]> {
  return tx('readonly', (s) => s.getAll() as IDBRequest<ItemFilaLocal[]>)
}

export async function removerDaFila(id: string): Promise<void> {
  await tx('readwrite', (s) => s.delete(id))
  avisarMudanca()
}

export function contarFila(): Promise<number> {
  return tx('readonly', (s) => s.count())
}

/** Nº de áudios aguardando conexão (reativo — atualiza no evento da fila). */
export function useFilaOfflineCount(): number {
  const [count, setCount] = useState(0)
  useEffect(() => {
    let vivo = true
    const atualizar = () => contarFila().then((n) => vivo && setCount(n)).catch(() => {})
    atualizar()
    window.addEventListener(EVENTO_FILA, atualizar)
    return () => {
      vivo = false
      window.removeEventListener(EVENTO_FILA, atualizar)
    }
  }, [])
  return count
}
