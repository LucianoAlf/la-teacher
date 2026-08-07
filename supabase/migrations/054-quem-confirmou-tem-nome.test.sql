-- Teste da 054 — quem confirmou volta a ter nome
--
-- O passo decisivo é "a assinatura VELHA ignora o autor informado": ele chama a
-- casca de compatibilidade passando o id de OUTRO usuário e confere que o
-- carimbo saiu com o id de quem estava logado. É o único jeito de provar que o
-- buraco fechou em vez de só ter sido contornado no cliente — cliente se
-- reescreve, banco é o que sobra.
--
-- E os passos de regressão existem porque esta migration reescreve uma função
-- de ~120 linhas: presença forte, aviso enfileirado e correção continuam
-- valendo, ou o conserto de identidade custou o ciclo inteiro.

create temp table _res(passo text, esperado text, obtido text) on commit drop;
create temp table _erros(passo text, msg text) on commit drop;
grant select, insert on _erros to authenticated, anon;

-- ── Fixture ─────────────────────────────────────────────────────────────────
insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000000540', 'ZZTESTE unidade 054', 'ZZTESTE054')
on conflict (id) do nothing;

insert into public.unidade_contato_comercial (unidade_id, nome, whatsapp, ativo)
values ('00000000-0000-4000-8000-000000000540', 'ZZTESTE Consultora 054', '5521999540001', true);

insert into public.usuarios (id, nome, email, auth_user_id) values
  (-54901, 'ZZTESTE Dono 054',  'zz-dono-054@exemplo.invalido',  '00000000-0000-4000-8000-000000054901'),
  (-54902, 'ZZTESTE Vitima 054', 'zz-vitima-054@exemplo.invalido', '00000000-0000-4000-8000-000000054902');
insert into public.professores (id, nome, usuario_id) values (-54001, 'ZZTESTE Prof 054', -54901);

insert into public.leads (id, unidade_id, whatsapp, status)
select v.id, '00000000-0000-4000-8000-000000000540', '55219995400' || abs(v.id) % 100, 'novo'
  from (values (-54001), (-54002)) as v(id);

insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id)
select v.id, v.id, 'ZZTESTE Aluno 054 #' || abs(v.id),
       '00000000-0000-4000-8000-000000000540',
       (now() at time zone 'America/Sao_Paulo')::date, '16:00',
       'experimental_agendada', -54001
  from (values (-54001), (-54002)) as v(id);

insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, data_hora_fim,
   categoria, curso_nome, professor_id, cancelada)
select v.id, v.id * 10, '00000000-0000-4000-8000-000000000540',
       (now() at time zone 'America/Sao_Paulo')::date,
       now() - interval '1 hour', now() - interval '10 minutes',
       'experimental', 'ZZTESTE Canto', -54001, false
  from (values (-54001), (-54002)) as v(id);

insert into public.lead_experimental_aulas (id, lead_experimental_id, aula_local_id, estado, casado_por)
values (-54001, -54001, -54001, 'vinculado', 'chave_natural'),
       (-54002, -54002, -54002, 'vinculado', 'chave_natural');

insert into public.lead_experimental_registros
  (id, vinculo_id, unidade_id, professor_id, anotacao_pedagogica, devolutiva_familia,
   proximos_passos, leitura_de_conversao, origem, status)
values
  ('00000000-0000-4000-8000-000000054001', -54001, '00000000-0000-4000-8000-000000000540', -54001,
   'ZZTESTE pedagogica', 'ZZTESTE familia', 'ZZTESTE proximos', 'ZZTESTE conversao',
   'app', 'aguardando_confirmacao'),
  ('00000000-0000-4000-8000-000000054002', -54002, '00000000-0000-4000-8000-000000000540', -54001,
   'ZZTESTE pedagogica 2', 'ZZTESTE familia 2', 'ZZTESTE proximos 2', 'ZZTESTE conversao 2',
   'app', 'aguardando_confirmacao');

-- ═══════════════════════════════════════════════════════════════════════════
-- 1) A assinatura nova
-- ═══════════════════════════════════════════════════════════════════════════
create temp table _saida(rotulo text, j jsonb) on commit drop;
grant select, insert on _saida to authenticated;

