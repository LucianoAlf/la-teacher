// Mutantes da 065 — o painel da coordenação tem fonte.
//
// Os cinco mutantes são os cinco jeitos plausíveis de esta RPC ficar errada sem
// ninguém perceber: ela responde, o painel desenha, os números parecem números.
// Nenhum deles quebra a tela — é por isso que precisam de teste.
//
// V2 é o mais importante do arquivo. A fila alfabética JÁ FOI AO AR uma vez, no
// painel de equipe, com a tela escrita "por urgência" em cima dela. Lista
// ordenada errado parece lista ordenada.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/065-o-painel-da-coordenacao-tem-fonte.sql'
const TESTE = 'supabase/migrations/065-o-painel-da-coordenacao-tem-fonte.test.sql'
const TEMP = 'supabase/migrations/_mutante-065.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    // A RPC responde pra qualquer um que esteja logado — inclusive os 44
    // professores, que passariam a ver a pendência dos colegas.
    nome: 'V1 — a RPC deixa de checar se quem chamou e coordenacao',
    pega: 'passo "sem identidade a RPC recusa"',
    de: `  if not public.fn_e_coordenacao_la_teacher() then
    raise exception 'apenas_admin';
  end if;`,
    para: `  -- guard removido pelo mutante`,
  },
  {
    // O defeito que já aconteceu: a tela diz "ordenado por urgência" e a fila
    // vem por nome. Quem tem 7 dias de atraso vai parar no meio da lista.
    nome: 'V2 — a fila volta a ser alfabetica (o defeito que ja foi ao ar)',
    pega: 'passo "a fila desce por urgencia"',
    de: `order by p.em_aberto desc, p.pior_atraso desc, p.professor_nome)`,
    para: `order by p.professor_nome)`,
  },
  {
    // O seletor de unidade continua na tela e para de fazer efeito: a Juliana
    // filtra Campo Grande e continua vendo a escola inteira.
    nome: 'V3 — o filtro de unidade vira enfeite',
    pega: 'passo "filtrar por unidade devolve menos que o total"',
    de: `       and (p_unidade_id is null or unidade_id = p_unidade_id)`,
    para: `       and (p_unidade_id is null or true)`,
  },
  {
    // Janela aberta: o painel cobra o professor pela aula que ele está dando
    // agora. São 218 aulas de hoje entrando na conta de atraso.
    nome: 'V4 — a janela passa a incluir HOJE (cobra a aula em andamento)',
    pega: 'passos "a aula de HOJE nao entra" e "o resumo bate com a view"',
    de: `       and data_aula <  current_date`,
    para: `       and data_aula <= current_date`,
  },
  {
    // `create or replace` PRESERVA privilégios — por isso o mutante de
    // permissão tem que dar o grant ATIVAMENTE. Sem isso ele não mede nada.
    nome: 'V5 — a RPC fica aberta pro anon',
    pega: 'passo "anon NAO executa a RPC do painel"',
    de: `revoke all on function public.app_coordenacao_em_aberto(int, uuid) from anon;`,
    para: `grant execute on function public.app_coordenacao_em_aberto(int, uuid) to anon;`,
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
