-- 074 — a mesa do professor (o semáforo dentro do app)
--
-- POR QUE: até aqui a percepção do professor não existia como dado. Esta
-- migration abre as três portas: ler a mesa, salvar UM aluno (é o que cada
-- toque chama) e devolver o progresso.
--
-- RLS: as duas policies antigas eram `auth.role() = 'authenticated'` sem
-- checagem de dono — qualquer professor logado leria a observação crua sobre os
-- alunos de qualquer colega. Nada vazou porque a tabela tinha 0 linhas. Aqui
-- elas viram dono-e-coordenação. Isso afeta o formulário do LA Report, que
-- gravava direto pelo cliente; ele está sem uso (0 linhas) e o envio era manual.

-- ─── Leitura da mesa ────────────────────────────────────────────────────────
create or replace function public.app_professor_feedback_mesa(
  p_competencia date default null
) returns jsonb
language plpgsql stable security definer set search_path to 'public'
as $$
declare
  v_prof  integer := public.fn_professor_do_usuario();
  v_comp  date    := public.fn_competencia_feedback(p_competencia);
  v_hoje  date    := public.fn_hoje_brt();
  v_saida jsonb;
begin
  if v_prof is null then
    return jsonb_build_object('erro','sem_professor_vinculado');
  end if;

  with carteira as (
    -- UMA linha por aluno. A carteira tem uma por matrícula/disciplina.
    select v.aluno_id,
           min(v.aluno_nome)                        as aluno_nome,
           (array_agg(v.unidade_id))[1]             as unidade_id,
           string_agg(distinct v.curso_nome, ' · ') as cursos,
           max(v.ultima_aula_registrada)            as ultima_aula
      from public.vw_jornada_professor_atual v
      join public.alunos a on a.id = v.aluno_id
     where v.professor_id = v_prof
       and a.arquivado_em is null
     group by v.aluno_id
  ),
  resp as (
    select f.aluno_id, f.feedback, f.pratica_em_casa, f.evolucao, f.animo,
           f.observacao,
           (f.feedback is not null and f.pratica_em_casa is not null
            and f.evolucao is not null and f.animo is not null) as completo
      from public.aluno_feedback_professor f
     where f.professor_id = v_prof
       and f.competencia  = v_comp
  )
  select jsonb_build_object(
    'competencia',   v_comp,
    'janela_aberta', public.fn_janela_feedback_aberta(v_hoje),
    'total',         count(*),
    'respondidos',   count(*) filter (where coalesce(r.completo, false)),
    'alunos', coalesce(jsonb_agg(jsonb_build_object(
        'aluno_id',         c.aluno_id,
        'nome',             c.aluno_nome,
        'cursos',           c.cursos,
        -- Snapshot do bloco: NULL (nunca teve aula registrada) cai no bloco
        -- "não viu", que é onde ele tem que aparecer.
        'teve_aula_no_mes', coalesce(c.ultima_aula >= v_comp, false),
        'dias_sem_aula',    case when coalesce(c.ultima_aula >= v_comp, false)
                                 then null else v_hoje - c.ultima_aula end,
        'feedback',         r.feedback,
        'pratica_em_casa',  r.pratica_em_casa,
        'evolucao',         r.evolucao,
        'animo',            r.animo,
        'observacao',       r.observacao,
        'completo',         coalesce(r.completo, false))
      order by coalesce(c.ultima_aula >= v_comp, false) desc,
               case when coalesce(c.ultima_aula >= v_comp, false)
                    then c.aluno_nome end asc,
               c.ultima_aula asc nulls first), '[]'::jsonb))
    into v_saida
    from carteira c
    left join resp r on r.aluno_id = c.aluno_id;

  return v_saida;
end $$;

-- ─── Progresso ──────────────────────────────────────────────────────────────
create or replace function public.app_professor_feedback_progresso(
  p_competencia date default null
) returns jsonb
language plpgsql stable security definer set search_path to 'public'
as $$
declare
  v_prof  integer := public.fn_professor_do_usuario();
  v_comp  date    := public.fn_competencia_feedback(p_competencia);
  v_total integer;
  v_ok    integer;
