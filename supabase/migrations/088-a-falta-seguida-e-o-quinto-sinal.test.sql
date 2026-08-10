-- Teste da 088. O 5º sinal entra na mesma redistribuição dos outros 4 — não é
-- atropelo. E carrega a mesma guarda do C1 (085): sem aula medida, sai da conta.
create temporary table _res(caso text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_r0 jsonb;
  v_r2 jsonb;
  v_r3 jsonb;
  v_semdado jsonb;
  v_bate boolean;
  v_cfg jsonb := '{"peso_absenteismo":40,"peso_feedback":25,"peso_pratica":20,
                   "peso_faltas_mes":15,"peso_faltas_consecutivas":20,
                   "faixa_critico":40,"faixa_saudavel":70,
                   "faltas_consecutivas_atencao":2,"faltas_consecutivas_critico":3,
                   "minimo_sinais_para_nota":2}'::jsonb;
begin
  v_r0 := public.fn_radar_nota(
    '{"absenteismo_pct":0,"aulas_medidas":10,"faltas_consecutivas":0}'::jsonb, v_cfg);
  insert into _res values ('sinais_totais e 5', (v_r0->>'sinais_totais')::int = 5,
    v_r0->>'sinais_totais');

  v_semdado := public.fn_radar_nota(
    '{"aulas_medidas":0,"faltas_consecutivas":0}'::jsonb, v_cfg);
  insert into _res values ('sem aula medida, faltas_consecutivas fica sem_dado',
    (select (e->>'sem_dado')::boolean from jsonb_array_elements(v_semdado->'decomposicao') e
      where e->>'sinal' = 'faltas_consecutivas'), v_semdado::text);

  v_r2 := public.fn_radar_nota(
    '{"absenteismo_pct":0,"aulas_medidas":10,"faltas_consecutivas":2}'::jsonb, v_cfg);
  insert into _res values ('2 faltas seguidas pontua 50 (atencao)',
    (select (e->>'score')::numeric from jsonb_array_elements(v_r2->'decomposicao') e
      where e->>'sinal' = 'faltas_consecutivas') = 50,
    (select e->>'score' from jsonb_array_elements(v_r2->'decomposicao') e
      where e->>'sinal' = 'faltas_consecutivas'));

  v_r3 := public.fn_radar_nota(
    '{"absenteismo_pct":0,"aulas_medidas":10,"faltas_consecutivas":3}'::jsonb, v_cfg);
  insert into _res values ('3 faltas seguidas pontua 0 (critico)',
    (select (e->>'score')::numeric from jsonb_array_elements(v_r3->'decomposicao') e
      where e->>'sinal' = 'faltas_consecutivas') = 0,
    (select e->>'score' from jsonb_array_elements(v_r3->'decomposicao') e
      where e->>'sinal' = 'faltas_consecutivas'));

  insert into _res values ('1 falta seguida pontua 100 (saudavel)',
    (select (e->>'score')::numeric
       from jsonb_array_elements(public.fn_radar_nota(
         '{"absenteismo_pct":0,"aulas_medidas":10,"faltas_consecutivas":1}'::jsonb, v_cfg
       )->'decomposicao') e
      where e->>'sinal' = 'faltas_consecutivas') = 100, 'ok');

  insert into _res values ('nota com 3 faltas seguidas e menor que com 0',
    (v_r3->>'nota')::numeric < (v_r0->>'nota')::numeric,
    format('0=%s 3=%s', v_r0->>'nota', v_r3->>'nota'));

  with aula2 as (
    select p.aluno_id, p.data_aula, p.horario_aula,
           bool_or(p.considera_presenca) as veio
      from public.vw_aluno_presenca_semantica_v1 p
     where p.considera_frequencia_denominador
       and p.data_aula >= date '2026-08-01'
     group by 1,2,3
  ),
  ordenada2 as (
    select aluno_id, veio,
           row_number() over (partition by aluno_id
             order by data_aula desc, horario_aula desc nulls last) as rn
      from aula2
  ),
  esperado as (
    select o.aluno_id, count(*) as n
      from ordenada2 o
     where not o.veio
       and not exists (select 1 from ordenada2 o2
                        where o2.aluno_id = o.aluno_id and o2.rn < o.rn and o2.veio)
     group by o.aluno_id
  )
  select bool_and(v.faltas_consecutivas = coalesce(e.n, 0))
    into v_bate
    from public.vw_radar_aluno_sinais v
    left join esperado e on e.aluno_id = v.aluno_id;

  insert into _res values ('a view tem faltas_consecutivas e bate com o calculo direto',
    coalesce(v_bate, false), 'ok');
end $$;

select json_build_object(
         'falhas', (select count(*) from _res where not ok),
         'detalhe', coalesce((select json_agg(json_build_object(
                                'passo', caso, 'esperado', 'ok', 'obtido', detalhe))
                                from _res where not ok), '[]'::json)
       ) as resumo;
