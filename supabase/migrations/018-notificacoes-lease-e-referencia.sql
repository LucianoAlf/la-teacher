-- 018-notificacoes-lease-e-referencia.sql
-- Camada de TRANSPORTE das notificações do Fábio: lease de verdade + chave por
-- referência. Pré-requisito da devolutiva de aula (spec §7.5), mas o defeito
-- que ele conserta já está vivo hoje, no briefing do Matheus.
--
-- ⚠️ O BUG DE RELÓGIO (é o motivo principal desta migration)
--
-- fabio_claim_notificacao considerava abandonada uma linha assim:
--
--     status = 'processando' and criado_em < now() - interval '10 minutes'
--
-- `criado_em` é quando a LINHA NASCEU, não quando ela foi reivindicada. Uma
-- notificação criada há 11 minutos e reivindicada há 5 SEGUNDOS já contava como
-- abandonada: o worker seguinte roubava na hora, com o primeiro ainda enviando.
-- Não é corrida rara — é o comportamento normal de qualquer linha que passou
-- dez minutos na fila. Agora a janela mede `lease_expira_em`, carimbado NA
-- REIVINDICAÇÃO.
--
-- ⚠️ SEM TOKEN NÃO HÁ CERCA
--
-- Expirar o lease libera a linha mas não desarma o worker velho: ele volta do
-- timeout e escreve 'enviada' por cima de quem já enviou, sem deixar rastro. As
-- RPCs de conclusão passam a exigir o token.
--
-- ⚠️ O CORTE ENTRE WORKER ANTIGO E NOVO (revisão do Alfredo, e ele está certo)
--
-- A primeira versão desta migration aceitava `p_lease_token is null` como
-- "modo legado" **sem olhar a linha**. Isso não é compatibilidade, é bypass: o
-- worker antigo poderia concluir uma linha que o worker novo tinha acabado de
-- reivindicar, e a cerca inteira viraria enfeite.
--
-- A regra correta é a que ele cravou: **token nulo só vale em linha sem token.**
--
--     (p_lease_token is null and lease_token is null)   -- legado com legado
--     or (lease_token = p_lease_token and lease_expira_em > now())
--
-- Só que isso, sozinho, quebraria o briefing: se as duas RPCs de claim
-- passassem a gravar token, TODA linha teria token e o worker antigo — que não
-- manda token — nunca mais concluiria nada. Por isso quem emite token é
-- explícito:
--
--   • fabio_claim_notificacao_por_referencia  → SEMPRE emite (nasce agora, só o
--     worker novo consome; não há legado pra proteger);
--   • fabio_claim_notificacao (briefing)      → emite só com `p_com_token=true`.
--     O worker em produção não passa esse parâmetro, então continua em linha
--     sem token e continua funcionando. O worker novo passa, e a partir daí
--     aquela linha fica cercada — inclusive contra o antigo.
--
-- O corte é por linha, não por data: cada notificação passa a ser cercada no
-- instante em que um worker que entende token a reivindica. Não existe janela
-- em que uma linha esteja com token e desprotegida.
--
-- ⚠️ E o corte precisa valer nos DOIS lados — finalização E claim. A primeira
-- versão só cercava a finalização, o que deixava um bypass em duas etapas:
-- worker novo cerca (token A) → a linha falha ou o lease vence → worker antigo
-- reivindica → o `DO UPDATE` grava `lease_token = null` e **desarma a cerca**;
-- daí ele conclui numa boa, porque a finalização aceita token nulo em linha sem
-- token. Por isso o claim legado é barrado em linha já tokenizada (a "catraca",
-- lá embaixo). Cercar só a saída não adianta se a entrada devolve a chave.
--
-- Fase 2, depois do worker novo no ar: `p_com_token` vira default true e o
-- caminho de token nulo é removido. O conserto do relógio vale desde já pra
-- todo mundo, com ou sem token.
--
-- ⚠️ ÍNDICE ÚNICO E `ON CONFLICT` SÃO UM CONTRATO SÓ. Em 03/08/2026 o briefing
--    parou inteiro (42P10) porque o índice mudou e a RPC ficou na chave antiga.
--    Aqui entra índice novo E RPC nova, juntos.

