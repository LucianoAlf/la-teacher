begin;

do $test$
declare
  v_registro_id uuid;
  v_audio_origem text;
begin
  select registro.id, audio.origem
    into v_registro_id, v_audio_origem
    from public.fabio_registros_aula registro
    join public.fabio_fila_audios audio on audio.id = registro.audio_id
   order by registro.criado_em desc
   limit 1;

  if v_registro_id is null then
    raise exception 'fixture_registro_com_audio_ausente';
  end if;

  update public.fabio_registros_aula
     set origem = case when v_audio_origem = 'app' then 'whatsapp' else 'app' end
   where id = v_registro_id;

  update public.fabio_registros_aula as registro
     set origem = audio.origem,
         atualizado_em = now()
    from public.fabio_fila_audios as audio
   where registro.audio_id = audio.id
     and registro.origem is distinct from audio.origem;

  if exists (
    select 1
      from public.fabio_registros_aula registro
      join public.fabio_fila_audios audio on audio.id = registro.audio_id
     where registro.origem is distinct from audio.origem
  ) then
    raise exception 'origem_do_registro_diverge_da_fila';
  end if;
end
$test$;

rollback;
