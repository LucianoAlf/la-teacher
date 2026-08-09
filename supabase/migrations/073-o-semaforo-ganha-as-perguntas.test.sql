-- 073 (teste) — o semáforo ganha as perguntas
--
-- O passo que dá nome à migration é o par "check recusa valor inválido" +
-- "janela abre exatamente nos últimos 7 dias". A âncora do fuso exige que a
-- competência calculada às 22h BRT ainda seja o mês corrente.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

-- ─── Os checks recusam lixo ─────────────────────────────────────────────────
do $$
declare v_erro text := 'nao levantou'; v_aluno int; v_unid uuid; v_prof int;
begin
  select v.aluno_id, v.unidade_id, v.professor_id
    into v_aluno, v_unid, v_prof
    from public.vw_jornada_professor_atual v limit 1;

  insert into _res values ('ancora: ha aluno na jornada pra testar o check',
    'sim', case when v_aluno is null then 'NAO' else 'sim' end);

  begin
    insert into public.aluno_feedback_professor
      (aluno_id, professor_id, unidade_id, competencia, feedback, pratica_em_casa)
    values (v_aluno, v_prof, v_unid, public.fn_competencia_feedback(), 'verde', 'talvez');
  exception when others then v_erro := sqlerrm; end;
  insert into _res values ('check recusa pratica_em_casa invalida', 'sim',
    case when v_erro like '%aluno_feedback_pratica_valida%' then 'sim' else 'NAO — ' || v_erro end);
end $$;

do $$
declare v_erro text := 'nao levantou'; v_aluno int; v_unid uuid; v_prof int;
begin
  select v.aluno_id, v.unidade_id, v.professor_id into v_aluno, v_unid, v_prof
    from public.vw_jornada_professor_atual v limit 1;
  begin
    insert into public.aluno_feedback_professor
      (aluno_id, professor_id, unidade_id, competencia, feedback)
    values (v_aluno, v_prof, v_unid, public.fn_competencia_feedback(), 'roxo');
  exception when others then v_erro := sqlerrm; end;
  insert into _res values ('check recusa cor invalida', 'sim',
    case when v_erro like '%aluno_feedback_cor_valida%' then 'sim' else 'NAO — ' || v_erro end);
end $$;

-- ─── A janela abre nos últimos 7 dias e não antes ───────────────────────────
insert into _res values ('janela FECHADA no dia 24 de agosto', 'false',
  public.fn_janela_feedback_aberta(date '2026-08-24')::text);
insert into _res values ('janela ABERTA no dia 25 de agosto (31-7+1)', 'true',
  public.fn_janela_feedback_aberta(date '2026-08-25')::text);
insert into _res values ('janela ABERTA no ultimo dia do mes', 'true',
  public.fn_janela_feedback_aberta(date '2026-08-31')::text);
insert into _res values ('janela FECHADA no dia 1', 'false',
  public.fn_janela_feedback_aberta(date '2026-09-01')::text);
-- Fevereiro: a régua é relativa ao fim do mês, não a um dia fixo.
insert into _res values ('fevereiro: janela FECHADA em 21/02', 'false',
  public.fn_janela_feedback_aberta(date '2026-02-21')::text);
insert into _res values ('fevereiro: janela ABERTA em 22/02', 'true',
  public.fn_janela_feedback_aberta(date '2026-02-22')::text);

-- ─── Toda janela de 7 dias tem uma segunda e uma quinta ─────────────────────
insert into _res
select 'todo mes de 2026 tem 1 segunda e 1 quinta na janela', 'sim',
  case when count(*) filter (where segs <> 1 or quis <> 1) = 0 then 'sim'
       else 'NAO — ' || count(*) filter (where segs <> 1 or quis <> 1) || ' mes(es)' end
from (
  select m,
         count(*) filter (where extract(isodow from d) = 1) as segs,
         count(*) filter (where extract(isodow from d) = 4) as quis
    from generate_series(date '2026-01-01', date '2026-12-01', interval '1 month') m,
         lateral generate_series(m::date, (m + interval '1 month - 1 day')::date, interval '1 day') d
   where public.fn_janela_feedback_aberta(d::date)
   group by m
) por_mes;

-- ─── O fuso: às 22h BRT a competência ainda é o mês corrente ────────────────
-- Sem isso, no dia 31 às 22h a competência viraria o mês seguinte e o professor
-- perderia o trabalho do mês inteiro.
insert into _res values ('competencia de 31/08 as 22h BRT ainda e agosto', '2026-08-01',
  public.fn_competencia_feedback(date '2026-08-31')::text);
insert into _res values ('fn_hoje_brt e a data BRT, nao a UTC', 'sim',
  case when public.fn_hoje_brt() = (now() at time zone 'America/Sao_Paulo')::date
       then 'sim' else 'NAO' end);

-- O passo acima só falseia dentro da janela em que o dia BRT diverge do dia
-- UTC (por volta de 21h à meia-noite BRT) — é a mesma armadilha que deixou o
-- teste 018 vermelho só entre 21h e meia-noite. Rodado fora dela, um
-- `fn_hoje_brt` reescrito para `current_date` cru devolve o MESMO valor por
-- coincidência de horário, e o passo acima passa batido. A prova que vale a
-- qualquer hora do dia é o corpo da função — tem que citar 'America/Sao_Paulo'
-- e não pode conter `current_date` cru (mesma técnica de `pg_get_functiondef`
-- que auditou produção vs. repo no incidente da 018).
insert into _res values (
  'fn_hoje_brt cita America/Sao_Paulo e nao usa current_date cru [ancora horario-independente]',
  'sim',
  case when pg_get_functiondef('public.fn_hoje_brt()'::regprocedure) ilike '%America/Sao_Paulo%'
   and pg_get_functiondef('public.fn_hoje_brt()'::regprocedure) not ilike '%current_date%'
       then 'sim' else 'NAO' end);

-- ─── Veredito ───────────────────────────────────────────────────────────────
-- Alias `resumo` com `falhas` numérico: é o contrato que
-- `scripts/rodar-teste-sql.mjs` exige (`typeof resumo.falhas !== 'number'`), o
-- mesmo usado em todo `.test.sql` do repo — não o alias `resultado` com
-- `falhas` como array que o brief desta task trazia.
select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
