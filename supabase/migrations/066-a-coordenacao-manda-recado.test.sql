-- 066 (teste) — a coordenação manda recado
--
-- Estas funções ESCREVEM. Toda chamada acontece dentro de um bloco, guardada
-- numa variável, e só então é medida. Chamar função que escreve dentro de um
-- `WHERE` faz a asserção ler o snapshot de ANTES da chamada, e o passo passa
-- dos dois jeitos — já mordeu duas vezes (056, 057).

create temp table _res(passo text, esperado text, obtido text) on commit drop;

-- Contexto: um coordenador de verdade e um professor que AINDA não foi cobrado
-- hoje (senão a reserva bate na dedupe e o passo mede a coisa errada).
create temp table _ctx on commit drop as
select
  (select u.auth_user_id
     from public.la_teacher_coordenacao c
     join public.usuarios u on u.id = c.usuario_id
    where u.auth_user_id is not null and coalesce(u.ativo, true)
    limit 1) as coord,
  (select p.id
     from public.professores p
    where p.ativo
      and nullif(regexp_replace(coalesce(p.telefone_whatsapp,''), '\D', '', 'g'), '') is not null
      and not exists (
        select 1 from public.fabio_notificacoes n
         where n.professor_id = p.id
           and n.tipo = 'pendencia_registro'
           and n.dia_referencia = current_date
           and n.canal = 'whatsapp')
    order by p.id
    limit 1) as prof;

insert into _res select 'ancora: ha coordenador e professor cobravel', 'sim',
  (select case when coord is not null and prof is not null then 'sim'
               else 'NAO — coord=' || coalesce(coord::text,'null')
                    || ' prof=' || coalesce(prof::text,'null') end from _ctx);

-- ───────────────────────────────────────────────────────────────────────────
-- Quem não é coordenação não manda recado — nem sendo service_role.
-- ───────────────────────────────────────────────────────────────────────────
do $$
declare v_erro text := 'nao levantou';
begin
  begin
    perform public.fn_reservar_recado_coordenacao(
      (select prof from _ctx), 'Recado de teste', gen_random_uuid());
  exception when others then v_erro := sqlerrm; end;
  insert into _res values ('autor fora da coordenacao e recusado', 'sim',
    case when v_erro like '%apenas_admin%' then 'sim' else 'NAO — ' || v_erro end);
end $$;

-- ───────────────────────────────────────────────────────────────────────────
-- Recado vazio e professor inexistente
-- ───────────────────────────────────────────────────────────────────────────
do $$
declare v_erro text := 'nao levantou';
begin
  begin
    perform public.fn_reservar_recado_coordenacao(
      (select prof from _ctx), '  ', (select coord from _ctx));
  exception when others then v_erro := sqlerrm; end;
  insert into _res values ('recado vazio e recusado', 'sim',
    case when v_erro like '%recado_vazio%' then 'sim' else 'NAO — ' || v_erro end);
end $$;

do $$
declare v_erro text := 'nao levantou';
begin
  begin
    perform public.fn_reservar_recado_coordenacao(
      -999, 'Recado de teste', (select coord from _ctx));
  exception when others then v_erro := sqlerrm; end;
  insert into _res values ('professor inexistente e recusado', 'sim',
    case when v_erro like '%professor_inexistente%' then 'sim' else 'NAO — ' || v_erro end);
end $$;

-- ───────────────────────────────────────────────────────────────────────────
-- A reserva: uma linha, em processando, com autor e lease.
-- ───────────────────────────────────────────────────────────────────────────
create temp table _reserva(j jsonb) on commit drop;

do $$
declare v_j jsonb; v_antes int; v_depois int;
begin
  select count(*) into v_antes from public.fabio_notificacoes
   where professor_id = (select prof from _ctx);

  v_j := public.fn_reservar_recado_coordenacao(
           (select prof from _ctx),
           'Oi! Ficaram lancamentos em aberto na sua agenda.',
           (select coord from _ctx));
  insert into _reserva values (v_j);

  select count(*) into v_depois from public.fabio_notificacoes
   where professor_id = (select prof from _ctx);

  insert into _res values ('a reserva diz que reservou', 'true',
    coalesce(v_j->>'reservado', 'null'));
  insert into _res values ('a reserva gravou exatamente 1 linha', '1',
    (v_depois - v_antes)::text);
end $$;

insert into _res select 'a linha nasce em processando', 'processando',
  (select n.status from public.fabio_notificacoes n, _reserva r
    where n.id = (r.j->>'notificacao_id')::uuid);

