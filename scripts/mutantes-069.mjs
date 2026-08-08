// Mutantes da 069 — a coordenação tem perfil.
//
// V2 é o que assusta: uma RPC de perfil que ignora o `auth.uid()` funciona
// perfeitamente na tela de quem testou (o primeiro da lista) e mostra o dado de
// OUTRA PESSOA pra todo mundo depois. Telefone, e-mail, foto. É por isso que o
// teste confere DOIS coordenadores, um de cada vez: com um só, este mutante
// sobreviveria.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/069-a-coordenacao-tem-perfil.sql'
const TESTE = 'supabase/migrations/069-a-coordenacao-tem-perfil.test.sql'
const TEMP = 'supabase/migrations/_mutante-069.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    // Qualquer um que esteja logado — inclusive os 44 professores — abre o
    // perfil da coordenação.
    nome: 'V1 — para de checar se quem chamou e da coordenacao',
    pega: 'passos "sem identidade recusa" e "professor NAO abre"',
    de: `  if not public.fn_e_coordenacao_la_teacher() then
    raise exception 'apenas_admin';
  end if;`,
    para: `  -- guard removido pelo mutante`,
  },
  {
    // O perfil de outra pessoa. Passa liso com um coordenador só na base.
    nome: 'V2 — devolve o perfil de OUTRA pessoa (ignora o auth.uid)',
    pega: 'passos "coordenador N recebe o PROPRIO nome/email"',
    de: `   where u.auth_user_id = auth.uid()
     and coalesce(u.ativo, true);`,
    para: `   where coalesce(u.ativo, true)
   order by u.id
   limit 1;`,
  },
  {
    // A chave some do JSON e o componente de foto quebra em quem nunca subiu
    // avatar — que é a maioria.
    nome: 'V3 — o contrato perde o avatar_url',
    pega: 'passo "o contrato traz todas as chaves da tela"',
    de: `           'avatar_url',  u.avatar_url,`,
    para: ``,
  },
  // V4 era "devolve nulo em vez de negar quando não acha a linha". Ele
  // SOBREVIVEU — e tinha razão: o guard lê a MESMA `usuarios` com o mesmo
  // predicado, então "passou no guard e não achou" é inalcançável. Em vez de
  // manter um mutante que não mata nada, a linha saiu da migration. O achado
  // foi que ela não fazia nada. (Mesmo caminho do `analyze` na 064.)
  {
    // `create or replace` PRESERVA privilégios — o mutante tem que dar o grant
    // ATIVAMENTE, senão não mede nada.
    nome: 'V5 — o perfil fica aberto pro anon',
    pega: 'passo "anon NAO abre o perfil da coordenacao"',
    de: `revoke all on function public.app_meu_perfil_coordenacao() from anon;`,
    para: `grant execute on function public.app_meu_perfil_coordenacao() to anon;`,
  },
]

let mortos = 0
let stale = 0

for (const m of MUTANTES) {
  const n = fonte.split(m.de).length - 1
  if (n !== 1) {
    console.log(`STALE  ${m.nome} — ancora aparece ${n} vez(es), esperava 1`)
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
    mortos++
    console.log(`OK     morto: ${m.nome}  (${m.pega})`)
  } else {
    console.log(`FALHA  SOBREVIVEU: ${m.nome}  (${m.pega})`)
  }
}

try { unlinkSync(TEMP) } catch {}
console.log(`\n${mortos}/${MUTANTES.length} mutantes mortos` + (stale ? `  —  ${stale} ANCORA(S) PODRE(S)` : ''))
process.exitCode = mortos === MUTANTES.length ? 0 : 1
