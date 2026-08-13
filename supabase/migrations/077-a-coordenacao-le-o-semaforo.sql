-- SUPERADA POR: 079-o-semaforo-ganha-filtros.sql
--
-- Este arquivo cria `app_coordenacao_feedback_mes(date, uuid, integer)`. A 079
-- fez `drop function` dessa assinatura e criou a de CINCO parametros
-- (`+ p_coracao text, p_professor_id integer`), que e a viva. Replayar aqui
-- ressuscita a de tres AO LADO da de cinco: a chamada sem argumentos passa a
-- ser ambigua (`42725: function ... is not unique`) -- que e exatamente o
-- erro que o teste acusa. Nao ha ambiguidade em producao: conferido, existe
-- uma assinatura so.
--
-- 077 — a coordenação lê o semáforo (e a observação chega em alguém)
--
-- POR QUE ESTA MIGRATION EXISTE
-- O campo de observação da mesa tem este convite escrito na tela: "Algo que
-- vale a coordenação saber". Medido em 09/08/2026, grep no `src` deste repo e
-- no do LA Report: a coluna `observacao` NÃO era lida por nenhum consumidor.
-- O que a coordenação enxergava do semáforo era só CUMPRIMENTO — quem
-- respondeu, quantos faltam (a cobrança da 076 e o Painel Farmer) — e o
-- coração, indireto, valendo 20% do `health_score`. As três perguntas e o
-- texto do professor não chegavam a ninguém.
--
-- Pedir a alguém que escreva pra um leitor que não existe é pior do que não
-- pedir: gasta o tempo dele e ensina que o app não serve pra nada.
--
-- O QUE ELA ENTREGA
-- `app_coordenacao_feedback_mes` — a leitura da coordenação: o resumo do mês e
-- a lista de quem PRECISA DE OLHO. É a fonte única desta pergunta; o painel do
-- LA Teacher, o LA Report e o Fábio devem ler daqui em vez de cada um montar a
-- sua (foi assim que a carteira acabou com duas contagens diferentes).
--
-- O MESMO UNIVERSO DA MESA, DE PROPÓSITO
-- A carteira (`vw_jornada_professor_atual`) tem uma linha por MATRÍCULA: quem
-- renovou contrato aparece duas vezes. Contar linha aqui e aluno lá faria a
-- coordenação ver 24 onde o professor vê 21 — e o professor seria cobrado por
-- uma diferença que é do SQL, não dele. Por isso o `group by v.aluno_id` e os
-- `count(distinct)`: o teste desta migration compara os dois números na marra.
--
-- QUEM PRECISA DE OLHO
-- vermelho, amarelo, ou QUALQUER coração com observação escrita. O verde com
-- observação entra porque o texto é o motivo desta migration existir — um
-- elogio ou um pedido de material não são alarme, mas são justamente o que a
-- coordenação nunca recebeu. Verde silencioso fica fora: é o caso em que não
-- há nada a fazer, e listar todo mundo é a mesma parede de texto que já torna
-- o escalonamento diário ilegível.
--
-- SEM CORTE SILENCIOSO
-- `p_limite` existe pra que uma escola inteira respondendo não devolva um JSON
-- de 1.600 alunos, mas o payload sempre diz `truncado` e `precisam_de_olho`
-- (o total real). Lista cortada que não se anuncia lê como "é só isso".
--
-- FRONTEIRA
-- Esta função é da COORDENAÇÃO (`fn_e_coordenacao_la_teacher`), e a observação
-- crua sai aqui de propósito: ela foi escrita PARA a coordenação. O que
-- continua valendo é a fronteira do outro lado — `observacao` nunca vai pro
-- aluno, pro responsável nem pra devolutiva, e nada de inadimplência entra
-- neste payload.

create or replace function public.app_coordenacao_feedback_mes(
  p_competencia date default null,
  p_unidade_id  uuid default null,
  p_limite      integer default 200
) returns jsonb
language plpgsql stable security definer set search_path to 'public'
as $$
declare
  v_comp  date := public.fn_competencia_feedback(p_competencia);
  v_hoje  date := public.fn_hoje_brt();
  v_lim   int  := greatest(coalesce(p_limite, 200), 1);
  v_saida jsonb;
begin
  if not public.fn_e_coordenacao_la_teacher() then
    raise exception 'apenas_admin';
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
    -- O filtro de unidade vale pra lista E pros números; as OPÇÕES do filtro
    -- são montadas antes dele, senão escolher uma unidade apagaria as outras
    -- da lista e não haveria como voltar.
    universo as (
      select * from carteira
       where p_unidade_id is null or unidade_id = p_unidade_id
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
    linha as (
      select u.*, r.feedback, r.pratica_em_casa, r.evolucao, r.animo,
             r.observacao, r.respondido_em, r.atualizado_em,
             coalesce(r.completo, false) as completo,
             (r.feedback in ('vermelho','amarelo') or r.observacao is not null)
               as precisa_olho
        from universo u
        left join resp r
          on r.aluno_id = u.aluno_id and r.professor_id = u.professor_id
    ),
    olho as (
      select * from linha
       where precisa_olho
       -- Vermelho primeiro; depois amarelo; verde com recado por último. Dentro
       -- de cada faixa, quem tem texto vem antes — texto é o que exige leitura.
       order by case feedback when 'vermelho' then 0 when 'amarelo' then 1 else 2 end,
                (observacao is null),
                aluno_nome
       limit v_lim
    ),
    fac as (
      select c.unidade_id, min(c.unidade_nome) as nome,
             count(distinct c.aluno_id)::int as alunos
        from carteira c
       where c.unidade_id is not null
       group by c.unidade_id
    )
    select jsonb_build_object(
      'competencia',   v_comp,
      'janela_aberta', public.fn_janela_feedback_aberta(v_hoje),
      'resumo', (
        select jsonb_build_object(
          'alunos',         count(distinct aluno_id),
          'respondidos',    count(distinct aluno_id) filter (where completo),
          'verde',          count(distinct aluno_id) filter (where feedback = 'verde'),
          'amarelo',        count(distinct aluno_id) filter (where feedback = 'amarelo'),
          'vermelho',       count(distinct aluno_id) filter (where feedback = 'vermelho'),
          'sem_resposta',   count(distinct aluno_id) filter (where feedback is null),
          'com_recado',     count(distinct aluno_id) filter (where observacao is not null),
          'professores',    count(distinct professor_id),
          'professores_ok', count(distinct professor_id) filter (where completo))
          from linha),
      'precisam_de_olho', (select count(*) from linha where precisa_olho),
      'truncado',         (select count(*) from linha where precisa_olho) > v_lim,
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
          from olho o), '[]'::jsonb),
      'filtros', jsonb_build_object(
        'unidades', coalesce((
          select jsonb_agg(jsonb_build_object(
            'unidade_id', f.unidade_id, 'nome', f.nome, 'alunos', f.alunos)
            order by f.nome)
            from fac f), '[]'::jsonb))
    )
  );
end;
$$;

comment on function public.app_coordenacao_feedback_mes(date, uuid, integer) is
  'Semáforo do mês pra COORDENAÇÃO: resumo + quem precisa de olho (vermelho, '
  'amarelo ou com observação do professor). Mesmo universo da mesa do '
  'professor (077).';

revoke all on function public.app_coordenacao_feedback_mes(date, uuid, integer) from public;
grant execute on function public.app_coordenacao_feedback_mes(date, uuid, integer) to authenticated;