-- ⚠️ DOIS LANDMINES QUE SÓ APARECERAM RODANDO O TESTE
--
-- 1. `create or replace function` com PARÂMETRO NOVO não substitui: **cria uma
--    sobrecarga**. As duas versões passam a existir, e toda chamada com a
--    aridade antiga vira ambígua — `42725: function ... is not unique`. Aplicar
--    sem os DROPs abaixo derrubaria o briefing na hora. Por isso a assinatura
--    velha é removida explicitamente antes.
--
-- 2. DROP leva os GRANTS junto. Estas funções são executadas por `service_role`
--    e `fabio_agent` (o worker). Sem re-conceder no fim desta migration, o
--    worker passa a tomar "permission denied" — falha diferente, mesmo
--    resultado: professor sem briefing.

-- =====================================================================================
-- 0) Remove as assinaturas antigas. Ver landmine 1.
-- =====================================================================================
drop function if exists public.fabio_claim_notificacao(integer, text, text, text, text, text);
drop function if exists public.fabio_marcar_notificacao_enviada(uuid);
drop function if exists public.fabio_marcar_notificacao_falhou(uuid, text);

-- =====================================================================================
-- 1) Colunas do lease. Aditivas e nullable: nenhuma linha existente quebra.
-- =====================================================================================
alter table public.fabio_notificacoes
  add column if not exists lease_token          uuid,
  add column if not exists lease_expira_em      timestamptz,
  add column if not exists proxima_tentativa_em timestamptz,
  add column if not exists envio_recibo         text;

comment on column public.fabio_notificacoes.lease_token is
  'Dono da tentativa de entrega. Toda escrita de conclusão exige este token (spec §7.5).';
comment on column public.fabio_notificacoes.lease_expira_em is
  'Prazo do lease, carimbado NA REIVINDICAÇÃO. Antes a janela media criado_em — ver cabeçalho.';
comment on column public.fabio_notificacoes.envio_recibo is
  'Id da mensagem devolvido pelo canal. É ele que prova que saiu, independente da escrita seguinte ter dado certo.';

-- Linhas antigas ainda em 'processando' não têm lease. Sem isto elas ficariam
-- presas pra sempre (lease_expira_em null nunca vence). Dá a elas um prazo já
-- vencido: continuam reivindicáveis, como eram antes.
update public.fabio_notificacoes
   set lease_expira_em = coalesce(criado_em, now()) + interval '10 minutes'
 where status = 'processando' and lease_expira_em is null;

-- =====================================================================================
-- 1b) O tipo novo precisa caber no CHECK. Descoberto testando: sem isto o claim
--     falha com 23514 na primeira devolutiva. `categoria` continua servindo
--     ('informativa'), só `tipo` estava fechado.
-- =====================================================================================
alter table public.fabio_notificacoes
  drop constraint if exists fabio_notificacoes_tipo_check;

alter table public.fabio_notificacoes
  add constraint fabio_notificacoes_tipo_check
  check (tipo = any (array[
    'briefing_matinal','pendencia_registro','experimental_nova',
    'reagendamento','outro',
    'devolutiva_pronta',      -- <<< 018: a oferta da devolutiva ao professor
    'devolutiva_destinatario' -- <<< 018: "pra quem é essa devolutiva?" (spec §4.5)
  ]));

-- =====================================================================================
-- 2) Chave por REFERÊNCIA — para notificação que não é "uma por professor/dia".
--    A devolutiva é por aluno: o mesmo professor tem várias no mesmo dia, e a
--    chave atual (professor, tipo, dia, canal) engoliria da segunda em diante.
-- =====================================================================================
create unique index if not exists uq_fabio_notif_por_referencia
  on public.fabio_notificacoes (referencia_tipo, referencia_id, canal)
  where referencia_tipo is not null and referencia_id is not null;

comment on index public.uq_fabio_notif_por_referencia is
  'Uma notificação por (referência, canal). Par obrigatório do ON CONFLICT de fabio_claim_notificacao_por_referencia — mexeu num, mexe no outro.';

