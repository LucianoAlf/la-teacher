import { supabase } from './supabase'
import { SOMENTE_LEITURA } from './config'

/**
 * Camada de dados do app: SOMENTE wrappers das RPCs app_*.
 * Proibido `supabase.from('tabela')` em qualquer lugar do cliente —
 * a segurança é resolvida no banco via auth.uid() (ver 001-fundacao-fabio.sql).
 */

/** Erro que a RPC devolve quando o usuário logado não tem professor vinculado. */
export const SEM_VINCULO = 'sem_professor_vinculado' as const

export type RpcErro = { erro: string }

export function isSemVinculo(v: unknown): v is RpcErro {
  return typeof v === 'object' && v !== null && (v as RpcErro).erro === SEM_VINCULO
}

// ---- Agenda por SESSÃO (contrato v4 — app_minha_agenda_sessao) ----
// O banco devolve 1 sessão POR AULA CRUA do espelho, com o roster embutido
// (aula_alunos_emusys) + presença lançada + justificativa administrativa.
// O agrupamento "1 aula real = 1 linha" (regra do contrato v3) é refeito no
// cliente por agruparSessoes() — ver src/features/agenda/sessao.ts.

export interface AlunoSessao {
  /** null = aluno do roster ainda NÃO conciliado (bloqueia a chamada). */
  aluno_id: number | null
  nome: string
  /** Presença lançada. 'a_confirmar' = chamada ainda não feita. */
  presenca: 'presente' | 'falta' | 'a_confirmar'
  /**
   * true = presença deste aluno lançada por FONTE FORTE (professor_la_teacher /
   * fabio_audio / manual / professor_whatsapp) — chamada REAL, não o default do
   * Emusys. Fonte de verdade do selo "chamada feita" (Fase 2 — selo honesto).
   */
  tem_presenca_registrada: boolean
  /**
   * true = existe o RELATÓRIO do Fábio (anotacoes_fabio) desta aula — NÃO é
   * presença. Gravação e chamada são INDEPENDENTES: nunca use isto pra decidir
   * "chamada feita" (foi o bug que trancava a chamada depois de gravar o áudio).
   */
  tem_registro: boolean
  /** Falta justificada pela coordenação (aluno_presenca_administrativo). */
  justificada: boolean
  /**
   * Aula individual paralela do aluno (alvo da fatia do Fábio — contrato v3).
   * Reconstruído no CLIENTE por agruparSessoes(); ausente nas sessões cruas.
   */
  aula_id_alvo?: number
}

export interface SessaoAula {
  hora: string
  hora_fim: string | null
  data_hora_inicio: string
  data_hora_fim: string | null
  curso: string | null
  turma_nome: string | null
  tipo: 'turma' | 'individual'
  /** A aula da sessão — âncora do áudio da gravação e da chamada. */
  aula_id_ancora: number
  n_alunos: number
  /** Nº de alunos com presença de FONTE FORTE (chamada real, não o default do Emusys). */
  n_registradas: number
  /** true = há aluno do roster sem conciliação (chamada bloqueada no banco). */
  roster_incompleto: boolean
  alunos: AlunoSessao[]
  /** Aulas cruas colapsadas nesta linha (enriquecido por agruparSessoes). */
  aulas_agrupadas?: number[]
  /**
   * Aula que RECEBE a chamada — o banco só aceita na aula de TURMA do slot
   * ('chamada_somente_na_aula_ancora'). null = sem turma paralela (individual
   * avulsa): sem porta de chamada pelo app. Enriquecido por agruparSessoes.
   */
  aula_id_chamada?: number | null
}

/**
 * Linha da carteira — uma por MATRÍCULA/DISCIPLINA (jornada canônica).
 * Um aluno com dois cursos aparece duas vezes, cada um com a própria régua.
 */
export interface CarteiraAluno {
  aluno_id: number | null
  aluno_nome: string
  curso: string | null
  status_matricula: string | null
  dia_aula: string | null
  horario_aula: string | null
  /** Unidade da matrícula (professor pode ser multiunidade). */
  unidade: string | null
  /** Posição na jornada — "Aula 20/40". */
  jornada_label: string | null
  nr_aulas_passadas: number | null
  nr_aulas_contratadas: number | null
  percentual_presenca_contrato: number | null
  qualidade: string | null
}

