-- ============================================================================
-- LA TEACHER · MIGRAÇÃO 005 — RPCs DA TELA DE CONFIRMAÇÃO (Sprint 3 · P7)
-- Projeto: ouqwbbermlzqqvtqwlul · Pré-requisito: 001/002 aplicadas
-- Leitura do registro completo (tronco + fatias + contexto da aula),
-- lista de pendentes de confirmação e update guardado de campos/texto.
-- Idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1 · Registro completo: tronco + fatias + contexto da aula (data/hora/turma)
--     Segurança: o professor só lê o próprio (fn_professor_do_usuario).
-- ---------------------------------------------------------------------------
create or replace function public.app_registro_completo(p_registro_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_prof   integer := public.fn_professor_do_usuario();
  v_tronco jsonb;
  v_fatias jsonb;
  v_aula   jsonb;
begin
  if v_prof is null then return jsonb_build_object('erro','sem_professor'); end if;

  select to_jsonb(r) into v_tronco from public.fabio_registros_aula r
   where r.id = p_registro_id and r.parent_id is null and r.professor_id = v_prof;
  if v_tronco is null then return jsonb_build_object('erro','nao_encontrado'); end if;

  select coalesce(jsonb_agg(to_jsonb(r) order by r.criado_em), '[]'::jsonb) into v_fatias
    from public.fabio_registros_aula r where r.parent_id = p_registro_id;

  -- contexto da aula-âncora (cabeçalho da tela + formato da Tese)
  select jsonb_build_object(
           'data_aula', v.data_aula, 'hora', v.horario_inicio_brt,
           'turma', v.turma_nome, 'curso', v.curso_nome, 'tipo', v.aula_tipo)
    into v_aula
    from public.vw_fabio_aulas_contexto v
   where v.aula_local_id = (v_tronco->>'aula_id')::integer
   limit 1;

  return jsonb_build_object('tronco', v_tronco, 'fatias', v_fatias, 'aula', v_aula);
end $$;
revoke all on function public.app_registro_completo(uuid) from public, anon;
grant execute on function public.app_registro_completo(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2 · Registros aguardando confirmação do professor logado
-- ---------------------------------------------------------------------------
create or replace function public.app_registros_pendentes()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_prof integer := public.fn_professor_do_usuario();
begin
  if v_prof is null then return '[]'::jsonb; end if;
  return (select coalesce(jsonb_agg(to_jsonb(r) order by r.criado_em desc), '[]'::jsonb)
          from public.fabio_registros_aula r
          where r.professor_id = v_prof and r.parent_id is null
            and r.status = 'aguardando_confirmacao');
end $$;
revoke all on function public.app_registros_pendentes() from public, anon;
grant execute on function public.app_registros_pendentes() to authenticated;

-- ---------------------------------------------------------------------------
-- 3 · Update guardado de um registro (tronco OU fatia): texto e/ou campos.
--     campos faz MERGE (campos || p_campos); só em rascunho/aguardando.
--     Dono da fatia: professor_id da linha ou, se nulo, o do tronco-pai.
-- ---------------------------------------------------------------------------
create or replace function public.app_atualizar_fatia(
  p_id uuid, p_texto text default null, p_campos jsonb default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_prof      integer := public.fn_professor_do_usuario();
  v_reg       public.fabio_registros_aula%rowtype;
  v_prof_dono integer;
  v_out       jsonb;
begin
  if v_prof is null then raise exception 'Usuário sem professor vinculado'; end if;

  select * into v_reg from public.fabio_registros_aula where id = p_id;
  if not found then raise exception 'Registro % não encontrado', p_id; end if;

  v_prof_dono := v_reg.professor_id;
  if v_prof_dono is null and v_reg.parent_id is not null then
    select professor_id into v_prof_dono
      from public.fabio_registros_aula where id = v_reg.parent_id;
  end if;
  if v_prof_dono is distinct from v_prof then
    raise exception 'Registro não pertence a este professor';
  end if;
  if v_reg.status not in ('rascunho','aguardando_confirmacao') then
    raise exception 'Status % não permite edição', v_reg.status;
  end if;

  update public.fabio_registros_aula
     set texto_consolidado = coalesce(p_texto, texto_consolidado),
         campos = case when p_campos is null then campos else campos || p_campos end
   where id = p_id
   returning to_jsonb(fabio_registros_aula) into v_out;

  return v_out;
end $$;
revoke all on function public.app_atualizar_fatia(uuid,text,jsonb) from public, anon;
grant execute on function public.app_atualizar_fatia(uuid,text,jsonb) to authenticated;

-- ============================================================================
-- Sanidade: select public.app_registros_pendentes(); (como professor de teste)
-- ============================================================================
