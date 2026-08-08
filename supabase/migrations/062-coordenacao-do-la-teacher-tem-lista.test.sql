-- Teste da 062 — a coordenação do LA Teacher tem lista própria
--
-- O passo que dá sentido a todos os outros é "admin do LA Report que NÃO está
-- na lista continua de fora". Sem ele, a migration passaria com a guarda
-- antiga intacta: os quatro da coordenação também são admin, então checar só
-- que eles entram não distingue as duas regras.
--
-- Por isso a fixture do admin de fora é obrigatória, e ela imita exatamente
-- quem existe em produção: perfil='admin', ativo, e sem nenhuma relação com o
-- pedagógico (o Marketing e o Comercial da casa).

create temp table _res(passo text, esperado text, obtido text) on commit drop;

insert into auth.users (id) values
  ('00000000-0000-4000-8000-000000062001'),   -- coordenação
  ('00000000-0000-4000-8000-000000062002'),   -- admin de fora (Marketing)
  ('00000000-0000-4000-8000-000000062003'),   -- coordenação desligada
  ('00000000-0000-4000-8000-000000062004');   -- professor comum

insert into public.usuarios (id, nome, email, auth_user_id, perfil, ativo) values
  (-62001, 'ZZTESTE Coordenacao 062', 'zz-coord-062@exemplo.invalido',
   '00000000-0000-4000-8000-000000062001', 'admin', true),
  (-62002, 'ZZTESTE Marketing 062',   'zz-mkt-062@exemplo.invalido',
   '00000000-0000-4000-8000-000000062002', 'admin', true),
  (-62003, 'ZZTESTE Desligada 062',   'zz-off-062@exemplo.invalido',
   '00000000-0000-4000-8000-000000062003', 'admin', false),
  (-62004, 'ZZTESTE Professor 062',   'zz-prof-062@exemplo.invalido',
   '00000000-0000-4000-8000-000000062004', 'professor', true);

-- Na lista: a coordenação e a desligada. Fora: o Marketing e o professor.
insert into public.la_teacher_coordenacao (usuario_id, criado_por) values
  (-62001, 'teste 062'), (-62003, 'teste 062');

create temp table _r(quem text, resposta text) on commit drop;
grant select, insert on _r to authenticated, anon;

do $$
declare v record;
begin
  set local role authenticated;
  for v in select * from (values
      ('coordenacao',        '00000000-0000-4000-8000-000000062001'),
      ('admin de fora',      '00000000-0000-4000-8000-000000062002'),
      ('coordenacao inativa','00000000-0000-4000-8000-000000062003'),
      ('professor',          '00000000-0000-4000-8000-000000062004')) t(quem, sub)
  loop
    perform set_config('request.jwt.claims', json_build_object('sub', v.sub)::text, true);
    begin
      perform public.app_professores_para_liberar();
      insert into _r values (v.quem, 'ABRIU');
    exception when others then
      insert into _r values (v.quem, case when sqlerrm like '%apenas_admin%' then 'RECUSOU' else sqlerrm end);
    end;
  end loop;
  reset role;
end $$;

insert into _res select 'quem esta na lista abre o painel', 'ABRIU',
  (select resposta from _r where quem='coordenacao');

-- O passo que separa a regra nova da velha.
insert into _res select 'admin do LA Report FORA da lista nao abre', 'RECUSOU',
  (select resposta from _r where quem='admin de fora');

insert into _res select 'quem foi desligado perde o painel', 'RECUSOU',
  (select resposta from _r where quem='coordenacao inativa');

insert into _res select 'professor comum continua de fora', 'RECUSOU',
  (select resposta from _r where quem='professor');

-- A função que responde tem que responder sobre QUEM PERGUNTOU.
create temp table _b(quem text, v boolean) on commit drop;
grant select, insert on _b to authenticated;
do $$
begin
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000062001"}',true);
  insert into _b select 'coordenacao', public.fn_e_coordenacao_la_teacher();
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000062002"}',true);
  insert into _b select 'admin de fora', public.fn_e_coordenacao_la_teacher();
  reset role;
end $$;

insert into _res select 'a funcao responde sobre quem perguntou', 'true|false',
  (select string_agg(v::text, '|' order by quem desc) from _b);

-- A lista não pode ser lida por quem está logado no app.
create temp table _leitura(msg text) on commit drop;
grant select, insert on _leitura to authenticated;
do $$
declare n int;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000062002"}',true);
  begin
    select count(*) into n from public.la_teacher_coordenacao;
    insert into _leitura values ('LEU ' || n || ' linha(s)');
  exception when others then insert into _leitura values ('BLOQUEADO');
  end;
  reset role;
end $$;

insert into _res select 'a lista nao vaza pra quem esta logado', 'BLOQUEADO',
  (select msg from _leitura);

-- Os quatro de verdade entraram na lista pela migration.
insert into _res select 'os quatro combinados estao na lista', '4',
  (select count(*)::text from public.la_teacher_coordenacao c
     join public.usuarios u on u.id = c.usuario_id
    where u.email in ('lucianoalf.la@gmail.com','hugo@gmail.com',
                      'juliana@lamusic.com.br','quintela@lamusic.com.br'));

-- E ninguém mais entrou junto.
insert into _res select 'e ninguem entrou de carona', '0',
  (select count(*)::text from public.la_teacher_coordenacao c
     join public.usuarios u on u.id = c.usuario_id
    where u.email not in ('lucianoalf.la@gmail.com','hugo@gmail.com',
                          'juliana@lamusic.com.br','quintela@lamusic.com.br')
      and c.usuario_id not in (-62001, -62003));

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
