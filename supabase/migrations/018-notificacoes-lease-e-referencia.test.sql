-- Teste de concorrência da migration 018. Roda em BEGIN/ROLLBACK: não deixa traço.
--
-- Por que existe: claim é código de concorrência, e concorrência não se testa
-- lendo. O passo 3 é o que importa — ele reproduz o bug que a 018 conserta e
-- prova que ele morreu. Com a regra antiga (`criado_em < now() - 10 min`), o
-- passo 3 devolveria claimed=true e o teste falharia.
--
-- Uso: aplicar a 018 e rodar este arquivo inteiro. Todas as linhas do resultado
-- final precisam dizer PASSOU.

begin;

create temp table res(n int, passo text, esperado text, obtido text) on commit drop;

do $t$
declare
  a jsonb; b jsonb; c jsonb; d jsonb;
  v_id uuid; v_tok uuid; v_tok2 uuid; ok1 boolean; ok2 boolean;
  v_prof integer := 25;   -- Matheus (piloto). Trocar se rodar em outra base.
begin
  -- worker A pega o trabalho
  a := public.fabio_claim_notificacao_por_referencia(
        v_prof,'devolutiva_pronta','informativa','whatsapp','corpo A','devolutiva','teste-r1');
  v_id := (a->>'notificacao_id')::uuid;
  v_tok := (a->>'lease_token')::uuid;
  insert into res values (1,'worker A reivindica','true',a->>'claimed');

  -- worker B chega logo depois: o lease de A está vivo, então não é dele
  b := public.fabio_claim_notificacao_por_referencia(
        v_prof,'devolutiva_pronta','informativa','whatsapp','corpo B','devolutiva','teste-r1');
  insert into res values (2,'worker B com lease de A vivo','false',b->>'claimed');

  -- ===== O PASSO QUE PROVA O CONSERTO =====
  -- Linha criada há 20 minutos, mas reivindicada agora. A regra antiga media
  -- `criado_em` e daria a linha por abandonada — o worker B roubaria com o A
  -- ainda enviando. A regra nova mede o lease.
  update public.fabio_notificacoes set criado_em = now() - interval '20 minutes' where id=v_id;
  c := public.fabio_claim_notificacao_por_referencia(
        v_prof,'devolutiva_pronta','informativa','whatsapp','corpo C','devolutiva','teste-r1');
  insert into res values (3,'REGRESSAO: linha velha + lease vivo','false',c->>'claimed');

  -- lease vence de verdade: aí sim outro worker pode assumir
  update public.fabio_notificacoes set lease_expira_em = now() - interval '1 second' where id=v_id;
  d := public.fabio_claim_notificacao_por_referencia(
        v_prof,'devolutiva_pronta','informativa','whatsapp','corpo D','devolutiva','teste-r1');
  v_tok2 := (d->>'lease_token')::uuid;
  insert into res values (4,'lease vencido: novo dono assume','true',d->>'claimed');

  -- a cerca: o worker velho volta do timeout e tenta concluir
  ok1 := public.fabio_marcar_notificacao_enviada(v_id, v_tok, 'recibo-do-velho');
  insert into res values (5,'worker velho conclui com token morto','false',ok1::text);

  -- o dono atual conclui e grava o recibo do canal
  ok2 := public.fabio_marcar_notificacao_enviada(v_id, v_tok2, 'wamid.NOVO');
  insert into res values (6,'dono atual conclui','true',ok2::text);

  insert into res select 7,'recibo do canal gravado','wamid.NOVO',envio_recibo
    from public.fabio_notificacoes where id=v_id;
  insert into res select 8,'tentativas contadas','2',tentativas::text
    from public.fabio_notificacoes where id=v_id;
end $t$;

-- ============================================================================
-- PARTE 2 — o corte entre worker antigo e novo (exigência do Alfredo)
--
-- "p_lease_token default null só pode ser aceito enquanto a linha também
--  estiver sem token. Senão a compatibilidade vira bypass de fencing."
--
-- O passo 6 é o que prova: o worker legado tenta concluir uma linha que o
-- worker novo cercou. Com a regra frouxa (`p_lease_token is null` sozinho),
-- ele conseguiria — e a cerca inteira seria enfeite.
-- ============================================================================

do $t$
declare a jsonb; b jsonb; v_id uuid; v_tok uuid; ok boolean;
        v_prof integer := 25;
