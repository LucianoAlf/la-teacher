-- 088 — o 5º sinal: faltas consecutivas
--
-- Decisão do Alf (10/08/2026): duas faltas seguidas empurram pra atenção,
-- três pra crítico — e o motivo é dado escasso. Com só 9 dias de corte
-- (01/08), percentual sobre 1-2 aulas medidas é ruído; contagem BRUTA de
-- falta seguida é sinal sólido mesmo com pouquíssimo histórico.
--
-- É SINAL PONDERADO, NÃO ATROPELO: entra na mesma redistribuição dos outros
-- 4 (fn_radar_nota) — tem peso próprio, compete e se redistribui como os
-- demais. Não é um "if crítico then critico" por fora da conta.
--
-- MESMA GUARDA DO C1 (085): sem aula medida, o sinal SAI da conta — não é
-- "0 faltas seguidas = saudável fantasma".
--
-- FASE B (Fábio avisa o professor com 2 seguidas, grupo da coordenação com
-- 3+) é decisão do Alf de deixar pra depois — isto aqui é só o sinal
-- entrando na nota.

create or replace view public.vw_radar_aluno_sinais as
with coorte as (
  select id as professor_id
    from public.professores
   where coalesce(ativo, true) and usuario_id is not null
),
aula as (
  select v.aluno_id,
         v.data_aula,
         v.horario_aula,
         bool_or(v.considera_presenca) as veio
    from public.vw_aluno_presenca_semantica_v1 v
   where v.considera_frequencia_denominador
     and v.data_aula >= date '2026-08-01'
   group by 1, 2, 3
),
ordenada as (
  select aluno_id, data_aula, veio,
         row_number() over (partition by aluno_id
                            order by data_aula desc, horario_aula desc nulls last) as rn
    from aula
),
janela as (
  select aluno_id,
         count(*)                          as aulas_medidas,
         count(*) filter (where not veio)  as faltas_janela
    from ordenada
   where rn <= 10
   group by 1
),
-- Faltas seguidas a partir da aula mais recente: conta enquanto não bater a
-- primeira presença. Zero linhas = sem falta ativa (última foi presença, ou
-- não há aula medida — quem distingue os dois é o guard em fn_radar_nota).
consecutivas as (
  select o.aluno_id, count(*) as faltas_consecutivas
    from ordenada o
   where not o.veio
     and not exists (
       select 1 from ordenada o2
        where o2.aluno_id = o.aluno_id and o2.rn < o.rn and o2.veio)
   group by o.aluno_id
),
mes as (
  select aluno_id,
         count(*)                          as aulas_mes,
         count(*) filter (where not veio)  as faltas_mes
    from aula
   where data_aula >= public.fn_competencia_feedback()
   group by 1
),
semaforo as (
  select distinct on (f.aluno_id, f.professor_id)
         f.aluno_id, f.professor_id, f.feedback, f.pratica_em_casa,
         f.evolucao, f.animo, nullif(btrim(f.observacao), '') as observacao,
         f.competencia
    from public.aluno_feedback_professor f
   where f.competencia = public.fn_competencia_feedback()
   order by f.aluno_id, f.professor_id,
            coalesce(f.atualizado_em, f.respondido_em) desc
),
aviso as (
  select distinct ma.aluno_id, min(ma.mes_saida) as mes_saida
    from public.movimentacoes_admin ma
   where ma.tipo = 'aviso_previo'
     and ma.mes_saida >= public.fn_competencia_feedback()
     and ma.aluno_id is not null
   group by ma.aluno_id
)
select s.id                                as aluno_id,
       s.nome                              as aluno_nome,
       s.unidade_id,
       s.unidade_codigo,
       s.professor_atual_id                as professor_id,
       s.professor_nome,
       s.curso_nome,
       coalesce(j.aulas_medidas, 0)        as aulas_medidas,
       coalesce(j.faltas_janela, 0)        as faltas_janela,
       case when coalesce(j.aulas_medidas, 0) > 0
            then round(100.0 * j.faltas_janela / j.aulas_medidas, 1)
       end                                 as absenteismo_pct,
       coalesce(m.faltas_mes, 0)           as faltas_mes,
       coalesce(m.aulas_mes, 0)            as aulas_mes,
       sf.feedback,
       sf.pratica_em_casa,
       sf.evolucao,
       sf.animo,
       sf.observacao,
       sf.competencia                      as feedback_competencia,
       (av.aluno_id is not null)           as avisou_que_sai,
       av.mes_saida,
       -- Novo na 088: precisa ficar no FIM da lista. `create or replace view`
       -- recusa mudar a posição ordinal de coluna existente (só permite
       -- ACRESCENTAR no fim) — medido ao aplicar, não previsto no brief.
       coalesce(fc.faltas_consecutivas, 0) as faltas_consecutivas
  from public.vw_aluno_sucesso_lista s
  join coorte c   on c.professor_id = s.professor_atual_id
  left join janela j        on j.aluno_id = s.id
  left join consecutivas fc on fc.aluno_id = s.id
  left join mes m           on m.aluno_id = s.id
  left join semaforo sf on sf.aluno_id = s.id and sf.professor_id = s.professor_atual_id
  left join aviso av  on av.aluno_id = s.id;