// ---------------------------------------------------------------------------

/** Sessões de aula do professor logado numa data (default: hoje, resolvido no banco). */
export async function minhaAgendaSessao(data?: string): Promise<SessaoAula[] | RpcErro> {
  const { data: res, error } = await supabase.rpc('app_minha_agenda_sessao', data ? { p_data: data } : {})
  if (error) throw error
  if (isSemVinculo(res)) return res
  return (res as unknown as SessaoAula[]) ?? []
}

/**
 * Carteira do professor logado — lê a jornada canônica
 * (vw_jornada_professor_atual, via porta guardada no banco).
 * Nunca retorna dado financeiro nem contato (telefone/whatsapp).
 */
export async function minhaCarteira(): Promise<CarteiraAluno[] | RpcErro> {
  const { data: res, error } = await supabase.rpc('app_minha_carteira')
  if (error) throw error
  if (isSemVinculo(res)) return res
  return res as unknown as CarteiraAluno[]
}

/** Registros do professor logado, opcionalmente filtrados por status. */
export async function meusRegistros(status?: string): Promise<unknown[]> {
  const { data: res, error } = await supabase.rpc('app_meus_registros', status ? { p_status: status } : {})
  if (error) throw error
  return (res as unknown[]) ?? []
}

export interface PendenciaConfirmacao {
  fatia_id: string
  aluno_id: number | null
  motivo: string
}

export interface ConfirmacaoResultado {
  registro_id: string
  gravadas: number
  ausentes_puladas: number
  pendencias: PendenciaConfirmacao[]
}

export type ModoRegistro = 'novo' | 'substituir' | 'complementar'

/** A trava do banco: registrar_aula_fabio RECUSA 'novo' sobre texto já existente. */
export const ERRO_ESCOLHA_MODO = 'registro_ja_existe_escolha_modo'
export class ErroEscolhaModo extends Error {
  constructor() {
    super(ERRO_ESCOLHA_MODO)
    this.name = 'ErroEscolhaModo'
  }
}

/**
 * Confirma um registro → grava POR ALUNO via porta única registrar_aula_fabio
 * (fatias presentes com texto; ausentes são puladas). O `modo` decide o que fazer
 * quando a aula JÁ tem relatório: 'substituir' apaga o anterior, 'complementar'
 * anexa. O banco RECUSA 'novo' sobre texto existente (fail-safe: erro, não perda) —
 * traduzido aqui em `ErroEscolhaModo` pra tela mostrar a escolha. LANÇA em erro.
 */
export async function confirmarRegistro(
  registroId: string,
  modo: ModoRegistro = 'novo',
): Promise<ConfirmacaoResultado> {
  const { data: res, error } = await supabase.rpc('app_confirmar_registro', {
    p_registro_id: registroId,
    p_modo: modo,
  })
  if (error) {
    // A trava pode chegar no message, code, details ou hint — depende de como o
    // PostgREST embrulha o RAISE. Checa todos pra não cair no toast genérico.
    const bruto = [error.message, error.code, error.details, error.hint].filter(Boolean).join(' ')
    if (bruto.includes(ERRO_ESCOLHA_MODO)) throw new ErroEscolhaModo()
    throw error
  }
  return res as unknown as ConfirmacaoResultado
}

// ---------------------------------------------------------------------------
// Sprint 3 · motor de registro
// ---------------------------------------------------------------------------

/** Linha de fabio_registros_aula (tronco ou fatia) como a RPC devolve. */
export interface RegistroRow {
  id: string
  aula_id: number | null
  aluno_id: number | null
  parent_id: string | null
  /** Áudio de origem (fabio_fila_audios.id) — casa a Processando com o registro pronto. */
  audio_id: string | null
  molde: 'A' | 'B' | 'C'
  campos: Record<string, unknown>
  texto_consolidado: string | null
  status: string
  origem: string
  criado_em: string
  /**
   * Enriquecimento POR FATIA (app_registro_completo) — nome e foto do aluno.
   * É o controle de qualidade humano do fatiamento: sem o nome na tela o
   * professor não percebe se o Fábio trocou os alunos. Ausente no tronco.
   */
  aluno_nome?: string | null
  aluno_primeiro_nome?: string | null
  aluno_foto_url?: string | null
  /** Aula individual paralela do aluno — onde a fatia dele é gravada. */
  aula_id_alvo?: number | null
  [k: string]: unknown
}

