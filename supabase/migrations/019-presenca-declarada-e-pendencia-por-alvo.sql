-- 019-presenca-declarada-e-pendencia-por-alvo.sql
--
-- Conserta a ORIGEM da presença em app_confirmar_registro, que é pré-requisito
-- da devolutiva (spec §2.6 a §2.8). Dois defeitos, os dois vivos hoje:
--
-- a) O ramo da aula 1:1 NÃO OLHA PRESENÇA. Manda pro prontuário e marca
--    gravado_emusys mesmo com o aluno ausente. Uma aula que não aconteceu vira
--    registro pedagógico. (O ramo de turma já pulava o ausente.)
--
-- b) `coalesce(campos->>'presenca','presente')` trata ausência de dado como
--    presença afirmada. E o dado é duro: 31 de 31 registros do sistema nunca
--    tiveram a chave `presenca`. Todo "presente" que esse sistema já afirmou
--    saiu do coalesce, nenhum de evidência.
--
--    É a mesma família do problema que a gente matou na presença: lá
--    "não-marcado" virava falta fantasma, aqui "não-informado" vira presença
--    fantasma. Mesma raiz — ausência de dado lida como afirmação.
--
-- ⚠️ COMPATIBILIDADE COM O APP QUE ESTÁ NO AR
--    A tela de Confirmar lê `pendencias[].fatia_id`. O contrato novo é por
--    alvo (registro_alvo_id / tipo_alvo / campo_obrigatorio /
--    valores_permitidos), mas cada item continua trazendo `fatia_id` com o
--    mesmo valor. Assim o app atual não quebra entre esta migration e o deploy
--    do app novo — mesma disciplina de corte da 018.
--
-- ⚠️ SEQUÊNCIA
--    Enquanto o app não perguntar a presença, registro sem a chave vira
--    PENDÊNCIA em vez de gravar errado. É barulhento de propósito: o professor
--    vê o que falta em vez de confirmar uma afirmação que ninguém apurou.

-- =====================================================================================
-- 1) Presença declarada: fonte única da leitura. Nada de coalesce espalhado.
-- =====================================================================================
create or replace function public.fn_presenca_declarada(p_campos jsonb)
returns text
language sql immutable parallel safe
as $function$
  -- 'presente' | 'ausente' | 'nao_informada'
  -- Valor estranho também é 'nao_informada': melhor perguntar que adivinhar.
  select case
    when p_campos->>'presenca' = 'presente' then 'presente'
    when p_campos->>'presenca' = 'ausente'  then 'ausente'
    else 'nao_informada'
  end
$function$;

comment on function public.fn_presenca_declarada is
  'Presença como AFIRMAÇÃO. Chave faltando ou valor estranho => nao_informada, nunca presente (migration 019).';

-- =====================================================================================
-- 2) app_confirmar_registro — corpo atual com as mudanças marcadas  -- <<< 019
-- =====================================================================================
create or replace function public.app_confirmar_registro(p_registro_id uuid, p_modo text default 'novo')
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_prof integer := public.fn_professor_do_usuario(); v_reg public.fabio_registros_aula%rowtype;
  v_fatia record; v_user_id integer; v_gravadas integer := 0; v_puladas integer := 0;
  v_pend jsonb := '[]'::jsonb; v_alvo integer; v_texto text; v_presenca jsonb;
  v_decl text;                                                        -- <<< 019
