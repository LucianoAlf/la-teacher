-- 079 — o semáforo da coordenação ganha filtro de coração e de professor
--
-- Pedido do Alf vendo a tela pronta (09/08/2026): *"tem que ter outros filtros
-- aqui: filtro de alunos que estão críticos, atenção e saudável também; filtro
-- por professor também tem que ter"*.
--
-- SUBSTITUI a assinatura de 3 argumentos da 077 — não convive com ela. Duas
-- funções com o mesmo nome e defaults sobrepostos deixam o PostgREST escolher,
-- e a escolha dele não é a nossa. Por isso o `drop` explícito antes.
--
-- O QUE MUDA NA REGRA DA LISTA
-- Sem filtro de coração, a lista continua sendo "precisam de olho" (vermelho,
-- amarelo ou com recado escrito) — verde calado fora. MAS quando a coordenação
-- escolhe um coração, ela pede AQUELE grupo inteiro: filtrar por "saudável" e
-- receber só os saudáveis que escreveram alguma coisa seria um filtro que
-- promete menos do que o clique faz — a mesma mentira do rótulo de curso que a
-- 071 já teve que consertar. `total_lista` sempre diz quantos casaram com a
-- regra vigente, e `truncado` avisa quando o corte entrou.
--
-- `sem_resposta` É UM CORAÇÃO. Não responder é o estado mais comum do mês (hoje
-- 1.160 de 1.160) e é justamente o que a coordenação precisa cobrar. Deixá-lo
-- de fora do seletor obrigaria a olhar o KPI e adivinhar quem são.
--
-- CADA FACETA IGNORA O PRÓPRIO FILTRO E RESPEITA AS OUTRAS (regra da 071)
-- É o que evita o beco: escolher "Barra", a lista de professores encolher para
-- os da Barra, e não haver como voltar pra "Todas" sem recarregar. Então:
--   unidades    → respeitam coração + professor, ignoram unidade
--   professores → respeitam coração + unidade,  ignoram professor
--   corações    → respeitam unidade + professor, ignoram coração
-- O mutante V4 desta migration existe só pra guardar essa linha.

drop function if exists public.app_coordenacao_feedback_mes(date, uuid, integer);

create or replace function public.app_coordenacao_feedback_mes(
  p_competencia  date    default null,
  p_unidade_id   uuid    default null,
  p_limite       integer default 200,
  p_coracao      text    default null,
  p_professor_id integer default null
) returns jsonb
language plpgsql stable security definer set search_path to 'public'
as $$
declare
  v_comp date := public.fn_competencia_feedback(p_competencia);
  v_hoje date := public.fn_hoje_brt();
  v_lim  int  := greatest(coalesce(p_limite, 200), 1);
  v_cor  text := nullif(btrim(coalesce(p_coracao, '')), '');
