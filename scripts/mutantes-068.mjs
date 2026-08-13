// Mutantes da 068 — o default que o próprio CHECK recusa.
//
// A migration é uma linha só, e é exatamente por isso que ela precisa de
// mutante: um teste que só olhasse "o INSERT sem status falha" ficaria VERDE
// sem a migration — hoje ele já falha, só que pelo motivo errado. O que está
// sob teste não é "falha", é "falha apontando a coluna".
//
// M2, M3 e M6 são os três consertos tentadores e errados. Os três deixam o
// banco funcionando e a tela feliz: M2 faz o INSERT incompleto PASSAR e nascer
// uma linha em voo que ninguém reservou; M3 e M6 legitimam o 'pendente' que a
// fila não tem. M4 é o pior de todos — troca o erro confuso por null silencioso.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/068-o-default-que-o-check-recusa.sql'
const TESTE = 'supabase/migrations/068-o-default-que-o-check-recusa.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-068.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

// Cada mutante RECRIA o defeito antes de rodar a migration mutada.
//
// Sem isto o harness morreria no dia do apply: com produção já consertada, um
// mutante que simplesmente NÃO conserta (M1, M5) encontraria o banco correto e
// passaria — e o arquivo continuaria imprimindo um 6/6 que não mede mais nada.
// É a mesma doença do teste da 060, que media o buraco da produção e ficou
// verde quando o buraco fechou sozinho. Recriando o defeito aqui dentro, o
// veredito vale amanhã igual valeu na hora de escrever.
//
// Roda dentro do BEGIN/ROLLBACK do runner, como todo o resto.
const RECRIA_O_DEFEITO = `alter table public.fabio_notificacoes
  alter column status set default 'pendente';
`

const ALVO = `alter table public.fabio_notificacoes
  alter column status drop default;`

const MUTANTES = [
  {
    // O controle: sem esta linha a migration não faz nada. Se este sobreviver,
    // o teste não está medindo a mudança — está medindo o que já existia.
    nome: 'M1 — a migration vira no-op (o default continua la)',
    pega: 'passo "INSERT sem status falha por NOT NULL, nao por CHECK"',
    de: ALVO,
    para: `-- o drop default foi removido pelo mutante`,
  },
  {
    // A opção (b) que foi descartada. O INSERT omisso PASSA e grava uma linha
    // 'processando' sem lease, sem tentativa e sem destinatário resolvido —
    // uma mensagem que ninguém vai enviar e ninguém vai concluir.
    nome: 'M2 — default vira processando (o INSERT incompleto passa a PASSAR)',
    pega: 'passo "INSERT sem status falha…" + "o DEFAULT contraditorio sumiu"',
    de: ALVO,
    para: `alter table public.fabio_notificacoes
  alter column status set default 'processando';`,
  },
  {
    // O conserto pela outra ponta: em vez de tirar o default, alargar o CHECK
    // pra aceitar 'pendente'. Cria um estado de entrada numa fila que não tem
    // caixa de entrada — a linha nasce no claim.
    nome: 'M3 — alarga o CHECK pra aceitar pendente em vez de tirar o default',
    pega: 'ancora do CHECK + passo do 23502 + passo do "pendente" barrado',
    de: ALVO,
    para: `alter table public.fabio_notificacoes
  drop constraint fabio_notificacoes_status_check;
alter table public.fabio_notificacoes
  add constraint fabio_notificacoes_status_check
  check (status = any (array['pendente','processando','enviada','falhou',
                             'pulada_preferencia','pulada_sem_destinatario']));`,
  },
  {
    // O mais perigoso: o erro some, mas a linha entra com status null. Deixa de
    // haver erro confuso e passa a não haver erro nenhum — e uma notificação
    // sem estado nunca é pega por nenhum worker.
    nome: 'M4 — tira o NOT NULL junto (omitir passa a gravar null em silencio)',
    pega: 'ancora "status continua NOT NULL" + passo do 23502',
    de: ALVO,
    para: `${ALVO}
alter table public.fabio_notificacoes
  alter column status drop not null;`,
  },
  {
    // Coluna errada. A migration roda, o rc é zero, e o defeito continua lá.
    nome: 'M5 — dropa o default da coluna errada (tentativas)',
    pega: 'passo "o DEFAULT contraditorio sumiu da coluna"',
    de: ALVO,
    para: `alter table public.fabio_notificacoes
  alter column tentativas drop default;`,
  },
  {
    // Derrubar a trava inteira também faz o INSERT omisso "funcionar" — com
    // 'pendente' gravado. É o conserto que resolve o sintoma destruindo a
    // garantia.
    nome: 'M6 — derruba o CHECK inteiro em vez de tirar o default',
    pega: 'ancora do CHECK + passo do "pendente" explicito barrado',
    de: ALVO,
    para: `alter table public.fabio_notificacoes
  drop constraint fabio_notificacoes_status_check;`,
  },
]

let mortos = 0
let stale = 0

// CONTROLE — com o defeito recriado, a migration DE VERDADE tem que consertar.
// Sem este passo, um 6/6 poderia significar só "todo mundo morre porque o
// recria-defeito sozinho já derruba o teste", que é vermelho por motivo errado.
writeFileSync(TEMP, RECRIA_O_DEFEITO + fonte)
let controleOk = true
try {
  execFileSync('node', ['scripts/rodar-teste-sql.mjs', TEMP, TESTE], { stdio: 'pipe' })
} catch {
  controleOk = false
}
console.log(controleOk
  ? 'OK     controle: com o defeito recriado, a migration real conserta'
  : 'FALHA  CONTROLE VERMELHO: a migration real nao conserta o defeito recriado')

for (const m of MUTANTES) {
  const n = fonte.split(m.de).length - 1
  if (n !== 1) {
    console.log(`STALE  ${m.nome} — ancora aparece ${n} vez(es), esperava 1`)
    stale++
    continue
  }
  writeFileSync(TEMP, RECRIA_O_DEFEITO + fonte.replace(m.de, m.para))
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
console.log(`\n${mortos}/${MUTANTES.length} mutantes mortos`
  + (stale ? `  —  ${stale} ANCORA(S) PODRE(S)` : '')
  + (controleOk ? '' : '  —  CONTROLE VERMELHO'))
process.exitCode = mortos === MUTANTES.length && controleOk && !stale ? 0 : 1
