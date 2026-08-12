-- RED/GREEN contract test for 090. The runner wraps migration + test in
-- BEGIN/ROLLBACK; every action and fixture below disappears after the run.

create temporary table _fabio_090_res(caso text, ok boolean, detalhe text)
on commit drop;

do $$
declare
  v_prof integer;
  v_a jsonb;
  v_b jsonb;
  v_c jsonb;
  v_id uuid;
  v_event_id uuid;
  v_erro text;
  v_before integer;
  v_after integer;
begin
  select id into v_prof from public.professores where ativo order by id limit 1;
  if v_prof is null then
    raise exception 'fixture_missing: professor ativo';
  end if;

  insert into _fabio_090_res values (
    'pool de registro retorna envelope e nao explode sem aula de teste',
    (public.fabio_aulas_candidatas(v_prof, 'registro') ->> 'ok')::boolean,
    public.fabio_aulas_candidatas(v_prof, 'registro')::text
  );

  v_a := public.fabio_iniciar_acao(
    v_prof,
    'ZZTESTE-090-A',
    'confirmar_intencao_audio',
    'whatsapp/' || v_prof || '/ZZTESTE-090-A.ogg',
    jsonb_build_object('candidatas', jsonb_build_array(2147483647))
  );
  v_id := (v_a -> 'acao' ->> 'id')::uuid;
  insert into _fabio_090_res values (
    'inicio cria uma acao auditavel',
    (v_a ->> 'ok')::boolean and v_id is not null and (v_a ->> 'codigo') = 'acao_criada',
    v_a::text
  );
  insert into _fabio_090_res values (
    'inicio nao aceita shortlist vinda do payload',
    (v_a -> 'acao' -> 'candidatas') = '[]'::jsonb,
    v_a::text
  );

  v_b := public.fabio_iniciar_acao(
    v_prof, 'ZZTESTE-090-A', 'confirmar_intencao_audio', null, '{}'::jsonb
  );
  insert into _fabio_090_res values (
    'replay do wa_message_id devolve a mesma acao',
    (v_b ->> 'ok')::boolean and (v_b -> 'acao' ->> 'id') = v_id::text and
      (v_b ->> 'codigo') = 'acao_existente',
    v_b::text
  );

  v_c := public.fabio_iniciar_acao(
    v_prof, 'ZZTESTE-090-B', 'confirmar_intencao_audio', null, '{}'::jsonb
  );
  insert into _fabio_090_res values (
    'segunda acao ativa para o mesmo professor e recusada',
    (v_c ->> 'ok')::boolean = false and (v_c ->> 'codigo') = 'acao_ativa_existente',
    v_c::text
  );

  v_b := public.fabio_aplicar_evento_acao(
    v_id, v_prof, 'ZZTESTE-090-C', 'intencao_confirmada', '{}'::jsonb
  );
  insert into _fabio_090_res values (
    'intencao confirmada abre a escolha de aula',
    (v_b ->> 'ok')::boolean and (v_b -> 'acao' ->> 'tipo') = 'escolher_aula_audio',
    v_b::text
  );

  v_c := public.fabio_aplicar_evento_acao(
    v_id, v_prof, 'ZZTESTE-090-S', 'shortlist_definida',
    jsonb_build_object('candidatas', jsonb_build_array(2147483647))
  );
  insert into _fabio_090_res values (
    'shortlist inventada pelo bridge e rejeitada',
    (v_c ->> 'ok')::boolean = false and (v_c ->> 'codigo') = 'shortlist_invalida',
    v_c::text
  );

  v_c := public.fabio_aplicar_evento_acao(
    v_id, v_prof, 'ZZTESTE-090-C', 'intencao_confirmada', '{}'::jsonb
  );
  insert into _fabio_090_res values (
    'replay de evento antigo nao duplica ledger nem transicao',
    (v_c ->> 'ok')::boolean and (v_c ->> 'codigo') = 'evento_existente' and
      (v_c -> 'resultado' -> 'acao' ->> 'tipo') = 'escolher_aula_audio',
    v_c::text
  );

  v_c := public.fabio_aplicar_evento_acao(
    v_id, v_prof, 'ZZTESTE-090-D', 'aula_escolhida',
    jsonb_build_object('aula_id', 2147483646)
  );
  insert into _fabio_090_res values (
    'aula fora da shortlist nunca e escolhida',
    (v_c ->> 'ok')::boolean = false and (v_c ->> 'codigo') = 'aula_fora_da_shortlist',
    v_c::text
  );

  update public.fabio_acoes_pendentes
     set expira_em = now() - interval '1 minute'
   where id = v_id;
  v_c := public.fabio_aplicar_evento_acao(
    v_id, v_prof, 'ZZTESTE-090-E', 'pergunta_refinada', '{}'::jsonb
  );
  insert into _fabio_090_res values (
    'acao expirada nao aceita evento humano',
    (v_c ->> 'ok')::boolean = false and (v_c ->> 'codigo') = 'acao_expirada',
    v_c::text
  );

  select count(*) into v_before from public.fabio_acao_eventos where acao_id = v_id;
  perform public.fabio_acao_ativa(v_prof);
  select count(*) into v_after from public.fabio_acao_eventos where acao_id = v_id;
  insert into _fabio_090_res values (
    'leitura da acao ativa nao grava evento',
    v_before = v_after,
    format('antes=%s depois=%s', v_before, v_after)
  );

  insert into _fabio_090_res values (
    'RLS habilitada nas duas tabelas novas',
    (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relname='fabio_acoes_pendentes')
      and (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relname='fabio_acao_eventos'),
    'relrowsecurity'
  );

  insert into _fabio_090_res values (
    'indice de acao ativa e unico por professor',
    (select i.indisunique from pg_index i join pg_class c on c.oid=i.indexrelid
      where c.relname='fabio_acoes_pendentes_ativa_professor_uq'),
    'indisunique'
  );

  insert into _fabio_090_res values (
    'pool de registro nao usa chamada_feita como filtro',
    lower(pg_get_functiondef('public.fabio_aulas_candidatas(integer,text,timestamptz)'::regprocedure)) not like '%chamada_feita%'
      and lower(pg_get_functiondef('public.fabio_aulas_candidatas(integer,text,timestamptz)'::regprocedure)) like '%vw_registro_pendencia%',
    'definicao do pool'
  );

  insert into _fabio_090_res values (
    'pool de registro preserva professor e janela de sete dias',
    position('where v.professor_id = p_professor_id' in lower(pg_get_functiondef('public.fabio_aulas_candidatas(integer,text,timestamptz)'::regprocedure))) > 0
      and position('v.data_hora_fim >= p_referencia - (public.fn_janela_registro_dias()' in lower(pg_get_functiondef('public.fabio_aulas_candidatas(integer,text,timestamptz)'::regprocedure))) > 0,
    'guardas do pool'
  );

  insert into _fabio_090_res values (
    'contrato de eventos fechados existe na maquina',
    position('shortlist_definida' in lower(pg_get_functiondef(
      'public.fabio_aplicar_evento_acao(uuid,integer,text,text,jsonb)'::regprocedure))) > 0
      and position('audio_enfileirado' in lower(pg_get_functiondef(
        'public.fabio_aplicar_evento_acao(uuid,integer,text,text,jsonb)'::regprocedure))) > 0
      and position('rascunho_pronto' in lower(pg_get_functiondef(
        'public.fabio_aplicar_evento_acao(uuid,integer,text,text,jsonb)'::regprocedure))) > 0
      and position('correcao_aplicada' in lower(pg_get_functiondef(
        'public.fabio_aplicar_evento_acao(uuid,integer,text,text,jsonb)'::regprocedure))) > 0
      and position('confirmado' in lower(pg_get_functiondef(
        'public.fabio_aplicar_evento_acao(uuid,integer,text,text,jsonb)'::regprocedure))) > 0
      and position('limpeza_concluida' in lower(pg_get_functiondef(
        'public.fabio_aplicar_evento_acao(uuid,integer,text,text,jsonb)'::regprocedure))) > 0,
    'eventos da SPEC'
  );

  insert into _fabio_090_res values (
    'escolha revalida a aula contra o pool atual',
    (length(lower(pg_get_functiondef(
      'public.fabio_aplicar_evento_acao(uuid,integer,text,text,jsonb)'::regprocedure)))
      - length(replace(lower(pg_get_functiondef(
        'public.fabio_aplicar_evento_acao(uuid,integer,text,text,jsonb)'::regprocedure)),
        'fabio_shortlist_valida', '')))
      / length('fabio_shortlist_valida') >= 2,
    'revalidacao da shortlist'
  );

  insert into _fabio_090_res values (
    'anon e authenticated nao executam RPCs fabio nem leem tabelas novas',
    not has_function_privilege('anon', 'public.fabio_iniciar_acao(integer,text,text,text,jsonb)', 'EXECUTE')
      and not has_function_privilege('authenticated', 'public.fabio_iniciar_acao(integer,text,text,text,jsonb)', 'EXECUTE')
      and not has_table_privilege('anon', 'public.fabio_acoes_pendentes', 'SELECT')
      and not has_table_privilege('authenticated', 'public.fabio_acao_eventos', 'SELECT'),
    'ACL'
  );
end $$;

select json_build_object(
  'falhas', (select count(*) from _fabio_090_res where not coalesce(ok, false)),
  'detalhe', coalesce((select json_agg(json_build_object(
    'passo', caso, 'esperado', 'ok', 'obtido', coalesce(detalhe, '<NULL>'))
  ) from _fabio_090_res where not coalesce(ok, false)), '[]'::json)
) as resumo;
