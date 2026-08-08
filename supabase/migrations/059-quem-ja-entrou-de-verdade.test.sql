-- Teste da 059 — quem já entrou de verdade
--
-- O truque que faz este teste valer: as fixtures gravam em
-- `usuarios.ultimo_acesso` uma data ABSURDA (2001) e em `auth.users` a data
-- verdadeira (2026). São valores diferentes de propósito. Se o código voltar a
-- ler a coluna vazia — ou "se proteger" com um coalesce entre as duas — o passo
-- acusa na hora. Com os dois lados iguais (ou os dois nulos) qualquer versão
-- passaria, e o teste seria decoração.
--
-- O caso do meio (auth existe, mas nunca logou) é o que mata o coalesce: ali a
-- resposta certa é NULO, e a coluna velha tem valor.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000000590', 'ZZTESTE unidade 059', 'ZZTESTE059')
on conflict (id) do nothing;

-- Os auth.users de verdade: um que entrou, um que nunca entrou.
insert into auth.users (id, last_sign_in_at) values
  ('00000000-0000-4000-8000-000000059801', '2026-08-01 10:00:00+00'),
  ('00000000-0000-4000-8000-000000059802', null);

-- E o admin que abre o painel.
insert into auth.users (id, last_sign_in_at) values
  ('00000000-0000-4000-8000-000000059901', now());

-- ultimo_acesso com data absurda: é a coluna que NÃO pode ser lida.
insert into public.usuarios (id, nome, email, auth_user_id, perfil, ativo, ultimo_acesso) values
  (-59901, 'ZZTESTE Admin 059',    'zz-admin-059@exemplo.invalido',
   '00000000-0000-4000-8000-000000059901', 'admin', true, '2001-01-01 00:00:00+00'),
  (-59801, 'ZZTESTE Entrou 059',   'zz-entrou-059@exemplo.invalido',
   '00000000-0000-4000-8000-000000059801', 'professor', true, '2001-01-01 00:00:00+00'),
  (-59802, 'ZZTESTE NuncaEntrou 059', 'zz-nunca-059@exemplo.invalido',
   '00000000-0000-4000-8000-000000059802', 'professor', true, '2001-01-01 00:00:00+00');

insert into public.professores (id, nome, telefone_whatsapp, usuario_id, ativo) values
  (-59001, 'ZZTESTE Prof Entrou 059',      '5521991110591', -59801, true),
  (-59002, 'ZZTESTE Prof NuncaEntrou 059', '5521991110592', -59802, true),
  (-59003, 'ZZTESTE Prof SemAcesso 059',   '5521991110593', null,   true);

create temp table _painel(j jsonb) on commit drop;
grant select, insert on _painel to authenticated;

do $$
begin
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000059901"}',true);
  insert into _painel select public.app_professores_para_liberar();
  reset role;
end $$;

create temp table _linhas(professor_id integer, ultimo_acesso timestamptz, liberado boolean) on commit drop;
insert into _linhas
select (e.value ->> 'professor_id')::integer,
       (e.value ->> 'ultimo_acesso')::timestamptz,
       (e.value ->> 'liberado')::boolean
  from jsonb_array_elements((select j from _painel)) e
 where (e.value ->> 'professor_id')::integer in (-59001, -59002, -59003);

-- 1. Quem entrou aparece com a data do AUTH, não com a da coluna velha.
insert into _res select 'quem entrou traz a data do auth', '2026-08-01 10:00:00+00',
  (select ultimo_acesso::text from _linhas where professor_id = -59001);

-- 2. O caso que mata o coalesce: tem usuário, tem linha no auth, mas nunca logou.
--    A coluna velha tem 2001 gravado. A resposta certa é NULO.
insert into _res select 'liberado que nunca entrou continua vazio', 'NULO',
  (select coalesce(ultimo_acesso::text, 'NULO') from _linhas where professor_id = -59002);

-- 3. Quem nem acesso tem não inventa data.
insert into _res select 'quem nao tem acesso nao tem data', 'NULO',
  (select coalesce(ultimo_acesso::text, 'NULO') from _linhas where professor_id = -59003);

-- 4. E os três continuam na lista (a junção nova não pode ter sumido com ninguém).
insert into _res select 'a juncao nova nao derrubou ninguem', '3',
  (select count(*)::text from _linhas);

insert into _res select 'quem nao tem acesso continua marcado assim', 'false',
  (select liberado::text from _linhas where professor_id = -59003);

-- 5. Regressão da guarda: professor comum não abre o painel.
create temp table _erros(passo text, msg text) on commit drop;
grant select, insert on _erros to authenticated, anon;

do $$
begin
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000059801"}',true);
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

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
