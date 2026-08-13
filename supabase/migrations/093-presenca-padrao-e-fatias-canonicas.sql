-- SUPERADA POR: 20260812163000_recibo_so_whatsapp_e_fila_ativa.sql
--
-- A 20260812163000 redefiniu `fabio_criar_registro` DE PROPOSITO. Replayar a
-- 093 sobre o schema de hoje instala a versao antiga e o teste acusa
-- `presencas_antes=1` -- o que PARECE presenca vazando em rascunho, e nao e.
-- Medido em 13/08/2026: o `fabio_criar_registro` vivo NAO referencia
-- `aluno_presenca`, nao ha trigger de presenca em `fabio_registros_aula`, e
-- NENHUMA das 8 funcoes que dao INSERT em `aluno_presenca` e chamada por ele.
--
-- As guardas de ACL que este teste protegia foram resgatadas para
-- `20260813170000_guardas_resgatadas_da_presenca.sql`, com 4/4 mutantes
-- mortos. Marcar SUPERADA sem esse resgate teria desarmado a guarda em
-- silencio.
-- 093 — presença padrão e fatias canônicas.
--
-- O registro continua sendo a fonte do preview. A presença sem declaração só
-- ganha valor no ato de confirmar: nenhum rascunho emite chamada nem presume
-- que a aula ocorreu. A única escrita em aluno_presenca permanece no emissor
-- já existente, que chama o núcleo único da 086/091 e preserva os gêmeos e a
-- proteção contra uma fonte humana forte.

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
  v_alterados jsonb;
begin
  if p_registro_id is null or p_professor_id is null then
    raise exception 'registro_e_professor_obrigatorios';
  end if;

  select * into v_raiz
    from public.fabio_registros_aula
   where id = p_registro_id
     and parent_id is null;
  if not found then
    raise exception 'Registro % nao encontrado', p_registro_id;
  end if;
  if v_raiz.professor_id is distinct from p_professor_id then
    raise exception 'Registro nao pertence a este professor';
  end if;

  with alteradas as (
    update public.fabio_registros_aula f
       set campos = coalesce(f.campos, '{}'::jsonb)
                    || jsonb_build_object('presenca', 'presente'),
           atualizado_em = now()
     where coalesce(f.professor_id, v_raiz.professor_id) = p_professor_id
       and (
         (v_raiz.aluno_id is null and f.parent_id = v_raiz.id)
         or (v_raiz.aluno_id is not null and f.id = v_raiz.id)
       )
       and not (coalesce(f.campos, '{}'::jsonb) ? 'presenca')
    returning f.id
  )
  select coalesce(jsonb_agg(id order by id), '[]'::jsonb)
    into v_alterados
    from alteradas;

  return jsonb_build_object(
    'registro_id', p_registro_id,
    'alterados', v_alterados,
    'quantidade_alterada', jsonb_array_length(v_alterados)
  );
end
$function$;

create or replace function public.fn_remover_campos_comuns_da_fatia(
  p_tronco jsonb,
  p_fatia jsonb
) returns jsonb
language plpgsql
immutable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_saida jsonb := coalesce(p_fatia, '{}'::jsonb);
  v_campo text;
  v_valor_fatia text;
  v_valor_tronco text;
begin
  foreach v_campo in array array[
    'objetivo', 'atividades', 'repertorio', 'dever_casa', 'observacoes'
  ]
  loop
    v_valor_fatia := v_saida ->> v_campo;
    v_valor_tronco := coalesce(p_tronco, '{}'::jsonb) ->> v_campo;
    if v_valor_fatia is null
       or btrim(v_valor_fatia) = ''
       or (
         nullif(btrim(v_valor_tronco), '') is not null
         and lower(btrim(v_valor_fatia)) = lower(btrim(v_valor_tronco))
       ) then
      v_saida := v_saida - v_campo;
    end if;
  end loop;
  return v_saida;
end
$function$;

-- O normalizador de entrada passa a persistir somente a diferença da fatia.
-- A assinatura, a idempotência por áudio e o contrato de origem existentes são
-- preservados; só os campos duplicados deixam de ser gravados.
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
begin
  if v_aula_id is null then raise exception 'aula_id obrigatorio'; end if;
  if v_professor is null then raise exception 'professor_id obrigatorio'; end if;

  -- SECURITY DEFINER: ids em JSON nunca são autoridade. A âncora precisa ser
  -- uma aula ativa do professor declarado, antes de qualquer escrita.
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
    -- A fila tambem e parte da autorizacao do rascunho. Validar antes de
    -- idempotencia impede que um audio de outra relacao revele/reaproveite um
    -- registro e antes de qualquer insert/update impede escrita indevida.
    if not exists (
      select 1
        from public.fabio_fila_audios f
       where f.id = v_audio_id
         and f.professor_id = v_professor
         and f.aula_id = v_ancora.id
         and f.unidade_id = v_unidade
    ) then
      raise exception 'audio_id_invalido';
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
     'aguardando_confirmacao',
     coalesce(p_payload ->> 'origem', 'app'),
     v_audio_id)
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

    -- A relação turma/sessão é resolvida pelo banco. Se o cliente informar
    -- uma aula de fatia, ela deve ser exatamente o alvo canônico; sem id, o
    -- próprio alvo é materializado. Isso preserva aula individual e gêmeos.
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
       'aguardando_confirmacao',
       coalesce(p_payload ->> 'origem', 'app'),
       v_audio_id);
    v_qtd_fatias := v_qtd_fatias + 1;
  end loop;

  if v_audio_id is not null then
    update public.fabio_fila_audios set status = 'normalizado', atualizado_em = now()
     where id = v_audio_id;
  end if;

  return jsonb_build_object('status', 'criado', 'registro_id', v_tronco_id, 'fatias', v_qtd_fatias);
