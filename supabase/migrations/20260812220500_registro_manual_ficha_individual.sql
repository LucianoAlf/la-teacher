-- Registro manual por ficha individual.
-- Reutiliza fabio_registros_aula e a confirmacao canonica; rascunho nunca escreve presenca.

set lock_timeout = '5s';
set statement_timeout = '60s';

alter table public.fabio_registros_aula
  add column if not exists modo_entrada text not null default 'audio';

alter table public.fabio_registros_aula
  add column if not exists versao integer not null default 1;

do $function$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.fabio_registros_aula'::regclass
      and conname = 'fabio_registros_aula_modo_entrada_check'
  ) then
    alter table public.fabio_registros_aula
      add constraint fabio_registros_aula_modo_entrada_check
      check (modo_entrada in ('audio','manual')) not valid;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.fabio_registros_aula'::regclass
      and conname = 'fabio_registros_aula_versao_check'
  ) then
    alter table public.fabio_registros_aula
      add constraint fabio_registros_aula_versao_check
      check (versao >= 1) not valid;
  end if;
end
$function$;

alter table public.fabio_registros_aula
  validate constraint fabio_registros_aula_modo_entrada_check;
alter table public.fabio_registros_aula
  validate constraint fabio_registros_aula_versao_check;

create unique index if not exists ux_fabio_reg_manual_aberto
  on public.fabio_registros_aula(professor_id, aula_id)
  where parent_id is null
    and modo_entrada = 'manual'
    and status in ('rascunho','aguardando_confirmacao');

comment on column public.fabio_registros_aula.modo_entrada is
  'Meio de composicao pedagogica: audio ou manual. origem continua sendo o canal app/whatsapp.';
comment on column public.fabio_registros_aula.versao is
  'Versao otimista do rascunho; impede que duas abas sobrescrevam campos silenciosamente.';

create or replace function public.fn_campos_registro_manual_validos(
  p_campos jsonb,
  p_tronco boolean
) returns boolean
language sql
immutable
security definer
set search_path = pg_catalog, public
as $function$
  select jsonb_typeof(coalesce(p_campos, '{}'::jsonb)) = 'object'
    and not exists (
      select 1
      from jsonb_each(coalesce(p_campos, '{}'::jsonb)) as item(chave, valor)
      where item.chave <> all(
        case when p_tronco
          then array['atividades','objetivo','repertorio','dever_casa','obs_gerais','materiais']::text[]
          else array['repertorio','atividades','objetivo','observacao','dever_casa','progresso']::text[]
        end
      )
      or jsonb_typeof(item.valor) not in ('string','null')
    );
$function$;

revoke all on function public.fn_campos_registro_manual_validos(jsonb,boolean)
  from public, anon, authenticated, service_role;

create or replace function public.app_abrir_rascunho_manual(p_aula_id integer)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_professor integer := public.fn_professor_do_usuario();
  v_aula public.aulas_emusys%rowtype;
  v_raiz uuid;
  v_audio uuid;
  v_total integer;
  v_sem_aluno integer;
  v_roster record;
  v_alvo integer;
  v_adicionados integer := 0;
  v_saida jsonb;
