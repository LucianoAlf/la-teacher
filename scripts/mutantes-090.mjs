// Mutantes 090 — a máquina de ações falha fechada ou o teste está mentindo.
// Cada mutante roda o SQL inteiro em BEGIN/ROLLBACK contra o alvo compartilhado.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/090-fabio-whatsapp-acoes.sql'
const TESTE = 'supabase/migrations/090-fabio-whatsapp-acoes.test.sql'
const TEMP = 'supabase/migrations/_mutante-090.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'M1 — pool de registro perde a guarda de professor',
    de: 'where v.professor_id = p_professor_id',
    para: 'where true',
  },
  {
    nome: 'M2 — pool de registro perde o limite inferior da janela',
    de: "and v.data_hora_fim >= p_referencia - (public.fn_janela_registro_dias() || ' days')::interval",
    para: 'and true',
  },
  {
    nome: 'M3 — pool de registro mistura chamada_feita como filtro',
    de: 'and v.data_hora_fim <= p_referencia',
    para: "and v.data_hora_fim <= p_referencia\n        and v.chamada_feita = false",
  },
  {
    nome: 'M4 — aula fora da shortlist passa',
    de: 'if v_aula is null or not (v_aula = any(v_a.candidatas))\n       or not public.fabio_shortlist_valida(\n         p_professor_id, v_fluxo, array[v_aula], now()) then',
    para: 'if false then',
  },
  {
    nome: 'M5 — replay de evento deixa de consultar o ledger',
    de: 'select resultado into v_existente from public.fabio_acao_eventos where wa_message_id = p_wa_message_id;',
    para: 'select null::jsonb into v_existente;',
  },
  {
    nome: 'M6 — indice de acao ativa deixa de ser unico',
    de: 'create unique index fabio_acoes_pendentes_ativa_professor_uq',
    para: 'create index fabio_acoes_pendentes_ativa_professor_uq',
  },
  {
    nome: 'M7 — RLS da tabela de eventos desaparece',
    de: 'alter table public.fabio_acao_eventos enable row level security;',
    para: '-- alter table public.fabio_acao_eventos enable row level security;',
  },
  {
    nome: 'M8 — inicio volta a confiar no payload da shortlist',
    de: "v_candidatas := '{}'::integer[];",
    para: 'v_candidatas := ARRAY[2147483647]::integer[];',
  },
  {
    nome: 'M9 — shortlist_definida desaparece da transicao',
    de: "elsif p_evento = 'shortlist_definida' and v_a.tipo in ('escolher_aula_audio','escolher_aula_chamada') then",
    para: "elsif false and p_evento = 'shortlist_definida' and v_a.tipo in ('escolher_aula_audio','escolher_aula_chamada') then",
  },
  {
    nome: 'M10 — aula escolhida pula revalidacao do pool atual',
    de: "or not public.fabio_shortlist_valida(\n         p_professor_id, v_fluxo, array[v_aula], now()) then",
    para: 'or false then',
  },
]

let mortos = 0
let stale = 0

for (const m of MUTANTES) {
  const ocorrencias = fonte.split(m.de).length - 1
  if (ocorrencias !== 1) {
    console.log(`STALE  ${m.nome} — ancora aparece ${ocorrencias} vez(es)`)
    stale++
    continue
  }
  writeFileSync(TEMP, fonte.replace(m.de, m.para))
  let falhou = false
  try {
    execFileSync('node', ['scripts/rodar-teste-sql.mjs', TEMP, TESTE], { stdio: 'pipe' })
  } catch {
    falhou = true
  }
  if (falhou) {
    mortos++
    console.log(`OK     morto: ${m.nome}`)
  } else {
    console.log(`FALHA  SOBREVIVEU: ${m.nome}`)
  }
}

try { unlinkSync(TEMP) } catch {}
console.log(`\n${mortos}/${MUTANTES.length} mutantes mortos` + (stale ? ` — ${stale} ancora(s) podre(s)` : ''))
process.exitCode = mortos === MUTANTES.length ? 0 : 1
