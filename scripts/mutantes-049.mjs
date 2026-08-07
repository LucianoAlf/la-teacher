// Mutantes da 049 — a mesma fronteira nos dois caminhos.
//
// W1 reintroduz exatamente o estado que existia até agora: a tela cortando e o
// Fábio não. Ele é o mutante que prova que o passo de COMPARAÇÃO entre os dois
// caminhos vale mais que os dois passos individuais — porque foi a ausência
// dessa comparação que deixou a divergência viver.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/049-mesma-fronteira-nos-dois-caminhos.sql'
const TESTE = 'supabase/migrations/049-mesma-fronteira-nos-dois-caminhos.test.sql'
const TEMP = 'supabase/migrations/_mutante-049.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'W1 — o Fábio volta a ver o sinal comercial (a divergência de antes)',
    pega: 'passo "os dois caminhos concordam sobre o sinal"',
    de: "           'contexto',             (e.contexto #- '{para_a_devolutiva,atencao_conversao}')",
    para: "           'contexto',             e.contexto",
  },
  {
    // Cortar demais: o professor perde o que a família espera, que é
    // pedagógico e é dele. Já aconteceu com a anamnese — eu cortei por
    // privacidade e o Alf reverteu, porque omitir também causa dano.
    nome: 'W2 — o corte engole o bloco inteiro (leva junto o que é do professor)',
    pega: 'passo "e os dois levam o que a familia espera"',
    de: "           'contexto',             (e.contexto #- '{para_a_devolutiva,atencao_conversao}')",
    para: "           'contexto',             (e.contexto - 'para_a_devolutiva')",
  },
  {
    nome: 'W3 — o corte engole a dica de condução',
    pega: 'passo "o Fabio leva a dica de conducao"',
    de: "           'contexto',             (e.contexto #- '{para_a_devolutiva,atencao_conversao}')",
    para: "           'contexto',             (e.contexto - 'como_conduzir')",
  },
  {
    // A guarda de posse desta RPC: sem professor_id ela mostraria a
    // experimental de qualquer um.
    nome: 'W4 — a RPC do Fábio aceita professor nulo',
    pega: 'levanta na chamada — a guarda de posse da 029',
    de: `    raise exception 'professor_id_obrigatorio: o Fabio so pode mostrar as experimentais DESTE professor.'
      using errcode = '42501';`,
    para: '    return \'[]\'::jsonb;',
    esperaSobreviver: true,
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
  const previsto = m.esperaSobreviver ? passou : !passou
  if (previsto) {
    previstos++
    console.log(
      `OK     ${m.esperaSobreviver ? 'sobreviveu como previsto' : 'morto'}: ${m.nome}  (${m.pega})`,
    )
  } else {
    console.log(
      `FALHA  ${m.esperaSobreviver ? 'MORREU e devia sobreviver' : 'SOBREVIVEU'}: ${m.nome}  (${m.pega})`,
    )
  }
}

try { unlinkSync(TEMP) } catch {}
console.log(`\n${previstos}/${MUTANTES.length} com o resultado previsto` + (stale ? `  —  ${stale} ANCORA(S) PODRE(S)` : ''))
process.exitCode = previstos === MUTANTES.length ? 0 : 1
