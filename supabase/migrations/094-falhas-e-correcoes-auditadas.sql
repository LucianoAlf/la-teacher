-- 094 - falhas terminais tipadas e correcoes finais auditadas.
--
-- A fila usa o par status/erro_tipo, nunca o texto de erro, para decidir retry.
-- As correcoes sao portas de service_role: atualizam somente o alvo do professor,
-- deixam antes/depois auditavel e nao criam notificacao ou envio a familia.

alter table public.fabio_fila_audios
  add column if not exists erro_tipo text not null default 'transitorio';

alter table public.fabio_fila_audios
  drop constraint if exists fabio_fila_audios_status_check;
alter table public.fabio_fila_audios
  add constraint fabio_fila_audios_status_check
  check (status in ('pendente', 'transcrevendo', 'transcrito', 'normalizado', 'erro', 'erro_terminal'));

alter table public.fabio_fila_audios
  drop constraint if exists fabio_fila_audios_erro_tipo_check;
alter table public.fabio_fila_audios
  add constraint fabio_fila_audios_erro_tipo_check
  check (
    (status = 'erro_terminal' and erro_tipo = 'semantico_terminal')
    or (status <> 'erro_terminal' and erro_tipo = 'transitorio')
  );

create or replace function public.fn_fabio_retry_fila()
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  r record;
  n integer := 0;
begin
  for r in
    select f.id
      from public.fabio_fila_audios f
     where f.status in ('pendente', 'erro')
       and f.erro_tipo = 'transitorio'
       and f.status <> 'erro_terminal'
       and f.criado_em > now() - interval '3 days'
       and f.atualizado_em < now() - (least(greatest(f.tentativas, 1), 12) * interval '5 minutes')
     order by f.atualizado_em
     limit 10
  loop
    update public.fabio_fila_audios
       set tentativas = tentativas + 1,
           atualizado_em = now()
     where id = r.id;
    perform public.fn_fabio_chama_edge(r.id);
    n := n + 1;
  end loop;
  return n;
end
$function$;

revoke execute on function public.fn_fabio_retry_fila()
  from public, anon, authenticated;
grant execute on function public.fn_fabio_retry_fila() to service_role;

