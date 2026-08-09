-- 072 (teste) — a pendência aprende o Emusys
--
-- O passo que dá nome à migration é o par "sem_nada + no_emusys = total" +
-- "no_emusys conta quem tem ANOTAÇÃO". A âncora exige aula pendente com
-- anotação na janela — sem ela, separar e não separar dão o mesmo número
-- (o buraco que deixou a 065 e a 067 passarem com o count errado).
--
-- E o passo da ORDEM tem âncora própria: só falseia se existir professor cuja
-- posição por total difere da posição por sem_nada — o caso Isaque (25 de 29
-- no Emusys), que é exatamente o que motivou a migration.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

-- ─── Guardas ────────────────────────────────────────────────────────────────
do $$
declare v_erro text := 'nao levantou';
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  begin perform public.app_coordenacao_em_aberto(7, null, null);
  exception when others then v_erro := sqlerrm; end;
  insert into _res values ('sem identidade a fila recusa', 'sim',
    case when v_erro like '%apenas_admin%' then 'sim' else 'NAO — ' || v_erro end);
end $$;

do $$
declare v_erro text := 'nao levantou';
begin
  begin perform public.app_coordenacao_professor_detalhe(1, 7, null, null);
  exception when others then v_erro := sqlerrm; end;
  insert into _res values ('sem identidade o detalhe recusa', 'sim',
    case when v_erro like '%apenas_admin%' then 'sim' else 'NAO — ' || v_erro end);
end $$;

do $$
declare v_uid uuid;
begin
  select u.auth_user_id into v_uid
    from public.la_teacher_coordenacao c
    join public.usuarios u on u.id = c.usuario_id
   where u.auth_user_id is not null and coalesce(u.ativo, true) limit 1;
  insert into _res values ('ancora: ha coordenador com login', 'sim',
    case when v_uid is null then 'NAO' else 'sim' end);
  if v_uid is not null then
    perform set_config('request.jwt.claim.sub', v_uid::text, true);
  end if;
end $$;

-- ─── Base medida direto na fonte ────────────────────────────────────────────
create temp table _janela on commit drop as
  select v.professor_id, v.aula_id, v.data_aula, v.dias_em_atraso,
         (nullif(btrim(ae.anotacoes), '') is not null) as no_emusys
    from public.vw_presenca_pendencia v
    join public.aulas_emusys ae on ae.id = v.aula_id
   where v.data_aula >= current_date - 7 and v.data_aula < current_date;

create temp table _saida on commit drop as
  select public.app_coordenacao_em_aberto(7, null, null) as j;

-- ─── O PASSO DESTA MIGRATION ────────────────────────────────────────────────
insert into _res select 'ancora: ha aula pendente COM anotacao no Emusys', 'sim',
  (select case when count(distinct aula_id) > 0 then 'sim'
               else 'NAO — sem anotacao na janela, separar nao falseia' end
     from _janela where no_emusys);

insert into _res select 'ancora: ha aula pendente SEM nada', 'sim',
  (select case when count(distinct aula_id) > 0 then 'sim'
               else 'NAO — tudo no Emusys, separar nao falseia' end
     from _janela where not no_emusys);

insert into _res select 'no_emusys conta quem tem ANOTACAO',
  (select count(distinct aula_id)::text from _janela where no_emusys),
  (select j->'resumo'->>'no_emusys' from _saida);

insert into _res select 'sem_nada conta quem NAO tem nada',
  (select count(distinct aula_id)::text from _janela where not no_emusys),
  (select j->'resumo'->>'sem_nada' from _saida);

insert into _res select 'sem_nada + no_emusys = pendencia total',
  (select count(distinct aula_id)::text from _janela),
  (select ((j->'resumo'->>'sem_nada')::int + (j->'resumo'->>'no_emusys')::int)::text
     from _saida);

insert into _res select '"so de ontem" conta so o cobravel (sem_nada)',
  (select count(distinct aula_id)::text from _janela
    where data_aula = current_date - 1 and not no_emusys),
  (select j->'resumo'->>'ontem' from _saida);

-- ─── A ORDEM: sem_nada manda ────────────────────────────────────────────────
insert into _res select 'ancora: ordenar por total e por sem_nada diverge', 'sim',
  (select case when count(*) > 0 then 'sim'
               else 'NAO — ninguem com anotacao suficiente pra mudar a ordem' end
     from (
       select professor_id,
              row_number() over (order by count(distinct aula_id) desc) as pos_total,
              row_number() over (order by count(distinct aula_id)
                                          filter (where not no_emusys) desc) as pos_sem_nada
         from _janela group by professor_id
     ) t where pos_total <> pos_sem_nada);

insert into _res select 'a fila desce por sem_nada', 'sim',
  (select case when bool_and(ok) then 'sim' else 'NAO — fila fora de ordem' end
     from (
       select (x->>'sem_nada')::int
              <= lag((x->>'sem_nada')::int, 1, 2147483647) over (order by ord) as ok
         from _saida, lateral jsonb_array_elements(j->'professores')
              with ordinality t(x, ord)
     ) s);