begin
  -- O briefing de hoje já existe e está 'enviada' — o claim recusaria, com razão.
  -- Some com ele SÓ DENTRO DESTA TRANSAÇÃO, que termina em ROLLBACK.
  delete from public.fabio_notificacoes
   where professor_id=v_prof and tipo='briefing_matinal' and dia_referencia=current_date;

  -- worker ANTIGO: não conhece p_com_token, então a linha nasce sem token
  a := public.fabio_claim_notificacao(v_prof,'briefing_matinal','informativa','app','corpo legado');
  v_id := (a->>'notificacao_id')::uuid;
  insert into res values (11,'legado reivindica','true',a->>'claimed');
  insert into res select 12,'linha do legado fica SEM token','true',(lease_token is null)::text
    from public.fabio_notificacoes where id=v_id;
  ok := public.fabio_marcar_notificacao_enviada(v_id);
  insert into res values (13,'legado conclui a propria linha','true',ok::text);

  -- worker NOVO assume a mesma linha e cerca
  update public.fabio_notificacoes set status='falhou' where id=v_id;
  b := public.fabio_claim_notificacao(v_prof,'briefing_matinal','informativa','app','corpo novo',
        null, true);
  v_tok := (b->>'lease_token')::uuid;
  insert into res values (14,'worker novo reivindica com token','true',b->>'claimed');
  insert into res select 15,'agora a linha TEM token','true',(lease_token is not null)::text
    from public.fabio_notificacoes where id=v_id;

  -- ===== O BYPASS =====
  ok := public.fabio_marcar_notificacao_enviada(v_id);
  insert into res values (16,'BYPASS: legado conclui linha cercada','false',ok::text);

  ok := public.fabio_marcar_notificacao_enviada(v_id, gen_random_uuid(), 'wamid.INTRUSO');
  insert into res values (17,'token errado nao conclui','false',ok::text);

  ok := public.fabio_marcar_notificacao_enviada(v_id, v_tok, 'wamid.OK');
  insert into res values (18,'dono com token conclui','true',ok::text);
end $t$;

-- ============================================================================
-- PARTE 3 — o bypass em DUAS ETAPAS, pelo claim
--
-- A Parte 2 só cobria "legado tenta finalizar logo depois do novo cercar".
-- Faltava o caminho que estava realmente aberto: o legado REIVINDICANDO de
-- novo depois de falha/expiração. O `DO UPDATE` gravava lease_token = null e
-- desarmava a cerca; daí ele concluía numa boa.
--
-- Passos 22 e 23 são a prova: o legado é recusado E o token não é rebaixado.
-- Sem a catraca no claim, o 22 daria claimed=true e o 23 devolveria null.
-- ============================================================================

do $t$
declare a jsonb; b jsonb; c jsonb;
        v_id uuid; v_tokA uuid; v_tokB uuid; ok boolean;
        v_prof integer := 25;
begin
  delete from public.fabio_notificacoes
   where professor_id=v_prof and tipo='briefing_matinal' and dia_referencia=current_date;

  -- worker NOVO cerca a linha
  a := public.fabio_claim_notificacao(v_prof,'briefing_matinal','informativa','app','c1',null,true);
  v_id := (a->>'notificacao_id')::uuid;
  v_tokA := (a->>'lease_token')::uuid;
  insert into res values (21,'novo reivindica e cerca','true',a->>'claimed');

  -- a linha falha E o lease vence: as duas portas do DO UPDATE abertas
  update public.fabio_notificacoes
     set status='falhou', lease_expira_em = now() - interval '1 minute' where id=v_id;

  -- ===== O BYPASS EM DUAS ETAPAS =====
  b := public.fabio_claim_notificacao(v_prof,'briefing_matinal','informativa','app','c2');
  insert into res values (22,'legado reivindica linha cercada','false',b->>'claimed');
  insert into res select 23,'token NAO foi rebaixado', v_tokA::text, lease_token::text
    from public.fabio_notificacoes where id=v_id;
  insert into res select 24,'status intacto (legado nao mexeu)','falhou',status
    from public.fabio_notificacoes where id=v_id;

  -- só quem entende token retoma
  c := public.fabio_claim_notificacao(v_prof,'briefing_matinal','informativa','app','c3',null,true);
  v_tokB := (c->>'lease_token')::uuid;
  insert into res values (25,'novo retoma','true',c->>'claimed');
  insert into res values (26,'token trocou',(v_tokA is distinct from v_tokB)::text,'true');

  ok := public.fabio_marcar_notificacao_enviada(v_id);
  insert into res values (27,'legado conclui linha cercada','false',ok::text);
  ok := public.fabio_marcar_notificacao_enviada(v_id, v_tokA, 'wamid.VELHO');
  insert into res values (28,'token A (morto) conclui','false',ok::text);
  ok := public.fabio_marcar_notificacao_enviada(v_id, v_tokB, 'wamid.OK');
  insert into res values (29,'token B (vivo) conclui','true',ok::text);
end $t$;

select n, passo, esperado, obtido,
       case when esperado = obtido then 'PASSOU' else '*** FALHOU ***' end as veredito
from res order by n;

rollback;
