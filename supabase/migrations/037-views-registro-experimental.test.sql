-- Teste da 037 — a fronteira e estrutural, verificavel no catalogo
--
-- O catalogo prova que a coluna NAO EXISTE, que e uma garantia mais forte que
-- "o codigo nao seleciona ela". Mas catalogo sozinho nao basta: uma view com
-- join errado devolve zero linha e passaria em todas as asercoes de coluna.
-- Por isso o teste tambem exercita CONTEUDO, com fixture ZZTESTE. (O plano so
-- tinha catalogo — o mutante M4 existe pra mostrar por que isso era pouco.)

create temp table _res(passo text, esperado text, obtido text) on commit drop;

-- ── Catalogo: a fronteira que nao depende de ninguem lembrar ──────────────
insert into _res
select 'view comercial TEM leitura_de_conversao', 'sim',
       case when exists (select 1 from information_schema.columns
                          where table_schema='public'
                            and table_name='vw_experimental_registro_comercial'
                            and column_name='leitura_de_conversao')
            then 'sim' else 'nao' end;

insert into _res
select 'view family_safe NAO TEM leitura_de_conversao', 'nao',
       case when exists (select 1 from information_schema.columns
                          where table_schema='public'
                            and table_name='vw_experimental_registro_family_safe'
                            and column_name='leitura_de_conversao')
            then 'sim — VAZOU' else 'nao' end;

insert into _res
select 'family_safe nao tem NENHUMA coluna de conversao', '0',
       (select count(*)::text from information_schema.columns
         where table_schema='public'
           and table_name='vw_experimental_registro_family_safe'
           and column_name ilike '%conversao%');

insert into _res
select 'family_safe expoe os 3 blocos family-safe', '3',
       (select count(*)::text from information_schema.columns
         where table_schema='public'
           and table_name='vw_experimental_registro_family_safe'
           and column_name in ('anotacao_pedagogica','devolutiva_familia','proximos_passos'));

-- ── Permissao: family-safe descreve o CONTEUDO, nao a autorizacao ─────────
-- A linha ainda tem nome de lead, unidade e horario. Sem filtro por professor,
-- select direto entregaria a base de leads a qualquer usuario logado.
insert into _res
select 'anon nao le a view comercial', 'sem privilegio',
       case when has_table_privilege('anon','public.vw_experimental_registro_comercial','select')
            then 'LE — vazou' else 'sem privilegio' end;
insert into _res
select 'authenticated nao le a view comercial', 'sem privilegio',
       case when has_table_privilege('authenticated','public.vw_experimental_registro_comercial','select')
            then 'LE — leitura de conversao no app' else 'sem privilegio' end;
insert into _res
select 'anon nao le a view family_safe', 'sem privilegio',
       case when has_table_privilege('anon','public.vw_experimental_registro_family_safe','select')
            then 'LE — base de leads exposta' else 'sem privilegio' end;
insert into _res
select 'authenticated nao le a view family_safe', 'sem privilegio',
       case when has_table_privilege('authenticated','public.vw_experimental_registro_family_safe','select')
            then 'LE — base de leads exposta' else 'sem privilegio' end;
insert into _res
select 'service_role le as duas', '2',
       (case when has_table_privilege('service_role','public.vw_experimental_registro_comercial','select')
             then 1 else 0 end
      + case when has_table_privilege('service_role','public.vw_experimental_registro_family_safe','select')
             then 1 else 0 end)::text;

-- ── Cenario, pra provar que as views devolvem LINHA ───────────────────────
insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000000370', 'ZZTESTE unidade 037', 'ZZTESTE037')
on conflict (id) do nothing;

insert into public.professores (id, nome) values (-37001, 'ZZTESTE Professor 037');

insert into public.leads (id, unidade_id, whatsapp, status) values
  (-37001, '00000000-0000-4000-8000-000000000370', '5521999370001', 'novo'),
  (-37002, '00000000-0000-4000-8000-000000000370', '5521999370002', 'novo');

insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id)
values
  (-37001, -37001, 'ZZTESTE Vigente',    '00000000-0000-4000-8000-000000000370', current_date+1, '10:00', 'experimental_agendada', -37001),
  (-37002, -37002, 'ZZTESTE Descartado', '00000000-0000-4000-8000-000000000370', current_date+1, '11:00', 'experimental_agendada', -37001);

insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, categoria, professor_id, cancelada)
values
  (-37001, -937001, '00000000-0000-4000-8000-000000000370', current_date+1,
   (current_date+1 + time '10:00') at time zone 'America/Sao_Paulo', 'experimental', -37001, false),
  (-37002, -937002, '00000000-0000-4000-8000-000000000370', current_date+1,
   (current_date+1 + time '11:00') at time zone 'America/Sao_Paulo', 'experimental', -37001, false);

insert into public.lead_experimental_aulas
  (lead_experimental_id, aula_local_id, estado, casado_por,
   presenca_status, presenca_respondido_por)
values (-37001, -37001, 'vinculado', 'chave_natural', 'presente', 'professor_la_teacher'),
       (-37002, -37002, 'vinculado', 'chave_natural', null, null);

create temp table _reg(quem text, id uuid) on commit drop;

do $$
declare v_vinc bigint; v_reg uuid;
begin
  select id into v_vinc from lead_experimental_aulas where lead_experimental_id=-37001;
  select public.fn_registrar_experimental_interno(v_vinc, 'trabalhou acordes',
           'ela se soltou muito', 'comecar pelo repertorio dela',
           'SEGREDO — mae perguntou preco 2x') into v_reg;
  insert into _reg values ('vigente', v_reg);

  select id into v_vinc from lead_experimental_aulas where lead_experimental_id=-37002;
  select public.fn_registrar_experimental_interno(v_vinc, 'a','b','c','d') into v_reg;
  update lead_experimental_registros set status='descartado' where id=v_reg;
  insert into _reg values ('descartado', v_reg);
end $$;

-- ── Conteudo: a view devolve a linha, com o dado certo ────────────────────
-- Sem estes passos, um join quebrado devolveria zero linha e TODAS as
-- asercoes de catalogo acima continuariam verdes.
insert into _res select 'comercial devolve o registro vigente', '1',
  (select count(*)::text from vw_experimental_registro_comercial c
     join _reg g on g.id = c.registro_id where g.quem='vigente');

insert into _res select 'comercial carrega a leitura de conversao',
  'SEGREDO — mae perguntou preco 2x',
  (select c.leitura_de_conversao from vw_experimental_registro_comercial c
     join _reg g on g.id = c.registro_id where g.quem='vigente');

insert into _res select 'comercial resolve o nome do aluno pelo lead', 'ZZTESTE Vigente',
  (select c.nome_aluno from vw_experimental_registro_comercial c
     join _reg g on g.id = c.registro_id where g.quem='vigente');

insert into _res select 'comercial marca presenca de fonte forte', 'true',
  (select c.presenca_e_forte::text from vw_experimental_registro_comercial c
     join _reg g on g.id = c.registro_id where g.quem='vigente');

insert into _res select 'family_safe devolve a MESMA linha', '1',
  (select count(*)::text from vw_experimental_registro_family_safe f
     join _reg g on g.id = f.registro_id where g.quem='vigente');

insert into _res select 'family_safe traz a devolutiva da familia', 'ela se soltou muito',
  (select f.devolutiva_familia from vw_experimental_registro_family_safe f
     join _reg g on g.id = f.registro_id where g.quem='vigente');

-- ── Descartado nao aparece em nenhuma das duas ────────────────────────────
-- Registro descartado e o rascunho que foi substituido: se ele vazar pra view,
-- o comercial recebe a versao velha da conversa.
insert into _res select 'descartado fica fora da comercial', '0',
  (select count(*)::text from vw_experimental_registro_comercial c
     join _reg g on g.id = c.registro_id where g.quem='descartado');
insert into _res select 'descartado fica fora da family_safe', '0',
  (select count(*)::text from vw_experimental_registro_family_safe f
     join _reg g on g.id = f.registro_id where g.quem='descartado');

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
