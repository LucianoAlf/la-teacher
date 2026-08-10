-- Teste da 085. A nota é o coração do Radar e a parte mais fácil de mentir:
-- ela precisa ABRIR (mostrar de onde veio), REDISTRIBUIR peso de sinal ausente
-- e SE CALAR quando não tem base.
create temporary table _res(caso text, ok boolean, detalhe text) on commit drop;

do $$
declare
  cfg   jsonb := jsonb_build_object(
    'peso_absenteismo', 40, 'peso_feedback', 25, 'peso_pratica', 20,
    'peso_faltas_mes', 15, 'faixa_critico', 40, 'faixa_saudavel', 70,
    'minimo_sinais_para_nota', 2);
  v     jsonb;
begin
  -- ── Todos os sinais presentes: os pesos somam 100 e nada se redistribui ──
  v := public.fn_radar_nota(jsonb_build_object(
         'absenteismo_pct', 0, 'aulas_medidas', 10, 'feedback', 'verde',
         'pratica_em_casa', 'sim', 'faltas_mes', 0, 'aulas_mes', 4), cfg);
  insert into _res values ('aluno perfeito tira 100', (v->>'nota')::numeric = 100, v->>'nota');
  insert into _res values ('e o status e saudavel', v->>'status' = 'saudavel', v->>'status');
  insert into _res values ('com 4 sinais, apurados = 4', (v->>'sinais_apurados')::int = 4,
    v->>'sinais_apurados');

  v := public.fn_radar_nota(jsonb_build_object(
         'absenteismo_pct', 100, 'aulas_medidas', 10, 'feedback', 'vermelho',
         'pratica_em_casa', 'nao', 'faltas_mes', 4, 'aulas_mes', 4), cfg);
  insert into _res values ('aluno no pior caso tira 0', (v->>'nota')::numeric = 0, v->>'nota');
  insert into _res values ('e o status e critico', v->>'status' = 'critico', v->>'status');

  -- ── A DECOMPOSICAO ABRE ─────────────────────────────────────────────────
  v := public.fn_radar_nota(jsonb_build_object(
         'absenteismo_pct', 0, 'aulas_medidas', 10, 'feedback', 'verde',
         'pratica_em_casa', 'sim', 'faltas_mes', 0, 'aulas_mes', 4), cfg);
  insert into _res values ('a decomposicao tem uma linha por sinal',
    jsonb_array_length(v->'decomposicao') = 4,
    (jsonb_array_length(v->'decomposicao'))::text);
  insert into _res values ('cada linha diz quanto CONTRIBUIU (nao so o peso)',
    not exists (select 1 from jsonb_array_elements(v->'decomposicao') d
                 where d->>'contribuiu' is null), 'ok');
  insert into _res values ('a soma das contribuicoes e a nota',
    round((select sum((d->>'contribuiu')::numeric)
             from jsonb_array_elements(v->'decomposicao') d)) = (v->>'nota')::numeric,
    v->>'nota');

  -- ── SINAL AUSENTE SAI DA CONTA E O PESO SE REDISTRIBUI ──────────────────
  -- Sem feedback e sem pratica, sobram absenteismo (40) e faltas do mes (15).
  -- Se os dois estao perfeitos, a nota tem que ser 100 — e NAO 55, que seria
  -- o resultado de contar os ausentes como zero.
  v := public.fn_radar_nota(jsonb_build_object(
         'absenteismo_pct', 0, 'aulas_medidas', 10,
         'faltas_mes', 0, 'aulas_mes', 4), cfg);
  insert into _res values ('sinal ausente NAO puxa a nota pra baixo',
    (v->>'nota')::numeric = 100, v->>'nota');
  insert into _res values ('e nao conta como neutro (que daria 77,5)',
    (v->>'nota')::numeric <> 77.5, v->>'nota');
  insert into _res values ('apurados = 2 de 4', (v->>'sinais_apurados')::int = 2,
    v->>'sinais_apurados');
  insert into _res values ('o peso efetivo do absenteismo subiu de 40',
    (select (d->>'peso_efetivo')::numeric from jsonb_array_elements(v->'decomposicao') d
      where d->>'sinal' = 'absenteismo') > 40,
    (select d->>'peso_efetivo' from jsonb_array_elements(v->'decomposicao') d
      where d->>'sinal' = 'absenteismo'));

  -- ── PISO DE COBERTURA: com 1 sinal, a nota SE CALA ──────────────────────
  v := public.fn_radar_nota(jsonb_build_object('faltas_mes', 0, 'aulas_mes', 4), cfg);
  insert into _res values ('com 1 sinal, suficiente = false',
    (v->>'suficiente')::boolean = false, v->>'suficiente');
  insert into _res values ('e a nota vem NULA (nao um numero bonito)',
    v->>'nota' is null, coalesce(v->>'nota','(nulo)'));
  insert into _res values ('mas a decomposicao continua vindo (pra tela explicar)',
    jsonb_array_length(v->'decomposicao') >= 1,
    (jsonb_array_length(v->'decomposicao'))::text);

  -- ── Sem sinal nenhum ────────────────────────────────────────────────────
  v := public.fn_radar_nota('{}'::jsonb, cfg);
  insert into _res values ('sem sinal nenhum, nota nula e apurados 0',
    v->>'nota' is null and (v->>'sinais_apurados')::int = 0, v::text);

  -- ── As faixas vem da config, nao do codigo ──────────────────────────────
  v := public.fn_radar_nota(jsonb_build_object(
         'absenteismo_pct', 0, 'aulas_medidas', 10, 'feedback', 'verde',
         'pratica_em_casa', 'sim', 'faltas_mes', 0, 'aulas_mes', 4),
       cfg || jsonb_build_object('faixa_saudavel', 101));
  insert into _res values ('subindo a faixa_saudavel, 100 deixa de ser saudavel',
    v->>'status' <> 'saudavel', v->>'status');

  -- ── E a faixa de critico tambem — nao so a de saudavel ───────────────────
  -- Os quatro sinais no meio da escala (score 50 cada) dao nota 50, que com a
  -- regua padrao (critico<40, saudavel>=70) e "atencao". Subindo faixa_critico
  -- pra 55 essa MESMA nota vira critico — se a comparacao estivesse hardcoded
  -- em 40 no codigo, subir a regua na tela nao mudaria nada.
  v := public.fn_radar_nota(jsonb_build_object(
         'absenteismo_pct', 50, 'aulas_medidas', 10, 'feedback', 'amarelo',
         'pratica_em_casa', 'as_vezes', 'faltas_mes', 2, 'aulas_mes', 4),
       cfg || jsonb_build_object('faixa_critico', 55));
  insert into _res values ('os quatro sinais no meio dao nota 50',
    (v->>'nota')::numeric = 50, v->>'nota');
  insert into _res values ('subindo a faixa_critico pra 55, a nota 50 deixa de ser atencao e vira critico',
    v->>'status' = 'critico', v->>'status');
end $$;

select json_build_object(
         'falhas', (select count(*) from _res where not ok),
         'detalhe', coalesce((select json_agg(json_build_object(
                                'passo', caso, 'esperado', 'ok', 'obtido', detalhe))
                                from _res where not ok), '[]'::json)
       ) as resumo;
