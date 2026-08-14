-- O trecho executavel remotamente e um contrato de catalogo: nao cria fixtures
-- nem escreve em public. O bloco Docker no fim fica comentado de proposito e o
-- mutante o extrai para um PostgreSQL efemero, onde a gravacao roda de verdade.

create temporary table pg_temp._fabio_20260814230000_res (
  caso text,
  ok boolean,
  detalhe text
) on commit drop;

create or replace function pg_temp.checar_20260814230000(
  p_caso text,
  p_ok boolean,
  p_detalhe text
) returns void
language plpgsql
as $function$
begin
  insert into pg_temp._fabio_20260814230000_res(caso, ok, detalhe)
  values (p_caso, coalesce(p_ok, false), p_detalhe);
end
$function$;

do $function$
declare
  v_core regprocedure := to_regprocedure(
    'public.fn_enfileirar_audio_core(integer,text,integer,uuid,text,integer)'
  );
  v_core_def text;
  v_core_norm text;
begin
  if v_core is null then
    perform pg_temp.checar_20260814230000(
      'core de audio existe para proteger nova gravacao', false,
      'fn_enfileirar_audio_core(integer,text,integer,uuid,text,integer) ausente'
    );
    return;
  end if;

  select pg_get_functiondef(v_core) into v_core_def;
  v_core_norm := lower(regexp_replace(v_core_def, '[[:space:]]+', ' ', 'g'));

  -- O coracao do conserto: so um rascunho de AUDIO retoma a confirmacao. Sem
  -- este filtro, a ficha manual vazia sequestra e engole a gravacao por audio.
  perform pg_temp.checar_20260814230000(
    'so um rascunho de audio retoma a confirmacao (ficha manual nao bloqueia)',
    position('and r.modo_entrada = ''audio''' in v_core_norm) > 0
      and position('from public.fabio_registros_aula r' in v_core_norm) > 0
      and position('and r.parent_id is null' in v_core_norm) > 0
      and position('and r.status in (''rascunho'', ''aguardando_confirmacao'')' in v_core_norm) > 0
      and position('''rascunho_existente'', true' in v_core_norm) > 0,
    left(coalesce(v_core_def, ''), 2400)
  );

  -- Nada do resto da porta pode ter regredido junto com o filtro novo.
  perform pg_temp.checar_20260814230000(
    'core preserva fila viva, dedupe por path, complemento e janela',
    position('and f.status in (''pendente'', ''transcrevendo'', ''transcrito'', ''erro'')' in v_core_norm) > 0
      and position('''ja_em_processamento'', true' in v_core_norm) > 0
      and position('and storage_path = v_storage_path' in v_core_norm) > 0
      and position('if p_registro_id is not null then' in v_core_norm) > 0
      and position('janela_de_gravacao_encerrada' in v_core_norm) > 0
      and not has_function_privilege(
        'authenticated',
        'public.fn_enfileirar_audio_core(integer,text,integer,uuid,text,integer)',
        'EXECUTE'
      ),
    left(coalesce(v_core_def, ''), 2400)
  );
end
$function$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._fabio_20260814230000_res where not ok),
  'detalhe', coalesce((
    select json_agg(json_build_object(
      'passo', caso,
      'esperado', 'true',
      'obtido', detalhe
    ) order by caso)
      from pg_temp._fabio_20260814230000_res
     where not ok
  ), '[]'::json)
) as resumo;

