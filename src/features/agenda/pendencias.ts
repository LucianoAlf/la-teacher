import { isSemVinculo, minhaAgendaSessao, type SessaoAula } from '../../lib/api'
import { addDias, hojeBRT } from '../../lib/date'
import { agruparSessoes, statusSessao } from './sessao'

export interface Pendencias {
  /** Data (YYYY-MM-DD) do dia com chamadas pendentes. */
  data: string
  sessoes: SessaoAula[]
}

/**
 * Pendências = chamadas de ONTEM ainda não enviadas e AINDA dentro da janela
 * (a chamada fecha 24h após a aula — mais velho que isso é 'perdida', vira
 * assunto da coordenação e não aparece como tarefa do professor).
 */
export async function buscarPendencias(): Promise<Pendencias | null> {
  const now = new Date()
  const ontem = addDias(hojeBRT(), -1)
  const res = await minhaAgendaSessao(ontem)
  if (isSemVinculo(res)) return null
  const pendentes = agruparSessoes(res).filter((s) => statusSessao(s, now) === 'pendente')
  return pendentes.length > 0 ? { data: ontem, sessoes: pendentes } : null
}

/**
 * Aulas de HOJE já começadas e ainda sem chamada enviada ('agora' ou
 * 'pendente') — busca independente da DateNav, pro alerta da Home sempre
 * falar de hoje, mesmo se o professor estiver olhando outro dia na tela.
 */
export async function buscarPendentesHoje(): Promise<SessaoAula[]> {
  const now = new Date()
  const res = await minhaAgendaSessao(hojeBRT())
  if (isSemVinculo(res)) return []
  return agruparSessoes(res).filter((s) => {
    const st = statusSessao(s, now)
    return st === 'agora' || st === 'pendente'
  })
}
