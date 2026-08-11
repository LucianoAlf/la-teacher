-- 090 — máquina durável do professor no WhatsApp
--
-- Esta migration cria somente o estado conversacional, os dois pools e as
-- transições guardadas. A escrita pedagógica continua nas cinco portas da 091.
-- O bridge nunca recebe acesso direto às tabelas novas: chama RPCs service_role.

create table public.fabio_acoes_pendentes (
  id uuid primary key default gen_random_uuid(),
  professor_id integer not null references public.professores(id),
  canal text not null default 'whatsapp' check (canal = 'whatsapp'),
  wa_message_id text not null,
  ultima_resposta_wa_id text,
  tipo text not null check (tipo in (
    'confirmar_intencao_audio', 'confirmar_intencao_chamada',
    'escolher_aula_audio', 'escolher_aula_chamada',
    'processando_audio', 'confirmar_registro', 'confirmar_chamada'
  )),
  estado text not null check (estado in (
    'aberta', 'processando', 'resolvida', 'adiada', 'cancelada', 'expirada', 'erro'
  )),
  aula_id integer references public.aulas_emusys(id),
  audio_id uuid references public.fabio_fila_audios(id),
  registro_id uuid references public.fabio_registros_aula(id),
  storage_path text,
  candidatas integer[] not null default '{}'::integer[],
  payload jsonb not null default '{}'::jsonb,
  expira_em timestamptz,
  lease_token uuid,
  lease_expira_em timestamptz,
  erro text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  encerrado_em timestamptz
);

create unique index fabio_acoes_pendentes_wa_uq
  on public.fabio_acoes_pendentes(wa_message_id);

create unique index fabio_acoes_pendentes_ativa_professor_uq
  on public.fabio_acoes_pendentes(professor_id)
  where estado in ('aberta', 'processando', 'adiada');

create index fabio_acoes_pendentes_expira_idx
  on public.fabio_acoes_pendentes(estado, expira_em)
  where estado in ('aberta', 'adiada', 'processando');

create index fabio_acoes_pendentes_lease_idx
  on public.fabio_acoes_pendentes(lease_expira_em)
  where lease_token is not null;

create table public.fabio_acao_eventos (
  id uuid primary key default gen_random_uuid(),
  acao_id uuid not null references public.fabio_acoes_pendentes(id),
  chat_mensagem_id uuid references public.fabio_chat_mensagens(id),
  wa_message_id text not null unique,
  evento text not null,
  resultado jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now()
);

create index fabio_acao_eventos_acao_idx
  on public.fabio_acao_eventos(acao_id, criado_em);

