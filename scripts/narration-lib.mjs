// Funções puras do cache de narração (testáveis sem rede).
import { createHash } from 'node:crypto';

// Muda quando a RECEITA de geração muda (não o texto) — invalida o cache sozinho.
// v2: break tag no fim + cauda aparada (a ElevenLabs cortava a última palavra).
// v3: aparação só do silêncio que vai até o fim (a v2 decepava frase no meio).
// v4: SEM break tag no texto (o modelo vocalizava a tag e virava ruído);
//     o silêncio da cauda passou a ser digital, por apad, depois da geração.
// v5: modelo eleven_turbo_v2_5 (o v2 atropelava a fala).
export const GEN_VERSION = 'v5';

export function hashText(text) {
  return createHash('sha1').update(`${GEN_VERSION}|${String(text)}`, 'utf-8').digest('hex').slice(0, 8);
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
