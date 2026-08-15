-- O trecho executavel remotamente e um contrato de catalogo: nao cria fixtures
-- nem escreve em public. O bloco Docker no fim fica comentado de proposito e o
-- mutante o extrai para um PostgreSQL efemero, onde a prova roda de verdade.

create temporary table pg_temp._fabio_20260815050000_res (
  caso text,
  ok boolean,
  detalhe text
) on commit drop;

create or replace function pg_temp.checar_20260815050000(
  p_caso text,
  p_ok boolean,
  p_detalhe text
) returns void
language plpgsql
as $function$
begin
  insert into pg_temp._fabio_20260815050000_res(caso, ok, detalhe)
  values (p_caso, coalesce(p_ok, false), p_detalhe);
end
$function$;

do $function$
declare
  v_fn regprocedure := to_regprocedure('public.fabio_provar_limpeza(uuid,text)');
  v_norm text;
begin
  perform pg_temp.checar_20260815050000(
    'fabio_provar_limpeza continua existindo',
    v_fn is not null,
    coalesce(v_fn::text, '<ausente>')
  );
  if v_fn is null then
    return;
  end if;

  v_norm := lower(regexp_replace(pg_get_functiondef(v_fn), '\s+', ' ', 'g'));

  perform pg_temp.checar_20260815050000(
    'a nova guarda da fila existe',
    v_norm like '%fila_ainda_pode_reprocessar%',
    substring(v_norm from 1 for 900)
  );

  -- A guarda so vale se espelhar a elegibilidade do retry. Se estes
  -- predicados sumirem, a limpeza volta a apagar o que o retry ainda alcanca.
  perform pg_temp.checar_20260815050000(
    'a guarda espelha a elegibilidade do retry (terminal, tentativas, janela)',
    v_norm like '%not in (''normalizado'', ''erro_terminal'')%'
      and v_norm like '%f.tentativas < 3%'
      and v_norm like '%interval ''3 days''%',
    substring(v_norm from 1 for 900)
  );

  -- As duas guardas que ja existiam nao podem ter sido perdidas.
  perform pg_temp.checar_20260815050000(
    'guarda de acao ativa preservada',
    v_norm like '%acao_ativa_referencia_storage%',
    substring(v_norm from 1 for 900)
  );

  perform pg_temp.checar_20260815050000(
    'guarda de registro confirmado preservada',
    v_norm like '%registro_confirmado_referencia_storage%',
    substring(v_norm from 1 for 900)
  );

  perform pg_temp.checar_20260815050000(
    'a funcao continua STABLE (so le, nunca escreve)',
    (select p.provolatile = 's' from pg_catalog.pg_proc p where p.oid = v_fn),
    (select p.provolatile::text from pg_catalog.pg_proc p where p.oid = v_fn)
  );
end
$function$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._fabio_20260815050000_res where not ok),
  'detalhe', coalesce((
    select json_agg(json_build_object(
      'passo', caso,
      'esperado', 'true',
      'obtido', detalhe
    ) order by caso)
      from pg_temp._fabio_20260815050000_res
     where not ok
  ), '[]'::json)
) as resumo;

