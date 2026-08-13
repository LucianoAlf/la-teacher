// Mutantes da 050 — a fila de áudio aprende a rotear.
//
// R1 e R4 são os que importam. R1 devolve o gatilho ao estado de hoje (chama o
// Hermes pra tudo) e R4 esquece de escrever a coluna que roteia — dois jeitos
// diferentes de a experimental cair no agente errado, um no gatilho e outro na
// porta. Se os dois morrerem, o roteamento está preso dos dois lados.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/050-fila-de-audio-aprende-a-rotear.sql'
const TESTE = 'supabase/migrations/050-fila-de-audio-aprende-a-rotear.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-050.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    // O estado de hoje: todo áudio pendente vira chamada pro Hermes, inclusive
    // o da experimental — que ele monta pelo roster e não tem onde pendurar.
    nome: 'R1 — o gatilho volta a chamar o Hermes pra tudo',
    pega: 'passo "a experimental NAO chega no Hermes"',
    de: `  if new.vinculo_id is null then
    perform public.fn_fabio_chama_edge(new.id);
  end if;`,
    para: '  perform public.fn_fabio_chama_edge(new.id);',
  },
  {
    // Inverter é pior que desligar: a aula comum (que funciona há semanas)
    // silencia e ninguém liga o sumiço ao roteamento novo.
    nome: 'R2 — o gatilho inverte (só a experimental chama)',
    pega: 'passo "a aula comum ainda chama o Hermes"',
    de: '  if new.vinculo_id is null then',
    para: '  if new.vinculo_id is not null then',
  },
  {
    nome: 'R3 — o gatilho para de chamar qualquer coisa',
    pega: 'passo "a aula comum ainda chama o Hermes"',
    de: '    perform public.fn_fabio_chama_edge(new.id);',
    para: '    perform 1;',
  },
  {
    // A porta esquece a coluna. O gatilho continua correto, e mesmo assim a
    // experimental vai pro Hermes: o roteamento depende de alguém ESCREVER.
    nome: 'R4 — a RPC não marca a linha como experimental',
    pega: 'passos "nem pela RPC o Hermes e chamado" e "a linha nasce marcada"',
    de: `    (professor_id, unidade_id, aula_id, vinculo_id, storage_path, duracao_segundos, origem, status)
  values
    (v_prof, v_aula.unidade_id, v_aula.id, p_vinculo_id, p_storage_path, p_duracao_segundos, 'app', 'pendente')`,
    para: `    (professor_id, unidade_id, aula_id, storage_path, duracao_segundos, origem, status)
  values
    (v_prof, v_aula.unidade_id, v_aula.id, p_storage_path, p_duracao_segundos, 'app', 'pendente')`,
  },
  {
    // `<>` em vez de `is distinct from`: null não compara, a comparação vira
    // nula, o if não dispara e a aula sem professor entra. Já foi buraco real
    // na 036 e na 038.
    nome: 'R5 — a guarda de posse deixa de tratar o nulo',
    pega: 'passo "a RPC recusa aula sem professor"',
    de: '  if v_aula.professor_id is distinct from v_prof then',
    para: '  if v_aula.professor_id <> v_prof then',
  },
  {
    nome: 'R6 — a RPC não olha de quem é a aula',
    pega: 'passo "a RPC recusa aula de outro professor"',
    de: `  if v_aula.professor_id is distinct from v_prof then
    raise exception 'aula_de_outro_professor';
  end if;`,
    para: '',
  },
  {
    // Sem as travas de estado, o professor grava dois minutos e só descobre no
    // fim que a aula não aceita registro.
    nome: 'R7 — a RPC aceita experimental com falta declarada',
    pega: 'passo "a RPC recusa experimental com falta"',
    de: `  elsif v_vinculo.estado = 'faltou' then
    raise exception 'experimental_faltou_nao_tem_registro';`,
    para: `  elsif v_vinculo.estado = '___nunca___' then
    raise exception 'experimental_faltou_nao_tem_registro';`,
  },
  {
    nome: 'R8 — a janela de gravação some',
    pega: 'passo "a RPC recusa fora da janela"',
    de: `  if coalesce(v_aula.data_hora_fim, v_aula.data_hora_inicio) < now() - interval '3 days' then
    raise exception 'janela_de_gravacao_encerrada';
  end if;`,
    para: '',
  },
  {
    // GRANT ativo, não só a ausência do revoke: `create or replace function`
    // PRESERVA privilégio, então um mutante que apenas omite o revoke vira
    // no-op depois da migration aplicada — e "sobrevive" por engano.
    nome: 'R9 — a porta do professor fica aberta pro anônimo',
    pega: 'passo "anonimo nao enfileira nada"',
    de: 'revoke all on function public.app_enfileirar_audio_experimental(bigint, text, integer) from public, anon;',
    para: 'grant execute on function public.app_enfileirar_audio_experimental(bigint, text, integer) to anon;',
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
