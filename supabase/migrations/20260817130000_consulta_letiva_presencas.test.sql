-- Parte executada remotamente (rollback contra producao): contrato de catalogo
-- (existencia, portas fechadas, ZERO financeiro, ZERO proveniencia) + o caso
-- canonico do Rodrigo, que roda contra o dado real porque a RPC e read-only.
-- O bloco Docker no fim fica comentado e o runner de mutantes o extrai.

-- PREAMBULO-INICIO
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
  v_fn oid := to_regprocedure('public.fabio_professor_presencas_periodo(integer,date,date)');
  v_def text;
  v_res jsonb;
  v_linhas integer;
begin
  perform pg_temp.checar('a RPC existe', v_fn is not null, coalesce(v_fn::text,'<ausente>'));
  if v_fn is null then return; end if;

  perform pg_temp.checar('service_role executa; anon/authenticated nao',
    has_function_privilege('service_role', v_fn, 'EXECUTE')
    and not has_function_privilege('anon', v_fn, 'EXECUTE')
    and not has_function_privilege('authenticated', v_fn, 'EXECUTE'), 'grants');

  v_def := pg_get_functiondef(v_fn);
  perform pg_temp.checar('nenhum identificador financeiro no corpo',
    v_def !~* '(valor_|mensalidade|pagamento|repasse|contrato|desconto|bolsa|fatura|folha)', 'corpo');

  -- O balde provavel NAO pode nascer de proveniencia: no dia em que a secretaria
  -- vereditar um caso do Emusys, a linha continua com proveniencia 'emusys' e
  -- voltaria a ser contada como provavel depois de virar falta confirmada.
  perform pg_temp.checar('nao classifica por proveniencia',
    v_def !~* 'proveniencia', 'corpo');

  -- ── Caso canonico dos baldes: professor 35 (Rodrigo), 11-15/08 ────────────
  -- ATENCAO: 'falta_provavel' encolhe quando a secretaria vereditar esses casos.
  -- Se esta asercao quebrar, conferir PRIMEIRO se o veredito chegou:
  --   select situacao_chamada, count(*) from vw_aluno_presenca_semantica_v1
  --    where professor_id=35 and data_aula between '2026-08-11' and '2026-08-15'
  --    group by 1;
  v_res := public.fabio_professor_presencas_periodo(35, date '2026-08-11', date '2026-08-15');
  perform pg_temp.checar('Rodrigo: presentes 40', (v_res->>'presentes')::int = 40, coalesce(v_res->>'presentes','<nulo>'));
  perform pg_temp.checar('Rodrigo: faltas 7', jsonb_array_length(v_res->'faltas') = 7, (v_res->'faltas')::text);
  perform pg_temp.checar('Rodrigo: falta_provavel 6', jsonb_array_length(v_res->'falta_provavel') = 6, (v_res->'falta_provavel')::text);
  perform pg_temp.checar('Rodrigo: nao_aplicavel 7', jsonb_array_length(v_res->'nao_aplicavel') = 7, (v_res->'nao_aplicavel')::text);

  -- A asercao que protege aluno real: os baldes sao DISJUNTOS.
  perform pg_temp.checar('faltas nao engole falta_provavel (7, nao 13)',
    jsonb_array_length(v_res->'faltas') <> 13, jsonb_array_length(v_res->'faltas')::text);
  perform pg_temp.checar('faltas nao engole nao_aplicavel (7, nao 14)',
    jsonb_array_length(v_res->'faltas') <> 14, jsonb_array_length(v_res->'faltas')::text);

  -- Invariante independente de veredito: os cinco baldes somam as linhas do
  -- periodo. Continua valendo mesmo quando os numeros acima mudarem.
  select count(*) into v_linhas from public.vw_aluno_presenca_semantica_v1
   where professor_id = 35 and data_aula between date '2026-08-11' and date '2026-08-15';
  perform pg_temp.checar('os baldes somam o total de linhas',
    (v_res->>'presentes')::int
      + jsonb_array_length(v_res->'faltas')
      + jsonb_array_length(v_res->'falta_provavel')
      + jsonb_array_length(v_res->'indeterminado')
      + jsonb_array_length(v_res->'nao_aplicavel') = v_linhas,
    format('baldes vs linhas=%s', v_linhas));

  -- O professor le NOME, nunca id.
  perform pg_temp.checar('faltas trazem nome de aluno, nao id',
    (v_res->'faltas'->0->>'aluno') ~ '[A-Za-zÀ-ÿ]', coalesce((v_res->'faltas'->0)::text,'<vazio>'));

  -- ── Valdo (36) na mesma semana: 0 provavel, 11 faltas ─────────────────────
  v_res := public.fabio_professor_presencas_periodo(36, date '2026-08-11', date '2026-08-15');
  perform pg_temp.checar('Valdo: 11 faltas', jsonb_array_length(v_res->'faltas') = 11, (v_res->'faltas')::text);
  perform pg_temp.checar('Valdo: 0 falta_provavel',
    jsonb_array_length(v_res->'falta_provavel') = 0, (v_res->'falta_provavel')::text);
  perform pg_temp.checar('Valdo: presentes 61', (v_res->>'presentes')::int = 61, coalesce(v_res->>'presentes','<nulo>'));

  -- Guardas de parametro
  perform pg_temp.checar('periodo invertido recusa',
    (public.fabio_professor_presencas_periodo(36, date '2026-08-15', date '2026-08-11')->>'motivo') = 'periodo_invertido', 'invertido');
  perform pg_temp.checar('janela > 90 dias recusa',
    (public.fabio_professor_presencas_periodo(36, date '2026-01-01', date '2026-08-15')->>'motivo') = 'janela_maior_que_90_dias', 'janela');
  perform pg_temp.checar('parametro nulo recusa',
    (public.fabio_professor_presencas_periodo(null, date '2026-08-11', date '2026-08-15')->>'motivo') = 'parametros_obrigatorios', 'nulo');