end
$function$;

-- A correção pré-confirmação usa a mesma normalização. Atualizar o tronco
-- também limpa nas fatias o que acabou de se tornar informação comum.
create or replace function public.fn_atualizar_fatia_core(
  p_professor_id integer,
  p_id uuid,
  p_texto text default null::text,
  p_campos jsonb default null::jsonb
) returns jsonb
language plpgsql
security definer
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
     where id = p_id
     returning * into v_reg;

    update public.fabio_registros_aula f
       set campos = public.fn_remover_campos_comuns_da_fatia(v_campos_novos, f.campos),
           texto_consolidado = public.fn_compor_texto_prontuario(
             v_campos_novos,
             public.fn_remover_campos_comuns_da_fatia(v_campos_novos, f.campos)
           )
     where f.parent_id = p_id;
  else
    select * into v_tronco from public.fabio_registros_aula where id = v_reg.parent_id;
    if not found then raise exception 'Tronco do registro % nao encontrado', p_id; end if;
    v_campos_novos := public.fn_remover_campos_comuns_da_fatia(
      v_tronco.campos,
      v_campos_novos
    );
    update public.fabio_registros_aula
       set campos = v_campos_novos,
           texto_consolidado = public.fn_compor_texto_prontuario(
             v_tronco.campos, v_campos_novos)
     where id = p_id
     returning * into v_reg;
  end if;

  select to_jsonb(v_reg) into v_out;
  return v_out;
end
$function$;

-- A confirmação é o único ponto que transforma presença não declarada em
-- presente. O emissor existente continua sendo o único escritor de chamada.
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

-- Defesa contra legado: fatias antigas continuam no banco para auditoria, mas
-- o histórico não repete repertório individual quando ele é igual ao tronco.
create or replace function public.app_historico_turma(
  p_turma_nome text,
  p_limite integer default 15
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_prof integer := public.fn_professor_do_usuario();
  v_res jsonb;
begin
  if v_prof is null then raise exception 'sem_professor_vinculado' using errcode = '42501'; end if;

  if not exists (
    select 1 from public.aulas_emusys ae
     where ae.turma_nome = p_turma_nome and ae.professor_id = v_prof
  ) then
    raise exception 'turma_nao_encontrada_ou_nao_e_sua' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'turma_nome', p_turma_nome,
    'curso', (
      select ae.curso_nome from public.aulas_emusys ae
       where ae.turma_nome = p_turma_nome and ae.professor_id = v_prof
       order by ae.data_aula desc limit 1
    ),
    'alunos_atuais', coalesce((
      select jsonb_agg(distinct a.nome order by a.nome)
        from public.aulas_emusys ae
        join public.aula_alunos_emusys r on r.aula_emusys_id = ae.id
        join public.alunos a on a.id = r.aluno_id
       where ae.turma_nome = p_turma_nome and ae.professor_id = v_prof
         and ae.data_aula >= now()::date - 14
    ), '[]'::jsonb),
    'sessoes', coalesce((
      select jsonb_agg(u.x order by u.data_aula desc)
        from (
          select d.x, d.data_aula
            from (
              select distinct on (ae.data_aula)
                     ae.data_aula,
                     jsonb_build_object(
                       'data', ae.data_aula,
                       'objetivo', nullif(btrim(coalesce(reg.campos ->> 'objetivo', '')), ''),
                       'conteudo', nullif(btrim(coalesce(reg.campos ->> 'atividades', '')), ''),
                       'dever_casa', nullif(btrim(coalesce(reg.campos ->> 'dever_casa', '')), ''),
                       'repertorio_turma', nullif(btrim(coalesce(reg.campos ->> 'repertorio', '')), ''),
                       'repertorio_por_aluno', coalesce((
                         select jsonb_agg(jsonb_build_object(
                                  'aluno', a.nome,
                                  'primeiro_nome', split_part(btrim(a.nome), ' ', 1),
                                  'repertorio', fat.campos ->> 'repertorio'
                                ) order by a.nome)
                           from public.fabio_registros_aula fat
                           join public.alunos a on a.id = fat.aluno_id
                          where fat.parent_id = reg.id
                            and nullif(btrim(coalesce(fat.campos ->> 'repertorio', '')), '') is not null
                            and lower(btrim(fat.campos ->> 'repertorio'))
                                is distinct from lower(btrim(reg.campos ->> 'repertorio'))
                       ), '[]'::jsonb),
                       'origem', case when reg.id is not null then 'fabio' else 'emusys' end,
                       'texto_legado', case when reg.id is null
                                             then nullif(btrim(coalesce(ae.anotacoes, '')), '') end
                     ) as x
                from public.aulas_emusys ae
                left join public.fabio_registros_aula reg
                       on reg.aula_id = ae.id and reg.parent_id is null
               where ae.turma_nome = p_turma_nome and ae.professor_id = v_prof
                 and coalesce(ae.cancelada, false) = false
                 and (
                   reg.id is not null
                   or nullif(btrim(coalesce(ae.anotacoes, '')), '') is not null
                 )
               order by ae.data_aula desc, (reg.id is null), ae.id
            ) d
           order by d.data_aula desc
           limit greatest(coalesce(p_limite, 15), 1)
        ) u
    ), '[]'::jsonb)
  ) into v_res;

  return v_res;
end
$function$;

revoke all on function public.fn_materializar_presenca_padrao(uuid, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.fn_remover_campos_comuns_da_fatia(jsonb, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.fabio_criar_registro(jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.fabio_criar_registro(jsonb) to service_role;