export interface AulaContexto {
  data_aula: string | null
  hora: string | null
  turma: string | null
  curso: string | null
  tipo: string | null
}

/** Relatório JÁ existente nesta aula (o prontuário atual, prévia do que seria sobrescrito). */
export interface RegistroJaFeito {
  aluno_id: number | null
  aluno_nome: string | null
  aula_id: number | null
  registrado_em: string | null
  previa: string | null
}

export interface RegistroCompleto {
  tronco: RegistroRow
  fatias: RegistroRow[]
  aula: AulaContexto | null
  /** true = esta aula JÁ tem relatório confirmado (o prontuário do aluno). */
  aula_ja_registrada?: boolean
  ja_registrados?: RegistroJaFeito[]
  /**
   * O que o banco exige na confirmação: 'novo' = grava direto; qualquer outra
   * coisa ('substituir|complementar') = o professor PRECISA escolher — a RPC
   * recusa 'novo' sobre texto existente pra nunca destruir em silêncio.
   */
  modo_exigido?: string
}

/** Tronco + fatias + contexto da aula. Erros da RPC: sem_professor | nao_encontrado. */
export async function registroCompleto(registroId: string): Promise<RegistroCompleto | RpcErro> {
  const { data: res, error } = await supabase.rpc('app_registro_completo', { p_registro_id: registroId })
  if (error) throw error
  const obj = res as unknown as RegistroCompleto | RpcErro
  return obj
}

/** Status do áudio na fila do Fábio (fabio_fila_audios) — só o do próprio professor. */
export type StatusFila = 'pendente' | 'transcrevendo' | 'transcrito' | 'normalizado' | 'erro'

export interface StatusAudioFila {
  audio_id: string
  status: StatusFila
  tentativas: number
  tem_erro: boolean
  criado_em: string
  atualizado_em: string
}

/**
 * Acompanha o processamento de UM áudio (app_status_audio_fila, guardada).
 * Devolve null se o áudio não é do professor logado ou não existe.
 */
export async function statusAudioFila(audioId: string): Promise<StatusAudioFila | null> {
  const { data, error } = await supabase.rpc('app_status_audio_fila', { p_audio_id: audioId })
  if (error) throw error
  const linhas = data as unknown as StatusAudioFila[]
  return linhas?.[0] ?? null
}

/** Registros (troncos) do professor aguardando confirmação, mais recentes primeiro. */
export async function registrosPendentes(): Promise<RegistroRow[]> {
  const { data: res, error } = await supabase.rpc('app_registros_pendentes')
  if (error) throw error
  return (res as unknown as RegistroRow[]) ?? []
}

/**
 * Atualiza texto e/ou campos (merge) de um tronco/fatia em edição.
 * Só o dono, só em rascunho/aguardando_confirmacao. LANÇA exceção em erro.
 */
export async function atualizarFatia(
  id: string,
  texto: string | null,
  campos: Record<string, unknown> | null,
): Promise<RegistroRow> {
  const { data: res, error } = await supabase.rpc('app_atualizar_fatia', {
    p_id: id,
    ...(texto != null ? { p_texto: texto } : {}),
    ...(campos != null ? { p_campos: campos as never } : {}),
  })
  if (error) throw error
  return res as unknown as RegistroRow
}

// ---------------------------------------------------------------------------
// MVP dia 21 · chamada (presença em lote) + ponto
// ---------------------------------------------------------------------------

export interface ResultadoChamada {
  aula_id: number
  total_roster: number
  inseridos: number
  ignorados_first_write_wins: number
  ja_havia_registros: boolean
  /** true = alguém já tinha enviado a chamada desta aula (nada foi gravado). */
  chamada_ja_enviada: boolean
}