begin
  if v_professor is null then raise exception 'sem_professor_vinculado'; end if;

  select * into v_aula from public.aulas_emusys where id = p_aula_id;
  if not found then raise exception 'aula_nao_encontrada'; end if;
  if v_aula.professor_id is distinct from v_professor then
    raise exception 'aula_nao_pertence_ao_professor' using errcode='42501';
  end if;
  if coalesce(v_aula.cancelada,false) then raise exception 'aula_cancelada'; end if;
  if v_aula.data_hora_inicio > now() + interval '15 minutes' then
    raise exception 'registro_ainda_nao_disponivel';
  end if;
  if coalesce(v_aula.data_hora_fim,v_aula.data_hora_inicio)
      < now() - (public.fn_janela_registro_dias() || ' days')::interval then
    raise exception 'janela_de_gravacao_encerrada';
  end if;

  select count(*), count(*) filter(where aluno_id is null)
    into v_total, v_sem_aluno
    from public.aula_alunos_emusys
   where aula_emusys_id = v_aula.id;
  if v_total = 0 then raise exception 'roster_nao_sincronizado'; end if;
  if v_sem_aluno > 0 then raise exception 'roster_incompleto'; end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'fabio-registro-manual:' || v_professor::text || ':' || v_aula.id::text, 0
  ));

  select id into v_raiz
    from public.fabio_registros_aula
   where professor_id = v_professor
     and aula_id = v_aula.id
     and parent_id is null
     and modo_entrada = 'manual'
     and status in ('rascunho','aguardando_confirmacao')
   order by criado_em desc, id
   limit 1
   for update;

  if v_raiz is null then
    -- Resolve todos os alvos antes de escrever: uma turma sem fatia individual
    -- falha inteira, sem deixar uma raiz orfa.
    for v_roster in
      select distinct r.aluno_id
        from public.aula_alunos_emusys r
       where r.aula_emusys_id = v_aula.id
       order by r.aluno_id
    loop
      perform public.fn_aula_individual_do_aluno(v_aula.id,v_roster.aluno_id);
    end loop;

    insert into public.fabio_registros_aula(
      aula_id,unidade_id,professor_id,aluno_id,parent_id,molde,campos,
      texto_consolidado,status,origem,audio_id,modo_entrada,versao
    ) values (
      v_aula.id,v_aula.unidade_id,v_professor,null,null,'C','{}',
      null,'rascunho','app',null,'manual',1
    ) returning id into v_raiz;

    for v_roster in
      select distinct r.aluno_id
        from public.aula_alunos_emusys r
       where r.aula_emusys_id = v_aula.id
       order by r.aluno_id
    loop
      v_alvo := public.fn_aula_individual_do_aluno(v_aula.id,v_roster.aluno_id);
      insert into public.fabio_registros_aula(
        aula_id,unidade_id,professor_id,aluno_id,parent_id,molde,campos,
        texto_consolidado,status,origem,audio_id,modo_entrada,versao
      ) values (
        v_alvo,v_aula.unidade_id,v_professor,v_roster.aluno_id,v_raiz,'C','{}',
        null,'rascunho','app',null,'manual',1
      );
    end loop;
  else
    -- Roster pode sincronizar depois da primeira abertura. Incluímos alunos
    -- novos, mas nunca apagamos silenciosamente uma ficha que já saiu do roster.
    if exists (
      select 1
        from public.fabio_registros_aula f
       where f.parent_id=v_raiz
         and (
           f.aluno_id is null
           or not exists (
             select 1 from public.aula_alunos_emusys r
              where r.aula_emusys_id=v_aula.id and r.aluno_id=f.aluno_id
           )
         )
    ) then
      raise exception 'roster_divergente';
    end if;

    for v_roster in
      select distinct r.aluno_id
        from public.aula_alunos_emusys r
       where r.aula_emusys_id=v_aula.id
         and not exists (
           select 1 from public.fabio_registros_aula f
            where f.parent_id=v_raiz and f.aluno_id=r.aluno_id
         )
       order by r.aluno_id
    loop
      v_alvo := public.fn_aula_individual_do_aluno(v_aula.id,v_roster.aluno_id);
      insert into public.fabio_registros_aula(
        aula_id,unidade_id,professor_id,aluno_id,parent_id,molde,campos,
        texto_consolidado,status,origem,audio_id,modo_entrada,versao
      ) values (
        v_alvo,v_aula.unidade_id,v_professor,v_roster.aluno_id,v_raiz,'C','{}',
        null,'rascunho','app',null,'manual',1
      );
      v_adicionados := v_adicionados + 1;
    end loop;
    if v_adicionados > 0 then
      update public.fabio_registros_aula
         set versao=versao+1, atualizado_em=now()
       where id=v_raiz;
    end if;
  end if;

  select id into v_audio
    from public.fabio_registros_aula
   where professor_id = v_professor
     and aula_id = v_aula.id
     and parent_id is null
     and modo_entrada = 'audio'
     and status in ('rascunho','aguardando_confirmacao')
   order by criado_em desc,id
   limit 1;

  v_saida := public.app_registro_completo(v_raiz);
  return v_saida || jsonb_build_object(
    'audio_aberto_registro_id',v_audio,
    'modo_entrada','manual'
  );
