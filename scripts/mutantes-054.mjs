// Mutantes da 054 — quem confirmou volta a ter nome.
//
// X1 é o defeito original: a coluna volta a receber o que o cliente mandar. O
// teste só o mata porque tem um passo que chama a assinatura VELHA passando o
// id de outro usuário — sem esse passo, "confirmado_por = p_confirmado_por"
// pareceria correto (a casca manda null, então o campo ficaria nulo, e um
// teste que só olha "gravou alguma coisa?" não distingue nulo de errado).

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/054-quem-confirmou-tem-nome.sql'
const TESTE = 'supabase/migrations/054-quem-confirmou-tem-nome.test.sql'
const TEMP = 'supabase/migrations/_mutante-054.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    // O estado de antes: a casca repassa o autor informado e a função obedece.
    nome: 'X1 — o autor volta a vir de fora (forjável)',
    pega: 'passo "e IGNORA o autor informado"',
    de: `as $compat$
  select public.app_confirmar_registro_experimental(p_registro_id);
$compat$;`,
    para: `as $compat$
  select public.fn_confirmar_forjado(p_registro_id, p_confirmado_por);
$compat$;`,
    // Precisa de uma função auxiliar pra o mutante ser executável.
    prefixo: `create or replace function public.fn_confirmar_forjado(p_registro_id uuid, p_autor integer)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare v jsonb; begin
  v := public.app_confirmar_registro_experimental(p_registro_id);
  update lead_experimental_registros set confirmado_por = p_autor where id = p_registro_id;
  return v;
end $f$;
`,
  },
  {
    nome: 'X2 — o autor volta a nao ser gravado (nulo pra sempre)',
    pega: 'passo "quem confirmou fica gravado"',
    de: 'confirmado_por = v_usuario',
    para: 'confirmado_por = null',
  },
  {
    // Resolver pelo professor em vez do usuário: parece igual e não é. A
    // coluna é FK pra `usuarios`, e -54001 (professor) não existe lá.
    nome: 'X3 — grava o id do professor no lugar do usuario',
    pega: 'passo "quem confirmou fica gravado"',
    de: 'confirmado_por = v_usuario',
    para: 'confirmado_por = v_prof',
  },
  {
    // Regressões: o conserto de identidade não pode custar o ciclo.
    nome: 'X4 — a presença forte para de ser gravada',
    pega: 'passo "a presenca forte continua sendo gravada"',
    de: "case when v_origem = 'whatsapp' then 'fabio_audio' else 'professor_la_teacher' end)",
    para: "'emusys')",
  },
  {
    nome: 'X5 — a casca de compatibilidade some (aba aberta quebra)',
    pega: 'passo "a casca velha ainda funciona"',
    de: `create or replace function public.app_confirmar_registro_experimental(
  p_registro_id uuid, p_confirmado_por integer
) returns jsonb`,
    para: `create or replace function public.fn_casca_morta_054(
  p_registro_id uuid, p_confirmado_por integer
) returns jsonb`,
    // O mutante DERRUBA a casca antes: depois da migration aplicada, a
    // assinatura de duas mãos já existe em produção, e um mutante que só
    // deixasse de criá-la seria no-op — sobreviveria por engano, não por
    // fraqueza do teste. Mesma armadilha do `create or replace` que preserva
    // privilégio.
    prefixo: 'drop function if exists public.app_confirmar_registro_experimental(uuid, integer);\n',
  },
  {
    nome: 'X6 — a porta nova fica aberta pro anonimo',
    pega: 'passo "anonimo nao confirma nada"',
    de: 'revoke all on function public.app_confirmar_registro_experimental(uuid) from public, anon;',
    para: 'grant execute on function public.app_confirmar_registro_experimental(uuid) to anon;',
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
  writeFileSync(TEMP, (m.prefixo ?? '') + fonte.replace(m.de, m.para))
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
