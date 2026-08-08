-- 069 (teste) — a coordenação tem perfil
--
-- O passo que mais importa é "devolve o perfil de QUEM chamou". Uma RPC de
-- perfil que ignora o `auth.uid()` e devolve `limit 1` funciona na tela do
-- primeiro usuário e mostra o dado de outra pessoa pra todos os demais — e
-- ninguém percebe até alguém reconhecer o nome errado.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

-- Dois coordenadores DIFERENTES: sem o segundo, uma RPC que devolve sempre a
-- mesma linha passaria no teste do primeiro.
create temp table _dois on commit drop as
select u.auth_user_id as uid, u.nome, u.email,
       row_number() over (order by u.nome) as n
  from public.la_teacher_coordenacao c
  join public.usuarios u on u.id = c.usuario_id
 where u.auth_user_id is not null and coalesce(u.ativo, true);

insert into _res select 'ancora: ha ao menos 2 coordenadores com login', 'sim',
  (select case when count(*) >= 2 then 'sim'
               else 'NAO — so ' || count(*)::text end from _dois);

-- ───────────────────────────────────────────────────────────────────────────
do $$
declare v_erro text := 'nao levantou';
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  begin perform public.app_meu_perfil_coordenacao();
  exception when others then v_erro := sqlerrm; end;
  insert into _res values ('sem identidade a RPC recusa', 'sim',
    case when v_erro like '%apenas_admin%' then 'sim' else 'NAO — ' || v_erro end);
end $$;

-- Quem tem login mas NÃO é da coordenação também não passa. O professor
-- Matheus serve de âncora: ele existe, entra no app, e não pode ver isto.
do $$
declare v_uid uuid; v_erro text := 'nao levantou';
begin
  select au.id into v_uid
    from public.professores p
    join public.usuarios u on u.id = p.usuario_id
    join auth.users au on au.id = u.auth_user_id
   where not exists (select 1 from public.la_teacher_coordenacao c
                      where c.usuario_id = u.id)
   limit 1;

  insert into _res values ('ancora: ha professor logado fora da coordenacao', 'sim',
    case when v_uid is null then 'NAO — nenhum professor com login' else 'sim' end);

  if v_uid is not null then
    perform set_config('request.jwt.claim.sub', v_uid::text, true);
    begin perform public.app_meu_perfil_coordenacao();
    exception when others then v_erro := sqlerrm; end;
    insert into _res values ('professor NAO abre o perfil da coordenacao', 'sim',
      case when v_erro like '%apenas_admin%' then 'sim' else 'NAO — ' || v_erro end);
  end if;
end $$;

-- ───────────────────────────────────────────────────────────────────────────
-- Devolve o perfil de QUEM chamou — conferido com os dois, um de cada vez.
-- ───────────────────────────────────────────────────────────────────────────
do $$
declare r record; v_j jsonb;
begin
  for r in select * from _dois order by n loop
    perform set_config('request.jwt.claim.sub', r.uid::text, true);
    v_j := public.app_meu_perfil_coordenacao();
    insert into _res values (
      'coordenador ' || r.n::text || ' recebe o PROPRIO nome',
      r.nome, coalesce(v_j->>'nome', 'null'));
    insert into _res values (
      'coordenador ' || r.n::text || ' recebe o PROPRIO email',
      r.email, coalesce(v_j->>'email', 'null'));
  end loop;
end $$;

-- A tela desenha a foto: a chave tem que existir mesmo quando não há foto,
-- senão o componente quebra em quem nunca subiu avatar.
do $$
declare v_uid uuid; v_j jsonb;
begin
  select uid into v_uid from _dois order by n limit 1;
  perform set_config('request.jwt.claim.sub', v_uid::text, true);
  v_j := public.app_meu_perfil_coordenacao();
  insert into _res values ('o contrato traz todas as chaves da tela', 'sim',
    case when v_j ?& array['usuario_id','nome','apelido','email','cargo',
                           'telefone','avatar_url','alcance']
         then 'sim'
         else 'NAO — faltou ' || (
           select string_agg(k, ', ') from unnest(
             array['usuario_id','nome','apelido','email','cargo',
                   'telefone','avatar_url','alcance']) k
            where not (v_j ? k)) end);
end $$;

-- ───────────────────────────────────────────────────────────────────────────
insert into _res select 'anon NAO abre o perfil da coordenacao', 'sim',
  (select case when has_function_privilege('anon',
       'public.app_meu_perfil_coordenacao()', 'execute')
     then 'NAO — anon pode' else 'sim' end);

insert into _res select 'authenticated abre', 'sim',
  (select case when has_function_privilege('authenticated',
       'public.app_meu_perfil_coordenacao()', 'execute')
     then 'sim' else 'NAO' end);

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
