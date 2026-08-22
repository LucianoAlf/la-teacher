-- Teste da régua "só cobra quem tem o app".
-- Roda em BEGIN/ROLLBACK contra produção (branches são inviáveis aqui).
--
-- O caso que importa é o NEGATIVO: sem ele, `fn_professor_usa_app` vira
-- `return true` e a cobrança volta a alcançar os 34 professores sem app —
-- exatamente o defeito que esta migration conserta.

do $$
declare
  v_com_app    integer;
  v_sem_app    integer;
  v_inativo    integer;
  v_n          integer;
  v_antes      integer;
  v_depois     integer;
begin
  -- ── amostras REAIS do banco (não fixture: fixture em banco compartilhado vaza)
  select pr.id into v_com_app
    from professores pr join usuarios u on u.id = pr.usuario_id
   where coalesce(pr.ativo,true) and coalesce(u.ativo,true) and u.auth_user_id is not null
   order by pr.id limit 1;

  -- LEFT JOIN de propósito: dos 44 professores ativos, 34 não têm NENHUMA linha
  -- em `usuarios` (nunca foram onboardados). Um INNER JOIN aqui não acha
  -- nenhum "sem app" e o teste se auto-pula — foi o que aconteceu na 1ª
  -- rodada, e teste que se pula sozinho é teste que não existe.
  select pr.id into v_sem_app
    from professores pr left join usuarios u on u.id = pr.usuario_id
   where coalesce(pr.ativo,true) and coalesce(u.auth_user_id::text, '') = ''
   order by pr.id limit 1;

  if v_com_app is null or v_sem_app is null then
    raise exception 'PULADO: preciso de 1 professor COM app e 1 SEM app (com=%, sem=%)', v_com_app, v_sem_app;
  end if;

  -- 1. a régua em si
  if not public.fn_professor_usa_app(v_com_app) then
    raise exception 'FALHOU 1a: professor % tem login e deveria usar o app', v_com_app;
  end if;
  if public.fn_professor_usa_app(v_sem_app) then
    raise exception 'FALHOU 1b: professor % NÃO tem login e não pode ser cobrável', v_sem_app;
  end if;

  -- 2. NEGATIVO que distingue: professor inativo não vira cobrável nem com login.
  --    (sem este caso, tirar o `coalesce(pr.ativo,true)` passaria batido)
  select pr.id into v_inativo
    from professores pr join usuarios u on u.id = pr.usuario_id
   where pr.ativo is false and u.auth_user_id is not null
   order by pr.id limit 1;
  if v_inativo is not null and public.fn_professor_usa_app(v_inativo) then
    raise exception 'FALHOU 2: professor % está INATIVO e não pode ser cobrável', v_inativo;
  end if;

  -- 3. id inexistente devolve false, nunca null (null em AND vira "não cobrável"
  --    por acidente, e acidente que acerta hoje erra amanhã)
  if public.fn_professor_usa_app(-1) is distinct from false then
    raise exception 'FALHOU 3: id inexistente devia devolver false, veio %',
      public.fn_professor_usa_app(-1);
  end if;

  -- 4. a view não cobra ninguém sem app
  select count(*) into v_n from vw_registro_pendencia v
   where v.cobravel and not public.fn_professor_usa_app(v.professor_id);
  if v_n <> 0 then
    raise exception 'FALHOU 4: % linha(s) cobráveis de professor sem app', v_n;
  end if;

  -- 5. INVARIANTE: para quem TEM app, `cobravel` continua sendo exatamente a
  --    régua de data. A mudança só pode SUBTRAIR de quem não tem app — se ela
  --    alterar uma linha de quem tem, quebrou o app de quem já usa.
  select count(*) into v_antes
    from vw_registro_pendencia v
   where public.fn_professor_usa_app(v.professor_id)
     and v.data_aula >= public.fn_data_corte_cobranca();
  select count(*) into v_depois
    from vw_registro_pendencia v
   where public.fn_professor_usa_app(v.professor_id) and v.cobravel;
  if v_antes <> v_depois then
    raise exception 'FALHOU 5: para quem tem app, cobravel mudou (data=%, cobravel=%)', v_antes, v_depois;
  end if;

  -- 6. e a régua REALMENTE corta alguém — teste que não corta nada não prova nada
  select count(distinct professor_id) into v_n from vw_registro_pendencia
   where data_aula >= public.fn_data_corte_cobranca()
     and not public.fn_professor_usa_app(professor_id);
  if v_n = 0 then
    raise exception 'FALHOU 6: a régua não cortou nenhum professor — ou todos têm app, ou o filtro é inócuo';
  end if;

  -- ── 7 e 8: os casos que MATAM os mutantes ────────────────────────────────
  -- Com os dados de hoje, "tem usuário" e "tem login" são a MESMA coisa (0
  -- usuários sem auth) e não há professor inativo com login. Sem cenário
  -- sintético, dois mutantes sobreviviam: tirar `auth_user_id is not null` e
  -- tirar `coalesce(pr.ativo,true)` passavam verde. Cenário montado por UPDATE
  -- temporário — a transação inteira dá ROLLBACK, nada é commitado, e os
  -- triggers de `usuarios`/`professores` não chamam http (conferido), então
  -- nada vaza pra fora do banco.
  declare
    v_prof integer; v_uid integer; v_auth uuid;
  begin
    select pr.id, pr.usuario_id into v_prof, v_uid
      from professores pr join usuarios u on u.id = pr.usuario_id
     where coalesce(pr.ativo,true) and u.auth_user_id is not null
     order by pr.id limit 1;

    -- 7. login REVOGADO → deixa de ser cobrável na hora
    select auth_user_id into v_auth from usuarios where id = v_uid;
    update usuarios set auth_user_id = null where id = v_uid;
    if public.fn_professor_usa_app(v_prof) then
      raise exception 'FALHOU 7: login revogado e professor % ainda cobrável', v_prof;
    end if;
    update usuarios set auth_user_id = v_auth where id = v_uid;

    -- 8. professor DESATIVADO → deixa de ser cobrável mesmo com login
    update professores set ativo = false where id = v_prof;
    if public.fn_professor_usa_app(v_prof) then
      raise exception 'FALHOU 8: professor % inativo e ainda cobrável', v_prof;
    end if;
    update professores set ativo = true where id = v_prof;
  end;

  raise notice 'TODOS OS CASOS PASSARAM (cortou % professor(es) sem app)', v_n;
end $$;
