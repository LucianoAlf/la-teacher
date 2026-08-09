// Mutantes da 074 — a mesa do professor.
//
// V1/V2/V3 pegam os três achados que dão nome à migration: dedupe (a carteira
// tem 1.224 linhas para 1.165 alunos), a coluna certa de última aula
// (`ultima_aula_registrada`, não `data_ultima_aula` — fim de contrato, no
// futuro em 1.191/1.224) e "respondido" exigindo as três perguntas, não só o
// coração. V9/V10 são a mesma armadilha da 073: `revoke` precisa mirar
// `public, anon` juntos, senão o PUBLIC do Postgres deixa a porta aberta.
//
// V12 veio da revisão: `origem`/`respondido_em` estavam certos no código
// (fora do SET do `on conflict`) e sem nenhuma prova. O teste que teria que
// provar isso não podia comparar contra o valor "natural" da 1ª chamada —
// `now()` fica congelado no início da transação (confirmado ao vivo: duas
// chamadas com 1,5s de `pg_sleep` no meio devolveram o MESMO timestamp) e
// `origem` é literal fixo na função, então os dois nunca teriam como divergir
// nem sob o bug. O `.test.sql` planta sentinelas manuais antes da 2ª escrita
// pra tornar o mutante falseável de verdade.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/074-a-mesa-do-professor.sql'
const TESTE = 'supabase/migrations/074-a-mesa-do-professor.test.sql'
const TEMP = 'supabase/migrations/_mutante-074.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'V1 — a mesa perde o dedupe e conta matricula [a barrinha nunca fecha]',
    pega: 'passos "a mesa conta ALUNO" e "nenhum aluno aparece duas vezes"',
    de: `     group by v.aluno_id
  ),
  resp as (`,
    para: `     group by v.aluno_id, v.id
  ),
  resp as (`,
  },
  {
    nome: 'V2 — volta a coluna errada de ultima aula (fim do contrato, ate 2032)',
    pega: 'passos "ninguem tem dias_sem_aula negativo" e "quem tem aula no mes..."',
    de: `           max(v.ultima_aula_registrada)            as ultima_aula`,
    para: `           max(v.data_ultima_aula)::date            as ultima_aula`,
  },
  {
    nome: 'V3 — "respondido" volta a ser so o coracao',
    pega: 'passo "so o coracao NAO conta como respondido"',
    de: `     and f.feedback         is not null
     and f.pratica_em_casa  is not null
     and f.evolucao         is not null
     and f.animo            is not null`,
    para: `     and f.feedback         is not null`,
  },
  {
    nome: 'V4 — o salvar aceita aluno de qualquer professor',
    pega: 'passo "salvar recusa aluno fora da carteira"',
    de: `   where v.professor_id = v_prof
     and v.aluno_id     = p_aluno_id
     and a.arquivado_em is null;

  if v_unidade is null then
    raise exception 'aluno_fora_da_sua_carteira';
  end if;`,
    para: `   where v.aluno_id     = p_aluno_id
     and a.arquivado_em is null;

  if v_unidade is null then
    raise exception 'aluno_fora_da_sua_carteira';
  end if;`,
  },
  {
    nome: 'V5 — o denominador volta a contar aluno arquivado',
    pega: 'passo "arquivar um aluno tira ele do denominador"',
    de: `     where v.professor_id = v_prof
       and a.arquivado_em is null
     group by v.aluno_id`,
    para: `     where v.professor_id = v_prof
     group by v.aluno_id`,
  },
  {
    nome: 'V6 — teve_aula_no_mes gravado sempre true',
    pega: 'passo "quem tem aula no mes esta no bloco viu" (via mesa)',
    de: `        'teve_aula_no_mes', coalesce(c.ultima_aula >= v_comp, false),`,
    para: `        'teve_aula_no_mes', true,`,
  },
  {
    nome: 'V7 — a mesa volta a atender sem identidade',
    pega: 'passo "sem identidade a mesa devolve erro"',
    de: `  if v_prof is null then
    return jsonb_build_object('erro','sem_professor_vinculado');
  end if;

  with carteira as (`,
    para: `  if false then
    return jsonb_build_object('erro','sem_professor_vinculado');
  end if;

  with carteira as (`,
  },
  {
    nome: 'V8 — o salvar volta a atender sem identidade',
    pega: 'passo "sem identidade o salvar recusa"',
    de: `  if v_prof is null then
    raise exception 'sem_professor_vinculado';
  end if;`,
    para: `  if false then
    raise exception 'sem_professor_vinculado';
  end if;`,
  },
  {
    nome: 'V9 — a mesa fica aberta pro anon',
    pega: 'passo "anon NAO executa a mesa"',
    de: `revoke all on function public.app_professor_feedback_mesa(date)      from public, anon;`,
    para: `grant execute on function public.app_professor_feedback_mesa(date) to anon;`,
  },
  {
    nome: 'V10 — o salvar fica aberto pro anon',
    pega: 'passo "anon NAO executa o salvar"',
    de: `revoke all on function public.app_professor_feedback_salvar(integer, text, text, text, text, text, date) from public, anon;`,
    para: `grant execute on function public.app_professor_feedback_salvar(integer, text, text, text, text, text, date) to anon;`,
  },
  {
    nome: 'V11 — a RLS escancarada volta [a fronteira do texto cru]',
    pega: 'passo "nenhuma policy solta por auth.role() sobrou"',
    de: `create policy feedback_professor_dono on public.aluno_feedback_professor
  for all to authenticated
  using      (professor_id = public.fn_professor_do_usuario())
  with check (professor_id = public.fn_professor_do_usuario());`,
    para: `create policy feedback_professor_dono on public.aluno_feedback_professor
  for all to authenticated
  using      (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');`,
  },
  {
    nome: 'V12 — o update reescreve origem e respondido_em [achado da revisao]',
    pega: 'passos "a 2a escrita NAO reescreve origem" e "...NAO reescreve respondido_em"',
    de: `         teve_aula_no_mes = excluded.teve_aula_no_mes,
         atualizado_em    = now();`,
    para: `         teve_aula_no_mes = excluded.teve_aula_no_mes,
         origem           = excluded.origem,
         respondido_em    = excluded.respondido_em,
         atualizado_em    = now();`,
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
process.exitCode = mortos === MUTANTES.length && stale === 0 ? 0 : 1
