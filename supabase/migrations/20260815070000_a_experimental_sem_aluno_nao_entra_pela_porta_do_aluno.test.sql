-- O trecho executavel remotamente e um contrato de catalogo: nao cria fixtures
-- nem escreve em public. O bloco Docker no fim fica comentado de proposito e o
-- mutante o extrai para um PostgreSQL efemero, onde a guarda roda de verdade.

create temporary table pg_temp._fabio_20260815070000_res (
  caso text, ok boolean, detalhe text
) on commit drop;

create or replace function pg_temp.checar_20260815070000(
  p_caso text, p_ok boolean, p_detalhe text
) returns void language plpgsql as $function$
begin
  insert into pg_temp._fabio_20260815070000_res(caso, ok, detalhe)
  values (p_caso, coalesce(p_ok, false), p_detalhe);
end
$function$;

do $function$
declare
  v_fn regprocedure := to_regprocedure(
    'public.fn_enfileirar_audio_core(integer,text,integer,uuid,text,integer)'
  );
  v_norm text;
begin
  perform pg_temp.checar_20260815070000(
    'fn_enfileirar_audio_core continua existindo', v_fn is not null,
    coalesce(v_fn::text, '<ausente>')
  );
  if v_fn is null then return; end if;

  v_norm := lower(regexp_replace(pg_get_functiondef(v_fn), '\s+', ' ', 'g'));

  perform pg_temp.checar_20260815070000(
    'a guarda da porta errada existe',
    v_norm like '%aula_experimental_usa_porta_propria%',
    substring(v_norm from 1 for 700)
  );

  -- A guarda tem DUAS pernas de proposito. So `categoria` quebraria a
  -- experimental cujo lead ja virou aluno, que hoje FUNCIONA.
  perform pg_temp.checar_20260815070000(
    'a guarda exige experimental E sem aluno no roster (nao so categoria)',
    v_norm like '%categoria = ''experimental''%'
      and v_norm like '%not exists%'
      and v_norm like '%r.aluno_id is not null%',
    substring(v_norm from 1 for 700)
  );

  -- O que ja existia nao pode ter sido perdido no caminho.
  perform pg_temp.checar_20260815070000(
    'guardas anteriores preservadas',
    v_norm like '%aula_nao_pertence_ao_professor%'
      and v_norm like '%aula_cancelada%'
      and v_norm like '%janela_de_gravacao_encerrada%'
      and v_norm like '%gravacao_ainda_nao_disponivel%',
    substring(v_norm from 1 for 700)
  );

  perform pg_temp.checar_20260815070000(
    'a trilha manual continua sem engolir o audio (conserto de 14/08)',
    v_norm like '%r.modo_entrada = ''audio''%',
    substring(v_norm from 1 for 700)
  );

  perform pg_temp.checar_20260815070000(
    'a normalizacao de gemeos continua (fn_aula_operacional_id)',
    v_norm like '%fn_aula_operacional_id%',
    substring(v_norm from 1 for 700)
  );
end
$function$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._fabio_20260815070000_res where not ok),
  'detalhe', coalesce((
    select json_agg(json_build_object('passo', caso, 'esperado', 'true', 'obtido', detalhe) order by caso)
      from pg_temp._fabio_20260815070000_res where not ok
  ), '[]'::json)
) as resumo;

