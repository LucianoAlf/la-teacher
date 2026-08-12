/**
 * Mantém a ordem das mutações, mas uma falha anterior não envenena a cauda:
 * a próxima ação é uma tentativa real de recuperação.
 */
export function continuarFila<T>(
  cauda: Promise<unknown>,
  operacao: () => Promise<T>,
): Promise<T> {
  return cauda.then(operacao, operacao)
}