end
$function$;

revoke all on function public.app_abrir_rascunho_manual(integer)
  from public, anon, service_role;
grant execute on function public.app_abrir_rascunho_manual(integer)
  to authenticated;

create or replace function public.app_salvar_rascunho_manual(
  p_registro_id uuid,
  p_versao integer,
  p_tronco_campos jsonb,
  p_fatias jsonb
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_professor integer := public.fn_professor_do_usuario();
  v_raiz public.fabio_registros_aula%rowtype;
  v_item jsonb;
  v_fatia public.fabio_registros_aula%rowtype;
  v_fatia_id uuid;
  v_ids uuid[] := '{}'::uuid[];
  v_campos jsonb;
  v_total integer;
begin
  if v_professor is null then raise exception 'sem_professor_vinculado'; end if;
  if p_versao is null then raise exception 'versao_obrigatoria'; end if;
  if jsonb_typeof(coalesce(p_fatias,'null'::jsonb)) <> 'array' then
    raise exception 'fatias_invalidas';
  end if;
  if not public.fn_campos_registro_manual_validos(p_tronco_campos,true) then
    raise exception 'campo_manual_invalido';
  end if;

  select * into v_raiz
    from public.fabio_registros_aula
   where id=p_registro_id
     and professor_id=v_professor
     and parent_id is null
     and modo_entrada='manual'
     and status in ('rascunho','aguardando_confirmacao')
   for update;
  if not found then raise exception 'rascunho_manual_nao_encontrado'; end if;
  if v_raiz.versao is distinct from p_versao then
    raise exception 'conflito_de_versao: esperado %, atual %',p_versao,v_raiz.versao using errcode='40001';
  end if;

  select count(*) into v_total from public.fabio_registros_aula where parent_id=v_raiz.id;
  for v_item in select value from jsonb_array_elements(p_fatias)
  loop
    if jsonb_typeof(v_item)<>'object' then raise exception 'fatia_manual_invalida'; end if;
    begin
      v_fatia_id := nullif(v_item->>'id','')::uuid;
    exception when invalid_text_representation then
      raise exception 'fatia_manual_invalida';
    end;
    if v_fatia_id is null or v_fatia_id=any(v_ids) then raise exception 'fatias_divergentes'; end if;
    v_campos := coalesce(v_item->'campos','{}'::jsonb);
    if not public.fn_campos_registro_manual_validos(v_campos,false) then
      raise exception 'campo_manual_invalido';
    end if;
    select * into v_fatia from public.fabio_registros_aula
     where id=v_fatia_id and parent_id=v_raiz.id and modo_entrada='manual'
     for update;
    if not found then raise exception 'fatias_divergentes'; end if;
    v_ids := array_append(v_ids,v_fatia_id);
  end loop;
  if cardinality(v_ids) is distinct from v_total then raise exception 'fatias_divergentes'; end if;
  if exists (
    select 1 from public.fabio_registros_aula f
     where f.parent_id=v_raiz.id
       and (
         f.aluno_id is null
         or not exists (
           select 1 from public.aula_alunos_emusys r
            where r.aula_emusys_id=v_raiz.aula_id and r.aluno_id=f.aluno_id
         )
       )
  ) or (
    select count(distinct r.aluno_id)
      from public.aula_alunos_emusys r
     where r.aula_emusys_id=v_raiz.aula_id and r.aluno_id is not null
  ) is distinct from v_total then
    raise exception 'roster_divergente';
  end if;

  update public.fabio_registros_aula
     set campos=jsonb_strip_nulls(coalesce(p_tronco_campos,'{}'::jsonb)),
         texto_consolidado=public.fn_compor_texto_prontuario(jsonb_strip_nulls(coalesce(p_tronco_campos,'{}'::jsonb)),'{}'::jsonb),
         versao=versao+1,
         atualizado_em=now()
   where id=v_raiz.id;

  for v_item in select value from jsonb_array_elements(p_fatias)
  loop
    v_fatia_id := (v_item->>'id')::uuid;
    v_campos := jsonb_strip_nulls(coalesce(v_item->'campos','{}'::jsonb));
    -- A edição pedagógica não recebe `presenca` no payload, mas também não pode
    -- apagar uma decisão explícita já feita na etapa de conferência.
    select v_campos || case
      when campos ? 'presenca' then jsonb_build_object('presenca', campos->'presenca')
      else '{}'::jsonb
    end into v_campos
      from public.fabio_registros_aula
     where id=v_fatia_id and parent_id=v_raiz.id;
    update public.fabio_registros_aula
       set campos=v_campos,
           texto_consolidado=public.fn_compor_texto_prontuario(
             jsonb_strip_nulls(coalesce(p_tronco_campos,'{}'::jsonb)),v_campos
           ),
           versao=versao+1,
           atualizado_em=now()
     where id=v_fatia_id and parent_id=v_raiz.id;
  end loop;

  return public.app_registro_completo(v_raiz.id)
    || jsonb_build_object('modo_entrada','manual');
end
$function$;

revoke all on function public.app_salvar_rascunho_manual(uuid,integer,jsonb,jsonb)
  from public, anon, service_role;
grant execute on function public.app_salvar_rascunho_manual(uuid,integer,jsonb,jsonb)
  to authenticated;

create or replace function public.app_preparar_rascunho_manual(
  p_registro_id uuid,
  p_versao integer
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_professor integer := public.fn_professor_do_usuario();
  v_raiz public.fabio_registros_aula%rowtype;
begin
  if v_professor is null then raise exception 'sem_professor_vinculado'; end if;
  select * into v_raiz
    from public.fabio_registros_aula
   where id=p_registro_id
     and professor_id=v_professor
     and parent_id is null
     and modo_entrada='manual'
     and status in ('rascunho','aguardando_confirmacao')
   for update;
  if not found then raise exception 'rascunho_manual_nao_encontrado'; end if;
  if v_raiz.versao is distinct from p_versao then
    raise exception 'conflito_de_versao: esperado %, atual %',p_versao,v_raiz.versao using errcode='40001';
  end if;

  update public.fabio_registros_aula
     set status='aguardando_confirmacao',versao=versao+1,atualizado_em=now()
   where id=v_raiz.id or parent_id=v_raiz.id;

  return public.app_registro_completo(v_raiz.id)
    || jsonb_build_object('modo_entrada','manual');
end
$function$;

revoke all on function public.app_preparar_rascunho_manual(uuid,integer)
  from public, anon, service_role;
grant execute on function public.app_preparar_rascunho_manual(uuid,integer)
  to authenticated;

comment on function public.app_abrir_rascunho_manual(integer) is
  'Abre/cria ficha manual pelo roster canonico, sem escrever presenca.';
comment on function public.app_salvar_rascunho_manual(uuid,integer,jsonb,jsonb) is
  'Salva o agregado manual completo com whitelist e concorrencia otimista.';
comment on function public.app_preparar_rascunho_manual(uuid,integer) is
  'Promove o rascunho manual para o preview canonico; presenca so nasce na confirmacao existente.';

-- O repositório antigo tinha uma versão da materialização que olhava apenas
-- `campos`. Mantemos aqui a definição canônica já usada em produção para que
-- uma falta humana nunca seja convertida em presença ao confirmar o conteúdo.
create or replace function public.fn_materializar_presenca_padrao(
  p_registro_id uuid,
  p_professor_id integer
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_raiz public.fabio_registros_aula%rowtype;
  v_fatia record;
  v_decisao public.aluno_presenca%rowtype;
  v_presenca text;
  v_alterados jsonb := '[]'::jsonb;
  v_ausencias_humanas integer := 0;
begin
  if p_registro_id is null or p_professor_id is null then
    raise exception 'registro_e_professor_obrigatorios';
  end if;

  select * into v_raiz
    from public.fabio_registros_aula
   where id = p_registro_id
     and parent_id is null;
  if not found then raise exception 'Registro % nao encontrado', p_registro_id; end if;
  if v_raiz.professor_id is distinct from p_professor_id then
    raise exception 'Registro nao pertence a este professor';
  end if;

  for v_fatia in
    select f.id, f.aula_id, f.aluno_id, f.campos
      from public.fabio_registros_aula f
     where coalesce(f.professor_id, v_raiz.professor_id) = p_professor_id
       and (
         (v_raiz.aluno_id is null and f.parent_id = v_raiz.id)
         or (v_raiz.aluno_id is not null and f.id = v_raiz.id)
       )
       and public.fn_presenca_declarada(coalesce(f.campos, '{}'::jsonb)) = 'nao_informada'
     for update of f
  loop
    select * into v_decisao
      from public.aluno_presenca ap
     where ap.aluno_id = v_fatia.aluno_id
       and ap.aula_emusys_id = v_fatia.aula_id
     for key share;

    v_presenca := 'presente';
    if found
       and public.fn_presenca_e_forte(v_decisao.respondido_por)
       and coalesce(
         v_decisao.status_presenca,
         case v_decisao.status when 'ausente' then 'falta' end
       ) in ('falta', 'falta_justificada') then
      v_presenca := 'ausente';
      v_ausencias_humanas := v_ausencias_humanas + 1;
    end if;

    update public.fabio_registros_aula
       set campos = coalesce(campos, '{}'::jsonb)
                    || jsonb_build_object('presenca', v_presenca),
           atualizado_em = now()
     where id = v_fatia.id;
    v_alterados := v_alterados || jsonb_build_array(jsonb_build_object(
      'registro_id', v_fatia.id,
      'aluno_id', v_fatia.aluno_id,
      'presenca', v_presenca
    ));
  end loop;

  return jsonb_build_object(
    'registro_id', p_registro_id,
    'alterados', v_alterados,
    'quantidade_alterada', jsonb_array_length(v_alterados),
    'ausencias_humanas_preservadas', v_ausencias_humanas
  );
end
$function$;

-- Presença e confirmação disputam a mesma linha. O lock impede que uma falta
-- atrasada seja escrita depois de o prontuário já ter sido confirmado.
create or replace function public.fn_responder_presenca_core(
  p_professor_id integer,
  p_registro_alvo_id uuid,
  p_presenca text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_reg public.fabio_registros_aula%rowtype;
begin
  if p_professor_id is null then raise exception 'sem_professor_vinculado'; end if;
  if p_presenca not in ('presente', 'ausente') then
    raise exception 'Presenca invalida: % (use presente ou ausente)', p_presenca;
  end if;
  select * into v_reg
    from public.fabio_registros_aula
   where id = p_registro_alvo_id
   for update;
  if not found then raise exception 'Registro % nao encontrado', p_registro_alvo_id; end if;
  if v_reg.professor_id is distinct from p_professor_id then
    raise exception 'Registro nao pertence a este professor';
  end if;
  if v_reg.status not in ('rascunho', 'aguardando_confirmacao', 'confirmado') then
    raise exception 'Status % nao aceita mais resposta de presenca', v_reg.status;
  end if;
  update public.fabio_registros_aula
     set campos = coalesce(campos, '{}'::jsonb) || jsonb_build_object('presenca', p_presenca),
         atualizado_em = now()
   where id = p_registro_alvo_id
     and status in ('rascunho', 'aguardando_confirmacao', 'confirmado');
  if not found then raise exception 'Status alterado durante resposta de presenca'; end if;
  return jsonb_build_object(
    'ok', true,
    'registro_alvo_id', p_registro_alvo_id,
    'presenca', p_presenca
  );
end
$function$;

-- A confirmação manual nasce no LA Teacher. `modo_entrada` diferencia o meio
-- do conteúdo; `respondido_por` continua identificando o sistema da presença.
create or replace function public.fabio_emitir_presenca_por_registro(p_registro_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_reg public.fabio_registros_aula%rowtype;
  v_aula_reg public.aulas_emusys%rowtype;
  v_ausentes integer[];
  v_ancora integer;
  v_roster_ind integer;
  v_tem_sinal boolean;
  v_res jsonb;
  v_fonte text;
begin
  select * into v_reg from public.fabio_registros_aula where id=p_registro_id and parent_id is null;
  if not found then return jsonb_build_object('aplicado',false,'motivo','registro_nao_encontrado'); end if;
  v_fonte := case when v_reg.modo_entrada='manual' then 'professor_la_teacher' else 'fabio_audio' end;
  select * into v_aula_reg from public.aulas_emusys where id=v_reg.aula_id;
  if not found then
    update public.fabio_registros_aula set campos=coalesce(campos,'{}'::jsonb)||jsonb_build_object(
      'presenca_emitida',true,'presenca_emitida_em',now(),'presenca_aplicado',false,
      'presenca_erro','aula_do_registro_nao_encontrada','presenca_fonte',v_fonte)
     where id=p_registro_id;
    return jsonb_build_object('aula_id',v_reg.aula_id,'aplicado',false,'motivo','aula_do_registro_nao_encontrada');
  end if;
  if v_reg.aluno_id is not null then
    v_ancora := v_reg.aula_id;
    select count(*) into v_roster_ind from public.aula_alunos_emusys where aula_emusys_id=v_ancora and aluno_id is not null;
    if coalesce(v_roster_ind,0) > 1 then
      update public.fabio_registros_aula set campos=coalesce(campos,'{}'::jsonb)||jsonb_build_object(
        'presenca_emitida',true,'presenca_emitida_em',now(),'presenca_aplicado',false,
        'presenca_erro','registro_individual_em_aula_de_turma','presenca_fonte',v_fonte)
       where id=p_registro_id;
      return jsonb_build_object('aula_id',v_ancora,'aplicado',false,'motivo','registro_individual_em_aula_de_turma');
    end if;
    v_tem_sinal := (v_reg.campos->>'presenca') is not null;
    v_ausentes := case when coalesce(v_reg.campos->>'presenca','presente')='ausente'
      then array[v_reg.aluno_id] else '{}'::integer[] end;
  else
    if coalesce(v_aula_reg.tipo,'') = 'turma' then
      v_ancora := v_reg.aula_id;
    else
      select coalesce((select t.id from public.aulas_emusys t where t.tipo='turma'
         and t.unidade_id=v_aula_reg.unidade_id and t.data_hora_inicio=v_aula_reg.data_hora_inicio
         and t.professor_id is not distinct from v_reg.professor_id and coalesce(t.cancelada,false)=false limit 1), v_reg.aula_id)
        into v_ancora;
    end if;
    select coalesce(array_agg(f.aluno_id) filter (
      where coalesce(f.campos->>'presenca','presente')='ausente' and f.aluno_id is not null
    ),'{}'::integer[])
      into v_ausentes from public.fabio_registros_aula f where f.parent_id=p_registro_id;
    v_tem_sinal := exists (
      select 1 from public.fabio_registros_aula f
       where f.parent_id=p_registro_id and (f.campos->>'presenca') is not null
    );
  end if;
  if not coalesce(v_tem_sinal,false) then
    return jsonb_build_object('aula_id',v_ancora,'aplicado',false,'motivo','sem_sinal_de_presenca_no_registro');
  end if;
  begin
    v_res := public.fn_registrar_presencas_core(v_ancora, v_reg.professor_id, v_ausentes, v_fonte, false);
  exception when others then
    v_res := jsonb_build_object('aula_id',v_ancora,'aplicado',false,'erro',sqlerrm);
  end;
  update public.fabio_registros_aula set campos=coalesce(campos,'{}'::jsonb)||jsonb_build_object(
    'presenca_emitida',true,'presenca_emitida_em',now(),
    'presenca_aplicado',coalesce((v_res->>'aplicado')::boolean,false),
    'presenca_erro',v_res->>'erro','presenca_fonte',v_fonte)
   where id=p_registro_id;
  return v_res || jsonb_build_object(
    'ausentes', to_jsonb(coalesce(v_ausentes,'{}'::integer[])),
    'fonte', v_fonte
  );
end
$function$;

create or replace function public.fn_confirmar_registro_core(
  p_professor_id integer,
  p_confirmado_por uuid,
  p_registro_id uuid,
  p_modo text
) returns jsonb
language plpgsql
security definer
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
  v_recibo jsonb := null;
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

  perform public.fn_materializar_presenca_padrao(p_registro_id, p_professor_id);
  select * into v_reg from public.fabio_registros_aula
   where id = p_registro_id and parent_id is null;

  if v_reg.aluno_id is not null then
    v_decl := public.fn_presenca_declarada(v_reg.campos);
    if v_decl = 'nao_informada' then
      v_pend := v_pend || public.fn_pendencia_presenca(v_reg.id, 'raiz', v_reg.aluno_id);
    elsif v_decl = 'ausente' then
      v_puladas := 1;
      update public.fabio_registros_aula
         set status = 'confirmado', confirmado_em = now(), confirmado_por = v_user_id
       where id = p_registro_id;
    else
      v_texto := coalesce(
        public.fn_compor_texto_prontuario(v_reg.campos, v_reg.campos),
        nullif(btrim(v_reg.texto_consolidado), ''));
      if v_texto is null then raise exception 'Registro sem conteudo'; end if;
      v_alvo := public.fn_aula_individual_do_aluno(v_reg.aula_id, v_reg.aluno_id);
      perform public.registrar_aula_fabio(
        p_aula_id => v_alvo,
        p_texto => v_texto,
        p_origem => case
          when v_reg.modo_entrada='manual' then 'texto'
          when v_reg.origem in ('audio','texto') then v_reg.origem
          else 'audio'
        end,
        p_professor_id => v_reg.professor_id,
        p_modo => p_modo
      );
      v_gravadas := 1;
      update public.fabio_registros_aula
         set status = 'gravado_emusys', confirmado_em = now(), confirmado_por = v_user_id
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
        v_pend := v_pend || public.fn_pendencia_presenca(v_fatia.id, 'fatia', v_fatia.aluno_id);
      elsif v_decl = 'ausente' then
        v_puladas := v_puladas + 1;
        update public.fabio_registros_aula
           set status = 'confirmado', confirmado_em = now(), confirmado_por = v_user_id
         where id = v_fatia.id;
      elsif v_fatia.aula_id is null or v_fatia.aluno_id is null or v_texto is null then
        v_pend := v_pend || jsonb_build_object(
          'registro_alvo_id', v_fatia.id,
          'tipo_alvo', 'fatia',
          'fatia_id', v_fatia.id,
          'aluno_id', v_fatia.aluno_id,
          'aluno_nome', (select a.nome from public.alunos a where a.id = v_fatia.aluno_id),
          'campo_obrigatorio', null,
          'valores_permitidos', null,
          'motivo', case
            when v_fatia.aula_id is null then 'sem aula vinculada'
            when v_fatia.aluno_id is null then 'sem aluno vinculado'
            else 'sem conteudo'
          end
        );
      else
        v_alvo := public.fn_aula_individual_do_aluno(v_fatia.aula_id, v_fatia.aluno_id);
        perform public.registrar_aula_fabio(
          p_aula_id => v_alvo,
          p_texto => v_texto,
          p_origem => case
            when v_fatia.modo_entrada='manual' then 'texto'
            when v_fatia.origem in ('audio','texto') then v_fatia.origem
            else 'audio'
          end,
          p_professor_id => v_reg.professor_id,
          p_modo => p_modo
        );
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
         set status = 'gravado_emusys', confirmado_em = now(), confirmado_por = v_user_id
       where id = p_registro_id;
    else
      update public.fabio_registros_aula
         set status = 'confirmado', confirmado_em = now(), confirmado_por = v_user_id
       where id = p_registro_id;
    end if;
  end if;

  v_ganchos := public.fabio_emitir_presenca_por_registro_e_devolutiva(p_registro_id);
  v_recibo := public.fn_enfileirar_registro_recibo(p_registro_id, p_professor_id);

  return jsonb_build_object(
    'registro_id', p_registro_id,
    'modo', p_modo,
    'gravadas', v_gravadas,
    'ausentes_puladas', v_puladas,
    'pendencias', v_pend,
    'presenca', v_ganchos -> 'presenca',
    'devolutivas_enfileiradas', v_ganchos -> 'devolutivas_enfileiradas',
    'recibo_enfileirado', v_recibo
  );
end
$function$;

reset statement_timeout;
reset lock_timeout;
