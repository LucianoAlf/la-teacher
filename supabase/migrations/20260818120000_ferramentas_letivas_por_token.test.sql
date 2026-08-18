-- Itens 4, 5 e 9 da revisão do Alfredo, provados juntos.
--
-- As duas perguntas que este teste faz são opostas e as duas precisam passar:
--   1. a ferramenta DEVOLVE a vida letiva do dono do token — e o número tem que
--      ser o mesmo que a produção já dá hoje (Valdo, 11–15/08 = 36 aulas);
--   2. a ferramenta NÃO alcança mais nada — nem financeiro, nem outro professor,
--      nem por argumento, porque o argumento não existe.
--
-- Sem a primeira, a fronteira é só um muro em volta do nada. Sem a segunda, é
-- porta aberta com aparência de muro.

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
  v_aulas oid := to_regprocedure('public.fabio_prof_aulas_periodo(text,date,date,text)');
  v_pres  oid := to_regprocedure('public.fabio_prof_presencas_periodo(text,date,date)');
  v_valdo integer := 36;      -- professor do caso real de 17/08
  v_r jsonb;
  v_token text;
  v_token_outro text;
  v_outro integer;
  v_canonico jsonb;
  v_executaveis text[];
  v_arg text;
begin
  perform pg_temp.checar('as duas ferramentas existem',
    v_aulas is not null and v_pres is not null,
    coalesce(v_aulas::text,'<sem aulas>') || ' / ' || coalesce(v_pres::text,'<sem presencas>'));
  if v_aulas is null or v_pres is null then return; end if;

  -- ── NENHUMA assinatura aceita professor_id ────────────────────────────────
  foreach v_arg in array (select coalesce(array_agg(a), '{}') from (
      select unnest(string_to_array(pg_get_function_arguments(v_aulas), ', ')) as a
      union all
      select unnest(string_to_array(pg_get_function_arguments(v_pres), ', '))
  ) x)
  loop
    if v_arg ilike '%professor%' then
      perform pg_temp.checar('NENHUM argumento e professor_id', false, v_arg);
    end if;
  end loop;
  perform pg_temp.checar('NENHUM argumento e professor_id',
    pg_get_function_arguments(v_aulas) not ilike '%professor%'
    and pg_get_function_arguments(v_pres) not ilike '%professor%',
    pg_get_function_arguments(v_aulas) || ' | ' || pg_get_function_arguments(v_pres));

  -- ── Item 5: quem executa e SO o papel do agente ───────────────────────────
  perform pg_temp.checar('so o papel do agente executa a ferramenta de aulas',
    has_function_privilege(v_papel, v_aulas, 'EXECUTE')
    and not has_function_privilege('anon', v_aulas, 'EXECUTE')
    and not has_function_privilege('authenticated', v_aulas, 'EXECUTE')
    and not has_function_privilege('service_role', v_aulas, 'EXECUTE'),
    'anon/authenticated/service_role fora');
  perform pg_temp.checar('so o papel do agente executa a ferramenta de presencas',
    has_function_privilege(v_papel, v_pres, 'EXECUTE')
    and not has_function_privilege('anon', v_pres, 'EXECUTE')
    and not has_function_privilege('authenticated', v_pres, 'EXECUTE')
    and not has_function_privilege('service_role', v_pres, 'EXECUTE'),
    'anon/authenticated/service_role fora');

  -- ── Item 9: FINANCEIRO NAO EXISTE — a lista inteira do papel sao 2 funcoes ─
  -- Esta e a assercao que prova "nao existe como ferramenta". Enumera TUDO que
  -- o papel consegue executar no schema; se um dia alguem plugar uma funcao
  -- financeira nele, este numero muda e o teste cai.
  select coalesce(array_agg(p.oid::regprocedure::text order by p.proname), '{}')
    into v_executaveis
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.prokind = 'f'
     and has_function_privilege(v_papel, p.oid, 'EXECUTE');
  -- ⚠️ ACHADO (18/08): a primeira versao desta assercao exigia "exatamente 2" e
  -- CAIU — o papel executa ~181 funcoes. Nao e falha desta fatia: 179 funcoes do
  -- `public` tem EXECUTE concedido ao pseudo-papel PUBLIC, e PUBLIC vale pra
  -- TODO papel do cluster. Afrouxar a assercao pra passar seria transformar um
  -- achado em decoracao, entao ela vira DUAS medidas honestas:
  --
  --   (a) esta fatia nao abriu nada alem das 2 ferramentas;
  --   (b) o buraco herdado fica FIXADO num numero — se crescer, o teste cai.
  --
  -- O que importa de verdade sao as `security definer`: as `invoker` esbarram na
  -- falta de privilegio de tabela do papel. Hoje sao 38, e entre elas ha
  -- `get_faturas_alunos_financeiro_v1` (dado financeiro) e duas que ESCREVEM
  -- (`app_falta_professor_cancelar_aulas`, `materializar_projecao_contrato`).
  -- Fechar isso e decisao da casa (atinge sol/mila/lia tambem), nao desta fatia.
  perform pg_temp.checar('esta fatia abriu SO as 2 ferramentas (nada mais)',
    cardinality(v_executaveis) = (
      select count(*) + 2 from pg_proc p2
       join pg_namespace n2 on n2.oid = p2.pronamespace
      where n2.nspname = 'public' and p2.prokind = 'f'
        and exists (select 1 from unnest(coalesce(p2.proacl,'{}')) a where a::text like '=%')
    ),
    format('%s executaveis = %s herdadas do PUBLIC + 2 desta fatia',
      cardinality(v_executaveis), cardinality(v_executaveis) - 2));

  -- Eram 38 quando esta assercao nasceu; a `130000` (mesma fatia) fechou todas.
  -- O numero fixado agora e ZERO: qualquer funcao definer que volte a ser aberta
  -- ao PUBLIC reabre a porta lateral pros papeis restritos, e o teste cai.
  perform pg_temp.checar('gap do PUBLIC fechado: ZERO security definer aberta',
    (select count(*) from pg_proc p2
      join pg_namespace n2 on n2.oid = p2.pronamespace
     where n2.nspname = 'public' and p2.prokind = 'f' and p2.prosecdef
       and exists (select 1 from unnest(coalesce(p2.proacl,'{}')) a where a::text like '=%')) = 0,
    format('%s hoje — se subiu, alguem abriu mais uma porta ao PUBLIC',
      (select count(*) from pg_proc p2
        join pg_namespace n2 on n2.oid = p2.pronamespace
       where n2.nspname = 'public' and p2.prokind = 'f' and p2.prosecdef
         and exists (select 1 from unnest(coalesce(p2.proacl,'{}')) a where a::text like '=%'))));

  perform pg_temp.checar('nenhuma ferramenta DESTA fatia tem cara de financeiro',
    not exists (select 1 from unnest(array[v_aulas::regprocedure::text,
                                          v_pres::regprocedure::text]) f
                 where f ~* '(financ|repasse|mensalidade|contrato|folha|pagamento|fatura|valor)'),
    v_aulas::regprocedure::text || ' | ' || v_pres::regprocedure::text);

  -- ── O numero tem que continuar sendo o mesmo da producao ──────────────────
  v_r := public.fabio_agente_cunhar_sessao(v_valdo, null, 10, 8);
  v_token := v_r ->> 'token';

  v_canonico := public.fabio_professor_resumo_aulas(v_valdo, date '2026-08-11', date '2026-08-15', null);
  v_r := public.fabio_prof_aulas_periodo(v_token, date '2026-08-11', date '2026-08-15');

  perform pg_temp.checar('Valdo 11-15/08: a ferramenta da 36 aulas',
    (v_r -> 'total_aulas')::text = '36', coalesce(v_r ->> 'total_aulas', v_r::text));
  perform pg_temp.checar('a ferramenta nao inventa: bate com a RPC canonica',
    (v_r -> 'total_aulas') = (v_canonico -> 'total_aulas')
    and (v_r -> 'por_unidade') = (v_canonico -> 'por_unidade'),
    format('ferramenta=%s canonica=%s', v_r -> 'total_aulas', v_canonico -> 'total_aulas'));

  v_r := public.fabio_prof_presencas_periodo(v_token, date '2026-08-11', date '2026-08-15');
  perform pg_temp.checar('presencas respondem pelo mesmo dono do token',
    (v_r ->> 'ok') = 'true', left(v_r::text, 160));

  -- ── Um token so fala do seu dono ──────────────────────────────────────────
  select id into v_outro from public.professores where id <> v_valdo order by id limit 1;
  v_token_outro := (public.fabio_agente_cunhar_sessao(v_outro, null, 10, 8)) ->> 'token';
  v_r := public.fabio_prof_aulas_periodo(v_token_outro, date '2026-08-11', date '2026-08-15');
  perform pg_temp.checar('token de outro professor NAO devolve os dados do Valdo',
    (v_r -> 'total_aulas') is distinct from (v_canonico -> 'total_aulas')
    or v_outro = v_valdo,
    format('outro=%s total=%s', v_outro, v_r -> 'total_aulas'));

  -- ── As recusas ────────────────────────────────────────────────────────────
  perform pg_temp.checar('token inventado -> recusa estruturada, sem dado',
    (public.fabio_prof_aulas_periodo('nao-sou-um-token', date '2026-08-11', date '2026-08-15') ->> 'ok') = 'false',
    public.fabio_prof_aulas_periodo('nao-sou-um-token', date '2026-08-11', date '2026-08-15')::text);

  v_r := public.fabio_agente_cunhar_sessao(v_valdo, null, 10, 1);
  v_token := v_r ->> 'token';
  perform public.fabio_prof_aulas_periodo(v_token, date '2026-08-11', date '2026-08-15');
  perform pg_temp.checar('token esgotado -> recusa na segunda chamada',
    (public.fabio_prof_aulas_periodo(v_token, date '2026-08-11', date '2026-08-15') ->> 'codigo') = 'token_esgotado',
    public.fabio_prof_aulas_periodo(v_token, date '2026-08-11', date '2026-08-15')::text);

  v_token := (public.fabio_agente_cunhar_sessao(v_valdo, null, 10, 8)) ->> 'token';
  perform pg_temp.checar('periodo invertido -> recusa',
    (public.fabio_prof_aulas_periodo(v_token, date '2026-08-15', date '2026-08-11') ->> 'codigo') = 'periodo_invertido',
    'fim < inicio');
  perform pg_temp.checar('janela longa demais -> recusa',
    (public.fabio_prof_aulas_periodo(v_token, date '2026-01-01', date '2026-08-15') ->> 'codigo') = 'periodo_longo_demais',
    'janela > 92 dias');
  perform pg_temp.checar('periodo incompleto -> pergunta, nao chuta',
    (public.fabio_prof_aulas_periodo(v_token, null, null) ->> 'codigo') = 'periodo_incompleto',
    'sem datas');
end
$function$;

select json_build_object(
  'total',  (select count(*) from pg_temp._res),
  'falhas', (select count(*) from pg_temp._res where not ok),
  -- `detalhe` no formato que o runner sabe imprimir (passo/esperado/obtido):
  -- sem isso ele diz "2 passos divergiram" e engole QUAIS, que e a unica parte
  -- que interessa quando cai.
  'detalhe', (select json_agg(json_build_object(
                      'passo', caso, 'esperado', 'OK', 'obtido', detalhe)
                      order by caso)
               from pg_temp._res where not ok),
  'casos',  (select json_agg(json_build_object(
                      'caso', caso,
                      'veredito', case when ok then 'OK' else 'FALHOU' end,
                      'detalhe', detalhe) order by caso)
               from pg_temp._res)
) as resumo;
