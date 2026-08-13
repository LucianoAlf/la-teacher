-- A régua de precedência é UMA só, e o core pergunta pra ela.
--
-- O teste é comportamental, não só de texto: monta presença de fonte forte e
-- manda o core tentar sobrescrever. Se ele pisar, o passo cai.

create temporary table _regua_res(caso text, ok boolean, detalhe text) on commit drop;

create or replace function pg_temp.checar_regua(p_caso text, p_ok boolean, p_detalhe text)
returns void language plpgsql as $$
begin insert into _regua_res values (p_caso, coalesce(p_ok,false), p_detalhe); end $$;

do $$
declare
  v_aula   public.aulas_emusys%rowtype;
  v_aluno  integer;
  v_depois text;
  v_res    jsonb;
begin
  -- Fixture: uma aula real com roster, no passado, nao cancelada.
  select a.* into v_aula
    from public.aulas_emusys a
   where exists (select 1 from public.aula_alunos_emusys r
                  where r.aula_emusys_id = a.id and r.aluno_id is not null)
     and not coalesce(a.cancelada,false)
     and a.data_hora_inicio < now()
   order by a.data_hora_inicio desc limit 1;

  select r.aluno_id into v_aluno
    from public.aula_alunos_emusys r
   where r.aula_emusys_id = v_aula.id and r.aluno_id is not null limit 1;

  perform pg_temp.checar_regua('fixture: achou aula com roster',
    v_aula.id is not null and v_aluno is not null,
    format('aula=%s aluno=%s', v_aula.id, v_aluno));
  if v_aula.id is null or v_aluno is null then return; end if;

  -- 1) FONTE FORTE JA GRAVADA NAO PODE SER PISADA.
  delete from public.aluno_presenca
   where aluno_id = v_aluno and aula_emusys_id = v_aula.id;
  insert into public.aluno_presenca
    (aluno_id, aula_emusys_id, professor_id, unidade_id, data_aula, horario_aula,
     status, status_presenca, respondido_por, respondido_em)
  values (v_aluno, v_aula.id, v_aula.professor_id, v_aula.unidade_id,
          (v_aula.data_hora_inicio at time zone 'America/Sao_Paulo')::date,
          (v_aula.data_hora_inicio at time zone 'America/Sao_Paulo')::time,
          'ausente', 'falta', 'agenda_secretaria', now());

  v_res := public.fn_registrar_presencas_core(
             v_aula.id, v_aula.professor_id, '{}'::integer[], 'fabio_audio', false);

  select respondido_por into v_depois
    from public.aluno_presenca where aluno_id = v_aluno and aula_emusys_id = v_aula.id;
  perform pg_temp.checar_regua(
    'decisao da secretaria NAO e pisada pelo audio do Fabio',
    v_depois = 'agenda_secretaria',
    format('ficou como %s (esperado agenda_secretaria) | %s', coalesce(v_depois,'<NULL>'), v_res));

  -- 2) FONTE FRACA PODE, SIM, SER PROMOVIDA.
  update public.aluno_presenca
     set respondido_por = 'emusys', status_presenca = 'falta', status = 'ausente'
   where aluno_id = v_aluno and aula_emusys_id = v_aula.id;

  perform public.fn_registrar_presencas_core(
            v_aula.id, v_aula.professor_id, '{}'::integer[], 'fabio_audio', false);

  select respondido_por into v_depois
    from public.aluno_presenca where aluno_id = v_aluno and aula_emusys_id = v_aula.id;
  perform pg_temp.checar_regua(
    'emusys E promovido quando o professor afirma',
    v_depois = 'fabio_audio',
    format('ficou como %s (esperado fabio_audio)', coalesce(v_depois,'<NULL>')));

  -- 3) O core tem que PERGUNTAR pra regua, nao repetir a lista.
  perform pg_temp.checar_regua(
    'o core consulta fn_presenca_e_forte',
    (select pg_get_functiondef(p.oid) from pg_proc p
       join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='fn_registrar_presencas_core')
      ilike '%fn_presenca_e_forte(aluno_presenca.respondido_por)%',
    'a clausula de sobrescrita tem que derivar da regua');

  perform pg_temp.checar_regua(
    'o core NAO repete a lista de fontes fracas na mao',
    (select pg_get_functiondef(p.oid) from pg_proc p
       join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='fn_registrar_presencas_core')
      not ilike '%(''emusys'', ''sistema'')%',
    'lista negativa envelhece sozinha');

  -- 4) A regua canonica continua sendo a mesma que a agenda usa.
  perform pg_temp.checar_regua(
    'agenda e regua canonica concordam sobre quem e forte',
    (select bool_and(public.fn_presenca_e_forte(f)) from unnest(array[
       'professor_la_teacher','professor_whatsapp','manual','fabio_audio','agenda_secretaria']) f)
    and (select bool_and(not public.fn_presenca_e_forte(f)) from unnest(array['emusys','sistema']) f),
    '5 fortes x 2 fracos');
end $$;

select json_build_object(
  'teste', '20260813220000-uma-regua-so-de-precedencia',
  'falhas', (select count(*) from _regua_res where not ok),
  'detalhe', coalesce((select json_agg(json_build_object(
    'passo', caso, 'esperado','ok','obtido', coalesce(detalhe,'<NULL>'))
  ) from _regua_res where not ok), '[]'::json)
) as resumo;
