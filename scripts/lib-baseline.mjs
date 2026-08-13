// A trava que faltava em todo runner de mutante desta casa.
//
// POR QUE ELA EXISTE. Um mutante "morre" quando o teste falha com ele
// aplicado. Se o teste JA FALHA sem mutante nenhum, todos morrem -- e o runner
// imprime um placar perfeito que nao prova coisa alguma.
//
// Isso nao e hipotetico; foi medido duas vezes em 13/08/2026:
//
//   1. Na propria migration da limpeza: um fixture invalido (payload nulo numa
//      coluna NOT NULL) quebrou o baseline e a suite reportou 5/5. Zero dos
//      cinco tinha sido pego por assercao.
//   2. Depois de consertar o CRLF que cegava as ancoras, `mutantes-090` e
//      `mutantes-091` passaram a reportar 10/10 -- mas os baselines das duas
//      FALHAM contra a producao. Os vinte "mortos" sao decoracao.
//
// Placar de mutante so tem sentido depois de um baseline verde. Chame
// `exigirBaselineVerde()` antes do laco, sempre.

import { execFileSync } from 'node:child_process'

export function exigirBaselineVerde(migration, teste) {
  try {
    execFileSync('node', ['scripts/rodar-teste-sql.mjs', migration, teste], { stdio: 'pipe' })
  } catch (erro) {
    const saida = [erro.stdout, erro.stderr]
      .filter(Boolean).map((b) => b.toString()).join('\n').trim()
    console.error('BASELINE VERMELHO — placar de mutante nao vale nada aqui.')
    console.error(`  migration: ${migration}`)
    console.error(`  teste:     ${teste}`)
    console.error('  O teste falha SEM mutante nenhum, entao todo mutante')
    console.error('  "morreria" por erro e nao por assercao. Conserte o')
    console.error('  baseline antes de ler qualquer numero.')
    if (saida) console.error('\n' + saida.split('\n').slice(0, 12).join('\n'))
    process.exit(1)
  }
}
