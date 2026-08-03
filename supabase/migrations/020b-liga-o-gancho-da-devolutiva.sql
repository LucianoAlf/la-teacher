-- 020b-liga-o-gancho-da-devolutiva.sql
--
-- A 020 criou fabio_emitir_presenca_por_registro_e_devolutiva e NINGUÉM a
-- chamava: app_confirmar_registro continuava chamando só a de presença. A fila
-- da devolutiva nasceria vazia pra sempre — e sem erro nenhum pra avisar, que é
-- o pior jeito de estar quebrado.
--
-- Achado conferindo o que a 020 realmente tinha fiado depois de aplicar.
--
-- O gancho continua NÃO-FATAL (o begin/exception já estava lá): confirmar
-- registro nunca pode falhar porque a devolutiva falhou.

create or replace function public.app_confirmar_registro(p_registro_id uuid, p_modo text default 'novo')
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_prof integer := public.fn_professor_do_usuario(); v_reg public.fabio_registros_aula%rowtype;
  v_fatia record; v_user_id integer; v_gravadas integer := 0; v_puladas integer := 0;
  v_pend jsonb := '[]'::jsonb; v_alvo integer; v_texto text; v_ganchos jsonb;
  v_decl text;
begin
  if v_prof is null then raise exception 'Usuário sem professor vinculado'; end if;
  if p_modo not in ('novo','substituir','complementar') then raise exception 'Modo inválido: %', p_modo; end if;
  select u.id into v_user_id from public.usuarios u where u.auth_user_id = auth.uid();
  select * into v_reg from public.fabio_registros_aula where id=p_registro_id and parent_id is null;
  if not found then raise exception 'Registro % não encontrado', p_registro_id; end if;
  if v_reg.professor_id is distinct from v_prof then raise exception 'Registro não pertence a este professor'; end if;
  if v_reg.status not in ('rascunho','aguardando_confirmacao') then raise exception 'Status % não permite confirmação', v_reg.status; end if;

  if v_reg.aluno_id is not null then
    v_decl := public.fn_presenca_declarada(v_reg.campos);
    if v_decl = 'nao_informada' then
      v_pend := v_pend || public.fn_pendencia_presenca(v_reg.id, 'raiz', v_reg.aluno_id);
    elsif v_decl = 'ausente' then
      v_puladas := 1;
      update public.fabio_registros_aula
         set status='confirmado', confirmado_em=now(), confirmado_por=v_user_id
       where id=p_registro_id;
    else
      v_texto := coalesce(public.fn_compor_texto_prontuario(v_reg.campos, v_reg.campos), nullif(btrim(v_reg.texto_consolidado),''));
      if v_texto is null then raise exception 'Registro sem conteúdo'; end if;
      v_alvo := public.fn_aula_individual_do_aluno(v_reg.aula_id, v_reg.aluno_id);
      perform public.registrar_aula_fabio(p_aula_id=>v_alvo, p_texto=>v_texto,
        p_origem=>case when v_reg.origem in ('audio','texto') then v_reg.origem else 'audio' end,
        p_professor_id=>v_reg.professor_id, p_modo=>p_modo);
      v_gravadas := 1;
      update public.fabio_registros_aula set status='gravado_emusys', confirmado_em=now(), confirmado_por=v_user_id where id=p_registro_id;
    end if;
  else
    for v_fatia in select * from public.fabio_registros_aula where parent_id=p_registro_id loop
      v_texto := coalesce(public.fn_compor_texto_prontuario(v_reg.campos, v_fatia.campos), nullif(btrim(v_fatia.texto_consolidado),''));
      v_decl := public.fn_presenca_declarada(v_fatia.campos);
      if v_decl = 'nao_informada' then
        v_pend := v_pend || public.fn_pendencia_presenca(v_fatia.id, 'fatia', v_fatia.aluno_id);
      elsif v_decl = 'ausente' then
        v_puladas := v_puladas + 1;
        update public.fabio_registros_aula set status='confirmado', confirmado_em=now(), confirmado_por=v_user_id where id=v_fatia.id;
      elsif v_fatia.aula_id is null or v_fatia.aluno_id is null or v_texto is null then
        v_pend := v_pend || jsonb_build_object(
          'registro_alvo_id', v_fatia.id, 'tipo_alvo', 'fatia', 'fatia_id', v_fatia.id,
          'aluno_id', v_fatia.aluno_id,
          'aluno_nome', (select a.nome from public.alunos a where a.id = v_fatia.aluno_id),
          'campo_obrigatorio', null, 'valores_permitidos', null,
          'motivo', case when v_fatia.aula_id is null then 'sem aula vinculada'
                         when v_fatia.aluno_id is null then 'sem aluno vinculado'
                         else 'sem conteúdo' end);
      else
        v_alvo := public.fn_aula_individual_do_aluno(v_fatia.aula_id, v_fatia.aluno_id);
        perform public.registrar_aula_fabio(p_aula_id=>v_alvo, p_texto=>v_texto,
          p_origem=>case when v_fatia.origem in ('audio','texto') then v_fatia.origem else 'audio' end,
          p_professor_id=>v_reg.professor_id, p_modo=>p_modo);
        v_gravadas := v_gravadas + 1;
        update public.fabio_registros_aula set status='gravado_emusys', confirmado_em=now(), confirmado_por=v_user_id,
          aula_id=v_alvo, campos=campos||jsonb_build_object('aula_alvo_resolvida',v_alvo) where id=v_fatia.id;
      end if;
    end loop;

    if v_gravadas = 0 and v_puladas = 0 and jsonb_array_length(v_pend) = 0 then
      raise exception 'Nada gravável neste registro. Pendências: %', v_pend::text;
    end if;

    if jsonb_array_length(v_pend) = 0 then
      update public.fabio_registros_aula set status='gravado_emusys',
        confirmado_em=now(), confirmado_por=v_user_id where id=p_registro_id;
    else
      update public.fabio_registros_aula set status='confirmado',
        confirmado_em=now(), confirmado_por=v_user_id where id=p_registro_id;
    end if;
  end if;

  -- <<< 020b: presença E devolutiva, as duas não-fatais.
  v_ganchos := public.fabio_emitir_presenca_por_registro_e_devolutiva(p_registro_id);

  return jsonb_build_object('registro_id',p_registro_id,'modo',p_modo,'gravadas',v_gravadas,
    'ausentes_puladas',v_puladas,'pendencias',v_pend,
    'presenca', v_ganchos->'presenca',
    'devolutivas_enfileiradas', v_ganchos->'devolutivas_enfileiradas');
end $function$;
