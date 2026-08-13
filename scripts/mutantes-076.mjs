// Mutantes da 076 — o carteiro da cobrança (e a coordenação recebe).
//
// V1 pega a mesma âncora que motivou o desenho da 075: dia da semana inverte
// lembrete/reforço em todo mês que não termina em domingo.
//
// V2 pega a coordenação sendo gravada com destinatario_tipo='professor' — com
// professor_id nulo isso nem passa no CHECK (chk_notificacao_destinatario não
// tem ramo pra 'professor' com professor_id nulo), então morre com exceção na
// própria reserva da coordenação — ainda assim é o defeito descrito: a
// coordenação deixa de ser reconhecida como o quarto ramo do destinatário.
//
// V3 pega o dedupe da coordenação reusando a chave (professor_id, tipo,
// dia_referencia) do professor: como professor_id é sempre NULO pra
// coordenação, nulos não colidem em índice único, e o ON CONFLICT nunca
// dispara — duas notificações no mesmo dia pro grupo. Precisa mudar DUAS
// coisas JUNTAS (o ON CONFLICT e o índice) pra reproduzir o defeito de
// verdade em vez de só quebrar a inferência do Postgres — se só o ON CONFLICT
// mudasse, um índice com WHERE incompatível levantaria 42P10 na primeira
// chamada, não na segunda, e o teste morreria pelo motivo errado. Por isso
// este é o único mutante com duas `partes`. E o índice PRECISA de um `drop
// index if exists` explícito antes do `create ... if not exists`: `create
// index if not exists` casa por NOME — sem o drop, assim que o índice real
// (076 já aplicada) existir em produção, o `create` vira no-op e o mutante
// para de mudar qualquer coisa de verdade (mesma armadilha do V5 da 075,
// medida depois daquele deploy).
//
// V4 pega a conclusão sem checar o lease. Duas âncoras podres foram achadas
// na revisão de 09/08 e as DUAS precisavam de correção independente:
//   (a) `mutado.replace(de, para)` com `para` STRING interpreta `$$` na
//       string de SUBSTITUIÇÃO como o escape de "$" — vira `$` sozinho, que
//       não é delimitador de dollar-quote válido, e o mutante morria de erro
//       de sintaxe, não da asserção. `node -e "console.log('A'.replace('A','x
//       \$\$ y'))"` imprime `x $ y` — reproduzido e confirmado antes de
//       corrigir. Fix: replacer em FUNÇÃO (`() => parte.para`), que devolve o
//       texto literal sem nenhuma interpretação de `$`.
//   (b) mesmo com o `$$` corrigido, `fabio_marcar_notificacao_enviada` real
//       (018) tem PARÂMETROS NOMEADOS (`p_notificacao_id`, `p_lease_token`,
//       `p_recibo`). `create or replace function` recusa mudar o NOME de um
//       parâmetro existente (`cannot change name of input parameter`) — a
//       versão anterior deste mutante declarava `(uuid, uuid, text)` sem
//       nome nenhum, e o CREATE OR REPLACE quebrava antes de qualquer teste
//       rodar. Fix: nomes e assinatura idênticos aos medidos em 018, e tag
//       `$mut$` em vez de `$$` (defesa extra, redundante com o fix do
//       replacer, mas o revisor pediu as duas).
// As DUAS causas eram fatais sozinhas — cada uma, isolada, já derrubava o
// CREATE OR REPLACE antes de qualquer assert rodar, e `rodar-teste-sql.mjs`
// sai com código≠0 tanto pra "SQL quebrou" quanto pra "falhas>0": o mutante
// morria, mas nunca pela asserção "concluir com token errado nao fecha" —
// morria mudo. Corrigido, ele tem que morrer FALANDO.
//
// V5 pega reforço/coordenação cobrando quem já fechou o mês — o defeito que
// ensina o professor a ignorar o Fábio (mesma lição da 075, agora na
// leitura).
//
// V6 pega `elegiveis` contando só quem falta em vez de toda a carteira — é o
// defeito que faria a coordenação ler "0 de 12 fecharam" num mês em que todo
// mundo fechou.
//
// V7 é a mesma armadilha de permissão das tasks anteriores (073/074/075):
// `create or replace function` PRESERVA privilégio — só um `grant` a mais
// prova que os `revoke` desta migration fecham a porta de verdade.
//
// V8 (decisão do dono do plano, 09/08): a RESERVA ganhou volta — `do nothing`
// virou `do update` que reclama linha 'falhou' ou 'processando' com lease
// VENCIDO. Tirar a checagem `lease_expira_em < now()` reabre o defeito de
// envio duplicado: um lease AINDA VIVO vira reclamável, ou seja, dois workers
// podem mandar a MESMA cobrança. Não precisou de um teste novo pra pegar —
// "dedupe do professor no mesmo dia" já reserva, tenta reservar nas costas
// (lease fresquinho, bem vivo) e exige `ja_cobrado_hoje`; com a checagem de
// lease fora, essa segunda chamada reclama e devolve `reservado:true`, e o
// teste já existente morre por conta própria.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/076-o-carteiro-da-cobranca.sql'
const TESTE = 'supabase/migrations/076-o-carteiro-da-cobranca.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-076.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'V1 — a regua volta a ser dia da semana',
    pega: 'passo "regua NN: lembrete antes do reforco" (varredura dos 12 meses)',
    de: `  elsif v_dia = v_ultimo - 6 then
    v_fase := 'lembrete';
    v_comp := public.fn_competencia_feedback(v_dia);
  elsif v_dia = v_ultimo - 3 then
    v_fase := 'reforco';
    v_comp := public.fn_competencia_feedback(v_dia);`,
    para: `  elsif extract(dow from v_dia) = 1 then
    v_fase := 'lembrete';
    v_comp := public.fn_competencia_feedback(v_dia);
  elsif extract(dow from v_dia) = 4 then
    v_fase := 'reforco';
    v_comp := public.fn_competencia_feedback(v_dia);`,
  },
  {
    nome: 'V2 — a coordenacao e gravada como professor',
    pega: 'passo "coordenacao grava no grupo, sem professor"',
    de: `btrim(p_corpo), 'coordenacao',`,
    para: `btrim(p_corpo), 'professor',`,
  },
  {
    nome: 'V3 — dedupe da coordenacao reusa a chave do professor',
    pega: 'passo "dedupe da coordenacao no mesmo dia"',
    partes: [
      {
        de: `create unique index if not exists fabio_notificacoes_feedback_coord_dia_unico
  on public.fabio_notificacoes (tipo, dia_referencia, destinatario_whatsapp)
  where tipo = 'feedback_coordenacao';`,
        para: `drop index if exists public.fabio_notificacoes_feedback_coord_dia_unico;
create unique index if not exists fabio_notificacoes_feedback_coord_dia_unico
  on public.fabio_notificacoes (professor_id, tipo, dia_referencia)
  where tipo = 'feedback_coordenacao';`,
      },
      {
        de: `on conflict (tipo, dia_referencia, destinatario_whatsapp)`,
        para: `on conflict (professor_id, tipo, dia_referencia)`,
      },
    ],
  },
  {
    nome: 'V4 — conclusao fecha com qualquer lease token',
    pega: 'passo "concluir com token errado nao fecha"',
    de: `  'volta da reserva do professor. So service_role.';`,
    para: `  'volta da reserva do professor. So service_role.';

-- MUTANTE V4: ignora o lease_token, fecha qualquer 'processando' so pelo id.
-- Nomes de parametro tem que bater com a funcao real (018) — CREATE OR
-- REPLACE recusa "cannot change name of input parameter" se os nomes
-- mudarem (medido, achado da revisao de 09/08). Tag $mut$, nao $$: reforca o
-- fix do replacer em funcao la embaixo (mutado.replace(de, () => para)) —
-- $$ dentro de uma STRING de substituicao do String.replace e um padrao
-- especial ($$ vira $ literal) e corrompia o dollar-quote antes dos dois
-- fixes.
create or replace function public.fabio_marcar_notificacao_enviada(
  p_notificacao_id uuid, p_lease_token uuid default null, p_recibo text default null)
returns boolean language plpgsql security definer set search_path to 'public'
as $mut$
declare v_n integer;
begin
  update public.fabio_notificacoes set status='enviada', enviada_em=now()
   where id = p_notificacao_id and status='processando';
  get diagnostics v_n = row_count; return v_n > 0;
end $mut$;`,
  },
  {
    nome: 'V5 — reforco e coordenacao voltam a cobrar quem JA fechou',
    pega: 'passo "quem fechou sai da lista da coordenacao"',
    de: `filter (where v_fase = 'lembrete' or ok < total),`,
    para: `filter (where true),`,
  },
  {
    nome: 'V6 — elegiveis conta so quem falta',
    pega: 'passo "mas continua contando em elegiveis"',
    de: `select count(*)::int,`,
    para: `select count(*) filter (where v_fase = 'lembrete' or ok < total)::int,`,
  },
  {
    nome: 'V7 — a reserva do professor fica aberta pro anon',
    pega: 'passo "anon nao executa as tres"',
    de: `revoke all on function public.fn_reservar_cobranca_feedback_coordenacao(text, text, date)
  from public, anon, authenticated;`,
    para: `revoke all on function public.fn_reservar_cobranca_feedback_coordenacao(text, text, date)
  from public, anon, authenticated;

grant execute on function public.fn_reservar_cobranca_feedback(int,text,text,date) to anon;`,
  },
  {
    nome: 'V8 — lease AINDA VIVO vira reclamavel (envio duplicado)',
    pega: 'passo "dedupe do professor no mesmo dia (lease vivo nao reclama)"',
    // Só na reserva do PROFESSOR: o comentário "reclamo (professor)" é a
    // âncora que separa este bloco do gêmeo idêntico na reserva da
    // coordenação ("reclamo (coordenacao)") — sem essa distinção as duas
    // ficariam com o MESMO texto e a checagem de unicidade acusaria 2.
    de: `  -- reclamo (professor): dono anterior falhou, ou lease vencido de verdade.
  do update set
    status          = 'processando',
    tentativas      = fabio_notificacoes.tentativas + 1,
    corpo           = excluded.corpo,
    lease_token     = excluded.lease_token,
    lease_expira_em = excluded.lease_expira_em,
    last_error      = null
  where
    fabio_notificacoes.status = 'falhou'
    or (fabio_notificacoes.status = 'processando'
        and fabio_notificacoes.lease_expira_em < now())
  returning id into v_id;`,
    para: `  -- reclamo (professor): dono anterior falhou, ou lease vencido de verdade.
  do update set
    status          = 'processando',
    tentativas      = fabio_notificacoes.tentativas + 1,
    corpo           = excluded.corpo,
    lease_token     = excluded.lease_token,
    lease_expira_em = excluded.lease_expira_em,
    last_error      = null
  where
    fabio_notificacoes.status = 'falhou'
    or (fabio_notificacoes.status = 'processando')
  returning id into v_id;`,
  },
]