begin
  if v_prof is null then raise exception 'Usuário sem professor vinculado'; end if;
  if p_modo not in ('novo','substituir','complementar') then raise exception 'Modo inválido: %', p_modo; end if;
  select u.id into v_user_id from public.usuarios u where u.auth_user_id = auth.uid();
  select * into v_reg from public.fabio_registros_aula where id=p_registro_id and parent_id is null;
  if not found then raise exception 'Registro % não encontrado', p_registro_id; end if;
  if v_reg.professor_id is distinct from v_prof then raise exception 'Registro não pertence a este professor'; end if;
  if v_reg.status not in ('rascunho','aguardando_confirmacao') then raise exception 'Status % não permite confirmação', v_reg.status; end if;

  if v_reg.aluno_id is not null then
    -- ================= AULA INDIVIDUAL (raiz com aluno, sem fatias) =================
    v_decl := public.fn_presenca_declarada(v_reg.campos);             -- <<< 019
    if v_decl = 'nao_informada' then                                  -- <<< 019
      -- Antes: nem consultava presença. Agora vira pendência respondível em vez
      -- de gravar uma aula que talvez não tenha acontecido.
      v_pend := v_pend || public.fn_pendencia_presenca(v_reg.id, 'raiz', v_reg.aluno_id);
    elsif v_decl = 'ausente' then                                     -- <<< 019
      -- Antes: gravava no prontuário do mesmo jeito. Agora pula, igual à turma.
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
    -- ================= TURMA (tronco + fatias) =================
    for v_fatia in select * from public.fabio_registros_aula where parent_id=p_registro_id loop
      v_texto := coalesce(public.fn_compor_texto_prontuario(v_reg.campos, v_fatia.campos), nullif(btrim(v_fatia.texto_consolidado),''));
      v_decl := public.fn_presenca_declarada(v_fatia.campos);         -- <<< 019
      if v_decl = 'nao_informada' then                                -- <<< 019
        -- Antes: coalesce dizia 'presente' e gravava. Agora pergunta.
        v_pend := v_pend || public.fn_pendencia_presenca(v_fatia.id, 'fatia', v_fatia.aluno_id);
      elsif v_decl = 'ausente' then
        v_puladas := v_puladas + 1;
        update public.fabio_registros_aula set status='confirmado', confirmado_em=now(), confirmado_por=v_user_id where id=v_fatia.id;
      elsif v_fatia.aula_id is null or v_fatia.aluno_id is null or v_texto is null then
        v_pend := v_pend || jsonb_build_object(
          'registro_alvo_id', v_fatia.id, 'tipo_alvo', 'fatia',
          'fatia_id', v_fatia.id,                                     -- <<< 019 (compat)
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

    -- <<< 019: "nada gravável" deixou de ser exceção quando há pendência. Antes,
    -- turma inteira sem presença estourava e o professor não via o que fazer.
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

  begin
    v_presenca := public.fabio_emitir_presenca_por_registro(p_registro_id);
  exception when others then v_presenca := jsonb_build_object('aplicado',false,'erro',sqlerrm); end;

  return jsonb_build_object('registro_id',p_registro_id,'modo',p_modo,'gravadas',v_gravadas,
    'ausentes_puladas',v_puladas,'pendencias',v_pend,'presenca',v_presenca);
end $function$;

-- =====================================================================================
-- 3) O item de pendência de presença, num formato genérico por ALVO.
--    Serve fatia E raiz 1:1 — a tela não precisa procurar na lista de fatias.
--    `campo_obrigatorio` + `valores_permitidos` deixam a tela desenhar os botões
--    a partir do contrato; amanhã outro campo entra sem redesenhar nada.
-- =====================================================================================
create or replace function public.fn_pendencia_presenca(
  p_registro_alvo_id uuid, p_tipo_alvo text, p_aluno_id integer)
returns jsonb
language sql stable
as $function$
  select jsonb_build_array(jsonb_build_object(
    'registro_alvo_id',  p_registro_alvo_id,
    'tipo_alvo',         p_tipo_alvo,
    -- compat com o app que está no ar; sai quando o app novo subir
    'fatia_id',          p_registro_alvo_id,
    'aluno_id',          p_aluno_id,
    'aluno_nome',        (select a.nome from public.alunos a where a.id = p_aluno_id),
    'campo_obrigatorio', 'presenca',
    'valores_permitidos', jsonb_build_array('presente','ausente'),
    'motivo',            'presença não informada'))
$function$;

-- =====================================================================================
-- 4) A resposta do professor. Sem isto a pendência é beco sem saída — foi
--    exatamente a crítica da auditoria: a tela listava o problema e não dava ação.
-- =====================================================================================
create or replace function public.app_responder_presenca(
  p_registro_alvo_id uuid, p_presenca text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_prof integer := public.fn_professor_do_usuario();
  v_reg public.fabio_registros_aula%rowtype;
begin
  if v_prof is null then raise exception 'Usuário sem professor vinculado'; end if;
  if p_presenca not in ('presente','ausente') then
    raise exception 'Presença inválida: % (use presente ou ausente)', p_presenca;
  end if;

  select * into v_reg from public.fabio_registros_aula where id = p_registro_alvo_id;
  if not found then raise exception 'Registro % não encontrado', p_registro_alvo_id; end if;
  if v_reg.professor_id is distinct from v_prof then
    raise exception 'Registro não pertence a este professor';
  end if;
  if v_reg.status not in ('rascunho','aguardando_confirmacao','confirmado') then
    raise exception 'Status % não aceita mais resposta de presença', v_reg.status;
  end if;

  update public.fabio_registros_aula
     set campos = coalesce(campos,'{}'::jsonb) || jsonb_build_object('presenca', p_presenca),
         atualizado_em = now()
   where id = p_registro_alvo_id;

  return jsonb_build_object('ok', true, 'registro_alvo_id', p_registro_alvo_id,
                            'presenca', p_presenca);
end $function$;

comment on function public.app_responder_presenca is
  'Grava a presença que o professor informou numa pendência, para ele reconfirmar o registro (migration 019).';

-- =====================================================================================
-- 5) Grants. A ACL das funções recriadas é conferida INTEIRA — a 018b nasceu de
--    eu ter devolvido os grants certos e não ter percebido quem mais entrou.
-- =====================================================================================
grant execute on function public.app_responder_presenca(uuid, text) to authenticated;
grant execute on function public.fn_presenca_declarada(jsonb) to authenticated, service_role, fabio_agent;
