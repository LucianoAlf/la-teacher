-- O trecho executavel remotamente e um contrato de catalogo: confere que as 5
-- RPCs existem e que as portas estao fechadas (service_role executa;
-- public/anon/authenticated nao). O bloco Docker no fim fica comentado de
-- proposito e o runner de mutantes o extrai para um PostgreSQL efemero, onde a
-- prova por DML (resolver, registrar shadow, maquina de estados, idempotencia)
-- roda de verdade sobre uma carteira fake.

create temporary table pg_temp._participacao_res (
  caso text,
  ok boolean,
  detalhe text
) on commit drop;

create or replace function pg_temp.checar_schema(
  p_caso text,
  p_ok boolean,
  p_detalhe text
) returns void
language plpgsql
as $function$
begin
  insert into pg_temp._participacao_res(caso, ok, detalhe)
  values (p_caso, coalesce(p_ok, false), p_detalhe);
end
$function$;

do $function$
declare
  v_resolver oid := to_regprocedure('public.fabio_resolver_participante(integer,uuid,text)');
  v_registrar oid := to_regprocedure('public.fabio_participacao_registrar_candidata(integer,integer,integer,integer,text,text,text,text,text,text)');
  v_confirmar oid := to_regprocedure('public.fabio_participacao_confirmar(uuid,integer)');
  v_validar   oid := to_regprocedure('public.fabio_participacao_validar(uuid,uuid)');
  v_descartar oid := to_regprocedure('public.fabio_participacao_descartar(uuid,text,text,text)');
begin
  perform pg_temp.checar_schema('a RPC resolver_participante existe', v_resolver is not null, coalesce(v_resolver::text, '<ausente>'));
  perform pg_temp.checar_schema('a RPC registrar_candidata existe', v_registrar is not null, coalesce(v_registrar::text, '<ausente>'));
  perform pg_temp.checar_schema('a RPC confirmar existe', v_confirmar is not null, coalesce(v_confirmar::text, '<ausente>'));
  perform pg_temp.checar_schema('a RPC validar existe', v_validar is not null, coalesce(v_validar::text, '<ausente>'));
  perform pg_temp.checar_schema('a RPC descartar existe', v_descartar is not null, coalesce(v_descartar::text, '<ausente>'));

  if v_resolver is not null then
    perform pg_temp.checar_schema(
      'service_role executa resolver; anon/authenticated nao',
      has_function_privilege('service_role', v_resolver, 'EXECUTE')
      and not has_function_privilege('anon', v_resolver, 'EXECUTE')
      and not has_function_privilege('authenticated', v_resolver, 'EXECUTE'),
      'grant resolver');
  end if;
  if v_registrar is not null then
    perform pg_temp.checar_schema(
      'service_role executa registrar_candidata; anon/authenticated nao',
      has_function_privilege('service_role', v_registrar, 'EXECUTE')
      and not has_function_privilege('anon', v_registrar, 'EXECUTE')
      and not has_function_privilege('authenticated', v_registrar, 'EXECUTE'),
      'grant registrar');
  end if;
  if v_confirmar is not null then
    perform pg_temp.checar_schema(
      'service_role executa confirmar; anon/authenticated nao',
      has_function_privilege('service_role', v_confirmar, 'EXECUTE')
      and not has_function_privilege('anon', v_confirmar, 'EXECUTE')
      and not has_function_privilege('authenticated', v_confirmar, 'EXECUTE'),
      'grant confirmar');
  end if;
  if v_validar is not null then
    perform pg_temp.checar_schema(
      'service_role executa validar; anon/authenticated nao',
      has_function_privilege('service_role', v_validar, 'EXECUTE')
      and not has_function_privilege('anon', v_validar, 'EXECUTE')
      and not has_function_privilege('authenticated', v_validar, 'EXECUTE'),
      'grant validar');
  end if;
  if v_descartar is not null then
    perform pg_temp.checar_schema(
      'service_role executa descartar; anon/authenticated nao',
      has_function_privilege('service_role', v_descartar, 'EXECUTE')
      and not has_function_privilege('anon', v_descartar, 'EXECUTE')
      and not has_function_privilege('authenticated', v_descartar, 'EXECUTE'),
      'grant descartar');
  end if;
