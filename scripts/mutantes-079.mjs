// Mutantes da 079 — filtros de coração e professor no semáforo.
//
// V4 e V5 são os que guardam a regra da 071 ("cada faceta ignora o próprio
// filtro e respeita a outra"). Um seletor que se apaga sozinho é um beco: a
// coordenação escolhe uma unidade, some a lista das outras, e só o F5 traz de
// volta. É o defeito mais fácil de escrever e o mais difícil de perceber, porque
// a TELA continua funcionando.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/079-o-semaforo-ganha-filtros.sql'
const TESTE = 'supabase/migrations/079-o-semaforo-ganha-filtros.test.sql'
const TEMP = 'supabase/migrations/_mutante-079.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    // O filtro de "saudável" volta a esconder o verde calado — o rótulo promete
    // um grupo e entrega outro.
    nome: 'V1 — filtrar por coracao ainda aplica a regra "precisam de olho"',
    pega: 'passo "filtro saudavel mostra o verde calado"',
    de: `       where case when v_cor is null then precisa_olho else true end`,
    para: `       where precisa_olho`,
  },
  {
    nome: 'V2 — o filtro de professor nao filtra',
    pega: 'passo "filtro de professor nao traz aluno de colega"',
    de: `      select * from fac_cor where (v_cor is null or coracao = v_cor)`,
    para: `      select * from base where (v_cor is null or coracao = v_cor)`,
  },
  {
    // "Sem resposta" deixa de ser um coração: quem não respondeu vira buraco e
    // some do seletor — justamente o grupo que a coordenação precisa cobrar.
    nome: 'V3 — sem_resposta deixa de existir como coracao',
    pega: 'passo "sem_resposta lista quem nao respondeu"',
    de: `             coalesce(r.feedback, 'sem_resposta') as coracao,`,
    para: `             r.feedback as coracao,`,
  },
  {
    nome: 'V4 — a faceta de unidade passa a respeitar o proprio filtro (beco)',
    pega: 'passo "filtrando unidade, o seletor de unidade mantem as outras"',
    de: `              from fac_uni where unidade_id is not null`,
    para: `              from linha where unidade_id is not null`,
  },
  {
    nome: 'V5 — a faceta de professor passa a respeitar o proprio filtro (beco)',
    pega: 'passo "filtrando professor, o seletor de professor mantem os outros"',
    de: `              from fac_prof
             group by professor_id) p), '[]'::jsonb),`,
    para: `              from linha
             group by professor_id) p), '[]'::jsonb),`,
  },
  {
    // Faceta que ignora TUDO: oferece unidade que, escolhida, devolve lista
    // vazia. Pior que o beco — é o seletor mentindo sobre onde tem gente.
    nome: 'V6 — a faceta de unidade ignora tambem o filtro de professor',
    pega: 'passo "faceta de unidade respeita o filtro de professor"',
    de: `    fac_uni as (
      select * from base
       where (v_cor is null or coracao = v_cor)
         and (p_professor_id is null or professor_id = p_professor_id)
    ),`,
    para: `    fac_uni as (
      select * from base
    ),`,
  },
  {
    nome: 'V7 — coracao invalido passa direto (filtro silencioso que nao filtra)',
    pega: 'passo "coracao invalido explode"',
    de: `  if v_cor is not null and v_cor not in ('verde','amarelo','vermelho','sem_resposta') then
    raise exception 'coracao_invalido';
  end if;`,
    para: `  if false then
    raise exception 'coracao_invalido';
  end if;`,
  },
  {
    nome: 'V8 — o corte para de se anunciar',
    pega: 'passo "sem_resposta lista quem nao respondeu"',
    de: `      'truncado',         (select count(*) from alvo) > v_lim,`,
    para: `      'truncado',         false,`,
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
