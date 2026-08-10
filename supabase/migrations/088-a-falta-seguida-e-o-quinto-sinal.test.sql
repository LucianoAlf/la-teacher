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

  -- coalesce(...,false) nas quatro checagens abaixo (achado da revisão,
  -- 10/08): a subquery escalar devolve SQL NULL se o nome do sinal não bater
  -- (typo, sinal renomeado) — e `not ok` de um `ok` NULL é NULL, que
  -- `count(*) where not ok` não conta como falha. A linha 84 (mais abaixo, "a
  -- view tem faltas_consecutivas...") já fazia isso certo; faltava replicar
  -- aqui.
  v_semdado := public.fn_radar_nota(
    '{"aulas_medidas":0,"faltas_consecutivas":0}'::jsonb, v_cfg);
  insert into _res values ('sem aula medida, faltas_consecutivas fica sem_dado',
    coalesce((select (e->>'sem_dado')::boolean from jsonb_array_elements(v_semdado->'decomposicao') e
      where e->>'sinal' = 'faltas_consecutivas'), false), v_semdado::text);

  v_r2 := public.fn_radar_nota(
    '{"absenteismo_pct":0,"aulas_medidas":10,"faltas_consecutivas":2}'::jsonb, v_cfg);
  insert into _res values ('2 faltas seguidas pontua 50 (atencao)',
    coalesce((select (e->>'score')::numeric from jsonb_array_elements(v_r2->'decomposicao') e
      where e->>'sinal' = 'faltas_consecutivas') = 50, false),
    (select e->>'score' from jsonb_array_elements(v_r2->'decomposicao') e
      where e->>'sinal' = 'faltas_consecutivas'));

  v_r3 := public.fn_radar_nota(
    '{"absenteismo_pct":0,"aulas_medidas":10,"faltas_consecutivas":3}'::jsonb, v_cfg);
  insert into _res values ('3 faltas seguidas pontua 0 (critico)',
    coalesce((select (e->>'score')::numeric from jsonb_array_elements(v_r3->'decomposicao') e
      where e->>'sinal' = 'faltas_consecutivas') = 0, false),
    (select e->>'score' from jsonb_array_elements(v_r3->'decomposicao') e
      where e->>'sinal' = 'faltas_consecutivas'));

  insert into _res values ('1 falta seguida pontua 100 (saudavel)',
    coalesce((select (e->>'score')::numeric
       from jsonb_array_elements(public.fn_radar_nota(
         '{"absenteismo_pct":0,"aulas_medidas":10,"faltas_consecutivas":1}'::jsonb, v_cfg
       )->'decomposicao') e
      where e->>'sinal' = 'faltas_consecutivas') = 100, false), 'ok');

  insert into _res values ('nota com 3 faltas seguidas e menor que com 0',
    (v_r3->>'nota')::numeric < (v_r0->>'nota')::numeric,
    format('0=%s 3=%s', v_r0->>'nota', v_r3->>'nota'));

  -- ── I1 (revisão, 10/08): a CHAVE ausente tem que sair da conta, não só ────
  -- aulas_medidas=0. A guarda antiga só checava aulas_medidas>0 — sem a
  -- própria chave faltas_consecutivas no jsonb, (null)::int vira null, as
  -- duas comparações >= dão null (nunca true), cai no ELSE 100: "saudável"
  -- fantasma pra um sinal nunca medido. Mesmo defeito que já foi Crítico na
  -- 085 (dado ausente virando nota boa em vez de SEM_DADO).
  insert into _res values (
    'faltas_consecutivas ausente do jsonb (nao so aulas_medidas=0) fica sem_dado',
    coalesce((select (e->>'sem_dado')::boolean
       from jsonb_array_elements(public.fn_radar_nota(
         '{"absenteismo_pct":0,"aulas_medidas":10}'::jsonb, v_cfg
       )->'decomposicao') e
      where e->>'sinal' = 'faltas_consecutivas'), false),
    (select e::text
       from jsonb_array_elements(public.fn_radar_nota(
         '{"absenteismo_pct":0,"aulas_medidas":10}'::jsonb, v_cfg
       )->'decomposicao') e
      where e->>'sinal' = 'faltas_consecutivas'));

  -- ── I2 (revisão, 10/08): os limiares vêm da CONFIG, não do fallback ───────
  -- hardcoded. O teste até aqui só usa atencao=2/critico=3 — os MESMOS
  -- valores do coalesce(...,2)/coalesce(...,3) na função — então trocar os
  -- dois reads de config por literais passaria batido. Subindo os dois
  -- limiares, 3 faltas seguidas (que hoje pontua 0) tem que virar 100.
  insert into _res values (
    '3 faltas seguidas com limiares subidos (atencao:4, critico:5) pontua 100, nao 0',
    coalesce((select (e->>'score')::numeric
       from jsonb_array_elements(public.fn_radar_nota(
         '{"absenteismo_pct":0,"aulas_medidas":10,"faltas_consecutivas":3}'::jsonb,
         v_cfg || '{"faltas_consecutivas_atencao":4,"faltas_consecutivas_critico":5}'::jsonb
       )->'decomposicao') e
      where e->>'sinal' = 'faltas_consecutivas') = 100, false),
    (select e->>'score'
       from jsonb_array_elements(public.fn_radar_nota(
         '{"absenteismo_pct":0,"aulas_medidas":10,"faltas_consecutivas":3}'::jsonb,
         v_cfg || '{"faltas_consecutivas_atencao":4,"faltas_consecutivas_critico":5}'::jsonb
       )->'decomposicao') e
      where e->>'sinal' = 'faltas_consecutivas'));

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
