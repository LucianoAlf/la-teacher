// Mutantes da 062 — a coordenação do LA Teacher tem lista própria.
//
// V1 é o estado de antes: a guarda volta a ser `perfil = 'admin'`. Repare que
// ele NÃO quebra nenhum passo "feliz" — os quatro da coordenação também são
// admin, então tudo que testasse só "eles entram" continuaria verde. Quem mata
// V1 é o passo do admin de fora, e só ele.
//
// V6 é o par: permissão. `create or replace` PRESERVA privilégios, então
// mutante de permissão precisa mexer no grant/revoke de propósito — foi assim
// que o X5 da 054 e os da 027/028 sobreviveram uma vez.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/062-coordenacao-do-la-teacher-tem-lista.sql'
const TESTE = 'supabase/migrations/062-coordenacao-do-la-teacher-tem-lista.test.sql'
const TEMP = 'supabase/migrations/_mutante-062.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'V1 — a guarda volta a ser perfil=admin (as 11 pessoas de novo)',
    pega: 'passo "admin do LA Report FORA da lista nao abre"',
    de: `  if not public.fn_e_coordenacao_la_teacher() then
    raise exception 'apenas_admin' using errcode = '42501';
  end if;`,
    para: `  if not exists (select 1 from public.usuarios u
                  where u.auth_user_id = auth.uid()
                    and coalesce(u.ativo, true) and u.perfil = 'admin') then
    raise exception 'apenas_admin' using errcode = '42501';
  end if;`,
  },
  {
    // Desligar alguém deixa de tirar o painel: quem sai da escola continua
    // liberando professor e mandando WhatsApp em nome do Fábio.
    nome: 'V2 — a lista ignora o desligamento (usuarios.ativo)',
    pega: 'passo "quem foi desligado perde o painel"',
    de: `       and coalesce(u.ativo, true)`,
    para: `       and true`,
  },
  {
    // Responde "sim" pra qualquer um que perguntar.
    nome: 'V3 — a funcao para de olhar quem perguntou',
    pega: 'passos "a funcao responde sobre quem perguntou" e o do admin de fora',
    de: `     where u.auth_user_id = auth.uid()`,
    para: `     where u.auth_user_id is not null`,
  },
  {
    // A lista vira legível pelo PostgREST: o alvo de quem quer escalar
    // privilégio fica publicado.
    nome: 'V4 — a lista fica legivel pra quem esta logado',
    pega: 'passo "a lista nao vaza pra quem esta logado"',
    de: `alter table public.la_teacher_coordenacao enable row level security;
revoke all on table public.la_teacher_coordenacao from public, anon, authenticated;`,
    para: `alter table public.la_teacher_coordenacao disable row level security;
grant select on table public.la_teacher_coordenacao to authenticated;`,
  },
  {
    // O seed erra e alguém da coordenação fica de fora — descobre na
    // segunda-feira, quando precisar liberar um professor.
    nome: 'V5 — o seed esquece a Juliana e o Quintela',
    pega: 'passo "os quatro combinados estao na lista"',
    de: `   'juliana@lamusic.com.br',    -- Juliana — coordenadora da LA Music School
   'quintela@lamusic.com.br'    -- Quintela — coordenador da LA Music Kids`,
    para: `   'lucianoalf.la@gmail.com'`,
  },
  {
    // Permissão: `create or replace` preserva privilégios, então o mutante
    // precisa revogar de propósito pra provar que o grant é do arquivo.
    nome: 'V6 — o painel perde o grant e para pra todo mundo',
    pega: 'passo "quem esta na lista abre o painel"',
    de: `grant execute on function public.app_professores_para_liberar() to authenticated;`,
    para: `revoke execute on function public.app_professores_para_liberar() from authenticated;`,
  },
  {
    // O seed abre demais: entra todo admin, e a 062 não teria servido pra nada.
    nome: 'V7 — o seed entra com todos os admins',
    pega: 'passo "e ninguem entrou de carona"',
    de: ` where u.email in (
   'lucianoalf.la@gmail.com',   -- Luciano Alf — diretor geral
   'hugo@gmail.com',            -- Hugo — coordenador de tecnologia
   'juliana@lamusic.com.br',    -- Juliana — coordenadora da LA Music School
   'quintela@lamusic.com.br'    -- Quintela — coordenador da LA Music Kids
 )`,
    para: ` where u.perfil = 'admin'`,
  },
]

let previstos = 0
let stale = 0

for (const m of MUTANTES) {
  const n = fonte.split(m.de).length - 1
  if (n !== 1) {
    console.log(`STALE  ${m.nome} — ancora aparece ${n} vez(es), esperava 1`)
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