begin
  if v_prof is null then
    return jsonb_build_object('erro','sem_professor_vinculado');
  end if;

  select count(distinct v.aluno_id) into v_total
    from public.vw_jornada_professor_atual v
    join public.alunos a on a.id = v.aluno_id
   where v.professor_id = v_prof and a.arquivado_em is null;

  -- "Respondido" é coração E as três perguntas. Sem isso a barrinha fecharia
  -- 38/38 com a metade das perguntas vazia, e o Fábio pararia de cobrar quem
  -- não terminou. O `exists` impede que aluno que saiu da carteira conte no
  -- numerador e faça respondidos > total.
  select count(*) into v_ok
    from public.aluno_feedback_professor f
   where f.professor_id     = v_prof
     and f.competencia      = v_comp
     and f.feedback         is not null
     and f.pratica_em_casa  is not null
     and f.evolucao         is not null
     and f.animo            is not null
     and exists (select 1
                   from public.vw_jornada_professor_atual v
                   join public.alunos a on a.id = v.aluno_id
                  where v.professor_id = v_prof
                    and v.aluno_id     = f.aluno_id
                    and a.arquivado_em is null);

  return jsonb_build_object(
    'competencia',   v_comp,
    'total',         v_total,
    'respondidos',   v_ok,
    'janela_aberta', public.fn_janela_feedback_aberta(public.fn_hoje_brt()));
end $$;

-- ─── Salvar UM aluno (é o que cada toque chama) ─────────────────────────────
create or replace function public.app_professor_feedback_salvar(
  p_aluno_id        integer,
  p_feedback        text,
  p_pratica_em_casa text default null,
  p_evolucao        text default null,
  p_animo           text default null,
  p_observacao      text default null,
  p_competencia     date default null
) returns jsonb
language plpgsql security definer set search_path to 'public'
as $$
declare
  v_prof    integer := public.fn_professor_do_usuario();
  v_comp    date    := public.fn_competencia_feedback(p_competencia);
  v_unidade uuid;
  v_teve    boolean;
begin
  if v_prof is null then
    raise exception 'sem_professor_vinculado';
  end if;

  -- O professor vem SEMPRE do usuário logado, nunca de parâmetro.
  select (array_agg(v.unidade_id))[1],
         coalesce(max(v.ultima_aula_registrada) >= v_comp, false)
    into v_unidade, v_teve
    from public.vw_jornada_professor_atual v
    join public.alunos a on a.id = v.aluno_id
   where v.professor_id = v_prof
     and v.aluno_id     = p_aluno_id
     and a.arquivado_em is null;

  if v_unidade is null then
    raise exception 'aluno_fora_da_sua_carteira';
  end if;

  insert into public.aluno_feedback_professor
    (aluno_id, professor_id, unidade_id, competencia, feedback,
     pratica_em_casa, evolucao, animo, observacao,
     teve_aula_no_mes, origem, respondido_em, atualizado_em)
  values
    (p_aluno_id, v_prof, v_unidade, v_comp, p_feedback,
     p_pratica_em_casa, p_evolucao, p_animo, nullif(btrim(p_observacao), ''),
     v_teve, 'la_teacher', now(), now())
  on conflict (aluno_id, professor_id, competencia) do update
     set feedback         = excluded.feedback,
         pratica_em_casa  = excluded.pratica_em_casa,
         evolucao         = excluded.evolucao,
         animo            = excluded.animo,
         observacao       = excluded.observacao,
         teve_aula_no_mes = excluded.teve_aula_no_mes,
         atualizado_em    = now();
  -- `origem` e `respondido_em` NÃO entram no update: a primeira resposta é que
  -- data o registro, e reescrever a origem apagaria de onde ele veio.

  return public.app_professor_feedback_progresso(v_comp);
end $$;

-- ─── RLS por dono ───────────────────────────────────────────────────────────
drop policy if exists "Authenticated users can manage feedback"   on public.aluno_feedback_professor;
drop policy if exists "Authenticated users can read all feedback" on public.aluno_feedback_professor;
drop policy if exists feedback_professor_dono                     on public.aluno_feedback_professor;
drop policy if exists feedback_coordenacao_le                     on public.aluno_feedback_professor;

create policy feedback_professor_dono on public.aluno_feedback_professor
  for all to authenticated
  using      (professor_id = public.fn_professor_do_usuario())
  with check (professor_id = public.fn_professor_do_usuario());

create policy feedback_coordenacao_le on public.aluno_feedback_professor
  for select to authenticated
  using (public.fn_e_coordenacao_la_teacher());

-- ─── Portas ─────────────────────────────────────────────────────────────────
grant execute on function public.app_professor_feedback_mesa(date)      to authenticated;
grant execute on function public.app_professor_feedback_progresso(date) to authenticated;
grant execute on function public.app_professor_feedback_salvar(integer, text, text, text, text, text, date) to authenticated;
-- `from public, anon`, não só `from anon`: função nova nasce com EXECUTE para
-- PUBLIC (Postgres) e para anon/authenticated (default_acl do Supabase).
-- Revogar só de `anon` deixa o PUBLIC e a porta continua aberta.
revoke all on function public.app_professor_feedback_mesa(date)      from public, anon;
revoke all on function public.app_professor_feedback_progresso(date) from public, anon;
revoke all on function public.app_professor_feedback_salvar(integer, text, text, text, text, text, date) from public, anon;
