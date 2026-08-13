-- A duplicata morreu e o numero nao mudou.

create temporary table _mata_res(caso text, ok boolean, detalhe text) on commit drop;

create or replace function pg_temp.checar_mata(p_caso text, p_ok boolean, p_detalhe text)
returns void language plpgsql as $$
begin insert into _mata_res values (p_caso, coalesce(p_ok,false), p_detalhe); end $$;

do $$
declare v25 jsonb; v33 jsonb;
begin
  perform pg_temp.checar_mata(
    'a view duplicada nao existe mais',
    to_regclass('public.vw_aluno_pessoa') is null,
    'vw_aluno_pessoa'
  );

  perform pg_temp.checar_mata(
    'a canonica que fica esta la',
    to_regclass('public.vw_professor_carteira_pessoa_canonica_sombra') is not null
      and to_regclass('public.vw_aluno_identidade_unidade_canonica') is not null,
    'as duas canonicas da casa'
  );

  -- O numero tem que ser o MESMO de antes da troca de fonte. Se mudar, a
  -- canonica nao era equivalente e a substituicao estaria errada.
  v25 := public.app_professor_carteira_contagem(25);
  v33 := public.app_professor_carteira_contagem(33);
  perform pg_temp.checar_mata(
    'professor 25 continua com 20 pessoas / 21 matriculas / 23 linhas',
    (v25->>'pessoas')::int = 20 and (v25->>'matriculas')::int = 21
      and (v25->>'linhas')::int = 23,
    coalesce(v25::text,'<NULL>')
  );
  perform pg_temp.checar_mata(
    'Ramon (33) continua com 47 pessoas',
    (v33->>'pessoas')::int = 47,
    coalesce(v33::text,'<NULL>')
  );

  -- A RPC nao pode voltar a reimplementar deduplicacao por conta propria.
  perform pg_temp.checar_mata(
    'a contagem le a canonica, nao refaz a chave de pessoa',
    (select pg_get_functiondef(p.oid)
       from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='app_professor_carteira_contagem')
      ilike '%vw_professor_carteira_pessoa_canonica_sombra%',
    'tem que citar a canonica'
  );
  perform pg_temp.checar_mata(
    'a contagem NAO monta chave de pessoa na mao',
    (select pg_get_functiondef(p.oid)
       from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='app_professor_carteira_contagem')
      not ilike '%emusys_student_id%',
    'nada de emusys_student_id dentro da RPC'
  );

  -- ACL: worker e agente dentro, cliente fora.
  perform pg_temp.checar_mata(
    'ACL preservada',
    has_function_privilege('service_role','public.app_professor_carteira_contagem(integer)','EXECUTE')
      and has_function_privilege('fabio_agent','public.app_professor_carteira_contagem(integer)','EXECUTE')
      and not has_function_privilege('anon','public.app_professor_carteira_contagem(integer)','EXECUTE')
      and not has_function_privilege('authenticated','public.app_professor_carteira_contagem(integer)','EXECUTE'),
    'service_role+fabio_agent dentro, anon/authenticated fora'
  );
end $$;

select json_build_object(
  'teste', '20260813215959-mata-a-view-duplicada',
  'falhas', (select count(*) from _mata_res where not ok),
  'detalhe', coalesce((select json_agg(json_build_object(
    'passo', caso, 'esperado','ok','obtido', coalesce(detalhe,'<NULL>'))
  ) from _mata_res where not ok), '[]'::json)
) as resumo;
