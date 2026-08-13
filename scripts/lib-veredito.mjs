// Como a bateria decide se uma migration REPROVOU ou se ela apenas não serve
// de harness.
//
// POR QUE ISTO SAIU DE DENTRO DO RUNNER. Era uma regex solta no meio do laço,
// e ninguém consegue testar uma regex que não tem nome. Em 13/08/2026 ela
// classificou errado um teste MEU: a régua de precedência (20260813220000)
// quebrou com `duplicate key value violates unique constraint` -- erro de
// DADO, do fixture -- e foi parar na coluna "sem harness reaplicável". A
// bateria imprimiu uma reprovação a menos do que tinha.
//
// Classificador que engole falha de verdade tem exatamente a mesma doença do
// verde que não pode ficar vermelho. Então ele virou função com nome, e tem
// teste próprio em `scripts/teste-veredito.mjs`, com as strings reais.
//
// POR QUE SQLSTATE E NÃO TEXTO. Minha primeira tentativa de conserto foi
// apertar o termo `duplicate` -- e o teste novo reprovou na primeira rodada,
// porque a mensagem de unique violation **termina com "already exists."** no
// DETAIL:
//
//   ERROR: 23505: duplicate key value violates unique constraint "uq_..."
//   DETAIL: Key (aluno_id, aula_emusys_id)=(674, 234509) already exists.
//
// Ou seja: casar por texto ia continuar errando, só que num caso diferente. O
// SQLSTATE é o campo que o Postgres mantém estável de propósito -- é por ele
// que se decide.

/**
 * Códigos que significam "esta migration não se reaplica", não "o teste caiu".
 * Todos são erros que aparecem na SEGUNDA passada de um DDL que já rodou.
 */
const SQLSTATE_NAO_REAPLICAVEL = new Set([
  '42P07', // duplicate_table      — create table na segunda vez
  '42701', // duplicate_column     — add column na segunda vez
  '42710', // duplicate_object     — índice/constraint/tipo já criado
  '42723', // duplicate_function
  '42P06', // duplicate_schema
  '42P16', // invalid_table_definition — "cannot drop columns from view"
  '42703', // undefined_column     — coluna que uma migration posterior removeu
  '42P01', // undefined_table
  '42883', // undefined_function   — assinatura trocada depois
  '42846', // cannot_coerce        — "cannot be cast"
])

/**
 * @param {string} saida  stdout+stderr de `rodar-teste-sql.mjs`
 * @returns {boolean} true = a migration não é reaplicável (não é reprovação)
 */
export function naoEReaplicavel(saida) {
  // Sem "a execução falhou" o teste RODOU e o veredito é dele, não daqui.
  if (!/a execução falhou/i.test(saida)) return false

  const codigo = (saida.match(/ERROR:\s*([0-9A-Z]{5}):/) ?? [])[1]

  // Sem código legível, o default é REPROVAÇÃO. Falha que ninguém sabe
  // classificar tem que aparecer, não sumir numa coluna de dívida.
  if (!codigo) return false

  return SQLSTATE_NAO_REAPLICAVEL.has(codigo)
}