create or replace function public.fabio_acao_json(p_acao_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select jsonb_build_object(
    'id', a.id,
    'professor_id', a.professor_id,
    'canal', a.canal,
    'wa_message_id', a.wa_message_id,
    'ultima_resposta_wa_id', a.ultima_resposta_wa_id,
    'tipo', a.tipo,
    'estado', a.estado,
    'aula_id', a.aula_id,
    'audio_id', a.audio_id,
    'registro_id', a.registro_id,
    'storage_path', a.storage_path,
    'candidatas', to_jsonb(a.candidatas),
    'payload', a.payload,
    'expira_em', a.expira_em,
    'lease_expira_em', a.lease_expira_em,
    'erro', a.erro,
    'criado_em', a.criado_em,
    'atualizado_em', a.atualizado_em,
    'encerrado_em', a.encerrado_em
  )
  from public.fabio_acoes_pendentes a
  where a.id = p_acao_id;
$function$;

create or replace function public.fabio_aulas_candidatas(
  p_professor_id integer,
  p_fluxo text,
  p_referencia timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_candidatas jsonb;
begin
  if p_fluxo not in ('registro', 'chamada') then
    return jsonb_build_object('ok', false, 'codigo', 'fluxo_invalido', 'candidatas', '[]'::jsonb);
  end if;
  if not exists (select 1 from public.professores p where p.id = p_professor_id) then
    return jsonb_build_object('ok', false, 'codigo', 'professor_nao_encontrado', 'candidatas', '[]'::jsonb);
  end if;

  if p_fluxo = 'registro' then
    with passado as (
      select
        v.aula_ancora_id as aula_id,
        max(v.data_aula) as data_aula,
        max(v.data_hora_inicio) as data_hora_inicio,
        max(v.curso_nome) as curso,
        max(v.turma_nome) as turma,
        max(v.tipo) as tipo,
        max(v.dias_em_atraso) as dias_em_atraso,
        jsonb_agg(distinct jsonb_build_object(
          'aluno_id', v.aluno_id,
          'nome', v.aluno_nome,
          'aula_alvo_id', v.aula_alvo_id
        ) order by jsonb_build_object(
          'aluno_id', v.aluno_id,
          'nome', v.aluno_nome,
          'aula_alvo_id', v.aula_alvo_id
        )) as alunos
      from public.vw_registro_pendencia v
      where v.professor_id = p_professor_id
        and v.data_hora_fim <= p_referencia
        and v.data_hora_fim >= p_referencia - (public.fn_janela_registro_dias() || ' days')::interval
      group by v.aula_ancora_id
    ), futuro as (
      select
        ae.id as aula_id,
        ae.data_aula,
        ae.data_hora_inicio,
        ae.curso_nome as curso,
        ae.turma_nome as turma,
        ae.tipo,
        0 as dias_em_atraso,
        jsonb_agg(jsonb_build_object(
          'aluno_id', r.aluno_id,
          'nome', al.nome,
          'aula_alvo_id', ae.id
        ) order by al.nome) as alunos
      from public.aulas_emusys ae
      join public.aula_alunos_emusys r on r.aula_emusys_id = ae.id
      join public.alunos al on al.id = r.aluno_id
      where ae.professor_id = p_professor_id
        and coalesce(ae.cancelada, false) = false
        and ae.data_hora_inicio > p_referencia
        and ae.data_hora_inicio <= p_referencia + interval '15 minutes'
        and nullif(btrim(coalesce(ae.anotacoes_fabio, '')), '') is null
      group by ae.id, ae.data_aula, ae.data_hora_inicio, ae.curso_nome, ae.turma_nome, ae.tipo
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'aula_id', x.aula_id,
      'data', x.data_aula,
      'hora', to_char(x.data_hora_inicio at time zone 'America/Sao_Paulo', 'HH24:MI'),
      'curso', x.curso,
      'turma', x.turma,
      'tipo', x.tipo,
      'dias_em_atraso', x.dias_em_atraso,
      'alunos', x.alunos
    ) order by x.data_hora_inicio desc), '[]'::jsonb)
      into v_candidatas
    from (select * from passado union all select * from futuro) x;
  else
    with roster as (
      select
        ae.id as aula_id,
        ae.data_aula,
        ae.data_hora_inicio,
        ae.curso_nome as curso,
        ae.turma_nome as turma,
        ae.tipo,
        r.aluno_id,
        al.nome,
        not exists (
          select 1
          from public.aulas_emusys gem
          join public.aluno_presenca ap
            on ap.aula_emusys_id = gem.id
           and ap.aluno_id = r.aluno_id
          where gem.unidade_id = ae.unidade_id
            and gem.data_hora_inicio = ae.data_hora_inicio
            and gem.professor_id is not distinct from ae.professor_id
            and coalesce(gem.cancelada, false) = false
            and public.fn_presenca_e_forte(ap.respondido_por)
        ) as sem_presenca_forte
      from public.aulas_emusys ae
      join public.aula_alunos_emusys r on r.aula_emusys_id = ae.id and r.aluno_id is not null
      join public.alunos al on al.id = r.aluno_id
      where ae.professor_id = p_professor_id
        and coalesce(ae.cancelada, false) = false
        and ae.data_hora_inicio <= p_referencia + interval '15 minutes'
        and coalesce(ae.data_hora_fim, ae.data_hora_inicio) >= p_referencia - (public.fn_janela_registro_dias() || ' days')::interval
    ), por_aula as (
      select aula_id, max(data_aula) as data_aula, max(data_hora_inicio) as data_hora_inicio,
             max(curso) as curso, max(turma) as turma, max(tipo) as tipo,
             jsonb_agg(jsonb_build_object('aluno_id', aluno_id, 'nome', nome)
                       order by nome) filter (where sem_presenca_forte) as alunos,
             count(*) filter (where sem_presenca_forte) as faltantes
      from roster group by aula_id
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'aula_id', aula_id,
      'data', data_aula,
      'hora', to_char(data_hora_inicio at time zone 'America/Sao_Paulo', 'HH24:MI'),
      'curso', curso,
      'turma', turma,
      'tipo', tipo,
      'alunos_sem_presenca_forte', coalesce(alunos, '[]'::jsonb)
    ) order by data_hora_inicio desc), '[]'::jsonb)
      into v_candidatas
    from por_aula where faltantes > 0;
  end if;

  return jsonb_build_object(
    'ok', true,
    'codigo', 'candidatas_prontas',
    'professor_id', p_professor_id,
    'fluxo', p_fluxo,
    'candidatas', coalesce(v_candidatas, '[]'::jsonb)
  );
