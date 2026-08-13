// Mutantes da 038 — a confirmacao que amarra o ciclo.
//
// Os 6 do plano + 2 acrescentados: N7 e N8 guardam o encontro da 038 com a
// 036 (unidade sem comercial) e a permissao do anon. Nenhum dos dois tinha
// carrasco.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/038-confirmar-registro-experimental.sql'
const TESTE = 'supabase/migrations/038-confirmar-registro-experimental.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-038.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    // A meia confirmacao que esta migration existe pra impedir: presenca
    // gravada, comercial sem saber, nada sinalizando.
    nome: 'M1 — confirma sem avisar o comercial',
    pega: 'passo "confirmacao reclamou o aviso (com lease)"',
    de: `  select public.fabio_claim_aviso_comercial(p_registro_id) into v_aviso;
  v_not_id := (v_aviso->>'notificacao_id')::uuid;`,
    para: `  v_aviso := jsonb_build_object('claimed', false, 'motivo', 'M1');
  v_not_id := null;`,
  },
  {
    nome: 'M2 — confirma sem gravar presenca',
    pega: 'passo "confirmacao gravou presenca"',
    de: `  select public.fn_registrar_presenca_experimental(
           v_vinculo_id, 'presente',
           case when v_origem = 'whatsapp' then 'fabio_audio' else 'professor_la_teacher' end)
    into v_presenca_ok;`,
    para: '  v_presenca_ok := false;',
  },
  {
    // A presenca nasceria FRACA em silencio — o selo verde mentiroso da Fase 2.
    nome: 'M3 — fonte fraca na confirmacao (presenca fantasma)',
    pega: 'passo "presenca nasceu de fonte FORTE"',
    de: "else 'professor_la_teacher' end)",
    para: "else 'emusys' end)",
  },
  {
    nome: 'M4 — idempotencia quebrada: confirmar 2x duplica o aviso',
    pega: 'passo "a 2a confirmacao se declara repetida"',
    de: `  if v_status = 'confirmado' then
    -- Idempotente: confirmar duas vezes nao duplica aviso nem regrava presenca.
    return jsonb_build_object('registro_id', p_registro_id, 'ja_confirmado', true);
  end if;`,
    para: '',
  },
  {
    // Intruso confirma registro alheio: grava presenca forte, promove o
    // estado do vinculo e dispara aviso de aula que nao e dele.
    nome: 'M5 — guarda de posse removida',
    pega: 'passo "intruso NAO confirma registro alheio"',
    de: `  if v_prof_aula is distinct from v_prof then
    raise exception 'aula_de_outro_professor';
  end if;`,
    para: '',
  },
  {
    nome: 'M6 — confirmar deixa de exigir usuario resolvido',
    pega: 'passo "sessao sem professor nao confirma aula orfa"',
    de: `  if v_prof is null then
    raise exception 'sem_professor_vinculado';
  end if;`,
    para: '',
  },
  {
    // Acrescentado: onde a 038 encosta na 036. Se a falta de contato virasse
    // excecao, o professor apertaria confirmar e o trabalho dele sumiria por
    // causa de um cadastro que nao e dele.
    nome: 'N7 — unidade sem comercial derruba a confirmacao inteira',
    pega: 'passo "sem comercial, a confirmacao NAO explode"',
    de: "  select public.fabio_claim_aviso_comercial(p_registro_id) into v_aviso;",
    para: `  select public.fabio_claim_aviso_comercial(p_registro_id) into v_aviso;
  if (v_aviso->>'claimed')::boolean is not true then
    raise exception 'sem_contato_comercial';
  end if;`,
  },
  {
    // Acrescentado: revoke sem carrasco e convencao, nao regra.
    //
    // O mutante CONCEDE de proposito, em vez de so deixar de revogar.
    // `create or replace function` PRESERVA os privilegios existentes: depois
    // que a migration foi aplicada de verdade, "esquecer o revoke" nao devolve
    // nada a ninguem e o mutante vira no-op — ele sobreviveria sem que
    // houvesse defeito nenhum. Um mutante que so funciona antes do deploy
    // deixa de vigiar exatamente quando passa a importar.
    nome: 'N8 — anon passa a confirmar registro',
    pega: 'passo "anon nao confirma registro"',
    de: 'grant execute on function public.app_confirmar_registro_experimental(uuid,integer) to service_role, authenticated;',
    para:
      'grant execute on function public.app_confirmar_registro_experimental(uuid,integer) to service_role, authenticated;\n' +
      'grant execute on function public.app_confirmar_registro_experimental(uuid,integer) to anon;',
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
