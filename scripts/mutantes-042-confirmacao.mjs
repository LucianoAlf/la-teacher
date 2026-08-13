// Mutantes da 042 — a confirmacao enfileira, o worker entrega.
//
// P1 e P2 reintroduzem o defeito pelos DOIS lados, porque o conserto tem duas
// metades e cada uma sozinha nao resolve — foi o teste que me obrigou a
// descobrir isso, reprovando a primeira versao.
// P3 guarda o outro lado: afrouxar o vencimento nao pode deixar um worker
// roubar trabalho de quem esta trabalhando agora.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/042-confirmacao-enfileira-nao-segura.sql'
const TESTE = 'supabase/migrations/042-confirmacao-enfileira-nao-segura.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-042c.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    // O defeito original, inteiro: quem confirma volta a segurar 10 minutos.
    nome: 'P1 — a confirmacao volta a segurar o lease (10 min)',
    pega: 'passo "o worker CONSEGUE reivindicar o aviso"',
    de: 'select public.fabio_claim_aviso_comercial(p_registro_id, 0) into v_aviso;',
    para: 'select public.fabio_claim_aviso_comercial(p_registro_id) into v_aviso;',
  },
  {
    // Segurar por 1 minuto ja basta pra travar: o teste nao esta detectando
    // "o numero 10", esta detectando QUALQUER retencao.
    nome: 'P2 — a confirmacao segura so 1 minuto (ainda trava a fila)',
    pega: 'passo "o worker CONSEGUE reivindicar o aviso"',
    de: 'select public.fabio_claim_aviso_comercial(p_registro_id, 0) into v_aviso;',
    para: 'select public.fabio_claim_aviso_comercial(p_registro_id, 1) into v_aviso;',
  },
  {
    // A outra metade: com `<`, lease_expira_em = now() nao conta como vencido
    // e o worker segue barrado — em producao passaria por acidente, porque o
    // relogio anda entre transacoes. Nenhum teste conseguiria provar isso.
    nome: 'P3 — o vencimento volta a ser estrito (< em vez de <=)',
    pega: 'passo "o worker CONSEGUE reivindicar o aviso"',
    de: '      and fabio_notificacoes.lease_expira_em <= now())',
    para: '      and fabio_notificacoes.lease_expira_em < now())',
  },
  {
    // O risco do afrouxamento: se o vencimento virar "qualquer um pode pegar",
    // dois workers entregam a mesma devolutiva e o comercial recebe duas
    // vezes. O passo do segundo worker e o carrasco.
    nome: 'P4 — o vencimento vira porta e um segundo worker rouba o trabalho',
    pega: 'passo "um segundo worker NAO rouba o trabalho"',
    de: `    or (fabio_notificacoes.status = 'processando'
      and fabio_notificacoes.lease_expira_em is not null
      and fabio_notificacoes.lease_expira_em <= now())`,
    para: `    or (fabio_notificacoes.status = 'processando')`,
  },
]

let previstos = 0
let stale = 0

for (const m of MUTANTES) {
  if (!fonte.includes(m.de)) {
    console.log(`STALE  ${m.nome} — ancora nao existe mais na migration`)
    console.log(`       procurava: ${JSON.stringify(m.de.slice(0, 90))}`)
    stale++
    continue
  }
  writeFileSync(TEMP, fonte.replace(m.de, m.para))
  let passou = true
  try {
    execFileSync('node', ['scripts/rodar-teste-sql.mjs', TEMP, TESTE], { stdio: 'pipe' })
  } catch {
    passou = false
  }
  if (!passou) {
    previstos++
    console.log(`OK     morto: ${m.nome}  (${m.pega})`)
  } else {
    console.log(`FALHA  SOBREVIVEU: ${m.nome}  (${m.pega})`)
  }
}

try { unlinkSync(TEMP) } catch {}
console.log(`\n${previstos}/${MUTANTES.length} mutantes mortos` + (stale ? `  —  ${stale} ANCORA(S) PODRE(S)` : ''))
process.exitCode = previstos === MUTANTES.length ? 0 : 1
