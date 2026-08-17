-- Parte executada remotamente (rollback contra producao): contrato de catalogo
-- (existencia, portas fechadas, ZERO identificador financeiro) + o caso
-- canonico do Valdo, que roda contra o dado real porque a RPC e read-only.
-- O bloco Docker no fim fica comentado e o runner de mutantes o extrai.

-- PREAMBULO-INICIO
-- (o runner de mutantes extrai este trecho para montar o ensaio Docker sem
-- arrastar junto as asercoes que dependem do dado de PRODUCAO)
create temporary table pg_temp._res (caso text, ok boolean, detalhe text) on commit drop;

create or replace function pg_temp.checar(p_caso text, p_ok boolean, p_detalhe text)
returns void language plpgsql as $function$
begin
  insert into pg_temp._res(caso, ok, detalhe) values (p_caso, coalesce(p_ok,false), p_detalhe);
end
$function$;
-- PREAMBULO-FIM

do $function$
declare
  v_fn oid := to_regprocedure('public.fabio_professor_resumo_aulas(integer,date,date,text)');
  v_def text;
  v_res jsonb;
  v_cru integer;
begin
  perform pg_temp.checar('a RPC existe', v_fn is not null, coalesce(v_fn::text,'<ausente>'));
  if v_fn is null then return; end if;

  perform pg_temp.checar('service_role executa; anon/authenticated nao',
    has_function_privilege('service_role', v_fn, 'EXECUTE')
    and not has_function_privilege('anon', v_fn, 'EXECUTE')
    and not has_function_privilege('authenticated', v_fn, 'EXECUTE'),
    'grants');

  -- Fronteira do financeiro: porta que nao existe, verificada no corpo.
  v_def := pg_get_functiondef(v_fn);
  perform pg_temp.checar('nenhum identificador financeiro no corpo',
    v_def !~* '(valor_|mensalidade|pagamento|repasse|contrato|desconto|bolsa|fatura|folha)',
    'corpo da funcao');

  -- Caso canonico do Valdo (professor 36, 11-15/08). Semana fechada: se este
  -- numero mudar, conferir PRIMEIRO se a agenda mudou, nao o codigo.
  v_res := public.fabio_professor_resumo_aulas(36, date '2026-08-11', date '2026-08-15', null);
  perform pg_temp.checar('Valdo 11-15/08 = 36 aulas',
    (v_res->>'total_aulas')::int = 36, coalesce(v_res->>'total_aulas','<nulo>'));

  -- A armadilha: linha crua devolve 74. A RPC NUNCA pode devolver isso.
  select count(*) into v_cru from public.aulas_emusys ae
   where ae.professor_id=36 and ae.data_aula between date '2026-08-11' and date '2026-08-15'
     and coalesce(ae.cancelada,false)=false;
  perform pg_temp.checar('a linha crua realmente dobra (armadilha viva)', v_cru = 74, v_cru::text);
  perform pg_temp.checar('a RPC nao devolve a contagem crua',
    (v_res->>'total_aulas')::int <> v_cru, format('rpc=%s cru=%s', v_res->>'total_aulas', v_cru));

  perform pg_temp.checar('por_unidade: Campo Grande 25',
    (select (x->>'aulas')::int from jsonb_array_elements(v_res->'por_unidade') x
      where x->>'unidade' = 'Campo Grande') = 25, (v_res->'por_unidade')::text);
  perform pg_temp.checar('por_unidade: Recreio 11',
    (select (x->>'aulas')::int from jsonb_array_elements(v_res->'por_unidade') x
      where x->>'unidade' = 'Recreio') = 11, (v_res->'por_unidade')::text);
  perform pg_temp.checar('por_dia soma o total',
    (select sum((x->>'aulas')::int) from jsonb_array_elements(v_res->'por_dia') x) = 36,
    (v_res->'por_dia')::text);
  -- registradas exato NAO e asserido: muda quando o professor registra. O que
  -- nao pode mudar e a soma fechar com o total.
  perform pg_temp.checar('registradas + sem_registro = total',
    (v_res->>'registradas')::int + (v_res->>'sem_registro')::int = 36,
    format('%s + %s', v_res->>'registradas', v_res->>'sem_registro'));

  -- Recorte por unidade
  v_res := public.fabio_professor_resumo_aulas(36, date '2026-08-11', date '2026-08-15', 'Recreio');
  perform pg_temp.checar('recorte Recreio = 11', (v_res->>'total_aulas')::int = 11,
    coalesce(v_res->>'total_aulas','<nulo>'));

  -- Isolamento por professor: o 35 tem outra agenda na mesma semana.
  perform pg_temp.checar('outro professor tem outro total',
    (public.fabio_professor_resumo_aulas(35, date '2026-08-11', date '2026-08-15', null)->>'total_aulas')::int <> 36,
    'isolamento');

  -- Guardas de parametro
  perform pg_temp.checar('periodo invertido recusa',
    (public.fabio_professor_resumo_aulas(36, date '2026-08-15', date '2026-08-11', null)->>'motivo') = 'periodo_invertido', 'invertido');
  perform pg_temp.checar('janela > 90 dias recusa',
    (public.fabio_professor_resumo_aulas(36, date '2026-01-01', date '2026-08-15', null)->>'motivo') = 'janela_maior_que_90_dias', 'janela');
  perform pg_temp.checar('parametro nulo recusa',
    (public.fabio_professor_resumo_aulas(null, date '2026-08-11', date '2026-08-15', null)->>'motivo') = 'parametros_obrigatorios', 'nulo');
