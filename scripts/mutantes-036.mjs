// Mutantes da 036 — o aviso ao comercial.
//
// O plano trazia estes 7 como python inline. Viraram script pelo mesmo motivo
// dos outros: ancora podre e FALHA, nao aviso — mutante cita SQL literal e
// apodrece em silencio quando a migration muda.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/036-aviso-comercial-experimental.sql'
const TESTE = 'supabase/migrations/036-aviso-comercial-experimental.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-036.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const RAMO_EXCECAO = `    (status = 'pulada_sem_destinatario'
      and destinatario_tipo = 'comercial'
      and professor_id is null
      and destinatario_whatsapp is null)`

const MUTANTES = [
  {
    // O defeito classico: unidade sem contato e o aviso evapora. Ninguem
    // reclama, porque ninguem sabe que ele existiu.
    nome: 'M1 — sem contato, o aviso some em silencio',
    pega: 'passo "sem contato deixa RASTRO na fila"',
    de: `    insert into fabio_notificacoes
      (professor_id, destinatario_tipo, tipo, categoria, corpo, canal, status,
       motivo_pulada, referencia_tipo, referencia_id, destinatario_whatsapp)
    values
      (null, 'comercial', 'experimental_registrada', 'informativa', v_corpo, 'whatsapp',
       'pulada_sem_destinatario', 'sem_contato_comercial_na_unidade',
       'lead_experimental_registro', p_registro_id::text, null)
    on conflict (referencia_tipo, referencia_id, canal)
      where referencia_tipo is not null and referencia_id is not null
    do nothing;
    return jsonb_build_object('ok', true, 'claimed', false, 'motivo', 'sem_destinatario');`,
    para: `    return jsonb_build_object('ok', true, 'claimed', false, 'motivo', 'sem_destinatario');`,
  },
  {
    nome: 'M2 — o CHECK de destinatario vira permissivo',
    pega: 'passo "aviso sem destinatario rejeitado"',
    de: `  add constraint chk_notificacao_destinatario check (
${RAMO_EXCECAO}
    or
    (destinatario_tipo = 'professor' and professor_id is not null)
    or
    (destinatario_tipo = 'comercial' and destinatario_whatsapp is not null)
  );`,
    para: '  add constraint chk_notificacao_destinatario check (true);',
  },
  {
    // Volta o numero chumbado do n8n — o no que ainda se chama "Clayton".
    nome: 'M3 — o destinatario deixa de vir da unidade (hardcode)',
    pega: 'passo "destinatario resolvido pela unidade"',
    de: 'v_contato.whatsapp,',
    para: "'5521999999999',",
  },
  {
    // Sem o ramo de excecao, a unica forma de registrar a falta de
    // destinatario passa a ser... nao registrar.
    nome: 'M4 — o CHECK volta a se contradizer com o rastro de ausencia',
    pega: 'passo "rastro legitimo de ausencia continua aceito"',
    de: RAMO_EXCECAO + '\n    or\n',
    para: '',
  },
  {
    // Sem lease, o argumento que ganhou a decisao contra o n8n ("a fila do
    // Fabio tem lease, retry e recibo") fica vazio.
    nome: 'M5 — o claim nasce sem lease (volta o insert cru)',
    pega: 'passo "aviso nasce com lease vivo"',
    de: "'whatsapp', 'processando', 1, v_token, now() + make_interval(mins => p_lease_minutos),",
    para: "'whatsapp', 'processando', 0, null, null,",
  },
  {
    // O aviso fica preso pra sempre: o contato foi cadastrado depois e
    // ninguem volta pra buscar.
    nome: 'M6 — rastro de ausencia nunca e retomado',
    pega: 'passo "pulada_sem_destinatario e retomada apos cadastro"',
    de: "    or (fabio_notificacoes.status = 'pulada_sem_destinatario')",
    para: '',
  },
  {
    // A excecao vira PORTA: qualquer linha com esse status passa, inclusive
    // aviso de professor mal formado.
    nome: 'M7 — o ramo de excecao vira porta',
    pega: 'passo "excecao nao vira porta p/ outro formato"',
    de: RAMO_EXCECAO,
    para: "    status = 'pulada_sem_destinatario'",
  },
  {
    // Acrescentado ao plano: revoke sem carrasco e convencao, nao regra.
    nome: 'M8 — o telefone do comercial fica legivel pelo app',
    pega: 'passo "authenticated nao le os contatos comerciais"',
    de: 'revoke all on table public.unidade_contato_comercial from public, anon, authenticated;',
    para: 'revoke all on table public.unidade_contato_comercial from public;',
  },
  {
    nome: 'M9 — qualquer professor logado enfileira aviso comercial',
    pega: 'passo "authenticated nao enfileira aviso comercial"',
    de: 'grant execute on function public.fabio_claim_aviso_comercial(uuid,integer) to service_role;',
    para:
      'grant execute on function public.fabio_claim_aviso_comercial(uuid,integer) to service_role;\n' +
      'grant execute on function public.fabio_claim_aviso_comercial(uuid,integer) to authenticated;',
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
