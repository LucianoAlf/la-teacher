// Mutantes da 083 — a cobrança para de aceitar plano como relato.
//
// V1 e V2 são literalmente o estado de antes: o plano do Emusys voltando a
// valer como registro, e a presença voltando a ser lida só pelo gêmeo-âncora.
// Repare que nenhum dos dois QUEBRA nada — a view carrega, a cobrança sai, a
// mensagem chega bonita no WhatsApp do professor. Ela só está errada pra menos,
// que é o jeito de errar que ninguém reclama.
//
// V5 e V6 são o lado oposto: cobrar aula que não devia. Sem eles, "conserto"
// vira `where true` e o teste bate palma.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/083-a-cobranca-para-de-aceitar-plano-como-relato.sql'
const TESTE = 'supabase/migrations/083-a-cobranca-para-de-aceitar-plano-como-relato.test.sql'
const TEMP = 'supabase/migrations/_mutante-083.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'V1 — o plano do Emusys volta a valer como relato (o estado de antes)',
    pega: 'passo "plano do Emusys NAO conta como relato"',
    de: `    and nullif(btrim(coalesce(alvo.anotacoes_fabio, ''::text)), ''::text) is null;`,
    para: `    and nullif(btrim(coalesce(alvo.anotacoes_fabio, alvo.anotacoes, ''::text)), ''::text) is null;`,
  },
  {
    // O estado de antes, na letra: a presença volta a ser lida SÓ da linha da
    // aula-âncora, e o gêmeo que o Emusys sorteou decide se a aula existe.
    nome: 'V2 — a presenca volta a ser lida so do gemeo-ancora (o estado de antes)',
    pega: 'passos "gemeo com falta nao esconde mais" e "a presenca resolvida e a AFIRMADA"',
    de: `                 where gem.unidade_id = ae.unidade_id`,
    para: `                 where gem.id = ae.id and gem.unidade_id = ae.unidade_id`,
  },
  {
    nome: 'V3 — o status resolvido volta a ser o do gemeo-ancora sorteado',
    pega: 'passo "a presenca resolvida e a AFIRMADA, nao a da ancora"',
    de: `              case when bool_or(g.st = 'presente'::text) then 'presente'::text`,
    para: `              case when bool_and(g.st = 'presente'::text) then 'presente'::text`,
  },
  {
    nome: 'V4 — a aula esconde que tem plano no Emusys (a mensagem volta a acusar injustamente)',
    pega: 'passos "a mesma aula se anuncia" e "fn_pendencias_do_professor conta"',
    de: `    nullif(btrim(coalesce(alvo.anotacoes, ''::text)), ''::text) is not null as tem_plano_emusys`,
    para: `    false as tem_plano_emusys`,
  },
  {
    nome: 'V5 — "nao lancado" volta a ser tratado como falta (a aula muda some da cobranca)',
    pega: 'passo "chamada nunca lancada continua cobravel"',
    de: `    and coalesce(pres.status_presenca, 'presente'::text) <> 'falta'::text`,
    para: `    and coalesce(pres.status_presenca, 'falta'::text) <> 'falta'::text`,
  },
  {
    nome: 'V6 — falta em TODOS os gemeos passa a virar pendencia (cobra aula que nao aconteceu)',
    pega: 'passo "falta em TODOS os gemeos continua fora"',
    de: `                   when count(*) > 0                     then 'falta'::text`,
    para: `                   when count(*) > 0                     then 'presente'::text`,
  },
  {
    nome: 'V7 — o relato de verdade deixa de fechar a pendencia (cobra quem ja registrou)',
    pega: 'passo "relato de verdade (anotacoes_fabio) continua fechando a pendencia"',
    de: `    and nullif(btrim(coalesce(alvo.anotacoes_fabio, ''::text)), ''::text) is null;

comment on view`,
    para: `    and true;

comment on view`,
  },
  {
    nome: 'V8 — a contagem "com plano no Emusys" ignora a aula (numero volta a zero)',
    pega: 'passo "fn_pendencias_do_professor conta as aulas com plano no Emusys"',
    de: `      bool_or(p.tem_plano_emusys) as tem_plano_emusys,`,
    para: `      bool_and(false) as tem_plano_emusys,`,
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
