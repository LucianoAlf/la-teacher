// Teste do que o professor recebe de saúde, na notificar-anamnese.
//
// O contrato mudou em 05/08/2026, no meio do dia. A primeira versão deste
// arquivo testava o oposto: garantia que o rótulo do diagnóstico NUNCA saísse.
// O Alf reverteu, e com razão — se a família relatou, ela espera que o professor
// saiba, e "Anafilaxia a formiga" é segurança física, não etiqueta.
//
// O que se mede agora:
//   1. o que a família informou de saúde CHEGA ao professor
//   2. campo vazio ou "não" NÃO vira linha — era o ruído que fazia a informação
//      de verdade se perder no meio de três "nao"
//   3. filiação e situação conjugal continuam fora do que vai para a IA
//
// Roda sem rede e sem banco:
//   node supabase/functions/notificar-anamnese/fronteira.test.mjs

import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const aqui = dirname(fileURLToPath(import.meta.url))
const fonte = readFileSync(join(aqui, 'index.ts'), 'utf8')

// Extrai as funções puras do próprio arquivo publicado. Copiá-las para cá seria
// testar uma cópia — e cópia que diverge da original é como a garantia deixa de
// valer sem ninguém decidir isso.
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
${extrair('sinaisDeSaude')}
export { ehVazioOuNegativo, sinaisDeSaude };`

const mod = await import('data:text/javascript,' + encodeURIComponent(sandbox))
const { sinaisDeSaude, ehVazioOuNegativo } = mod

const casos = []
const checar = (nome, obtido, esperado) => casos.push({ nome, obtido, esperado })
const rotulos = (itens) => itens.map(i => i.rotulo).join('|')
const texto = (itens) => itens.map(i => `${i.rotulo}: ${i.valor}`).join(' / ')

// ── O que a família relatou CHEGA ────────────────────────────────────────────
const comTudo = sinaisDeSaude({
  diagnosticos: ['TEA nível 1'],
  cuidado_medico: 'Cardiopata',
  medicacao_continua: 'Ritalina 10mg',
  necessidade_apoio: 'Precisa de aviso antes de trocar de atividade',
})
checar('os quatro campos chegam',
  rotulos(comTudo), 'Diagnóstico|Cuidado médico|Medicação contínua|Apoio necessário')
checar('o nome do diagnóstico chega inteiro',
  texto(comTudo).includes('TEA nível 1'), true)
checar('a condição médica chega (é segurança física)',
  texto(comTudo).includes('Cardiopata'), true)

// Vários diagnósticos viram uma linha só, não quatro.
checar('diagnósticos múltiplos numa linha',
  texto(sinaisDeSaude({ diagnosticos: ['TDAH', 'Dislexia'] })), 'Diagnóstico: TDAH, Dislexia')

// ── O ruído NÃO chega ────────────────────────────────────────────────────────
// Estes valores são reais: saíram do banco em 05/08/2026.
checar('aluno sem nada registrado não gera bloco',
  sinaisDeSaude({ diagnosticos: ['NÃO'], cuidado_medico: 'nao',
                  medicacao_continua: 'não ', necessidade_apoio: 'n' }).length, 0)
checar('"teste" não vira linha',
  sinaisDeSaude({ cuidado_medico: 'teste' }).length, 0)
checar('campo nulo/ausente não vira linha',
  sinaisDeSaude({ diagnosticos: null, cuidado_medico: null }).length, 0)
// O caso misto é o que importa: um campo real no meio de negativas não pode
// ser perdido, e as negativas não podem aparecer junto.
const misto = sinaisDeSaude({
  diagnosticos: ['NÃO'], cuidado_medico: 'Anafilaxia a formiga',
  medicacao_continua: 'nao', necessidade_apoio: '',
})
checar('só o campo real sobrevive no meio das negativas',
  texto(misto), 'Cuidado médico: Anafilaxia a formiga')

// ── Reconhecimento de negativas (o que separa ruído de conteúdo) ────────────
checar('negativas reconhecidas', [
  ehVazioOuNegativo('n'), ehVazioOuNegativo('Não '), ehVazioOuNegativo('teste'),
  ehVazioOuNegativo(''), ehVazioOuNegativo('NAO'), ehVazioOuNegativo('nenhum'),
].every(Boolean), true)
checar('texto real NÃO é negativa', [
  ehVazioOuNegativo('Sim, pela dificuldade da idade e a novidade!'),
  ehVazioOuNegativo('Cardiopata'),
  ehVazioOuNegativo('TEA'),
].some(Boolean), false)

// ── O que continua fora do que a IA recebe ──────────────────────────────────
// Não é varredura de saída: `sanitizeForAI` simplesmente não passa esses
// campos. A IA não cita o que nunca recebeu.
const sanitize = extrair('sanitizeForAI')
checar('sanitizeForAI descarta filiacao', /filiacao:\s*_f/.test(sanitize), true)
checar('sanitizeForAI descarta situacao_responsaveis', /situacao_responsaveis:\s*_s/.test(sanitize), true)

const falhas = casos.filter(c => JSON.stringify(c.obtido) !== JSON.stringify(c.esperado))
for (const f of falhas) console.error(`  ✗ ${f.nome}: esperado ${JSON.stringify(f.esperado)}, obtido ${JSON.stringify(f.obtido)}`)
console.log(falhas.length === 0
  ? `✓ saúde na anamnese — ${casos.length} casos, nenhuma divergência`
  : `✗ saúde na anamnese — ${falhas.length} de ${casos.length} falharam`)
process.exitCode = falhas.length === 0 ? 0 : 1
