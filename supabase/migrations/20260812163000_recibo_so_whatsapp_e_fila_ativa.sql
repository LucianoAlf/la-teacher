-- O carimbo e a devolutiva pelo WhatsApp pertencem somente ao fluxo iniciado
-- naquele canal. Confirmacoes feitas no app continuam no app e nao geram uma
-- nova conversa no WhatsApp.

-- A fila duravel e a fonte autoritativa do canal. A 094 validava e travava a
-- linha da fila, mas ainda gravava a origem fornecida pelo payload. Recriamos
-- a porta sem tocar a migration historica: havendo audio valido, raiz e fatias
-- recebem exatamente f.origem; sem audio, o unico fallback seguro e app.
create or replace function public.app_status_audio_fila(p_audio_id uuid)
returns table(
  audio_id uuid,
  status text,
  tentativas integer,
  tem_erro boolean,
  criado_em timestamptz,
  atualizado_em timestamptz
)
language sql
security definer
set search_path = pg_catalog, public
as $function$
  select f.id, f.status, f.tentativas,
         case when f.status = 'erro' then true else false end,
         f.criado_em, f.atualizado_em
  from public.fabio_fila_audios f
  where f.id = p_audio_id
    and f.professor_id = public.fn_professor_do_usuario();
$function$;

create or replace function public.fn_enfileirar_audio_core(
  p_aula_id integer,
  p_storage_path text,
  p_duracao_segundos integer,
  p_registro_id uuid,
  p_origem text,
  p_professor_id integer
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_aula public.aulas_emusys%rowtype;
  v_existente public.fabio_fila_audios%rowtype;
  v_fila_viva public.fabio_fila_audios%rowtype;
  v_rascunho public.fabio_registros_aula%rowtype;
  v_unidade uuid;
  v_id uuid;
  v_ja jsonb;
  v_qtd_ja integer := 0;
  v_storage_path text := nullif(btrim(p_storage_path), '');
begin
  if p_professor_id is null then raise exception 'sem_professor_vinculado'; end if;
  if p_origem not in ('app', 'whatsapp') then
    raise exception 'origem_invalida: %', p_origem;
  end if;
  if v_storage_path is null then
    raise exception 'storage_path obrigatorio';
  end if;

  select * into v_aula from public.aulas_emusys where id = p_aula_id;
  if not found then raise exception 'Aula % nao encontrada', p_aula_id; end if;
  if v_aula.professor_id is distinct from p_professor_id then
    raise exception 'aula_nao_pertence_ao_professor';
  end if;
  if coalesce(v_aula.cancelada, false) then raise exception 'aula_cancelada'; end if;
  if v_aula.data_hora_inicio > now() + interval '15 minutes' then
    raise exception 'gravacao_ainda_nao_disponivel';
  end if;
  if coalesce(v_aula.data_hora_fim, v_aula.data_hora_inicio)
      < now() - (public.fn_janela_registro_dias() || ' days')::interval then
    raise exception 'janela_de_gravacao_encerrada';
  end if;

  v_unidade := v_aula.unidade_id;
  if p_registro_id is not null then
    perform 1 from public.fabio_registros_aula
     where id = p_registro_id and professor_id = p_professor_id
       and status in ('rascunho', 'aguardando_confirmacao');
    if not found then
      raise exception 'Registro % nao encontrado/permitido para complemento', p_registro_id;
    end if;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'aluno_id', x.aluno_id, 'aluno_nome', x.nome, 'aula_id', x.aula_id,
           'registrado_em', x.criado_em, 'previa', left(x.texto, 120)
         ) order by x.nome), '[]'::jsonb), count(*)
    into v_ja, v_qtd_ja
  from (
    select distinct on (r.aluno_id)
           r.aluno_id, a.nome, alvo.id as aula_id,
           alvo.anotacoes_fabio as texto,
           (select max(l.criado_em) from public.aula_registros_fabio_log l
             where l.aula_id = alvo.id) as criado_em
      from public.aula_alunos_emusys r
      join public.alunos a on a.id = r.aluno_id
      join lateral (select ae2.* from public.aulas_emusys ae2
                     where ae2.id = public.fn_aula_individual_do_aluno(p_aula_id, r.aluno_id)) alvo on true
     where r.aula_emusys_id = p_aula_id
       and nullif(btrim(coalesce(alvo.anotacoes_fabio, '')), '') is not null
     order by r.aluno_id, alvo.id
  ) x;

  if p_registro_id is null then
    perform pg_advisory_xact_lock(hashtextextended(
      'fabio-fila-audio-aula:' || p_professor_id::text || ':' || p_aula_id::text, 0
    ));
  end if;

  -- A chave por path preserva a idempotencia de reenvio do mesmo blob. Para
  -- gravacoes novas, a chave adicional por aula serializa o bloqueio abaixo e
  -- impede duas filas com paths distintos na mesma aula.
  perform pg_advisory_xact_lock(hashtextextended(
    'fabio-fila-audio:' || p_professor_id::text || ':' || v_storage_path, 0
  ));
  select * into v_existente
    from public.fabio_fila_audios
   where professor_id = p_professor_id
     and storage_path = v_storage_path
   order by id
   limit 1;
  if found then
    if v_existente.aula_id is distinct from p_aula_id then
      raise exception 'storage_path_reutilizado_para_outra_aula';
    end if;
    return jsonb_build_object(
      'audio_id', v_existente.id,
      'status', v_existente.status,
      'modo', case when p_registro_id is null then 'novo' else 'complementar' end,
      'registro_id', p_registro_id,
      'deduplicado', true,
      'aula_ja_registrada', v_qtd_ja > 0,
      'ja_registrados', v_ja
    );
  end if;

  if p_registro_id is null then
    select * into v_fila_viva
      from public.fabio_fila_audios f
     where f.professor_id = p_professor_id
       and f.aula_id = p_aula_id
       and f.status in ('pendente', 'transcrevendo', 'transcrito', 'erro')
     order by f.criado_em, f.id
     limit 1;
    if found then
      return jsonb_build_object(
        'audio_id', v_fila_viva.id,
        'status', v_fila_viva.status,
        'modo', 'novo',
        'registro_id', null,
        'deduplicado', false,
        'ja_em_processamento', true,
        'aula_ja_registrada', v_qtd_ja > 0,
        'ja_registrados', v_ja
      );
    end if;

    select * into v_rascunho
      from public.fabio_registros_aula r
     where r.professor_id = p_professor_id
       and r.aula_id = p_aula_id
       and r.parent_id is null
       and r.status in ('rascunho', 'aguardando_confirmacao')
     order by r.criado_em desc, r.id
     limit 1;
    if found then
      return jsonb_build_object(
        'modo', 'novo',
        'registro_id', v_rascunho.id,
        'deduplicado', false,
        'rascunho_existente', true,
        'aula_ja_registrada', v_qtd_ja > 0,
        'ja_registrados', v_ja
      );
    end if;
  end if;

  insert into public.fabio_fila_audios(
    professor_id, unidade_id, aula_id, storage_path, duracao_segundos, origem, status
  ) values (
    p_professor_id, v_unidade, p_aula_id, v_storage_path,
    p_duracao_segundos, p_origem, 'pendente'
  ) returning id into v_id;

  if p_registro_id is not null then
    update public.fabio_registros_aula
       set campos = campos || jsonb_build_object('audio_complemento_id', v_id)
     where id = p_registro_id;
  end if;

  return jsonb_build_object(
    'audio_id', v_id, 'status', 'pendente',
    'modo', case when p_registro_id is null then 'novo' else 'complementar' end,
    'registro_id', p_registro_id, 'deduplicado', false,
    'aula_ja_registrada', v_qtd_ja > 0,
    'ja_registrados', v_ja
  );