begin
  if not public.fn_e_coordenacao_la_teacher() then
    raise exception 'apenas_admin';
  end if;

  if v_cor is not null and v_cor not in ('verde','amarelo','vermelho','sem_resposta') then
    raise exception 'coracao_invalido';
  end if;

  return (
    with carteira as (
      -- UMA linha por aluno+professor, igual à mesa (074).
      select v.aluno_id,
             v.professor_id,
             min(v.aluno_nome)                        as aluno_nome,
             (array_agg(v.unidade_id))[1]             as unidade_id,
             (array_agg(v.unidade_nome))[1]           as unidade_nome,
             min(v.professor_nome)                    as professor_nome,
             string_agg(distinct v.curso_nome, ' · ') as cursos
        from public.vw_jornada_professor_atual v
        join public.alunos a on a.id = v.aluno_id
       where a.arquivado_em is null
       group by v.aluno_id, v.professor_id
    ),
    resp as (
      select f.aluno_id, f.professor_id, f.feedback, f.pratica_em_casa,
             f.evolucao, f.animo, nullif(btrim(f.observacao), '') as observacao,
             f.respondido_em, f.atualizado_em,
             (f.feedback is not null and f.pratica_em_casa is not null
              and f.evolucao is not null and f.animo is not null) as completo
        from public.aluno_feedback_professor f
       where f.competencia = v_comp
    ),
    base as (
      select c.*, r.feedback, r.pratica_em_casa, r.evolucao, r.animo,
             r.observacao, r.respondido_em, r.atualizado_em,
             coalesce(r.completo, false)          as completo,
             coalesce(r.feedback, 'sem_resposta') as coracao,
             (r.feedback in ('vermelho','amarelo') or r.observacao is not null)
               as precisa_olho
        from carteira c
        left join resp r
          on r.aluno_id = c.aluno_id and r.professor_id = c.professor_id
    ),
    -- Um recorte por faceta, cada um cego pro próprio filtro.
    fac_uni as (
      select * from base
       where (v_cor is null or coracao = v_cor)
         and (p_professor_id is null or professor_id = p_professor_id)
    ),
    fac_prof as (
      select * from base
       where (v_cor is null or coracao = v_cor)
         and (p_unidade_id is null or unidade_id = p_unidade_id)
    ),
    fac_cor as (
      select * from base
       where (p_unidade_id is null or unidade_id = p_unidade_id)
         and (p_professor_id is null or professor_id = p_professor_id)
    ),
    -- Os três filtros de uma vez: é o que os números do topo respondem.
    linha as (
      select * from fac_cor where (v_cor is null or coracao = v_cor)
    ),
    -- Sem coração escolhido a lista é "precisam de olho"; com coração, é o
    -- grupo inteiro daquele coração.
    alvo as (
      select * from linha
       where case when v_cor is null then precisa_olho else true end
    ),
    pagina as (
      select * from alvo
       order by case coracao when 'vermelho' then 0 when 'amarelo' then 1
                             when 'verde' then 2 else 3 end,
                (observacao is null),
                aluno_nome
       limit v_lim
    )
    select jsonb_build_object(
      'competencia',   v_comp,
      'janela_aberta', public.fn_janela_feedback_aberta(v_hoje),
      'resumo', (
        select jsonb_build_object(
          'alunos',         count(distinct aluno_id),
          'respondidos',    count(distinct aluno_id) filter (where completo),
          'verde',          count(distinct aluno_id) filter (where coracao = 'verde'),
          'amarelo',        count(distinct aluno_id) filter (where coracao = 'amarelo'),
          'vermelho',       count(distinct aluno_id) filter (where coracao = 'vermelho'),
          'sem_resposta',   count(distinct aluno_id) filter (where coracao = 'sem_resposta'),
          'com_recado',     count(distinct aluno_id) filter (where observacao is not null),
          'professores',    count(distinct professor_id),
          'professores_ok', count(distinct professor_id) filter (where completo))
          from linha),
      'precisam_de_olho', (select count(*) from linha where precisa_olho),
      'total_lista',      (select count(*) from alvo),
      'truncado',         (select count(*) from alvo) > v_lim,
      'alunos', coalesce((
        select jsonb_agg(jsonb_build_object(
          'aluno_id',        o.aluno_id,
          'aluno_nome',      o.aluno_nome,
          'cursos',          o.cursos,
          'unidade_id',      o.unidade_id,
          'unidade_nome',    o.unidade_nome,
          'professor_id',    o.professor_id,
          'professor_nome',  o.professor_nome,
          'feedback',        o.feedback,
          'pratica_em_casa', o.pratica_em_casa,
          'evolucao',        o.evolucao,
          'animo',           o.animo,
          'observacao',      o.observacao,
          'completo',        o.completo,
          'respondido_em',   coalesce(o.atualizado_em, o.respondido_em)))
          from pagina o), '[]'::jsonb),
      'filtros', jsonb_build_object(
        'unidades', coalesce((
          select jsonb_agg(u.j order by u.nome) from (
            select min(unidade_nome) as nome,
                   jsonb_build_object('unidade_id', unidade_id,
                                      'nome', min(unidade_nome),
                                      'alunos', count(distinct aluno_id)) as j
              from fac_uni where unidade_id is not null
             group by unidade_id) u), '[]'::jsonb),
        'professores', coalesce((
          select jsonb_agg(p.j order by p.nome) from (
            select min(professor_nome) as nome,
                   jsonb_build_object('professor_id', professor_id,
                                      'nome', min(professor_nome),
                                      'alunos', count(distinct aluno_id)) as j
              from fac_prof
             group by professor_id) p), '[]'::jsonb),
        'coracoes', coalesce((
          select jsonb_agg(c.j order by c.ordem) from (
            select case coracao when 'vermelho' then 0 when 'amarelo' then 1
                                when 'verde' then 2 else 3 end as ordem,
                   jsonb_build_object('valor', coracao,
                                      'alunos', count(distinct aluno_id)) as j
              from fac_cor
             group by coracao) c), '[]'::jsonb))
    )
  );
end;
$$;

comment on function public.app_coordenacao_feedback_mes(date, uuid, integer, text, integer) is
  'Semáforo do mês pra COORDENAÇÃO, com filtro de unidade, coração e professor '
  '(079). Sem coração escolhido a lista é "precisam de olho"; com coração, é o '
  'grupo inteiro. Cada faceta ignora o próprio filtro.';

revoke all on function public.app_coordenacao_feedback_mes(date, uuid, integer, text, integer) from public;
grant execute on function public.app_coordenacao_feedback_mes(date, uuid, integer, text, integer) to authenticated;
