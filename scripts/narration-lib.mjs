// Funções puras do cache de narração (testáveis sem rede).
import { createHash } from 'node:crypto';

export function hashText(text) {
  return createHash('sha1').update(String(text), 'utf-8').digest('hex').slice(0, 8);
}

export function audioFileName(sceneId, text) {
  return `${sceneId}.${hashText(text)}.mp3`;
}

/** cenas: [{id, narracao}] · existing: nomes .mp3 no diretório.
 *  → {keep: string[], generate: [{id, narracao, file}], stale: string[]} */
export function planFiles(cenas, existing) {
  const wanted = new Map(cenas.map(c => [audioFileName(c.id, c.narracao), c]));
  const keep = existing.filter(f => wanted.has(f));
  const keepSet = new Set(keep);
  const generate = [...wanted.entries()]
    .filter(([file]) => !keepSet.has(file))
    .map(([file, c]) => ({ id: c.id, narracao: c.narracao, file }));
  const stale = existing.filter(f => !wanted.has(f));
  return { keep, generate, stale };
}