do $$
declare v_out jsonb;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000054901"}',true);
  begin
    select public.app_confirmar_registro_experimental('00000000-0000-4000-8000-000000054001') into v_out;
    insert into _saida values ('nova', v_out);
  exception when others then insert into _erros values ('nova', sqlerrm);
  end;
  reset role;
end $$;

insert into _res select 'a confirmacao nao levantou nada', '0',
  (select coalesce((select msg from _erros where passo='nova'), '0'));

insert into _res select 'quem confirmou fica gravado', '-54901',
  (select coalesce(confirmado_por::text, 'NULO')
     from public.lead_experimental_registros where id = '00000000-0000-4000-8000-000000054001');

insert into _res select 'e com a hora', 'sim',
  (select case when confirmado_em is not null then 'sim' else 'nao' end
     from public.lead_experimental_registros where id = '00000000-0000-4000-8000-000000054001');

-- ── Regressão: o ciclo inteiro continua valendo ─────────────────────────────
insert into _res select 'a presenca forte continua sendo gravada', 'presente|professor_la_teacher',
  (select coalesce(presenca_status,'?') || '|' || coalesce(presenca_respondido_por,'?')
     from public.lead_experimental_aulas where id = -54001);

insert into _res select 'e o aviso ao comercial continua saindo', 'true',
  (select (j ->> 'aviso_claimed') from _saida where rotulo='nova');

insert into _res select 'com a devolutiva da familia dentro', 'sim',
  (select case when n.corpo like '%ZZTESTE familia%' then 'sim' else 'nao' end
     from public.fabio_notificacoes n
    where n.referencia_tipo = 'lead_experimental_registro'
      and n.referencia_id = '00000000-0000-4000-8000-000000054001');

-- ═══════════════════════════════════════════════════════════════════════════
-- 2) A assinatura VELHA não deixa mais forjar autor
-- ═══════════════════════════════════════════════════════════════════════════
do $$
declare v_out jsonb;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000054901"}',true);
  begin
    -- Passando o id de OUTRO usuário de propósito: era exatamente isto que a
    -- assinatura antiga aceitava sem perguntar.
    select public.app_confirmar_registro_experimental(
             '00000000-0000-4000-8000-000000054002', -54902) into v_out;
    insert into _saida values ('velha', v_out);
  exception when others then insert into _erros values ('velha', sqlerrm);
  end;
  reset role;
end $$;

insert into _res select 'a casca velha ainda funciona', '0',
  (select coalesce((select msg from _erros where passo='velha'), '0'));

insert into _res select 'e IGNORA o autor informado', '-54901',
  (select coalesce(confirmado_por::text, 'NULO')
     from public.lead_experimental_registros where id = '00000000-0000-4000-8000-000000054002');

-- ═══════════════════════════════════════════════════════════════════════════
-- 3) As guardas que já existiam
-- ═══════════════════════════════════════════════════════════════════════════
do $$
begin
  set local role anon;
  begin
    perform public.app_confirmar_registro_experimental('00000000-0000-4000-8000-000000054001');
    insert into _erros values ('anon', 'NAO LEVANTOU');
  exception when others then insert into _erros values ('anon', sqlerrm);
  end;
  reset role;

  -- Autenticado que não é professor nenhum.
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000054902"}',true);
  begin
    perform public.app_confirmar_registro_experimental('00000000-0000-4000-8000-000000054001');
    insert into _erros values ('sem professor', 'NAO LEVANTOU');
  exception when others then insert into _erros values ('sem professor', sqlerrm);
  end;
  reset role;
end $$;

insert into _res select 'anonimo nao confirma nada', 'barrado',
  (select case when msg = 'NAO LEVANTOU' then 'PASSOU' else 'barrado' end
     from _erros where passo='anon');

insert into _res select 'autenticado sem professor tambem nao', 'barrado',
  (select case when msg = 'NAO LEVANTOU' then 'PASSOU' else 'barrado' end
     from _erros where passo='sem professor');

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