/** Códigos que a RPC de chamada levanta como exceção (message do PostgREST). */
export const ERROS_CHAMADA = [
  'sem_professor_vinculado',
  'aula_nao_pertence_ao_professor',
  'aula_cancelada',
  'chamada_ainda_nao_disponivel',
  'janela_de_chamada_encerrada',
  'roster_nao_sincronizado',
  'roster_incompleto',
  'aluno_ausente_fora_do_roster',
  'chamada_somente_na_aula_ancora',
  'somente_leitura',
] as const
export type ErroChamada = (typeof ERROS_CHAMADA)[number]

/**
 * Envia a chamada da aula em lote: TODOS os alunos do roster viram 'presente',
 * exceto os ids em `ausentes` (viram 'falta'). First-write-wins no banco —
 * depois de enviada, correção é da coordenação, não do app.
 */
export async function registrarPresencas(
  aulaId: number,
  ausentes: number[],
): Promise<{ ok: true; resultado: ResultadoChamada } | { ok: false; erro: ErroChamada | 'desconhecido' }> {
  // Trava de segurança: em modo demonstração a chamada não grava em produção.
  if (SOMENTE_LEITURA) return { ok: false, erro: 'somente_leitura' }
  const { data: res, error } = await supabase.rpc('app_registrar_presencas_aula', {
    p_aula_emusys_id: aulaId,
    p_alunos_ausentes: ausentes,
  })
  if (error) {
    const conhecido = ERROS_CHAMADA.find((c) => error.message.includes(c))
    return { ok: false, erro: conhecido ?? 'desconhecido' }
  }
  return { ok: true, resultado: res as unknown as ResultadoChamada }
}

/** Um dia de ponto derivado da presença (app_meu_ponto). */
export interface PontoDia {
  data_aula: string
  unidades_ids: string[] | null
  inicio_creditado: string | null
  fim_creditado: string | null
  minutos_creditados: number
  aulas_creditadas: number
  pontas_confirmadas: number
}

/** Ponto do professor logado no intervalo (só leitura; horas nascem da chamada). */
export async function meuPonto(inicio: string, fim: string): Promise<PontoDia[]> {
  const { data: res, error } = await supabase.rpc('app_meu_ponto', {
    p_data_inicio: inicio,
    p_data_fim: fim,
  })
  if (error) throw error
  return (res as unknown as PontoDia[]) ?? []
}

// ---------------------------------------------------------------------------
// Ficha do aluno (tela /app/aluno/:id) — app_aluno_ficha
// ---------------------------------------------------------------------------

export interface AlunoFichaPerfil {
  aluno_id: number
  nome: string
  foto_url: string | null
  idade: number | null
  data_nascimento: string | null
  /** LAMK = Kids · EMLA = School. */
  classificacao: string | null
  modalidade: string | null
  unidade: string | null
  data_matricula: string | null
  meses_de_casa: number | null
  status: string | null
  is_retorno: boolean | null
  is_segundo_curso: boolean | null
}

export interface AlunoFichaJornada {
  curso: string | null
  aula_atual: number | null
  aulas_contratadas: number | null
  aulas_realizadas: number | null
  jornada_label: string | null
  dia_aula: string | null
  horario: string | null
  status_matricula: string | null
  percentual: number | null
}

export interface AlunoFichaOutroCurso {
  curso: string | null
  professor: string | null
}

export interface AlunoFichaResponsavel {
  nome: string | null
  parentesco: string | null
  principal: boolean | null
}

/** Estados da camada semântica de presença (regra v1.3 do LA Report, 22/07). */
export type ResultadoPedagogico =
  | 'presente'
  | 'falta_confirmada'
  | 'falta_provavel'
  | 'indeterminado'
  | 'aula_justificada'
  | 'aula_cancelada'

export interface AlunoFichaPresenca {
  data: string
  /** Estado BRUTO da origem — legado, mantido por compatibilidade. Prefira resultado_pedagogico. */
  status: string | null
  curso: string | null
  horario?: string | null
  /**
   * A verdade pedagógica: falta CONFIRMADA (chamada real) ≠ falta PROVÁVEL
   * (o "ausente" automático do Emusys quando ninguém fez a chamada).
   */
  resultado_pedagogico?: ResultadoPedagogico | null
  situacao_chamada?: string | null
  confianca?: string | null
  /** Quem marcou: 'la_teacher' | 'fabio_audio' | 'manual' | 'emusys'. */
  proveniencia?: string | null
  revisao_operacional_exigida?: boolean | null
  revisao_operacional_status?: string | null
}

