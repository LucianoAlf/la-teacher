-- 020d-devolver-lease-do-ensaio.sql
--
-- ⚠️ Aplicada em produção antes de ser versionada (ver o aviso na 020c).
--    Conteúdo extraído de `pg_get_functiondef` do que está no ar.
--
-- O ensaio precisa DEVOLVER o que pegou.
--
-- Achado rodando: `--dry-run` reivindicava as linhas (certo, pra exercitar o
-- caminho real) e ia embora sem soltar. As linhas ficavam em 'gerando' com
-- lease de 5 minutos, e a execução de verdade logo em seguida encontrava a fila
-- vazia. Ensaio que trava trabalho de produção não é ensaio.
--
-- Devolver também desconta a tentativa: ensaio não pode consumir o orçamento de
-- retentativas de ninguém.

create or replace function public.fabio_devolutiva_devolver(
  p_id uuid, p_lease_token uuid)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_n integer;
begin
  update public.fabio_devolutivas
     set status = 'pendente',
         lease_token = null, lease_expira_em = null,
         tentativas = greatest(tentativas - 1, 0),
         atualizado_em = now()
   where id = p_id and status = 'gerando'
     and lease_token = p_lease_token and lease_expira_em > now();
  get diagnostics v_n = row_count;
  return v_n > 0;
end $function$;

comment on function public.fabio_devolutiva_devolver is
  'Solta o lease sem contar como falha nem gastar tentativa. Usado pelo --dry-run (migration 020d).';

revoke all on function public.fabio_devolutiva_devolver(uuid, uuid) from public, anon, authenticated;
grant execute on function public.fabio_devolutiva_devolver(uuid, uuid) to service_role, fabio_agent;
