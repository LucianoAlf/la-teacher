// Mutantes da 045 — a porta de entrada do professor na experimental.
//
// Esta RPC devolve NOME DE LEAD. Falha de leitura aqui nao estraga dado
// nenhum — so entrega a base de leads da escola a quem pediu. Por isso os
// dois primeiros sao de posse.
//
// S2 e COMBINADO de proposito: a aula orfa e defendida em duas camadas (a
// exigencia de usuario resolvido, e o `=` que devolve NULL contra null).
// Cada uma sozinha continua barrando — foi medido. Um mutante que so mexe
// numa delas sobreviveria sem que houvesse defeito, e "sobreviveu" viraria
// ruido no relatorio em vez de sinal.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/045-app-experimental-do-professor.sql'
const TESTE = 'supabase/migrations/045-app-experimental-do-professor.test.sql'
const TEMP = 'supabase/migrations/_mutante-045.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'S1 — a posse some do JOIN (qualquer professor le qualquer lead)',
    pega: 'passo "intruso NAO le experimental alheia"',
    de: '    and ae.professor_id = v_prof;',
    para: ';',
  },
  {
    nome: 'S2 — aula orfa passa a casar com sessao orfa (as duas camadas)',
    pega: 'passo "sessao sem professor NAO le aula orfa"',
    de: `  if v_prof is null then
    raise exception 'sem_professor_vinculado';
  end if;`,
    para: '',
    extra: {
      de: '    and ae.professor_id = v_prof;',
      para: '    and ae.professor_id is not distinct from v_prof;',
    },
  },
  {
    // A fronteira nova desta migration. O professor conduz melhor sabendo que
    // ela canta no chuveiro; nao conduz melhor sabendo que a mae ja perguntou
    // o preco — conduz diferente.
    nome: 'S3 — o sinal comercial volta a chegar no professor',
    pega: 'passo "o sinal de conversao NAO chega ao professor"',
    de: `    'contexto', (public.fn_experimental_contexto_seguro(le.contexto_ia)
                   #- '{para_a_devolutiva,atencao_conversao}'),`,
    para: "    'contexto', public.fn_experimental_contexto_seguro(le.contexto_ia),",
  },
  {
    // Trocar a lista branca da 028 por contexto_ia cru: o `porque` (que cita
    // o preco) e tudo mais que o LLM inventar entram de carona.
    nome: 'S4 — a lista branca da 028 e trocada pelo contexto cru',
    pega: 'passo "e o PORQUE do sinal muito menos"',
    de: `    'contexto', (public.fn_experimental_contexto_seguro(le.contexto_ia)
                   #- '{para_a_devolutiva,atencao_conversao}'),`,
    para: "    'contexto', (le.contexto_ia #- '{para_a_devolutiva,atencao_conversao}'),",
  },
  {
    // A tela reabriria um texto que o professor ja tinha substituido — e ele
    // confirmaria a versao velha achando que era a dele.
    // Inverte o filtro em vez de so remove-lo: sem o filtro, os dois registros
    // ficam elegiveis com o MESMO criado_em (now() e constante dentro de uma
    // transacao), o `order by` nao discrimina e o mutante sobrevive por sorte
    // metade das vezes. Mutante que depende de sorte nao e carrasco.
    nome: 'S5 — a tela reabre o registro descartado',
    pega: 'passo "a tela reabre o registro VIGENTE, nao o descartado"',
    de: "       where r.vinculo_id = v.id and r.status <> 'descartado'",
    para: "       where r.vinculo_id = v.id and r.status = 'descartado'",
  },
  {
    nome: 'S6 — anon passa a ler a experimental',
    pega: 'passo "anon nao le experimental"',
    de: 'grant execute on function public.app_experimental_do_professor(bigint) to service_role, authenticated;',
    para:
      'grant execute on function public.app_experimental_do_professor(bigint) to service_role, authenticated;\n' +
      'grant execute on function public.app_experimental_do_professor(bigint) to anon;',
  },
]

let previstos = 0
let stale = 0

for (const m of MUTANTES) {
  const trocas = [{ de: m.de, para: m.para }, ...(m.extra ? [m.extra] : [])]
  let mutado = fonte
  let ok = true
  for (const t of trocas) {
    if (!mutado.includes(t.de)) {
      console.log(`STALE  ${m.nome} — ancora nao existe mais na migration`)
      console.log(`       procurava: ${JSON.stringify(t.de.slice(0, 90))}`)
      ok = false
      break
    }
    mutado = mutado.replace(t.de, t.para)
  }
  if (!ok) { stale++; continue }

  writeFileSync(TEMP, mutado)
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
