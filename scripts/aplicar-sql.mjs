#!/usr/bin/env node
// Aplica um ou mais arquivos .sql EM DEFINITIVO no banco (sem rollback).
//
// Existe porque a alternativa era eu reconstruir o SQL dentro da chamada de
// API — e reconstruir de memória é como se introduz diferença silenciosa entre
// o que foi testado e o que foi aplicado. Aqui vai o byte do arquivo.
//
// Irmão do `rodar-teste-sql.mjs`, que roda o MESMO arquivo em transação
// descartável. Fluxo da casa: testa com o runner, mata os mutantes, e só então
// aplica com este.
//
// Uso:  node scripts/aplicar-sql.mjs <migration.sql> [outro.sql ...]

import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

const PROJETO = 'ouqwbbermlzqqvtqwlul' // LA Performance Report (banco compartilhado)

function lerEnv(chave) {
  if (process.env[chave]) return process.env[chave]
  const texto = readFileSync(resolve(process.cwd(), '.env'), 'utf8')
  for (const linha of texto.split(/\r?\n/)) {
    const corte = linha.indexOf('=')
    if (corte < 0 || linha.trimStart().startsWith('#')) continue
    if (linha.slice(0, corte).trim() === chave) {
      return linha.slice(corte + 1).trim().replace(/^["']|["']$/g, '')
    }
  }
  return null
}

const arquivos = process.argv.slice(2)
if (arquivos.length === 0) {
  console.error('uso: node scripts/aplicar-sql.mjs <arquivo.sql> [outro.sql ...]')
  process.exit(2)
}

const token = lerEnv('SUPABASE_ACCESS_TOKEN')
if (!token) {
  console.error('SUPABASE_ACCESS_TOKEN não encontrado (env ou .env)')
  process.exit(2)
}

// Arquivo de TESTE não se aplica: ele cria temp tables, semeia dado e conta com
// o ROLLBACK do runner. Rodar um aqui sujaria produção de verdade.
for (const a of arquivos) {
  if (/\.test\.sql$/i.test(a)) {
    console.error(`✗ ${a} é arquivo de teste — este script aplica em definitivo.`)
    process.exit(2)
  }
}

async function consultar(sql) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROJETO}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  })
  const texto = await r.text()
  return { ok: r.ok, texto }
}

// Marcadores {{VAR}} são resolvidos do .env na hora de aplicar. Existe por
// causa do cron: o padrão da casa manda a chave anon dentro do comando do job,
// e a migration versionada não precisa carregar credencial nenhuma pra isso.
function resolverMarcadores(sql, arquivo) {
  return sql.replace(/\{\{([A-Z0-9_]+)\}\}/g, (_, chave) => {
    const valor = lerEnv(chave)
    if (!valor) {
      console.error(`\n✗ ${arquivo} pede {{${chave}}} e não achei no ambiente nem no .env`)
      process.exit(2)
    }
    return valor
  })
}

for (const a of arquivos) {
  const sql = resolverMarcadores(readFileSync(resolve(a), 'utf8'), a)
  process.stdout.write(`aplicando ${a} (${sql.length} bytes)... `)
  const { ok, texto } = await consultar(sql)
  if (!ok) {
    console.log('FALHOU')
    console.error(texto.slice(0, 1200))
    process.exit(1)
  }
  console.log('ok')
}
console.log('\naplicado em definitivo.')
