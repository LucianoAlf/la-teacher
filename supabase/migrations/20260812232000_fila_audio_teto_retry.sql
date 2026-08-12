-- Alinha o retry canônico da fila de áudio ao contrato já exibido pela UI:
-- no máximo três tentativas automáticas. Falhas semânticas usam a porta
-- tipificada da 094 e nunca entram neste sorteio.

create or replace function public.fn_fabio_retry_fila()
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  r record;
  n integer := 0;
begin
  for r in
    select f.id
      from public.fabio_fila_audios f
     where f.status in ('pendente', 'erro')
       and f.erro_tipo = 'transitorio'
       and f.status <> 'erro_terminal'
       and f.tentativas < 3
       and f.criado_em > now() - interval '3 days'
       and f.atualizado_em < now() - (least(greatest(f.tentativas, 1), 12) * interval '5 minutes')
     order by f.atualizado_em
     limit 10
  loop
    update public.fabio_fila_audios
       set tentativas = tentativas + 1,
           atualizado_em = now()
     where id = r.id;
    perform public.fn_fabio_chama_edge(r.id);
    n := n + 1;
  end loop;
  return n;
end
$function$;

comment on function public.fn_fabio_retry_fila() is
  'Retenta somente falhas transitorias por ate tres tentativas automaticas; '
  'falhas semanticas terminais sao encerradas pela RPC tipificada da 094.';

revoke execute on function public.fn_fabio_retry_fila()
  from public, anon, authenticated;
grant execute on function public.fn_fabio_retry_fila() to service_role;