-- =====================================================================================
-- 3) Claim por referência. RPC PRÓPRIA, e não um parâmetro na existente, porque
--    um INSERT tem UM alvo de conflito — as duas chaves são incompatíveis.
-- =====================================================================================
create or replace function public.fabio_claim_notificacao_por_referencia(
  p_professor_id   integer,
  p_tipo           text,
  p_categoria      text,
  p_canal          text,
  p_corpo          text,
  p_referencia_tipo text,
  p_referencia_id  text,
  p_titulo         text default null,
  p_lease_minutos  integer default 10
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_id    uuid;
  v_token uuid := gen_random_uuid();
begin
  if p_referencia_tipo is null or p_referencia_id is null then
    raise exception 'referencia_tipo e referencia_id são obrigatórios neste claim';
  end if;

  insert into public.fabio_notificacoes
    (professor_id, tipo, categoria, canal, corpo, titulo,
     referencia_tipo, referencia_id,
     status, tentativas, lease_token, lease_expira_em)
  values
    (p_professor_id, p_tipo, p_categoria, p_canal, p_corpo, p_titulo,
     p_referencia_tipo, p_referencia_id,
     'processando', 1, v_token, now() + make_interval(mins => p_lease_minutos))
  on conflict (referencia_tipo, referencia_id, canal)
    where referencia_tipo is not null and referencia_id is not null
  do update set
    status               = 'processando',
    tentativas           = fabio_notificacoes.tentativas + 1,
    corpo                = excluded.corpo,   -- reprocessa com conteúdo fresco
    titulo               = excluded.titulo,
    lease_token          = excluded.lease_token,
    lease_expira_em      = excluded.lease_expira_em,
    last_error           = null
  where
    -- falhou: pode tentar de novo, respeitando o backoff
    (fabio_notificacoes.status = 'falhou'
      and (fabio_notificacoes.proxima_tentativa_em is null
           or fabio_notificacoes.proxima_tentativa_em <= now()))
    -- ou: o dono anterior sumiu. A janela mede o LEASE, não a criação.
    or (fabio_notificacoes.status = 'processando'
      and fabio_notificacoes.lease_expira_em is not null
      and fabio_notificacoes.lease_expira_em < now())
  returning id into v_id;

  if v_id is null then
    -- já enviada nesse canal, ou outro worker está com o lease VIVO agora
    return jsonb_build_object('ok', true, 'claimed', false);
  end if;
  return jsonb_build_object('ok', true, 'claimed', true,
                            'notificacao_id', v_id, 'lease_token', v_token);
end;
$function$;

comment on function public.fabio_claim_notificacao_por_referencia is
  'Claim de notificação chaveada por referência (ex.: uma devolutiva). Devolve lease_token — quem conclui precisa dele.';

-- =====================================================================================
-- 4) A RPC do briefing: mesma correção de relógio + token no retorno.
--    O corpo é o ATUAL, verbatim, com as mudanças marcadas  -- <<< 018
-- =====================================================================================
create or replace function public.fabio_claim_notificacao(
  p_professor_id integer,
  p_tipo         text,
  p_categoria    text,
  p_canal        text,
  p_corpo        text,
  p_titulo       text default null,
  p_com_token    boolean default false   -- <<< 018: ver "O CORTE" no cabeçalho
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_id    uuid;
  -- null quando o chamador não entende token: a linha fica sem token e o worker
  -- antigo consegue concluí-la. Quem passa p_com_token cerca a linha na hora.
  v_token uuid := case when p_com_token then gen_random_uuid() else null end;  -- <<< 018
begin
  insert into public.fabio_notificacoes
    (professor_id, tipo, categoria, canal, corpo, titulo, status, tentativas,
     lease_token, lease_expira_em)                                    -- <<< 018
  values
    (p_professor_id, p_tipo, p_categoria, p_canal, p_corpo, p_titulo, 'processando', 1,
     v_token, now() + interval '10 minutes')                          -- <<< 018
  on conflict (professor_id, tipo, dia_referencia, canal)
    where tipo in ('briefing_matinal','pendencia_registro')
  do update set
    status          = 'processando',
    tentativas      = fabio_notificacoes.tentativas + 1,
    corpo           = excluded.corpo,   -- reprocessa com conteudo fresco, nao o congelado da 1a tentativa
    titulo          = excluded.titulo,
    canal           = excluded.canal,
    lease_token     = excluded.lease_token,                           -- <<< 018
    lease_expira_em = excluded.lease_expira_em,                       -- <<< 018
    last_error      = null
  where
    -- <<< 018: A CATRACA. Linha já cercada só volta pra quem entende token.
    --
    -- Sem esta condição existia um bypass em duas etapas: o worker novo cercava
    -- (token A), a linha falhava ou o lease vencia, e aí o worker antigo
    -- reivindicava de novo — o `lease_token = excluded.lease_token` acima
    -- gravaria NULL e **removeria a cerca**. Em seguida ele concluiria numa boa,
    -- porque a finalização aceita token nulo em linha sem token. O corte da
    -- finalização estava certo; a porta aberta era o claim.
    --
    -- É de mão única de propósito: uma vez cercada, a linha não rebaixa
    -- sozinha. Se algum dia o worker novo sair de operação, a saída é explícita
    -- e humana (`update ... set lease_token = null`), não um efeito colateral.
    (p_com_token or fabio_notificacoes.lease_token is null)
    and (
      fabio_notificacoes.status = 'falhou'
      -- <<< 018: era `criado_em < now() - interval '10 minutes'`, que mede a hora
      --          em que a LINHA NASCEU. Agora mede o prazo do lease, carimbado
      --          na reivindicação. Ver o cabeçalho desta migration.
      or (fabio_notificacoes.status = 'processando'
          and fabio_notificacoes.lease_expira_em is not null
          and fabio_notificacoes.lease_expira_em < now())
    )
  returning id into v_id;

  if v_id is null then
    return jsonb_build_object('ok', true, 'claimed', false);  -- ja enviado nesse canal, ou outro worker processando agora
  end if;
  return jsonb_build_object('ok', true, 'claimed', true,
                            'notificacao_id', v_id, 'lease_token', v_token);  -- <<< 018
end;
$function$;

-- =====================================================================================
-- 5) Conclusão cercada. `p_lease_token` tem DEFAULT null só para o worker que
--    está em produção AGORA não quebrar entre esta migration e o deploy dele.
--    Quando o token vem, ele manda: sem token vigente, zero linhas afetadas.
-- =====================================================================================
create or replace function public.fabio_marcar_notificacao_enviada(
  p_notificacao_id uuid,
  p_lease_token    uuid default null,
  p_recibo         text default null
)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_n integer;
begin
  update public.fabio_notificacoes
     set status       = 'enviada',
         enviada_em   = now(),
         envio_recibo = coalesce(p_recibo, envio_recibo)
   where id = p_notificacao_id
     and status = 'processando'
     -- O corte: token nulo SÓ vale em linha sem token. Assim que um worker que
     -- entende token reivindica, o antigo não alcança mais aquela linha.
     and ((p_lease_token is null and lease_token is null)
          or (p_lease_token is not null
              and lease_token = p_lease_token
              and lease_expira_em > now()));
  get diagnostics v_n = row_count;
  -- false = o trabalho não é mais meu (lease venceu, ou outro worker concluiu).
  -- Quem chamou deve DESCARTAR o que fez, não insistir.
  return v_n > 0;