comment on view public.vw_radar_aluno_sinais is
  'Sinais do Radar da coordenação, grão de ALUNO. Presença vem de '
  'vw_aluno_presenca_semantica_v1 no grão de AULA (aluno,dia,hora), janela '
  'desde 01/08/2026, só coorte de professor com login liberado. '
  'absenteismo_pct é NULO sem base — nunca zero. faltas_consecutivas é a '
  'sequência aberta a partir da aula mais recente (0 = sem falta ativa).';

revoke all on table public.vw_radar_aluno_sinais from public, anon, authenticated;
grant select on table public.vw_radar_aluno_sinais to service_role;

insert into public.radar_config (chave, valor, fabrica, rotulo, grupo, ordem) values
  ('peso_faltas_consecutivas',    20, 20, 'Faltas consecutivas',           'pesos',        11),
  ('faltas_consecutivas_atencao',  2,  2, 'Atenção a partir de (seguidas)', 'consecutivas', 12),
  ('faltas_consecutivas_critico',  3,  3, 'Crítico a partir de (seguidas)', 'consecutivas', 13)
on conflict (chave) do nothing;

create or replace function public.fn_radar_nota(p_sinais jsonb, p_config jsonb)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_dec        jsonb := '[]'::jsonb;
  v_peso_vivo  numeric := 0;
  v_apurados   int := 0;
  v_nota       numeric;
  v_status     text;
  v_minimo     int := coalesce((p_config->>'minimo_sinais_para_nota')::int, 2);
  r            record;
