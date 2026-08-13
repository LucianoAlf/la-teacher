-- O upload de audio e uma transacao em duas partes: Storage primeiro, RPC
-- depois. Se a resposta da RPC se perde, o replay precisa poder fazer upsert
-- do MESMO objeto e receber o MESMO audio_id. Sem UPDATE na policy, o segundo
-- upload falha; sem dedupe na RPC, ele cria duas filas para uma fala.

drop policy if exists "fabio_audios_update_own" on storage.objects;
create policy "fabio_audios_update_own" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'fabio-audios'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'fabio-audios'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Segunda barreira independente do lock: a corrida de duas conexoes nao pode
-- materializar duas filas para o mesmo objeto experimental, mesmo que uma
-- futura edicao da funcao mova ou remova o advisory lock por engano.
create unique index if not exists uq_fabio_fila_audio_experimental_path
  on public.fabio_fila_audios (professor_id, storage_path)
  where vinculo_id is not null;

create or replace function public.app_enfileirar_audio_experimental(
  p_vinculo_id bigint,
  p_storage_path text,
  p_duracao_segundos integer
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_prof integer := public.fn_professor_do_usuario();
  v_vinculo record;
  v_aula public.aulas_emusys%rowtype;
  v_existente public.fabio_fila_audios%rowtype;
  v_id uuid;
  v_storage_path text := nullif(btrim(p_storage_path), '');
begin
  if v_prof is null then
    raise exception 'sem_professor_vinculado';
  end if;
  if v_storage_path is null then
    raise exception 'storage_path obrigatorio';
  end if;

  select v.id, v.estado, v.aula_local_id
    into v_vinculo
    from public.lead_experimental_aulas v
   where v.id = p_vinculo_id
     and v.substituido_em is null;
  if not found then
    raise exception 'vinculo_inexistente_ou_sem_aula: %', p_vinculo_id;
  end if;

  if v_vinculo.estado = 'pendente' then
    raise exception 'experimental_sem_aula_vinculada';
  elsif v_vinculo.estado = 'faltou' then
    raise exception 'experimental_faltou_nao_tem_registro';
  elsif v_vinculo.estado = 'cancelado' then
    raise exception 'experimental_cancelada';
  end if;

  select * into v_aula
    from public.aulas_emusys
   where id = v_vinculo.aula_local_id;
  if not found then
    raise exception 'vinculo_inexistente_ou_sem_aula: %', p_vinculo_id;
  end if;
  if v_aula.professor_id is distinct from v_prof then
    raise exception 'aula_de_outro_professor';
  end if;
  if coalesce(v_aula.cancelada, false) then
    raise exception 'aula_cancelada';
  end if;
  if v_aula.data_hora_inicio > now() + interval '15 minutes' then
    raise exception 'gravacao_ainda_nao_disponivel';
  end if;
  if coalesce(v_aula.data_hora_fim, v_aula.data_hora_inicio)
      < now() - (public.fn_janela_registro_dias() || ' days')::interval then
    raise exception 'janela_de_gravacao_encerrada';
  end if;

  -- Serializa apenas a mesma intencao persistida. Duas gravacoes distintas
  -- continuam possiveis; um replay do mesmo blob nao vira segunda fila.
  perform pg_advisory_xact_lock(hashtextextended(
    'fabio-fila-audio:' || v_prof::text || ':' || v_storage_path, 0
  ));
  select * into v_existente
    from public.fabio_fila_audios
   where professor_id = v_prof
     and storage_path = v_storage_path
   order by id
   limit 1;
  if found then
    if v_existente.vinculo_id is distinct from p_vinculo_id then
      raise exception 'storage_path_reutilizado_para_outra_experimental';
    end if;
    return jsonb_build_object(
      'audio_id', v_existente.id,
      'status', v_existente.status,
      'vinculo_id', p_vinculo_id,
      'deduplicado', true
    );
  end if;

  begin
    insert into public.fabio_fila_audios (
      professor_id, unidade_id, aula_id, vinculo_id, storage_path,
      duracao_segundos, origem, status
    ) values (
      v_prof, v_aula.unidade_id, v_aula.id, p_vinculo_id, v_storage_path,
      p_duracao_segundos, 'app', 'pendente'
    ) returning id into v_id;
  exception when unique_violation then
    -- Defesa para duas transacoes que chegaram antes de o lock de uma versao
    -- antiga ser adquirido. A mesma identidade continua recebendo o mesmo id.
    select * into v_existente
      from public.fabio_fila_audios
     where professor_id = v_prof
       and storage_path = v_storage_path
     order by id
     limit 1;
    if not found or v_existente.vinculo_id is distinct from p_vinculo_id then
      raise;
    end if;
    return jsonb_build_object(
      'audio_id', v_existente.id,
      'status', v_existente.status,
      'vinculo_id', p_vinculo_id,
      'deduplicado', true
    );
  end;

  return jsonb_build_object(
    'audio_id', v_id,
    'status', 'pendente',
    'vinculo_id', p_vinculo_id,
    'deduplicado', false
  );
end
$function$;

comment on function public.app_enfileirar_audio_experimental(bigint, text, integer) is
  'Enfileira audio experimental com identidade do professor derivada de auth.uid(). '
  'Replays do mesmo storage_path devolvem o mesmo audio_id; paths nao podem migrar entre vinculos.';

revoke all on function public.app_enfileirar_audio_experimental(bigint, text, integer)
  from public, anon;
grant execute on function public.app_enfileirar_audio_experimental(bigint, text, integer)
  to authenticated;
