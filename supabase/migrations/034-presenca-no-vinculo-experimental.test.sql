-- Teste da 034 — presenca no vinculo respeita fonte, e o comercial nao rebaixa
--
-- O coracao do desenho e "fonte forte". Se a fonte nascer errada, a presenca
-- vira fantasma em silencio — que e exatamente o que esta migration existe
-- pra matar. Por isso o primeiro passo tenta gravar 'professor_app' (valor
-- que NAO existe) e exige rejeicao.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000000340', 'ZZTESTE unidade 034', 'ZZTESTE034')
on conflict (id) do nothing;

insert into public.professores (id, nome) values (-34001, 'ZZTESTE Professor 034');

insert into public.leads (id, unidade_id, whatsapp, status) values
  (-34001, '00000000-0000-4000-8000-000000000340', '5521999340001', 'novo'),
  (-34002, '00000000-0000-4000-8000-000000000340', '5521999340002', 'novo'),
  (-34003, '00000000-0000-4000-8000-000000000340', '5521999340003', 'novo'),
  (-34004, '00000000-0000-4000-8000-000000000340', '5521999340004', 'novo');

insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id)
values
  (-34001, -34001, 'ZZTESTE Forte vence fraca',  '00000000-0000-4000-8000-000000000340', current_date+1, '10:00', 'experimental_agendada', -34001),
  (-34002, -34002, 'ZZTESTE Fraca nao vence',    '00000000-0000-4000-8000-000000000340', current_date+1, '11:00', 'experimental_agendada', -34001),
  (-34003, -34003, 'ZZTESTE Regressao comercial','00000000-0000-4000-8000-000000000340', current_date+1, '12:00', 'experimental_agendada', -34001),
  (-34004, -34004, 'ZZTESTE Bruto preservado',   '00000000-0000-4000-8000-000000000340', current_date+1, '13:00', 'experimental_agendada', -34001);

insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, categoria, professor_id, cancelada)
values
  (-34001, -934001, '00000000-0000-4000-8000-000000000340', current_date+1,
   (current_date+1 + time '10:00') at time zone 'America/Sao_Paulo', 'experimental', -34001, false),
  (-34002, -934002, '00000000-0000-4000-8000-000000000340', current_date+1,
   (current_date+1 + time '11:00') at time zone 'America/Sao_Paulo', 'experimental', -34001, false),
  (-34003, -934003, '00000000-0000-4000-8000-000000000340', current_date+1,
   (current_date+1 + time '12:00') at time zone 'America/Sao_Paulo', 'experimental', -34001, false),
  (-34004, -934004, '00000000-0000-4000-8000-000000000340', current_date+1,
   (current_date+1 + time '13:00') at time zone 'America/Sao_Paulo', 'experimental', -34001, false);

insert into public.lead_experimental_aulas (lead_experimental_id, aula_local_id, estado, casado_por)
values (-34001, -34001, 'vinculado', 'chave_natural'),
       (-34002, -34002, 'vinculado', 'chave_natural'),
       (-34003, -34003, 'vinculado', 'chave_natural'),
       (-34004, -34004, 'vinculado', 'chave_natural');

-- ── CHECK rejeita fonte inventada (o professor_app da spec v1) ─────────────
do $$
declare v_id bigint;
begin
  select id into v_id from lead_experimental_aulas where lead_experimental_id=-34001;
  begin
    update lead_experimental_aulas set presenca_respondido_por='professor_app' where id=v_id;
    insert into _res values ('fonte inventada rejeitada', 'rejeitado', 'ACEITOU — nasceria fraca em silencio');
  exception when check_violation then
    insert into _res values ('fonte inventada rejeitada', 'rejeitado', 'rejeitado');
  end;
end $$;

-- ── Forte sobrescreve fraca ────────────────────────────────────────────────
do $$
declare v_id bigint;
begin
  select id into v_id from lead_experimental_aulas where lead_experimental_id=-34001;
  perform public.fn_registrar_presenca_experimental(v_id, 'presente', 'emusys', 'presente');
  perform public.fn_registrar_presenca_experimental(v_id, 'falta', 'professor_la_teacher');
  insert into _res select 'forte sobrescreve fraca', 'falta/professor_la_teacher',
    presenca_status||'/'||presenca_respondido_por from lead_experimental_aulas where id=v_id;
  insert into _res select 'bruto do emusys preservado apos professor ganhar', 'presente',
    coalesce(presenca_bruta_emusys,'(nulo)') from lead_experimental_aulas where id=v_id;
end $$;

-- ── Fraca NAO sobrescreve forte, e a funcao devolve false ──────────────────
do $$
declare v_id bigint; v_ok boolean;
begin
  select id into v_id from lead_experimental_aulas where lead_experimental_id=-34002;
  perform public.fn_registrar_presenca_experimental(v_id, 'presente', 'fabio_audio');
  select public.fn_registrar_presenca_experimental(v_id, 'falta', 'emusys', 'ausente') into v_ok;
  insert into _res values ('fraca nao sobrescreve forte (retorno)', 'false', v_ok::text);
  insert into _res select 'fraca nao sobrescreve forte (valor)', 'presente/fabio_audio',
    presenca_status||'/'||presenca_respondido_por from lead_experimental_aulas where id=v_id;
  insert into _res select 'bruto gravado mesmo com escrita barrada', 'ausente',
    coalesce(presenca_bruta_emusys,'(nulo)') from lead_experimental_aulas where id=v_id;
end $$;

-- ── Presenca forte promove estado ──────────────────────────────────────────
insert into _res
select 'presenca forte promove estado', 'faltou',
       (select estado from lead_experimental_aulas where lead_experimental_id=-34001);

-- ── Fonte fraca NAO promove estado (fantasma nao entra pela porta dos fundos)
do $$
declare v_id bigint;
begin
  select id into v_id from lead_experimental_aulas where lead_experimental_id=-34004;
  perform public.fn_registrar_presenca_experimental(v_id, 'presente', 'emusys', 'presente');
  insert into _res select 'fonte fraca NAO promove estado', 'vinculado', estado
    from lead_experimental_aulas where id=v_id;
end $$;

-- ── REGRESSAO COMERCIAL: status do lead nao rebaixa presenca forte ─────────
do $$
declare v_id bigint;
begin
  select id into v_id from lead_experimental_aulas where lead_experimental_id=-34003;
  perform public.fn_registrar_presenca_experimental(v_id, 'presente', 'professor_la_teacher');
end $$;
update public.lead_experimentais set status='experimental_faltou' where id=-34003;

create temp table _rodada_034 on commit drop as
select public.fn_reconciliar_experimental_aulas(30, 500) as resumo;

insert into _res
select 'comercial nao rebaixa presenca forte (estado)', 'realizado',
       (select estado from lead_experimental_aulas where lead_experimental_id=-34003);
insert into _res
select 'comercial nao rebaixa presenca forte (fonte intacta)', 'professor_la_teacher',
       (select presenca_respondido_por from lead_experimental_aulas where lead_experimental_id=-34003);
insert into _res
select 'rodada da reconciliacao sem erro', '0',
       (select resumo->>'erros' from _rodada_034);

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
