-- 089 — a foto do aluno chega no Radar
--
-- Pedido do Alf em 10/08/2026, olhando a mesa do desktop: "tem que trazer a
-- foto dos alunos para cá também, a gente tem isso no banco de dados já".
--
-- IDENTIDADE, NÃO SINAL. A foto não entra na nota nem em faceta nenhuma — ela
-- serve pra coordenação reconhecer O ALUNO numa lista de 311 nomes, do mesmo
-- jeito que o professor já reconhece a turma pela cara no app. Por isso vem em
-- `linhas` junto de `aluno`/`curso`/`unidade` e não passa perto de `medias`.
--
-- A FONTE É `alunos.foto_url`, e é medida: 1.447 dos 1.634 alunos têm (290 dos
-- 311 da coorte do Radar). A tabela também tem uma coluna `photo_url` — está
-- ZERADA (0 preenchidas, medido em 10/08). Ler a coluna errada daria uma tela
-- inteira de iniciais sem ninguém notar que o dado existia; o teste desta
-- migration existe pra isso, e o mutante V1 é exatamente essa troca.
--
-- Vem por `vw_aluno_sucesso_lista.foto_url`, que a view do Radar já usa como
-- fonte de nome/curso/unidade — uma fonte só de identidade, não um join novo
-- na RPC.
--
-- COLUNA NOVA VAI NO FIM (regra que a 088 mediu ao aplicar): `create or
-- replace view` recusa mudar a posição ordinal de coluna existente — só
-- permite ACRESCENTAR no fim.

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
       coalesce(fc.faltas_consecutivas, 0) as faltas_consecutivas,
       -- Nova na 089, no fim pela MESMA regra acima. Sem `coalesce` de
       -- propósito: aluno sem foto vem NULO, e nulo é o que faz o Avatar cair
       -- nas iniciais. Trocado por string vazia, o `<img>` renderiza quadrado
       -- quebrado — é o mesmo defeito de família do "ausência virando valor".
       s.foto_url                          as aluno_foto_url
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
  'sequência aberta a partir da aula mais recente (0 = sem falta ativa). '
  'aluno_foto_url é identidade, não sinal: nao entra na nota nem em media.';

revoke all on table public.vw_radar_aluno_sinais from public, anon, authenticated;
grant select on table public.vw_radar_aluno_sinais to service_role;

-- Restaurado da 087/088 (`create or replace function` troca o corpo INTEIRO —
-- reescrever sem colar o cabeçalho original apaga a justificativa junto com o
-- texto; lição que a 088 já teve que aprender):
--
-- Junta os três: sinais (081/088) + réguas (082) + nota (085/088). Molde da
-- 077/079.
--
-- UM NÚMERO SÓ (lição da 080): resumo, `total_lista` e chips contam a mesma
-- coisa, no mesmo grão. Na tela do semáforo isso apareceu como 1.155 no topo e
-- 1.161 na lista, e a causa era grão diferente entre as duas contas.
--
-- CADA FACETA IGNORA O PRÓPRIO FILTRO E RESPEITA AS OUTRAS (regra da 071).
-- Sem isso, escolher uma unidade encolhe a lista de unidades e não há como
-- voltar pra "todas" sem F5.
--
-- FRONTEIRA (§2.1 da spec) — texto completo no cabeçalho da 088: as médias por
-- professor carregam SÓ absenteísmo. Semáforo, prática, evolução e ânimo são
-- opinião do professor sobre o aluno — agregá-los por professor dá a ele
-- incentivo pra responder verde, e aí a fonte apodrece em silêncio. Cobra-se
-- que ele responda; nunca se avalia o que ele respondeu. O 5º sinal (faltas
-- consecutivas) é presença, não opinião, mas também não entra em
-- `medias.professores`. A foto da 089 muito menos: é identidade do ALUNO.
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
        'aluno_id', aluno_id, 'aluno', aluno_nome, 'foto', aluno_foto_url,
        'curso', curso_nome, 'unidade', unidade_codigo,
        'professor_id', professor_id, 'professor', professor_nome,
        'nota', nota, 'status', status_calc,
        'absenteismo_pct', absenteismo_pct, 'aulas_medidas', aulas_medidas,
        'faltas_janela', faltas_janela, 'faltas_consecutivas', faltas_consecutivas,
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
