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

select n, passo, esperado, obtido,
       case when esperado = obtido then 'PASSOU' else '*** FALHOU ***' end as veredito
from res order by n;

rollback;