end
$function$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._res where not ok),
  'detalhe', coalesce((select json_agg(json_build_object('passo', caso, 'esperado','true','obtido', detalhe) order by caso)
                         from pg_temp._res where not ok), '[]'::json)
) as resumo;

/* RESUMO-AULAS-DOCKER-DML-TESTS-INICIO
-- Roda so no PostgreSQL efemero do mutante. O bootstrap (no .mjs) ja criou
-- unidades, aulas_emusys com DUAS linhas por aula (a armadilha), o
-- fn_aula_operacional_id fake que colapsa o par, e fabio_registros_aula —
-- inclusive um tronco apontando pro id PAR (linha de evento), que e o caso que
-- o dado de producao nao alcanca.
do $docker$
declare
  v_res jsonb;
  v_def text;
begin
  -- A fronteira do financeiro tambem e verificada aqui: e este passo que mata o
  -- mutante que injeta coluna financeira no retorno.
  v_def := pg_get_functiondef(to_regprocedure('public.fabio_professor_resumo_aulas(integer,date,date,text)'));
  perform pg_temp.checar('docker: nenhum identificador financeiro no corpo',
    v_def !~* '(valor_|mensalidade|pagamento|repasse|contrato|desconto|bolsa|fatura|folha)', 'corpo');

  v_res := public.fabio_professor_resumo_aulas(36, date '2026-08-11', date '2026-08-15', null);
  -- 4 aulas operacionais, 8 linhas cruas (+2 canceladas)
  perform pg_temp.checar('docker: total colapsa 8 linhas em 4 aulas',
    (v_res->>'total_aulas')::int = 4, coalesce(v_res->>'total_aulas','<nulo>'));
  perform pg_temp.checar('docker: cancelada fora da contagem',
    (v_res->>'total_aulas')::int <> 5, coalesce(v_res->>'total_aulas','<nulo>'));
  perform pg_temp.checar('docker: por_unidade CG 3 / Recreio 1',
    (select (x->>'aulas')::int from jsonb_array_elements(v_res->'por_unidade') x where x->>'unidade'='Campo Grande') = 3
    and (select (x->>'aulas')::int from jsonb_array_elements(v_res->'por_unidade') x where x->>'unidade'='Recreio') = 1,
    (v_res->'por_unidade')::text);
  -- 3 registradas: a aula 7 so aparece porque o registro (que aponta pro id
  -- par 8) tambem passa pelo fn_aula_operacional_id. Com o join ingenuo daria 2.
  perform pg_temp.checar('docker: registradas 3 / sem_registro 1',
    (v_res->>'registradas')::int = 3 and (v_res->>'sem_registro')::int = 1,
    format('%s/%s', v_res->>'registradas', v_res->>'sem_registro'));
  perform pg_temp.checar('docker: rascunho nao conta como registrada',
    (v_res->>'registradas')::int <> 4, coalesce(v_res->>'registradas','<nulo>'));
  perform pg_temp.checar('docker: recorte por unidade',
    (public.fabio_professor_resumo_aulas(36, date '2026-08-11', date '2026-08-15', 'Recreio')->>'total_aulas')::int = 1,
    'recorte');
  perform pg_temp.checar('docker: outro professor nao vaza',
    (public.fabio_professor_resumo_aulas(99, date '2026-08-11', date '2026-08-15', null)->>'total_aulas')::int = 0,
    'isolamento por professor');
end
$docker$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._res where not ok),
  'detalhe', coalesce((select json_agg(json_build_object('passo', caso, 'esperado','true','obtido', detalhe) order by caso)
                         from pg_temp._res where not ok), '[]'::json)
) as resumo;
RESUMO-AULAS-DOCKER-DML-TESTS-FIM */
