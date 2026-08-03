-- Teste de concorrência da migration 018.
--
-- ⚠️ ESTE TESTE NÃO ABORTA — DE PROPÓSITO.
--
--    A versão anterior levantava exceção na divergência. Isso dava rc correto,
--    mas deixava a transação em estado abortado e o ROLLBACK dependendo de
--    cleanup implícito da conexão — que a Management API não promete. Ou seja:
--    exatamente no caminho de falha, DDL e locks numa tabela viva
--    (fabio_notificacoes, que o briefing usa) ficavam por conta da sorte.
--
--    Agora `pg_temp.checar()` REGISTRA a divergência numa temp table, o teste
--    segue até o fim, o ROLLBACK executa normalmente e o resumo estruturado sai
--    no último SELECT. Quem reprova é o runner, lendo esse resumo — e ele ainda
--    confere, numa SEGUNDA conexão, que nada sobrou.
--
-- Rodar com:  npm run teste:018
--   (= node scripts/rodar-teste-sql.mjs <migration>.sql <este arquivo>)
--
-- O runner é DONO da transação (BEGIN/ROLLBACK). Este arquivo não abre nem
-- fecha transação de propósito: assim não existe a versão dele em que alguém
-- esqueceu o rollback e escreveu em produção.
--
-- Por que os cenários são separados: o `DO UPDATE` do claim tem DUAS portas —
-- status 'falhou' e lease vencido. Um teste que abre as duas de uma vez não diz
-- por qual delas o worker legado entrou. A catraca tem que segurar as duas
-- sozinhas, então cada uma tem seu cenário.

create temp table _falhas(passo text, esperado text, obtido text) on commit drop;

create function pg_temp.checar(p_passo text, p_esperado text, p_obtido text)
returns void language plpgsql as $c$
begin
  if p_esperado is distinct from p_obtido then
    insert into _falhas values (p_passo, coalesce(p_esperado,'(null)'), coalesce(p_obtido,'(null)'));
  end if;
end $c$;

-- ============================================================================
-- PARTE 1 — o relógio do claim
--
-- O passo 3 é a regressão do bug que a 018 conserta: com a regra antiga
-- (`criado_em < now() - 10 min`) ele devolveria claimed=true.
-- ============================================================================
do $t$
declare
  a jsonb; b jsonb; c jsonb; d jsonb;
  v_id uuid; v_tok uuid; v_tok2 uuid; v_prof integer := 25;   -- Matheus (piloto)
begin
  a := public.fabio_claim_notificacao_por_referencia(
        v_prof,'devolutiva_pronta','informativa','whatsapp','corpo A','devolutiva','teste-r1');
  v_id := (a->>'notificacao_id')::uuid;
  v_tok := (a->>'lease_token')::uuid;
  perform pg_temp.checar('1. worker A reivindica','true',a->>'claimed');

  b := public.fabio_claim_notificacao_por_referencia(
        v_prof,'devolutiva_pronta','informativa','whatsapp','corpo B','devolutiva','teste-r1');
  perform pg_temp.checar('2. worker B com lease de A vivo','false',b->>'claimed');

  -- ===== REGRESSÃO DO RELÓGIO =====
  update public.fabio_notificacoes set criado_em = now() - interval '20 minutes' where id=v_id;
  c := public.fabio_claim_notificacao_por_referencia(
        v_prof,'devolutiva_pronta','informativa','whatsapp','corpo C','devolutiva','teste-r1');
  perform pg_temp.checar('3. linha velha + lease vivo','false',c->>'claimed');

  update public.fabio_notificacoes set lease_expira_em = now() - interval '1 second' where id=v_id;
  d := public.fabio_claim_notificacao_por_referencia(
        v_prof,'devolutiva_pronta','informativa','whatsapp','corpo D','devolutiva','teste-r1');
  v_tok2 := (d->>'lease_token')::uuid;
  perform pg_temp.checar('4. lease vencido: novo dono assume','true',d->>'claimed');

  perform pg_temp.checar('5. dono anterior nao conclui','false',
    public.fabio_marcar_notificacao_enviada(v_id, v_tok, 'recibo-do-velho')::text);
  perform pg_temp.checar('6. dono atual conclui','true',
    public.fabio_marcar_notificacao_enviada(v_id, v_tok2, 'wamid.NOVO')::text);
  perform pg_temp.checar('7. recibo do canal gravado','wamid.NOVO',
    (select envio_recibo from public.fabio_notificacoes where id=v_id));
  perform pg_temp.checar('8. tentativas contadas','2',
    (select tentativas::text from public.fabio_notificacoes where id=v_id));
