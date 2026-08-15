-- O trecho executavel remotamente e um contrato de catalogo: nao cria fixtures
-- nem escreve em `aluno_presenca` viva. `fn_presenca_precedencia` e IMMUTABLE
-- e sem efeito colateral, entao chamar com literais aqui e seguro. O bloco
-- Docker no fim fica comentado de proposito e o mutante o extrai para um
-- PostgreSQL efemero, onde a chamada e a gravacao rodam de verdade.

create temporary table pg_temp._fabio_20260815010000_res (
  caso text,
  ok boolean,
  detalhe text
) on commit drop;

create or replace function pg_temp.checar_20260815010000(
  p_caso text,
  p_ok boolean,
  p_detalhe text
) returns void
language plpgsql
as $function$
begin
  insert into pg_temp._fabio_20260815010000_res(caso, ok, detalhe)
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
  v_core_def text; v_app_def text; v_whats_def text;
  v_core_norm text; v_app_norm text; v_whats_norm text;
begin
  -- A régua nova responde certo pra cada fonte do vocabulario.
  perform pg_temp.checar_20260815010000(
    'precedencia: manual > professor/audio/whatsapp > secretaria > resto',
    public.fn_presenca_precedencia('manual') = 3
      and public.fn_presenca_precedencia('professor_la_teacher') = 2
      and public.fn_presenca_precedencia('fabio_audio') = 2
      and public.fn_presenca_precedencia('professor_whatsapp') = 2
      and public.fn_presenca_precedencia('agenda_secretaria') = 1
      and public.fn_presenca_precedencia('emusys') = 0
      and public.fn_presenca_precedencia('sistema') = 0
      and public.fn_presenca_precedencia(null) = 0,
    jsonb_build_object(
      'manual', public.fn_presenca_precedencia('manual'),
      'professor_la_teacher', public.fn_presenca_precedencia('professor_la_teacher'),
      'fabio_audio', public.fn_presenca_precedencia('fabio_audio'),
      'professor_whatsapp', public.fn_presenca_precedencia('professor_whatsapp'),
      'agenda_secretaria', public.fn_presenca_precedencia('agenda_secretaria'),
      'emusys', public.fn_presenca_precedencia('emusys'),
      'nulo', public.fn_presenca_precedencia(null)
    )::text
  );

  if v_core is null or v_app is null or v_whats is null then
    perform pg_temp.checar_20260815010000(
      'as tres portas de presenca existem', false,
      'fn_registrar_presencas_core/app_registrar_presencas_aula/fabio_registrar_presencas_aula ausente'
    );
    return;
  end if;

  select pg_get_functiondef(v_core) into v_core_def;
  select pg_get_functiondef(v_app) into v_app_def;
  select pg_get_functiondef(v_whats) into v_whats_def;
  v_core_norm := lower(regexp_replace(v_core_def, '[[:space:]]+', ' ', 'g'));
  v_app_norm := lower(regexp_replace(v_app_def, '[[:space:]]+', ' ', 'g'));
  v_whats_norm := lower(regexp_replace(v_whats_def, '[[:space:]]+', ' ', 'g'));

  perform pg_temp.checar_20260815010000(
    'core: o on conflict decide por precedencia, nao por booleano forte/fraca',
    position(
      'where public.fn_presenca_precedencia(excluded.respondido_por) >= public.fn_presenca_precedencia(aluno_presenca.respondido_por)'
      in v_core_norm
    ) > 0
      and position('fn_presenca_e_forte' in v_core_norm) = 0,
    left(coalesce(v_core_def, ''), 2400)
  );

  perform pg_temp.checar_20260815010000(
    'core preserva o resto do contrato: janela, roster e as tres fontes validas',
    position('respondido_por_invalido' in v_core_norm) > 0
      and position('janela_de_chamada_encerrada' in v_core_norm) > 0
      and position('roster_incompleto' in v_core_norm) > 0
      and position('fn_sincronizar_gemeos_presenca' in v_core_norm) > 0,
    left(coalesce(v_core_def, ''), 1200)
  );

  perform pg_temp.checar_20260815010000(
    'app do professor: chamada_ja_enviada usa a mesma regua de precedencia',
    position(
      'and public.fn_presenca_precedencia(ap.respondido_por) >= public.fn_presenca_precedencia(''professor_la_teacher'')'
      in v_app_norm
    ) > 0
      and position('fn_presenca_e_forte' in v_app_norm) = 0
      and position('''professor_la_teacher'', true' in v_app_norm) > 0,
    left(coalesce(v_app_def, ''), 2400)
  );

  perform pg_temp.checar_20260815010000(
    'porta do whatsapp/audio: chamada_ja_enviada usa a mesma regua de precedencia',
    position(
      'and public.fn_presenca_precedencia(ap.respondido_por) >= public.fn_presenca_precedencia(''professor_la_teacher'')'
      in v_whats_norm
    ) > 0
      and position('fn_presenca_e_forte' in v_whats_norm) = 0
      and position('''professor_whatsapp'', true' in v_whats_norm) > 0,
    left(coalesce(v_whats_def, ''), 2400)
  );
end
$function$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._fabio_20260815010000_res where not ok),
  'detalhe', coalesce((
    select json_agg(json_build_object(
      'passo', caso,
      'esperado', 'true',
      'obtido', detalhe
    ) order by caso)
      from pg_temp._fabio_20260815010000_res
     where not ok
  ), '[]'::json)
) as resumo;

