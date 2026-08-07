-- Teste da 048 — a correção se anuncia; a primeira entrega não
--
-- O par de passos que carrega peso é este:
--   a PRIMEIRA devolutiva NÃO pode se chamar correção
--   a SEGUNDA precisa
-- Sozinha, cada metade passaria com uma implementação idiota (sempre marcar,
-- ou nunca marcar). É o par que prende o comportamento.
--
-- E o terceiro caso é o que separa "registro" de "entrega": quem escreveu,
-- reescreveu e SÓ ENTÃO confirmou não corrigiu nada — ninguém recebeu a
-- primeira versão. Se a detecção olhasse registro em vez de entrega, a
-- primeira devolutiva dele chegaria marcada como correção do nada.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000000480', 'ZZTESTE unidade 048', 'ZZTESTE048')
on conflict (id) do nothing;
insert into public.unidade_contato_comercial (unidade_id, nome, whatsapp)
values ('00000000-0000-4000-8000-000000000480', 'ZZTESTE Comercial 048', '5521900000048')
on conflict (unidade_id) do nothing;
insert into public.usuarios (id, nome, email, auth_user_id) values
  (-48901, 'ZZTESTE Dono 048', 'zz-dono-048@exemplo.invalido', '00000000-0000-4000-8000-000000048901');
insert into public.professores (id, nome, usuario_id) values (-48001, 'ZZTESTE Professor 048', -48901);
insert into public.leads (id, unidade_id, whatsapp, status) values
  (-48001, '00000000-0000-4000-8000-000000000480', '5521999480001', 'novo'),
  (-48002, '00000000-0000-4000-8000-000000000480', '5521999480002', 'novo');
insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id)
values
  (-48001, -48001, 'ZZTESTE Corrigida 048',  '00000000-0000-4000-8000-000000000480',
   current_date, '16:00', 'experimental_agendada', -48001),
  (-48002, -48002, 'ZZTESTE Reescrita 048',  '00000000-0000-4000-8000-000000000480',
   current_date, '17:00', 'experimental_agendada', -48001);
insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, categoria, curso_nome, professor_id, cancelada)
values
  (-48001, -948001, '00000000-0000-4000-8000-000000000480', current_date,
   (current_date + time '16:00') at time zone 'America/Sao_Paulo', 'experimental', 'ZZTESTE Canto', -48001, false),
  (-48002, -948002, '00000000-0000-4000-8000-000000000480', current_date,
   (current_date + time '17:00') at time zone 'America/Sao_Paulo', 'experimental', 'ZZTESTE Canto', -48001, false);
insert into public.lead_experimental_aulas (lead_experimental_id, aula_local_id, estado, casado_por)
values (-48001, -48001, 'vinculado', 'chave_natural'),
       (-48002, -48002, 'vinculado', 'chave_natural');

create temp table _m(quem text, corpo text) on commit drop;

-- ── Caso 1: escreve, confirma, ENTREGA. Depois corrige e confirma de novo. ──
do $$
declare v_vinc bigint; v_reg uuid; v_not uuid; v_tok uuid;
begin
  select id into v_vinc from lead_experimental_aulas where lead_experimental_id=-48001;

  -- primeira: registra, confirma, e o worker ENTREGA
  select public.fn_registrar_experimental_interno(v_vinc,'a','PRIMEIRA VERSAO','c','d') into v_reg;
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000048901"}',true);
  perform public.app_confirmar_registro_experimental(v_reg, null);
  reset role;

  insert into _m select 'primeira', corpo from fabio_notificacoes
   where referencia_tipo='lead_experimental_registro' and referencia_id=v_reg::text;

  -- o worker pega e entrega (é a ENTREGA que torna a próxima uma correção)
  select (public.fabio_claim_aviso_comercial(v_reg)->>'notificacao_id')::uuid,
         (public.fabio_claim_aviso_comercial(v_reg)->>'lease_token')::uuid into v_not, v_tok;
  select n.id, n.lease_token into v_not, v_tok from fabio_notificacoes n
   where n.referencia_tipo='lead_experimental_registro' and n.referencia_id=v_reg::text;
  perform public.fabio_marcar_notificacao_enviada(v_not, v_tok, 'ZZTESTE');

  -- agora o professor corrige: novo registro, nova confirmação
  select public.fn_registrar_experimental_interno(v_vinc,'a','VERSAO CORRIGIDA','c','d') into v_reg;
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000048901"}',true);
  perform public.app_confirmar_registro_experimental(v_reg, null);
  reset role;

  insert into _m select 'correcao', corpo from fabio_notificacoes
   where referencia_tipo='lead_experimental_registro' and referencia_id=v_reg::text;
end $$;

insert into _res select 'a PRIMEIRA devolutiva nao se chama correcao', 'nao',
  (select case when corpo like '%Correção%' then 'SE CHAMOU' else 'nao' end
     from _m where quem='primeira');
