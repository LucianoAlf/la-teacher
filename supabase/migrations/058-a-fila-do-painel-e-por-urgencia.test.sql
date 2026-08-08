-- Teste da 058 — a fila do painel é por urgência
--
-- Este teste existe porque o anterior não pegou. A lista da 057 estava certa em
-- tudo — completa, com os campos certos, com a guarda de admin funcionando — e
-- só na ORDEM errada. Nenhum passo olhava pra ordem, então nenhum reclamou.
--
-- Aqui os nomes das fixtures são escolhidos ao contrário de propósito: quem tem
-- MAIS experimental tem nome que vem DEPOIS no alfabeto. Se a ordenação voltar
-- a ser por nome, a sequência inverte e o passo acusa.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000000580', 'ZZTESTE unidade 058', 'ZZTESTE058')
on conflict (id) do nothing;

insert into public.usuarios (id, nome, email, auth_user_id, perfil, ativo) values
  (-58901, 'ZZTESTE Admin 058', 'zz-admin-058@exemplo.invalido',
   '00000000-0000-4000-8000-000000058901', 'admin', true),
  (-58902, 'ZZTESTE Liberado 058', 'zz-lib-058@exemplo.invalido',
   '00000000-0000-4000-8000-000000058902', 'professor', true);

-- Alfabeto e urgência em ORDEM OPOSTA: Ana tem 0, Zeca tem 2.
insert into public.professores (id, nome, telefone_whatsapp, usuario_id, ativo) values
  (-58001, 'ZZTESTE Ana Zero 058',  '5521991110001', null,   true),
  (-58002, 'ZZTESTE Bia Uma 058',   '5521991110002', null,   true),
  (-58003, 'ZZTESTE Zeca Duas 058', '5521991110003', null,   true),
  (-58004, 'ZZTESTE Aaa Liberado 058', '5521991110004', -58902, true);

insert into public.leads (id, unidade_id, whatsapp, status)
select v.id, '00000000-0000-4000-8000-000000000580', '5521991119' || abs(v.id) % 1000, 'novo'
  from (values (-58001), (-58002), (-58003)) as v(id);

-- Bia com 1, Zeca com 2.
insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id)
values
  (-58001, -58001, 'ZZTESTE Aluno A', '00000000-0000-4000-8000-000000000580',
   (now() at time zone 'America/Sao_Paulo')::date + 1, '10:00', 'experimental_agendada', -58002),
  (-58002, -58002, 'ZZTESTE Aluno B', '00000000-0000-4000-8000-000000000580',
   (now() at time zone 'America/Sao_Paulo')::date + 1, '11:00', 'experimental_agendada', -58003),
  (-58003, -58003, 'ZZTESTE Aluno C', '00000000-0000-4000-8000-000000000580',
   (now() at time zone 'America/Sao_Paulo')::date + 2, '11:00', 'experimental_agendada', -58003);

create temp table _painel(j jsonb) on commit drop;
grant select, insert on _painel to authenticated;

do $$
begin
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000058901"}',true);
  insert into _painel select public.app_professores_para_liberar();
  reset role;
end $$;

-- Só os do teste, na ordem em que vieram.
create temp table _ordem(pos integer, professor_id integer, exp_7d integer) on commit drop;
insert into _ordem
select row_number() over (order by t.n), (t.value ->> 'professor_id')::integer,
       (t.value ->> 'experimentais_7d')::integer
  from jsonb_array_elements((select j from _painel)) with ordinality t(value, n)
 where (t.value ->> 'professor_id')::integer in (-58001, -58002, -58003, -58004);

-- O passo que a 057 não tinha: quem tem MAIS experimental vem primeiro, mesmo
-- com nome no fim do alfabeto.
insert into _res select 'quem tem mais experimental vem primeiro', '-58003,-58002,-58001,-58004',
  (select string_agg(professor_id::text, ',' order by pos) from _ordem);

insert into _res select 'e a contagem de cada um confere', '2,1,0,0',
  (select string_agg(exp_7d::text, ',' order by pos) from _ordem);

-- Liberado vai pro fim, mesmo com nome no comeco do alfabeto e mesmo tendo
-- experimental: quem já entra não é fila.
insert into _res select 'quem ja tem acesso vai pro fim', '-58004',
  (select professor_id::text from _ordem order by pos desc limit 1);

-- Regressões da 057 — a reescrita não pode ter derrubado nada.
create temp table _erros(passo text, msg text) on commit drop;
grant select, insert on _erros to authenticated, anon;

do $$
begin
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000058902"}',true);
  begin
    perform public.app_professores_para_liberar();
    insert into _erros values ('nao admin', 'NAO LEVANTOU');
  exception when others then insert into _erros values ('nao admin', sqlerrm);
  end;
  reset role;
end $$;

insert into _res select 'professor comum continua sem ver o painel', 'apenas_admin',
  (select case when msg like '%apenas_admin%' then 'apenas_admin' else msg end
     from _erros where passo='nao admin');

insert into _res select 'e o painel continua marcando quem tem whatsapp', '4',
  (select count(*)::text from jsonb_array_elements((select j from _painel)) e
    where (e.value ->> 'professor_id')::integer in (-58001,-58002,-58003,-58004)
      and (e.value ->> 'tem_whatsapp')::boolean);

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
