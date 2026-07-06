-- ============================================================================
-- LA TEACHER · MIGRAÇÃO 002 — MOTOR DE REGISTRO (Sprint 3)
-- Projeto: ouqwbbermlzqqvtqwlul · Pré-requisito: 001 aplicada
-- Novidades: enfileirar áudio (app), disparo do pipeline (pg_net + retry),
--            correção por voz, e app_confirmar_registro v2 — GRAVAÇÃO POR
--            ALUNO (descoberta da Fase 3: espelho de aulas é 1 linha/aluno).
-- Idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1 · Enfileirar áudio (professor autenticado; correção por voz opcional)
-- ---------------------------------------------------------------------------
create or replace function public.app_enfileirar_audio(
  p_aula_id          integer,
  p_storage_path     text,
  p_duracao_segundos integer default null,
  p_registro_id      uuid default null      -- não nulo = correção por voz (complementar)
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_prof    integer := public.fn_professor_do_usuario();
  v_unidade uuid;
  v_id      uuid;
begin
  if v_prof is null then raise exception 'Usuário sem professor vinculado'; end if;
  if p_storage_path is null or btrim(p_storage_path) = '' then
    raise exception 'storage_path obrigatório';
  end if;

  select unidade_id into v_unidade from public.aulas_emusys where id = p_aula_id;
  if not found then raise exception 'Aula % não encontrada', p_aula_id; end if;

  if p_registro_id is not null then
    perform 1 from public.fabio_registros_aula
     where id = p_registro_id and professor_id = v_prof
       and status in ('rascunho','aguardando_confirmacao');
    if not found then
      raise exception 'Registro % não encontrado/permitido para complemento', p_registro_id;
    end if;
  end if;

  insert into public.fabio_fila_audios
    (professor_id, unidade_id, aula_id, storage_path, duracao_segundos, origem, status)
  values (v_prof, v_unidade, p_aula_id, p_storage_path, p_duracao_segundos, 'app', 'pendente')
  returning id into v_id;

  -- vínculo do complemento: guardado no registro-alvo p/ a edge saber o modo
  if p_registro_id is not null then
    update public.fabio_registros_aula
       set campos = campos || jsonb_build_object('audio_complemento_id', v_id)
     where id = p_registro_id;
  end if;

  return jsonb_build_object('audio_id', v_id, 'status', 'pendente',
                            'modo', case when p_registro_id is null then 'novo' else 'complementar' end,
                            'registro_id', p_registro_id);
end $$;
revoke all on function public.app_enfileirar_audio(integer,text,integer,uuid) from public, anon;
grant execute on function public.app_enfileirar_audio(integer,text,integer,uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2 · Disparo do pipeline — trigger pg_net → Edge Function + retry via cron
--     Secrets no Vault (criar no painel): fabio_edge_url · fabio_edge_token
-- ---------------------------------------------------------------------------
create or replace function public.fn_fabio_chama_edge(p_audio_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_url text; v_token text;
begin
  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'fabio_edge_url' limit 1;
  select decrypted_secret into v_token
    from vault.decrypted_secrets where name = 'fabio_edge_token' limit 1;
  if v_url is null or v_token is null then
    raise notice 'Vault sem fabio_edge_url/fabio_edge_token — pipeline não disparado';
    return;
  end if;
  perform net.http_post(
    url     := v_url,
    headers := jsonb_build_object('Content-Type','application/json',
                                  'Authorization','Bearer '||v_token),
    body    := jsonb_build_object('audio_id', p_audio_id));
end $$;

create or replace function public.trg_fabio_fila_dispara()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.fn_fabio_chama_edge(new.id);
  return new;
end $$;

drop trigger if exists trg_fabio_fila_novo on public.fabio_fila_audios;
create trigger trg_fabio_fila_novo
  after insert on public.fabio_fila_audios
  for each row when (new.status = 'pendente')
  execute function public.trg_fabio_fila_dispara();

-- Retry: pendentes/erro com menos de 5 tentativas, parados há 3+ minutos
create or replace function public.fn_fabio_retry_fila()
returns integer language plpgsql security definer set search_path = public as $$
declare r record; n integer := 0;
begin
  for r in
    select id from public.fabio_fila_audios
    where status in ('pendente','erro') and tentativas < 5
      and atualizado_em < now() - interval '3 minutes'
    limit 10
  loop
    update public.fabio_fila_audios
       set tentativas = tentativas + 1, atualizado_em = now()
     where id = r.id;
    perform public.fn_fabio_chama_edge(r.id);
    n := n + 1;
  end loop;
  return n;
end $$;

do $$ begin
  perform cron.schedule('fabio-retry-fila', '*/5 * * * *',
                        $cron$ select public.fn_fabio_retry_fila(); $cron$);
exception when others then
  raise notice 'cron fabio-retry-fila: % (talvez já exista)', sqlerrm;
end $$;

-- ---------------------------------------------------------------------------
-- 3 · app_confirmar_registro v2 — GRAVAÇÃO POR ALUNO
--     1:1  → grava texto do registro raiz na aula do aluno.
--     Turma → para cada fatia PRESENTE com aula_id própria: grava o
--             texto_consolidado da fatia (cabeçalho + bloco geral + bloco do
--             aluno, já montado pelo normalizador) na aula daquele aluno.
--     Fatias ausentes: confirmadas sem gravação (nada é inventado).
-- ---------------------------------------------------------------------------
create or replace function public.app_confirmar_registro(p_registro_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_prof     integer := public.fn_professor_do_usuario();
  v_reg      public.fabio_registros_aula%rowtype;
  v_fatia    record;
  v_user_id  integer;
  v_gravadas integer := 0;
  v_puladas  integer := 0;
  v_pend     jsonb := '[]'::jsonb;
  v_out      jsonb;
begin
  if v_prof is null then raise exception 'Usuário sem professor vinculado'; end if;
  select u.id into v_user_id from public.usuarios u where u.auth_user_id = auth.uid();

  select * into v_reg from public.fabio_registros_aula
   where id = p_registro_id and parent_id is null;
  if not found then raise exception 'Registro % não encontrado', p_registro_id; end if;
  if v_reg.professor_id is distinct from v_prof then
    raise exception 'Registro não pertence a este professor';
  end if;
  if v_reg.status not in ('rascunho','aguardando_confirmacao') then
    raise exception 'Status % não permite confirmação', v_reg.status;
  end if;

  if v_reg.aluno_id is not null then
    -- ---------- aula individual ----------
    if coalesce(btrim(v_reg.texto_consolidado),'') = '' then
      raise exception 'Registro sem texto consolidado';
    end if;
    perform public.registrar_aula_fabio(
      p_aula_id => v_reg.aula_id, p_texto => v_reg.texto_consolidado,
      p_origem => v_reg.origem, p_professor_id => v_reg.professor_id, p_modo => 'novo');
    v_gravadas := 1;
    update public.fabio_registros_aula
       set status='gravado_emusys', confirmado_em=now(), confirmado_por=v_user_id
     where id = p_registro_id;
  else
    -- ---------- turma: tronco + fatias ----------
    for v_fatia in
      select * from public.fabio_registros_aula
       where parent_id = p_registro_id
    loop
      if coalesce(v_fatia.campos->>'presenca','presente') = 'ausente' then
        v_puladas := v_puladas + 1;
        update public.fabio_registros_aula
           set status='confirmado', confirmado_em=now(), confirmado_por=v_user_id
         where id = v_fatia.id;
      elsif v_fatia.aula_id is null
            or coalesce(btrim(v_fatia.texto_consolidado),'') = '' then
        v_pend := v_pend || jsonb_build_object(
          'fatia_id', v_fatia.id, 'aluno_id', v_fatia.aluno_id,
          'motivo', case when v_fatia.aula_id is null
                         then 'sem aula vinculada' else 'sem texto' end);
      else
        perform public.registrar_aula_fabio(
          p_aula_id => v_fatia.aula_id, p_texto => v_fatia.texto_consolidado,
          p_origem => v_fatia.origem, p_professor_id => v_reg.professor_id, p_modo => 'novo');
        v_gravadas := v_gravadas + 1;
        update public.fabio_registros_aula
           set status='gravado_emusys', confirmado_em=now(), confirmado_por=v_user_id
         where id = v_fatia.id;
      end if;
    end loop;

    if v_gravadas = 0 and jsonb_array_length(v_pend) > 0 then
      raise exception 'Nenhuma fatia gravável: %', v_pend::text;
    end if;

    update public.fabio_registros_aula
       set status = case when jsonb_array_length(v_pend) = 0
                         then 'gravado_emusys' else 'confirmado' end,
           confirmado_em = now(), confirmado_por = v_user_id
     where id = p_registro_id;
  end if;

  v_out := jsonb_build_object('registro_id', p_registro_id,
                              'gravadas', v_gravadas,
                              'ausentes_puladas', v_puladas,
                              'pendencias', v_pend);
  return v_out;
end $$;
-- grants herdados da 001 (mesma assinatura). Reforço:
revoke all on function public.app_confirmar_registro(uuid) from public, anon;
grant execute on function public.app_confirmar_registro(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4 · Índice de apoio da Confirmação
-- ---------------------------------------------------------------------------
create index if not exists ix_fabio_reg_aguardando
  on public.fabio_registros_aula(professor_id, criado_em desc)
  where status = 'aguardando_confirmacao';

-- ============================================================================
-- Pós-migração (painel Supabase, uma vez):
--   1. Vault → secrets: fabio_edge_url = https://<ref>.functions.supabase.co/fabio-processa-audio
--                       fabio_edge_token = token forte próprio (a edge valida)
--   2. Deploy da edge function fabio-processa-audio (prompt P6)
--   3. Secrets da edge: GROQ_API_KEY · ANTHROPIC_API_KEY · SUPABASE_SERVICE_ROLE_KEY
--      · FABIO_EDGE_TOKEN (igual ao do Vault)
-- Sanidade: select cron.schedule ... listado em cron.job; insert de teste na
-- fila com status 'pendente' dispara http_post (ver net._http_response).
-- ============================================================================
