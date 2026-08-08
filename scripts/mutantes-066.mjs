// Mutantes da 066 — a coordenação manda recado.
//
// Todo mutante aqui produz uma tela que FUNCIONA: clica, some o botão, aparece
// "enviado". A diferença chega no WhatsApp de outra pessoa, ou duas vezes, ou
// nunca — e sempre horas depois, longe de quem clicou.
//
// V4 e V6 são os que mais assustam: um marca 'enviada' uma mensagem que ainda
// não saiu, o outro deixa qualquer chamada perdida fechar o recado de outra.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/066-a-coordenacao-manda-recado.sql'
const TESTE = 'supabase/migrations/066-a-coordenacao-manda-recado.test.sql'
const TEMP = 'supabase/migrations/_mutante-066.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const VALORES = `     'processando', 1, v_token, now() + interval '5 minutes', p_solicitado_por)`

const MUTANTES = [
  {
    // A função é service_role: sem esta checagem, qualquer coisa que alcance a
    // chave de serviço dispara WhatsApp em nome do Fábio, assinado por um uuid
    // qualquer.
    nome: 'V1 — para de conferir se quem pediu e da coordenacao',
    pega: 'passo "autor fora da coordenacao e recusado"',
    de: `  if not exists (
    select 1
      from public.la_teacher_coordenacao c
      join public.usuarios u on u.id = c.usuario_id
     where u.auth_user_id = p_solicitado_por
       and coalesce(u.ativo, true)
  ) then
    raise exception 'apenas_admin';
  end if;`,
    para: `  -- checagem de autor removida pelo mutante`,
  },
  {
    // Clique acidental vira mensagem em branco no WhatsApp do professor.
    nome: 'V2 — aceita recado vazio',
    pega: 'passo "recado vazio e recusado"',
    de: `  if p_corpo is null or length(btrim(p_corpo)) < 3 then
    raise exception 'recado_vazio';
  end if;`,
    para: `  -- validacao de corpo removida pelo mutante`,
  },
  {
    // A dedupe diária deixa de proteger: o segundo clique reserva de novo e o
    // professor leva duas cobranças no mesmo dia, no mesmo canal do briefing.
    nome: 'V3 — o 2o pedido do dia volta a reservar',
    pega: 'passo "o 2o pedido do dia e recusado"',
    de: `  do nothing
  returning id into v_id;`,
    para: `  do update set corpo = excluded.corpo
  returning id into v_id;`,
  },
  {
    // O pior: a linha nasce dizendo que a mensagem foi enviada. Se o envio
    // falhar depois, ninguém nunca vai saber — o banco jura que saiu.
    nome: 'V4 — a reserva ja nasce como enviada (antes de enviar)',
    pega: 'passo "a linha nasce em processando"',
    de: VALORES,
    para: `     'enviada', 1, v_token, now() + interval '5 minutes', p_solicitado_por)`,
  },
  {
    // Exatamente o defeito do 360° do LA Report: 192 de 192 ocorrências sem
    // autor. A ação existe, o responsável não.
    nome: 'V5 — o recado perde o autor (o defeito do 360 do LA Report)',
    pega: 'passo "a linha guarda QUEM pediu"',
    de: VALORES,
    para: `     'processando', 1, v_token, now() + interval '5 minutes', null)`,
  },
  {
    // Sem o lease, qualquer chamada atrasada ou repetida fecha o recado de
    // outra pessoa como enviado, com um recibo que não é dele.
    nome: 'V6 — a conclusao ignora o lease (fecha recado alheio)',
    pega: 'passo "concluir com lease errado nao fecha nada"',
    de: `   where id = p_notificacao_id
     and lease_token = p_lease_token;`,
    para: `   where id = p_notificacao_id;`,
  },
  {
    // `create or replace` PRESERVA privilégios — o mutante tem que dar o grant
    // ATIVAMENTE, senão não mede nada. Com authenticated podendo chamar, o
    // navegador escolhe o valor de p_solicitado_por: o autor vira forjável.
    nome: 'V7 — a reserva fica aberta pro navegador (autor forjavel)',
    pega: 'passo "authenticated NAO reserva recado"',
    de: `revoke all on function public.fn_reservar_recado_coordenacao(int, text, uuid) from authenticated;`,
    para: `grant execute on function public.fn_reservar_recado_coordenacao(int, text, uuid) to authenticated;`,
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