/* 20260815050000-DOCKER-DML-TESTS-INICIO
-- Roda so no PostgreSQL efemero do mutante: a prova acontece de verdade
-- contra linhas reais. Cada mutante precisa matar um caso.

do $docker$
declare
  v_acao_viva uuid := gen_random_uuid();
  v_acao_esgotada uuid := gen_random_uuid();
  v_acao_normalizada uuid := gen_random_uuid();
  v_acao_sem_fila uuid := gen_random_uuid();
  v_r jsonb;
begin
  -- 1. O CASO DO VALDO: acao morreu (erro), mas a fila ainda pode reprocessar.
  --    O audio NAO pode ser destruido.
  insert into public.fabio_acoes_pendentes (id, professor_id, storage_path, estado)
  values (v_acao_viva, 36, 'whatsapp/36/viva.mp3', 'erro');
  insert into public.fabio_fila_audios
    (professor_id, unidade_id, aula_id, storage_path, status, origem, erro_tipo, tentativas, criado_em)
  values
    (36, gen_random_uuid(), 1, 'whatsapp/36/viva.mp3', 'transcrevendo', 'whatsapp', 'transitorio', 0, now());

  v_r := public.fabio_provar_limpeza(v_acao_viva, 'whatsapp/36/viva.mp3');
  perform pg_temp.checar_20260815050000(
    'o caso do Valdo: fila ainda reprocessa, audio NAO e destruido',
    (v_r ->> 'pode_remover')::boolean is false
      and (v_r ->> 'motivo') = 'fila_ainda_pode_reprocessar',
    v_r::text
  );

  -- 2. Fila esgotou as tentativas: agora o retry nao alcanca mais, pode limpar.
  insert into public.fabio_acoes_pendentes (id, professor_id, storage_path, estado)
  values (v_acao_esgotada, 36, 'whatsapp/36/esgotada.mp3', 'erro');
  insert into public.fabio_fila_audios
    (professor_id, unidade_id, aula_id, storage_path, status, origem, erro_tipo, tentativas, criado_em)
  values
    (36, gen_random_uuid(), 2, 'whatsapp/36/esgotada.mp3', 'erro', 'whatsapp', 'transitorio', 3, now());

  v_r := public.fabio_provar_limpeza(v_acao_esgotada, 'whatsapp/36/esgotada.mp3');
  perform pg_temp.checar_20260815050000(
    'fila sem tentativa sobrando pode ser limpa (nao vaza Storage)',
    (v_r ->> 'pode_remover')::boolean is true,
    v_r::text
  );

  -- 3. Fila ja normalizada: terminou o trabalho, pode limpar.
  insert into public.fabio_acoes_pendentes (id, professor_id, storage_path, estado)
  values (v_acao_normalizada, 36, 'whatsapp/36/pronta.mp3', 'erro');
  insert into public.fabio_fila_audios
    (professor_id, unidade_id, aula_id, storage_path, status, origem, erro_tipo, tentativas, criado_em)
  values
    (36, gen_random_uuid(), 3, 'whatsapp/36/pronta.mp3', 'normalizado', 'whatsapp', 'transitorio', 0, now());

  v_r := public.fabio_provar_limpeza(v_acao_normalizada, 'whatsapp/36/pronta.mp3');
  perform pg_temp.checar_20260815050000(
    'fila ja normalizada pode ser limpa',
    (v_r ->> 'pode_remover')::boolean is true,
    v_r::text
  );

  -- 4. Sem linha nenhuma na fila: comportamento antigo preservado.
  insert into public.fabio_acoes_pendentes (id, professor_id, storage_path, estado)
  values (v_acao_sem_fila, 36, 'whatsapp/36/orfa.mp3', 'cancelada');

  v_r := public.fabio_provar_limpeza(v_acao_sem_fila, 'whatsapp/36/orfa.mp3');
  perform pg_temp.checar_20260815050000(
    'audio orfao sem fila continua sendo limpo (sem regressao)',
    (v_r ->> 'pode_remover')::boolean is true,
    v_r::text
  );

  -- 5 e 6 isolam as guardas que ja existiam. Em ambos a fila esta ESGOTADA
  -- (tentativas = 3) de proposito: assim a guarda nova nao bloqueia e quem
  -- reprova e exatamente a guarda antiga sob teste. Sem esse cuidado as duas
  -- guardas bloqueariam a mesma linha e o caso nao provaria nada.
  declare
    v_acao_com_irma uuid := gen_random_uuid();
    v_acao_com_registro uuid := gen_random_uuid();
    v_fila_confirmada uuid;
  begin
    -- 5. Outra acao ainda ativa sobre o mesmo path: nao pode remover.
    insert into public.fabio_acoes_pendentes (id, professor_id, storage_path, estado)
    values (v_acao_com_irma, 36, 'whatsapp/36/disputada.mp3', 'erro');
    insert into public.fabio_acoes_pendentes (id, professor_id, storage_path, estado)
    values (gen_random_uuid(), 36, 'whatsapp/36/disputada.mp3', 'processando');
    insert into public.fabio_fila_audios
      (professor_id, unidade_id, aula_id, storage_path, status, origem, erro_tipo, tentativas, criado_em)
    values
      (36, gen_random_uuid(), 5, 'whatsapp/36/disputada.mp3', 'erro', 'whatsapp', 'transitorio', 3, now());

    v_r := public.fabio_provar_limpeza(v_acao_com_irma, 'whatsapp/36/disputada.mp3');
    perform pg_temp.checar_20260815050000(
      'acao ativa sobre o mesmo path ainda impede a remocao',
      (v_r ->> 'pode_remover')::boolean is false
        and (v_r ->> 'motivo') = 'acao_ativa_referencia_storage',
      v_r::text
    );

    -- 6. Registro confirmado aponta pro audio: ele e a evidencia, nao remove.
    insert into public.fabio_acoes_pendentes (id, professor_id, storage_path, estado)
    values (v_acao_com_registro, 36, 'whatsapp/36/confirmada.mp3', 'erro');
    insert into public.fabio_fila_audios
      (professor_id, unidade_id, aula_id, storage_path, status, origem, erro_tipo, tentativas, criado_em)
    values
      (36, gen_random_uuid(), 6, 'whatsapp/36/confirmada.mp3', 'erro', 'whatsapp', 'transitorio', 3, now())
    returning id into v_fila_confirmada;
    insert into public.fabio_registros_aula (audio_id, status)
    values (v_fila_confirmada, 'confirmado');

    v_r := public.fabio_provar_limpeza(v_acao_com_registro, 'whatsapp/36/confirmada.mp3');
    perform pg_temp.checar_20260815050000(
      'registro confirmado ainda impede a remocao do audio',
      (v_r ->> 'pode_remover')::boolean is false
        and (v_r ->> 'motivo') = 'registro_confirmado_referencia_storage',
      v_r::text
    );
  end;
end
$docker$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._fabio_20260815050000_res where not ok),
  'detalhe', coalesce((
    select json_agg(json_build_object(
      'passo', caso,
      'esperado', 'true',
      'obtido', detalhe
    ) order by caso)
      from pg_temp._fabio_20260815050000_res
     where not ok
  ), '[]'::json)
) as resumo;
20260815050000-DOCKER-DML-TESTS-FIM */