/* 20260815070000-DOCKER-DML-TESTS-INICIO
do $docker$
declare
  v_prof integer := 4242;
  v_unidade uuid := gen_random_uuid();
  v_resp jsonb;
  v_erro text;
begin
  insert into public.unidades(id, nome) values (v_unidade, 'U') on conflict do nothing;
  insert into public.professores(id, nome) values (v_prof, 'P') on conflict do nothing;

  -- 1. EXPERIMENTAL com LEAD (aluno_id nulo): a porta errada. Tem que RECUSAR.
  insert into public.aulas_emusys(id, professor_id, unidade_id, categoria, data_hora_inicio, data_hora_fim)
  values (901, v_prof, v_unidade, 'experimental', now() - interval '1 hour', now() - interval '10 minutes');
  insert into public.aula_alunos_emusys(aula_emusys_id, aluno_id) values (901, null);

  begin
    v_resp := public.fn_enfileirar_audio_core(901, 'app/exp-lead.webm', 10, null, 'app', v_prof);
    v_erro := '<nao levantou>';
  exception when others then
    v_erro := sqlerrm;
  end;
  perform pg_temp.checar_20260815070000(
    'experimental com lead (sem aluno) e RECUSADA na entrada',
    v_erro like '%aula_experimental_usa_porta_propria%',
    v_erro
  );
  perform pg_temp.checar_20260815070000(
    'e nada foi enfileirado (nao aceita para perder depois)',
    (select count(*) = 0 from public.fabio_fila_audios where aula_id = 901),
    (select count(*)::text from public.fabio_fila_audios where aula_id = 901)
  );

  -- 2. EXPERIMENTAL cujo lead JA virou aluno: hoje funciona. NAO pode quebrar.
  insert into public.alunos(id, nome) values (77, 'Ja Matriculado') on conflict do nothing;
  insert into public.aulas_emusys(id, professor_id, unidade_id, categoria, data_hora_inicio, data_hora_fim)
  values (902, v_prof, v_unidade, 'experimental', now() - interval '1 hour', now() - interval '10 minutes');
  insert into public.aula_alunos_emusys(aula_emusys_id, aluno_id) values (902, 77);

  begin
    v_resp := public.fn_enfileirar_audio_core(902, 'app/exp-aluno.webm', 10, null, 'app', v_prof);
    v_erro := null;
  exception when others then
    v_erro := sqlerrm;
  end;
  perform pg_temp.checar_20260815070000(
    'experimental cujo lead virou aluno CONTINUA passando (sem falso positivo)',
    v_erro is null and (v_resp ->> 'audio_id') is not null and (v_resp ->> 'status') = 'pendente',
    coalesce(v_erro, coalesce(v_resp, '{}'::jsonb)::text)
  );

  -- 3. AULA NORMAL com roster vazio: NAO e assunto desta guarda. Continua
  --    passando — existe caso real assim que gera registro pelo fallback da
  --    carteira do professor.
  insert into public.aulas_emusys(id, professor_id, unidade_id, categoria, data_hora_inicio, data_hora_fim)
  values (903, v_prof, v_unidade, 'normal', now() - interval '1 hour', now() - interval '10 minutes');

  begin
    v_resp := public.fn_enfileirar_audio_core(903, 'app/normal-vazia.webm', 10, null, 'app', v_prof);
    v_erro := null;
  exception when others then
    v_erro := sqlerrm;
  end;
  perform pg_temp.checar_20260815070000(
    'aula NORMAL com roster vazio continua passando (outra investigacao)',
    v_erro is null and (v_resp ->> 'audio_id') is not null,
    coalesce(v_erro, coalesce(v_resp, '{}'::jsonb)::text)
  );

  -- 4. AULA NORMAL comum: o caminho de todo dia, intocado.
  insert into public.aulas_emusys(id, professor_id, unidade_id, categoria, data_hora_inicio, data_hora_fim)
  values (904, v_prof, v_unidade, 'normal', now() - interval '1 hour', now() - interval '10 minutes');
  insert into public.aula_alunos_emusys(aula_emusys_id, aluno_id) values (904, 77);

  begin
    v_resp := public.fn_enfileirar_audio_core(904, 'app/normal.webm', 10, null, 'app', v_prof);
    v_erro := null;
  exception when others then
    v_erro := sqlerrm;
  end;
  perform pg_temp.checar_20260815070000(
    'aula normal com aluno segue enfileirando (sem regressao)',
    v_erro is null and (v_resp ->> 'status') = 'pendente',
    coalesce(v_erro, coalesce(v_resp, '{}'::jsonb)::text)
  );
end
$docker$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._fabio_20260815070000_res where not ok),
  'detalhe', coalesce((
    select json_agg(json_build_object('passo', caso, 'esperado', 'true', 'obtido', detalhe) order by caso)
      from pg_temp._fabio_20260815070000_res where not ok
  ), '[]'::json)
) as resumo;
20260815070000-DOCKER-DML-TESTS-FIM */