end
$function$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._res where not ok),
  'detalhe', coalesce((select json_agg(json_build_object('passo', caso, 'esperado','true','obtido', detalhe) order by caso)
                         from pg_temp._res where not ok), '[]'::json)
) as resumo;

/* PRESENCAS-DOCKER-DML-TESTS-INICIO
-- Roda so no PostgreSQL efemero do mutante. O bootstrap (no .mjs) ja criou
-- `alunos` e a `vw_aluno_presenca_semantica_v1` como TABELA fake, com os cinco
-- baldes preenchidos e valores DIFERENTES entre si — se dois baldes tivessem o
-- mesmo tamanho, o mutante que soma um no outro passaria por morto.
do $docker$
declare
  v_res jsonb;
  v_def text;
begin
  v_def := pg_get_functiondef(to_regprocedure('public.fabio_professor_presencas_periodo(integer,date,date)'));
  perform pg_temp.checar('docker: nenhum identificador financeiro no corpo',
    v_def !~* '(valor_|mensalidade|pagamento|repasse|contrato|desconto|bolsa|fatura|folha)', 'corpo');
  perform pg_temp.checar('docker: nao classifica por proveniencia',
    v_def !~* 'proveniencia', 'corpo');

  v_res := public.fabio_professor_presencas_periodo(36, date '2026-08-11', date '2026-08-15');
  perform pg_temp.checar('docker: presentes 3', (v_res->>'presentes')::int = 3, coalesce(v_res->>'presentes','<nulo>'));
  perform pg_temp.checar('docker: faltas 2', jsonb_array_length(v_res->'faltas') = 2, (v_res->'faltas')::text);
  perform pg_temp.checar('docker: falta_provavel 2', jsonb_array_length(v_res->'falta_provavel') = 2, (v_res->'falta_provavel')::text);
  perform pg_temp.checar('docker: indeterminado 1', jsonb_array_length(v_res->'indeterminado') = 1, (v_res->'indeterminado')::text);
  perform pg_temp.checar('docker: nao_aplicavel 1', jsonb_array_length(v_res->'nao_aplicavel') = 1, (v_res->'nao_aplicavel')::text);

  -- Nome, nao id: a primeira falta do periodo e o Diego (12/08).
  perform pg_temp.checar('docker: faltas trazem NOME do aluno',
    (v_res->'faltas'->0->>'aluno') = 'Diego', coalesce((v_res->'faltas'->0)::text,'<vazio>'));
  -- nao_aplicavel carrega o motivo, nao o curso.
  perform pg_temp.checar('docker: nao_aplicavel traz motivo',
    (v_res->'nao_aplicavel'->0->>'motivo') = 'aula_justificada', coalesce((v_res->'nao_aplicavel'->0)::text,'<vazio>'));

  -- Isolamento: o 99 tem UMA linha no fixture e enxerga so ela. O outro lado da
  -- prova e o 'presentes 3' acima — se o filtro por professor cair, vira 4.
  perform pg_temp.checar('docker: outro professor enxerga so o dele',
    (public.fabio_professor_presencas_periodo(99, date '2026-08-11', date '2026-08-15')->>'presentes')::int = 1,
    'isolamento por professor');
  perform pg_temp.checar('docker: professor sem dado no periodo devolve estrutura vazia, nao nulo',
    (public.fabio_professor_presencas_periodo(77, date '2026-08-11', date '2026-08-15')->>'presentes')::int = 0
    and jsonb_array_length(public.fabio_professor_presencas_periodo(77, date '2026-08-11', date '2026-08-15')->'faltas') = 0,
    coalesce(public.fabio_professor_presencas_periodo(77, date '2026-08-11', date '2026-08-15')::text,'<NULO>'));
  perform pg_temp.checar('docker: fora do periodo nao entra',
    (public.fabio_professor_presencas_periodo(36, date '2026-08-11', date '2026-08-12')->>'presentes')::int = 2,
    'recorte por periodo');
end
$docker$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._res where not ok),
  'detalhe', coalesce((select json_agg(json_build_object('passo', caso, 'esperado','true','obtido', detalhe) order by caso)
                         from pg_temp._res where not ok), '[]'::json)
) as resumo;
PRESENCAS-DOCKER-DML-TESTS-FIM */
