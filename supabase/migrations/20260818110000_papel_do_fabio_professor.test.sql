-- Item 3 da revisão do Alfredo: PROVAR com `has_table_privilege`, não afirmar.
--
-- O que este teste mede não é "o papel foi criado" — é "o papel não alcança".
-- A pergunta certa sobre uma fronteira é sempre negativa, e ela precisa ser
-- feita contra o catálogo, que é quem decide de verdade na hora do acesso.

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
  v_papel text := 'fabio_professor_agente';
  v_tabelas_com_select integer;
  v_papeis text[] := array['public','anon','authenticated','service_role','fabio_professor_agente'];
  v_p text;
  v_vazam text[] := '{}';
begin
  perform pg_temp.checar('o papel existe',
    exists (select 1 from pg_roles where rolname = v_papel), v_papel);
  if not exists (select 1 from pg_roles where rolname = v_papel) then return; end if;

  -- ── O que o papel NAO e ───────────────────────────────────────────────────
  perform pg_temp.checar('NAO ignora RLS (o fabio_agent de hoje ignora)',
    (select not rolbypassrls from pg_roles where rolname = v_papel), 'rolbypassrls');
  perform pg_temp.checar('NAO e superusuario',
    (select not rolsuper from pg_roles where rolname = v_papel), 'rolsuper');
  perform pg_temp.checar('NAO herda privilegio de grupo',
    (select not rolinherit from pg_roles where rolname = v_papel), 'rolinherit');
  perform pg_temp.checar('NAO cria papel nem banco',
    (select not rolcreaterole and not rolcreatedb from pg_roles where rolname = v_papel),
    'rolcreaterole/rolcreatedb');
  perform pg_temp.checar('NAO pertence a grupo nenhum',
    not exists (select 1 from pg_auth_members m
                 join pg_roles r on r.oid = m.member
                where r.rolname = v_papel),
    'pg_auth_members');

  -- ── Item 3: NINGUEM le a tabela da capacidade ─────────────────────────────
  foreach v_p in array v_papeis loop
    if has_table_privilege(v_p, 'public.fabio_agente_sessoes', 'SELECT') then
      v_vazam := v_vazam || v_p;
    end if;
  end loop;
  perform pg_temp.checar('NENHUM papel tem SELECT em fabio_agente_sessoes',
    cardinality(v_vazam) = 0,
    case when cardinality(v_vazam) = 0 then 'nenhum' else array_to_string(v_vazam, ', ') end);

  v_vazam := '{}';
  foreach v_p in array v_papeis loop
    if has_table_privilege(v_p, 'public.fabio_agente_sessoes', 'INSERT')
       or has_table_privilege(v_p, 'public.fabio_agente_sessoes', 'UPDATE')
       or has_table_privilege(v_p, 'public.fabio_agente_sessoes', 'DELETE') then
      v_vazam := v_vazam || v_p;
    end if;
  end loop;
  perform pg_temp.checar('NENHUM papel escreve em fabio_agente_sessoes',
    cardinality(v_vazam) = 0,
    case when cardinality(v_vazam) = 0 then 'nenhum' else array_to_string(v_vazam, ', ') end);

  -- ── O corte de verdade: zero tabela do public alcancavel ──────────────────
  -- `pg_class` + OID de proposito: `information_schema.tables` lista relacao de
  -- extensao (pg_stat_statements_info) que nao resolve por nome, e o teste
  -- morria na regua em vez de medir a fronteira.
  select count(*) into v_tabelas_com_select
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relkind in ('r', 'p')
     and has_table_privilege(v_papel, c.oid, 'SELECT');
  perform pg_temp.checar('o papel le ZERO tabela do public',
    v_tabelas_com_select = 0,
    format('%s tabela(s) legiveis', v_tabelas_com_select));

  -- Contraprova viva: o papel que existe hoje lê tudo. Sem esta linha, o
  -- "zero" acima poderia ser um zero de medição errada, não de fronteira.
  perform pg_temp.checar('contraprova: fabio_agent (o de hoje) LE muita coisa',
    (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relkind in ('r', 'p')
        and has_table_privilege('fabio_agent', c.oid, 'SELECT')) > 100,
    'se isto falhar, a regua de medicao e que esta quebrada');

  -- ── Nao alcanca as RPCs cruas (as que aceitam professor_id) ───────────────
  perform pg_temp.checar('NAO executa a RPC crua de aulas (aceita professor_id)',
    not has_function_privilege(v_papel,
      to_regprocedure('public.fabio_professor_resumo_aulas(integer,date,date,text)'), 'EXECUTE'),
    'fabio_professor_resumo_aulas');
  perform pg_temp.checar('NAO executa a RPC crua de presencas',
    not has_function_privilege(v_papel,
      to_regprocedure('public.fabio_professor_presencas_periodo(integer,date,date)'), 'EXECUTE'),
    'fabio_professor_presencas_periodo');
  perform pg_temp.checar('NAO executa a cunhagem de capacidade',
    not has_function_privilege(v_papel,
      to_regprocedure('public.fabio_agente_cunhar_sessao(integer,uuid,integer,integer)'), 'EXECUTE'),
    'cunhar');
  perform pg_temp.checar('NAO executa a resolucao direta (nao existe oraculo de token)',
    not has_function_privilege(v_papel,
      to_regprocedure('public.fabio_agente_resolver(text)'), 'EXECUTE'),
    'resolver');

  -- ── O que ele PODE: so enxergar o schema ──────────────────────────────────
  perform pg_temp.checar('tem USAGE no schema public (pra chamar funcao)',
    has_schema_privilege(v_papel, 'public', 'USAGE'), 'usage');
  perform pg_temp.checar('NAO tem CREATE no schema public',
    not has_schema_privilege(v_papel, 'public', 'CREATE'), 'create');
end
$function$;

select json_build_object(
  'total',  (select count(*) from pg_temp._res),
  'falhas', (select count(*) from pg_temp._res where not ok),
  'casos',  (select json_agg(json_build_object(
                      'caso', caso,
                      'veredito', case when ok then 'OK' else 'FALHOU' end,
                      'detalhe', detalhe) order by caso)
               from pg_temp._res)
) as resumo;
