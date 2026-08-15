-- O trecho executavel remotamente e um contrato de catalogo: nao cria fixtures
-- nem escreve em public. O bloco Docker no fim fica comentado de proposito e o
-- mutante o extrai para um PostgreSQL efemero, onde a selecao roda de verdade.

create temporary table pg_temp._fabio_20260815060000_res (
  caso text,
  ok boolean,
  detalhe text
) on commit drop;

create or replace function pg_temp.checar_20260815060000(
  p_caso text,
  p_ok boolean,
  p_detalhe text
) returns void
language plpgsql
as $function$
begin
  insert into pg_temp._fabio_20260815060000_res(caso, ok, detalhe)
  values (p_caso, coalesce(p_ok, false), p_detalhe);
end
$function$;

do $function$
declare
  v_fn regprocedure := to_regprocedure('public.fn_fabio_retry_fila()');
  v_def text;
  v_norm text;
begin
  perform pg_temp.checar_20260815060000(
    'fn_fabio_retry_fila continua existindo',
    v_fn is not null,
    coalesce(v_fn::text, '<ausente>')
  );

  if v_fn is null then
    return;
  end if;

  v_def := pg_get_functiondef(v_fn);
  -- Normaliza espaco/quebra de linha para que a asercao fale de SEMANTICA e
  -- nao de formatacao.
  v_norm := lower(regexp_replace(v_def, '\s+', ' ', 'g'));

  -- O CORACAO: os estados em voo precisam estar no alcance do retry.
  perform pg_temp.checar_20260815060000(
    'estados em voo (transcrevendo/transcrito) entram no retry',
    v_norm like '%''transcrevendo'', ''transcrito''%'
      or v_norm like '%''transcrevendo'',''transcrito''%',
    substring(v_norm from 1 for 900)
  );

  -- O CORACAO DESTA MIGRATION: o orfao volta pro inicio. Sem isso a edge
  -- responde "ignorado" e a tentativa e queimada a toa.
  perform pg_temp.checar_20260815060000(
    'o orfao em voo e devolvido ao estado pendente',
    v_norm like '%status = case%'
      and v_norm like '%then ''pendente''%',
    substring(v_norm from 1 for 900)
  );

  -- A janela de folga existe: nao reenfileira quem ainda pode estar vivo.
  perform pg_temp.checar_20260815060000(
    'em voo so volta depois de uma janela de folga (15 minutos)',
    v_norm like '%interval ''15 minutes''%',
    substring(v_norm from 1 for 900)
  );

  -- A guarda que impede roubar audio da experimental.
  perform pg_temp.checar_20260815060000(
    'retry respeita a fronteira do worker da experimental (vinculo_id is null)',
    v_norm like '%vinculo_id is null%',
    substring(v_norm from 1 for 900)
  );

  -- As garantias que ja existiam nao podem ter sido perdidas no caminho.
  perform pg_temp.checar_20260815060000(
    'teto de tentativas preservado',
    v_norm like '%tentativas < 3%',
    substring(v_norm from 1 for 900)
  );

  perform pg_temp.checar_20260815060000(
    'erro_terminal continua fora do retry',
    v_norm like '%erro_tipo = ''transitorio''%'
      and v_norm like '%status <> ''erro_terminal''%',
    substring(v_norm from 1 for 900)
  );

  perform pg_temp.checar_20260815060000(
    'janela de 3 dias preservada',
    v_norm like '%interval ''3 days''%',
    substring(v_norm from 1 for 900)
  );
end
$function$;

-- Resumo do contrato de catalogo (execucao remota). O bloco Docker abaixo
-- fecha com o SEU proprio resumo: sem isso, o mutante leria este resumo aqui,
-- calculado ANTES das asercoes DML, e um mutante vivo passaria por morto.
select json_build_object(
  'falhas', (select count(*) from pg_temp._fabio_20260815060000_res where not ok),
  'detalhe', coalesce((
    select json_agg(json_build_object(
      'passo', caso,
      'esperado', 'true',
      'obtido', detalhe
    ) order by caso)
      from pg_temp._fabio_20260815060000_res
     where not ok
  ), '[]'::json)
) as resumo;