create or replace function public.fabio_marcar_audio_erro_terminal(
  p_audio_id uuid,
  p_codigo text,
  p_detalhe text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_audio public.fabio_fila_audios%rowtype;
  v_detalhe text;
begin
  if p_codigo not in ('sem_conteudo_pedagogico', 'transcricao_incompativel') then
    raise exception 'codigo_terminal_invalido';
  end if;

  select * into v_audio
    from public.fabio_fila_audios
   where id = p_audio_id
   for update;
  if not found then
    raise exception 'audio_nao_encontrado';
  end if;
  if v_audio.status = 'erro_terminal' then
    return jsonb_build_object(
      'audio_id', v_audio.id,
      'status', v_audio.status,
      'erro_tipo', v_audio.erro_tipo,
      'codigo', p_codigo
    );
  end if;
  if v_audio.status not in ('pendente', 'transcrevendo', 'transcrito', 'erro') then
    raise exception 'audio_status_nao_terminalizavel';
  end if;

  v_detalhe := nullif(btrim(regexp_replace(coalesce(p_detalhe, ''), '\\s+', ' ', 'g')), '');
  update public.fabio_fila_audios
     set status = 'erro_terminal',
         erro_tipo = 'semantico_terminal',
         erro = left(
           p_codigo || coalesce(': ' || v_detalhe, ''),
           360
         ),
         atualizado_em = now()
   where id = v_audio.id;

  return jsonb_build_object(
    'audio_id', v_audio.id,
    'status', 'erro_terminal',
    'erro_tipo', 'semantico_terminal',
    'codigo', p_codigo
  );
end
$function$;

-- A 093 define esta porta. Recriamos somente para fechar a janela entre um
-- callback terminal e a normalizacao tardia, sem alterar o arquivo 093.
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
    select f.status, f.erro_tipo
      into v_audio_status, v_audio_erro_tipo
      from public.fabio_fila_audios f
     where f.id = v_audio_id
       and f.professor_id = v_professor
       and f.aula_id = v_ancora.id
       and f.unidade_id = v_unidade
     for update;
    if not found then
      raise exception 'audio_id_invalido';
    end if;
    -- 094-GUARDA-AUDIO-TERMINAL-INICIO
    if v_audio_status = 'erro_terminal'
       or v_audio_erro_tipo = 'semantico_terminal' then
      raise exception 'audio_terminal_nao_normalizavel';
    end if;
    -- 094-GUARDA-AUDIO-TERMINAL-FIM
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
    update public.fabio_fila_audios
       set status = 'normalizado', atualizado_em = now()
     where id = v_audio_id;
  end if;

  return jsonb_build_object('status', 'criado', 'registro_id', v_tronco_id, 'fatias', v_qtd_fatias);
end
$function$;

create table public.fabio_registro_correcoes (
  id uuid primary key default gen_random_uuid(),
  registro_id uuid not null references public.fabio_registros_aula(id),
  professor_id integer not null references public.professores(id),
  autor_usuario_id integer not null references public.usuarios(id),
  canal text not null check (canal in ('app', 'whatsapp')),
  antes jsonb not null,
  depois jsonb not null,
  motivo text not null,
  criado_em timestamptz not null default now()
);

create table public.fabio_devolutiva_edicoes (
  id uuid primary key default gen_random_uuid(),
  devolutiva_id uuid not null references public.fabio_devolutivas(id),
  professor_id integer not null references public.professores(id),
  autor_usuario_id integer not null references public.usuarios(id),
  canal text not null check (canal in ('app', 'whatsapp')),
  antes jsonb not null,
  depois jsonb not null,
  motivo text not null,
  criado_em timestamptz not null default now()
);

-- Chave de acao obrigatoria para as escritas finais. Para WhatsApp ela e o
-- wa_message_id da mensagem humana; para app, a chave duravel da acao. A
-- unicidade por tipo impede que o mesmo replay repita uma correcao, sem
-- confundir uma correcao de registro com uma edicao de devolutiva.
create table public.fabio_correcoes_acoes (
  id uuid primary key default gen_random_uuid(),
  tipo text not null check (tipo in ('registro_confirmado', 'devolutiva_rascunho')),
  acao_id text not null check (nullif(btrim(acao_id), '') is not null),
  professor_id integer not null references public.professores(id),
  alvo_id uuid not null,
  canal text not null check (canal in ('app', 'whatsapp')),
  requisicao jsonb not null,
  resultado jsonb,
  criado_em timestamptz not null default now(),
  concluida_em timestamptz,
  constraint fabio_correcoes_acoes_tipo_acao_id_key unique (tipo, acao_id)
);

alter table public.fabio_registro_correcoes enable row level security;
alter table public.fabio_devolutiva_edicoes enable row level security;
alter table public.fabio_correcoes_acoes enable row level security;
alter table public.fabio_registro_correcoes force row level security;
alter table public.fabio_devolutiva_edicoes force row level security;
alter table public.fabio_correcoes_acoes force row level security;
revoke all on table public.fabio_registro_correcoes, public.fabio_devolutiva_edicoes,
  public.fabio_correcoes_acoes
  from public, anon, authenticated;

-- API incompativel: o bridge deve passar p_acao_id; nao ha sobrecarga sem
-- chave, nem valor default, para que replays nunca contornem o ledger.
drop function if exists public.fabio_corrigir_registro_confirmado(integer, uuid, jsonb, text, text);
create or replace function public.fabio_corrigir_registro_confirmado(
  p_professor_id integer,
  p_registro_id uuid,
  p_campos jsonb,
  p_motivo text,
  p_canal text,
  p_acao_id text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_registro public.fabio_registros_aula%rowtype;
  v_tronco public.fabio_registros_aula%rowtype;
  v_autor_usuario_id integer;
  v_campos_corrigidos jsonb;
  v_texto text;
  v_observacoes text;
  v_antes jsonb;
  v_depois jsonb;
  v_acao public.fabio_correcoes_acoes%rowtype;
  v_chave_acao text;
  v_requisicao jsonb;
  v_resultado jsonb;
begin
  if p_professor_id is null then
    raise exception 'sem_professor_vinculado';
  end if;
  if p_canal is null or p_canal not in ('app', 'whatsapp') then
    raise exception 'canal_correcao_invalido';
  end if;
  if jsonb_typeof(p_campos) <> 'object' or p_campos = '{}'::jsonb then
    raise exception 'campos_correcao_invalidos';
  end if;
  if exists (
    select 1
      from jsonb_object_keys(p_campos) as chave(nome)
     where chave.nome not in ('objetivo', 'atividades', 'repertorio', 'dever_casa', 'observacoes', 'progresso')
  ) then
    raise exception 'campo_correcao_nao_permitido';
  end if;
  if nullif(btrim(p_motivo), '') is null then
    raise exception 'motivo_correcao_obrigatorio';
  end if;
  v_chave_acao := nullif(btrim(p_acao_id), '');
  if v_chave_acao is null then
    raise exception 'acao_id_obrigatorio';
  end if;
  v_requisicao := jsonb_build_object(
    'professor_id', p_professor_id,
    'alvo_id', p_registro_id,
    'canal', p_canal,
    'campos', p_campos,
    'motivo', left(btrim(p_motivo), 500)
  );

  begin
    insert into public.fabio_correcoes_acoes(
      tipo, acao_id, professor_id, alvo_id, canal, requisicao
    ) values (
      'registro_confirmado', v_chave_acao, p_professor_id,
      p_registro_id, p_canal, v_requisicao
    ) returning * into v_acao;
  -- 094-REPLAY-REGISTRO-CONFLITO-INICIO
  exception when unique_violation then
    select * into v_acao
      from public.fabio_correcoes_acoes
     where tipo = 'registro_confirmado'
       and acao_id = v_chave_acao;
    if not found then
      raise exception 'acao_correcao_concorrente';
    end if;
    if v_acao.professor_id is distinct from p_professor_id
       or v_acao.alvo_id is distinct from p_registro_id
       or v_acao.canal is distinct from p_canal
       or v_acao.requisicao is distinct from v_requisicao then
      raise exception 'acao_id_reutilizada_para_outra_correcao';
    end if;
    if v_acao.resultado is null then
      raise exception 'acao_correcao_sem_resultado';
    end if;
    return v_acao.resultado;
  -- 094-REPLAY-REGISTRO-CONFLITO-FIM
  end;

  select * into v_registro
    from public.fabio_registros_aula
   where id = p_registro_id
   for update;
  if not found or v_registro.professor_id is distinct from p_professor_id then
    raise exception 'registro_nao_pertence_ao_professor';
  end if;
  if v_registro.status not in ('confirmado', 'gravado_emusys') then
    raise exception 'registro_status_nao_corrigivel';
  end if;
  if v_registro.aluno_id is null then
    raise exception 'registro_correcao_exige_alvo_individual';
  end if;

  select p.usuario_id into v_autor_usuario_id
    from public.professores p
   where p.id = p_professor_id;
  if v_autor_usuario_id is null then
    raise exception 'autor_usuario_nao_encontrado';
  end if;

  v_campos_corrigidos := coalesce(v_registro.campos, '{}'::jsonb) || p_campos;
  if v_registro.parent_id is not null then
    select * into v_tronco
      from public.fabio_registros_aula
     where id = v_registro.parent_id;
    if not found then
      raise exception 'tronco_do_registro_nao_encontrado';
    end if;
    v_campos_corrigidos := public.fn_remover_campos_comuns_da_fatia(
      v_tronco.campos,
      v_campos_corrigidos
    );
    v_texto := public.fn_compor_texto_prontuario(v_tronco.campos, v_campos_corrigidos);
  else
    v_texto := public.fn_compor_texto_prontuario(v_campos_corrigidos, v_campos_corrigidos);
  end if;
  -- O compositor historico nao projeta a chave canonica plural `observacoes`.
  -- A correcao final conserva esse campo no prontuario sem alterar o contrato
  -- do compositor compartilhado nem qualquer fluxo de presenca/devolutiva.
  v_observacoes := nullif(btrim(v_campos_corrigidos ->> 'observacoes'), '');
  v_texto := concat_ws(E'\n', nullif(btrim(v_texto), ''),
    case when v_observacoes is not null then 'Observacoes: ' || v_observacoes end);
  if nullif(btrim(v_texto), '') is null then
    raise exception 'registro_sem_conteudo_corrigivel';
  end if;

  v_antes := to_jsonb(v_registro);
  update public.fabio_registros_aula
     set campos = v_campos_corrigidos,
         texto_consolidado = v_texto,
         atualizado_em = now()
   where id = v_registro.id
   returning * into v_registro;

  perform public.registrar_aula_fabio(
    p_aula_id => v_registro.aula_id,
    p_texto => v_registro.texto_consolidado,
    p_origem => case when v_registro.origem in ('audio', 'texto') then v_registro.origem else 'audio' end,
    p_professor_id => p_professor_id,
    p_modo => 'substituir'
  );

  v_depois := to_jsonb(v_registro);
  -- 094-AUDIT-REGISTRO-INICIO
  insert into public.fabio_registro_correcoes(
    registro_id, professor_id, autor_usuario_id, canal, antes, depois, motivo
  ) values (
    v_registro.id, p_professor_id, v_autor_usuario_id, p_canal,
    v_antes, v_depois, left(btrim(p_motivo), 500)
  );
  -- 094-AUDIT-REGISTRO-FIM

  v_resultado := jsonb_build_object(
    'codigo', 'registro_corrigido',
    'registro_id', v_registro.id,
    'campos', v_registro.campos,
    'texto_consolidado', v_registro.texto_consolidado
  );
  update public.fabio_correcoes_acoes
     set resultado = v_resultado,
         concluida_em = now()
   where id = v_acao.id;
  return v_resultado;
end
$function$;

-- API incompativel: a chave obrigatoria tambem protege a edicao de rascunho.
drop function if exists public.fabio_atualizar_devolutiva_rascunho(integer, uuid, text, text, text, text);
create or replace function public.fabio_atualizar_devolutiva_rascunho(
  p_professor_id integer,
  p_devolutiva_id uuid,
  p_texto_normal text,
  p_texto_apoio_casa text,
  p_motivo text,
  p_canal text,
  p_acao_id text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_devolutiva public.fabio_devolutivas%rowtype;
  v_registro public.fabio_registros_aula%rowtype;
  v_autor_usuario_id integer;
  v_antes jsonb;
  v_depois jsonb;
  v_acao public.fabio_correcoes_acoes%rowtype;
  v_chave_acao text;
  v_requisicao jsonb;
  v_resultado jsonb;
begin
  if p_professor_id is null then
    raise exception 'sem_professor_vinculado';
  end if;
  if p_canal is null or p_canal not in ('app', 'whatsapp') then
    raise exception 'canal_correcao_invalido';
  end if;
  if nullif(btrim(p_texto_normal), '') is null or nullif(btrim(p_texto_apoio_casa), '') is null then
    raise exception 'texto_devolutiva_obrigatorio';
  end if;
  if nullif(btrim(p_motivo), '') is null then
    raise exception 'motivo_edicao_obrigatorio';
  end if;
  v_chave_acao := nullif(btrim(p_acao_id), '');
  if v_chave_acao is null then
    raise exception 'acao_id_obrigatorio';
  end if;
  v_requisicao := jsonb_build_object(
    'professor_id', p_professor_id,
    'alvo_id', p_devolutiva_id,
    'canal', p_canal,
    'texto_normal', btrim(p_texto_normal),
    'texto_apoio_casa', btrim(p_texto_apoio_casa),
    'motivo', left(btrim(p_motivo), 500)
  );

  begin
    insert into public.fabio_correcoes_acoes(
      tipo, acao_id, professor_id, alvo_id, canal, requisicao
    ) values (
      'devolutiva_rascunho', v_chave_acao, p_professor_id,
      p_devolutiva_id, p_canal, v_requisicao
    ) returning * into v_acao;
  -- 094-REPLAY-DEVOLUTIVA-CONFLITO-INICIO
  exception when unique_violation then
    select * into v_acao
      from public.fabio_correcoes_acoes
     where tipo = 'devolutiva_rascunho'
       and acao_id = v_chave_acao;
    if not found then
      raise exception 'acao_correcao_concorrente';
    end if;
    if v_acao.professor_id is distinct from p_professor_id
       or v_acao.alvo_id is distinct from p_devolutiva_id
       or v_acao.canal is distinct from p_canal
       or v_acao.requisicao is distinct from v_requisicao then
      raise exception 'acao_id_reutilizada_para_outra_correcao';
    end if;
    if v_acao.resultado is null then
      raise exception 'acao_correcao_sem_resultado';
    end if;
    return v_acao.resultado;
  -- 094-REPLAY-DEVOLUTIVA-CONFLITO-FIM
  end;

  select * into v_devolutiva
    from public.fabio_devolutivas
   where id = p_devolutiva_id
   for update;
  if not found or v_devolutiva.professor_id is distinct from p_professor_id then
    raise exception 'devolutiva_nao_pertence_ao_professor';
  end if;
  -- 094-GUARDA-STATUS-DEVOLUTIVA-INICIO
  if v_devolutiva.status not in ('gerada', 'oferecida')
     or v_devolutiva.compartilhada_em is not null
     or v_devolutiva.envio_confirmado_em is not null then
    raise exception 'devolutiva_status_nao_editavel';
  end if;
  -- 094-GUARDA-STATUS-DEVOLUTIVA-FIM

  select * into v_registro
    from public.fabio_registros_aula
   where id = v_devolutiva.registro_fatia_id;
  if not found or v_registro.professor_id is distinct from p_professor_id then
    raise exception 'devolutiva_registro_nao_pertence_ao_professor';
  end if;
  select p.usuario_id into v_autor_usuario_id
    from public.professores p
   where p.id = p_professor_id;
  if v_autor_usuario_id is null then
    raise exception 'autor_usuario_nao_encontrado';
  end if;

  v_antes := to_jsonb(v_devolutiva);
  update public.fabio_devolutivas
     set texto_normal = btrim(p_texto_normal),
         texto_apoio_casa = btrim(p_texto_apoio_casa),
         editada_em = now(),
         atualizado_em = now()
   where id = v_devolutiva.id
   returning * into v_devolutiva;
  v_depois := to_jsonb(v_devolutiva);

  insert into public.fabio_devolutiva_edicoes(
    devolutiva_id, professor_id, autor_usuario_id, canal, antes, depois, motivo
  ) values (
    v_devolutiva.id, p_professor_id, v_autor_usuario_id, p_canal,
    v_antes, v_depois, left(btrim(p_motivo), 500)
  );

  v_resultado := jsonb_build_object(
    'codigo', 'devolutiva_atualizada',
    'devolutiva_id', v_devolutiva.id,
    'status', v_devolutiva.status,
    'editada_em', v_devolutiva.editada_em
  );
  update public.fabio_correcoes_acoes
     set resultado = v_resultado,
         concluida_em = now()
   where id = v_acao.id;
  return v_resultado;
end
$function$;

revoke all on function public.fabio_marcar_audio_erro_terminal(uuid, text, text)
  from public, anon, authenticated;
revoke all on function public.fabio_corrigir_registro_confirmado(integer, uuid, jsonb, text, text, text)
  from public, anon, authenticated;
revoke all on function public.fabio_atualizar_devolutiva_rascunho(integer, uuid, text, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.fabio_marcar_audio_erro_terminal(uuid, text, text) to service_role;
grant execute on function public.fabio_corrigir_registro_confirmado(integer, uuid, jsonb, text, text, text) to service_role;
grant execute on function public.fabio_atualizar_devolutiva_rascunho(integer, uuid, text, text, text, text, text) to service_role;

comment on table public.fabio_correcoes_acoes is
  'Ledger idempotente das correcoes finais por tipo e p_acao_id; sem acesso direto do bridge.';
comment on function public.fabio_corrigir_registro_confirmado(integer, uuid, jsonb, text, text, text) is
  'API service_role incompativel: p_acao_id e obrigatorio; WhatsApp passa wa_message_id e app passa chave duravel da acao.';
comment on function public.fabio_atualizar_devolutiva_rascunho(integer, uuid, text, text, text, text, text) is
  'API service_role incompativel: p_acao_id e obrigatorio; WhatsApp passa wa_message_id e app passa chave duravel da acao.';
