-- The durable audio queue owns the channel origin. Registration normalization
-- must preserve it instead of trusting an LLM-supplied payload field.

update public.fabio_registros_aula as registro
   set origem = audio.origem,
       atualizado_em = now()
  from public.fabio_fila_audios as audio
 where registro.audio_id = audio.id
   and registro.origem is distinct from audio.origem;

comment on column public.fabio_registros_aula.origem is
  'Canal autoritativo do registro; quando ha audio_id, deve refletir fabio_fila_audios.origem.';