end
$function$;

create or replace function public.fabio_criar_registro(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_audio_text text := nullif(btrim(p_payload ->> 'audio_id'), '');
  v_audio_id uuid;
  v_aula_id integer := (p_payload ->> 'aula_id')::integer;
  v_professor integer := (p_payload ->> 'professor_id')::integer;
  v_unidade uuid;
  v_ancora public.aulas_emusys%rowtype;
  v_aula_fatia public.aulas_emusys%rowtype;
  v_alvo_canonico integer;
  v_aluno_fatia integer;
  v_molde text := coalesce(p_payload ->> 'molde', 'C');
  v_tronco_id uuid;
  v_tronco_campos jsonb := coalesce(p_payload -> 'tronco' -> 'campos', '{}'::jsonb);
  v_fatia jsonb;
  v_fatia_campos jsonb;
  v_fatia_aula integer;
  v_qtd_fatias integer := 0;
  v_origem text := 'app';
  v_audio_status text;
  v_audio_erro_tipo text;
begin
  if v_aula_id is null then raise exception 'aula_id obrigatorio'; end if;
  if v_professor is null then raise exception 'professor_id obrigatorio'; end if;

  select * into v_ancora
    from public.aulas_emusys
   where id = v_aula_id
     and professor_id = v_professor
     and coalesce(cancelada, false) = false;
  if not found then raise exception 'aula_nao_pertence_ao_professor'; end if;
  v_unidade := v_ancora.unidade_id;

  if v_audio_text is not null then
    begin
      v_audio_id := v_audio_text::uuid;
    exception when invalid_text_representation then
      raise exception 'audio_id_invalido';
    end;
    select f.origem, f.status, f.erro_tipo
      into v_origem, v_audio_status, v_audio_erro_tipo
      from public.fabio_fila_audios f
     where f.id = v_audio_id
       and f.professor_id = v_professor
       and f.aula_id = v_ancora.id
       and f.unidade_id = v_unidade
     for update;
    if not found then
      raise exception 'audio_id_invalido';
    end if;
    if v_audio_status = 'erro_terminal'
       or v_audio_erro_tipo = 'semantico_terminal' then
      raise exception 'audio_terminal_nao_normalizavel';
    end if;
  end if;

  if v_audio_id is not null then
    select id into v_tronco_id from public.fabio_registros_aula
     where audio_id = v_audio_id and parent_id is null limit 1;
    if v_tronco_id is not null then
      return jsonb_build_object('status', 'ja_existe', 'registro_id', v_tronco_id);
    end if;
  end if;

  insert into public.fabio_registros_aula
    (aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos,
     texto_consolidado, status, origem, audio_id)
  values
    (v_aula_id, v_unidade, v_professor, null, null, v_molde,
     v_tronco_campos,
     public.fn_compor_texto_prontuario(v_tronco_campos, '{}'::jsonb),
     'aguardando_confirmacao', v_origem, v_audio_id)
  returning id into v_tronco_id;

  for v_fatia in select * from jsonb_array_elements(coalesce(p_payload -> 'fatias', '[]'::jsonb))
  loop
    if jsonb_typeof(v_fatia) <> 'object' then raise exception 'fatia_invalida'; end if;
    v_aluno_fatia := nullif(v_fatia ->> 'aluno_id', '')::integer;
    if v_aluno_fatia is null then raise exception 'fatia_sem_aluno'; end if;
    if not exists (
      select 1
        from public.aula_alunos_emusys aa
       where aa.aula_emusys_id = v_aula_id
         and aa.aluno_id = v_aluno_fatia
    ) then
      raise exception 'fatia_aluno_fora_do_roster';
    end if;

    v_alvo_canonico := public.fn_aula_individual_do_aluno(v_aula_id, v_aluno_fatia);
    v_fatia_aula := coalesce(nullif(v_fatia ->> 'aula_id', '')::integer, v_alvo_canonico);
    select * into v_aula_fatia
      from public.aulas_emusys
     where id = v_fatia_aula
       and coalesce(cancelada, false) = false;
    if not found then raise exception 'fatia_aula_nao_encontrada'; end if;
    if v_aula_fatia.professor_id is distinct from v_professor then
      raise exception 'fatia_aula_nao_pertence_ao_professor';
    end if;
    if v_aula_fatia.unidade_id is distinct from v_ancora.unidade_id
       or v_aula_fatia.id is distinct from v_alvo_canonico then
      raise exception 'fatia_aula_fora_da_sessao';
    end if;
    if not exists (
      select 1
        from public.aula_alunos_emusys aa
       where aa.aula_emusys_id = v_fatia_aula
         and aa.aluno_id = v_aluno_fatia
    ) then
      raise exception 'fatia_aluno_fora_da_sessao';
    end if;

    v_fatia_campos := public.fn_remover_campos_comuns_da_fatia(
      v_tronco_campos,
      coalesce(v_fatia -> 'campos', '{}'::jsonb)
    );
    insert into public.fabio_registros_aula
      (aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos,
       texto_consolidado, status, origem, audio_id)
    values
      (v_fatia_aula, v_unidade, v_professor,
       v_aluno_fatia, v_tronco_id, v_molde,
       v_fatia_campos,
       public.fn_compor_texto_prontuario(v_tronco_campos, v_fatia_campos),
       'aguardando_confirmacao', v_origem, v_audio_id);
    v_qtd_fatias := v_qtd_fatias + 1;
  end loop;

  if v_audio_id is not null then
    update public.fabio_fila_audios
       set status = 'normalizado', atualizado_em = now()
     where id = v_audio_id;
  end if;

  return jsonb_build_object('status', 'criado', 'registro_id', v_tronco_id, 'fatias', v_qtd_fatias);
end
$function$;

create or replace function public.fn_enfileirar_registro_recibo(
  p_registro_id uuid,
  p_professor_id integer
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_registro public.fabio_registros_aula%rowtype;
  v_notificacao_id uuid;
begin
  if p_registro_id is null or p_professor_id is null then
    raise exception 'registro_e_professor_obrigatorios';
  end if;

  select * into v_registro
    from public.fabio_registros_aula
   where id = p_registro_id
     and parent_id is null
     and professor_id = p_professor_id;
  if not found then
    raise exception 'registro_recibo_nao_pertence_ao_professor';
  end if;
  if v_registro.confirmado_em is null
     or v_registro.status not in ('gravado_emusys', 'confirmado') then
    raise exception 'registro_recibo_exige_confirmacao';
  end if;

  if v_registro.origem is distinct from 'whatsapp' then
    return jsonb_build_object(
      'ok', true,
      'skipped', true,
      'motivo', case when v_registro.origem = 'app'
                       then 'origem_app'
                     else 'origem_nao_whatsapp'
                 end
    );
  end if;

  insert into public.fabio_notificacoes(
    professor_id, tipo, categoria, canal, titulo, corpo, destinatario_tipo,
    status, tentativas, lease_token, lease_expira_em,
    referencia_tipo, referencia_id
  ) values (
    p_professor_id, 'registro_recibo', 'informativa', 'whatsapp',
    'Registro confirmado', 'Recibo do registro aguardando devolutivas.', 'professor',
    'processando', 0, null, now(),
    'registro_aula', p_registro_id::text
  )
  on conflict (professor_id, tipo, referencia_tipo, referencia_id, canal)
    where tipo = 'registro_recibo'
      and referencia_tipo = 'registro_aula'
      and canal = 'whatsapp'
  do nothing
  returning id into v_notificacao_id;

  return jsonb_build_object(
    'ok', true,
    'notificacao_id', v_notificacao_id,
    'ja_enfileirado', v_notificacao_id is null
  );
end
$function$;

create or replace function public.fabio_claim_registro_recibo(
  p_limite integer default 20,
  p_professor_id integer default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_lease_token uuid := gen_random_uuid();
  v_itens jsonb;
begin
  with candidatas as (
    select n.id
      from public.fabio_notificacoes n
      join public.fabio_registros_aula raiz
        on raiz.id::text = n.referencia_id
       and raiz.parent_id is null
       and raiz.professor_id = n.professor_id
     where n.tipo = 'registro_recibo'
       and n.referencia_tipo = 'registro_aula'
       and n.canal = 'whatsapp'
       and (p_professor_id is null or n.professor_id = p_professor_id)
       and raiz.origem = 'whatsapp'
       and raiz.confirmado_em is not null
       and raiz.status in ('gravado_emusys', 'confirmado')
       and (
         (n.status = 'processando'
          and (n.lease_expira_em is null or n.lease_expira_em <= now()))
         or (n.status = 'falhou'
             and (n.proxima_tentativa_em is null or n.proxima_tentativa_em <= now()))
       )
       -- Cada aluno presente cujo registro foi gravado precisa ter exatamente
       -- uma devolutiva pronta. Sem a linha, ou em outro estado, o recibo nem
       -- sequer recebe lease: esperar e seguro; chutar nao e.
       and not exists (
         select 1
           from public.fabio_registros_aula alvo
           left join public.fabio_devolutivas d
             on d.registro_fatia_id = alvo.id
          where (alvo.id = raiz.id or alvo.parent_id = raiz.id)
            and alvo.aluno_id is not null
            and alvo.status = 'gravado_emusys'
            and alvo.confirmado_em is not null
            and public.fn_presenca_declarada(alvo.campos) = 'presente'
            and (d.id is null or d.status not in ('gerada', 'oferecida'))
       )
     order by n.criado_em, n.id
     limit greatest(1, least(coalesce(p_limite, 20), 100))
     for update of n skip locked
  ), tomadas as (
    update public.fabio_notificacoes n
       set status = 'processando',
           lease_token = v_lease_token,
           lease_expira_em = now() + interval '10 minutes',
           proxima_tentativa_em = null,
           tentativas = n.tentativas + 1,
           last_error = null
      from candidatas c
     where n.id = c.id
    returning n.id, n.professor_id, n.referencia_id, n.titulo, n.tentativas
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'notificacao_id', id,
    'professor_id', professor_id,
    'registro_id', referencia_id,
    'titulo', titulo,
    'tentativas', tentativas
  ) order by id), '[]'::jsonb)
    into v_itens
    from tomadas;

  return jsonb_build_object('ok', true, 'lease_token', v_lease_token, 'itens', v_itens);
end
$function$;

-- Repeticao explicita das ACLs: as portas internas nao sao expostas ao app.
revoke all on function public.app_status_audio_fila(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.app_status_audio_fila(uuid)
  to authenticated, service_role;
revoke all on function public.fn_enfileirar_registro_recibo(uuid, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.fabio_claim_registro_recibo(integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.fabio_claim_registro_recibo(integer, integer)
  to service_role;
