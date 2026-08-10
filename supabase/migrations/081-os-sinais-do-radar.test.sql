-- Teste da 081. Roda dentro de BEGIN/ROLLBACK do rodar-teste-sql.mjs.
--
-- A view é a fundação do Radar: se ela contar linha em vez de aula, TODO
-- número acima dela dobra. Os passos abaixo guardam as quatro decisões que
-- custaram medição: grão, denominador honesto, janela virada e coorte.
create temporary table _res(caso text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_pares_crus int;
  v_aulas      int;
  v_fora       int;
  v_antes      int;
  v_coorte     int;
  v_linhas     int;
begin
  -- ── Grão ────────────────────────────────────────────────────────────────
  -- A view semântica tem ~1,69 linha por aula. Se a nossa view herdar isso,
  -- o absenteísmo de todo mundo dobra.
  select count(*) into v_pares_crus
    from public.vw_aluno_presenca_semantica_v1
   where considera_frequencia_denominador and data_aula >= '2026-08-01';
  select count(*) into v_aulas from (
    select aluno_id, data_aula, horario_aula
      from public.vw_aluno_presenca_semantica_v1
     where considera_frequencia_denominador and data_aula >= '2026-08-01'
     group by 1,2,3) x;

  insert into _res values ('a base tem duplicata (senao o teste nao vale)',
    v_pares_crus > v_aulas, format('%s linhas, %s aulas', v_pares_crus, v_aulas));

  insert into _res values ('aulas_medidas conta AULA, nao linha',
    (select coalesce(sum(aulas_medidas),0) from public.vw_radar_aluno_sinais) <= v_aulas,
    format('soma=%s aulas=%s', (select coalesce(sum(aulas_medidas),0) from public.vw_radar_aluno_sinais), v_aulas));

  -- ── Denominador honesto ─────────────────────────────────────────────────
  -- Falta justificada, provavel e indeterminada NAO entram. Quem falta e
  -- repoe nao e quem falta e some.
  select count(*) into v_fora
    from public.vw_aluno_presenca_semantica_v1
   where not considera_frequencia_denominador and data_aula >= '2026-08-01';
  insert into _res values ('existe aula fora do denominador (senao o passo seguinte nao vale)',
    v_fora > 0, format('%s linhas fora', v_fora));

  insert into _res values ('nenhum aluno tem mais aula medida do que aula confirmada',
    not exists (
      select 1 from public.vw_radar_aluno_sinais r
       where r.aulas_medidas > (
         select count(*) from (
           select data_aula, horario_aula
             from public.vw_aluno_presenca_semantica_v1 v
            where v.aluno_id = r.aluno_id and v.considera_frequencia_denominador
              and v.data_aula >= '2026-08-01'
            group by 1,2) y)),
    'ok');

  -- O passo acima só pega o filtro se, HOJE, existir aluno da coorte com aula
  -- fora do denominador que não tem par confirmado no mesmo horário — e medido
  -- em 10/08 isso é zero (187 de 187 slots da coorte já têm confirmado junto).
  -- Dado bom demais não é prova: a mesma lacuna do `fn_hoje_brt` (018/073), onde
  -- só o CORPO da rotina prova a regra em qualquer hora do dia. Aqui o corpo é
  -- a definição da view — se o filtro sumir, o identificador some do texto.
  insert into _res values (
    'a view cita considera_frequencia_denominador no filtro da aula [ancora dado-independente]',
    pg_get_viewdef('public.vw_radar_aluno_sinais'::regclass) ilike '%considera_frequencia_denominador%',
    'ok');

  -- ── A janela virada ─────────────────────────────────────────────────────
  select count(*) into v_antes
    from public.vw_aluno_presenca_semantica_v1
   where data_aula < '2026-08-01' and considera_frequencia_denominador;
  insert into _res values ('existe aula antes de 01/08 (senao o passo seguinte nao vale)',
    v_antes > 0, format('%s linhas antes', v_antes));

  -- Se a janela vazasse pra julho, algum aluno teria mais aula medida do que
  -- existe em agosto. Este passo mede exatamente isso.
  insert into _res values ('a janela nao busca antes de 01/08',
    (select coalesce(max(aulas_medidas),0) from public.vw_radar_aluno_sinais)
      <= (select coalesce(max(n),0) from (
            select count(*) n from public.vw_aluno_presenca_semantica_v1
             where considera_frequencia_denominador and data_aula >= '2026-08-01'
             group by aluno_id) z),
    'ok');

  -- ── Coorte ──────────────────────────────────────────────────────────────
  select count(*) into v_coorte
    from public.professores where coalesce(ativo,true) and usuario_id is not null;
  insert into _res values ('a coorte e menor que a escola (senao o teste nao vale)',
    v_coorte < (select count(*) from public.professores where coalesce(ativo,true)),
    format('%s de %s professores', v_coorte,
           (select count(*) from public.professores where coalesce(ativo,true))));

  insert into _res values ('so entra aluno de professor que ja entrou no app',
    not exists (
      select 1 from public.vw_radar_aluno_sinais r
       where r.professor_id not in (
         select id from public.professores
          where coalesce(ativo,true) and usuario_id is not null)),
    'ok');

  -- ── O absenteismo e coerente com suas proprias colunas ──────────────────
  insert into _res values ('absenteismo bate com faltas/aulas da propria linha',
    not exists (
      select 1 from public.vw_radar_aluno_sinais
       where aulas_medidas > 0
         and absenteismo_pct is distinct from round(100.0*faltas_janela/aulas_medidas, 1)),
    'ok');

  insert into _res values ('sem aula medida, o absenteismo e NULO (nao zero)',
    not exists (select 1 from public.vw_radar_aluno_sinais
                 where aulas_medidas = 0 and absenteismo_pct is not null),
    'ok');

  select count(*) into v_linhas from public.vw_radar_aluno_sinais;
  insert into _res values ('a view devolve alguma coisa', v_linhas > 0, format('%s linhas', v_linhas));

  -- ── Um aluno, uma linha ─────────────────────────────────────────────────
  insert into _res values ('um aluno aparece uma vez so',
    not exists (select 1 from public.vw_radar_aluno_sinais
                 group by aluno_id having count(*) > 1), 'ok');
end $$;

select json_build_object(
         'falhas', (select count(*) from _res where not ok),
         'detalhe', coalesce((select json_agg(json_build_object(
                                'passo', caso, 'esperado', 'ok', 'obtido', detalhe))
                                from _res where not ok), '[]'::json)
       ) as resumo;