exception when others then
  -- Exceção inesperada também é falha — mas registrada, não propagada, pra não
  -- abortar a transação e devolver o ROLLBACK pra sorte.
  insert into _falhas values ('PARTE 1 (excecao)','sem excecao', sqlerrm);
end $t$;

-- ============================================================================
-- PARTE 2 — o corte na FINALIZAÇÃO entre worker antigo e novo
-- ============================================================================
do $t$
declare a jsonb; b jsonb; v_id uuid; v_tok uuid; v_prof integer := 25;
begin
  -- O briefing de hoje existe e está 'enviada' — o claim recusaria, com razão.
  -- Some com ele SÓ DENTRO DESTA TRANSAÇÃO, que termina em ROLLBACK.
  delete from public.fabio_notificacoes
   where professor_id=v_prof and tipo='briefing_matinal' and dia_referencia=current_date;

  a := public.fabio_claim_notificacao(v_prof,'briefing_matinal','informativa','app','corpo legado');
  v_id := (a->>'notificacao_id')::uuid;
  perform pg_temp.checar('11. legado reivindica','true',a->>'claimed');
  perform pg_temp.checar('12. linha do legado fica SEM token','true',
    (select (lease_token is null)::text from public.fabio_notificacoes where id=v_id));
  perform pg_temp.checar('13. legado conclui a propria linha','true',
    public.fabio_marcar_notificacao_enviada(v_id)::text);

  update public.fabio_notificacoes set status='falhou' where id=v_id;
  b := public.fabio_claim_notificacao(v_prof,'briefing_matinal','informativa','app','corpo novo',
        null, true);
  v_tok := (b->>'lease_token')::uuid;
  perform pg_temp.checar('14. worker novo reivindica com token','true',b->>'claimed');
  perform pg_temp.checar('15. agora a linha TEM token','true',
    (select (lease_token is not null)::text from public.fabio_notificacoes where id=v_id));

  -- ===== BYPASS PELA FINALIZAÇÃO =====
  perform pg_temp.checar('16. legado conclui linha cercada','false',
    public.fabio_marcar_notificacao_enviada(v_id)::text);
  perform pg_temp.checar('17. token errado nao conclui','false',
    public.fabio_marcar_notificacao_enviada(v_id, gen_random_uuid(), 'wamid.INTRUSO')::text);
  perform pg_temp.checar('18. dono com token conclui','true',
    public.fabio_marcar_notificacao_enviada(v_id, v_tok, 'wamid.OK')::text);
exception when others then
  insert into _falhas values ('PARTE 2 (excecao)','sem excecao', sqlerrm);
end $t$;

