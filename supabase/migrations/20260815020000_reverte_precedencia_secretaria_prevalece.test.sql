-- Trava a REGRA DE NEGÓCIO que eu tinha invertido: a presença lançada pela
-- SECRETARIA prevalece sobre a do professor. Não é detalhe de implementação —
-- é decisão da casa (Alf, 15/08/2026), e um teste é o que impede que ela seja
-- "consertada" de novo por quem ler o código sem conhecer o combinado.
--
-- O trecho remoto é contrato de catálogo; o bloco Docker no fim (comentado)
-- exercita a gravação de verdade num PostgreSQL efêmero.

create temporary table pg_temp._fabio_20260815020000_res (
  caso text,
  ok boolean,
  detalhe text
) on commit drop;

create or replace function pg_temp.checar_20260815020000(
  p_caso text,
  p_ok boolean,
  p_detalhe text
) returns void
language plpgsql
as $function$
begin
  insert into pg_temp._fabio_20260815020000_res(caso, ok, detalhe)
  values (p_caso, coalesce(p_ok, false), p_detalhe);
end
$function$;

do $function$
declare
  v_core regprocedure := to_regprocedure(
    'public.fn_registrar_presencas_core(integer,integer,integer[],text,boolean)'
  );
  v_app regprocedure := to_regprocedure(
    'public.app_registrar_presencas_aula(integer,integer[])'
  );
  v_whats regprocedure := to_regprocedure(
    'public.fabio_registrar_presencas_aula(integer,integer,integer[])'
  );
  v_core_norm text; v_app_norm text; v_whats_norm text;
begin
  -- A régua de precedência que eu inventei não pode voltar a existir: ela é
  -- justamente o que permitiria o professor pisar na resposta da secretaria.
  perform pg_temp.checar_20260815020000(
    'a regua de precedencia inventada nao existe no catalogo',
    to_regprocedure('public.fn_presenca_precedencia(text)') is null,
    coalesce(to_regprocedure('public.fn_presenca_precedencia(text)')::text, 'ausente')
  );

  if v_core is null or v_app is null or v_whats is null then
    perform pg_temp.checar_20260815020000(
      'as tres portas de presenca existem', false, 'alguma porta ausente');
    return;
  end if;

  v_core_norm := lower(regexp_replace(pg_get_functiondef(v_core), '[[:space:]]+', ' ', 'g'));
  v_app_norm := lower(regexp_replace(pg_get_functiondef(v_app), '[[:space:]]+', ' ', 'g'));
  v_whats_norm := lower(regexp_replace(pg_get_functiondef(v_whats), '[[:space:]]+', ' ', 'g'));

  perform pg_temp.checar_20260815020000(
    'core: qualquer resposta humana ja gravada e preservada (first write wins)',
    position(
      'where not public.fn_presenca_e_forte(aluno_presenca.respondido_por)' in v_core_norm
    ) > 0
      and position('fn_presenca_precedencia' in v_core_norm) = 0,
    left(pg_get_functiondef(v_core), 2400)
  );

  perform pg_temp.checar_20260815020000(
    'app do professor: chamada ja respondida (inclusive pela secretaria) nao e refeita',
    position('and public.fn_presenca_e_forte(ap.respondido_por))) then' in v_app_norm) > 0
      and position('fn_presenca_precedencia' in v_app_norm) = 0,
    left(pg_get_functiondef(v_app), 2400)
  );

  perform pg_temp.checar_20260815020000(
    'porta whatsapp/audio: mesma preservacao da resposta ja gravada',
    position('and public.fn_presenca_e_forte(ap.respondido_por))) then' in v_whats_norm) > 0
      and position('fn_presenca_precedencia' in v_whats_norm) = 0,
    left(pg_get_functiondef(v_whats), 2400)
  );

  -- A secretaria tem que continuar sendo fonte forte: e isso que faz a
  -- resposta dela ser preservada contra o professor.
  perform pg_temp.checar_20260815020000(
    'agenda_secretaria continua sendo fonte forte',
    public.fn_presenca_e_forte('agenda_secretaria')
      and public.fn_presenca_e_forte('professor_la_teacher')
      and not public.fn_presenca_e_forte('emusys'),
    jsonb_build_object(
      'agenda_secretaria', public.fn_presenca_e_forte('agenda_secretaria'),
      'professor_la_teacher', public.fn_presenca_e_forte('professor_la_teacher'),
      'emusys', public.fn_presenca_e_forte('emusys')
    )::text
  );
