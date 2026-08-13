// Teste do classificador da bateria — com as strings de erro REAIS que o
// Postgres devolveu neste projeto, copiadas das rodadas de 13/08/2026.
//
// Existe porque a versão anterior deste classificador escondeu uma reprovação
// de verdade na coluna errada, e ninguém tinha como perceber: regex sem nome
// não tem teste. Os casos negativos (o que NÃO pode ser tratado como "não
// reaplicável") são os que importam — são eles que a versão antiga errava.

import { naoEReaplicavel } from './lib-veredito.mjs'

const cabecalho = 'x — a execução falhou:\n\n'

const CASOS = [
  // --- NAO REAPLICAVEL (DDL na segunda passada) ---
  { esperado: true,
    nome: 'create table na segunda vez',
    saida: cabecalho + 'Failed to run sql query: ERROR:  42P07: relation "fabio_x" already exists' },
  { esperado: true,
    nome: 'coluna que a migration anterior removeu',
    saida: cabecalho + 'Failed to run sql query: ERROR:  42703: column "foo" does not exist' },
  { esperado: true,
    nome: 'view que ganhou coluna depois (088)',
    saida: cabecalho + 'Failed to run sql query: ERROR:  42P16: cannot drop columns from view' },
  { esperado: true,
    nome: 'objeto duplicado e DDL',
    saida: cabecalho + 'Failed to run sql query: ERROR:  42710: duplicate object "idx_x"' },

  // --- REPROVACAO (erro de dado ou do proprio teste) ---
  { esperado: false,
    nome: 'duplicate KEY e dado, nao DDL — o caso que a versao antiga engolia',
    saida: cabecalho + 'Failed to run sql query: ERROR:  23505: duplicate key value violates '
         + 'unique constraint "uq_presenca_aluno_aula"\nDETAIL:  Key (aluno_id, aula_emusys_id)=(674, 234509) already exists.' },
  { esperado: false,
    nome: 'CHECK violado por linha viva (053/075)',
    saida: cabecalho + 'Failed to run sql query: ERROR:  23514: check constraint '
         + '"fabio_notificacoes_tipo_check" of relation "fabio_notificacoes" is violated by some row' },
  { esperado: false,
    nome: 'ON CONFLICT sem indice (o 42P10 vivo)',
    saida: cabecalho + 'Failed to run sql query: ERROR:  42P10: there is no unique or exclusion '
         + 'constraint matching the ON CONFLICT specification' },
  { esperado: false,
    nome: 'funcao ambigua (077)',
    saida: cabecalho + 'Failed to run sql query: ERROR:  42725: function '
         + 'public.app_coordenacao_feedback_mes() is not unique' },
  { esperado: false,
    nome: 'passo divergiu — nem chegou a ter "a execução falhou"',
    saida: 'x — 3 passo(s) divergiram:\n  • algo\n      esperado <3>  obtido <4>' },
]

let falhas = 0
for (const c of CASOS) {
  const obtido = naoEReaplicavel(c.saida)
  if (obtido === c.esperado) {
    console.log(`OK     ${c.esperado ? 'nao-reaplicavel' : 'REPROVADO      '}  ${c.nome}`)
  } else {
    falhas++
    console.log(`FALHA  esperava ${c.esperado ? 'nao-reaplicavel' : 'REPROVADO'}, deu o contrario: ${c.nome}`)
  }
}

console.log(`\n${CASOS.length - falhas}/${CASOS.length} casos corretos`)
process.exitCode = falhas === 0 ? 0 : 1
