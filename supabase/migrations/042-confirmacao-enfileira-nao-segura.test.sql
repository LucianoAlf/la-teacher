-- Teste da 042 — depois de confirmar, o worker CONSEGUE pegar o aviso
--
-- O passo que importa e o 2: a 038 passava neste mesmo cenario com o aviso
-- preso por 10 minutos, porque nada no teste dela chegava a fazer o papel do
-- worker. Fila com dono errado nao levanta erro — so nao entrega.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000000420', 'ZZTESTE unidade 042', 'ZZTESTE042')
on conflict (id) do nothing;

insert into public.unidade_contato_comercial (unidade_id, nome, whatsapp)
values ('00000000-0000-4000-8000-000000000420', 'ZZTESTE Comercial 042', '5521900000042')
on conflict (unidade_id) do nothing;

insert into public.usuarios (id, nome, email, auth_user_id) values
  (-42901, 'ZZTESTE Usuario 042', 'zzteste-042@exemplo.invalido',
   '00000000-0000-4000-8000-000000042901');
insert into public.professores (id, nome, usuario_id) values (-42001, 'ZZTESTE Professor 042', -42901);
insert into public.leads (id, unidade_id, whatsapp, status) values
  (-42001, '00000000-0000-4000-8000-000000000420', '5521999420001', 'novo');
insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id)
values (-42001, -42001, 'ZZTESTE Enfileira', '00000000-0000-4000-8000-000000000420',
        current_date+1, '10:00', 'experimental_agendada', -42001);
insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, categoria, professor_id, cancelada)
values (-42001, -942001, '00000000-0000-4000-8000-000000000420', current_date+1,
   (current_date+1 + time '10:00') at time zone 'America/Sao_Paulo', 'experimental', -42001, false);
insert into public.lead_experimental_aulas (lead_experimental_id, aula_local_id, estado, casado_por)
values (-42001, -42001, 'vinculado', 'chave_natural');

create temp table _r(quem text, valor jsonb) on commit drop;

do $$
declare v_vinc bigint; v_reg uuid; v_conf jsonb; v_worker jsonb; v_worker2 jsonb;
begin
  select id into v_vinc from lead_experimental_aulas where lead_experimental_id=-42001;
  select public.fn_registrar_experimental_interno(v_vinc, 'trabalhou ritmo', 'foi bem',
           'seguir', 'quente') into v_reg;

  -- 1) o professor confirma na tela
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000042901"}', true);
  select public.app_confirmar_registro_experimental(v_reg, null) into v_conf;
  reset role;
  insert into _r values ('confirmacao', v_conf);

  -- 2) o worker chega pra entregar. E AQUI que a 038 travava.
  select public.fabio_claim_aviso_comercial(v_reg) into v_worker;
  insert into _r values ('worker', v_worker);

  -- 3) um segundo worker no mesmo instante NAO pode roubar o trabalho
  select public.fabio_claim_aviso_comercial(v_reg) into v_worker2;
  insert into _r values ('worker2', v_worker2);

  insert into _r values ('registro_id', to_jsonb(v_reg));
end $$;

-- ── O que a 042 conserta ──────────────────────────────────────────────────
insert into _res select 'o worker CONSEGUE reivindicar o aviso', 'true',
  (select coalesce(valor->>'claimed','(nulo)') from _r where quem='worker');

insert into _res select 'e recebe um lease_token pra fechar a linha depois', 'tem token',
  (select case when (valor->>'lease_token') is not null then 'tem token'
               else 'SEM TOKEN — nao consegue marcar como enviada' end
     from _r where quem='worker');

insert into _res select 'o lease do worker esta VIVO', 'sim',
  coalesce((select case when n.lease_expira_em > now() then 'sim' else 'nao' end
              from fabio_notificacoes n
             where n.referencia_tipo='lead_experimental_registro'
               and n.referencia_id = (select valor #>> '{}' from _r where quem='registro_id')),
           '(nenhum)');

insert into _res select 'um segundo worker NAO rouba o trabalho', 'false',
  (select coalesce(valor->>'claimed','(nulo)') from _r where quem='worker2');
insert into _res select 'e o segundo recebe o motivo certo', 'lease_vivo_ou_enviada',
  (select coalesce(valor->>'motivo','(nulo)') from _r where quem='worker2');

-- ── O que a 042 NAO pode ter quebrado ─────────────────────────────────────
insert into _res select 'a confirmacao segue enfileirando o aviso', 'true',
  (select coalesce(valor->>'aviso_claimed','(nulo)') from _r where quem='confirmacao');
insert into _res select 'a confirmacao segue gravando presenca', 'true',
  (select coalesce(valor->>'presenca_gravada','(nulo)') from _r where quem='confirmacao');
insert into _res select 'presenca continua de fonte forte', 'true',
  (select public.fn_presenca_e_forte(presenca_respondido_por)::text
     from lead_experimental_aulas where lead_experimental_id=-42001);
insert into _res select 'o registro ficou confirmado', 'confirmado',
  (select r.status from lead_experimental_registros r
     join lead_experimental_aulas v on v.id=r.vinculo_id
    where v.lead_experimental_id=-42001);
insert into _res select 'o aviso vai pro numero do comercial da unidade', '5521900000042',
  coalesce((select n.destinatario_whatsapp from fabio_notificacoes n
             where n.referencia_tipo='lead_experimental_registro'
               and n.referencia_id = (select valor #>> '{}' from _r where quem='registro_id')),
           '(nenhum)');
insert into _res select 'nao virou linha duplicada na fila', '1',
  (select count(*)::text from fabio_notificacoes n
    where n.referencia_tipo='lead_experimental_registro'
      and n.referencia_id = (select valor #>> '{}' from _r where quem='registro_id'));

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
