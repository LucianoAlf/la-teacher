-- 065 (teste) — a fonte do painel da coordenação
--
-- A identidade é trocada com `set_config('request.jwt.claim.sub', …, true)`:
-- é o primeiro ramo do coalesce dentro de `auth.uid()`. Sem isso o caminho da
-- permissão não teria como ser exercido dentro do BEGIN/ROLLBACK — e guard sem
-- teste é exatamente onde mutante sobrevive.
--
-- Passos de ÂNCORA existem porque quase toda asserção aqui mede dado vivo. Se a
-- âncora cair (todo mundo empatado, uma unidade só, nenhuma aula hoje), o passo
-- que depende dela passaria verde sem medir nada. A âncora é um passo como
-- outro qualquer: ela FALHA e aparece no resumo.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

-- ───────────────────────────────────────────────────────────────────────────
-- Sem identidade nenhuma, a RPC tem que recusar.
-- ───────────────────────────────────────────────────────────────────────────
do $$
declare v_erro text := 'nao levantou';
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  begin
    perform public.app_coordenacao_em_aberto(7, null);
  exception when others then
    v_erro := sqlerrm;
  end;
  insert into _res values ('sem identidade a RPC recusa', 'sim',
    case when v_erro like '%apenas_admin%' then 'sim'
         else 'NAO — ' || v_erro end);
end $$;

-- ───────────────────────────────────────────────────────────────────────────
-- A partir daqui a transação fala como coordenação.
-- ───────────────────────────────────────────────────────────────────────────
do $$
declare v_uid uuid;
begin
  select u.auth_user_id into v_uid
    from public.la_teacher_coordenacao c
    join public.usuarios u on u.id = c.usuario_id
   where u.auth_user_id is not null and coalesce(u.ativo, true)
   limit 1;

  insert into _res values ('ancora: ha coordenador com login', 'sim',
    case when v_uid is null then 'NAO — nenhum coordenador tem auth_user_id'
         else 'sim' end);

  if v_uid is not null then
    perform set_config('request.jwt.claim.sub', v_uid::text, true);
  end if;
end $$;

create temp table _saida on commit drop as
  select public.app_coordenacao_em_aberto(7, null) as j;

-- O resumo é a view, não uma segunda contagem. Se divergir, o painel e a
-- agenda passariam a contar histórias diferentes sobre a mesma escola.
insert into _res select 'o resumo bate com a view',
  (select count(*)::text from public.vw_presenca_pendencia
    where data_aula >= current_date - 7 and data_aula < current_date),
  (select j->'resumo'->>'sem_lancamento' from _saida);

insert into _res select 'a lista de professores nao vem vazia', 'sim',
  (select case when jsonb_array_length(j->'professores') > 0 then 'sim'
               else 'NAO — veio []' end from _saida);

-- Âncora da ordenação: com todo mundo empatado, qualquer ordem passaria.
insert into _res select 'ancora: ha valores distintos de em_aberto', 'sim',
  (select case when count(distinct (x->>'em_aberto')::int) >= 2 then 'sim'
               else 'NAO — todos empatados' end
     from _saida, lateral jsonb_array_elements(j->'professores') x);

-- A fila desce por urgência. NUNCA sobe por nome: o painel de equipe já foi
-- ao ar dizendo "por urgência" com a fila alfabética.
insert into _res select 'a fila desce por urgencia', 'sim',
  (select case when bool_and(ok) then 'sim' else 'NAO — fila fora de ordem' end
     from (
       select (x->>'em_aberto')::int
              <= lag((x->>'em_aberto')::int, 1, 2147483647) over (order by ord)
              as ok
         from _saida, lateral jsonb_array_elements(j->'professores')
              with ordinality t(x, ord)
     ) s);

-- ───────────────────────────────────────────────────────────────────────────
-- O filtro de unidade
-- ───────────────────────────────────────────────────────────────────────────
create temp table _unid on commit drop as
  select unidade_id
    from public.vw_presenca_pendencia
   where data_aula >= current_date - 7 and data_aula < current_date
   limit 1;

create temp table _saida_unid on commit drop as
  select public.app_coordenacao_em_aberto(7, (select unidade_id from _unid)) as j;

insert into _res select 'ancora: pendencia em mais de uma unidade', 'sim',
  (select case when count(distinct unidade_id) >= 2 then 'sim'
               else 'NAO — ' || count(distinct unidade_id)::text || ' unidade(s)' end
     from public.vw_presenca_pendencia
    where data_aula >= current_date - 7 and data_aula < current_date);

insert into _res select 'filtrar por unidade devolve menos que o total', 'sim',
  (select case
     when (u.j->'resumo'->>'sem_lancamento')::int = 0 then 'NAO — filtro zerou tudo'
     when (u.j->'resumo'->>'sem_lancamento')::int
          < (t.j->'resumo'->>'sem_lancamento')::int then 'sim'
     else 'NAO — uma unidade devolveu ' || (u.j->'resumo'->>'sem_lancamento')
          || ' de ' || (t.j->'resumo'->>'sem_lancamento') end
     from _saida_unid u, _saida t);

-- ───────────────────────────────────────────────────────────────────────────
-- A janela é fechada em current_date: aula de hoje ainda não está atrasada.
-- ───────────────────────────────────────────────────────────────────────────
insert into _res select 'ancora: ha aula de hoje na pendencia', 'sim',
  (select case when count(*) > 0 then 'sim' else 'NAO — nenhuma aula hoje' end
     from public.vw_presenca_pendencia where data_aula = current_date);

insert into _res select 'a aula de HOJE nao entra na cobranca',
  (select count(*)::text from public.vw_presenca_pendencia
    where data_aula >= current_date - 7 and data_aula < current_date),
  (select j->'resumo'->>'sem_lancamento' from _saida);

-- ───────────────────────────────────────────────────────────────────────────
-- Privilégios. `create or replace` PRESERVA grants — sem este passo, o
-- mutante que abre a RPC pro anon sobrevive calado.
-- ───────────────────────────────────────────────────────────────────────────
insert into _res select 'anon NAO executa a RPC do painel', 'sim',
  (select case when has_function_privilege('anon',
                     'public.app_coordenacao_em_aberto(int, uuid)', 'execute')
               then 'NAO — anon pode executar' else 'sim' end);

insert into _res select 'authenticated executa a RPC do painel', 'sim',
  (select case when has_function_privilege('authenticated',
                     'public.app_coordenacao_em_aberto(int, uuid)', 'execute')
               then 'sim' else 'NAO — authenticated nao pode' end);

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
