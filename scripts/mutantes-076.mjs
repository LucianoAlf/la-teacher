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
// V4 pega a conclusão sem checar o lease. `fabio_marcar_notificacao_enviada`
// não é definida por esta migration — é reusada de uma migration anterior
// (medido: `(p_notificacao_id uuid, p_lease_token uuid, p_recibo text)
// returns boolean`) — então o mutante precisa REDEFINI-LA dentro da própria
// transação descartável, com a MESMA assinatura, ignorando o token. O
// ROLLBACK do runner devolve a função real no final; nada some de produção.
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

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/076-o-carteiro-da-cobranca.sql'
const TESTE = 'supabase/migrations/076-o-carteiro-da-cobranca.test.sql'
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
  on public.fabio_notificacoes (tipo, dia_referencia)
  where tipo = 'feedback_coordenacao';`,
        para: `drop index if exists public.fabio_notificacoes_feedback_coord_dia_unico;
create unique index if not exists fabio_notificacoes_feedback_coord_dia_unico
  on public.fabio_notificacoes (professor_id, tipo, dia_referencia)
  where tipo = 'feedback_coordenacao';`,
      },
      {
        de: `on conflict (tipo, dia_referencia)`,
        para: `on conflict (professor_id, tipo, dia_referencia)`,
      },
    ],
  },
  {
    nome: 'V4 — conclusao fecha com qualquer lease token',
    pega: 'passo "concluir com token errado nao fecha"',
    de: `  'destinatario_tipo coordenacao, JID em destinatario_whatsapp. So service_role.';`,
    para: `  'destinatario_tipo coordenacao, JID em destinatario_whatsapp. So service_role.';

-- MUTANTE V4: ignora o lease_token, qualquer token "fecha" a notificacao.
-- Assinatura medida no banco em 09/08: (p_notificacao_id uuid, p_lease_token
-- uuid, p_recibo text) returns boolean — precisa bater pra SUBSTITUIR a
-- funcao real dentro da transacao descartavel, nao criar um overload.
create or replace function public.fabio_marcar_notificacao_enviada(uuid, uuid, text)
returns boolean language sql as $$ select true; $$;`,
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
  for (const parte of partes) mutado = mutado.replace(parte.de, parte.para)

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
