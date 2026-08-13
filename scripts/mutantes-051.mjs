// Mutantes da 051 — a porta do worker do áudio.
//
// S1 é o mais importante e o menos óbvio: se o claim parar de filtrar por
// `vinculo_id is not null`, este worker come as linhas do Hermes. O registro de
// aula do dia a dia não dá erro — ele simplesmente para de acontecer, com a
// linha marcada 'transcrevendo' por um worker que não sabe o que fazer com
// ela. Defeito silencioso numa fila que já funcionava.
//
// S6 é o inverso do zelo: gravar sem preservar. Verde num teste que só olha o
// campo que o áudio cobriu; três campos digitados a menos na vida real.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/051-a-porta-do-worker-do-audio.sql'
const TESTE = 'supabase/migrations/051-a-porta-do-worker-do-audio.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-051.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'S1 — o claim passa a comer a fila do Hermes',
    pega: 'passos "o claim NAO pega audio de aula comum" e "a aula comum continua pendente"',
    de: `    select f.id
      from public.fabio_fila_audios f
     where f.vinculo_id is not null
       and (`,
    para: `    select f.id
      from public.fabio_fila_audios f
     where (`,
  },
  {
    // Sem retomada, um worker que morre no meio prende a linha pra sempre e o
    // professor nunca vê os campos preenchidos.
    nome: 'S2 — a fila perde a retomada (preso é preso pra sempre)',
    pega: 'passo "e retoma o que ficou preso 20min"',
    de: `         or (f.status = 'transcrevendo' and f.atualizado_em < now() - interval '15 minutes')`,
    para: '',
  },
  {
    // O oposto: retomada sem prazo. Dois workers na mesma linha, dois registros
    // do mesmo áudio, e o professor vendo o texto mudar sozinho.
    nome: 'S3 — a retomada rouba linha que ainda está sendo trabalhada',
    pega: 'passo "mas NAO rouba o que esta preso ha 2min"',
    de: `         or (f.status = 'transcrevendo' and f.atualizado_em < now() - interval '15 minutes')`,
    para: `         or (f.status = 'transcrevendo' and f.atualizado_em < now() + interval '15 minutes')`,
  },
  {
    nome: 'S4 — a tentativa não é contada (retenta pra sempre)',
    pega: 'passo "e a tentativa e contada"',
    de: `       set status     = 'transcrevendo',
           tentativas = f.tentativas + 1`,
    para: `       set status     = 'transcrevendo'`,
  },
  {
    // O briefing viajando junto: o modelo preenche buraco com ele e o registro
    // deixa de ser o que o professor falou.
    nome: 'S5 — o claim manda o contexto pedagógico junto',
    pega: 'passo "o claim nao leva o briefing pedagogico"',
    de: `           'nome_aluno',        le.nome_aluno,`,
    para: `           'nome_aluno',        le.nome_aluno,
           'contexto',          le.contexto_ia,`,
  },
  {
    nome: 'S6 — gravar apaga o que o professor tinha escrito',
    pega: 'passo "e os TRES que ele nao cobriu sobrevivem"',
    de: `           coalesce(nullif(btrim(coalesce(p_campos ->> 'devolutiva_familia',   '')), ''), v_ja.devolutiva_familia),
           coalesce(nullif(btrim(coalesce(p_campos ->> 'proximos_passos',      '')), ''), v_ja.proximos_passos),
           coalesce(nullif(btrim(coalesce(p_campos ->> 'leitura_de_conversao', '')), ''), v_ja.leitura_de_conversao),`,
    para: `           p_campos ->> 'devolutiva_familia',
           p_campos ->> 'proximos_passos',
           p_campos ->> 'leitura_de_conversao',`,
  },
  {
    // `normalizado` sem transcrição é o bug de auditoria que o AGENTS.md
    // nomeia: sem a evidência não dá pra saber se traduziu ou inventou.
    nome: 'S7 — normaliza sem guardar a evidência',
    pega: 'passo "gravar recusa normalizar sem evidencia"',
    de: `  if v_texto is null then
    raise exception 'transcricao_obrigatoria';
  end if;`,
    para: '',
  },
  {
    nome: 'S8 — gravar aceita áudio de aula comum',
    pega: 'passo "gravar recusa audio que nao e de experimental"',
    de: `  if v_audio.vinculo_id is null then
    raise exception 'audio_nao_e_de_experimental: %', p_audio_id;
  end if;`,
    para: '',
  },
  {
    // Sem o carimbo, "o Fábio organizou" e "eu digitei" viram a mesma coisa no
    // banco — e a evidência (o áudio) fica sem link.
    nome: 'S9 — o registro não guarda de qual áudio veio',
    pega: 'passo "e carimbado com o audio de origem"',
    de: `  update public.lead_experimental_registros
     set audio_id = p_audio_id, atualizado_em = now()
   where id = v_registro;`,
    para: '',
  },
  {
    nome: 'S10 — a fila nunca fecha (o áudio volta a ser sorteado)',
    pega: 'passo "a fila fecha como normalizado"',
    de: `     set status = 'normalizado', transcricao = v_texto, erro = null`,
    para: `     set transcricao = v_texto, erro = null`,
  },
  {
    nome: 'S11 — falhar sempre devolve pra fila (nunca desiste)',
    pega: 'passo "na 3a falha para de circular"',
    de: `  v_novo := case when v_tent >= 3 then 'erro' else 'pendente' end;`,
    para: `  v_novo := 'pendente';`,
  },
  {
    nome: 'S12 — o esgotado continua circulando',
    pega: 'passo "e o esgotado vira erro (para de circular)"',
    de: `     and f.tentativas >= 3
     and f.atualizado_em < now() - interval '15 minutes';`,
    para: `     and f.tentativas >= 99
     and f.atualizado_em < now() - interval '15 minutes';`,
  },
  {
    // GRANT ativo: `create or replace function` preserva privilégio, então um
    // mutante que só omite o revoke vira no-op depois de aplicado.
    nome: 'S13 — a fila do worker fica aberta pro professor',
    pega: 'passo "professor nao mexe na fila do worker"',
    de: 'revoke all on function public.fabio_claim_audio_experimental(integer) from public, anon, authenticated;',
    para: 'grant execute on function public.fabio_claim_audio_experimental(integer) to authenticated;',
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
