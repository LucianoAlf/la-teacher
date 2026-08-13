// Mutantes da 077 — a coordenação lê o semáforo.
//
// Cada mutante reintroduz um defeito que já aconteceu de verdade nesta casa,
// e o teste tem que MORRER por ele. Verde que sobrevive a tudo é decoração.
//
// V1 é o defeito que a migration existe pra consertar: a observação sumir do
// payload. V4 é a "duas contagens da carteira" voltando (09/08: 54 linhas a
// mais em 26 professores, por renovação de contrato). V6 é o corte silencioso
// — a lista continua funcionando, só mente sobre o tamanho.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/077-a-coordenacao-le-o-semaforo.sql'
const TESTE = 'supabase/migrations/077-a-coordenacao-le-o-semaforo.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-077.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    // O estado de ANTES da 077: o dado existe, ninguém lê. Repare que a tela
    // continua carregando e os números continuam certos.
    nome: 'V1 — a observacao volta a nao sair no payload',
    pega: 'passo "a observacao do professor sai no payload"',
    de: `          'observacao',      o.observacao,`,
    para: `          'observacao',      null,`,
  },
  {
    // Só alarme entra: o elogio e o pedido de material — o texto que a
    // coordenação nunca recebeu — continuam sem leitor.
    nome: 'V2 — so coracao serve, recado do professor nao conta',
    pega: 'passo "a observacao do professor sai no payload" (o verde some da lista)',
    de: `             (r.feedback in ('vermelho','amarelo') or r.observacao is not null)`,
    para: `             (r.feedback in ('vermelho','amarelo'))`,
  },
  {
    // A lista vira despejo da carteira inteira — a mesma parede de texto que
    // já deixou o escalonamento diário ilegível.
    nome: 'V3 — a lista devolve todo mundo (verde calado incluso)',
    pega: 'passo "verde sem recado nao entra"',
    de: `       where precisa_olho`,
    para: `       where true`,
  },
  {
    // O erro de 09/08 voltando: contar LINHA da carteira em vez de aluno. A
    // coordenação vê 24 onde o professor vê 21, e cobra por diferença de SQL.
    nome: 'V4 — o resumo volta a contar linha da carteira',
    pega: 'passo "resumo conta aluno e nao linha da carteira"',
    de: `          'alunos',         count(distinct aluno_id),`,
    para: `          'alunos',         count(*),`,
  },
  {
    // A guarda cai: qualquer autenticado lê a observação crua sobre alunos de
    // qualquer professor. É exatamente a policy que a 074 teve que consertar.
    nome: 'V5 — a guarda de coordenacao some',
    pega: 'passo "quem nao e coordenacao nao le"',
    de: `  if not public.fn_e_coordenacao_la_teacher() then
    raise exception 'apenas_admin';
  end if;`,
    para: `  if false then
    raise exception 'apenas_admin';
  end if;`,
  },
  {
    // Corte silencioso: devolve 1 de 200 e diz que está tudo ali.
    nome: 'V6 — o corte para de se anunciar',
    pega: 'passo "corte se anuncia (truncado + total real)"',
    de: `      'truncado',         (select count(*) from linha where precisa_olho) > v_lim,`,
    para: `      'truncado',         false,`,
  },
  {
    // O filtro de unidade some do recorte: a coordenação escolhe "Barra" e
    // recebe a escola inteira — pior que não ter filtro, porque ela confia.
    nome: 'V7 — o filtro de unidade nao filtra',
    pega: 'passo "filtro de unidade nao devolve outra unidade"',
    de: `       where p_unidade_id is null or unidade_id = p_unidade_id`,
    para: `       where true`,
  },
  {
    // As opções do filtro passam a nascer do universo JÁ filtrado: escolheu
    // uma unidade, as outras somem do seletor e não há como voltar sem F5.
    nome: 'V8 — as opcoes do filtro nascem do universo filtrado (beco sem saida)',
    pega: 'passo "opcoes de unidade sobrevivem ao filtro"',
    de: `        from carteira c
       where c.unidade_id is not null`,
    para: `        from universo c
       where c.unidade_id is not null`,
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