/* 20260815060000-DOCKER-DML-TESTS-INICIO
-- Roda so no PostgreSQL efemero do mutante: aqui a selecao acontece de
-- verdade contra linhas reais, e cada mutante do fix precisa matar um caso.

do $docker$
declare
  v_prof integer := 4242;
  v_unidade uuid := gen_random_uuid();
  v_em_voo uuid;
  v_em_voo_recente uuid;
  v_experimental uuid;
  v_terminal uuid;
  v_pendente uuid;
  v_alcancados uuid[];
begin
  -- A porta do retry so LE a fila; fn_fabio_chama_edge depende de vault e nao
  -- existe aqui. Trocamos por um no-op para medir a SELECAO, que e o que esta
  -- em teste. Sem isso o teste morreria de erro e nao de asercao.
  create or replace function public.fn_fabio_chama_edge(p_audio_id uuid)
  returns void language plpgsql as $noop$
  begin
    insert into pg_temp._fabio_disparados(id) values (p_audio_id);
  end $noop$;

  create temporary table if not exists pg_temp._fabio_disparados (id uuid);
  delete from pg_temp._fabio_disparados;

  -- 1. Morreu em voo ha muito tempo: TEM que voltar. E o caso do Valdo.
  insert into public.fabio_fila_audios
    (professor_id, unidade_id, aula_id, storage_path, status, origem,
     erro_tipo, tentativas, vinculo_id, criado_em, atualizado_em)
  values
    (v_prof, v_unidade, 1, 'whatsapp/4242/em-voo.mp3', 'transcrevendo', 'whatsapp',
     'transitorio', 0, null, now() - interval '2 hours', now() - interval '2 hours')
  returning id into v_em_voo;

  -- 2. Em voo ha 8 MINUTOS: NAO pode voltar — pode estar transcrevendo agora.
  -- 8 e escolhido de proposito: JA passou do backoff geral (5 min), entao so a
  -- janela de folga de 15 min pode barra-lo. Com 2 min o caso seria barrado
  -- pelo backoff e o teste nao provaria nada sobre a janela.
  insert into public.fabio_fila_audios
    (professor_id, unidade_id, aula_id, storage_path, status, origem,
     erro_tipo, tentativas, vinculo_id, criado_em, atualizado_em)
  values
    (v_prof, v_unidade, 2, 'whatsapp/4242/agora.mp3', 'transcrevendo', 'whatsapp',
     'transitorio', 0, null, now() - interval '8 minutes', now() - interval '8 minutes')
  returning id into v_em_voo_recente;

  -- 3. Experimental parada em voo: e do worker proprio, o Hermes NAO leva.
  insert into public.fabio_fila_audios
    (professor_id, unidade_id, aula_id, storage_path, status, origem,
     erro_tipo, tentativas, vinculo_id, criado_em, atualizado_em)
  values
    (v_prof, v_unidade, 3, 'app/4242/experimental.webm', 'transcrevendo', 'app',
     'transitorio', 0, gen_random_uuid(), now() - interval '2 hours', now() - interval '2 hours')
  returning id into v_experimental;

  -- 4. Erro terminal: continua fora, como sempre esteve.
  insert into public.fabio_fila_audios
    (professor_id, unidade_id, aula_id, storage_path, status, origem,
     erro_tipo, tentativas, vinculo_id, criado_em, atualizado_em)
  values
    (v_prof, v_unidade, 4, 'whatsapp/4242/morto.mp3', 'erro_terminal', 'whatsapp',
     'semantico_terminal', 21, null, now() - interval '2 hours', now() - interval '2 hours')
  returning id into v_terminal;

  -- 5. Pendente antiga: o comportamento que ja existia nao pode regredir.
  insert into public.fabio_fila_audios
    (professor_id, unidade_id, aula_id, storage_path, status, origem,
     erro_tipo, tentativas, vinculo_id, criado_em, atualizado_em)
  values
    (v_prof, v_unidade, 5, 'whatsapp/4242/pendente.mp3', 'pendente', 'whatsapp',
     'transitorio', 0, null, now() - interval '2 hours', now() - interval '2 hours')
  returning id into v_pendente;

  perform public.fn_fabio_retry_fila();
  select array_agg(id) into v_alcancados from pg_temp._fabio_disparados;

  perform pg_temp.checar_20260815060000(
    'audio morto em voo volta pra fila (o caso do Valdo)',
    v_em_voo = any(coalesce(v_alcancados, '{}')),
    coalesce(array_to_string(v_alcancados, ','), '<nenhum>')
  );

  perform pg_temp.checar_20260815060000(
    'audio em voo ha 2 minutos NAO e reenfileirado (pode estar vivo)',
    not (v_em_voo_recente = any(coalesce(v_alcancados, '{}'))),
    coalesce(array_to_string(v_alcancados, ','), '<nenhum>')
  );

  perform pg_temp.checar_20260815060000(
    'experimental parada NAO e roubada pro Hermes',
    not (v_experimental = any(coalesce(v_alcancados, '{}'))),
    coalesce(array_to_string(v_alcancados, ','), '<nenhum>')
  );

  perform pg_temp.checar_20260815060000(
    'erro_terminal continua fora do retry',
    not (v_terminal = any(coalesce(v_alcancados, '{}'))),
    coalesce(array_to_string(v_alcancados, ','), '<nenhum>')
  );

  perform pg_temp.checar_20260815060000(
    'pendente antiga continua sendo reenfileirada (sem regressao)',
    v_pendente = any(coalesce(v_alcancados, '{}')),
    coalesce(array_to_string(v_alcancados, ','), '<nenhum>')
  );

  perform pg_temp.checar_20260815060000(
    'a tentativa foi contabilizada em quem voltou',
    (select tentativas = 1 from public.fabio_fila_audios where id = v_em_voo),
    (select tentativas::text from public.fabio_fila_audios where id = v_em_voo)
  );

  -- O CORACAO: sem voltar pra 'pendente', a edge responde "ignorado" e a
  -- tentativa e queimada a toa — foi exatamente o que producao mostrou no
  -- cron das 14:30 de 15/08.
  perform pg_temp.checar_20260815060000(
    'o orfao volta pro inicio: status vira pendente (a edge so aceita pendente/erro)',
    (select status = 'pendente' from public.fabio_fila_audios where id = v_em_voo),
    (select status from public.fabio_fila_audios where id = v_em_voo)
  );

  -- Quem ja estava num estado que a edge aceita nao pode ser reescrito: o
  -- 'erro' carrega a mensagem do que houve e o reset apagaria esse rastro.
  declare
    v_erro uuid;
  begin
    insert into public.fabio_fila_audios
      (professor_id, unidade_id, aula_id, storage_path, status, origem,
       erro_tipo, tentativas, vinculo_id, criado_em, atualizado_em)
    values
      (v_prof, v_unidade, 6, 'whatsapp/4242/com-erro.mp3', 'erro', 'whatsapp',
       'transitorio', 0, null, now() - interval '2 hours', now() - interval '2 hours')
    returning id into v_erro;

    perform public.fn_fabio_retry_fila();

    perform pg_temp.checar_20260815060000(
      'linha em erro continua em erro (o reset nao apaga o rastro)',
      (select status = 'erro' from public.fabio_fila_audios where id = v_erro),
      (select status from public.fabio_fila_audios where id = v_erro)
    );
  end;
end
$docker$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._fabio_20260815060000_res where not ok),
  'detalhe', coalesce((
    select json_agg(json_build_object(
      'passo', caso,
      'esperado', 'true',
      'obtido', detalhe
    ) order by caso)
      from pg_temp._fabio_20260815060000_res
     where not ok
  ), '[]'::json)
) as resumo;
20260815060000-DOCKER-DML-TESTS-FIM */