begin
  for r in
    select * from (values
      ('absenteismo',
       case when (p_sinais->>'absenteismo_pct') is not null
            then greatest(0, 100 - (p_sinais->>'absenteismo_pct')::numeric) end,
       coalesce((p_config->>'peso_absenteismo')::numeric, 0),
       case when (p_sinais->>'absenteismo_pct') is not null
            then format('%s%% (%s de %s)', p_sinais->>'absenteismo_pct',
                        coalesce((p_sinais->>'aulas_medidas')::int, 0)
                          - round(coalesce((p_sinais->>'aulas_medidas')::numeric,0)
                            * (1 - (p_sinais->>'absenteismo_pct')::numeric/100)),
                        p_sinais->>'aulas_medidas') end),
      ('feedback',
       case p_sinais->>'feedback'
            when 'verde' then 100 when 'amarelo' then 50 when 'vermelho' then 0 end,
       coalesce((p_config->>'peso_feedback')::numeric, 0),
       p_sinais->>'feedback'),
      ('pratica',
       case p_sinais->>'pratica_em_casa'
            when 'sim' then 100 when 'as_vezes' then 50 when 'nao' then 0 end,
       coalesce((p_config->>'peso_pratica')::numeric, 0),
       p_sinais->>'pratica_em_casa'),
      ('faltas_mes',
       case when (p_sinais->>'faltas_mes') is not null
                 and coalesce((p_sinais->>'aulas_mes')::int, 0) > 0
            then greatest(0, 100 - 100.0 * (p_sinais->>'faltas_mes')::numeric
                                        / (p_sinais->>'aulas_mes')::numeric) end,
       coalesce((p_config->>'peso_faltas_mes')::numeric, 0),
       case when (p_sinais->>'faltas_mes') is not null
                 and coalesce((p_sinais->>'aulas_mes')::int, 0) > 0
            then format('%s de %s no mês', p_sinais->>'faltas_mes', p_sinais->>'aulas_mes') end),
      -- Sinal ponderado, não atropelo: a urgência é o PESO, não um "if" por
      -- fora da redistribuição. Mesma guarda do C1: sem aula medida, sai da
      -- conta — 0 faltas seguidas por FALTA DE DADO != 0 por presença real.
      ('faltas_consecutivas',
       case when coalesce((p_sinais->>'aulas_medidas')::int, 0) > 0
            then case
                   when (p_sinais->>'faltas_consecutivas')::int
                        >= coalesce((p_config->>'faltas_consecutivas_critico')::int, 3) then 0
                   when (p_sinais->>'faltas_consecutivas')::int
                        >= coalesce((p_config->>'faltas_consecutivas_atencao')::int, 2) then 50
                   else 100 end
            end,
       coalesce((p_config->>'peso_faltas_consecutivas')::numeric, 0),
       case when coalesce((p_sinais->>'aulas_medidas')::int, 0) > 0
            then format('%s falta(s) seguida(s)', coalesce(p_sinais->>'faltas_consecutivas', '0')) end)
    ) as t(sinal, score, peso, valor)
  loop
    if r.score is null then
      v_dec := v_dec || jsonb_build_object(
        'sinal', r.sinal, 'valor', null, 'score', null,
        'peso', r.peso, 'peso_efetivo', null, 'contribuiu', null, 'sem_dado', true);
    else
      v_apurados  := v_apurados + 1;
      v_peso_vivo := v_peso_vivo + r.peso;
      v_dec := v_dec || jsonb_build_object(
        'sinal', r.sinal, 'valor', r.valor, 'score', r.score,
        'peso', r.peso, 'sem_dado', false);
    end if;
  end loop;

  if v_peso_vivo > 0 then
    v_dec := (
      select jsonb_agg(
        case when (d->>'sem_dado')::boolean then d
             else d || jsonb_build_object(
               'peso_efetivo', round(100.0 * (d->>'peso')::numeric / v_peso_vivo, 1),
               'contribuiu',   round((d->>'score')::numeric * (d->>'peso')::numeric
                                     / v_peso_vivo, 1),
               'de',           round(100.0 * (d->>'peso')::numeric / v_peso_vivo, 1))
        end order by ord)
        from jsonb_array_elements(v_dec) with ordinality as e(d, ord));

    select round(sum((d->>'contribuiu')::numeric)) into v_nota
      from jsonb_array_elements(v_dec) d
     where not (d->>'sem_dado')::boolean;
  end if;

  if v_apurados < v_minimo then
    v_nota := null;
    v_dec := (
      select jsonb_agg(
               d || jsonb_build_object('contribuiu', null, 'peso_efetivo', null, 'de', null)
               order by ord)
        from jsonb_array_elements(v_dec) with ordinality as e(d, ord));
  end if;

  v_status := case
    when v_nota is null then null
    when v_nota < coalesce((p_config->>'faixa_critico')::numeric, 40)   then 'critico'
    when v_nota >= coalesce((p_config->>'faixa_saudavel')::numeric, 70) then 'saudavel'
    else 'atencao' end;

  return jsonb_build_object(
    'nota', v_nota,
    'status', v_status,
    'sinais_apurados', v_apurados,
    'sinais_totais', 5,
    'suficiente', v_apurados >= v_minimo,
    'decomposicao', v_dec);
end $$;

comment on function public.fn_radar_nota(jsonb, jsonb) is
  'Nota do Radar. PURA. 5 sinais: absenteismo, feedback, pratica, faltas_mes, '
  'faltas_consecutivas. Sinal sem dado sai da conta e o peso se redistribui '
  '(nunca neutro, nunca zero). Abaixo de minimo_sinais_para_nota a nota vem '
  'NULA — mas a decomposicao vem, pra tela explicar.';

revoke all on function public.fn_radar_nota(jsonb, jsonb) from public;
grant execute on function public.fn_radar_nota(jsonb, jsonb) to authenticated;

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
               'absenteismo_pct',     s.absenteismo_pct,
               'aulas_medidas',       s.aulas_medidas,
               'feedback',            s.feedback,
               'pratica_em_casa',     s.pratica_em_casa,
               'faltas_mes',          s.faltas_mes,
               'aulas_mes',           s.aulas_mes,
               'faltas_consecutivas', s.faltas_consecutivas), v_cfg) as nota
      from public.vw_radar_aluno_sinais s
  ),
  com_status as (
    select b.*, coalesce(b.nota ->> 'status', 'sem_nota') as status_calc
      from base b
  ),
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
        'faltas_janela', faltas_janela, 'faltas_consecutivas', faltas_consecutivas,
        'faltas_mes', faltas_mes, 'aulas_mes', aulas_mes,
        'feedback', feedback, 'pratica_em_casa', pratica_em_casa,
        'evolucao', evolucao, 'animo', animo, 'observacao', observacao,
        'avisou_que_sai', avisou_que_sai, 'mes_saida', mes_saida)
        order by (nota ->> 'nota') is null,
                 (nota ->> 'nota')::numeric asc,
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