end;
$function$;

create or replace function public.fabio_marcar_notificacao_falhou(
  p_notificacao_id uuid,
  p_erro           text,
  p_lease_token    uuid default null,
  p_backoff_segundos integer default 0
)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_n integer;
begin
  update public.fabio_notificacoes
     set status               = 'falhou',
         last_error           = p_erro,
         proxima_tentativa_em = case when p_backoff_segundos > 0
                                     then now() + make_interval(secs => p_backoff_segundos)
                                     else proxima_tentativa_em end
   where id = p_notificacao_id
     and status = 'processando'
     -- Mesmo corte da RPC de sucesso: token nulo só vale em linha sem token.
     and ((p_lease_token is null and lease_token is null)
          or (p_lease_token is not null
              and lease_token = p_lease_token
              and lease_expira_em > now()));
  get diagnostics v_n = row_count;
  return v_n > 0;
end;
$function$;

comment on function public.fabio_marcar_notificacao_enviada is
  'Conclui a entrega. Devolve false quando o lease não é mais do chamador — nesse caso, descartar o trabalho, não reenviar.';

-- =====================================================================================
-- 6) Grants de volta. Ver landmine 2 — o DROP levou os originais
--    ({postgres, service_role, fabio_agent}), e sem isto o worker toma
--    "permission denied" na primeira execução.
-- =====================================================================================
grant execute on function
  public.fabio_claim_notificacao(integer, text, text, text, text, text, boolean),
  public.fabio_claim_notificacao_por_referencia(integer, text, text, text, text, text, text, text, integer),
  public.fabio_marcar_notificacao_enviada(uuid, uuid, text),
  public.fabio_marcar_notificacao_falhou(uuid, text, uuid, integer)
to service_role, fabio_agent;