let mortos = 0
let stale = 0

for (const m of MUTANTES) {
  // A maioria dos mutantes muda UM ponto do arquivo (`de`/`para`). O V3 é o
  // único que precisa mudar DOIS pontos juntos (índice + on conflict) pra
  // reproduzir o defeito real em vez de só quebrar a inferência do Postgres
  // — daí `partes`, uma lista de edições aplicadas em sequência. Cada âncora
  // ainda é checada isoladamente contra o arquivo ORIGINAL: se qualquer uma
  // não aparecer exatamente 1 vez, o mutante inteiro é PODRE e a rodada
  // acusa alto, igual ao mutantes-075.mjs.
  const partes = m.partes ?? [{ de: m.de, para: m.para }]

  let algumaPodre = false
  for (const parte of partes) {
    const n = fonte.split(parte.de).length - 1
    if (n !== 1) {
      console.log(`STALE  ${m.nome} — ancora aparece ${n} vez(es), esperava 1`)
      console.log(`       ${parte.de.split('\n')[0]}...`)
      algumaPodre = true
    }
  }
  if (algumaPodre) {
    stale++
    continue
  }

  let mutado = fonte
  // Replacer em FUNÇÃO, não string: `String.prototype.replace` trata `$$`
  // (e `$&`, `$1`, etc.) na string de SUBSTITUIÇÃO como padrão especial,
  // mesmo quando o padrão de busca é uma string literal — `$$` vira `$`
  // sozinho. O V4 carrega corpo de função com `$mut$ ... $mut$`, mas
  // qualquer mutante futuro que carregue um dollar-quote (`$$` incluso) cairia
  // na mesma armadilha. Uma função de substituição devolve o texto literal,
  // sem essa interpretação. (achado da revisão, 09/08 — reproduzido com
  // `node -e "console.log('A'.replace('A','x $$ y'))"` → `x $ y`.)
  for (const parte of partes) mutado = mutado.replace(parte.de, () => parte.para)

  writeFileSync(TEMP, mutado)
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
process.exitCode = mortos === MUTANTES.length && stale === 0 ? 0 : 1
