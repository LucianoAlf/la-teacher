-- RED: o bridge abre a shortlist diretamente depois de classificar o audio.
-- A RPC precisa aceitar os tipos de chooser que a propria maquina de estados
-- usa; antes da migration 096 ela devolve tipo_invalido.
create temp table _fabio_096_res(
  caso text not null,
  ok boolean not null,
  detalhe text not null
) on commit drop;

do $$
declare
  v_audio jsonb;
  v_call jsonb;
begin
  v_audio := public.fabio_iniciar_acao(
    10,
    'e2e-contract-096-audio',
    'escolher_aula_audio',
    'e2e/contract-096-audio.webm',
    '{}'::jsonb
  );
  insert into _fabio_096_res values (
    'chooser de audio aceito',
    coalesce((v_audio ->> 'ok')::boolean, false),
    v_audio::text
  );

  v_call := public.fabio_iniciar_acao(
    25,
    'e2e-contract-096-call',
    'escolher_aula_chamada',
    null,
    '{}'::jsonb
  );
  insert into _fabio_096_res values (
    'chooser de chamada aceito',
    coalesce((v_call ->> 'ok')::boolean, false),
    v_call::text
  );
end $$;

select json_build_object(
  'falhas', (select count(*) from _fabio_096_res where not ok),
  'detalhe', coalesce((select json_agg(json_build_object(
    'passo', caso,
    'esperado', 'true',
    'obtido', detalhe
  ) order by caso) from _fabio_096_res where not ok), '[]'::json)
) as resumo;
