-- Teste transacional da retomada segura: nenhum fixture persiste fora do
-- ROLLBACK do runner. A policy e verificada estruturalmente; a prova de RLS
-- autentica acontece no E2E com upload real pelo app.

create temp table _res_audio_exp_duravel(
  passo text,
  esperado text,
  obtido text
) on commit drop;

insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000081301', 'ZZTESTE unidade audio duravel', 'ZZADURAVEL')
on conflict (id) do nothing;

insert into public.usuarios (id, nome, email, auth_user_id) values
  (-81301, 'ZZTESTE Professor audio duravel', 'zz-audio-duravel@exemplo.invalido',
   '00000000-0000-4000-8000-000000081301');
insert into public.professores (id, nome, usuario_id) values
  (-81301, 'ZZTESTE Professor audio duravel', -81301);

insert into public.leads (id, unidade_id, whatsapp, status) values
  (-81301, '00000000-0000-4000-8000-000000081301', '5521999813001', 'novo'),
  (-81302, '00000000-0000-4000-8000-000000081301', '5521999813002', 'novo');
insert into public.lead_experimentais (
  id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
  status, professor_experimental_id
) values
  (-81301, -81301, 'ZZTESTE Audio Um', '00000000-0000-4000-8000-000000081301',
   (now() at time zone 'America/Sao_Paulo')::date, '10:00', 'experimental_agendada', -81301),
  (-81302, -81302, 'ZZTESTE Audio Dois', '00000000-0000-4000-8000-000000081301',
   (now() at time zone 'America/Sao_Paulo')::date, '11:00', 'experimental_agendada', -81301);
insert into public.aulas_emusys (
  id, emusys_id, unidade_id, data_aula, data_hora_inicio, data_hora_fim,
  categoria, curso_nome, professor_id, cancelada
) values
  (-81301, -981301, '00000000-0000-4000-8000-000000081301',
   (now() at time zone 'America/Sao_Paulo')::date, now() - interval '1 hour', now() - interval '10 minutes',
   'experimental', 'ZZTESTE Canto', -81301, false),
  (-81302, -981302, '00000000-0000-4000-8000-000000081301',
   (now() at time zone 'America/Sao_Paulo')::date, now() - interval '1 hour', now() - interval '10 minutes',
   'experimental', 'ZZTESTE Canto', -81301, false);
insert into public.lead_experimental_aulas (
  id, lead_experimental_id, aula_local_id, estado, casado_por
) values
  (-81301, -81301, -81301, 'vinculado', 'chave_natural'),
  (-81302, -81302, -81302, 'vinculado', 'chave_natural');

create temp table _out_audio_exp_duravel(
  tentativa text,
  resposta jsonb,
  erro text
) on commit drop;
grant select, insert on _out_audio_exp_duravel to authenticated;

do $$
declare
  v_primeiro jsonb;
  v_segundo jsonb;
begin
  set local role authenticated;
  perform set_config(
    'request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000081301"}',
    true
  );

  select public.app_enfileirar_audio_experimental(
    -81301, '00000000-0000-4000-8000-000000081301/exp-81301/replay.webm', 21
  ) into v_primeiro;
  select public.app_enfileirar_audio_experimental(
    -81301, '00000000-0000-4000-8000-000000081301/exp-81301/replay.webm', 21
  ) into v_segundo;
  insert into _out_audio_exp_duravel values ('primeiro', v_primeiro, null), ('segundo', v_segundo, null);

  begin
    perform public.app_enfileirar_audio_experimental(
      -81302, '00000000-0000-4000-8000-000000081301/exp-81301/replay.webm', 21
    );
    insert into _out_audio_exp_duravel values ('path cruzado', null, 'NAO LEVANTOU');
  exception when others then
    insert into _out_audio_exp_duravel values ('path cruzado', null, sqlerrm);
  end;
  reset role;
end $$;

