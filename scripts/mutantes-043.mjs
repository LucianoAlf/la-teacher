// Mutantes da 043 — a fila do aviso comercial.
//
// Q1..Q3 atacam o ESPELHO (fila x claim): as duas clausulas tem que continuar
// falando da mesma coisa. Q4..Q6 atacam o lease na leitura do conteudo, que e
// o que impede dois workers de entregarem a mesma devolutiva.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/043-fila-do-aviso-comercial.sql'
const TESTE = 'supabase/migrations/043-fila-do-aviso-comercial.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-043.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    // A promessa da 036 ("e retomado quando o contato aparecer") vira letra
    // morta: ninguem varre esses rastros e o aviso fica preso pra sempre.
    nome: 'Q1 — a fila para de varrer o rastro sem destinatario',
    pega: 'passo "o rastro sem destinatario tambem aparece"',
    de: "          or (n.status = 'pulada_sem_destinatario')",
    para: '',
  },
  {
    // Unidade sem comercial cadastrado passa a empurrar trabalho de verdade
    // pra fora do lote — a fila anda, mas ninguem e entregue.
    nome: 'Q2 — o rastro sem destinatario passa na frente',
    pega: 'passo "o sem-destinatario vem DEPOIS do trabalho de verdade"',
    de: "        case when n.status = 'pulada_sem_destinatario' then 1 else 0 end as prioridade,",
    para: "        case when n.status = 'pulada_sem_destinatario' then 0 else 1 end as prioridade,",
  },
  {
    // O espelho se desloca: a fila passa a listar linha com lease VIVO, que o
    // claim recusa. Fila que mostra o que nao da pra fazer.
    nome: 'Q3 — o espelho se desloca (lista lease vivo, que o claim recusa)',
    pega: 'passo "a fila nao lista nada que o claim recuse"',
    de: `          (n.status = 'processando'
            and n.lease_expira_em is not null
            and n.lease_expira_em <= now())`,
    para: `          (n.status = 'processando')`,
  },
  {
    // Sem conferir o token, dois workers leem o mesmo corpo e o comercial
    // recebe a devolutiva duas vezes.
    nome: 'Q4 — o conteudo sai sem conferir o lease',
    pega: 'passo "com token errado, nao ve conteudo nenhum"',
    de: '        and n.lease_token = p_lease_token      -- so quem esta com o lease',
    para: '',
  },
  {
    // Aviso ja entregue voltando a ser legivel e reenviavel.
    nome: 'Q5 — enviada volta a ser lida pra envio',
    pega: 'passo "com token errado, nao ve conteudo nenhum"',
    de: "        and n.status = 'processando'",
    para: '',
  },
  {
    // Entregue nao pode voltar pra fila: o comercial receberia a mesma
    // devolutiva a cada varredura.
    nome: 'Q6 — a fila devolve tambem o que ja foi enviado',
    pega: 'passo "aviso enviado sai da fila"',
    de: `          or (n.status = 'falhou'
            and (n.proxima_tentativa_em is null or n.proxima_tentativa_em <= now()))`,
    para: `          or (n.status in ('falhou','enviada'))`,
  },
  {
    nome: 'Q7 — a fila interna fica legivel pelo app',
    pega: 'passo "authenticated nao le a fila comercial"',
    de: 'grant execute on function public.fabio_avisos_comerciais_pendentes(integer) to service_role;',
    para:
      'grant execute on function public.fabio_avisos_comerciais_pendentes(integer) to service_role;\n' +
      'grant execute on function public.fabio_avisos_comerciais_pendentes(integer) to authenticated;',
  },
  {
    // O corpo carrega a leitura de conversao — e o unico lugar onde ela viaja.
    nome: 'Q8 — o corpo do aviso fica legivel pelo app',
    pega: 'passo "authenticated nao le o corpo do aviso"',
    de: 'grant execute on function public.fabio_aviso_comercial_para_envio(uuid,uuid) to service_role;',
    para:
      'grant execute on function public.fabio_aviso_comercial_para_envio(uuid,uuid) to service_role;\n' +
      'grant execute on function public.fabio_aviso_comercial_para_envio(uuid,uuid) to authenticated;',
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
