-- A limpeza para de se repetir
--
-- O QUE ESTAVA ACONTECENDO (medido em 13/08/2026): o reconciler rodou 1499
-- vezes num dia e 1493 dessas execucoes foram IDENTICAS --
-- {"claimed":5,"limpas":5}. Sempre as mesmas 5 linhas: artefatos de E2E cujo
-- objeto de Storage ja nao existia (`storage.objects` vazio para o path) e
-- cujo payload ja carregava `limpeza.removido = true`. O trabalho estava
-- feito; a linha e que nao sabia disso.
--
-- POR QUE: fabio_claim_acoes_limpeza escolhe por
--
--     estado in ('cancelada','expirada','erro') and storage_path is not null
--     and (lease_token is null or lease_expira_em < now())
--
-- e fabio_concluir_limpeza grava o carimbo em payload, zera lease_token e
-- lease_expira_em e carimba atualizado_em. Ou seja: ela NAO altera nenhuma
-- coluna que o predicado le -- e ainda LIBERA o lease, que era a unica coisa
-- segurando a linha fora do proximo ciclo. A linha requalifica em ~35s, pra
-- sempre.
--
-- Custo: ~7.500 ciclos/dia, cada um com prova + DELETE no Storage + 3 RPCs.
-- Perto de 22 mil chamadas inuteis por dia. E `atualizado_em` reescrito a cada
-- 35s destruia o valor de auditoria da coluna -- justamente a coluna pela qual
-- o proprio claim ordena.
--
-- O CONSERTO: o predicado passa a exigir que a linha ainda NAO tenha o carimbo
-- de limpeza. O carimbo ja existia e ja era gravado; ninguem lia.
--
-- POR QUE NAO ZERAR storage_path: seria mais simples e tambem fecharia o laco,
-- mas queimaria a trilha -- o path e a evidencia de qual objeto existiu e foi
-- removido. `fabio_provar_limpeza` compara o path recebido contra o da linha;
-- sem ele, a prova nao teria contra o que casar numa auditoria futura.
--
-- SOBRE O COALESCE, COM HONESTIDADE: hoje ele NAO muda nada. Medido em
-- 13/08/2026, `fabio_acoes_pendentes.payload` e NOT NULL com default
-- `'{}'::jsonb` -- payload nulo e impossivel, e por isso nao existe mutante
-- provando esta clausula (tentei escrever um e o proprio banco recusou o
-- fixture). Ele fica como defesa contra o dia em que alguem soltar o NOT NULL:
-- `null ? 'limpeza'` devolve NULL, `not NULL` e NULL, e a linha sumiria do
-- claim -- a limpeza morreria em silencio em vez de repetir em voz alta. E a
-- familia do `GREATEST(x, NULL)`, que esta casa ja pagou mais de uma vez.
-- Custo zero, e o silencio e o modo de falha pior.

create or replace function public.fabio_claim_acoes_limpeza(
  p_limite integer default 20,
  p_lease_segundos integer default 120
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_token uuid := gen_random_uuid();
  v_itens jsonb;
begin
  with picked as (
    select a.id from public.fabio_acoes_pendentes a
    where a.estado in ('cancelada','expirada','erro') and a.storage_path is not null
      and not (coalesce(a.payload, '{}'::jsonb) ? 'limpeza')
      and (a.lease_token is null or a.lease_expira_em < now())
    order by a.atualizado_em for update skip locked limit greatest(p_limite, 0)
  )
  update public.fabio_acoes_pendentes a
     set lease_token=v_token, lease_expira_em=now()+make_interval(secs=>greatest(p_lease_segundos,1)), atualizado_em=now()
    from picked p where a.id=p.id;
  select coalesce(jsonb_agg(jsonb_build_object('acao_id',a.id,'storage_path',a.storage_path,'lease_token',v_token) order by a.atualizado_em),'[]'::jsonb)
    into v_itens from public.fabio_acoes_pendentes a where a.lease_token=v_token;
  return jsonb_build_object('ok',true,'codigo','limpezas_claimadas','itens',v_itens);
end;
$function$;

comment on function public.fabio_claim_acoes_limpeza(integer, integer) is
  'Reivindica acoes terminais com objeto de Storage a remover. So entrega quem '
  'AINDA NAO tem o carimbo payload.limpeza -- sem essa clausula a linha limpa '
  'requalifica a cada ciclo e o worker repete a limpeza pra sempre (medido: '
  '1493 de 1499 execucoes identicas em 13/08/2026).';

-- ACL medida antes da troca e reafirmada aqui sem alargar nada:
-- anon=false, authenticated=false, service_role=true. Esta porta e de worker.
revoke all on function public.fabio_claim_acoes_limpeza(integer, integer)
  from public, anon, authenticated;
grant execute on function public.fabio_claim_acoes_limpeza(integer, integer)
  to service_role;
