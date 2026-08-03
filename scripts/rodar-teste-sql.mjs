#!/usr/bin/env node
// Roda um arquivo .sql contra o projeto Supabase e SAI COM CÓDIGO ≠ 0 se falhar.
//
// Por que existe (exigência da auditoria, 03/08/2026): o teste da 018 só
// imprimia PASSOU/FALHOU numa tabela. Verde por leitura humana não é prova —
// se ninguém olhar a coluna certa, um teste quebrado passa batido. Agora o
// próprio SQL levanta exceção na divergência, e este runner transforma isso em
// código de saída, que CI e gente distraída não conseguem ignorar.
//
// Equivalente ao `ON_ERROR_STOP=1` do psql: não temos psql nesta máquina, então
// o batch inteiro vai numa requisição só. Qualquer erro aborta tudo e volta
// como erro da API — e, como o arquivo roda dentro de BEGIN/ROLLBACK, abortar
// no meio também não deixa traço.
//
// O runner é DONO da transação: ele mesmo abre BEGIN e fecha ROLLBACK, sempre.
// Os arquivos não trazem controle de transação — assim não existe a versão do
// teste em que alguém esqueceu o `rollback` e escreveu em produção. Por isso dá
// pra passar a migration junto: ela é aplicada e descartada no mesmo fôlego.
//
// Uso:  node scripts/rodar-teste-sql.mjs <migration.sql> <teste.sql>
//       node scripts/rodar-teste-sql.mjs supabase/migrations/018-*.test.sql

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
  console.error('uso: node scripts/rodar-teste-sql.mjs <arquivo.sql> [outro.sql ...]')
  process.exit(2)
}

const token = lerEnv('SUPABASE_ACCESS_TOKEN')
if (!token) {
  console.error('SUPABASE_ACCESS_TOKEN não encontrado (env ou .env)')
  process.exit(2)
}

const corpos = arquivos.map((a) => {
  const texto = readFileSync(resolve(a), 'utf8')
  // Rede de segurança: se um arquivo trouxer controle de transação, o ROLLBACK
  // do runner deixaria de valer pro que veio antes do COMMIT.
  if (/^\s*(begin|commit|rollback)\s*;/im.test(texto)) {
    console.error(`✗ ${a} contém BEGIN/COMMIT/ROLLBACK — o runner é o dono da transação.`)
    process.exit(2)
  }
  return `-- >>>>> ${a}\n${texto}`
})

const sql = ['begin;', ...corpos, 'rollback;'].join('\n')

const resposta = await fetch(
  `https://api.supabase.com/v1/projects/${PROJETO}/database/query`,
  {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  },
)

const corpo = await resposta.text()

const alvo = arquivos.join(' + ')

if (!resposta.ok) {
  // Aqui cai o RAISE do próprio teste: a mensagem já diz qual passo divergiu.
  console.error(`\n✗ ${alvo}\n`)
  try {
    const j = JSON.parse(corpo)
    console.error(j?.error?.message ?? j?.message ?? corpo)
  } catch {
    console.error(corpo)
  }
  process.exitCode = 1
} else if (/FALHOU/.test(corpo)) {
  // Cinto e suspensório: se algum dia um passo virar linha de resultado em vez
  // de exceção, a palavra FALHOU também derruba o runner.
  console.error(`\n✗ ${alvo} — resultado contém FALHOU:\n${corpo}`)
  process.exitCode = 1
} else {
  console.log(`✓ ${alvo}\n  ${corpo.trim()}`)
}

// Sai por process.exitCode, NUNCA por process.exit(): chamar exit() logo depois
// do fetch derruba o libuv no Windows com "UV_HANDLE_CLOSING" e devolve rc=127
// — ou seja, o runner reprovaria um teste que passou. Rc errado e' pior que rc
// nenhum: e' a mesma classe de mentira que este teste existe pra impedir.
