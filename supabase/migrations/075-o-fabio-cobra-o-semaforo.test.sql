-- 075 (teste) — o Fábio cobra o semáforo
--
-- O passo que dá nome à migration é a ESCADA: lembrete pra todo mundo, reforço
-- só pra quem não fechou, coordenação no dia 1º olhando o mês que acabou.
-- Fora desses três dias, nada é enfileirado.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

-- ─── Quem já fechou o mês NÃO recebe reforço de novo ────────────────────────
-- Nenhum passo abaixo prova isto sozinho: "fase='reforco' no dia certo" é
-- verdade tanto fazendo reforço pra todo mundo quanto só pra quem falta.
-- Aqui o professor piloto (Matheus/25 — o único que o fingerprint do runner
-- observa) fecha o mês INTEIRO (as três perguntas dos 23 alunos da carteira,
-- competência de agosto/2026) ANTES de qualquer chamada da função — senão uma
-- chamada anterior já teria gravado a notificação dele completo, e o teste
-- estaria comparando contra um registro que nasceu quando ele ainda estava
-- incompleto. `distinct on` porque a carteira tem mais de uma linha por aluno
-- (curso/matrícula) — sem isso o INSERT tenta a mesma chave duas vezes e o
-- ON CONFLICT DO UPDATE explode com "command cannot affect row a second time".
do $$
declare
  v_prof int := 25;
begin
  insert into public.aluno_feedback_professor
    (aluno_id, professor_id, unidade_id, competencia, feedback,
     pratica_em_casa, evolucao, animo, origem)
  select distinct on (v.aluno_id)
         v.aluno_id, v_prof, v.unidade_id, date '2026-08-01',
         'verde', 'sim', 'evoluindo', 'animado', 'teste_mutante_075'
    from public.vw_jornada_professor_atual v
    join public.alunos a on a.id = v.aluno_id and a.arquivado_em is null
   where v.professor_id = v_prof
   order by v.aluno_id
  on conflict (aluno_id, professor_id, competencia) do update
     set feedback         = excluded.feedback,
         pratica_em_casa  = excluded.pratica_em_casa,
         evolucao         = excluded.evolucao,
         animo            = excluded.animo;

  perform public.fn_enfileirar_cobranca_feedback(date '2026-08-28');  -- reforco
end $$;

insert into _res values ('professor 100% completo NAO recebe reforco', 'sim',
  case when exists (select 1 from public.fabio_notificacoes
                      where tipo = 'feedback_reforco' and professor_id = 25
                        and dia_referencia = date '2026-08-28')
       then 'NAO — recebeu mesmo completo' else 'sim' end);

-- Agosto/2026 termina em 31, então a janela é 25 a 31: lembrete no 25,
-- reforço no 28. Fevereiro/2026 termina em 28: lembrete no 22, reforço no 25.
insert into _res values ('primeiro dia da janela dispara lembrete', 'lembrete',
  public.fn_enfileirar_cobranca_feedback(date '2026-08-25')->>'fase');
insert into _res values ('tres dias depois dispara reforco', 'reforco',
  public.fn_enfileirar_cobranca_feedback(date '2026-08-28')->>'fase');
insert into _res values ('dia do meio da janela NAO dispara', 'nenhuma',
  public.fn_enfileirar_cobranca_feedback(date '2026-08-26')->>'fase');
insert into _res values ('ultimo dia do mes NAO dispara', 'nenhuma',
  public.fn_enfileirar_cobranca_feedback(date '2026-08-31')->>'fase');
insert into _res values ('dia FORA da janela NAO dispara', 'nenhuma',
  public.fn_enfileirar_cobranca_feedback(date '2026-08-17')->>'fase');
insert into _res values ('dia 1 dispara coordenacao', 'coordenacao',
  public.fn_enfileirar_cobranca_feedback(date '2026-09-01')->>'fase');
insert into _res values ('dia 1 olha a competencia que ACABOU', '2026-08-01',
  public.fn_enfileirar_cobranca_feedback(date '2026-09-01')->>'competencia');

