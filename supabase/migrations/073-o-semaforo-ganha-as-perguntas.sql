-- 073 — o semáforo ganha as perguntas (e as réguas de data)
--
-- POR QUE: `aluno_feedback_professor` existe desde sempre e tem ZERO linhas.
-- `calcular_health_score_aluno` já LÊ essa tabela, com peso configurado — ou
-- seja, o pilar pedagógico do score sempre valeu zero. Esta migration prepara a
-- tabela para a coleta nascer dentro do app do professor.
--
-- DECISÃO DO ALF: grava na tabela que o score já lê. "Não cria duas verdades."
--
-- `origem` NÃO tem default de propósito: um default 'la_teacher' rotularia como
-- nosso qualquer linha vinda do formulário antigo do LA Report. Quem escreve é
-- que declara de onde veio.

alter table public.aluno_feedback_professor
  add column if not exists pratica_em_casa  text,
  add column if not exists evolucao         text,
  add column if not exists animo            text,
  add column if not exists teve_aula_no_mes boolean,
  add column if not exists origem           text,
  add column if not exists atualizado_em    timestamptz not null default now();

-- `drop if exists` antes do `add`: `add constraint` não é idempotente, e a
-- suíte reaplica cada migration. Sem isso o arquivo sai da suíte em silêncio.
alter table public.aluno_feedback_professor
  drop constraint if exists aluno_feedback_pratica_valida;
alter table public.aluno_feedback_professor
  add  constraint aluno_feedback_pratica_valida
       check (pratica_em_casa is null or pratica_em_casa in ('sim','as_vezes','nao'));

alter table public.aluno_feedback_professor
  drop constraint if exists aluno_feedback_evolucao_valida;
alter table public.aluno_feedback_professor
  add  constraint aluno_feedback_evolucao_valida
       check (evolucao is null or evolucao in ('evoluindo','parado','regredindo'));

alter table public.aluno_feedback_professor
  drop constraint if exists aluno_feedback_animo_valido;
alter table public.aluno_feedback_professor
  add  constraint aluno_feedback_animo_valido
       check (animo is null or animo in ('animado','neutro','desanimado'));

alter table public.aluno_feedback_professor
  drop constraint if exists aluno_feedback_cor_valida;
alter table public.aluno_feedback_professor
  add  constraint aluno_feedback_cor_valida
       check (feedback in ('verde','amarelo','vermelho'));

comment on column public.aluno_feedback_professor.teve_aula_no_mes is
  'Snapshot: o professor deu aula pra esse aluno na competência? Gravado e não '
  'calculado depois porque a agenda muda — sem isso ninguém sabe se o coração '
  'veio de observação recente ou de memória.';

-- ─── As réguas de data ──────────────────────────────────────────────────────
-- Tudo que é "hoje" passa por aqui. `current_date` cru é UTC: entre 21h e
-- meia-noite BRT ele já é amanhã, e foi isso que derrubou o teste 018.
create or replace function public.fn_hoje_brt()
returns date language sql stable parallel safe as $$
  select (now() at time zone 'America/Sao_Paulo')::date
$$;

create or replace function public.fn_competencia_feedback(p_dia date default null)
returns date language sql stable parallel safe as $$
  select date_trunc('month', coalesce(p_dia, public.fn_hoje_brt()))::date
$$;

-- Janela = os ÚLTIMOS 7 DIAS do mês. Qualquer janela de 7 dias contém
-- exatamente uma segunda e uma quinta, então os disparos da 075 são
-- não-ambíguos em todo mês, inclusive fevereiro.
create or replace function public.fn_janela_feedback_aberta(p_dia date default null)
returns boolean language sql stable parallel safe as $$
  select with_dia.d >= (date_trunc('month', with_dia.d) + interval '1 month - 7 days')::date
    from (select coalesce(p_dia, public.fn_hoje_brt()) as d) as with_dia
$$;

grant execute on function public.fn_hoje_brt() to authenticated;
grant execute on function public.fn_competencia_feedback(date) to authenticated;
grant execute on function public.fn_janela_feedback_aberta(date) to authenticated;
revoke all on function public.fn_janela_feedback_aberta(date) from anon;