end
$function$;

-- Resumo do contrato de catalogo (execucao remota). O bloco Docker abaixo fecha
-- com o SEU proprio resumo: sem isso, o mutante leria este resumo aqui,
-- calculado ANTES das asercoes DML, e um mutante vivo passaria por morto.
select json_build_object(
  'falhas', (select count(*) from pg_temp._participacao_res where not ok),
  'detalhe', coalesce((
    select json_agg(json_build_object('passo', caso, 'esperado', 'true', 'obtido', detalhe) order by caso)
      from pg_temp._participacao_res where not ok
  ), '[]'::json)
) as resumo;

/* PARTICIPACAO-DOCKER-DML-TESTS-INICIO
-- Roda so no PostgreSQL efemero do mutante. O bootstrap (no .mjs) ja criou:
-- pgcrypto, roles, o SCHEMA inteiro (tabelas/view/triggers), fn_aula_operacional_id
-- fake (devolve o proprio id), tabelas fake de presenca/registro (para provar
-- shadow por contagem), e uma vw_fabio_carteira_professor fake com:
--   professor 10 / unidade U: Billy(101 'Billy Paulo Vangu'),
--                             Felipe(103 'Felipe Souza'), Felipe(104 'Felipe Andrade');
--   professor 99 / unidade U: Marcelo(102 'Marcelo Dias').

do $docker$
declare
  v_unidade uuid := '11111111-1111-1111-1111-111111111111';
  v_res     jsonb;
  v_res2    jsonb;
  v_id      uuid;
  v_estado  text;
  v_pres0   bigint;
  v_reg0    bigint;
  v_pres1   bigint;
  v_reg1    bigint;
  v_confs   integer;
begin
  -- ── Escada de identidade ──────────────────────────────────────────────────
  v_res := public.fabio_resolver_participante(10, v_unidade, 'Felipe');
  perform pg_temp.checar_schema('resolver Felipe (duplicado) devolve cardinalidade 2',
    (v_res->>'cardinalidade')::int = 2 and (v_res->>'origem') = 'carteira', coalesce(v_res::text, '<nulo>'));

  v_res := public.fabio_resolver_participante(10, v_unidade, 'Billy');
  perform pg_temp.checar_schema('resolver Billy (por token) devolve cardinalidade 1',
    (v_res->>'cardinalidade')::int = 1 and (v_res->>'origem') = 'carteira', coalesce(v_res::text, '<nulo>'));

  v_res := public.fabio_resolver_participante(10, v_unidade, 'Marcelo');
  perform pg_temp.checar_schema('resolver Marcelo cai na unidade (fora da carteira do professor)',
    (v_res->>'cardinalidade')::int = 1 and (v_res->>'origem') = 'unidade', coalesce(v_res::text, '<nulo>'));

  v_res := public.fabio_resolver_participante(10, v_unidade, 'Ninguem');
  perform pg_temp.checar_schema('resolver nome inexistente devolve cardinalidade 0 / externo',
    (v_res->>'cardinalidade')::int = 0 and (v_res->>'origem') = 'externo', coalesce(v_res::text, '<nulo>'));

  -- ── Registrar candidata (participante externo) em SHADOW ───────────────────
  select count(*) into v_pres0 from public.aluno_presenca;
  select count(*) into v_reg0  from public.fabio_registros_aula;

  v_res := public.fabio_participacao_registrar_candidata(
    50, 10, 793, null, 'Juliana Externa', null, 'baixa', 'deterministico', 'wa:ext', 'quem fez foi a Juliana');
  v_id := (v_res->>'ocorrencia_id')::uuid;
  perform pg_temp.checar_schema('registrar externo pede confirmacao e nasce candidata',
    (v_res->>'ok')::boolean is true
      and (v_res->>'estado') = 'candidata'
      and (v_res->>'precisa_confirmar')::boolean is true,
    coalesce(v_res::text, '<nulo>'));

  select count(*) into v_pres1 from public.aluno_presenca;
  select count(*) into v_reg1  from public.fabio_registros_aula;
  perform pg_temp.checar_schema('candidata NAO escreve em presenca nem registro (shadow)',
    v_pres1 = v_pres0 and v_reg1 = v_reg0,
    format('presenca %s->%s, registro %s->%s', v_pres0, v_pres1, v_reg0, v_reg1));

  -- ── Maquina de estados ────────────────────────────────────────────────────
  -- validar uma candidata recusa (precisa confirmar antes)
  v_res := public.fabio_participacao_validar(v_id, gen_random_uuid());
  perform pg_temp.checar_schema('validar candidata recusa (nao esta confirmada)',
    (v_res->>'ok')::boolean is false, coalesce(v_res::text, '<nulo>'));

  -- confirmar: candidata -> confirmada
  v_res := public.fabio_participacao_confirmar(v_id, 10);
  perform pg_temp.checar_schema('confirmar leva candidata a confirmada',
    (v_res->>'ok')::boolean is true and (v_res->>'estado') = 'confirmada', coalesce(v_res::text, '<nulo>'));

  -- confirmar de novo e idempotente: nao empilha evento
  v_res := public.fabio_participacao_confirmar(v_id, 10);
  select count(*) into v_confs from public.fabio_participacao_ocorrencia_eventos
    where ocorrencia_id = v_id and evento = 'confirmada';
  perform pg_temp.checar_schema('confirmar de novo e idempotente (um so evento confirmada)',
    (v_res->>'ok')::boolean is true and v_confs = 1, format('ok=%s confs=%s', v_res->>'ok', v_confs));

  -- validar: confirmada -> validada
  v_res := public.fabio_participacao_validar(v_id, gen_random_uuid());
  perform pg_temp.checar_schema('validar leva confirmada a validada',
    (v_res->>'ok')::boolean is true and (v_res->>'estado') = 'validada', coalesce(v_res::text, '<nulo>'));

  -- descartar uma validada recusa (validada so se desfaz por correcao)
  v_res := public.fabio_participacao_descartar(v_id, 'engano', 'coordenacao', 'u1');
  perform pg_temp.checar_schema('descartar validada recusa',
    (v_res->>'ok')::boolean is false, coalesce(v_res::text, '<nulo>'));

  -- ── Idempotencia por origem_message_id ────────────────────────────────────
  v_res := public.fabio_participacao_registrar_candidata(
    60, 10, 793, null, 'Externo Idem', null, 'baixa', 'deterministico', 'wa:idem', 't');
  begin
    v_res2 := public.fabio_participacao_registrar_candidata(
      60, 10, 793, null, 'Externo Idem', null, 'baixa', 'deterministico', 'wa:idem', 't');
    perform pg_temp.checar_schema('mesma mensagem = uma so ocorrencia (idempotente)',
      (v_res2->>'ja_existia')::boolean is true
        and (v_res2->>'ocorrencia_id') = (v_res->>'ocorrencia_id')
        and (select count(*) from public.fabio_participacao_ocorrencias
              where origem_message_id = 'wa:idem'
                and aula_operacional_id = public.fn_aula_operacional_id(60)) = 1,
      coalesce(v_res2::text, '<nulo>'));
  exception when others then
    perform pg_temp.checar_schema('mesma mensagem = uma so ocorrencia (idempotente)', false, sqlerrm);
  end;
end
$docker$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._participacao_res where not ok),
  'detalhe', coalesce((
    select json_agg(json_build_object('passo', caso, 'esperado', 'true', 'obtido', detalhe) order by caso)
      from pg_temp._participacao_res where not ok
  ), '[]'::json)
) as resumo;
PARTICIPACAO-DOCKER-DML-TESTS-FIM */
