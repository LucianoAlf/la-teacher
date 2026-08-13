// Mutantes do contrato de replay do áudio experimental.
// Cada alteração abaixo precisa morrer no teste SQL transacional. Se uma
// sobreviver, o mesmo timeout pode voltar a duplicar uma fila ou negar o
// reenvio que a UI preservou localmente.

import { execFileSync } from 'node:child_process'
import { readFileSync, unlinkSync, writeFileSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/20260813004713_audio_experimental_duravel.sql'
const TESTE = 'supabase/migrations/20260813004713_audio_experimental_duravel.test.sql'
const TEMP = 'supabase/migrations/_mutante-audio-experimental-duravel.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'M1 — UPDATE deixa de exigir a pasta do proprio usuario',
    de: '(storage.foldername(name))[1] = auth.uid()::text',
    para: 'auth.uid() is not null',
  },
  {
    nome: 'M2 — replay deixa de ser serializado',
    de: "  perform pg_advisory_xact_lock(hashtextextended(\n    'fabio-fila-audio:' || v_prof::text || ':' || v_storage_path, 0\n  ));",
    para: '  perform 1;',
  },
  {
    nome: 'M3 — path pode migrar para outra experimental',
    de: `    if v_existente.vinculo_id is distinct from p_vinculo_id then
      raise exception 'storage_path_reutilizado_para_outra_experimental';
    end if;`,
    para: '    if false then perform 1; end if;',
  },
  {
    nome: 'M4 — indice unico que segura corrida some',
    de: `create unique index if not exists uq_fabio_fila_audio_experimental_path
  on public.fabio_fila_audios (professor_id, storage_path)
  where vinculo_id is not null;`,
    para: '',
  },
  {
    nome: 'M5 — anon recebe EXECUTE na porta experimental',
    de: 'grant execute on function public.app_enfileirar_audio_experimental(bigint, text, integer)\n  to authenticated;',
    para: 'grant execute on function public.app_enfileirar_audio_experimental(bigint, text, integer)\n  to authenticated, anon;',
  },
]

let aprovados = 0
for (const mutante of MUTANTES) {
  if (!fonte.includes(mutante.de)) {
    console.log(`STALE  ${mutante.nome}`)
    continue
  }
  writeFileSync(TEMP, fonte.replace(mutante.de, mutante.para))
  let morreu = false
  try {
    execFileSync('node', ['scripts/rodar-teste-sql.mjs', TEMP, TESTE], { stdio: 'pipe' })
  } catch {
    morreu = true
  }
  if (morreu) {
    aprovados += 1
    console.log(`OK     morto: ${mutante.nome}`)
  } else {
    console.log(`FALHA  sobreviveu: ${mutante.nome}`)
  }
}

try { unlinkSync(TEMP) } catch {}
console.log(`\n${aprovados}/${MUTANTES.length} mutantes mortos`)
process.exitCode = aprovados === MUTANTES.length ? 0 : 1