-- ─── O DEFEITO QUE MOTIVOU A ÂNCORA: o lembrete vem ANTES do reforço ────────
-- Com a régua velha (segunda/quinta da janela), em agosto o reforço caía no dia
-- 27 e o lembrete no 31 — o professor era cobrado antes de ser avisado. Este
-- passo varre 2026 inteiro e exige a ordem em TODO mês.
insert into _res
select 'em todo mes de 2026 o lembrete vem antes do reforco', 'sim',
  case when count(*) filter (where dia_lembrete >= dia_reforco) = 0 then 'sim'
       else 'NAO — ' || count(*) filter (where dia_lembrete >= dia_reforco) || ' mes(es)' end
from (
  select m,
         min(d) filter (where public.fn_enfileirar_cobranca_feedback(d::date)->>'fase' = 'lembrete') as dia_lembrete,
         min(d) filter (where public.fn_enfileirar_cobranca_feedback(d::date)->>'fase' = 'reforco')  as dia_reforco
    from generate_series(date '2026-01-01', date '2026-12-01', interval '1 month') m,
         lateral generate_series(m::date, (m + interval '1 month - 1 day')::date, interval '1 day') d
   group by m
) por_mes;

insert into _res
select 'todo mes de 2026 tem exatamente 1 lembrete e 1 reforco', 'sim',
  case when count(*) filter (where n_lembrete <> 1 or n_reforco <> 1) = 0 then 'sim'
       else 'NAO — ' || count(*) filter (where n_lembrete <> 1 or n_reforco <> 1) || ' mes(es)' end
from (
  select m,
         count(*) filter (where public.fn_enfileirar_cobranca_feedback(d::date)->>'fase' = 'lembrete') as n_lembrete,
         count(*) filter (where public.fn_enfileirar_cobranca_feedback(d::date)->>'fase' = 'reforco')  as n_reforco
    from generate_series(date '2026-01-01', date '2026-12-01', interval '1 month') m,
         lateral generate_series(m::date, (m + interval '1 month - 1 day')::date, interval '1 day') d
   group by m
) por_mes;

-- ─── O lembrete alcança gente ───────────────────────────────────────────────
insert into _res
select 'ancora: ha professor com carteira', 'sim',
  case when count(*) > 0 then 'sim' else 'NAO' end
from (select v.professor_id from public.vw_jornada_professor_atual v
       group by v.professor_id limit 1) x;

insert into _res values ('lembrete enfileira pelo menos um professor', 'sim',
  case when (public.fn_enfileirar_cobranca_feedback(date '2026-08-25')->>'enfileirados')::int > 0
            or exists (select 1 from public.fabio_notificacoes
                        where tipo = 'feedback_lembrete' and dia_referencia = date '2026-08-25')
       then 'sim' else 'NAO' end);

-- ─── Idempotência: rodar duas vezes não duplica ─────────────────────────────
do $$
declare v_antes int; v_depois int;
begin
  select count(*) into v_antes from public.fabio_notificacoes
   where tipo = 'feedback_lembrete' and dia_referencia = date '2026-08-25';
  perform public.fn_enfileirar_cobranca_feedback(date '2026-08-25');
  select count(*) into v_depois from public.fabio_notificacoes
   where tipo = 'feedback_lembrete' and dia_referencia = date '2026-08-25';
  insert into _res values ('rodar de novo no mesmo dia NAO duplica',
    v_antes::text, v_depois::text);
end $$;

-- ─── A porta ────────────────────────────────────────────────────────────────
insert into _res
select 'anon NAO executa a cobranca', 'sim',
  case when has_function_privilege('anon',
        'public.fn_enfileirar_cobranca_feedback(date)', 'execute')
       then 'NAO — anon executa' else 'sim' end;

insert into _res
select 'authenticated NAO executa a cobranca', 'sim',
  case when has_function_privilege('authenticated',
        'public.fn_enfileirar_cobranca_feedback(date)', 'execute')
       then 'NAO — authenticated executa' else 'sim' end;

-- Alias `resumo` com `falhas` NUMÉRICO: é o contrato que
-- `scripts/rodar-teste-sql.mjs` exige (`typeof resumo.falhas !== 'number'`) e
-- que os 54 `.test.sql` do repo usam. Um alias diferente faz o harness dizer
-- "não veio resumo estruturado" e reprovar sem explicar.
select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
