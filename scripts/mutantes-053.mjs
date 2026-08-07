// Mutantes da 053 — a falta em um toque.
//
// U1 é o mutante que mais me interessa e o que menos parece defeito: a fila
// volta a filtrar só a devolutiva. Nada quebra, nada loga, o `app_declarar_
// falta` continua respondendo `claimed: true` — e o aviso de falta fica
// parado na tabela pra sempre. É o defeito de sempre desta casa: gancho
// criado, chamador não.
//
// U2 é o vizinho pior: escrevendo o filtro novo eu podia derrubar a devolutiva
// da fila sem perceber. Ninguém receberia devolutiva nenhuma, e a causa
// estaria numa migration sobre FALTA.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/053-falta-em-um-toque.sql'
const TESTE = 'supabase/migrations/053-falta-em-um-toque.test.sql'
const TEMP = 'supabase/migrations/_mutante-053.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'U1 — a fila volta a enxergar só a devolutiva (falta fica parada)',
    pega: 'passo "e a falta sem destinatario tambem aparece"',
    de: "        and n.tipo in ('experimental_registrada', 'experimental_falta')",
    para: "        and n.tipo = 'experimental_registrada'",
  },
  {
    nome: 'U2 — a fila passa a enxergar só a falta (devolutiva some)',
    pega: 'passo "a devolutiva CONTINUA na fila"',
    de: "        and n.tipo in ('experimental_registrada', 'experimental_falta')",
    para: "        and n.tipo = 'experimental_falta'",
  },
  {
    // Sem o tipo/os ids separados, o worker não tem como decidir qual claim
    // chamar — e decidir por chute é como o aviso vai pro lugar errado.
    nome: 'U3 — a fila deixa de separar registro_id de vinculo_id',
    pega: 'passo "falta traz vinculo_id e registro_id nulo"',
    de: `          'vinculo_id',     case when n.referencia_tipo = 'lead_experimental_falta'
                                 then n.referencia_id end,`,
    para: "          'vinculo_id',     n.referencia_id,",
  },
  {
    // A presença é o produto invisível deste toque: sem ela, a experimental
    // fica "sem presença forte" e volta a cobrar o professor amanhã.
    nome: 'U4 — o toque não grava presença',
    pega: 'passo "a presenca vira falta de fonte forte"',
    de: `  v_gravou := public.fn_registrar_presenca_experimental(
                p_vinculo_id, 'falta', 'professor_la_teacher');`,
    para: '  v_gravou := false;',
  },
  {
    // Fonte fraca não promove estado (034/009): o vínculo não vira 'faltou' e
    // o Emusys pode sobrescrever depois.
    nome: 'U5 — a falta é gravada como fonte fraca',
    pega: 'passo "e o vinculo passa a faltou"',
    de: "                p_vinculo_id, 'falta', 'professor_la_teacher');",
    para: "                p_vinculo_id, 'falta', 'emusys');",
  },
  {
    // O conserto da 042 desfeito: quem enfileira sai segurando o lease, o
    // worker recebe lease_vivo, e o aviso só sai 10 minutos depois.
    nome: 'U6 — a confirmação volta a segurar o lease',
    pega: 'passo "o aviso foi reivindicado na hora"',
    de: '  v_aviso := public.fabio_claim_aviso_falta_experimental(p_vinculo_id, 0);',
    para: '  v_aviso := public.fabio_claim_aviso_falta_experimental(p_vinculo_id, 10);\n  perform public.fabio_claim_aviso_falta_experimental(p_vinculo_id, 10);\n  v_aviso := public.fabio_claim_aviso_falta_experimental(p_vinculo_id, 10);',
  },
  {
    nome: 'U7 — aula já relatada e confirmada pode virar falta',
    pega: 'passos "aula ja relatada nao vira falta" e "a devolutiva confirmada continua de pe"',
    de: `  if v_registro.status = 'confirmado' then
    raise exception 'experimental_ja_registrada_como_realizada';
  end if;`,
    para: '',
  },
  {
    nome: 'U8 — a guarda de posse some',
    pega: 'passo "aula de outro professor e recusada"',
    de: `  if v_aula.professor_id is distinct from v_prof then
    raise exception 'aula_de_outro_professor';
  end if;`,
    para: '',
  },
  {
    // Unidade sem comercial perdendo o rastro: o aviso desaparece e ninguém
    // sabe que a família ficou sem retorno.
    nome: 'U9 — unidade sem comercial perde o aviso',
    pega: 'passo "unidade sem comercial nao perde o aviso"',
    de: `    insert into fabio_notificacoes
      (professor_id, destinatario_tipo, tipo, categoria, corpo, canal, status,
       motivo_pulada, referencia_tipo, referencia_id, destinatario_whatsapp)
    values
      (null, 'comercial', 'experimental_falta', 'informativa', v_corpo, 'whatsapp',
       'pulada_sem_destinatario', 'sem_contato_comercial_na_unidade',
       'lead_experimental_falta', p_vinculo_id::text, null)
    on conflict (referencia_tipo, referencia_id, canal)
      where referencia_tipo is not null and referencia_id is not null
    do nothing;`,
    para: '',
  },
  {
    // A mensagem ganhando cara de devolutiva: o consultor procura conteúdo
    // pedagógico numa aula que não aconteceu.
    nome: 'U10 — a mensagem de falta finge ter capítulo pedagógico',
    pega: 'passo "e NAO tem bloco pedagogico"',
    de: "    'Marcado pelo professor %s.\\n'",
    para: "    '*Como foi*\\n_(não preenchido)_\\n'\n    'Marcado pelo professor %s.\\n'",
  },
  {
    // GRANT ativo: `create or replace function` preserva privilégio, então
    // omitir o revoke viraria no-op depois de aplicado.
    nome: 'U11 — a fila do comercial fica aberta pro professor',
    pega: 'passo "professor nao mexe na fila do comercial"',
    de: 'revoke all on function public.fabio_avisos_comerciais_pendentes(integer) from public, anon, authenticated;',
    para: 'grant execute on function public.fabio_avisos_comerciais_pendentes(integer) to authenticated;',
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