insert into _res_audio_exp_duravel
select 'policy UPDATE exige bucket e pasta do proprio usuario', 'sim',
  case when exists (
    select 1
      from pg_policies
     where schemaname = 'storage'
       and tablename = 'objects'
       and policyname = 'fabio_audios_update_own'
       and cmd = 'UPDATE'
       and roles = array['authenticated'::name]
       and regexp_replace(qual, '[[:space:]]|::text', '', 'g') =
         '((bucket_id=''fabio-audios'')AND((storage.foldername(name))[1]=(auth.uid())))'
       and regexp_replace(with_check, '[[:space:]]|::text', '', 'g') =
         '((bucket_id=''fabio-audios'')AND((storage.foldername(name))[1]=(auth.uid())))'
  ) then 'sim' else 'nao' end;

insert into _res_audio_exp_duravel
select 'a RPC roda com search_path seguro', 'sim',
  case when exists (
    select 1
      from pg_proc
     where oid = 'public.app_enfileirar_audio_experimental(bigint,text,integer)'::regprocedure
       and array_to_string(proconfig, ',') like '%search_path=pg_catalog, public%'
  ) then 'sim' else 'nao' end;

insert into _res_audio_exp_duravel
select 'a RPC serializa o replay pelo storage_path', 'sim',
  case when exists (
    select 1
      from pg_proc
     where oid = 'public.app_enfileirar_audio_experimental(bigint,text,integer)'::regprocedure
       and prosrc like '%pg_advisory_xact_lock%'
       and prosrc like '%fabio-fila-audio:%'
  ) then 'sim' else 'nao' end;

insert into _res_audio_exp_duravel
select 'indice unico materializa no maximo uma fila experimental por path', 'sim',
  case when exists (
    select 1
      from pg_indexes
     where schemaname = 'public'
       and indexname = 'uq_fabio_fila_audio_experimental_path'
       and indexdef like '%UNIQUE INDEX uq_fabio_fila_audio_experimental_path%'
       and indexdef like '%WHERE (vinculo_id IS NOT NULL)%'
  ) then 'sim' else 'nao' end;

insert into _res_audio_exp_duravel
select 'grants da RPC deixam anon e PUBLIC sem EXECUTE', 'sim',
  case when not has_function_privilege(
      'anon', 'public.app_enfileirar_audio_experimental(bigint,text,integer)', 'EXECUTE'
    ) and not has_function_privilege(
      'public', 'public.app_enfileirar_audio_experimental(bigint,text,integer)', 'EXECUTE'
    ) and has_function_privilege(
      'authenticated', 'public.app_enfileirar_audio_experimental(bigint,text,integer)', 'EXECUTE'
    ) then 'sim' else 'nao' end;

insert into _res_audio_exp_duravel
select 'replay devolve o mesmo audio_id e marca deduplicado', 'sim',
  case when (
    select resposta ->> 'audio_id' from _out_audio_exp_duravel where tentativa = 'primeiro'
  ) = (
    select resposta ->> 'audio_id' from _out_audio_exp_duravel where tentativa = 'segundo'
  ) and coalesce((
    select (resposta ->> 'deduplicado')::boolean from _out_audio_exp_duravel where tentativa = 'segundo'
  ), false) then 'sim' else 'nao' end;

insert into _res_audio_exp_duravel
select 'replay deixa uma unica fila para a fala', '1',
  (select count(*)::text
     from public.fabio_fila_audios
    where professor_id = -81301
      and storage_path = '00000000-0000-4000-8000-000000081301/exp-81301/replay.webm');

insert into _res_audio_exp_duravel
select 'path nao pode ser reutilizado por outra experimental', 'storage_path_reutilizado_para_outra_experimental',
  (select case
    when erro like '%storage_path_reutilizado_para_outra_experimental%'
      then 'storage_path_reutilizado_para_outra_experimental'
    else erro
  end from _out_audio_exp_duravel where tentativa = 'path cruzado');

select json_build_object(
  'falhas', (select count(*) from _res_audio_exp_duravel where esperado is distinct from obtido),
  'detalhe', coalesce((
    select json_agg(json_build_object('passo', passo, 'esperado', esperado, 'obtido', obtido) order by passo)
      from _res_audio_exp_duravel
     where esperado is distinct from obtido
  ), '[]'::json)
) as resumo;