/* 20260815010000-DOCKER-DML-TESTS-INICIO
do $docker$
declare
  v_unidade uuid := '00000000-0000-0000-0000-000000000901';
  v_professor integer := 836;
  v_aula_secretaria integer := 9101;   -- caso A: professor corrige a secretaria
  v_aula_autocorrecao integer := 9102; -- caso B: professor corrige a si mesmo
  v_aula_manual integer := 9103;       -- caso C: manual e teto, professor nao passa por cima
  v_aula_fraca integer := 9104;        -- caso D: piso continua sobrescrevivel
  v_aula_curto_secretaria integer := 9105; -- caso E: chamada_ja_enviada nao trava so com secretaria
  v_aula_curto_professor integer := 9106;  -- caso F: chamada_ja_enviada continua travando com professor
  v_aula_whats integer := 9107;        -- caso G: mesma paridade na porta whatsapp/audio
  v_aluno integer := 90101;
  v_res jsonb;
begin
  insert into public.aulas_emusys (
    id, professor_id, unidade_id, cancelada, data_hora_inicio, data_hora_fim
  ) values
    (v_aula_secretaria, v_professor, v_unidade, false, now() - interval '1 hour', now()),
    (v_aula_autocorrecao, v_professor, v_unidade, false, now() - interval '1 hour', now()),
    (v_aula_manual, v_professor, v_unidade, false, now() - interval '1 hour', now()),
    (v_aula_fraca, v_professor, v_unidade, false, now() - interval '1 hour', now()),
    (v_aula_curto_secretaria, v_professor, v_unidade, false, now() - interval '1 hour', now()),
    (v_aula_curto_professor, v_professor, v_unidade, false, now() - interval '1 hour', now()),
    (v_aula_whats, v_professor, v_unidade, false, now() - interval '1 hour', now());
  insert into public.aula_alunos_emusys (aula_emusys_id, aluno_id) values
    (v_aula_secretaria, v_aluno), (v_aula_autocorrecao, v_aluno),
    (v_aula_manual, v_aluno), (v_aula_fraca, v_aluno),
    (v_aula_curto_secretaria, v_aluno), (v_aula_curto_professor, v_aluno),
    (v_aula_whats, v_aluno);

  -- CASO A (o bug do Valdo): secretaria marcou falta um dia antes; o professor,
  -- que estava na sala, chama os dois como presentes. Tem que valer.
  insert into public.aluno_presenca (
    aluno_id, aula_emusys_id, professor_id, unidade_id, data_aula, horario_aula,
    status, status_presenca, respondido_por, respondido_em
  ) values (
    v_aluno, v_aula_secretaria, v_professor, v_unidade, current_date, '18:00',
    'ausente', 'falta', 'agenda_secretaria', now() - interval '1 day'
  );
  perform public.fn_registrar_presencas_core(
    v_aula_secretaria, v_professor, '{}'::integer[], 'professor_la_teacher', true);
  perform pg_temp.checar_20260815010000(
    'caso A: professor corrige a secretaria (o bug do Valdo)',
    (select status_presenca = 'presente' and respondido_por = 'professor_la_teacher'
       from public.aluno_presenca
      where aluno_id = v_aluno and aula_emusys_id = v_aula_secretaria),
    coalesce((select status_presenca || '/' || respondido_por from public.aluno_presenca
      where aluno_id = v_aluno and aula_emusys_id = v_aula_secretaria), 'NULL')
  );

  -- CASO B: o professor tinha marcado ausente na chamada em lote; ao confirmar
  -- o audio ele diz que o aluno veio. A segunda fonte de professor tem que
  -- conseguir corrigir a primeira.
  perform public.fn_registrar_presencas_core(
    v_aula_autocorrecao, v_professor, array[v_aluno], 'professor_la_teacher', true);
  perform public.fn_registrar_presencas_core(
    v_aula_autocorrecao, v_professor, '{}'::integer[], 'fabio_audio', false);
  perform pg_temp.checar_20260815010000(
    'caso B: professor corrige a propria chamada anterior via audio',
    (select status_presenca = 'presente' and respondido_por = 'fabio_audio'
       from public.aluno_presenca
      where aluno_id = v_aluno and aula_emusys_id = v_aula_autocorrecao),
    coalesce((select status_presenca || '/' || respondido_por from public.aluno_presenca
      where aluno_id = v_aluno and aula_emusys_id = v_aula_autocorrecao), 'NULL')
  );

  -- CASO C: 'manual' e uma correcao definitiva da coordenacao — nem o
  -- professor pode passar por cima dela pela chamada normal.
  insert into public.aluno_presenca (
    aluno_id, aula_emusys_id, professor_id, unidade_id, data_aula, horario_aula,
    status, status_presenca, respondido_por, respondido_em
  ) values (
    v_aluno, v_aula_manual, v_professor, v_unidade, current_date, '18:00',
    'ausente', 'falta', 'manual', now() - interval '1 hour'
  );
  perform public.fn_registrar_presencas_core(
    v_aula_manual, v_professor, '{}'::integer[], 'professor_la_teacher', true);
  perform pg_temp.checar_20260815010000(
    'caso C: manual continua sendo teto — professor nao sobrescreve',
    (select status_presenca = 'falta' and respondido_por = 'manual'
       from public.aluno_presenca
      where aluno_id = v_aluno and aula_emusys_id = v_aula_manual),
    coalesce((select status_presenca || '/' || respondido_por from public.aluno_presenca
      where aluno_id = v_aluno and aula_emusys_id = v_aula_manual), 'NULL')
  );

  -- CASO D: piso (emusys/sem resposta humana) continua livremente sobrescrevivel.
  insert into public.aluno_presenca (
    aluno_id, aula_emusys_id, professor_id, unidade_id, data_aula, horario_aula,
    status, status_presenca, respondido_por, respondido_em,
    emusys_presenca_bruta
  ) values (
    v_aluno, v_aula_fraca, v_professor, v_unidade, current_date, '18:00',
    'presente', 'presente', 'emusys', now() - interval '2 hours', 'presente'
  );
  perform public.fn_registrar_presencas_core(
    v_aula_fraca, v_professor, array[v_aluno], 'professor_la_teacher', true);
  perform pg_temp.checar_20260815010000(
    'caso D: piso (emusys) continua sobrescrevivel pelo professor',
    (select status_presenca = 'falta' and respondido_por = 'professor_la_teacher'
       from public.aluno_presenca
      where aluno_id = v_aluno and aula_emusys_id = v_aula_fraca),
    coalesce((select status_presenca || '/' || respondido_por from public.aluno_presenca
      where aluno_id = v_aluno and aula_emusys_id = v_aula_fraca), 'NULL')
  );

  -- CASO E: com SÓ a secretaria tendo respondido, a chamada do professor não
  -- pode se declarar "já enviada" — senão ele nunca alcança o core acima.
  insert into public.aluno_presenca (
    aluno_id, aula_emusys_id, professor_id, unidade_id, data_aula, horario_aula,
    status, status_presenca, respondido_por, respondido_em
  ) values (
    v_aluno, v_aula_curto_secretaria, v_professor, v_unidade, current_date, '18:00',
    'ausente', 'falta', 'agenda_secretaria', now() - interval '1 day'
  );
  select public.app_registrar_presencas_aula(v_aula_curto_secretaria, '{}'::integer[])
    into v_res;
  perform pg_temp.checar_20260815010000(
    'caso E: chamada_ja_enviada nao trava so com secretaria — o professor consegue chamar',
    coalesce((v_res ->> 'chamada_ja_enviada')::boolean, true) = false
      and (select status_presenca = 'presente' and respondido_por = 'professor_la_teacher'
             from public.aluno_presenca
            where aluno_id = v_aluno and aula_emusys_id = v_aula_curto_secretaria),
    coalesce(v_res, '{}'::jsonb)::text
  );

  -- CASO F: com o PROFESSOR já tendo respondido, chamada_ja_enviada continua
  -- travando (nao regride pra sempre tentar de novo à toa).
  insert into public.aluno_presenca (
    aluno_id, aula_emusys_id, professor_id, unidade_id, data_aula, horario_aula,
    status, status_presenca, respondido_por, respondido_em
  ) values (
    v_aluno, v_aula_curto_professor, v_professor, v_unidade, current_date, '18:00',
    'presente', 'presente', 'professor_la_teacher', now() - interval '10 minutes'
  );
  select public.app_registrar_presencas_aula(v_aula_curto_professor, '{}'::integer[])
    into v_res;
  perform pg_temp.checar_20260815010000(
    'caso F: chamada_ja_enviada ainda trava quando o professor ja respondeu',
    coalesce((v_res ->> 'chamada_ja_enviada')::boolean, false) = true,
    coalesce(v_res, '{}'::jsonb)::text
  );

  -- CASO G: mesma paridade na porta do whatsapp/audio (fabio_registrar_presencas_aula).
  insert into public.aluno_presenca (
    aluno_id, aula_emusys_id, professor_id, unidade_id, data_aula, horario_aula,
    status, status_presenca, respondido_por, respondido_em
  ) values (
    v_aluno, v_aula_whats, v_professor, v_unidade, current_date, '18:00',
    'ausente', 'falta', 'agenda_secretaria', now() - interval '1 day'
  );
  select public.fabio_registrar_presencas_aula(v_professor, v_aula_whats, '{}'::integer[])
    into v_res;
  perform pg_temp.checar_20260815010000(
    'caso G: a porta whatsapp/audio tambem corrige a secretaria',
    coalesce((v_res ->> 'chamada_ja_enviada')::boolean, true) = false
      and (select status_presenca = 'presente' and respondido_por = 'professor_whatsapp'
             from public.aluno_presenca
            where aluno_id = v_aluno and aula_emusys_id = v_aula_whats),
    coalesce(v_res, '{}'::jsonb)::text
  );
end
$docker$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._fabio_20260815010000_res where not ok),
  'detalhe', coalesce((
    select json_agg(json_build_object(
      'passo', caso,
      'esperado', 'true',
      'obtido', detalhe
    ) order by caso)
      from pg_temp._fabio_20260815010000_res
     where not ok
  ), '[]'::json)
) as resumo;
20260815010000-DOCKER-DML-TESTS-FIM */
