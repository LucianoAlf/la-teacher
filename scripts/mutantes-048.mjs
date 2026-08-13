// Mutantes da 048 — a correção depois da entrega.
//
// Esta migration abre uma exceção na regra "enviada não é retomada", que é a
// regra que impede o comercial de receber a mesma devolutiva duas vezes. Então
// metade dos mutantes ataca o conserto, e a outra metade ataca a EXCEÇÃO — se
// ela alargar, o defeito que ela conserta vira o defeito oposto.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/048-correcao-se-anuncia.sql'
const TESTE = 'supabase/migrations/048-correcao-se-anuncia.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-048.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    // O estado anterior: corrigir não produz mensagem nenhuma, em silêncio.
    // O professor arruma e a Daiana fica com a versão velha.
    nome: 'V1 — a correção volta a não gerar mensagem (o silêncio de antes)',
    pega: 'passo "a SEGUNDA se anuncia como correcao"',
    de: "    or (fabio_notificacoes.status = 'enviada' and v_e_correcao)",
    para: '',
  },
  {
    // A exceção alarga: qualquer reconfirmação reabre a linha entregue e o
    // comercial recebe a devolutiva de novo a cada toque no botão.
    nome: 'V2 — a exceção vira porta (reconfirmar reenvia sempre)',
    pega: 'passo "reconfirmar sem editar nao reabre a mensagem"',
    de: "    or (fabio_notificacoes.status = 'enviada' and v_e_correcao)",
    para: "    or (fabio_notificacoes.status = 'enviada')",
  },
  {
    // A correção chega idêntica à primeira: o comercial recebe duas
    // devolutivas da mesma aula e não sabe qual vale.
    nome: 'V3 — a correção não se anuncia (chega igual à primeira)',
    pega: 'passo "a SEGUNDA se anuncia como correcao"',
    de: `  v_corpo := case when v_e_correcao
    then E'✏️ *Correção — a devolutiva desta experimental mudou*\\n_a versão anterior não vale mais_\\n\\n'
    else E'🎓 *Experimental registrada*\\n\\n' end || v_corpo_base;`,
    para: "  v_corpo := E'🎓 *Experimental registrada*\\n\\n' || v_corpo_base;",
  },
  {
    // O oposto: TODA mensagem vira correção, inclusive a primeira. O comercial
    // procura uma versão anterior que nunca existiu.
    nome: 'V4 — até a primeira devolutiva se diz correção',
    pega: 'passo "a PRIMEIRA devolutiva nao se chama correcao"',
    de: '  v_e_correcao := v_ja.status = \'enviada\'\n              and right(v_ja.corpo, length(v_corpo_base)) is distinct from v_corpo_base;',
    para: '  v_e_correcao := true;',
  },
  {
    // Detectar por REGISTRO em vez de ENTREGA: quem escreveu, reescreveu e só
    // então confirmou receberia a PRIMEIRA devolutiva marcada como correção de
    // algo que ninguém recebeu.
    nome: 'V5 — a detecção olha registro em vez de entrega',
    pega: 'passo "reescrever ANTES de enviar nao vira correcao"',
    de: "  v_e_correcao := v_ja.status = 'enviada'\n              and right(v_ja.corpo, length(v_corpo_base)) is distinct from v_corpo_base;",
    para: '  v_e_correcao := v_ja.corpo is not null;',
  },
  {
    // A confirmação volta a sair pela porta dos fundos: nunca chega no claim,
    // e a correção morre antes de começar.
    nome: 'V6 — a confirmação volta ao retorno antecipado',
    pega: 'passo "a SEGUNDA se anuncia como correcao"',
    de: '    select public.fabio_claim_aviso_comercial(p_registro_id, 0) into v_aviso;\n    return jsonb_build_object(\n      \'registro_id\',   p_registro_id,\n      \'ja_confirmado\', true,',
    para: '    return jsonb_build_object(\n      \'registro_id\',   p_registro_id,\n      \'ja_confirmado\', true,',
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
