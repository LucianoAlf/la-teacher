-- ============================================================================
-- LA TEACHER · MIGRAÇÃO 006 — FIX: origem canal × origem de conteúdo (P7)
-- Bug de integração: fabio_registros_aula.origem é o CANAL de entrada
-- ('app' | 'whatsapp', constraint da 001), mas registrar_aula_fabio (fundação
-- pré-existente) valida a ORIGEM DO CONTEÚDO ('audio' | 'texto').
-- app_confirmar_registro repassava o canal cru → "Origem inválida: app".
-- Correção: traduzir no ponto de chamada (canal do motor = conteúdo de áudio).
-- Recria a função como implantada (assinatura com p_modo), só com o mapa.
-- Idempotente.
-- ============================================================================

create or replace function public.app_confirmar_registro(p_registro_id uuid, p_modo text default 'novo')
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_prof     integer := public.fn_professor_do_usuario();
  v_reg      public.fabio_registros_aula%rowtype;
  v_fatia    record;
  v_user_id  integer;
  v_gravadas integer := 0;
  v_puladas  integer := 0;
  v_pend     jsonb := '[]'::jsonb;
begin
  if v_prof is null then raise exception 'Usuário sem professor vinculado'; end if;
  if p_modo not in ('novo','substituir','complementar') then
    raise exception 'Modo inválido: % (use novo, substituir ou complementar)', p_modo;
  end if;
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
    -- aula individual
    if coalesce(btrim(v_reg.texto_consolidado),'') = '' then
      raise exception 'Registro sem texto consolidado';
    end if;
    perform public.registrar_aula_fabio(
      p_aula_id => v_reg.aula_id, p_texto => v_reg.texto_consolidado,
      -- canal ('app'/'whatsapp') vira origem de conteúdo: o motor é de voz
      p_origem => case when v_reg.origem in ('audio','texto') then v_reg.origem else 'audio' end,
      p_professor_id => v_reg.professor_id, p_modo => p_modo);
    v_gravadas := 1;
    update public.fabio_registros_aula
       set status='gravado_emusys', confirmado_em=now(), confirmado_por=v_user_id
     where id = p_registro_id;
  else
    -- turma: tronco + fatias, grava na aula de CADA aluno
    for v_fatia in
      select * from public.fabio_registros_aula where parent_id = p_registro_id
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
          'motivo', case when v_fatia.aula_id is null then 'sem aula vinculada' else 'sem texto' end);
      else
        perform public.registrar_aula_fabio(
          p_aula_id => v_fatia.aula_id, p_texto => v_fatia.texto_consolidado,
          p_origem => case when v_fatia.origem in ('audio','texto') then v_fatia.origem else 'audio' end,
          p_professor_id => v_reg.professor_id, p_modo => p_modo);
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
       set status = case when jsonb_array_length(v_pend) = 0 then 'gravado_emusys' else 'confirmado' end,
           confirmado_em = now(), confirmado_por = v_user_id
     where id = p_registro_id;
  end if;

  return jsonb_build_object('registro_id', p_registro_id, 'modo', p_modo,
                            'gravadas', v_gravadas, 'ausentes_puladas', v_puladas,
                            'pendencias', v_pend);
end $$;
revoke all on function public.app_confirmar_registro(uuid,text) from public, anon;
grant execute on function public.app_confirmar_registro(uuid,text) to authenticated;