end;
$function$;

create or replace function public.fabio_shortlist_valida(
  p_professor_id integer,
  p_fluxo text,
  p_candidatas integer[],
  p_referencia timestamptz default now()
) returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select p_fluxo in ('registro', 'chamada')
    and cardinality(coalesce(p_candidatas, '{}'::integer[])) between 1 and 3
    and not exists (
      select 1
        from unnest(coalesce(p_candidatas, '{}'::integer[])) id(aula_id)
       where not exists (
         select 1
           from jsonb_array_elements(
             public.fabio_aulas_candidatas(
               p_professor_id, p_fluxo, p_referencia)->'candidatas') c
          where (c->>'aula_id')::integer = id.aula_id
       )
    );
$function$;

create or replace function public.fabio_iniciar_acao(
  p_professor_id integer,
  p_wa_message_id text,
  p_tipo text,
  p_storage_path text default null,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_id uuid;
  v_candidatas integer[];
  v_acao jsonb;
begin
  if p_tipo not in ('confirmar_intencao_audio', 'confirmar_intencao_chamada') then
    return jsonb_build_object('ok', false, 'codigo', 'tipo_invalido');
  end if;
  if p_wa_message_id is null or btrim(p_wa_message_id) = '' then
    return jsonb_build_object('ok', false, 'codigo', 'wa_message_id_obrigatorio');
  end if;
  if not exists (select 1 from public.professores p where p.id = p_professor_id) then
    return jsonb_build_object('ok', false, 'codigo', 'professor_nao_encontrado');
  end if;

  select id into v_id from public.fabio_acoes_pendentes where wa_message_id = p_wa_message_id;
  if v_id is not null then
    return jsonb_build_object('ok', true, 'codigo', 'acao_existente', 'acao', public.fabio_acao_json(v_id));
  end if;

  if exists (select 1 from public.fabio_acoes_pendentes where professor_id = p_professor_id and estado in ('aberta','processando','adiada')) then
    return jsonb_build_object('ok', false, 'codigo', 'acao_ativa_existente', 'acao', public.fabio_acao_ativa(p_professor_id) -> 'acao');
  end if;

  -- A acao nasce sem shortlist. A lista do payload e evidencia nao confiavel;
  -- somente shortlist_definida, apos consultar o pool do banco, a preenche.
  v_candidatas := '{}'::integer[];

  insert into public.fabio_acoes_pendentes(
    professor_id, wa_message_id, tipo, estado, storage_path, candidatas, payload, expira_em
  ) values (
    p_professor_id, p_wa_message_id, p_tipo, 'aberta', p_storage_path,
    v_candidatas, coalesce(p_payload, '{}'::jsonb), now() + interval '24 hours'
  ) returning id into v_id;

  v_acao := public.fabio_acao_json(v_id);
  return jsonb_build_object('ok', true, 'codigo', 'acao_criada', 'acao', v_acao, 'dados', '{}'::jsonb);
exception when unique_violation then
  select id into v_id from public.fabio_acoes_pendentes where wa_message_id = p_wa_message_id;
  if v_id is not null then
    return jsonb_build_object('ok', true, 'codigo', 'acao_existente', 'acao', public.fabio_acao_json(v_id));
  end if;
  return jsonb_build_object('ok', false, 'codigo', 'acao_concorrente');
end;
$function$;

create or replace function public.fabio_acao_ativa(p_professor_id integer)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select coalesce(
    (select jsonb_build_object('ok', true, 'codigo', 'acao_ativa', 'acao', public.fabio_acao_json(a.id))
       from public.fabio_acoes_pendentes a
      where a.professor_id = p_professor_id and a.estado in ('aberta','processando','adiada')
      order by a.criado_em desc limit 1),
    jsonb_build_object('ok', true, 'codigo', 'sem_acao_ativa', 'acao', null)
  );
$function$;

create or replace function public.fabio_aplicar_evento_acao(
  p_acao_id uuid,
  p_professor_id integer,
  p_wa_message_id text,
  p_evento text,
  p_dados jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_a public.fabio_acoes_pendentes%rowtype;
  v_existente jsonb;
  v_resultado jsonb;
  v_novo_tipo text;
  v_novo_estado text;
  v_aula integer;
  v_candidatas integer[];
  v_audio_id uuid;
  v_registro_id uuid;
  v_fluxo text;
begin
  select resultado into v_existente from public.fabio_acao_eventos where wa_message_id = p_wa_message_id;
  if v_existente is not null then
    return jsonb_build_object('ok', true, 'codigo', 'evento_existente', 'resultado', v_existente);
  end if;

  select * into v_a from public.fabio_acoes_pendentes where id = p_acao_id for update;
  if not found then return jsonb_build_object('ok', false, 'codigo', 'acao_nao_encontrada'); end if;
  if v_a.professor_id is distinct from p_professor_id then return jsonb_build_object('ok', false, 'codigo', 'acao_nao_pertence_ao_professor'); end if;

  if v_a.estado in ('aberta','adiada') and v_a.expira_em is not null and v_a.expira_em < now() then
    update public.fabio_acoes_pendentes set estado='expirada', atualizado_em=now(), encerrado_em=now() where id=v_a.id;
    return jsonb_build_object('ok', false, 'codigo', 'acao_expirada', 'acao', public.fabio_acao_json(v_a.id));
  end if;

  v_novo_tipo := v_a.tipo;
  v_novo_estado := v_a.estado;
  if p_evento = 'intencao_confirmada' and v_a.tipo in ('confirmar_intencao_audio','confirmar_intencao_chamada') then
    v_novo_tipo := case when v_a.tipo = 'confirmar_intencao_audio' then 'escolher_aula_audio' else 'escolher_aula_chamada' end;
  elsif p_evento = 'intencao_negada' and v_a.tipo in ('confirmar_intencao_audio','confirmar_intencao_chamada') then
    v_novo_estado := 'cancelada';
  elsif p_evento = 'shortlist_definida' and v_a.tipo in ('escolher_aula_audio','escolher_aula_chamada') then
    if coalesce(jsonb_typeof(p_dados -> 'candidatas'), '') <> 'array' then
      return jsonb_build_object('ok', false, 'codigo', 'shortlist_invalida',
        'acao', public.fabio_acao_json(v_a.id));
    end if;
    select coalesce(array_agg(x.value::integer), '{}'::integer[])
      into v_candidatas
      from jsonb_array_elements_text(p_dados -> 'candidatas') x;
    v_fluxo := case when v_a.tipo = 'escolher_aula_audio'
                    then 'registro' else 'chamada' end;
    if not public.fabio_shortlist_valida(
      p_professor_id, v_fluxo, v_candidatas, now()) then
      return jsonb_build_object('ok', false, 'codigo', 'shortlist_invalida',
        'acao', public.fabio_acao_json(v_a.id));
    end if;
  elsif p_evento = 'aula_escolhida' and v_a.tipo in ('escolher_aula_audio','escolher_aula_chamada') then
    v_aula := nullif(p_dados ->> 'aula_id','')::integer;
    v_fluxo := case when v_a.tipo = 'escolher_aula_audio'
                    then 'registro' else 'chamada' end;
    if v_aula is null or not (v_aula = any(v_a.candidatas))
       or not public.fabio_shortlist_valida(
         p_professor_id, v_fluxo, array[v_aula], now()) then
      return jsonb_build_object('ok', false, 'codigo', 'aula_fora_da_shortlist', 'acao', public.fabio_acao_json(v_a.id));
    end if;
    v_novo_tipo := case when v_a.tipo = 'escolher_aula_audio' then 'processando_audio' else 'confirmar_chamada' end;
    v_novo_estado := case when v_a.tipo = 'escolher_aula_audio' then 'processando' else 'aberta' end;
  elsif p_evento = 'pergunta_refinada' and v_a.tipo in ('escolher_aula_audio','escolher_aula_chamada') then
    null;
  elsif p_evento = 'audio_enfileirado' and v_a.tipo = 'processando_audio' and v_a.estado = 'processando' then
    v_audio_id := nullif(p_dados ->> 'audio_id', '')::uuid;
    if v_audio_id is null or not exists (
      select 1 from public.fabio_fila_audios f
       where f.id = v_audio_id and f.professor_id = p_professor_id
         and f.origem = 'whatsapp' and f.aula_id = v_a.aula_id
    ) then
      return jsonb_build_object('ok', false, 'codigo', 'audio_invalido',
        'acao', public.fabio_acao_json(v_a.id));
    end if;
  elsif p_evento = 'rascunho_pronto' and v_a.tipo = 'processando_audio' and v_a.estado = 'processando' then
    v_registro_id := nullif(p_dados ->> 'registro_id', '')::uuid;
    if v_registro_id is null or not exists (
      select 1 from public.fabio_registros_aula r
       where r.id = v_registro_id and r.parent_id is null
         and r.professor_id = p_professor_id
         and r.status in ('rascunho', 'aguardando_confirmacao')
    ) then
      return jsonb_build_object('ok', false, 'codigo', 'rascunho_invalido',
        'acao', public.fabio_acao_json(v_a.id));
    end if;
    v_novo_tipo := 'confirmar_registro';
    v_novo_estado := 'aberta';
  elsif p_evento = 'correcao_aplicada' and v_a.tipo = 'confirmar_registro' and v_a.estado = 'aberta' then
    null;
  elsif p_evento = 'confirmado' and v_a.tipo in ('confirmar_registro', 'confirmar_chamada') and v_a.estado = 'aberta' then
    v_novo_estado := 'resolvida';
  elsif p_evento = 'expirado' and v_a.estado in ('aberta', 'adiada') then
    v_novo_estado := 'expirada';
  elsif p_evento = 'limpeza_solicitada' and v_a.estado in ('cancelada', 'expirada', 'erro') then
    null;
  elsif p_evento = 'limpeza_concluida' and v_a.estado in ('cancelada', 'expirada', 'erro') then
    null;
  elsif p_evento = 'adiado' and v_a.estado = 'aberta' then
    v_novo_estado := 'adiada';
  elsif p_evento = 'retomado' and v_a.estado = 'adiada' then
    v_novo_estado := 'aberta';
  elsif p_evento = 'cancelado' and v_a.estado in ('aberta','adiada','processando') then
    v_novo_estado := 'cancelada';
  elsif p_evento = 'confirmacao_solicitada' and v_a.tipo = 'processando_audio' then
    v_novo_tipo := 'confirmar_registro';
    v_novo_estado := 'aberta';
  else
    return jsonb_build_object('ok', false, 'codigo', 'transicao_invalida', 'acao', public.fabio_acao_json(v_a.id));
  end if;

  update public.fabio_acoes_pendentes
     set tipo = v_novo_tipo,
         estado = v_novo_estado,
         aula_id = coalesce(v_aula, aula_id),
         audio_id = coalesce(v_audio_id, audio_id),
         registro_id = coalesce(v_registro_id, registro_id),
         candidatas = coalesce(v_candidatas, candidatas),
         ultima_resposta_wa_id = p_wa_message_id,
         expira_em = case when v_novo_tipo = 'confirmar_registro' then now() + interval '24 hours' else expira_em end,
         atualizado_em = now(),
         encerrado_em = case when v_novo_estado in ('cancelada','resolvida','expirada','erro') then now() else encerrado_em end
   where id = v_a.id;

  v_resultado := jsonb_build_object('ok', true, 'codigo', 'evento_aplicado', 'acao', public.fabio_acao_json(v_a.id), 'dados', coalesce(p_dados,'{}'::jsonb));
  insert into public.fabio_acao_eventos(acao_id, wa_message_id, evento, resultado)
  values (v_a.id, p_wa_message_id, p_evento, v_resultado);
  return v_resultado;
end;
$function$;

create or replace function public.fabio_claim_acoes_processando(
  p_limite integer default 10,
  p_lease_segundos integer default 120
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_token uuid := gen_random_uuid();
  v_itens jsonb;
begin
  with picked as (
    select a.id from public.fabio_acoes_pendentes a
    where a.estado = 'processando'
      and (a.lease_token is null or a.lease_expira_em < now())
    order by a.atualizado_em
    for update skip locked limit greatest(p_limite, 0)
  )
  update public.fabio_acoes_pendentes a
     set lease_token=v_token, lease_expira_em=now() + make_interval(secs => greatest(p_lease_segundos, 1)), atualizado_em=now()
    from picked p where a.id=p.id;
  select coalesce(jsonb_agg(jsonb_build_object('acao', public.fabio_acao_json(a.id), 'lease_token', v_token) order by a.atualizado_em), '[]'::jsonb)
    into v_itens from public.fabio_acoes_pendentes a where a.lease_token=v_token;
  return jsonb_build_object('ok', true, 'codigo', 'acoes_claimadas', 'itens', v_itens);
end;
$function$;

create or replace function public.fabio_concluir_reconciliacao(
  p_acao_id uuid,
  p_lease_token uuid,
  p_evento text,
  p_dados jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_a public.fabio_acoes_pendentes%rowtype;
  v_resultado jsonb;
begin
  select * into v_a from public.fabio_acoes_pendentes where id=p_acao_id for update;
  if not found then return jsonb_build_object('ok',false,'codigo','acao_nao_encontrada'); end if;
  if v_a.lease_token is distinct from p_lease_token or v_a.lease_expira_em < now() then
    return jsonb_build_object('ok',false,'codigo','lease_invalido');
  end if;
  if p_evento not in ('rascunho_pronto','falha_temporaria','falha_terminal','confirmacao_solicitada') then
    return jsonb_build_object('ok',false,'codigo','evento_reconciliacao_invalido');
  end if;
  update public.fabio_acoes_pendentes
     set tipo = case when p_evento in ('rascunho_pronto','confirmacao_solicitada') then 'confirmar_registro' else tipo end,
         estado = case when p_evento in ('rascunho_pronto','confirmacao_solicitada') then 'aberta' when p_evento='falha_terminal' then 'erro' else 'processando' end,
         expira_em = case when p_evento in ('rascunho_pronto','confirmacao_solicitada') then now()+interval '24 hours' else null end,
         erro = case when p_evento like 'falha_%' then p_dados ->> 'erro' else null end,
         lease_token=null, lease_expira_em=null, atualizado_em=now(),
         encerrado_em=case when p_evento='falha_terminal' then now() else null end
   where id=v_a.id;
  v_resultado := jsonb_build_object('ok',true,'codigo','reconciliacao_concluida','acao',public.fabio_acao_json(v_a.id),'dados',coalesce(p_dados,'{}'::jsonb));
  insert into public.fabio_acao_eventos(acao_id, wa_message_id, evento, resultado)
  values (v_a.id, 'reconciliacao:' || v_a.id::text || ':' || extract(epoch from clock_timestamp())::bigint, p_evento, v_resultado);
  return v_resultado;
end;
$function$;

create or replace function public.fabio_claim_acoes_limpeza(
  p_limite integer default 20,
  p_lease_segundos integer default 120
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_token uuid := gen_random_uuid();
  v_itens jsonb;
begin
  with picked as (
    select a.id from public.fabio_acoes_pendentes a
    where a.estado in ('cancelada','expirada','erro') and a.storage_path is not null
      and (a.lease_token is null or a.lease_expira_em < now())
    order by a.atualizado_em for update skip locked limit greatest(p_limite, 0)
  )
  update public.fabio_acoes_pendentes a
     set lease_token=v_token, lease_expira_em=now()+make_interval(secs=>greatest(p_lease_segundos,1)), atualizado_em=now()
    from picked p where a.id=p.id;
  select coalesce(jsonb_agg(jsonb_build_object('acao_id',a.id,'storage_path',a.storage_path,'lease_token',v_token) order by a.atualizado_em),'[]'::jsonb)
    into v_itens from public.fabio_acoes_pendentes a where a.lease_token=v_token;
  return jsonb_build_object('ok',true,'codigo','limpezas_claimadas','itens',v_itens);
end;
$function$;

create or replace function public.fabio_concluir_limpeza(
  p_acao_id uuid,
  p_lease_token uuid,
  p_resultado jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_a public.fabio_acoes_pendentes%rowtype;
begin
  select * into v_a from public.fabio_acoes_pendentes where id=p_acao_id for update;
  if not found then return jsonb_build_object('ok',false,'codigo','acao_nao_encontrada'); end if;
  if v_a.lease_token is distinct from p_lease_token or v_a.lease_expira_em < now() then
    return jsonb_build_object('ok',false,'codigo','lease_invalido');
  end if;
  update public.fabio_acoes_pendentes
     set payload = payload || jsonb_build_object('limpeza', coalesce(p_resultado,'{}'::jsonb)),
         lease_token=null, lease_expira_em=null, atualizado_em=now()
   where id=v_a.id;
  return jsonb_build_object('ok',true,'codigo','limpeza_concluida','acao',public.fabio_acao_json(v_a.id));
end;
$function$;

alter table public.fabio_acoes_pendentes enable row level security;
alter table public.fabio_acao_eventos enable row level security;

revoke all on table public.fabio_acoes_pendentes from public, anon, authenticated;
revoke all on table public.fabio_acao_eventos from public, anon, authenticated;

revoke all on function public.fabio_acao_json(uuid) from public, anon, authenticated, service_role;
revoke all on function public.fabio_aulas_candidatas(integer,text,timestamptz) from public, anon, authenticated;
revoke all on function public.fabio_shortlist_valida(integer,text,integer[],timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.fabio_iniciar_acao(integer,text,text,text,jsonb) from public, anon, authenticated;
revoke all on function public.fabio_acao_ativa(integer) from public, anon, authenticated;
revoke all on function public.fabio_aplicar_evento_acao(uuid,integer,text,text,jsonb) from public, anon, authenticated;
revoke all on function public.fabio_claim_acoes_processando(integer,integer) from public, anon, authenticated;
revoke all on function public.fabio_concluir_reconciliacao(uuid,uuid,text,jsonb) from public, anon, authenticated;
revoke all on function public.fabio_claim_acoes_limpeza(integer,integer) from public, anon, authenticated;
revoke all on function public.fabio_concluir_limpeza(uuid,uuid,jsonb) from public, anon, authenticated;

grant execute on function public.fabio_aulas_candidatas(integer,text,timestamptz) to service_role;
grant execute on function public.fabio_iniciar_acao(integer,text,text,text,jsonb) to service_role;
grant execute on function public.fabio_acao_ativa(integer) to service_role;
grant execute on function public.fabio_aplicar_evento_acao(uuid,integer,text,text,jsonb) to service_role;
grant execute on function public.fabio_claim_acoes_processando(integer,integer) to service_role;
grant execute on function public.fabio_concluir_reconciliacao(uuid,uuid,text,jsonb) to service_role;
grant execute on function public.fabio_claim_acoes_limpeza(integer,integer) to service_role;
grant execute on function public.fabio_concluir_limpeza(uuid,uuid,jsonb) to service_role;

comment on table public.fabio_acoes_pendentes is
  'Estado duravel e auditavel das acoes iniciadas pelo professor no WhatsApp.';
comment on table public.fabio_acao_eventos is
  'Ledger idempotente por wa_message_id das transicoes da acao.';
