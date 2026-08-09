/**
 * Extensão de arquivo a partir do mime type.
 *
 * Mora em `lib/` porque três lugares precisam dela e eles estão em camadas
 * diferentes: o upload do registro de aula, o upload da experimental e a
 * transcrição da observação (`api.ts`). Antes vivia em
 * `features/registro/useRecorder.ts` e a `api.ts` não podia importar de lá
 * sem inverter a camada — foi por isso que a transcrição acabou com o nome
 * `observacao.webm` cravado no código, e o iPhone parou de funcionar.
 *
 * POR QUE ISSO IMPORTA: o Whisper decide o decoder pela EXTENSÃO do arquivo,
 * não pelo Content-Type. O iOS/Safari não grava webm — grava `audio/mp4`. Um
 * m4a chamado `.webm` chega como arquivo corrompido e a transcrição falha em
 * 100% dos iPhones.
 */
export function extensaoDoMime(mime: string): string {
  const m = (mime || '').toLowerCase()
  if (m.includes('mp4') || m.includes('m4a') || m.includes('aac')) return 'm4a'
  if (m.includes('webm')) return 'webm'
  if (m.includes('ogg') || m.includes('oga') || m.includes('opus')) return 'ogg'
  if (m.includes('wav')) return 'wav'
  if (m.includes('flac')) return 'flac'
  if (m.includes('mpeg') || m.includes('mp3')) return 'mp3'
  return 'webm'
}
