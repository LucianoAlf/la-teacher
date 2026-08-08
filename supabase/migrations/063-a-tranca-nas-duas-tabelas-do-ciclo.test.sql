-- Teste da 063 — a tranca nas duas tabelas do ciclo
--
-- "Liguei RLS" é a parte fácil e a menos importante. O passo que decide se
-- esta migration pode ir pra produção é o oposto: **o professor continua
-- abrindo e escrevendo a ficha dele**. RLS ligada numa tabela que as RPCs
-- `security definer` leem só funciona porque o dono da função é o dono da
-- tabela — se essa premissa estivesse errada, o ciclo inteiro da experimental
-- morreria calado, e o primeiro a descobrir seria um professor na segunda.
--
-- Por isso o teste é 40% cadeado e 60% regressão.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

-- ---------- o cadeado ----------
insert into _res select 'RLS ligada na tabela do vinculo', 'true',
  (select c.relrowsecurity::text from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='lead_experimental_aulas');

insert into _res select 'RLS ligada na tabela do registro', 'true',
  (select c.relrowsecurity::text from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='lead_experimental_registros');

insert into _res select 'nenhuma policy abre excecao', '0',
  (select count(*)::text from pg_policies
    where schemaname='public'
      and tablename in ('lead_experimental_aulas','lead_experimental_registros'));

insert into _res select 'anon e authenticated sem privilegio', '0',
  (select count(*)::text from information_schema.role_table_grants
    where table_schema='public'
      and table_name in ('lead_experimental_aulas','lead_experimental_registros')
      and grantee in ('anon','authenticated','PUBLIC'));

-- ---------- a regressão ----------
insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000000630', 'ZZTESTE unidade 063', 'ZZTESTE063')
on conflict (id) do nothing;

insert into auth.users (id) values ('00000000-0000-4000-8000-000000063001');

insert into public.usuarios (id, nome, email, auth_user_id, perfil, ativo) values
  (-63001, 'ZZTESTE Prof 063', 'zz-prof-063@exemplo.invalido',
   '00000000-0000-4000-8000-000000063001', 'professor', true);

insert into public.professores (id, nome, telefone_whatsapp, usuario_id, ativo) values
  (-63001, 'ZZTESTE Professor 063', '5521991110631', -63001, true);

insert into public.leads (id, unidade_id, whatsapp, status)
values (-63001, '00000000-0000-4000-8000-000000000630', '5521991116301', 'novo');

insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id)
values (-63001, -63001, 'ZZTESTE Aluno 063', '00000000-0000-4000-8000-000000000630',
        (now() at time zone 'America/Sao_Paulo')::date, '15:00',
        'experimental_agendada', -63001);

insert into public.aulas_emusys
  (id, emusys_id, unidade_id, professor_id, data_aula, data_hora_inicio, categoria, cancelada)
values (-63001, -963001, '00000000-0000-4000-8000-000000000630', -63001,
        (now() at time zone 'America/Sao_Paulo')::date,
        ((now() at time zone 'America/Sao_Paulo')::date + time '15:00') at time zone 'America/Sao_Paulo',
        'experimental', false);

insert into public.lead_experimental_aulas
  (id, lead_experimental_id, aula_local_id, estado, casado_por, vinculado_em, vinculado_por)
values (-63001, -63001, -63001, 'vinculado', 'chave_natural', now(), 'teste 063');

create temp table _saida(passo text, j jsonb) on commit drop;
grant select, insert on _saida to authenticated;
create temp table _falha(passo text, msg text) on commit drop;
grant select, insert on _falha to authenticated;

do $$
begin
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000063001"}',true);

  -- Ler a ficha (a tela /app/experimental/:id)
  begin
    insert into _saida select 'ficha', public.app_experimental_do_professor(-63001);
  exception when others then insert into _falha values ('ficha', sqlerrm);
  end;

  -- Escrever o prontuário (a tela de registrar). A RPC devolve o uuid do
  -- registro, não jsonb — `to_jsonb` só pra caber na mesma tabela de saída.
  begin
    insert into _saida select 'registro', to_jsonb(public.app_registrar_experimental(
      -63001, 'ZZTESTE tocou bem', 'ZZTESTE foi ótimo', 'ZZTESTE seguir', '', 'app'));
  exception when others then insert into _falha values ('registro', sqlerrm);
  end;

  -- A agenda, que é onde o vinculo_id nasce pro cliente
  begin
    insert into _saida select 'agenda', public.app_minha_agenda_sessao(
      (now() at time zone 'America/Sao_Paulo')::date);
  exception when others then insert into _falha values ('agenda', sqlerrm);
  end;

  reset role;
end $$;

insert into _res select 'o professor continua abrindo a ficha', 'ZZTESTE Aluno 063',
  (select coalesce(j ->> 'nome_aluno', j::text) from _saida where passo='ficha');

insert into _res select 'e continua escrevendo o prontuario', 'gravado',
  (select case when (j #>> '{}') ~ '^[0-9a-f-]{36}$' then 'gravado' else j::text end
     from _saida where passo='registro');

insert into _res select 'o prontuario chegou mesmo na tabela trancada', '1',
  (select count(*)::text from public.lead_experimental_registros r
    where r.vinculo_id = -63001);

insert into _res select 'a agenda entrega o vinculo da experimental', '-63001',
  (select coalesce((
     select e.value ->> 'vinculo_id'
       from jsonb_array_elements(j) e
      where (e.value ->> 'vinculo_id') is not null
      limit 1), 'NENHUM')
     from _saida where passo='agenda');

insert into _res select 'nenhuma RPC quebrou com a RLS ligada', 'nenhuma',
  (select coalesce(string_agg(passo || ': ' || msg, ' | '), 'nenhuma') from _falha);

-- E o cadeado de verdade: ler a tabela direto, como o app faria se alguém
-- esquecesse a regra de nunca usar from('tabela').
create temp table _direto(msg text) on commit drop;
grant select, insert on _direto to authenticated;
do $$
declare n int;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000063001"}',true);
  begin
    select count(*) into n from public.lead_experimental_registros;
    insert into _direto values ('LEU ' || n);
  exception when others then insert into _direto values ('BLOQUEADO');
  end;
  reset role;
end $$;

insert into _res select 'ler a tabela direto continua bloqueado', 'BLOQUEADO',
  (select msg from _direto);

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
