// Mutantes da 061 — a experimental remarcada volta a ter ficha.
//
// A 061 corrige três defeitos que viviam escondidos atrás do mesmo
// `exception when others then v_erros := v_erros + 1` do laço. Por isso o
// mutante mais importante aqui não é o que quebra o caso feliz — é o V5, que
// devolve o `v_vinculo := null`. Com ele, o caso A FALHA CALADO: a
// subtransação do laço é desfeita, o vínculo reaparece cancelado, e a rodada
// devolve "erros: N" que ninguém lê. É exatamente como o defeito viveu.
//
// V2, V3 e V4 são o outro lado: impedem que a correção vire "descancela tudo".

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/061-a-experimental-remarcada-ressuscita.sql'
const TESTE = 'supabase/migrations/061-a-experimental-remarcada-ressuscita.test.sql'
const TEMP = 'supabase/migrations/_mutante-061.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'V1 — o ramo da ressurreicao some (o estado de antes da 061)',
    pega: 'passo A "cancelado + lead agendado volta a ter ficha"',
    de: `      if v_vinculo.id is not null
         and v_vinculo.estado = 'cancelado'
         and v_lead.status = 'experimental_agendada'`,
    para: `      if false
         and v_vinculo.estado = 'cancelado'
         and v_lead.status = 'experimental_agendada'`,
  },
  {
    // "Já que estou ressuscitando, ressuscito tudo" — apaga o registro de que
    // a aula aconteceu.
    nome: 'V2 — a ressurreicao passa a valer pra realizado tambem',
    pega: 'passo B "realizado continua realizado"',
    de: `         and v_vinculo.estado = 'cancelado'`,
    para: `         and v_vinculo.estado in ('cancelado', 'realizado')`,
  },
  {
    // Ressuscita vínculo de lead que continua cancelado: a família desistiu e
    // o professor ganha uma ficha de aula que não vai acontecer.
    nome: 'V3 — a ressurreicao ignora o status do lead',
    pega: 'passo D "lead ainda cancelado nao ressuscita"',
    de: `         and v_lead.status = 'experimental_agendada'`,
    para: `         and v_lead.status is not null`,
  },
  {
    // Atropela quem estava na sala — a regra que o ramo 1 protege desde a 034.
    nome: 'V4 — a ressurreicao atropela presenca forte',
    pega: 'passo E "presenca forte barra a ressurreicao"',
    de: `         and not public.fn_presenca_e_forte(v_vinculo.presenca_respondido_por) then`,
    para: `         and true then`,
  },
  {
    // O DEFEITO 2 DE VOLTA. Não quebra nada visivelmente: só faz a rodada
    // contar erros que ninguém lê, e o vínculo reaparece cancelado.
    nome: 'V5 — volta o `v_vinculo := null` (o record fica nao atribuido)',
    pega: 'passos "a rodada nao teve erro" e A',
    de: `        select * into v_vinculo
          from lead_experimental_aulas
         where lead_experimental_id = v_lead.id and substituido_em is null;
        v_revinculados := v_revinculados + 1;`,
    para: `        v_vinculo := null;
        v_revinculados := v_revinculados + 1;`,
  },
  {
    // O DEFEITO 3 DE VOLTA: aula ocupada volta a virar "+1 erro" invisível em
    // vez de ambiguidade com nome.
    nome: 'V6 — o update de pendente perde o handler de aula ocupada',
    pega: 'passos F e "a rodada nao teve erro"',
    de: `              exception when unique_violation then
                if v_vinculo.motivo_pendencia is distinct from 'ambiguo' then`,
    para: `              exception when division_by_zero then
                if v_vinculo.motivo_pendencia is distinct from 'ambiguo' then`,
  },
  {
    // Ressuscita sem tirar o cancelado de vigência: o índice por lead barra a
    // linha nova e o lead fica exatamente como estava.
    nome: 'V7 — ressuscita sem tirar o cancelado de vigencia',
    pega: 'passo A "o cancelado vira historico, nao lixo"',
    de: `        update lead_experimental_aulas set substituido_em = now() where id = v_vinculo.id;
        -- 061: recarrega em vez de`,
    para: `        -- 061: recarrega em vez de`,
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
