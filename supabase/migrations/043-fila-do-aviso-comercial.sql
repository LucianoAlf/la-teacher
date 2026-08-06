-- 043 — a fila que o worker do aviso comercial le
--
-- Duas funcoes, com papeis separados de proposito:
--
--   fabio_avisos_comerciais_pendentes  — o que ha pra fazer (nao reivindica)
--   fabio_aviso_comercial_para_envio   — o conteudo do que EU reivindiquei
--
-- A segunda existe porque o claim (036) devolve so {claimed, notificacao_id,
-- lease_token} — nao devolve corpo nem destinatario. Sem ela o worker teria
-- que ler a tabela direto, e leitura direta de fila nao confere lease: dois
-- workers leriam o mesmo corpo e o comercial receberia a devolutiva duas
-- vezes. Aqui o token e a chave: quem nao esta com o lease nao ve o conteudo.

create or replace function public.fabio_avisos_comerciais_pendentes(
  p_lote integer default 10
)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(x order by prioridade, criado_em), '[]'::jsonb)
    from (
      select
        -- ESPELHO DELIBERADO da clausula de retomada do fabio_claim_aviso_comercial
        -- (036 + 042). Se as duas divergirem, o worker lista o que nao consegue
        -- reivindicar (barulho) ou deixa de ver o que poderia entregar
        -- (silencio) — e o segundo e o caro. O teste tem passo pra isso.
        case when n.status = 'pulada_sem_destinatario' then 1 else 0 end as prioridade,
        n.criado_em,
        jsonb_build_object(
          'notificacao_id', n.id,
          'registro_id',    n.referencia_id,
          'status',         n.status,
          'tentativas',     n.tentativas,
          'criado_em',      n.criado_em
        ) as x
      from fabio_notificacoes n
      where n.destinatario_tipo = 'comercial'
        and n.tipo = 'experimental_registrada'
        and n.referencia_tipo = 'lead_experimental_registro'
        and (
          -- abandonada: quem enfileirou nao trabalha (lease zero da 042), ou
          -- o dono anterior sumiu
          (n.status = 'processando'
            and n.lease_expira_em is not null
            and n.lease_expira_em <= now())
          -- falhou e ja pode tentar de novo
          or (n.status = 'falhou'
            and (n.proxima_tentativa_em is null or n.proxima_tentativa_em <= now()))
          -- sem destinatario na epoca. Entra aqui porque a 036 PROMETE que
          -- este rastro e retomado quando o contato aparecer — e promessa que
          -- ninguem varre e gancho criado sem chamador, que ja mordeu esta
          -- casa antes. Vai por ultimo: unidade sem comercial cadastrado nao
          -- pode empurrar trabalho de verdade pra fora do lote.
          or (n.status = 'pulada_sem_destinatario')
        )
      order by prioridade, n.criado_em
      limit greatest(coalesce(p_lote, 10), 1)
    ) s
$function$;

create or replace function public.fabio_aviso_comercial_para_envio(
  p_notificacao_id uuid,
  p_lease_token    uuid
)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $function$
  select coalesce(
    (select jsonb_build_object(
              'ok',            true,
              'notificacao_id', n.id,
              'destinatario',  n.destinatario_whatsapp,
              'corpo',         n.corpo,
              'tentativas',    n.tentativas)
       from fabio_notificacoes n
      where n.id = p_notificacao_id
        and n.lease_token = p_lease_token      -- so quem esta com o lease
        and n.lease_expira_em > now()          -- e so enquanto ele vale
        and n.status = 'processando'
        and n.destinatario_whatsapp is not null),
    jsonb_build_object('ok', false, 'motivo', 'sem_lease_ou_sem_destinatario'));
$function$;

revoke all on function public.fabio_avisos_comerciais_pendentes(integer) from public, anon, authenticated;
grant execute on function public.fabio_avisos_comerciais_pendentes(integer) to service_role;
revoke all on function public.fabio_aviso_comercial_para_envio(uuid,uuid) from public, anon, authenticated;
grant execute on function public.fabio_aviso_comercial_para_envio(uuid,uuid) to service_role;

comment on function public.fabio_avisos_comerciais_pendentes(integer) is
'Avisos comerciais que o worker pode reivindicar agora. Espelha a clausula de retomada do fabio_claim_aviso_comercial; inclui pulada_sem_destinatario (por ultimo) porque e essa varredura que cumpre a promessa da 036 de retomar quando o contato for cadastrado.';
comment on function public.fabio_aviso_comercial_para_envio(uuid,uuid) is
'Corpo e destinatario de um aviso, SO para quem esta com o lease vivo. Leitura direta da fila nao confere lease e faria dois workers entregarem a mesma devolutiva.';
