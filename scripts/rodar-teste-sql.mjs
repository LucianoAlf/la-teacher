#!/usr/bin/env node
// Roda arquivos .sql contra o Supabase num ensaio descartável e SAI COM CÓDIGO
// ≠ 0 se algo falhar OU se sobrar resíduo.
//
// ── Por que ele é assim (duas auditorias) ────────────────────────────────────
//
// 1ª: o teste só imprimia PASSOU/FALHOU numa tabela. Verde por leitura humana
//     não é prova — bastava ninguém olhar a coluna certa.
//
// 2ª: a correção foi levantar exceção na divergência. Isso dava rc certo, mas
//     deixava a transação ABORTADA e o ROLLBACK por conta do cleanup implícito
//     da conexão, que a Management API não promete. Justamente no caminho de
//     falha, DDL e locks numa tabela viva (`fabio_notificacoes`, do briefing)
//     ficavam dependendo de sorte.
//
// Agora:
//   • o SQL NUNCA aborta — registra divergências e devolve um resumo em JSON,
//     com a transação sadia, para o ROLLBACK executar normalmente;
//   • o veredito vem desse resumo explícito, não da ausência de erro;
//   • uma SEGUNDA chamada, em outra conexão, confirma que nada sobrou.
//     Reprovar por resíduo é tão importante quanto reprovar por divergência:
//     um ensaio que suja produção não é ensaio.
//
// Uso:  node scripts/rodar-teste-sql.mjs <migration.sql> <teste.sql>

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

async function consultar(sql) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROJETO}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  })
  const texto = await r.text()
  let dados = null
  try {
    dados = JSON.parse(texto)
  } catch {
    /* deixa null: quem chamou decide */
  }
  return { ok: r.ok, texto, dados }
}

const corpos = arquivos.map((a) => {
  const texto = readFileSync(resolve(a), 'utf8')
  // Se um arquivo trouxer controle de transação, o ROLLBACK do runner deixaria
  // de valer pro que veio antes do COMMIT.
  if (/^\s*(begin|commit|rollback)\s*;/im.test(texto)) {
    console.error(`✗ ${a} contém BEGIN/COMMIT/ROLLBACK — o runner é o dono da transação.`)
    process.exit(2)
  }
  return `-- >>>>> ${a}\n${texto}`
})

const alvo = arquivos.join(' + ')

// ── 1) O ensaio, numa transação que o runner abre e fecha ────────────────────
const ensaio = await consultar(['begin;', ...corpos, 'rollback;'].join('\n'))

let falhou = false

if (!ensaio.ok) {
  // Erro de verdade (sintaxe, permissão, exceção não prevista). O teste foi
  // escrito pra não chegar aqui — se chegou, é problema, e a transação pode ter
  // abortado: a checagem de resíduo abaixo passa a ser essencial.
  console.error(`\n✗ ${alvo} — a execução falhou:\n`)
  console.error(ensaio.dados?.error?.message ?? ensaio.dados?.message ?? ensaio.texto)
  falhou = true
} else {
  const resumo = Array.isArray(ensaio.dados) ? ensaio.dados.at(-1)?.resumo : null
  if (!resumo || typeof resumo.falhas !== 'number') {
    console.error(`\n✗ ${alvo} — não veio resumo estruturado. O teste precisa terminar`)
    console.error('  num SELECT json_build_object(... "falhas" ...). Sem veredito explícito,')
    console.error(`  "não deu erro" não é aprovação.\n  Recebido: ${ensaio.texto.slice(0, 400)}`)
    falhou = true
  } else if (resumo.falhas > 0) {
    console.error(`\n✗ ${alvo} — ${resumo.falhas} passo(s) divergiram:\n`)
    for (const d of resumo.detalhe ?? []) {
      console.error(`  • ${d.passo}\n      esperado <${d.esperado}>  obtido <${d.obtido}>`)
    }
    falhou = true
  } else {
    console.log(`✓ ${alvo} — nenhuma divergência`)
  }
}

// ── 2) Confirmação do ROLLBACK, em OUTRA conexão ─────────────────────────────
// O ensaio mexe em fabio_notificacoes, que o briefing usa. Confiar no rollback
// implícito seria repetir o defeito que esta versão existe pra corrigir.
const residuo = await consultar(`
  select json_build_object(
    'coluna_lease',  (select count(*) from information_schema.columns
                       where table_schema='public' and table_name='fabio_notificacoes'
                         and column_name='lease_token'),
    'rpc_nova',      (select count(*) from pg_proc
                       where pronamespace='public'::regnamespace
                         and proname='fabio_claim_notificacao_por_referencia'),
    'indice_novo',   (select count(*) from pg_indexes
                       where schemaname='public' and indexname='uq_fabio_notif_por_referencia'),
    'linhas_teste',  (select count(*) from public.fabio_notificacoes
                       where referencia_id like 'teste-%'),
    'briefing_hoje', (select count(*) from public.fabio_notificacoes
                       where tipo='briefing_matinal' and dia_referencia=current_date)
  ) as estado`)

if (!residuo.ok) {
  console.error(`\n✗ não consegui confirmar o rollback:\n${residuo.texto}`)
  falhou = true
} else {
  const e = Array.isArray(residuo.dados) ? residuo.dados[0]?.estado : null
  const sujeira = e
    ? Object.entries(e).filter(([k, v]) => k !== 'briefing_hoje' && v > 0)
    : [['resposta inesperada', 1]]
  if (sujeira.length) {
    console.error(`\n✗ ROLLBACK NÃO LIMPOU — sobrou em produção: ${JSON.stringify(Object.fromEntries(sujeira))}`)
    falhou = true
  } else {
    console.log(`✓ rollback confirmado em outra conexão — zero resíduo` +
      ` (briefing de hoje intacto: ${e.briefing_hoje} linha(s))`)
  }
}

// Sai por process.exitCode, NUNCA por process.exit(): chamar exit() logo depois
// do fetch derruba o libuv no Windows com "UV_HANDLE_CLOSING" e devolve rc=127
// — o runner reprovaria um teste que passou. Rc errado é a mesma classe de
// mentira que este runner existe pra impedir.
process.exitCode = falhou ? 1 : 0