end
$function$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._fabio_20260815020000_res where not ok),
  'detalhe', coalesce((
    select json_agg(json_build_object(
      'passo', caso, 'esperado', 'true', 'obtido', detalhe
    ) order by caso)
      from pg_temp._fabio_20260815020000_res where not ok
  ), '[]'::json)
) as resumo;

/* 20260815020000-DOCKER-DML-TESTS-INICIO
do $docker$
declare
  v_unidade uuid := '00000000-0000-0000-0000-000000000911';
  v_professor integer := 836;
  v_aula_secretaria integer := 9201;
  v_aula_livre integer := 9202;
  v_aluno integer := 90201;
  v_res jsonb;
begin
  insert into public.aulas_emusys (
    id, professor_id, unidade_id, cancelada, data_hora_inicio, data_hora_fim
  ) values
    (v_aula_secretaria, v_professor, v_unidade, false, now() - interval '1 hour', now()),
    (v_aula_livre, v_professor, v_unidade, false, now() - interval '1 hour', now());
  insert into public.aula_alunos_emusys (aula_emusys_id, aluno_id) values
    (v_aula_secretaria, v_aluno), (v_aula_livre, v_aluno);

  -- A REGRA: a secretaria lancou falta; o professor tenta marcar presente.
  -- A resposta da secretaria PREVALECE — o professor nao sobrescreve.
  insert into public.aluno_presenca (
    aluno_id, aula_emusys_id, professor_id, unidade_id, data_aula, horario_aula,
    status, status_presenca, respondido_por, respondido_em
  ) values (
    v_aluno, v_aula_secretaria, v_professor, v_unidade, current_date, '18:00',
    'ausente', 'falta', 'agenda_secretaria', now() - interval '1 day'
  );
  perform public.fn_registrar_presencas_core(
    v_aula_secretaria, v_professor, '{}'::integer[], 'professor_la_teacher', true);
  perform pg_temp.checar_20260815020000(
    'a presenca lancada pela secretaria PREVALECE sobre a do professor',
    (select status_presenca = 'falta' and respondido_por = 'agenda_secretaria'
       from public.aluno_presenca
      where aluno_id = v_aluno and aula_emusys_id = v_aula_secretaria),
    coalesce((select status_presenca || '/' || respondido_por from public.aluno_presenca
      where aluno_id = v_aluno and aula_emusys_id = v_aula_secretaria), 'NULL')
  );

  -- E o app do professor nao pede a chamada de novo quando a secretaria ja
  -- respondeu por todo mundo: ele ve como ja enviada.
  select public.app_registrar_presencas_aula(v_aula_secretaria, '{}'::integer[])
    into v_res;
  perform pg_temp.checar_20260815020000(
    'com a secretaria tendo respondido, a chamada aparece como ja enviada',
    coalesce((v_res ->> 'chamada_ja_enviada')::boolean, false) = true,
    coalesce(v_res, '{}'::jsonb)::text
  );

  -- Sem ninguem ter respondido, o professor lanca normalmente (a janela dele
  -- continua valendo — a regra tira o sobrescrito, nao o direito de lancar).
  select public.app_registrar_presencas_aula(v_aula_livre, array[v_aluno])
    into v_res;
  perform pg_temp.checar_20260815020000(
    'sem resposta previa, o professor continua lancando presenca normalmente',
    coalesce((v_res ->> 'chamada_ja_enviada')::boolean, true) = false
      and (select status_presenca = 'falta' and respondido_por = 'professor_la_teacher'
             from public.aluno_presenca
            where aluno_id = v_aluno and aula_emusys_id = v_aula_livre),
    coalesce(v_res, '{}'::jsonb)::text
  );
end
$docker$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._fabio_20260815020000_res where not ok),
  'detalhe', coalesce((
    select json_agg(json_build_object(
      'passo', caso, 'esperado', 'true', 'obtido', detalhe
    ) order by caso)
      from pg_temp._fabio_20260815020000_res where not ok
  ), '[]'::json)
) as resumo;
20260815020000-DOCKER-DML-TESTS-FIM */