-- ─── A linha: soma fecha e o atraso é o do cobrável ─────────────────────────
insert into _res select 'em toda linha, sem_nada + no_emusys = aulas', 'sim',
  (select case when bool_and(
            (x->>'sem_nada')::int + (x->>'no_emusys')::int = (x->>'aulas')::int)
          then 'sim' else 'NAO — linha com soma quebrada' end
     from _saida, lateral jsonb_array_elements(j->'professores') x);

insert into _res select 'ancora: ha professor cujo atraso muda ao ignorar o Emusys', 'sim',
  (select case when count(*) > 0 then 'sim'
               else 'NAO — atraso igual com e sem filtro; o passo abaixo nao falseia' end
     from (
       select professor_id
         from _janela group by professor_id
       having max(dias_em_atraso) is distinct from
              max(dias_em_atraso) filter (where not no_emusys)
     ) t);

insert into _res select 'o atraso da linha e o da aula mais antiga SEM NADA', 'sim',
  (select case when bool_and(coalesce((x->>'pior_atraso')::int, -1) = coalesce(m.esp, -1))
               then 'sim' else 'NAO — atraso contando aula do Emusys' end
     from _saida, lateral jsonb_array_elements(j->'professores') x
     join lateral (
       select max(dias_em_atraso) filter (where not no_emusys)::int as esp
         from _janela w where w.professor_id = (x->>'professor_id')::int
     ) m on true);

-- ─── O detalhe marca cada aula, e o cruzamento fecha ────────────────────────
create temp table _alvo on commit drop as
  select professor_id,
         count(distinct aula_id) filter (where no_emusys)::int as no_emusys_esperado
    from _janela group by professor_id
   order by count(distinct aula_id) filter (where no_emusys) desc limit 1;

create temp table _det on commit drop as
  select public.app_coordenacao_professor_detalhe(
           (select professor_id from _alvo), 7, null, null) as j;

insert into _res select 'ancora: o alvo do detalhe tem aula no Emusys', 'sim',
  (select case when no_emusys_esperado > 0 then 'sim' else 'NAO' end from _alvo);

insert into _res select 'o detalhe marca as aulas que estao no Emusys',
  (select no_emusys_esperado::text from _alvo),
  (select count(*)::text
     from _det, lateral jsonb_array_elements(j->'dias') d,
          lateral jsonb_array_elements(d->'itens') i
    where (i->>'no_emusys')::boolean);

insert into _res select 'a marca do detalhe bate com o no_emusys da linha',
  (select x->>'no_emusys' from _saida, lateral jsonb_array_elements(j->'professores') x
    where (x->>'professor_id')::int = (select professor_id from _alvo)),
  (select count(*)::text
     from _det, lateral jsonb_array_elements(j->'dias') d,
          lateral jsonb_array_elements(d->'itens') i
    where (i->>'no_emusys')::boolean);

-- ─── O que as anteriores garantiram e não pode regredir ─────────────────────
insert into _res select 'a fila NAO repete professor', 'sim',
  (select case when count(*) = count(distinct (x->>'professor_id')::int) then 'sim'
               else 'NAO' end
     from _saida, lateral jsonb_array_elements(j->'professores') x);

insert into _res select 'filtrar por curso AGRUPA as modalidades', 'sim',
  (select case when (public.app_coordenacao_em_aberto(7, null, 'bateria')
                       ->'resumo'->>'no_emusys') is not null then 'sim'
               else 'NAO — filtro quebrou' end);

insert into _res select 'a aula de HOJE nao entra', 'sim',
  (select case when ((j->'resumo'->>'sem_nada')::int + (j->'resumo'->>'no_emusys')::int)
                  = (select count(distinct aula_id) from _janela)
               then 'sim' else 'NAO' end from _saida);

insert into _res select 'anon NAO executa a fila', 'sim',
  (select case when has_function_privilege('anon',
       'public.app_coordenacao_em_aberto(int, uuid, text)', 'execute')
     then 'NAO' else 'sim' end);

insert into _res select 'authenticated executa a fila', 'sim',
  (select case when has_function_privilege('authenticated',
       'public.app_coordenacao_em_aberto(int, uuid, text)', 'execute')
     then 'sim' else 'NAO' end);

insert into _res select 'anon NAO executa o detalhe', 'sim',
  (select case when has_function_privilege('anon',
       'public.app_coordenacao_professor_detalhe(int, int, uuid, text)', 'execute')
     then 'NAO' else 'sim' end);

insert into _res select 'authenticated executa o detalhe', 'sim',
  (select case when has_function_privilege('authenticated',
       'public.app_coordenacao_professor_detalhe(int, int, uuid, text)', 'execute')
     then 'sim' else 'NAO' end);

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