export interface AlunoFichaRegistro {
  data: string
  curso: string | null
  texto: string | null
  /** 'fabio' = registro do Fábio; 'emusys' = anotação legada do Emusys. */
  origem: 'fabio' | 'emusys'
  /** true = foi este professor que escreveu; false = professor anterior do mesmo curso. */
  foi_voce: boolean
}

export interface AlunoFicha {
  perfil: AlunoFichaPerfil
  minha_jornada: AlunoFichaJornada[]
  outros_cursos: AlunoFichaOutroCurso[]
  responsaveis: AlunoFichaResponsavel[]
  presenca_recente: AlunoFichaPresenca[]
  historico_pedagogico: AlunoFichaRegistro[]
}

/** A RPC recusa aluno que não é da carteira do professor logado. */
export const FORA_DA_CARTEIRA = 'aluno_fora_da_sua_carteira' as const

/**
 * Ficha completa do aluno (app_aluno_ficha) — scoped ao professor logado.
 * Devolve FORA_DA_CARTEIRA se o aluno não é da carteira. LANÇA em erro de rede.
 */
export async function alunoFicha(alunoId: number): Promise<AlunoFicha | typeof FORA_DA_CARTEIRA> {
  const { data: res, error } = await supabase.rpc('app_aluno_ficha', { p_aluno_id: alunoId })
  if (error) {
    if (error.message.includes(FORA_DA_CARTEIRA)) return FORA_DA_CARTEIRA
    throw error
  }
  return res as unknown as AlunoFicha
}

// ---------------------------------------------------------------------------
// Perfil do professor (header interno + tela "Meu perfil")
// ---------------------------------------------------------------------------

/** Perfil do professor logado, como a RPC guardada devolve (app_meu_perfil). */
export interface MeuPerfil {
  professor_id: number
  nome: string
  /** Como o Fábio deve chamar o professor — editável, null se ainda não preenchido. */
  nome_preferido: string | null
  /** O que o Fábio deve saber sobre o professor — editável, null se ainda não preenchido. */
  bio: string | null
  email: string | null
  telefone_whatsapp: string | null
  foto_url: string | null
  unidades: string | null
}

/**
 * Perfil do professor logado (app_meu_perfil) — nome, contato, foto e unidades.
 * Devolve null se o usuário logado não tem professor vinculado (0 linhas).
 */
export async function meuPerfil(): Promise<MeuPerfil | null> {
  const { data: res, error } = await supabase.rpc('app_meu_perfil')
  if (error) throw error
  const linhas = res as unknown as MeuPerfil[]
  return linhas?.[0] ?? null
}

/**
 * Atualiza nome_preferido/bio do professor logado (app_atualizar_perfil).
 * Só a própria linha, só esses 2 campos. A RPC trata null como "não mexe" —
 * por isso aqui sempre manda string (mesmo vazia, pra limpar de verdade um
 * campo apagado na tela). LANÇA exceção em erro.
 */
export async function atualizarPerfil(
  nomePreferido: string,
  bio: string,
): Promise<{ ok: true; professor_id: number }> {
  const { data: res, error } = await supabase.rpc('app_atualizar_perfil', {
    p_nome_preferido: nomePreferido,
    p_bio: bio,
  })
  if (error) throw error
  return res as unknown as { ok: true; professor_id: number }
}

export interface EnfileirarResultado {
  audio_id: string
  status: 'pendente'
  modo: 'novo' | 'complementar'
  registro_id: string | null
}

/**
 * Erros de VALIDAÇÃO que a RPC de gravação levanta (message do PostgREST).
 * São permanentes (não adianta re-tentar): aula não é do professor, cancelada,
 * fora da janela. Mesma régua da chamada — desde 11/07 a RPC valida de verdade.
 */
export const ERROS_GRAVACAO = [
  'aula_nao_pertence_ao_professor',
  'aula_cancelada',
  'gravacao_ainda_nao_disponivel',
  'janela_de_gravacao_encerrada',
] as const
export type ErroGravacao = (typeof ERROS_GRAVACAO)[number]

