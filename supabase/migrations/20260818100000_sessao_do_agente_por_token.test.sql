-- O que está sob prova aqui é uma GUARDA, e guarda só se prova falhando.
--
-- Cada caso abaixo tem um par: o caminho que deve passar e o que deve ser
-- recusado. Sem o par, um mutante que "libera tudo" passaria verde — foi
-- exatamente assim que o teste da devolutiva nasceu vazio em 17/08.
--
-- Roda dentro do BEGIN/ROLLBACK do runner, que confere resíduo zero.

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
  v_cunhar oid := to_regprocedure('public.fabio_agente_cunhar_sessao(integer,uuid,integer,integer)');
  v_resolver oid := to_regprocedure('public.fabio_agente_resolver(text)');
  v_prof integer;
  v_outro integer;
  v_r jsonb;
  v_token text;
  v_token2 text;
  v_sessao uuid;
  v_i integer;
begin
  perform pg_temp.checar('as funcoes existem',
    v_cunhar is not null and v_resolver is not null,
    coalesce(v_cunhar::text,'<sem cunhar>') || ' / ' || coalesce(v_resolver::text,'<sem resolver>'));
  if v_cunhar is null or v_resolver is null then return; end if;

  select id into v_prof from public.professores order by id limit 1;
  select id into v_outro from public.professores where id <> v_prof order by id limit 1;
  perform pg_temp.checar('achei dois professores reais',
    v_prof is not null and v_outro is not null, format('%s / %s', v_prof, v_outro));
  if v_prof is null or v_outro is null then return; end if;

  -- ── PORTAS ────────────────────────────────────────────────────────────────
  perform pg_temp.checar('anon NAO cunha',
    not has_function_privilege('anon', v_cunhar, 'EXECUTE'), 'anon');
  perform pg_temp.checar('authenticated NAO cunha',
    not has_function_privilege('authenticated', v_cunhar, 'EXECUTE'), 'authenticated');
  perform pg_temp.checar('service_role cunha (e o bridge)',
    has_function_privilege('service_role', v_cunhar, 'EXECUTE'), 'service_role');
  -- A resolucao nao e de ninguem: quem chama sao as RPCs escopadas, que rodam
  -- como dono. Se alguem ganhar EXECUTE aqui, ganha um oraculo de tokens.
  perform pg_temp.checar('NINGUEM executa o resolver direto',
    not has_function_privilege('service_role', v_resolver, 'EXECUTE')
    and not has_function_privilege('authenticated', v_resolver, 'EXECUTE')
    and not has_function_privilege('anon', v_resolver, 'EXECUTE'),
    'service_role/authenticated/anon');

  -- ── CAMINHO FELIZ ─────────────────────────────────────────────────────────
  v_r := public.fabio_agente_cunhar_sessao(v_prof, null, 10, 8);
  v_token := v_r ->> 'token';
  v_sessao := (v_r ->> 'sessao_id')::uuid;
  perform pg_temp.checar('cunhar devolve token e assinatura curta',
    v_token is not null and length(v_r ->> 'assinatura') = 8, v_r::text);

  -- O TOKEN CRU NAO PODE ESTAR NA TABELA. Se estiver, vazar o banco vira vazar
  -- a capacidade — o motivo de existir hash aqui.
  perform pg_temp.checar('a tabela guarda HASH, nunca o token cru',
    not exists (select 1 from public.fabio_agente_sessoes where token_hash = v_token),
    'procurei o token cru na coluna de hash');
  perform pg_temp.checar('o hash gravado e o sha256 do token',
    exists (select 1 from public.fabio_agente_sessoes
             where id = v_sessao
               and token_hash = encode(extensions.digest(v_token, 'sha256'), 'hex')),
    'sha256');

  v_r := public.fabio_agente_resolver(v_token);
  perform pg_temp.checar('token valido resolve no professor certo',
    (v_r ->> 'ok') = 'true' and (v_r ->> 'professor_id')::integer = v_prof, v_r::text);
  perform pg_temp.checar('resolver consome um uso',
    (select usos from public.fabio_agente_sessoes where id = v_sessao) = 1,
    (select usos::text from public.fabio_agente_sessoes where id = v_sessao));

  -- ── UM TOKEN NAO ATRAVESSA PROFESSORES ────────────────────────────────────
  v_r := public.fabio_agente_cunhar_sessao(v_outro, null, 10, 8);
  v_token2 := v_r ->> 'token';
  perform pg_temp.checar('token do outro professor resolve NELE, nunca no primeiro',
    (public.fabio_agente_resolver(v_token2) ->> 'professor_id')::integer = v_outro,
    format('esperado %s', v_outro));
  perform pg_temp.checar('dois tokens diferentes nao colidem',
    v_token is distinct from v_token2, 'tokens distintos');

  -- ── AS RECUSAS (cada uma mata um mutante) ─────────────────────────────────
  perform pg_temp.checar('token inventado NAO resolve',
    (public.fabio_agente_resolver('token-que-eu-inventei') ->> 'codigo') = 'token_desconhecido',
    public.fabio_agente_resolver('token-que-eu-inventei')::text);
  perform pg_temp.checar('token vazio NAO resolve',
    (public.fabio_agente_resolver('') ->> 'codigo') = 'token_ausente', 'vazio');
  perform pg_temp.checar('token nulo NAO resolve',
    (public.fabio_agente_resolver(null) ->> 'codigo') = 'token_ausente', 'nulo');

  -- Envelhece a sessão INTEIRA (as duas datas), porque o CHECK
  -- `expira_em > criado_em` proíbe — com razão — uma sessão que já nasce morta.
  update public.fabio_agente_sessoes
     set criado_em = now() - interval '2 hours',
         expira_em = now() - interval '1 hour'
   where id = v_sessao;
  perform pg_temp.checar('token EXPIRADO nao resolve',
    (public.fabio_agente_resolver(v_token) ->> 'codigo') = 'token_expirado',
    public.fabio_agente_resolver(v_token)::text);

  update public.fabio_agente_sessoes set expira_em = now() + interval '10 minutes'
   where id = v_sessao;
  perform public.fabio_agente_revogar_sessao(v_sessao);
  perform pg_temp.checar('token REVOGADO nao resolve',
    (public.fabio_agente_resolver(v_token) ->> 'codigo') = 'token_revogado',
    public.fabio_agente_resolver(v_token)::text);

  -- Teto de usos: gasta ate o limite e confere que o seguinte e recusado.
  v_r := public.fabio_agente_cunhar_sessao(v_prof, null, 10, 2);
  v_token := v_r ->> 'token';
  for v_i in 1..2 loop
    perform public.fabio_agente_resolver(v_token);
  end loop;
  perform pg_temp.checar('estourou o teto de usos -> recusa',
    (public.fabio_agente_resolver(v_token) ->> 'codigo') = 'token_esgotado',
    public.fabio_agente_resolver(v_token)::text);

  -- ── LIMITES DA CUNHAGEM ───────────────────────────────────────────────────
  begin
    perform public.fabio_agente_cunhar_sessao(-1, null, 10, 8);
    perform pg_temp.checar('professor inexistente NAO cunha', false, 'cunhou!');
  exception when others then
    perform pg_temp.checar('professor inexistente NAO cunha', true, sqlerrm);
  end;

  v_r := public.fabio_agente_cunhar_sessao(v_prof, null, 999, 999);
  perform pg_temp.checar('TTL e usos sao limitados na entrada',
    (v_r ->> 'max_usos')::integer <= 32
    and (v_r ->> 'expira_em')::timestamptz <= now() + interval '61 minutes',
    v_r::text);
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
