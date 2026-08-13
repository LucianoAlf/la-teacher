-- O bloqueio permanente sai da fila; o temporário volta.
--
-- Teste COMPORTAMENTAL: monta os três cenários de prova (permanente,
-- temporário, permitido) e olha o que sobra na fila depois -- não só o que a
-- função devolve. O passo que importa de verdade é o último: o claim real
-- deixa de enxergar a ação carimbada. Sem ele, "carimbou" não prova "saiu".

create temporary table _laco_res(caso text, ok boolean, detalhe text) on commit drop;

create or replace function pg_temp.checar_laco(p_caso text, p_ok boolean, p_detalhe text)
returns void language plpgsql as $$
begin insert into _laco_res values (p_caso, coalesce(p_ok,false), p_detalhe); end $$;

do $$
declare
  v_prof   integer;
  v_unid   uuid;
  v_aula   integer;
  v_lease  uuid := gen_random_uuid();
  v_audio  uuid;
  v_perm   uuid;   -- acao com bloqueio PERMANENTE
  v_temp   uuid;   -- acao com bloqueio TEMPORARIO
  v_livre  uuid;   -- acao que PODE ser limpa
  v_res    jsonb;
  v_claim  jsonb;
begin
  -- Fixture ancorada em linhas reais: FK de professor, unidade e aula.
  select ae.professor_id, ae.unidade_id, ae.id
    into v_prof, v_unid, v_aula
    from public.aulas_emusys ae
   where ae.professor_id is not null and ae.unidade_id is not null
   order by ae.data_hora_inicio desc limit 1;

  perform pg_temp.checar_laco('fixture: achou aula real',
    v_prof is not null and v_unid is not null and v_aula is not null,
    format('prof=%s aula=%s', v_prof, v_aula));
  if v_prof is null then return; end if;

  -- 1) PERMANENTE: um registro CONFIRMADO aponta pro audio.
  insert into public.fabio_fila_audios (professor_id, unidade_id, aula_id, storage_path, status)
  values (v_prof, v_unid, v_aula, 'teste-laco/permanente.ogg', 'normalizado')
  returning id into v_audio;

  insert into public.fabio_registros_aula
    (aula_id, unidade_id, professor_id, molde, status, audio_id, confirmado_em)
  values (v_aula, v_unid, v_prof, 'A', 'confirmado', v_audio, now());

  insert into public.fabio_acoes_pendentes
    (professor_id, wa_message_id, tipo, estado, storage_path, lease_token, lease_expira_em)
  values (v_prof, 'teste-laco-perm', 'confirmar_registro', 'expirada',
          'teste-laco/permanente.ogg', v_lease, now() + interval '120 seconds')
  returning id into v_perm;

  v_res := public.fabio_arquivar_limpeza_bloqueada(v_perm, v_lease);
  perform pg_temp.checar_laco(
    'bloqueio permanente e arquivado com o motivo escrito',
    (v_res->>'ok')::boolean is true
      and v_res->>'codigo' = 'bloqueio_permanente_arquivado'
      and v_res->>'motivo' = 'registro_confirmado_referencia_storage',
    coalesce(v_res::text,'<NULL>'));

  perform pg_temp.checar_laco(
    'o carimbo grava a chave que o claim ignora',
    (select coalesce(payload,'{}'::jsonb) ? 'limpeza'
       and (payload#>>'{limpeza,removido}') = 'false'
       and lease_token is null
       from public.fabio_acoes_pendentes where id = v_perm),
    (select payload::text from public.fabio_acoes_pendentes where id = v_perm));

  -- 2) TEMPORARIO: outra acao ABERTA referencia o mesmo storage.
  insert into public.fabio_acoes_pendentes
    (professor_id, wa_message_id, tipo, estado, storage_path)
  values (v_prof, 'teste-laco-ativa', 'confirmar_registro', 'aberta',
          'teste-laco/temporario.ogg');

  insert into public.fabio_acoes_pendentes
    (professor_id, wa_message_id, tipo, estado, storage_path, lease_token, lease_expira_em)
  values (v_prof, 'teste-laco-temp', 'confirmar_registro', 'expirada',
          'teste-laco/temporario.ogg', v_lease, now() + interval '120 seconds')
  returning id into v_temp;

  v_res := public.fabio_arquivar_limpeza_bloqueada(v_temp, v_lease);
  perform pg_temp.checar_laco(
    'bloqueio temporario NAO e carimbado -- volta pra fila',
    (v_res->>'ok')::boolean is false
      and v_res->>'codigo' = 'bloqueio_temporario'
      and (select not (coalesce(payload,'{}'::jsonb) ? 'limpeza') and lease_token is null
             from public.fabio_acoes_pendentes where id = v_temp),
    coalesce(v_res::text,'<NULL>'));

  -- 3) PERMITIDA: nada referencia. Esta porta tem que recusar.
  insert into public.fabio_acoes_pendentes
    (professor_id, wa_message_id, tipo, estado, storage_path, lease_token, lease_expira_em)
  values (v_prof, 'teste-laco-livre', 'confirmar_registro', 'expirada',
          'teste-laco/livre.ogg', v_lease, now() + interval '120 seconds')
  returning id into v_livre;

  v_res := public.fabio_arquivar_limpeza_bloqueada(v_livre, v_lease);
  perform pg_temp.checar_laco(
    'audio REMOVIVEL nao pode ser arquivado por esta porta',
    (v_res->>'ok')::boolean is false
      and v_res->>'codigo' = 'limpeza_permitida_use_concluir'
      and (select not (coalesce(payload,'{}'::jsonb) ? 'limpeza')
             from public.fabio_acoes_pendentes where id = v_livre),
    coalesce(v_res::text,'<NULL>'));

  -- 4) Lease errado nao carimba nada.
  v_res := public.fabio_arquivar_limpeza_bloqueada(v_perm, gen_random_uuid());
  perform pg_temp.checar_laco(
    'lease invalido e recusado',
    v_res->>'codigo' = 'lease_invalido',
    coalesce(v_res::text,'<NULL>'));

  -- 5) O QUE IMPORTA: o claim real deixa de ver a acao carimbada, e continua
  --    vendo a temporaria. Sem este passo, "carimbou" nao prova "saiu do laco".
  v_claim := public.fabio_claim_acoes_limpeza(50, 120);
  perform pg_temp.checar_laco(
    'o claim nao reivindica mais a permanente, e ainda reivindica a temporaria',
    not exists (select 1 from jsonb_array_elements(coalesce(v_claim->'itens','[]'::jsonb)) i
                 where (i->>'acao_id')::uuid = v_perm)
    and exists (select 1 from jsonb_array_elements(coalesce(v_claim->'itens','[]'::jsonb)) i
                 where (i->>'acao_id')::uuid = v_temp),
    coalesce(v_claim::text,'<NULL>'));

  -- 6) ACL: worker dentro, cliente fora.
  perform pg_temp.checar_laco(
    'ACL: service_role dentro, anon/authenticated fora',
    has_function_privilege('service_role','public.fabio_arquivar_limpeza_bloqueada(uuid,uuid)','EXECUTE')
      and not has_function_privilege('anon','public.fabio_arquivar_limpeza_bloqueada(uuid,uuid)','EXECUTE')
      and not has_function_privilege('authenticated','public.fabio_arquivar_limpeza_bloqueada(uuid,uuid)','EXECUTE'),
    'porta de worker');
end $$;

select json_build_object(
  'teste', '20260813230000-bloqueio-permanente-sai-da-fila',
  'falhas', (select count(*) from _laco_res where not ok),
  'detalhe', coalesce((select json_agg(json_build_object(
    'passo', caso, 'esperado','ok','obtido', coalesce(detalhe,'<NULL>'))
  ) from _laco_res where not ok), '[]'::json)
) as resumo;