/* 20260814230000-DOCKER-DML-TESTS-INICIO
do $docker$
declare
  v_unidade uuid := '00000000-0000-0000-0000-000000000701';
  v_professor integer := 799;
  v_aula_manual_vazia integer := 9001;
  v_aula_audio integer := 9002;
  v_aula_manual_cheia integer := 9003;
  v_raiz_manual_vazia uuid := '00000000-0000-0000-0000-000000000801';
  v_raiz_audio uuid := '00000000-0000-0000-0000-000000000802';
  v_raiz_manual_cheia uuid := '00000000-0000-0000-0000-000000000803';
  v_resp jsonb;
begin
  insert into public.aulas_emusys (
    id, professor_id, unidade_id, cancelada, data_hora_inicio, data_hora_fim
  ) values
    (v_aula_manual_vazia, v_professor, v_unidade, false, now() - interval '1 hour', now()),
    (v_aula_audio, v_professor, v_unidade, false, now() - interval '1 hour', now()),
    (v_aula_manual_cheia, v_professor, v_unidade, false, now() - interval '1 hour', now());
  insert into public.aula_alunos_emusys (aula_emusys_id, aluno_id) values
    (v_aula_manual_vazia, 79001),
    (v_aula_audio, 79002),
    (v_aula_manual_cheia, 79003);
  insert into public.alunos (id, nome) values
    (79001, 'Aluno Um'), (79002, 'Aluno Dois'), (79003, 'Aluno Tres');

  -- CASO A (o bug do Matheus): ficha manual VAZIA e abandonada nao pode engolir
  -- a gravacao. A porta tem que criar a fila e mandar processar.
  insert into public.fabio_registros_aula (
    id, aula_id, unidade_id, parent_id, professor_id, aluno_id, molde, campos,
    texto_consolidado, status, origem, audio_id, modo_entrada
  ) values (
    v_raiz_manual_vazia, v_aula_manual_vazia, v_unidade, null, v_professor, null,
    'C', '{}'::jsonb, null, 'rascunho', 'app', null, 'manual'
  );
  select public.fn_enfileirar_audio_core(
    v_aula_manual_vazia, 'task/manual-vazia.webm', 12, null, 'app', v_professor
  ) into v_resp;
  perform pg_temp.checar_20260814230000(
    'ficha manual vazia NAO engole o audio: cria fila e vai processar',
    (v_resp ->> 'audio_id') is not null
      and (v_resp ->> 'status') = 'pendente'
      and not coalesce((v_resp ->> 'rascunho_existente')::boolean, false)
      and (select count(*) = 1 from public.fabio_fila_audios f
            where f.professor_id = v_professor and f.aula_id = v_aula_manual_vazia),
    coalesce(v_resp, '{}'::jsonb)::text
  );

  -- CASO B (guarda preservada): um rascunho de AUDIO aguardando confirmacao
  -- continua retomando a confirmacao, sem criar fila duplicada.
  insert into public.fabio_registros_aula (
    id, aula_id, unidade_id, parent_id, professor_id, aluno_id, molde, campos,
    texto_consolidado, status, origem, audio_id, modo_entrada
  ) values (
    v_raiz_audio, v_aula_audio, v_unidade, null, v_professor, null,
    'C', '{}'::jsonb, null, 'aguardando_confirmacao', 'app', null, 'audio'
  );
  select public.fn_enfileirar_audio_core(
    v_aula_audio, 'task/audio-aguardando.webm', 12, null, 'app', v_professor
  ) into v_resp;
  perform pg_temp.checar_20260814230000(
    'rascunho de audio aguardando confirmacao continua sendo retomado',
    coalesce((v_resp ->> 'rascunho_existente')::boolean, false)
      and (v_resp ->> 'registro_id') = v_raiz_audio::text
      and (v_resp ->> 'audio_id') is null
      and (select count(*) = 0 from public.fabio_fila_audios f
            where f.professor_id = v_professor and f.aula_id = v_aula_audio),
    coalesce(v_resp, '{}'::jsonb)::text
  );

  -- CASO C (trilha separada): mesmo uma ficha manual COM conteudo e uma trilha
  -- separada — a gravacao por audio segue seu proprio caminho e nao e engolida.
  insert into public.fabio_registros_aula (
    id, aula_id, unidade_id, parent_id, professor_id, aluno_id, molde, campos,
    texto_consolidado, status, origem, audio_id, modo_entrada
  ) values (
    v_raiz_manual_cheia, v_aula_manual_cheia, v_unidade, null, v_professor, null,
    'C', jsonb_build_object('objetivo', 'escrito a mao'), 'Objetivo: escrito a mao',
    'rascunho', 'app', null, 'manual'
  );
  select public.fn_enfileirar_audio_core(
    v_aula_manual_cheia, 'task/manual-cheia.webm', 12, null, 'app', v_professor
  ) into v_resp;
  perform pg_temp.checar_20260814230000(
    'ficha manual com conteudo tambem nao engole o audio (trilha separada)',
    (v_resp ->> 'audio_id') is not null
      and (v_resp ->> 'status') = 'pendente'
      and not coalesce((v_resp ->> 'rascunho_existente')::boolean, false)
      and (select count(*) = 1 from public.fabio_fila_audios f
            where f.professor_id = v_professor and f.aula_id = v_aula_manual_cheia),
    coalesce(v_resp, '{}'::jsonb)::text
  );
end
$docker$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._fabio_20260814230000_res where not ok),
  'detalhe', coalesce((
    select json_agg(json_build_object(
      'passo', caso,
      'esperado', 'true',
      'obtido', detalhe
    ) order by caso)
      from pg_temp._fabio_20260814230000_res
     where not ok
  ), '[]'::json)
) as resumo;
20260814230000-DOCKER-DML-TESTS-FIM */