/** Erro de validação conhecido da gravação — permanente, NÃO vai pra fila offline. */
export class ErroGravacaoConhecido extends Error {
  readonly codigo: ErroGravacao
  constructor(codigo: ErroGravacao) {
    super(codigo)
    this.name = 'ErroGravacaoConhecido'
    this.codigo = codigo
  }
}

/**
 * Enfileira um áudio gravado (fabio_fila_audios) para o Fábio processar.
 * A RPC resolve professor e unidade via auth.uid(); `registroId` não nulo
 * marca correção por voz (modo complementar). Levanta `ErroGravacaoConhecido`
 * nos erros de validação (aula fora da janela etc.) e o erro cru no resto.
 */
export async function enfileirarAudio(
  aulaId: number,
  storagePath: string,
  duracaoSegundos: number,
  registroId: string | null = null,
): Promise<EnfileirarResultado> {
  const { data: res, error } = await supabase.rpc('app_enfileirar_audio', {
    p_aula_id: aulaId,
    p_storage_path: storagePath,
    p_duracao_segundos: duracaoSegundos,
    // Mando p_registro_id SEMPRE (null quando não é correção por voz), por
    // robustez: funciona com ou sem o DEFAULT NULL da RPC — se o banco perder
    // o default de novo, a gravação não quebra. Cast porque o tipo gerado
    // (db.ts) marca o campo como string.
    p_registro_id: registroId as unknown as string,
  })
  if (error) {
    const conhecido = ERROS_GRAVACAO.find((c) => error.message.includes(c))
    if (conhecido) throw new ErroGravacaoConhecido(conhecido)
    throw error
  }
  return res as unknown as EnfileirarResultado
}

// ---------------------------------------------------------------------------
// Onboarding do professor (primeiro acesso)
// ---------------------------------------------------------------------------

export interface MeuOnboarding {
  professor_id: number
  primeiro_nome: string
  /** true quando o professor já passou pelo onboarding (não mostra de novo). */
  concluido: boolean
  /** true enquanto o WhatsApp não foi confirmado por ele. */
  precisa_confirmar_whatsapp: boolean
  /** número do cadastro pra pré-preencher (pode vir sem 55, sem 9, com máscara). */
  whatsapp_sugerido: string | null
  meus_alunos: number
  meus_cursos: number
}

// Helper pra RPCs criadas DEPOIS da última geração de src/types/db.ts — ainda
// não estão no union de nomes tipado. Cast pontual (com bind pra não perder o
// `this` do client), contrato verificado no banco. Usado por onboarding e pelo
// histórico da turma. Remover cada chamada quando o db.ts incluir a RPC.
const rpcSolta = supabase.rpc.bind(supabase) as unknown as (
  fn: string,
  args?: Record<string, unknown>,
) => Promise<{
  data: unknown
  error: { message?: string; code?: string; details?: string; hint?: string } | null
}>

/** Estado do onboarding do professor logado (app_meu_onboarding). Read-only. */
export async function meuOnboarding(): Promise<MeuOnboarding> {
  const { data: res, error } = await rpcSolta('app_meu_onboarding')
  if (error) throw error
  return res as unknown as MeuOnboarding
}

/** Motivo amigável da recusa do confirmar-WhatsApp. */
export type MotivoErroWhatsapp = 'ja_usado' | 'incompleto'
export class ErroConfirmarWhatsapp extends Error {
  constructor(public motivo: MotivoErroWhatsapp) {
    super(motivo)
    this.name = 'ErroConfirmarWhatsapp'
  }
}

/**
 * Confirma/corrige o WhatsApp do professor (app_confirmar_meu_whatsapp).
 * A RPC canoniza qualquer formato (com/sem 55, com/sem 9, com máscara) e grava
 * 55+DDD+número. Recusa colisão (número já usado por outro professor). LANÇA
 * ErroConfirmarWhatsapp('ja_usado'|'incompleto') nesses casos; erro cru no resto.
 */
export async function confirmarMeuWhatsapp(telefone: string): Promise<void> {
  const { error } = await rpcSolta('app_confirmar_meu_whatsapp', { p_telefone: telefone })
  if (error) {
    const bruto = [error.message, error.code, error.details, error.hint].filter(Boolean).join(' ')
    if (bruto.includes('whatsapp_ja_usado')) throw new ErroConfirmarWhatsapp('ja_usado')
    if (bruto.includes('whatsapp_incompleto')) throw new ErroConfirmarWhatsapp('incompleto')
    throw error
  }
}

