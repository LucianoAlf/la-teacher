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
//
// V13 é de outra task (a fronteira family-safe do mutante 4 do plano, nunca
// coberta): nenhuma função criada por ESTA migration é family-facing, então
// o mutante redefine — só dentro da transação do ensaio, via `create or
// replace function` — uma rotina family-facing REAL de outra migration
// (fabio_devolutiva_contexto, 020c) pra acrescentar 1 campo que lê
// aluno_feedback_professor.observacao. O rollback do runner desfaz a
// redefinição igual desfaz o resto; nenhuma outra rotina desta 074 toca
// fabio_devolutiva_contexto, então só o passo novo (catálogo) deveria cair.

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
  {
    nome: 'V13 — a devolutiva passa a levar a observacao do semaforo [furou a fronteira family-safe]',
    pega: 'passo "nenhuma rotina family-facing (devolutiva/pedagogico/responsavel/anamnese) seleciona observacao de aluno_feedback_professor"',
    // Ancora no fim do arquivo (o ultimo `revoke`, unico) e ACRESCENTA um
    // `create or replace function` que redefine fabio_devolutiva_contexto
    // (020c) so dentro da transacao do ensaio — o rollback do runner desfaz
    // igual desfaz qualquer outro DDL deste arquivo. E o defeito REAL que o
    // mutante 4 do plano descrevia: um caminho family-facing (o worker do
    // Fabio le exatamente este jsonb pra escrever a devolutiva que vai pro
    // responsavel) passa a expor aluno_feedback_professor.observacao — o
    // texto interno que 020c documentava como intencionalmente inacessivel
    // ("o worker nao ve campos crus... nada de observacao/obs_gerais/
    // materiais").
    de: `revoke all on function public.app_professor_feedback_salvar(integer, text, text, text, text, text, date) from public, anon;`,
    para: `revoke all on function public.app_professor_feedback_salvar(integer, text, text, text, text, text, date) from public, anon;

-- MUTANTE V13 (074): redefine fabio_devolutiva_contexto (020c) SO dentro
-- desta transacao de teste — o rollback do runner desfaz. "So mais um campo
-- de contexto pro Fabio" e exatamente o furo que a fronteira family-safe
-- existe pra impedir.
create or replace function public.fabio_devolutiva_contexto(p_devolutiva_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
stable
as $function$
declare
  d public.fabio_devolutivas%rowtype;
  r public.fabio_registros_aula%rowtype;
  t public.fabio_registros_aula%rowtype;
  a public.alunos%rowtype;
  v_skill public.fabio_skills%rowtype;
  v_idade integer;
begin
  select * into d from public.fabio_devolutivas where id = p_devolutiva_id;
  if not found then return jsonb_build_object('ok', false, 'erro', 'devolutiva não encontrada'); end if;

  select * into r from public.fabio_registros_aula where id = d.registro_fatia_id;
  if not found then return jsonb_build_object('ok', false, 'erro', 'registro não encontrado'); end if;

  -- tronco: só existe quando é fatia de turma
  if r.parent_id is not null then
    select * into t from public.fabio_registros_aula where id = r.parent_id;
  end if;

  select * into a from public.alunos where id = d.aluno_id;
  select * into v_skill from public.fabio_skills where nome = 'devolutiva_aula' and ativa;

  -- Idade da DATA DE NASCIMENTO, sempre. alunos.idade_atual é cache e envelhece
  -- errado (fica parado enquanto o aluno faz aniversário).
  if a.data_nascimento is not null then
    v_idade := date_part('year', age(a.data_nascimento))::integer;
  end if;

  return jsonb_build_object(
    'ok', true,
    'devolutiva_id', d.id,
    'professor_id', d.professor_id,
    'professor_nome', (select p.nome from public.professores p where p.id = d.professor_id),
    -- AQUI mora a fronteira: nada de observacao/obs_gerais/materiais.
    'fonte', public.fn_devolutiva_fonte(coalesce(t.campos, '{}'::jsonb), coalesce(r.campos, '{}'::jsonb)),
    'aluno', jsonb_build_object(
      'id', a.id,
      'nome', a.nome,
      'primeiro_nome', split_part(btrim(a.nome), ' ', 1),
      'data_nascimento', a.data_nascimento,
      'idade', v_idade,
      'responsavel_nome', nullif(btrim(coalesce(a.responsavel_nome,'')), ''),
      'curso', (select c.nome from public.cursos c where c.id = a.curso_id)),
    'skill', case when v_skill.id is null then null else jsonb_build_object(
      'id', v_skill.id, 'versao', v_skill.versao, 'conteudo', v_skill.conteudo) end,
    'destinatario_override', d.destinatario_override,
    'observacao_semaforo', (select f.observacao from public.aluno_feedback_professor f
                              where f.aluno_id = d.aluno_id and f.professor_id = d.professor_id
                              order by f.competencia desc limit 1)
  );
end $function$;`,
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
