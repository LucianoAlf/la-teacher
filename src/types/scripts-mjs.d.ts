declare module '*.mjs' {
  interface SnapshotRow {
    [key: string]: unknown
    tabela: string
    linhas: number
    digest: string
    owner?: string | null
    acl?: string | null
    comment?: string | null
  }

  interface RunnerResult {
    codigo: number
    stdout: string
    stderr: string
  }

  interface FunctionMetadata {
    digest: string
    owner: string
    acl: string
    comment: string
  }

  interface SnapshotAssessment {
    ok: boolean
    erros: string[]
    residuosAntes: number
    residuosDepois: number
    linhasAntes: SnapshotRow[]
    linhasDepois: SnapshotRow[]
    funcaoAntes: FunctionMetadata
    funcaoDepois: FunctionMetadata
  }

  interface SnapshotResponse {
    ok: boolean
    status: number
    json(): Promise<unknown>
  }

  export function construirConsultaSnapshot(marcador?: string): string
  export function validarRespostaSnapshot(dados: unknown): SnapshotRow[]
  export function avaliarSnapshots(antes: unknown, depois: unknown): SnapshotAssessment
  export function formatarResumoResiduos(resumos: SnapshotRow[]): string
  export function executarEnsaioPresencaNull(options?: {
    token?: string
    fetchImpl?: (input: string, init?: RequestInit) => Promise<SnapshotResponse>
    executarRunner?: () => RunnerResult | Promise<RunnerResult>
  }): Promise<{
    runner: RunnerResult
    prova: SnapshotAssessment
  }>
}
