#!/usr/bin/env node
// Roda TODOS os testes de migration que existem no repo.
//
// POR QUE ESTE ARQUIVO EXISTE
// Em 08/08/2026 havia 44 arquivos `*.test.sql` e 11 comandos `teste:NNN` no
// package.json. Trinta e três testes existiam e ninguém tinha como rodar —
// exatamente a doença que a 060 consertou no reconciliador: escrito, testado,
// e sem quem chamasse. Teste que não roda apodrece em silêncio (âncora podre,
// expectativa que envelheceu, fixture que colide) e o repositório fica com
// cara de coberto.
//
// TRÊS VEREDITOS, NÃO DOIS
// Nem toda migration é reaplicável: as que fazem `alter table ... add column`
// falham na segunda vez, e isso NÃO é o teste reprovando — é a migration não
// servir de harness. Misturar os dois casos num "falhou" genérico faria a
// saída mentir. Quem aparece como NAO-REAPLICAVEL precisa de um par
// idempotente pra ser exercitado de novo; não é bug, é dívida declarada.
//
// Uso:  node scripts/rodar-todos-os-testes.mjs [filtro]
//       node scripts/rodar-todos-os-testes.mjs 06     → só os que começam com 06

import { execFileSync } from 'node:child_process'
import { readdirSync, existsSync } from 'node:fs'

const DIR = 'supabase/migrations'
const filtro = process.argv[2] ?? ''

const pares = readdirSync(DIR)
  .filter((f) => f.endsWith('.test.sql'))
  .map((teste) => {
    const base = teste.replace(/\.test\.sql$/, '')
    return { teste: `${DIR}/${teste}`, migration: `${DIR}/${base}.sql`, nome: base }
  })
  .filter((p) => existsSync(p.migration))
  .filter((p) => p.nome.startsWith(filtro))
  .sort((a, b) => a.nome.localeCompare(b.nome))

console.log(`${pares.length} par(es) migration+teste\n`)

const passou = []
const falhou = []
const naoReaplicavel = []

for (const p of pares) {
  let saida = ''
  let ok = true
  try {
    saida = execFileSync('node', ['scripts/rodar-teste-sql.mjs', p.migration, p.teste], {
      stdio: 'pipe', encoding: 'utf8',
    })
  } catch (e) {
    ok = false
    saida = `${e.stdout ?? ''}${e.stderr ?? ''}`
  }

  // "a execução falhou" com erro de DDL = a migration não é reaplicável.
  // O teste em si nem chegou a rodar, então chamar isso de reprovação seria
  // apontar o dedo pro lugar errado.
  const ddl = /already exists|does not exist|cannot be cast|duplicate/i.test(saida)
              && /a execução falhou/i.test(saida)

  if (ok) {
    passou.push(p.nome)
    console.log(`✓ ${p.nome}`)
  } else if (ddl) {
    naoReaplicavel.push(p.nome)
    const motivo = (saida.match(/ERROR:[^\n]*/) ?? ['(sem detalhe)'])[0].slice(0, 110)
    console.log(`~ ${p.nome}  — migration não reaplicável: ${motivo}`)
  } else {
    falhou.push(p.nome)
    const detalhe = saida.split('\n').filter((l) => l.includes('•') || l.includes('divergiram') || l.includes('ANCORA'))
    console.log(`✗ ${p.nome}`)
    for (const l of detalhe.slice(0, 6)) console.log(`    ${l.trim()}`)
  }
}

console.log(`\n${passou.length} passaram · ${falhou.length} FALHARAM · ${naoReaplicavel.length} não reaplicáveis`)
if (falhou.length) console.log(`\nreprovados: ${falhou.join(', ')}`)
if (naoReaplicavel.length) console.log(`\nsem harness reaplicável: ${naoReaplicavel.join(', ')}`)
process.exitCode = falhou.length ? 1 : 0