/** Marca o onboarding como concluído (app_concluir_onboarding). Idempotente. */
export async function concluirOnboarding(): Promise<void> {
  const { error } = await rpcSolta('app_concluir_onboarding')
  if (error) throw error
}

// ---------------------------------------------------------------------------
// Histórico da turma (app_historico_turma)
// ---------------------------------------------------------------------------

/** Repertório individual de um aluno numa sessão da turma (ex.: música pró recital). */
export interface RepertorioAluno {
  aluno: string
  primeiro_nome: string
  repertorio: string
}

export interface HistoricoTurmaSessao {
  data: string
  origem: 'fabio' | 'emusys'
  /** Campos estruturados — só em origem:fabio (null no legado). */
  objetivo: string | null
  conteudo: string | null
  dever_casa: string | null
  repertorio_turma: string | null
  /** Repertório por aluno (recital etc.) — pode coexistir com repertorio_turma. */
  repertorio_por_aluno: RepertorioAluno[]
  /** Texto corrido do Emusys — só em origem:emusys (null no fabio). */
  texto_legado: string | null
}

export interface HistoricoTurma {
  turma_nome: string
  curso: string | null
  alunos_atuais: string[]
  sessoes: HistoricoTurmaSessao[]
}

/** A RPC recusa turma que não é do professor logado. */
export const TURMA_NAO_SUA = 'turma_nao_encontrada_ou_nao_e_sua' as const

/**
 * Histórico pedagógico de uma turma (app_historico_turma) — sessões mais recentes
 * primeiro, scoped ao professor logado. Devolve TURMA_NAO_SUA se a turma não é dele.
 * LANÇA em erro de rede.
 */
export async function historicoTurma(
  turmaNome: string,
  limite = 15,
): Promise<HistoricoTurma | typeof TURMA_NAO_SUA> {
  const { data: res, error } = await rpcSolta('app_historico_turma', {
    p_turma_nome: turmaNome,
    p_limite: limite,
  })
  if (error) {
    const bruto = [error.message, error.code, error.details, error.hint].filter(Boolean).join(' ')
    if (bruto.includes(TURMA_NAO_SUA)) return TURMA_NAO_SUA
    throw error
  }
  return res as unknown as HistoricoTurma
}

// ---------------------------------------------------------------------------
// Preferências do Fábio (como e quando ele fala com o professor)
// ---------------------------------------------------------------------------

/** Por onde o Fábio fala com o professor. Default do banco = 'ambos'. */
export type CanalPreferido = 'app' | 'whatsapp' | 'ambos'

/**
 * Só o que a tela v1 expõe. O banco guarda mais campos (silêncio por horário,
 * tom, cobrança de pendência), reservados de propósito — a tela do professor
 * mexe só em canal e domingo por enquanto.
 */
export interface PreferenciasFabio {
  canal_preferido: CanalPreferido
  recebe_domingo: boolean
}

/**
 * Preferências do Fábio do professor logado (app_minhas_preferencias_fabio).
 * A RPC cria o default no primeiro acesso (não precisa tratar "vazio"). LANÇA em erro.
 */
export async function minhasPreferenciasFabio(): Promise<PreferenciasFabio> {
  const { data: res, error } = await rpcSolta('app_minhas_preferencias_fabio')
  if (error) throw error
  return res as unknown as PreferenciasFabio
}

/**
 * Atualização PARCIAL das preferências (app_atualizar_preferencia_fabio): só os
 * campos presentes em `campos` são enviados — o resto fica intacto no banco.
 * A tela salva incremental (um campo por toque). LANÇA em erro.
 */
export async function atualizarPreferenciaFabio(
  campos: Partial<PreferenciasFabio>,
): Promise<void> {
  const args: Record<string, unknown> = {}
  if (campos.canal_preferido !== undefined) args.p_canal_preferido = campos.canal_preferido
  if (campos.recebe_domingo !== undefined) args.p_recebe_domingo = campos.recebe_domingo
  const { error } = await rpcSolta('app_atualizar_preferencia_fabio', args)
  if (error) throw error
}
