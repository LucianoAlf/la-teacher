-- 011-retry-fila-3-dias.sql
-- Resiliência do pipeline de áudio do Fábio.
-- A fn_fabio_retry_fila (cron a cada 5 min) desistia após 5 tentativas (~15 min):
-- um erro no Hermes/VPS obrigava o professor a REGRAVAR. Troca o cap de tentativas
-- por JANELA de 3 dias (mesma régua de gravar/chamada; depois é coordenação) +
-- BACKOFF crescente (5 min -> 60 min) pra não martelar o VPS à toa. Assim, quando o
-- Hermes voltar, tudo que falhou nos últimos 3 dias reprocessa sozinho — sem regravação.
--
-- ⚠️ Função compartilhada do pipeline do Fábio — coordenar com o Alfredo antes de ele
-- redeployar a versão dele por cima.
create or replace function public.fn_fabio_retry_fila()
returns integer
language plpgsql security definer set search_path to 'public'
as $function$
declare r record; n integer := 0;
begin
  for r in
    select id from public.fabio_fila_audios
    where status in ('pendente','erro')
      and criado_em     > now() - interval '3 days'                                        -- janela: depois, coordenação
      and atualizado_em < now() - (least(greatest(tentativas,1),12) * interval '5 minutes') -- backoff 5min -> 60min
    order by atualizado_em
    limit 10
  loop
    update public.fabio_fila_audios
       set tentativas = tentativas + 1, atualizado_em = now()
     where id = r.id;
    perform public.fn_fabio_chama_edge(r.id);
    n := n + 1;
  end loop;
  return n;
end $function$;
