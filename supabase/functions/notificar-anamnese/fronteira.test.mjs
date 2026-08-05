// Teste da varredura de privacidade da notificar-anamnese.
//
// Existe porque as outras provas desta função são todas sobre a SAÍDA de uma
// IA, e IA que se comporta hoje não é garantia de nada. O que precisa ser
// falsificável é o guarda: dado um texto que vaza, ele acusa?
//
// Roda sem rede e sem banco:  node supabase/functions/notificar-anamnese/fronteira.test.mjs

import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const aqui = dirname(fileURLToPath(import.meta.url))
const fonte = readFileSync(join(aqui, 'index.ts'), 'utf8')

// Extrai as funções puras do próprio arquivo publicado. Copiá-las para cá seria
// testar uma cópia — e cópia que diverge da original é como a fronteira se abre
// sem ninguém decidir isso.
function extrair(nome) {
  const i = fonte.indexOf(`function ${nome}(`)
  if (i < 0) throw new Error(`não achei function ${nome} em index.ts`)
  let profundidade = 0, comecou = false, j = i
  for (; j < fonte.length; j++) {
    if (fonte[j] === '{') { profundidade++; comecou = true }
    else if (fonte[j] === '}') { profundidade--; if (comecou && profundidade === 0) { j++; break } }
  }
  return fonte.slice(i, j)
}

const NEGATIVAS_SRC = fonte.match(/const NEGATIVAS = new Set\(\[[^\]]*\]\);/s)[0]
const sandbox = `${NEGATIVAS_SRC}
${extrair('ehVazioOuNegativo')}
${extrair('termosProibidos')}
${extrair('briefingVazou')}
export { ehVazioOuNegativo, termosProibidos, briefingVazou };`

const mod = await import('data:text/javascript,' + encodeURIComponent(sandbox))
const { termosProibidos, briefingVazou, ehVazioOuNegativo } = mod

const casos = []
const checar = (nome, obtido, esperado) => casos.push({ nome, obtido, esperado })

// Uma anamnese como as que existem em produção.
const anamnese = {
  diagnosticos: ['TEA nível 1'],
  cuidado_medico: 'Tratamento psiquiátrico de depressão e ansiedade',
  medicacao_continua: 'não',
}
const termos = termosProibidos(anamnese)

// ── O guarda tem que ACUSAR ────────────────────────────────────────────────
checar('rótulo literal',
  Boolean(briefingVazou('A aluna tem TEA nível 1 e precisa de rotina.', termos)), true)
checar('rótulo em caixa diferente',
  Boolean(briefingVazou('a aluna tem tea NÍVEL 1.', termos)), true)
checar('condição médica literal',
  Boolean(briefingVazou('Faz Tratamento psiquiátrico de depressão e ansiedade.', termos)), true)
// O caso que motivou a varredura por palavra: a IA reescreve a frase em volta,
// mas mantém a palavra clínica. Frase inteira não bate; "psiquiátrico" bate.
checar('palavra clínica solta na frase reescrita',
  Boolean(briefingVazou('Ela faz acompanhamento psiquiátrico há um ano.', termos)), true)
checar('outra palavra clínica solta',
  Boolean(briefingVazou('Convive com quadro de depressão.', termos)), true)

// ── E tem que DEIXAR PASSAR o que é o produto ─────────────────────────────
checar('tradução funcional passa',
  briefingVazou('Responde melhor a rotina previsível: avise antes de mudar de atividade.', termos), null)
checar('briefing pedagógico comum passa',
  briefingVazou('Divida a aula em blocos curtos e dinâmicos para manter o engajamento.', termos), null)
// "não" tem 3 letras e é negativa: não pode virar termo proibido, senão
// qualquer briefing com a palavra "não" seria bloqueado — o guarda travaria
// tudo e alguém acabaria desligando ele.
checar('medicacao "não" não vira termo', termos.includes('não'), false)
checar('negativas reconhecidas', [
  ehVazioOuNegativo('n'), ehVazioOuNegativo('Não '), ehVazioOuNegativo('teste'),
  ehVazioOuNegativo(''), ehVazioOuNegativo('NAO'),
].every(Boolean), true)
checar('texto real NÃO é negativa',
  ehVazioOuNegativo('Sim, pela dificuldade da idade e a novidade!'), false)

// ── Aluno sem nada registrado: o guarda não pode inventar bloqueio ────────
const limpo = termosProibidos({ diagnosticos: ['NÃO'], cuidado_medico: 'nao', medicacao_continua: null })
checar('sem dado de saúde, nenhum termo', limpo.length, 0)
checar('sem termos, nada bloqueia',
  briefingVazou('Qualquer briefing normal aqui.', limpo), null)

const falhas = casos.filter(c => JSON.stringify(c.obtido) !== JSON.stringify(c.esperado))
for (const f of falhas) console.error(`  ✗ ${f.nome}: esperado ${JSON.stringify(f.esperado)}, obtido ${JSON.stringify(f.obtido)}`)
console.log(falhas.length === 0
  ? `✓ fronteira da anamnese — ${casos.length} casos, nenhuma divergência`
  : `✗ fronteira da anamnese — ${falhas.length} de ${casos.length} falharam`)
process.exitCode = falhas.length === 0 ? 0 : 1
