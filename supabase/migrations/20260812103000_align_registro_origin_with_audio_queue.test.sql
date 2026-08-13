-- Contrato: a fila de audio e dona da origem do canal, nao o payload do LLM.
--
-- ESTE TESTE JA EXISTIA E NUNCA RODOU -- nasceu como
-- `098-registro-origin-authority.test.sql`, nome que nao casa com o da
-- migration, e o runner agregado pareia por nome. Vinha tambem com
-- `begin;`/`rollback;` proprios, e o runner e o dono da transacao.
-- Renomeado e convertido ao formato da casa em 13/08/2026, preservando
-- exatamente o que ele afirmava.
--
-- O QUE ELE PRENDE: `fabio_registros_aula.origem` tem que espelhar
-- `fabio_fila_audios.origem` do audio que originou o registro. Quando um
-- registro nasce de audio, quem sabe por qual canal a fala entrou e a FILA --
-- o campo de origem vindo do payload gerado pelo modelo nao e autoridade.

create temporary table _origem_res(caso text, ok boolean, detalhe text)
on commit drop;

create or replace function pg_temp.checar_origem(p_caso text, p_ok boolean, p_detalhe text)
returns void
language plpgsql
as $$
begin
  insert into _origem_res values (p_caso, coalesce(p_ok, false), p_detalhe);
end
$$;

do $$
declare
  v_registro_id uuid;
  v_audio_origem text;
  v_depois text;
begin
  select registro.id, audio.origem
    into v_registro_id, v_audio_origem
    from public.fabio_registros_aula registro
    join public.fabio_fila_audios audio on audio.id = registro.audio_id
   order by registro.criado_em desc
   limit 1;

  perform pg_temp.checar_origem(
    'existe registro vindo de audio para exercitar o contrato',
    v_registro_id is not null,
    coalesce(v_registro_id::text, '<nenhum registro com audio>')
  );

  if v_registro_id is null then
    return;
  end if;

  -- Estraga de proposito: poe no registro uma origem diferente da fila.
  update public.fabio_registros_aula
     set origem = case when v_audio_origem = 'app' then 'whatsapp' else 'app' end
   where id = v_registro_id;

  perform pg_temp.checar_origem(
    'a divergencia foi mesmo criada (senao o passo seguinte nao prova nada)',
    (select origem from public.fabio_registros_aula where id = v_registro_id)
      is distinct from v_audio_origem,
    coalesce((select origem from public.fabio_registros_aula where id = v_registro_id), '<NULL>')
  );

  -- O realinhamento que a migration faz.
  update public.fabio_registros_aula as registro
     set origem = audio.origem,
         atualizado_em = now()
    from public.fabio_fila_audios as audio
   where registro.audio_id = audio.id
     and registro.origem is distinct from audio.origem;

  select origem into v_depois from public.fabio_registros_aula where id = v_registro_id;
  perform pg_temp.checar_origem(
    'a fila reimpoe a origem no registro que divergiu',
    v_depois = v_audio_origem,
    format('registro=%s fila=%s', coalesce(v_depois,'<NULL>'), coalesce(v_audio_origem,'<NULL>'))
  );

  perform pg_temp.checar_origem(
    'nenhum registro com audio fica divergindo da fila',
    not exists (
      select 1
        from public.fabio_registros_aula registro
        join public.fabio_fila_audios audio on audio.id = registro.audio_id
       where registro.origem is distinct from audio.origem
    ),
    'varredura completa'
  );
end
$$;

select json_build_object(
  'teste', '20260812103000-align-registro-origin-with-audio-queue',
  'falhas', (select count(*) from _origem_res where not ok),
  'detalhe', coalesce((select json_agg(json_build_object(
    'passo', caso, 'esperado', 'ok', 'obtido', coalesce(detalhe, '<NULL>'))
  ) from _origem_res where not ok), '[]'::json)
) as resumo;
