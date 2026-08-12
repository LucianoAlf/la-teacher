// Mutantes 091 - as cinco portas nao podem divergir nem abrir uma ACL lateral.
// Cada mutante roda o SQL inteiro em BEGIN/ROLLBACK contra o alvo compartilhado.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/091-as-cinco-portas-do-whatsapp.sql'
const TESTE = 'supabase/migrations/091-as-cinco-portas-do-whatsapp.test.sql'
const TEMP = 'supabase/migrations/_mutante-091.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'M1 - correcao perde a guarda de professor',
    de: 'if v_prof_dono is distinct from p_professor_id then',
    para: 'if false then',
  },
  {
    nome: 'M2 - correcao perde a regeneracao de texto',
    de: 'set texto_consolidado = public.fn_compor_texto_prontuario(\n         v_campos_novos, f.campos)',
    para: 'set texto_consolidado = public.jsonb_build_object(\n         v_campos_novos, f.campos)',
  },
  {
    nome: 'M3 - confirmacao perde o hook de devolutiva',
    de: 'v_ganchos := public.fabio_emitir_presenca_por_registro_e_devolutiva(p_registro_id);',
    para: "v_ganchos := '{}'::jsonb;",
  },
  {
    nome: 'M4 - fonte professor_whatsapp deixa de ser aceita',
    de: "'professor_la_teacher', 'fabio_audio', 'professor_whatsapp'",
    para: "'professor_la_teacher', 'fabio_audio'",
  },
  {
    nome: 'M5 - presenca deixa de sincronizar gemeos',
    de: 'v_gemeos := public.fn_sincronizar_gemeos_presenca(v_aula.id);',
    para: 'v_gemeos := 0;',
  },
  {
    nome: 'M6 - ACL da confirmacao abre para authenticated',
    de: 'grant execute on function public.fabio_confirmar_registro(integer,uuid,text) to service_role;',
    para: 'grant execute on function public.fabio_confirmar_registro(integer,uuid,text) to authenticated;',
  },
  {
    nome: 'M7 - confirmacao passa a depender da janela',
    de: 'create or replace function public.fn_confirmar_registro_core(\n  p_professor_id integer, p_confirmado_por uuid, p_registro_id uuid, p_modo text\n) returns jsonb\nlanguage plpgsql security definer\nset search_path = pg_catalog, public\nas $function$\ndeclare\n  v_reg',
    para: 'create or replace function public.fn_confirmar_registro_core(\n  p_professor_id integer, p_confirmado_por uuid, p_registro_id uuid, p_modo text\n) returns jsonb\nlanguage plpgsql security definer\nset search_path = pg_catalog, public\nas $function$\n-- fn_janela_registro_dias nao pertence a confirmacao\ndeclare\n  v_reg',
  },
  {
    nome: 'M8 - audio do WhatsApp perde origem whatsapp',
    de: "    'whatsapp', p_professor_id);",
    para: "    'app', p_professor_id);",
  },
  {
    nome: 'M9 - read-back de registro perde a guarda de professor',
    de: 'and r.professor_id = p_professor_id;',
    para: 'and true;',
  },
  {
    nome: 'M10 - confirmacao perde o mapeamento para usuarios.id',
    de: 'select u.id into v_user_id\n    from public.usuarios u\n   where u.auth_user_id = p_confirmado_por;',
    para: 'select null::integer into v_user_id;',
  },
]

let mortos = 0
let stale = 0

for (const m of MUTANTES) {
  const ocorrencias = fonte.split(m.de).length - 1
  if (ocorrencias !== 1) {
    console.log(`STALE  ${m.nome} - ancora aparece ${ocorrencias} vez(es)`)
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
console.log(`\n${mortos}/${MUTANTES.length} mutantes mortos` + (stale ? ` - ${stale} ancora(s) podre(s)` : ''))
process.exitCode = mortos === MUTANTES.length ? 0 : 1