insert into _res select 'e abre como experimental registrada', 'sim',
  (select case when corpo like '%Experimental registrada%' then 'sim' else 'nao' end
     from _m where quem='primeira');

insert into _res select 'a SEGUNDA se anuncia como correcao', 'sim',
  (select case when corpo like '%Correção — a devolutiva desta experimental mudou%'
               then 'sim' else 'NAO — chega igual a primeira' end
     from _m where quem='correcao');
insert into _res select 'e avisa que a anterior nao vale', 'sim',
  (select case when corpo like '%não vale mais%' then 'sim' else 'nao' end
     from _m where quem='correcao');
insert into _res select 'a correcao leva o texto NOVO', 'sim',
  (select case when corpo like '%VERSAO CORRIGIDA%' then 'sim' else 'nao' end
     from _m where quem='correcao');
insert into _res select 'e nao leva o texto velho junto', 'nao leva',
  (select case when corpo like '%PRIMEIRA VERSAO%' then 'LEVOU OS DOIS' else 'nao leva' end
     from _m where quem='correcao');

-- ── O invariante que eu descobri implementando isto ───────────────────────
-- Corrigir NÃO cria registro novo: uq_lead_exp_registro_vigente é único por
-- vínculo e fn_registrar_experimental_interno faz UPDATE na mesma linha. Logo
-- a notificação também é a mesma linha da fila — e foi por isso que a correção
-- não produzia mensagem nenhuma antes desta migration.
-- Se um dia isso mudar, este passo cai e quem mexer vai LER o porquê.
insert into _res select 'corrigir nao cria registro novo (e a mesma linha)', '1',
  (select count(*)::text from lead_experimental_registros r
     join lead_experimental_aulas v on v.id = r.vinculo_id
    where v.lead_experimental_id = -48001);
insert into _res select 'e nao cria notificacao nova', '1',
  (select count(*)::text from fabio_notificacoes n
     join lead_experimental_registros r on r.id::text = n.referencia_id
     join lead_experimental_aulas v on v.id = r.vinculo_id
    where v.lead_experimental_id = -48001
      and n.referencia_tipo = 'lead_experimental_registro');

-- ── Reconfirmar SEM editar não pode gerar mensagem ────────────────────────
-- A idempotência que a 038 protegia com um return antecipado agora mora no
-- claim. Se ela tiver se perdido na mudança, o comercial passa a receber a
-- mesma devolutiva a cada toque no botão.
do $$
declare v_reg uuid; v_out jsonb;
begin
  select r.id into v_reg from lead_experimental_registros r
    join lead_experimental_aulas v on v.id = r.vinculo_id
   where v.lead_experimental_id = -48001;
  -- entrega a correção primeiro, senão a linha não está 'enviada'
  update fabio_notificacoes set status='enviada', enviada_em=now()
   where referencia_tipo='lead_experimental_registro' and referencia_id=v_reg::text;

  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000048901"}',true);
  select public.app_confirmar_registro_experimental(v_reg, null) into v_out;
  reset role;
  insert into _res values ('reconfirmar sem editar nao reabre a mensagem', 'false',
    coalesce(v_out->>'correcao','(ausente)'));
  insert into _res values ('e a linha entregue continua entregue', 'enviada',
    (select status from fabio_notificacoes
      where referencia_tipo='lead_experimental_registro' and referencia_id=v_reg::text));
end $$;

-- ── Caso 2: reescreve ANTES de confirmar. Não corrigiu nada. ───────────────
do $$
declare v_vinc bigint; v_reg uuid;
begin
  select id into v_vinc from lead_experimental_aulas where lead_experimental_id=-48002;
  -- rascunho que ninguem recebeu — a 035 descarta o anterior
  perform public.fn_registrar_experimental_interno(v_vinc,'a','RASCUNHO DESCARTADO','c','d');
  select public.fn_registrar_experimental_interno(v_vinc,'a','TEXTO FINAL','c','d') into v_reg;
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000048901"}',true);
  perform public.app_confirmar_registro_experimental(v_reg, null);
  reset role;
  insert into _m select 'reescrita', corpo from fabio_notificacoes
   where referencia_tipo='lead_experimental_registro' and referencia_id=v_reg::text;
end $$;

insert into _res select 'reescrever ANTES de enviar nao vira correcao', 'nao',
  (select case when corpo like '%Correção%'
               then 'SE CHAMOU — correcao de algo que ninguem recebeu' else 'nao' end
     from _m where quem='reescrita');

-- ── O resto da mensagem continua inteiro ──────────────────────────────────
insert into _res select 'a correcao mantem a regua do bloco interno', '2',
  (select ((length(corpo) - length(replace(corpo,'━━━━━━━━━━━━━━','')))
           / length('━━━━━━━━━━━━━━'))::text from _m where quem='correcao');
insert into _res select 'e mantem o aviso de nao encaminhar', 'sim',
  (select case when corpo like '%uso interno, não encaminhar%' then 'sim' else 'nao' end
     from _m where quem='correcao');

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