-- ============================================================================
-- PARTE 3A — catraca do CLAIM, porta 'falhou' com o lease AINDA VIVO
-- ============================================================================
do $t$
declare a jsonb; b jsonb; c jsonb; v_id uuid; v_tokA uuid; v_tokB uuid; v_prof integer := 25;
begin
  delete from public.fabio_notificacoes
   where professor_id=v_prof and tipo='briefing_matinal' and dia_referencia=current_date;

  a := public.fabio_claim_notificacao(v_prof,'briefing_matinal','informativa','app','A1',null,true);
  v_id := (a->>'notificacao_id')::uuid;
  v_tokA := (a->>'lease_token')::uuid;
  perform pg_temp.checar('31A. novo cerca','true',a->>'claimed');

  -- SÓ o status muda: lease continua vivo
  update public.fabio_notificacoes set status='falhou' where id=v_id;
  perform pg_temp.checar('32A. lease ainda vivo','true',
    (select (lease_expira_em > now())::text from public.fabio_notificacoes where id=v_id));

  b := public.fabio_claim_notificacao(v_prof,'briefing_matinal','informativa','app','A2');
  perform pg_temp.checar('33A. legado reivindica linha cercada','false',b->>'claimed');
  perform pg_temp.checar('34A. token NAO foi rebaixado', v_tokA::text,
    (select lease_token::text from public.fabio_notificacoes where id=v_id));
  perform pg_temp.checar('35A. status intacto','falhou',
    (select status from public.fabio_notificacoes where id=v_id));

  c := public.fabio_claim_notificacao(v_prof,'briefing_matinal','informativa','app','A3',null,true);
  v_tokB := (c->>'lease_token')::uuid;
  perform pg_temp.checar('36A. novo retoma','true',c->>'claimed');
  perform pg_temp.checar('37A. token trocou','true',(v_tokA is distinct from v_tokB)::text);
  perform pg_temp.checar('38A. legado ainda nao conclui','false',
    public.fabio_marcar_notificacao_enviada(v_id)::text);
  perform pg_temp.checar('39A. dono atual conclui','true',
    public.fabio_marcar_notificacao_enviada(v_id, v_tokB, 'wamid.A')::text);
exception when others then
  insert into _falhas values ('PARTE 3A (excecao)','sem excecao', sqlerrm);
end $t$;

-- ============================================================================
-- PARTE 3B — catraca do CLAIM, porta 'processando' com o lease VENCIDO
-- ============================================================================
do $t$
declare a jsonb; b jsonb; c jsonb; v_id uuid; v_tokA uuid; v_tokB uuid; v_prof integer := 25;
begin
  delete from public.fabio_notificacoes
   where professor_id=v_prof and tipo='briefing_matinal' and dia_referencia=current_date;

  a := public.fabio_claim_notificacao(v_prof,'briefing_matinal','informativa','app','B1',null,true);
  v_id := (a->>'notificacao_id')::uuid;
  v_tokA := (a->>'lease_token')::uuid;
  perform pg_temp.checar('31B. novo cerca','true',a->>'claimed');

  -- SÓ o prazo vence: status continua 'processando'
  update public.fabio_notificacoes set lease_expira_em = now() - interval '1 minute' where id=v_id;
  perform pg_temp.checar('32B. status continua processando','processando',
    (select status from public.fabio_notificacoes where id=v_id));

  b := public.fabio_claim_notificacao(v_prof,'briefing_matinal','informativa','app','B2');
  perform pg_temp.checar('33B. legado reivindica linha cercada','false',b->>'claimed');
  perform pg_temp.checar('34B. token NAO foi rebaixado', v_tokA::text,
    (select lease_token::text from public.fabio_notificacoes where id=v_id));

  c := public.fabio_claim_notificacao(v_prof,'briefing_matinal','informativa','app','B3',null,true);
  v_tokB := (c->>'lease_token')::uuid;
  perform pg_temp.checar('36B. novo retoma','true',c->>'claimed');
  perform pg_temp.checar('37B. token trocou','true',(v_tokA is distinct from v_tokB)::text);
  perform pg_temp.checar('38B. legado ainda nao conclui','false',
    public.fabio_marcar_notificacao_enviada(v_id)::text);
  perform pg_temp.checar('39B. dono atual conclui','true',
    public.fabio_marcar_notificacao_enviada(v_id, v_tokB, 'wamid.B')::text);
exception when others then
  insert into _falhas values ('PARTE 3B (excecao)','sem excecao', sqlerrm);
end $t$;

-- Resumo estruturado — é ESTE resultado que o runner lê pra decidir o rc.
-- A transação continua sadia aqui; o ROLLBACK do runner executa normalmente.
select json_build_object(
  'teste',  '018-notificacoes-lease-e-referencia',
  'falhas', (select count(*) from _falhas),
  'detalhe', coalesce((select json_agg(json_build_object(
                'passo', passo, 'esperado', esperado, 'obtido', obtido))
              from _falhas), '[]'::json)
) as resumo;
