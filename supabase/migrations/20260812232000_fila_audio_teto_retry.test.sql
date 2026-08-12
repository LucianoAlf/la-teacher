create temporary table _retry_audio_cases (
  caso text primary key,
  status text not null,
  erro_tipo text not null,
  tentativas integer not null,
  criado_em timestamptz not null,
  atualizado_em timestamptz not null,
  esperado boolean not null
) on commit drop;

insert into _retry_audio_cases values
  ('transitorio primeira tentativa', 'erro', 'transitorio', 1, now() - interval '1 hour', now() - interval '20 minutes', true),
  ('transitorio terceira tentativa', 'erro', 'transitorio', 2, now() - interval '1 hour', now() - interval '20 minutes', true),
  ('teto atingido', 'erro', 'transitorio', 3, now() - interval '1 hour', now() - interval '20 minutes', false),
  ('semantico terminal', 'erro_terminal', 'semantico_terminal', 1, now() - interval '1 hour', now() - interval '20 minutes', false),
  ('fora da janela', 'erro', 'transitorio', 1, now() - interval '4 days', now() - interval '20 minutes', false),
  ('ainda em backoff', 'erro', 'transitorio', 1, now() - interval '1 hour', now() - interval '1 minute', false);

do $function$
declare
  v_def text;
  v_divergentes text;
begin
  select pg_get_functiondef('public.fn_fabio_retry_fila()'::regprocedure)
    into v_def;

  if v_def not ilike '%f.tentativas < 3%'
     or v_def not ilike '%f.erro_tipo = ''transitorio''%'
     or v_def not ilike '%f.status <> ''erro_terminal''%' then
    raise exception 'fn_fabio_retry_fila nao contem teto e tipagem canonicos';
  end if;

  select string_agg(caso, ', ' order by caso)
    into v_divergentes
    from _retry_audio_cases c
   where (
     c.status in ('pendente', 'erro')
     and c.erro_tipo = 'transitorio'
     and c.status <> 'erro_terminal'
     and c.tentativas < 3
     and c.criado_em > now() - interval '3 days'
     and c.atualizado_em < now() - (least(greatest(c.tentativas, 1), 12) * interval '5 minutes')
   ) is distinct from c.esperado;

  if v_divergentes is not null then
    raise exception 'matriz de elegibilidade divergente: %', v_divergentes;
  end if;

  if has_function_privilege('anon', 'public.fn_fabio_retry_fila()', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.fn_fabio_retry_fila()', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.fn_fabio_retry_fila()', 'EXECUTE') then
    raise exception 'ACL de fn_fabio_retry_fila divergente';
  end if;
end
$function$;

select json_build_object(
  'teste', '20260812232000_fila_audio_teto_retry',
  'falhas', 0,
  'detalhe', '[]'::json
) as resumo;
