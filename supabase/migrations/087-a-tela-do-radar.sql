-- 087 — a RPC da tela do Radar
--
-- Junta os três: sinais (081) + réguas (082) + nota (085). Molde da 077/079.
--
-- UM NÚMERO SÓ (lição da 080): resumo, `total_lista` e chips contam a mesma
-- coisa, no mesmo grão. Na tela do semáforo isso apareceu como 1.155 no topo e
-- 1.161 na lista, e a causa era grão diferente entre as duas contas.
--
-- CADA FACETA IGNORA O PRÓPRIO FILTRO E RESPEITA AS OUTRAS (regra da 071).
-- Sem isso, escolher uma unidade encolhe a lista de unidades e não há como
-- voltar pra "todas" sem F5.
--
-- FRONTEIRA (§2.1 da spec): as médias por professor carregam SÓ absenteísmo.
-- Semáforo, prática, evolução e ânimo são opinião do professor sobre o aluno —
-- agregá-los por professor dá a ele incentivo pra responder verde, e aí a
-- fonte apodrece em silêncio. Cobra-se que ele responda; nunca se avalia o que
-- ele respondeu.
create or replace function public.app_coordenacao_radar(
  p_unidade_id   uuid    default null,
  p_professor_id integer default null,
  p_status       text    default null,
  p_limite       integer default 200)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cfg    jsonb;
  v_status text := nullif(btrim(coalesce(p_status, '')), '');
  v_r      jsonb;
begin
  if not public.fn_e_coordenacao_la_teacher() then
    raise exception 'apenas_admin';
  end if;

  if v_status is not null and v_status not in ('critico','atencao','saudavel','sem_nota') then
    raise exception 'status_invalido';
  end if;

  select jsonb_object_agg(chave, valor) into v_cfg from public.radar_config;

  with base as (
    select s.*, public.fn_radar_nota(
             jsonb_build_object(
               'absenteismo_pct', s.absenteismo_pct,
               'aulas_medidas',   s.aulas_medidas,
               'feedback',        s.feedback,
               'pratica_em_casa', s.pratica_em_casa,
               'faltas_mes',      s.faltas_mes,
               'aulas_mes',       s.aulas_mes), v_cfg) as nota
      from public.vw_radar_aluno_sinais s
  ),
  com_status as (
    select b.*, coalesce(b.nota ->> 'status', 'sem_nota') as status_calc
      from base b
  ),
  -- Cada faceta é cega ao próprio filtro (071).
  fac_uni  as (select * from com_status
                where (p_professor_id is null or professor_id = p_professor_id)
                  and (v_status is null or status_calc = v_status)),
  fac_prof as (select * from com_status
                where (p_unidade_id is null or unidade_id = p_unidade_id)
                  and (v_status is null or status_calc = v_status)),
  fac_st   as (select * from com_status
                where (p_unidade_id is null or unidade_id = p_unidade_id)
                  and (p_professor_id is null or professor_id = p_professor_id)),
  linha as (select * from com_status
             where (p_unidade_id is null or unidade_id = p_unidade_id)
               and (p_professor_id is null or professor_id = p_professor_id)
               and (v_status is null or status_calc = v_status))
  select jsonb_build_object(
    'config', v_cfg,
    'resumo', (select jsonb_build_object(
        'alunos',              count(*),
        'criticos',            count(*) filter (where status_calc = 'critico'),
        'atencao',             count(*) filter (where status_calc = 'atencao'),
        'saudaveis',           count(*) filter (where status_calc = 'saudavel'),
        'sem_nota',            count(*) filter (where status_calc = 'sem_nota'),
        'avisaram_que_saem',   count(*) filter (where avisou_que_sai),
        'absenteismo_media',   round(avg(absenteismo_pct), 1),
        'absenteismo_mediana', round(percentile_cont(0.5)
                                 within group (order by absenteismo_pct)::numeric, 1),
        'aulas_por_aluno',     round(avg(aulas_medidas), 1),
        'com_base',            count(*) filter (where absenteismo_pct is not null),
        'base_desde',          '2026-08-01') from linha),
    'medias', jsonb_build_object(
        'escola',   (select round(avg(absenteismo_pct),1) from com_status),
        'unidades', coalesce((select jsonb_agg(u.j order by u.unidade_codigo) from (
                       select unidade_id, unidade_codigo,
                              jsonb_build_object('unidade_id', unidade_id, 'unidade', unidade_codigo,
                                                'absenteismo_media', round(avg(absenteismo_pct),1)) as j
                         from com_status where unidade_codigo is not null
                        group by unidade_id, unidade_codigo) u), '[]'::jsonb),
        -- SÓ absenteísmo. Ver a fronteira no cabeçalho.
        'professores', coalesce((select jsonb_agg(p.j order by p.professor_nome) from (
                       select professor_id, professor_nome,
                              jsonb_build_object('professor_id', professor_id, 'professor', professor_nome,
                                                'absenteismo_media', round(avg(absenteismo_pct),1)) as j
                         from com_status where professor_id is not null
                        group by professor_id, professor_nome) p), '[]'::jsonb)),
    'linhas', coalesce((select jsonb_agg(jsonb_build_object(
        'aluno_id', aluno_id, 'aluno', aluno_nome,
        'curso', curso_nome, 'unidade', unidade_codigo,
        'professor_id', professor_id, 'professor', professor_nome,
        'nota', nota, 'status', status_calc,
        'absenteismo_pct', absenteismo_pct, 'aulas_medidas', aulas_medidas,
        'faltas_janela', faltas_janela,
        'faltas_mes', faltas_mes, 'aulas_mes', aulas_mes,
        'feedback', feedback, 'pratica_em_casa', pratica_em_casa,
        'evolucao', evolucao, 'animo', animo, 'observacao', observacao,
        'avisou_que_sai', avisou_que_sai, 'mes_saida', mes_saida)
        order by (nota ->> 'nota') is null,        -- quem tem nota primeiro
                 (nota ->> 'nota')::numeric asc,   -- pior nota no topo
                 aluno_nome)
      from (select * from linha
             order by (nota ->> 'nota') is null, (nota ->> 'nota')::numeric asc, aluno_nome
             limit p_limite) x), '[]'::jsonb),
    'total_lista', (select count(*) from linha),
    'truncado',    (select count(*) from linha) > p_limite,
    'filtros', jsonb_build_object(
      'unidades', coalesce((select jsonb_agg(jsonb_build_object(
            'unidade_id', unidade_id, 'unidade', unidade_codigo, 'alunos', n) order by unidade_codigo)
          from (select unidade_id, unidade_codigo, count(*) n from fac_uni
                 where unidade_codigo is not null group by 1,2) u), '[]'::jsonb),
      'professores', coalesce((select jsonb_agg(jsonb_build_object(
            'professor_id', professor_id, 'professor', professor_nome, 'alunos', n) order by professor_nome)
          from (select professor_id, professor_nome, count(*) n from fac_prof
                 where professor_id is not null group by 1,2) p), '[]'::jsonb),
      'status', coalesce((select jsonb_agg(jsonb_build_object(
            'status', status_calc, 'alunos', n) order by status_calc)
          from (select status_calc, count(*) n from fac_st group by 1) s), '[]'::jsonb))
  ) into v_r;

  return v_r;
end $$;

revoke all on function public.app_coordenacao_radar(uuid, integer, text, integer) from public;
grant execute on function public.app_coordenacao_radar(uuid, integer, text, integer) to authenticated;
