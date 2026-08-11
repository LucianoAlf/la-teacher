-- 091 - as cinco portas do WhatsApp
-- O app e o bridge atravessam os mesmos nucleos de escrita. A diferenca entre
-- canais fica restrita a identidade resolvida, origem/auditoria e ACL.

-- Audio: assinatura de cinco argumentos e o contrato historico; a sobrecarga
-- de seis argumentos carrega o professor explicitamente para o bridge.
create or replace function public.fn_enfileirar_audio_core(
  p_aula_id integer,
  p_storage_path text,
  p_duracao_segundos integer,
  p_registro_id uuid,
  p_origem text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_prof integer := public.fn_professor_do_usuario();
begin
  if v_prof is null then raise exception 'sem_professor_vinculado'; end if;
  return public.fn_enfileirar_audio_core(
    p_aula_id, p_storage_path, p_duracao_segundos, p_registro_id, p_origem, v_prof);
end
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
  v_unidade uuid;
  v_id uuid;
  v_ja jsonb;
  v_qtd_ja integer := 0;
begin
  if p_professor_id is null then raise exception 'sem_professor_vinculado'; end if;
  if p_origem not in ('app', 'whatsapp') then
    raise exception 'origem_invalida: %', p_origem;
  end if;
  if p_storage_path is null or btrim(p_storage_path) = '' then
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

  insert into public.fabio_fila_audios
    (professor_id, unidade_id, aula_id, storage_path, duracao_segundos, origem, status)
  values (p_professor_id, v_unidade, p_aula_id, p_storage_path,
          p_duracao_segundos, p_origem, 'pendente')
  returning id into v_id;

  if p_registro_id is not null then
    update public.fabio_registros_aula
       set campos = campos || jsonb_build_object('audio_complemento_id', v_id)
     where id = p_registro_id;
  end if;

  return jsonb_build_object(
    'audio_id', v_id, 'status', 'pendente',
    'modo', case when p_registro_id is null then 'novo' else 'complementar' end,
    'registro_id', p_registro_id, 'aula_ja_registrada', (v_qtd_ja > 0),
    'ja_registrados', v_ja);
end
$function$;

create or replace function public.app_enfileirar_audio(
  p_aula_id integer, p_storage_path text, p_duracao_segundos integer,
  p_registro_id uuid default null::uuid
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
declare v_prof integer := public.fn_professor_do_usuario();
begin
  if v_prof is null then raise exception 'Usuario sem professor vinculado'; end if;
  return public.fn_enfileirar_audio_core(
    p_aula_id, p_storage_path, p_duracao_segundos, p_registro_id, 'app', v_prof);
end
$function$;

create or replace function public.fabio_enfileirar_audio(
  p_professor_id integer, p_aula_id integer, p_storage_path text,
  p_duracao_segundos integer, p_registro_id uuid default null::uuid
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
begin
  return public.fn_enfileirar_audio_core(
    p_aula_id, p_storage_path, p_duracao_segundos, p_registro_id,
    'whatsapp', p_professor_id);
end
$function$;

-- Correcoes de fatia e pendencia de presenca.
create or replace function public.fn_atualizar_fatia_core(
  p_professor_id integer, p_id uuid, p_texto text default null::text,
  p_campos jsonb default null::jsonb
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
declare
  v_reg public.fabio_registros_aula%rowtype;
  v_prof_dono integer;
  v_campos_novos jsonb;
  v_tronco public.fabio_registros_aula%rowtype;
  v_out jsonb;
begin
  if p_professor_id is null then raise exception 'sem_professor_vinculado'; end if;
  select * into v_reg from public.fabio_registros_aula where id = p_id;
  if not found then raise exception 'Registro % nao encontrado', p_id; end if;
  v_prof_dono := v_reg.professor_id;
  if v_prof_dono is null and v_reg.parent_id is not null then
    select professor_id into v_prof_dono from public.fabio_registros_aula
     where id = v_reg.parent_id;
  end if;
  if v_prof_dono is distinct from p_professor_id then
    raise exception 'Registro nao pertence a este professor';
  end if;
  if v_reg.status not in ('rascunho', 'aguardando_confirmacao') then
    raise exception 'Status % nao permite edicao', v_reg.status;
  end if;
  v_campos_novos := case when p_campos is null then v_reg.campos
                         else v_reg.campos || p_campos end;

  if v_reg.parent_id is null then
    update public.fabio_registros_aula
       set campos = v_campos_novos,
           texto_consolidado = public.fn_compor_texto_prontuario(
             v_campos_novos, '{}'::jsonb)
     where id = p_id returning * into v_reg;
    update public.fabio_registros_aula f
       set texto_consolidado = public.fn_compor_texto_prontuario(
         v_campos_novos, f.campos)
     where f.parent_id = p_id;
  else
    select * into v_tronco from public.fabio_registros_aula where id = v_reg.parent_id;
    if not found then raise exception 'Tronco do registro % nao encontrado', p_id; end if;
    update public.fabio_registros_aula
       set campos = v_campos_novos,
           texto_consolidado = public.fn_compor_texto_prontuario(
             v_tronco.campos, v_campos_novos)
     where id = p_id returning * into v_reg;
  end if;
  select to_jsonb(v_reg) into v_out;
  return v_out;
end
$function$;

create or replace function public.app_atualizar_fatia(
  p_id uuid, p_texto text default null::text, p_campos jsonb default null::jsonb
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
declare v_prof integer := public.fn_professor_do_usuario();
begin
  if v_prof is null then raise exception 'Usuario sem professor vinculado'; end if;
  return public.fn_atualizar_fatia_core(v_prof, p_id, p_texto, p_campos);
end
$function$;

create or replace function public.fabio_atualizar_fatia(
  p_professor_id integer, p_id uuid, p_texto text default null::text,
  p_campos jsonb default null::jsonb
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
begin
  return public.fn_atualizar_fatia_core(p_professor_id, p_id, p_texto, p_campos);
end
$function$;

create or replace function public.fn_responder_presenca_core(
  p_professor_id integer, p_registro_alvo_id uuid, p_presenca text
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
declare v_reg public.fabio_registros_aula%rowtype;
begin
  if p_professor_id is null then raise exception 'sem_professor_vinculado'; end if;
  if p_presenca not in ('presente', 'ausente') then
    raise exception 'Presenca invalida: % (use presente ou ausente)', p_presenca;
  end if;
  select * into v_reg from public.fabio_registros_aula where id = p_registro_alvo_id;
  if not found then raise exception 'Registro % nao encontrado', p_registro_alvo_id; end if;
  if v_reg.professor_id is distinct from p_professor_id then
    raise exception 'Registro nao pertence a este professor';
  end if;
  if v_reg.status not in ('rascunho', 'aguardando_confirmacao', 'confirmado') then
    raise exception 'Status % nao aceita mais resposta de presenca', v_reg.status;
  end if;
  update public.fabio_registros_aula
     set campos = coalesce(campos, '{}'::jsonb)
                  || jsonb_build_object('presenca', p_presenca),
         atualizado_em = now()
   where id = p_registro_alvo_id;
  return jsonb_build_object('ok', true,
    'registro_alvo_id', p_registro_alvo_id, 'presenca', p_presenca);
end
$function$;

create or replace function public.app_responder_presenca(
  p_registro_alvo_id uuid, p_presenca text
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
declare v_prof integer := public.fn_professor_do_usuario();
begin
  if v_prof is null then raise exception 'Usuario sem professor vinculado'; end if;
  return public.fn_responder_presenca_core(v_prof, p_registro_alvo_id, p_presenca);
end
$function$;

create or replace function public.fabio_responder_presenca(
  p_professor_id integer, p_registro_alvo_id uuid, p_presenca text
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
begin
  return public.fn_responder_presenca_core(
    p_professor_id, p_registro_alvo_id, p_presenca);
end
$function$;

-- Confirmacao: o miolo recebe autoria explicita; nenhum canal fornece um
-- usuario diferente do professor resolvido dentro do proprio banco.
create or replace function public.fn_confirmar_registro_core(
  p_professor_id integer, p_confirmado_por uuid, p_registro_id uuid, p_modo text
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
declare
  v_reg public.fabio_registros_aula%rowtype;
  v_fatia record;
  v_gravadas integer := 0;
  v_puladas integer := 0;
  v_pend jsonb := '[]'::jsonb;
  v_alvo integer;
  v_texto text;
  v_ganchos jsonb;
  v_decl text;
  v_user_id integer;
begin
  if p_professor_id is null then raise exception 'sem_professor_vinculado'; end if;
  if p_modo not in ('novo', 'substituir', 'complementar') then
    raise exception 'Modo invalido: %', p_modo;
  end if;
  select u.id into v_user_id
    from public.usuarios u
   where u.auth_user_id = p_confirmado_por;
  select * into v_reg from public.fabio_registros_aula
   where id = p_registro_id and parent_id is null;
  if not found then raise exception 'Registro % nao encontrado', p_registro_id; end if;
  if v_reg.professor_id is distinct from p_professor_id then
    raise exception 'Registro nao pertence a este professor';
  end if;
  if v_reg.status not in ('rascunho', 'aguardando_confirmacao') then
    raise exception 'Status % nao permite confirmacao', v_reg.status;
  end if;

  if v_reg.aluno_id is not null then
    v_decl := public.fn_presenca_declarada(v_reg.campos);
    if v_decl = 'nao_informada' then
      v_pend := v_pend || public.fn_pendencia_presenca(
        v_reg.id, 'raiz', v_reg.aluno_id);
    elsif v_decl = 'ausente' then
      v_puladas := 1;
      update public.fabio_registros_aula
         set status = 'confirmado', confirmado_em = now(),
             confirmado_por = v_user_id
       where id = p_registro_id;
    else
      v_texto := coalesce(
        public.fn_compor_texto_prontuario(v_reg.campos, v_reg.campos),
        nullif(btrim(v_reg.texto_consolidado), ''));
      if v_texto is null then raise exception 'Registro sem conteudo'; end if;
      v_alvo := public.fn_aula_individual_do_aluno(v_reg.aula_id, v_reg.aluno_id);
      perform public.registrar_aula_fabio(
        p_aula_id => v_alvo, p_texto => v_texto,
        p_origem => case when v_reg.origem in ('audio', 'texto')
                         then v_reg.origem else 'audio' end,
        p_professor_id => v_reg.professor_id, p_modo => p_modo);
      v_gravadas := 1;
      update public.fabio_registros_aula
         set status = 'gravado_emusys', confirmado_em = now(),
             confirmado_por = v_user_id
       where id = p_registro_id;
    end if;
  else
    for v_fatia in select * from public.fabio_registros_aula
                    where parent_id = p_registro_id
    loop
      v_texto := coalesce(
        public.fn_compor_texto_prontuario(v_reg.campos, v_fatia.campos),
        nullif(btrim(v_fatia.texto_consolidado), ''));
      v_decl := public.fn_presenca_declarada(v_fatia.campos);
      if v_decl = 'nao_informada' then
        v_pend := v_pend || public.fn_pendencia_presenca(
          v_fatia.id, 'fatia', v_fatia.aluno_id);
      elsif v_decl = 'ausente' then
        v_puladas := v_puladas + 1;
        update public.fabio_registros_aula
           set status = 'confirmado', confirmado_em = now(),
               confirmado_por = v_user_id
         where id = v_fatia.id;
      elsif v_fatia.aula_id is null or v_fatia.aluno_id is null or v_texto is null then
        v_pend := v_pend || jsonb_build_object(
          'registro_alvo_id', v_fatia.id, 'tipo_alvo', 'fatia',
          'fatia_id', v_fatia.id, 'aluno_id', v_fatia.aluno_id,
          'aluno_nome', (select a.nome from public.alunos a where a.id = v_fatia.aluno_id),
          'campo_obrigatorio', null, 'valores_permitidos', null,
          'motivo', case when v_fatia.aula_id is null then 'sem aula vinculada'
                         when v_fatia.aluno_id is null then 'sem aluno vinculado'
                         else 'sem conteudo' end);
      else
        v_alvo := public.fn_aula_individual_do_aluno(v_fatia.aula_id, v_fatia.aluno_id);
        perform public.registrar_aula_fabio(
          p_aula_id => v_alvo, p_texto => v_texto,
          p_origem => case when v_fatia.origem in ('audio', 'texto')
                           then v_fatia.origem else 'audio' end,
          p_professor_id => v_reg.professor_id, p_modo => p_modo);
        v_gravadas := v_gravadas + 1;
        update public.fabio_registros_aula
           set status = 'gravado_emusys', confirmado_em = now(),
               confirmado_por = v_user_id, aula_id = v_alvo,
               campos = campos || jsonb_build_object('aula_alvo_resolvida', v_alvo)
         where id = v_fatia.id;
      end if;
    end loop;

    if v_gravadas = 0 and v_puladas = 0 and jsonb_array_length(v_pend) = 0 then
      raise exception 'Nada gravavel neste registro. Pendencias: %', v_pend::text;
    end if;
    if jsonb_array_length(v_pend) = 0 then
      update public.fabio_registros_aula
         set status = 'gravado_emusys', confirmado_em = now(),
             confirmado_por = v_user_id
       where id = p_registro_id;
    else
      update public.fabio_registros_aula
         set status = 'confirmado', confirmado_em = now(),
             confirmado_por = v_user_id
       where id = p_registro_id;
    end if;
  end if;

  v_ganchos := public.fabio_emitir_presenca_por_registro_e_devolutiva(p_registro_id);
  return jsonb_build_object(
    'registro_id', p_registro_id, 'modo', p_modo, 'gravadas', v_gravadas,
    'ausentes_puladas', v_puladas, 'pendencias', v_pend,
    'presenca', v_ganchos -> 'presenca',
    'devolutivas_enfileiradas', v_ganchos -> 'devolutivas_enfileiradas');
end
$function$;

create or replace function public.app_confirmar_registro(
  p_registro_id uuid, p_modo text default 'novo'::text
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
declare
  v_prof integer := public.fn_professor_do_usuario();
  v_user_id uuid;
begin
  if v_prof is null then raise exception 'Usuario sem professor vinculado'; end if;
  select u.auth_user_id into v_user_id from public.usuarios u
   join public.professores p on p.usuario_id = u.id where p.id = v_prof;
  return public.fn_confirmar_registro_core(v_prof, v_user_id, p_registro_id, p_modo);
end
$function$;

create or replace function public.fabio_confirmar_registro(
  p_professor_id integer, p_registro_id uuid, p_modo text default 'novo'::text
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
declare v_user_id uuid;
begin
  select u.auth_user_id into v_user_id from public.professores p
   left join public.usuarios u on u.id = p.usuario_id where p.id = p_professor_id;
  if not found then raise exception 'professor_nao_encontrado'; end if;
  return public.fn_confirmar_registro_core(
    p_professor_id, v_user_id, p_registro_id, p_modo);
end
$function$;

-- Presenca: um unico escritor. A origem do WhatsApp e forte e a sincronizacao
-- dos gemeos continua sendo feita pelo helper 086 chamado pelo core.
create or replace function public.fn_registrar_presencas_core(
  p_aula_ancora_id integer,
  p_professor_id integer,
  p_alunos_ausentes integer[] default '{}'::integer[],
  p_respondido_por text default 'professor_la_teacher'::text,
  p_estrito boolean default true
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
declare
  v_aula public.aulas_emusys%rowtype;
  v_roster_total integer;
  v_sem_vinculo integer;
  v_inseridos integer;
  v_promovidos integer;
  v_gemeos integer;
begin
  if p_respondido_por not in (
    'professor_la_teacher', 'fabio_audio', 'professor_whatsapp') then
    raise exception 'respondido_por_invalido: %', p_respondido_por;
  end if;
  select * into v_aula from public.aulas_emusys where id = p_aula_ancora_id;
  if not found then
    if p_estrito then raise exception 'aula_nao_encontrada'; end if;
    return jsonb_build_object('aula_id', p_aula_ancora_id,
      'aplicado', false, 'motivo', 'aula_nao_encontrada');
  end if;
  if coalesce(v_aula.cancelada, false) then
    if p_estrito then raise exception 'aula_cancelada'; end if;
    return jsonb_build_object('aula_id', v_aula.id,
      'aplicado', false, 'motivo', 'aula_cancelada');
  end if;
  if v_aula.professor_id is distinct from p_professor_id then
    if p_estrito then
      raise exception 'aula_nao_pertence_ao_professor' using errcode = '42501';
    end if;
    return jsonb_build_object('aula_id', v_aula.id,
      'aplicado', false, 'motivo', 'professor_divergente');
  end if;
  if p_estrito then
    if v_aula.data_hora_inicio > now() + interval '15 minutes' then
      raise exception 'chamada_ainda_nao_disponivel';
    end if;
    if coalesce(v_aula.data_hora_fim, v_aula.data_hora_inicio)
        < now() - (public.fn_janela_registro_dias() || ' days')::interval then
      raise exception 'janela_de_chamada_encerrada';
    end if;
  end if;

  select count(*), count(*) filter (where aluno_id is null)
    into v_roster_total, v_sem_vinculo
    from public.aula_alunos_emusys where aula_emusys_id = v_aula.id;
  if v_roster_total = 0 then
    if p_estrito then raise exception 'roster_nao_sincronizado'; end if;
    return jsonb_build_object('aula_id', v_aula.id,
      'aplicado', false, 'motivo', 'roster_nao_sincronizado');
  end if;
  if v_sem_vinculo > 0 then
    if p_estrito then raise exception 'roster_incompleto'; end if;
    return jsonb_build_object('aula_id', v_aula.id,
      'aplicado', false, 'motivo', 'roster_incompleto');
  end if;
  if exists (
    select 1 from unnest(coalesce(p_alunos_ausentes, '{}'::integer[])) a(aluno_id)
     where not exists (select 1 from public.aula_alunos_emusys r
                        where r.aula_emusys_id = v_aula.id
                          and r.aluno_id = a.aluno_id)
  ) then
    if p_estrito then raise exception 'aluno_ausente_fora_do_roster'; end if;
    return jsonb_build_object('aula_id', v_aula.id,
      'aplicado', false, 'motivo', 'aluno_ausente_fora_do_roster');
  end if;

  with up as (
    insert into public.aluno_presenca (
      aluno_id, aula_emusys_id, professor_id, unidade_id, data_aula,
      horario_aula, status, status_presenca, curso_nome, turma_nome,
      sala_nome, respondido_por, respondido_em)
    select distinct r.aluno_id, v_aula.id, p_professor_id, v_aula.unidade_id,
      v_aula.data_aula, (v_aula.data_hora_inicio at time zone 'America/Sao_Paulo')::time,
      case when r.aluno_id = any(coalesce(p_alunos_ausentes, '{}'::integer[]))
           then 'ausente' else 'presente' end,
      case when r.aluno_id = any(coalesce(p_alunos_ausentes, '{}'::integer[]))
           then 'falta' else 'presente' end,
      v_aula.curso_nome, v_aula.turma_nome, v_aula.sala_nome,
      p_respondido_por, now()
      from public.aula_alunos_emusys r
     where r.aula_emusys_id = v_aula.id and r.aluno_id is not null
    on conflict (aluno_id, aula_emusys_id) do update
      set status = excluded.status, status_presenca = excluded.status_presenca,
          respondido_por = excluded.respondido_por, respondido_em = excluded.respondido_em
      where aluno_presenca.respondido_por is null
         or aluno_presenca.respondido_por in ('emusys', 'sistema')
    returning (xmax = 0) as inserido
  )
  select count(*) filter (where inserido), count(*) filter (where not inserido)
    into v_inseridos, v_promovidos from up;

  v_gemeos := public.fn_sincronizar_gemeos_presenca(v_aula.id);
  return jsonb_build_object(
    'aula_id', v_aula.id, 'total_roster', v_roster_total,
    'inseridos', coalesce(v_inseridos, 0),
    'promovidos', coalesce(v_promovidos, 0),
    'ja_havia_forte', v_roster_total - coalesce(v_inseridos, 0)
      - coalesce(v_promovidos, 0),
    'gemeos_sincronizados', coalesce(v_gemeos, 0), 'aplicado', true);
end
$function$;

create or replace function public.app_registrar_presencas_aula(
  p_aula_emusys_id integer,
  p_alunos_ausentes integer[] default '{}'::integer[]
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
declare
  v_prof integer := public.fn_professor_do_usuario();
  v_aula public.aulas_emusys%rowtype;
  v_turma_irma integer;
  v_roster_total integer;
  v_sem_vinculo integer;
  v_res jsonb;
begin
  if v_prof is null then
    raise exception 'sem_professor_vinculado' using errcode = '42501';
  end if;
  select * into v_aula from public.aulas_emusys where id = p_aula_emusys_id;
  if not found or v_aula.professor_id is distinct from v_prof then
    raise exception 'aula_nao_pertence_ao_professor' using errcode = '42501';
  end if;
  if coalesce(v_aula.cancelada, false) then raise exception 'aula_cancelada'; end if;
  if coalesce(v_aula.tipo, '') <> 'turma' then
    select t.id into v_turma_irma from public.aulas_emusys t
     where t.tipo = 'turma' and t.unidade_id = v_aula.unidade_id
       and t.data_hora_inicio = v_aula.data_hora_inicio
       and t.professor_id is not distinct from v_aula.professor_id
       and coalesce(t.cancelada, false) = false limit 1;
    if v_turma_irma is not null then
      raise exception 'chamada_somente_na_aula_ancora (use a aula % deste horario)', v_turma_irma;
    end if;
  end if;
  select count(*) filter (where aluno_id is not null),
         count(*) filter (where aluno_id is null)
    into v_roster_total, v_sem_vinculo
    from public.aula_alunos_emusys where aula_emusys_id = v_aula.id;
  if v_roster_total > 0 and v_sem_vinculo = 0 and not exists (
    select 1 from public.aula_alunos_emusys r
     where r.aula_emusys_id = v_aula.id and r.aluno_id is not null
       and not exists (
         select 1 from public.aluno_presenca ap
          where ap.aula_emusys_id = v_aula.id and ap.aluno_id = r.aluno_id
            and public.fn_presenca_e_forte(ap.respondido_por))) then
    return jsonb_build_object('aula_id', v_aula.id,
      'total_roster', v_roster_total, 'inseridos', 0,
      'ignorados_first_write_wins', v_roster_total,
      'ja_havia_registros', true, 'chamada_ja_enviada', true);
  end if;
  v_res := public.fn_registrar_presencas_core(
    v_aula.id, v_prof, p_alunos_ausentes, 'professor_la_teacher', true);
  return v_res || jsonb_build_object(
    'chamada_ja_enviada', false,
    'ignorados_first_write_wins', coalesce((v_res->>'total_roster')::int, 0)
      - coalesce((v_res->>'inseridos')::int, 0),
    'ja_havia_registros', (coalesce((v_res->>'total_roster')::int, 0)
      - coalesce((v_res->>'inseridos')::int, 0)) > 0);
end
$function$;

create or replace function public.fabio_registrar_presencas_aula(
  p_professor_id integer, p_aula_emusys_id integer,
  p_alunos_ausentes integer[] default '{}'::integer[]
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
declare
  v_aula public.aulas_emusys%rowtype;
  v_turma_irma integer;
  v_roster_total integer;
  v_sem_vinculo integer;
  v_res jsonb;
begin
  select * into v_aula from public.aulas_emusys where id = p_aula_emusys_id;
  if not found or v_aula.professor_id is distinct from p_professor_id then
    raise exception 'aula_nao_pertence_ao_professor' using errcode = '42501';
  end if;
  if coalesce(v_aula.cancelada, false) then raise exception 'aula_cancelada'; end if;
  if coalesce(v_aula.tipo, '') <> 'turma' then
    select t.id into v_turma_irma from public.aulas_emusys t
     where t.tipo = 'turma' and t.unidade_id = v_aula.unidade_id
       and t.data_hora_inicio = v_aula.data_hora_inicio
       and t.professor_id is not distinct from v_aula.professor_id
       and coalesce(t.cancelada, false) = false limit 1;
    if v_turma_irma is not null then
      raise exception 'chamada_somente_na_aula_ancora (use a aula % deste horario)', v_turma_irma;
    end if;
  end if;
  select count(*) filter (where aluno_id is not null),
         count(*) filter (where aluno_id is null)
    into v_roster_total, v_sem_vinculo
    from public.aula_alunos_emusys where aula_emusys_id = v_aula.id;
  if v_roster_total > 0 and v_sem_vinculo = 0 and not exists (
    select 1 from public.aula_alunos_emusys r
     where r.aula_emusys_id = v_aula.id and r.aluno_id is not null
       and not exists (
         select 1 from public.aluno_presenca ap
          where ap.aula_emusys_id = v_aula.id and ap.aluno_id = r.aluno_id
            and public.fn_presenca_e_forte(ap.respondido_por))) then
    return jsonb_build_object('aula_id', v_aula.id,
      'total_roster', v_roster_total, 'inseridos', 0,
      'ignorados_first_write_wins', v_roster_total,
      'ja_havia_registros', true, 'chamada_ja_enviada', true);
  end if;
  v_res := public.fn_registrar_presencas_core(
    v_aula.id, p_professor_id, p_alunos_ausentes, 'professor_whatsapp', true);
  return v_res || jsonb_build_object(
    'chamada_ja_enviada', false,
    'ignorados_first_write_wins', coalesce((v_res->>'total_roster')::int, 0)
      - coalesce((v_res->>'inseridos')::int, 0),
    'ja_havia_registros', (coalesce((v_res->>'total_roster')::int, 0)
      - coalesce((v_res->>'inseridos')::int, 0)) > 0);
end
$function$;

-- Read-back guardado para o worker, sem acesso direto as tabelas.
create or replace function public.fabio_status_audio_fila(
  p_professor_id integer, p_audio_id uuid
) returns table(
  audio_id uuid, status text, tentativas integer, tem_erro boolean,
  criado_em timestamptz, atualizado_em timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select f.id, f.status, f.tentativas, (f.erro is not null),
         f.criado_em, f.atualizado_em
    from public.fabio_fila_audios f
   where f.id = p_audio_id and f.professor_id = p_professor_id;
$function$;

create or replace function public.fabio_registro_completo(
  p_professor_id integer, p_registro_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_tronco jsonb;
  v_fatias jsonb;
  v_aula jsonb;
  v_ja jsonb;
  v_aula_id integer;
begin
  if p_professor_id is null then
    return jsonb_build_object('erro', 'sem_professor');
  end if;
  select to_jsonb(r) into v_tronco from public.fabio_registros_aula r
   where r.id = p_registro_id and r.parent_id is null
     and r.professor_id = p_professor_id;
  if v_tronco is null then
    return jsonb_build_object('erro', 'nao_encontrado');
  end if;

  v_aula_id := (v_tronco->>'aula_id')::integer;
  select coalesce(jsonb_agg(
           to_jsonb(r) || jsonb_build_object(
             'aluno_nome', a.nome,
             'aluno_primeiro_nome', split_part(btrim(a.nome), ' ', 1),
             'aluno_foto_url', a.foto_url,
             'aula_id_alvo', case when r.aluno_id is not null
               then public.fn_aula_individual_do_aluno(r.aula_id, r.aluno_id) end
           ) order by a.nome), '[]'::jsonb)
    into v_fatias
    from public.fabio_registros_aula r
    left join public.alunos a on a.id = r.aluno_id
   where r.parent_id = p_registro_id;

  select jsonb_build_object(
           'data_aula', v.data_aula, 'hora', v.horario_inicio_brt,
           'turma', v.turma_nome, 'curso', v.curso_nome, 'tipo', v.aula_tipo)
    into v_aula
    from public.vw_fabio_aulas_contexto v
   where v.aula_local_id = v_aula_id limit 1;
  v_ja := public.fn_aula_ja_registrada(v_aula_id);

  return jsonb_build_object(
    'tronco', v_tronco, 'fatias', v_fatias, 'aula', v_aula,
    'aula_ja_registrada', (jsonb_array_length(v_ja) > 0),
    'ja_registrados', v_ja,
    'modo_exigido', case when jsonb_array_length(v_ja) > 0
                         then 'substituir|complementar' else 'novo' end);
end
$function$;

-- ACL: app segue autenticado; fabio_* fica somente no service_role; cores e
-- sobrecarga interna nao sao chamaveis pela API.
revoke all on function public.fn_enfileirar_audio_core(integer,text,integer,uuid,text)
  from public, anon, authenticated, service_role;
revoke all on function public.fn_enfileirar_audio_core(integer,text,integer,uuid,text,integer)
  from public, anon, authenticated, service_role;
revoke all on function public.fn_atualizar_fatia_core(integer,uuid,text,jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.fn_responder_presenca_core(integer,uuid,text)
  from public, anon, authenticated, service_role;
revoke all on function public.fn_confirmar_registro_core(integer,uuid,uuid,text)
  from public, anon, authenticated, service_role;
revoke all on function public.fn_registrar_presencas_core(integer,integer,integer[],text,boolean)
  from public, anon, authenticated;

revoke all on function public.app_enfileirar_audio(integer,text,integer,uuid) from public, anon;
revoke all on function public.app_atualizar_fatia(uuid,text,jsonb) from public, anon;
revoke all on function public.app_responder_presenca(uuid,text) from public, anon;
revoke all on function public.app_confirmar_registro(uuid,text) from public, anon;
revoke all on function public.app_registrar_presencas_aula(integer,integer[]) from public, anon;
grant execute on function public.app_enfileirar_audio(integer,text,integer,uuid) to authenticated, service_role;
grant execute on function public.app_atualizar_fatia(uuid,text,jsonb) to authenticated, service_role;
grant execute on function public.app_responder_presenca(uuid,text) to authenticated, service_role;
grant execute on function public.app_confirmar_registro(uuid,text) to authenticated, service_role;
grant execute on function public.app_registrar_presencas_aula(integer,integer[]) to authenticated, service_role;

revoke all on function public.fabio_enfileirar_audio(integer,integer,text,integer,uuid)
  from public, anon, authenticated;
revoke all on function public.fabio_atualizar_fatia(integer,uuid,text,jsonb)
  from public, anon, authenticated;
revoke all on function public.fabio_responder_presenca(integer,uuid,text)
  from public, anon, authenticated;
revoke all on function public.fabio_confirmar_registro(integer,uuid,text)
  from public, anon, authenticated;
revoke all on function public.fabio_registrar_presencas_aula(integer,integer,integer[])
  from public, anon, authenticated;
revoke all on function public.fabio_status_audio_fila(integer,uuid)
  from public, anon, authenticated;
revoke all on function public.fabio_registro_completo(integer,uuid)
  from public, anon, authenticated;

grant execute on function public.fabio_enfileirar_audio(integer,integer,text,integer,uuid) to service_role;
grant execute on function public.fabio_atualizar_fatia(integer,uuid,text,jsonb) to service_role;
grant execute on function public.fabio_responder_presenca(integer,uuid,text) to service_role;
grant execute on function public.fabio_confirmar_registro(integer,uuid,text) to service_role;
grant execute on function public.fabio_registrar_presencas_aula(integer,integer,integer[]) to service_role;
grant execute on function public.fabio_status_audio_fila(integer,uuid) to service_role;
grant execute on function public.fabio_registro_completo(integer,uuid) to service_role;
