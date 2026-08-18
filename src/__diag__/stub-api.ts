// Dublê da camada de rede SÓ para o harness de diagnóstico (diag-tremida.html).
// A tela sob teste é a REAL (RegistroManual.tsx); só o que fala com o servidor
// é falso, para medir a tremida sem precisar de sessão de produção.
const ALUNOS = ['Ana Beatriz Lopes', 'Carlos Eduardo', 'Fernanda Souza']

let versao = 1
let chamadasSalvar = 0

function fatia(i: number) {
  return {
    id: `fatia-${i}`,
    aula_id: 999000 + i,
    aluno_id: 100 + i,
    aluno_nome: ALUNOS[i],
    aluno_foto_url: null,
    parent_id: 'tronco-1',
    audio_id: null,
    molde: 'C',
    campos: {},
    texto_consolidado: null,
    status: 'rascunho',
    origem: 'app',
    modo_entrada: 'manual',
    versao,
    criado_em: '2026-08-17T23:00:00Z',
  }
}

function pacote() {
  return {
    tronco: {
      id: 'tronco-1', aula_id: 999000, aluno_id: null, parent_id: null, audio_id: null,
      molde: 'C', campos: {}, texto_consolidado: null, status: 'rascunho',
      origem: 'app', modo_entrada: 'manual', versao, criado_em: '2026-08-17T23:00:00Z',
    },
    fatias: ALUNOS.map((_, i) => fatia(i)),
    aula: { curso: 'Violão', turma: 'T_Sá_13', data_aula: '2026-08-17', hora: '13:00' },
    modo_entrada: 'manual',
    audio_aberto_registro_id: null,
  }
}

export class ErroConflitoRascunho extends Error {
  constructor() { super('conflito_de_versao'); this.name = 'ErroConflitoRascunho' }
}

// Latência de rede configurável pela página (default 220ms, 4G ruim de sala).
declare global { interface Window { __diagLatencia?: number; __diagSalvar?: number } }

export async function abrirRascunhoManual(_aulaId: number) {
  await new Promise((r) => setTimeout(r, 50))
  return pacote() as never
}

export async function salvarRascunhoManual(
  _registroId: string, _versao: number,
  _troncoCampos: Record<string, string>,
  _fatias: Array<{ id: string; campos: Record<string, string> }>,
) {
  chamadasSalvar += 1
  window.__diagSalvar = chamadasSalvar
  await new Promise((r) => setTimeout(r, window.__diagLatencia ?? 220))
  // Interruptor do harness: com window.__diagConflito o servidor recusa por versao.
  if ((window as unknown as Record<string, unknown>).__diagConflito) throw new ErroConflitoRascunho()
  versao += 1
  return pacote() as never
}

export async function prepararRascunhoManual(_registroId: string, _versao: number) {
  await new Promise((r) => setTimeout(r, 120))
  return pacote() as never
}

