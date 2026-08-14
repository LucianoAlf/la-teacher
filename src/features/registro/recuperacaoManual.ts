import { limparCamposManuais, type CamposManuais } from '../registroManual/modelo'

/**
 * Resiliência do registro manual na tela de confirmação ("Confere aí").
 *
 * O Caderno já guarda cada edição no IndexedDB e recupera; a tela de
 * confirmação não guardava nada — numa conexão ruim, o save falhava e o texto
 * do professor ficava só na tela e sumia ao sair. Estes ajudantes puros são o
 * miolo do conserto: montar o cache local (no MESMO formato do Caderno) e
 * recuperar o texto local que não sincronizou sem apagar o que veio do servidor.
 */

/** Uma fatia como a tela de confirmação a enxerga (vinda de app_registro_completo). */
export interface FatiaConfirmar {
  id: string
  aluno_id?: number | null
  aluno_nome?: string | null
  aluno_foto_url?: string | null
  versao?: number
  campos: Record<string, unknown>
}

/** Uma fatia no formato do cache local do Caderno (rascunhoLocal.ts). */
export interface FatiaCache {
  id: string
  alunoId: number
  alunoNome: string
  alunoFotoUrl?: string | null
  versao: number
  campos: CamposManuais
}

/**
 * Mapeia uma fatia da confirmação para o formato do cache local, guardando só
 * os campos pedagógicos (via limparCamposManuais) — assim o cache é o MESMO que
 * o Caderno lê, e a recuperação funciona entre as duas telas.
 */
export function montarFatiaCache(fatia: FatiaConfirmar): FatiaCache {
  return {
    id: fatia.id,
    alunoId: fatia.aluno_id ?? 0,
    alunoNome: fatia.aluno_nome ?? 'Aluno',
    alunoFotoUrl: fatia.aluno_foto_url ?? null,
    versao: fatia.versao ?? 1,
    campos: limparCamposManuais(fatia.campos),
  }
}

/**
 * Na recuperação, o texto local (cache) que ainda não sincronizou VENCE o do
 * servidor — senão a gente re-perde o que o professor digitou. Os campos que só
 * o servidor tem (ex.: presença aplicada no confirmar) permanecem.
 */
export function recuperarCamposFatia(
  camposServidor: Record<string, unknown>,
  camposLocais: Record<string, unknown>,
): Record<string, unknown> {
  return { ...camposServidor, ...camposLocais }
}
