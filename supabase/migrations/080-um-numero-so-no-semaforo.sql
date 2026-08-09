-- 080 — o semáforo da coordenação passa a ter UM número só
--
-- ACHADO NA TELA, minutos depois de a 079 subir: o KPI dizia "0 de 1155" e o
-- título da lista, na mesma tela, dizia "1161". Seis de diferença, sem
-- explicação visível — exatamente o defeito que eu tinha consertado de manhã na
-- carteira do professor e que voltou aqui pela porta dos fundos.
--
-- DE ONDE VINHAM OS SEIS
-- O grão desta tela é (aluno, professor): quem faz aula com DOIS professores é
-- respondido por cada um deles, e são duas respostas diferentes sobre a mesma
-- criança. A lista, corretamente, mostrava um card por par (1161). Os números
-- do topo contavam `distinct aluno_id` (1155).
--
-- QUAL DOS DOIS ESTÁ CERTO: o 1161. A mesa de cada professor conta os alunos
-- DELE; somar as mesas dos 43 professores dá o número de pares, não o de
-- crianças. Como esta tela é a visão de "o que os professores responderam",
-- ela tem que fechar com a soma das mesas — senão a coordenação cobra 1155 e
-- os professores entregam 1161, e ninguém sabe explicar a diferença.
--
-- O mesmo vale pros chips dos filtros: o número ao lado de "Barra" tem que ser
-- o que aparece na lista quando se escolhe Barra. Chip que promete menos do que
-- o clique entrega é a mesma mentira do rótulo de curso da 071.
--
-- `professores` e `professores_ok` seguem em `distinct professor_id` — ali a
-- pergunta é "quantas pessoas", e pessoa não se conta em par.
--
-- Só muda CONTAGEM. Nenhum filtro, nenhuma regra de lista, nenhuma fronteira.

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
      -- UMA linha por aluno+professor. A carteira crua tem uma por matrícula, e
      -- a renovação de contrato duplica (medido em 09/08: 54 linhas a mais).
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
    linha as (
      select * from fac_cor where (v_cor is null or coracao = v_cor)
    ),
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
        -- `count(*)` = pares aluno+professor, o MESMO grão da lista e da soma
        -- das mesas. Ver o cabeçalho: com `distinct aluno_id` a tela mostrava
        -- dois números diferentes da mesma coisa.
        select jsonb_build_object(
          'alunos',         count(*),
          'respondidos',    count(*) filter (where completo),
          'verde',          count(*) filter (where coracao = 'verde'),
          'amarelo',        count(*) filter (where coracao = 'amarelo'),
          'vermelho',       count(*) filter (where coracao = 'vermelho'),
          'sem_resposta',   count(*) filter (where coracao = 'sem_resposta'),
          'com_recado',     count(*) filter (where observacao is not null),
          -- Pessoa se conta uma vez só.
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
                                      'alunos', count(*)) as j
              from fac_uni where unidade_id is not null
             group by unidade_id) u), '[]'::jsonb),
        'professores', coalesce((
          select jsonb_agg(p.j order by p.nome) from (
            select min(professor_nome) as nome,
                   jsonb_build_object('professor_id', professor_id,
                                      'nome', min(professor_nome),
                                      'alunos', count(*)) as j
              from fac_prof
             group by professor_id) p), '[]'::jsonb),
        'coracoes', coalesce((
          select jsonb_agg(c.j order by c.ordem) from (
            select case coracao when 'vermelho' then 0 when 'amarelo' then 1
                                when 'verde' then 2 else 3 end as ordem,
                   jsonb_build_object('valor', coracao,
                                      'alunos', count(*)) as j
              from fac_cor
             group by coracao) c), '[]'::jsonb))
    )
  );
end;
$$;

comment on function public.app_coordenacao_feedback_mes(date, uuid, integer, text, integer) is
  'Semáforo do mês pra COORDENAÇÃO, com filtro de unidade, coração e professor. '
  'Grão = par (aluno, professor), o mesmo da lista e da soma das mesas (080).';