insert into _res select 'a linha guarda QUEM pediu', (select coord::text from _ctx),
  (select n.solicitado_por::text from public.fabio_notificacoes n, _reserva r
    where n.id = (r.j->>'notificacao_id')::uuid);

insert into _res select 'a linha e governanca no whatsapp pro professor',
  'governanca|whatsapp|professor|pendencia_registro',
  (select n.categoria || '|' || n.canal || '|' || n.destinatario_tipo || '|' || n.tipo
     from public.fabio_notificacoes n, _reserva r
    where n.id = (r.j->>'notificacao_id')::uuid);

insert into _res select 'a reserva devolve o telefone pra quem vai enviar', 'sim',
  (select case when coalesce(r.j->>'telefone','') ~ '^[0-9]{10,15}$' then 'sim'
               else 'NAO — ' || coalesce(r.j->>'telefone','null') end from _reserva r);

-- ───────────────────────────────────────────────────────────────────────────
-- Segundo pedido no mesmo dia NÃO vira segunda mensagem.
-- ───────────────────────────────────────────────────────────────────────────
do $$
declare v_j jsonb; v_antes int; v_depois int;
begin
  select count(*) into v_antes from public.fabio_notificacoes
   where professor_id = (select prof from _ctx);

  v_j := public.fn_reservar_recado_coordenacao(
           (select prof from _ctx), 'Segundo recado do mesmo dia',
           (select coord from _ctx));

  select count(*) into v_depois from public.fabio_notificacoes
   where professor_id = (select prof from _ctx);

  insert into _res values ('o 2o pedido do dia e recusado', 'ja_cobrado_hoje',
    coalesce(v_j->>'motivo', 'null'));
  insert into _res values ('o 2o pedido do dia NAO grava linha nova', '0',
    (v_depois - v_antes)::text);
end $$;

-- ───────────────────────────────────────────────────────────────────────────
-- A conclusão. O lease prova que quem fecha é quem reservou.
-- ───────────────────────────────────────────────────────────────────────────
do $$
declare v_j jsonb;
begin
  v_j := public.fn_concluir_recado_coordenacao(
           (select (j->>'notificacao_id')::uuid from _reserva),
           gen_random_uuid(),   -- lease errado
           true, 'recibo-falso');
  insert into _res values ('concluir com lease errado nao fecha nada', 'false',
    coalesce(v_j->>'concluida','null'));
end $$;

insert into _res select 'e a linha continua em processando', 'processando',
  (select n.status from public.fabio_notificacoes n, _reserva r
    where n.id = (r.j->>'notificacao_id')::uuid);

do $$
declare v_j jsonb;
begin
  v_j := public.fn_concluir_recado_coordenacao(
           (select (j->>'notificacao_id')::uuid from _reserva),
           (select (j->>'lease_token')::uuid from _reserva),
           true, 'recibo-de-teste-123');
  insert into _res values ('concluir com o lease certo fecha', 'true',
    coalesce(v_j->>'concluida','null'));
end $$;

insert into _res select 'a linha vira enviada com recibo', 'enviada|recibo-de-teste-123',
  (select n.status || '|' || coalesce(n.envio_recibo,'sem recibo')
     from public.fabio_notificacoes n, _reserva r
    where n.id = (r.j->>'notificacao_id')::uuid);

insert into _res select 'e o lease e devolvido', 'sim',
  (select case when n.lease_token is null then 'sim' else 'NAO — lease preso' end
     from public.fabio_notificacoes n, _reserva r
    where n.id = (r.j->>'notificacao_id')::uuid);

-- ───────────────────────────────────────────────────────────────────────────
-- Nenhuma das duas é do navegador.
-- ───────────────────────────────────────────────────────────────────────────
insert into _res select 'anon NAO reserva recado', 'sim',
  (select case when has_function_privilege('anon',
       'public.fn_reservar_recado_coordenacao(int, text, uuid)', 'execute')
     then 'NAO — anon pode' else 'sim' end);

insert into _res select 'authenticated NAO reserva recado', 'sim',
  (select case when has_function_privilege('authenticated',
       'public.fn_reservar_recado_coordenacao(int, text, uuid)', 'execute')
     then 'NAO — authenticated pode (o navegador forjaria o autor)' else 'sim' end);

insert into _res select 'authenticated NAO conclui recado', 'sim',
  (select case when has_function_privilege('authenticated',
       'public.fn_concluir_recado_coordenacao(uuid, uuid, boolean, text, text)', 'execute')
     then 'NAO — authenticated pode' else 'sim' end);

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
