-- 095 — recibo canonico de registro no WhatsApp
--
-- Um registro confirmado pode gerar presenca, devolutivas e um carimbo para o
-- professor. O carimbo nasce no mesmo outbox existente, mas so e entregue
-- quando cada devolutiva exigida para aluno presente ja esta pronta. Assim nao
-- existe um segundo sistema de envio nem uma mensagem concorrendo com o
-- ofertador legado.

-- O vocabulario e aditivo: conserva todos os tipos existentes da 075 e inclui
-- apenas o recibo consolidado do registro.
alter table public.fabio_notificacoes
  drop constraint if exists fabio_notificacoes_tipo_check;
alter table public.fabio_notificacoes
  add constraint fabio_notificacoes_tipo_check
  check (tipo = any (array[
    'briefing_matinal','pendencia_registro','experimental_nova','reagendamento',
    'outro','devolutiva_pronta','devolutiva_destinatario','experimental_registrada',
    'experimental_falta','feedback_lembrete','feedback_reforco','feedback_coordenacao',
    'registro_recibo'
  ]));

-- 095-RECIBO-CHAVE-INICIO
-- O indice legado por referencia nao pode capturar o recibo: uma notificacao
-- legada e o carimbo consolidado precisam coexistir para o mesmo registro e
-- canal. A chave antiga continua identica para todos os seus tipos; somente
-- `registro_recibo` sai dela e entra na chave especifica abaixo.
drop index if exists public.uq_fabio_notif_por_referencia;
create unique index uq_fabio_notif_por_referencia
  on public.fabio_notificacoes (referencia_tipo, referencia_id, canal)
  where referencia_tipo is not null
    and referencia_id is not null
    and tipo <> 'registro_recibo';

comment on index public.uq_fabio_notif_por_referencia is
  'Uma notificacao legada por (referencia, canal). registro_recibo usa a chave propria da 095.';

-- A funcao da 018 precisa carregar o mesmo predicado do indice. Recibos nao
-- passam por esta porta generica: sao enfileirados apenas pelo outbox 095.
create or replace function public.fabio_claim_notificacao_por_referencia(
  p_professor_id integer,
  p_tipo text,
  p_categoria text,
  p_canal text,
  p_corpo text,
  p_referencia_tipo text,
  p_referencia_id text,
  p_titulo text default null,
  p_lease_minutos integer default 10
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_id uuid;
  v_token uuid := gen_random_uuid();
begin
  if p_referencia_tipo is null or p_referencia_id is null then
    raise exception 'referencia_tipo e referencia_id sao obrigatorios neste claim';
  end if;
  if p_tipo = 'registro_recibo' then
    raise exception 'registro_recibo_exige_outbox_dedicado';
  end if;

  insert into public.fabio_notificacoes(
    professor_id, tipo, categoria, canal, corpo, titulo,
    referencia_tipo, referencia_id,
    status, tentativas, lease_token, lease_expira_em
  ) values (
    p_professor_id, p_tipo, p_categoria, p_canal, p_corpo, p_titulo,
    p_referencia_tipo, p_referencia_id,
    'processando', 1, v_token, now() + make_interval(mins => p_lease_minutos)
  )
  on conflict (referencia_tipo, referencia_id, canal)
    where referencia_tipo is not null
      and referencia_id is not null
      and tipo <> 'registro_recibo'
  do update set
    status = 'processando',
    tentativas = fabio_notificacoes.tentativas + 1,
    corpo = excluded.corpo,
    titulo = excluded.titulo,
    lease_token = excluded.lease_token,
    lease_expira_em = excluded.lease_expira_em,
    last_error = null
  where
    (fabio_notificacoes.status = 'falhou'
      and (fabio_notificacoes.proxima_tentativa_em is null
           or fabio_notificacoes.proxima_tentativa_em <= now()))
    or (fabio_notificacoes.status = 'processando'
      and fabio_notificacoes.lease_expira_em is not null
      and fabio_notificacoes.lease_expira_em < now())
  returning id into v_id;

  if v_id is null then
    return jsonb_build_object('ok', true, 'claimed', false);
  end if;
  return jsonb_build_object('ok', true, 'claimed', true,
                            'notificacao_id', v_id, 'lease_token', v_token);
end
$function$;

-- Um recibo pertence a um professor, a um tipo, ao registro raiz e ao canal.
create unique index if not exists uq_fabio_notificacoes_registro_recibo_unico
  on public.fabio_notificacoes(
    professor_id, tipo, referencia_tipo, referencia_id, canal
  )
  where tipo = 'registro_recibo'
    and referencia_tipo = 'registro_aula'
    and canal = 'whatsapp';
-- 095-RECIBO-CHAVE-FIM

create or replace function public.fn_enfileirar_registro_recibo(
  p_registro_id uuid,
  p_professor_id integer
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_registro public.fabio_registros_aula%rowtype;
  v_notificacao_id uuid;
begin
  if p_registro_id is null or p_professor_id is null then
    raise exception 'registro_e_professor_obrigatorios';
  end if;

  select * into v_registro
    from public.fabio_registros_aula
   where id = p_registro_id
     and parent_id is null
     and professor_id = p_professor_id;
  if not found then
    raise exception 'registro_recibo_nao_pertence_ao_professor';
  end if;
  if v_registro.confirmado_em is null
     or v_registro.status not in ('gravado_emusys', 'confirmado') then
    raise exception 'registro_recibo_exige_confirmacao';
  end if;

  insert into public.fabio_notificacoes(
    professor_id, tipo, categoria, canal, titulo, corpo, destinatario_tipo,
    status, tentativas, lease_token, lease_expira_em,
    referencia_tipo, referencia_id
  ) values (
    p_professor_id, 'registro_recibo', 'informativa', 'whatsapp',
    'Registro confirmado', 'Recibo do registro aguardando devolutivas.', 'professor',
    'processando', 0, null, now(),
    'registro_aula', p_registro_id::text
  )
  on conflict (professor_id, tipo, referencia_tipo, referencia_id, canal)
    where tipo = 'registro_recibo'
      and referencia_tipo = 'registro_aula'
      and canal = 'whatsapp'
  do nothing
  returning id into v_notificacao_id;

  return jsonb_build_object(
    'ok', true,
    'notificacao_id', v_notificacao_id,
    'ja_enfileirado', v_notificacao_id is null
  );
end
$function$;

-- O core e a unica porta compartilhada de confirmacao. O recibo autoritativo
-- faz parte da confirmacao: se o enqueue falhar, a excecao aborta a transacao
-- em vez de confirmar silenciosamente sem outbox.
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
  v_recibo := public.fn_enfileirar_registro_recibo(p_registro_id, p_professor_id);

  return jsonb_build_object(
    'registro_id', p_registro_id, 'modo', p_modo, 'gravadas', v_gravadas,
    'ausentes_puladas', v_puladas, 'pendencias', v_pend,
    'presenca', v_ganchos -> 'presenca',
    'devolutivas_enfileiradas', v_ganchos -> 'devolutivas_enfileiradas',
    'recibo_enfileirado', v_recibo);
end
$function$;

create or replace function public.fabio_claim_registro_recibo(
  p_limite integer default 20
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_lease_token uuid := gen_random_uuid();
  v_itens jsonb;
begin
  with candidatas as (
    select n.id
      from public.fabio_notificacoes n
      join public.fabio_registros_aula raiz
        on raiz.id::text = n.referencia_id
       and raiz.parent_id is null
       and raiz.professor_id = n.professor_id
     where n.tipo = 'registro_recibo'
       and n.referencia_tipo = 'registro_aula'
       and n.canal = 'whatsapp'
       and raiz.confirmado_em is not null
       and raiz.status in ('gravado_emusys', 'confirmado')
       and (
         (n.status = 'processando'
          and (n.lease_expira_em is null or n.lease_expira_em <= now()))
         or (n.status = 'falhou'
             and (n.proxima_tentativa_em is null or n.proxima_tentativa_em <= now()))
       )
       -- 095-RECIBO-GUARDA-DEVOLUTIVAS-INICIO
       -- Cada aluno presente cujo registro foi gravado precisa ter exatamente
       -- uma devolutiva pronta. Sem a linha, ou em outro estado, o recibo nem
       -- sequer recebe lease: esperar e seguro; chutar nao e.
       and not exists (
         select 1
           from public.fabio_registros_aula alvo
           left join public.fabio_devolutivas d
             on d.registro_fatia_id = alvo.id
          where (alvo.id = raiz.id or alvo.parent_id = raiz.id)
            and alvo.aluno_id is not null
            and alvo.status = 'gravado_emusys'
            and alvo.confirmado_em is not null
            and public.fn_presenca_declarada(alvo.campos) = 'presente'
            and (d.id is null or d.status not in ('gerada', 'oferecida'))
       )
       -- 095-RECIBO-GUARDA-DEVOLUTIVAS-FIM
     order by n.criado_em, n.id
     limit greatest(1, least(coalesce(p_limite, 20), 100))
     for update of n skip locked
  ), tomadas as (
    update public.fabio_notificacoes n
       set status = 'processando',
           lease_token = v_lease_token,
           lease_expira_em = now() + interval '10 minutes',
           proxima_tentativa_em = null,
           tentativas = n.tentativas + 1,
           last_error = null
      from candidatas c
     where n.id = c.id
    returning n.id, n.professor_id, n.referencia_id, n.titulo, n.tentativas
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'notificacao_id', id,
    'professor_id', professor_id,
    'registro_id', referencia_id,
    'titulo', titulo,
    'tentativas', tentativas
  ) order by id), '[]'::jsonb)
    into v_itens
    from tomadas;

  return jsonb_build_object('ok', true, 'lease_token', v_lease_token, 'itens', v_itens);
end
$function$;

create or replace function public.fabio_concluir_registro_recibo(
  notificacao_id uuid,
  lease_token uuid,
  envio_recibo text,
  corpo text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_notificacao public.fabio_notificacoes%rowtype;
  v_chat_id uuid;
  v_envio_recibo text := nullif(btrim(envio_recibo), '');
  v_corpo text := nullif(btrim(corpo), '');
begin
  if notificacao_id is null or lease_token is null then
    return jsonb_build_object('ok', false, 'codigo', 'lease_obrigatorio');
  end if;
  if v_envio_recibo is null or v_corpo is null then
    return jsonb_build_object('ok', false, 'codigo', 'recibo_e_corpo_obrigatorios');
  end if;

  select * into v_notificacao
    from public.fabio_notificacoes n
   where n.id = notificacao_id
     and n.tipo = 'registro_recibo'
     and n.referencia_tipo = 'registro_aula'
     and n.canal = 'whatsapp'
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'recibo_nao_encontrado');
  end if;
  if v_notificacao.status = 'enviada' then
    return jsonb_build_object(
      'ok', v_notificacao.envio_recibo = v_envio_recibo and v_notificacao.corpo = v_corpo,
      'ja_enviado', true,
      'codigo', case when v_notificacao.envio_recibo = v_envio_recibo
                         and v_notificacao.corpo = v_corpo
                     then 'replay_idempotente' else 'recibo_ja_concluido' end
    );
  end if;
  if v_notificacao.status is distinct from 'processando'
     or v_notificacao.lease_token is distinct from lease_token
     or v_notificacao.lease_expira_em is null
     or v_notificacao.lease_expira_em <= now() then
    return jsonb_build_object('ok', false, 'codigo', 'lease_invalido');
  end if;

  -- 095-RECIBO-ESPELHO-CONTEXTO-INICIO
  -- A mesma chave que veio do transporte vira wa_message_id no historico.
  -- Se um retry chegar depois da escrita, atualiza a mesma bolha outbound; se
  -- a chave ja pertencer a outro papel/canal, falha fechado em vez de adulterar
  -- uma mensagem de entrada.
  insert into public.fabio_chat_mensagens(
    identidade_tipo, role, kind, content, channel, professor_id, wa_message_id
  ) values (
    'professor', 'fabio', 'text', v_corpo, 'whatsapp',
    v_notificacao.professor_id, v_envio_recibo
  )
  on conflict (wa_message_id) do update
     set kind = excluded.kind,
         content = excluded.content
   where public.fabio_chat_mensagens.professor_id = excluded.professor_id
     and public.fabio_chat_mensagens.role = 'fabio'
     and public.fabio_chat_mensagens.channel = 'whatsapp'
  returning id into v_chat_id;
  if v_chat_id is null then
    raise exception 'recibo_contexto_conflitante';
  end if;
  -- 095-RECIBO-ESPELHO-CONTEXTO-FIM

  update public.fabio_notificacoes
     set status = 'enviada',
         enviada_em = now(),
         envio_recibo = v_envio_recibo,
         corpo = v_corpo,
         lease_token = null,
         lease_expira_em = null,
         last_error = null
   where id = v_notificacao.id;

  return jsonb_build_object(
    'ok', true,
    'notificacao_id', v_notificacao.id,
    'chat_mensagem_id', v_chat_id,
    'envio_recibo', v_envio_recibo
  );
end
$function$;

create or replace function public.fabio_falhar_registro_recibo(
  notificacao_id uuid,
  lease_token uuid,
  erro text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_afetadas integer;
begin
  if notificacao_id is null or lease_token is null or nullif(btrim(erro), '') is null then
    return jsonb_build_object('ok', false, 'codigo', 'parametros_invalidos');
  end if;

  update public.fabio_notificacoes n
     set status = 'falhou',
         last_error = left(btrim(erro), 1000),
         proxima_tentativa_em = now() + interval '1 minute',
         lease_token = null,
         lease_expira_em = null
   where n.id = notificacao_id
     and n.tipo = 'registro_recibo'
     and n.status = 'processando'
     and n.lease_token = lease_token
     and n.lease_expira_em > now();
  get diagnostics v_afetadas = row_count;
  return jsonb_build_object('ok', v_afetadas = 1, 'codigo',
    case when v_afetadas = 1 then 'falha_registrada' else 'lease_invalido' end);
end
$function$;

-- O notificador antigo continua atendendo apenas devolutivas anteriores a este
-- contrato. Qualquer recibo do registro, ainda em fila, em voo, enviado ou em
-- retry, e dono autoritativo da saida consolidada.
create or replace function public.fabio_devolutivas_a_oferecer(p_limite integer default 50)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  with prontas as (
    select
      d.id,
      d.professor_id,
      d.aluno_id,
      coalesce(a.nome, 'Aluno') as aluno_nome,
      d.destinatario,
      d.destinatario_nome,
      d.criado_em
    from public.fabio_devolutivas d
    join public.alunos a on a.id = d.aluno_id
    where d.status = 'gerada'
      and d.oferecida_em is null
      and d.destinatario is not null
      and nullif(btrim(d.texto_normal), '') is not null
      and not exists (
        select 1
          from public.fabio_registros_aula fatia
          join public.fabio_notificacoes recibo
            on recibo.professor_id = d.professor_id
           and recibo.tipo = 'registro_recibo'
           and recibo.referencia_tipo = 'registro_aula'
           and recibo.referencia_id = coalesce(fatia.parent_id, fatia.id)::text
           and recibo.canal = 'whatsapp'
         where fatia.id = d.registro_fatia_id
      )
    order by d.criado_em asc
    limit greatest(1, least(coalesce(p_limite, 50), 500))
  )
  select coalesce(jsonb_agg(prof order by prof ->> 'professor_id'), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'professor_id', p.professor_id,
      'total', count(*),
      'devolutivas', jsonb_agg(jsonb_build_object(
        'id', p.id,
        'aluno_id', p.aluno_id,
        'aluno_nome', p.aluno_nome,
        'destinatario', p.destinatario,
        'destinatario_nome', p.destinatario_nome
      ) order by p.aluno_nome)
    ) as prof
    from prontas p
    group by p.professor_id
  ) agrupado;
$function$;

-- 095-AGENDA-RASCUNHO-INICIO
create or replace function public.app_minha_agenda_sessao(p_data date default current_date)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_professor_id integer := public.fn_professor_do_usuario();
begin
  if v_professor_id is null then
    return jsonb_build_object('erro', 'sem_professor_vinculado');
  end if;

  return coalesce((
    with aulas_dia as (
      select ae.*
        from public.aulas_emusys ae
       where ae.professor_id = v_professor_id
         and ae.data_aula = p_data
         and coalesce(ae.cancelada, false) = false
    ), slots as (
      select data_hora_inicio, data_hora_fim,
             (array_agg(id order by case when tipo = 'turma' then 0 else 1 end, id))[1] as aula_id_ancora
        from aulas_dia
       group by data_hora_inicio, data_hora_fim
    ), ancoras as (
      select ae.*
        from slots s
        join aulas_dia ae on ae.id = s.aula_id_ancora
    )
    select jsonb_agg(jsonb_build_object(
      'aula_id_ancora', ae.id,
      'hora', to_char(ae.data_hora_inicio at time zone 'America/Sao_Paulo', 'HH24:MI'),
      'hora_fim', to_char(ae.data_hora_fim at time zone 'America/Sao_Paulo', 'HH24:MI'),
      'data_hora_inicio', ae.data_hora_inicio,
      'data_hora_fim', ae.data_hora_fim,
      'curso', ae.curso_nome,
      'turma_nome', ae.turma_nome,
      'tipo', ae.tipo,
      'n_alunos', coalesce(roster.n_alunos, 0),
      'n_registradas', coalesce(roster.n_registradas, 0),
      'tem_registro', coalesce(roster.tem_registro, false),
      'tem_rascunho', coalesce(roster.tem_rascunho, false),
      'roster_incompleto', coalesce(roster.n_sem_vinculo, 0) > 0,
      'alunos', coalesce(roster.alunos, '[]'::jsonb),
      'experimental', ae.categoria = 'experimental',
      'vinculo_id', (
        select v.id from public.lead_experimental_aulas v
         where v.aula_local_id = ae.id and v.cancelado_em is null
         order by v.id desc limit 1
      ),
      'experimental_nome', (
        select le.nome_aluno
          from public.lead_experimental_aulas v
          join public.lead_experimentais le on le.id = v.lead_experimental_id
         where v.aula_local_id = ae.id and v.cancelado_em is null
         order by v.id desc limit 1
      )
    ) order by ae.data_hora_inicio, ae.id)
      from ancoras ae
      left join lateral (
        select
          count(*) as n_alunos,
          count(distinct ap.aluno_id) filter (where public.fn_presenca_e_forte(ap.respondido_por)) as n_registradas,
          count(*) filter (where r.aluno_id is null) as n_sem_vinculo,
          bool_or(nullif(btrim(coalesce(aula_alvo.anotacoes_fabio, '')), '') is not null) as tem_registro,
          bool_or(rascunho.id is not null) as tem_rascunho,
          jsonb_agg(jsonb_build_object(
            'aluno_id', r.aluno_id,
            'nome', r.aluno_nome,
            'aula_id_alvo', coalesce(aula_alvo.id, ae.id),
            'presenca', coalesce(
              ap.status_presenca,
              case ap.status when 'presente' then 'presente' when 'ausente' then 'falta' end,
              'a_confirmar'
            ),
            'tem_presenca_registrada', ap.id is not null and public.fn_presenca_e_forte(ap.respondido_por),
            'tem_registro', nullif(btrim(coalesce(aula_alvo.anotacoes_fabio, '')), '') is not null,
            'tem_rascunho', rascunho.id is not null,
            'justificada', coalesce(adm.justificada, false)
          ) order by r.aluno_nome) as alunos
        from public.aula_alunos_emusys r
        left join public.aluno_presenca ap
          on ap.aula_emusys_id = ae.id and ap.aluno_id = r.aluno_id
        left join public.aluno_presenca_administrativo adm
          on adm.aula_emusys_id = ae.id and adm.aluno_id = r.aluno_id
        left join lateral (
          select alvo.id, alvo.anotacoes_fabio
            from public.aulas_emusys alvo
            join public.aula_alunos_emusys alvo_roster
              on alvo_roster.aula_emusys_id = alvo.id
             and alvo_roster.aluno_id = r.aluno_id
           where alvo.professor_id = v_professor_id
             and alvo.data_aula = p_data
             and alvo.data_hora_inicio = ae.data_hora_inicio
             and alvo.data_hora_fim is not distinct from ae.data_hora_fim
             and coalesce(alvo.cancelada, false) = false
             and coalesce(alvo.tipo, '') <> 'turma'
           order by alvo.id
           limit 1
        ) aula_individual on true
        left join public.aulas_emusys aula_alvo
          on aula_alvo.id = coalesce(aula_individual.id, ae.id)
        left join lateral (
          select rasc.id
            from public.fabio_registros_aula rasc
           where rasc.professor_id = v_professor_id
             and rasc.status = 'aguardando_confirmacao'
             and (
               -- Tronco da turma: a pendencia e do slot inteiro.
               (rasc.parent_id is null and rasc.aluno_id is null and rasc.aula_id = ae.id)
               -- Registro individual ja aponta para o alvo agrupado.
               or (rasc.parent_id is null and rasc.aluno_id = r.aluno_id
                   and rasc.aula_id = coalesce(aula_individual.id, ae.id))
               -- Fatia pertence ao tronco do slot, mas so aparece para seu aluno.
               or (rasc.parent_id is not null and rasc.aluno_id = r.aluno_id
                   and exists (
                     select 1 from public.fabio_registros_aula tronco
                      where tronco.id = rasc.parent_id
                        and tronco.aula_id = ae.id
                        and tronco.professor_id = v_professor_id
                   ))
             )
           order by rasc.criado_em, rasc.id
           limit 1
        ) rascunho on true
       where r.aula_emusys_id = ae.id
      ) roster on true
  ), '[]'::jsonb);
end
$function$;
-- 095-AGENDA-RASCUNHO-FIM

-- 095-WRAPPER-APP-AUTH-INICIO
create or replace function public.app_atualizar_devolutiva_rascunho(
  p_devolutiva_id uuid,
  p_texto_normal text,
  p_texto_apoio_casa text,
  p_motivo text,
  p_acao_id text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_auth_user_id uuid := auth.uid();
  v_professor_id integer;
begin
  if v_auth_user_id is null then
    raise exception 'usuario_nao_autenticado' using errcode = '42501';
  end if;
  select p.id into v_professor_id
    from public.professores p
    join public.usuarios u on u.id = p.usuario_id
   where u.auth_user_id = v_auth_user_id
     and coalesce(p.ativo, true);
  if v_professor_id is null then
    raise exception 'sem_professor_vinculado' using errcode = '42501';
  end if;

  return public.fabio_atualizar_devolutiva_rascunho(
    v_professor_id,
    p_devolutiva_id,
    p_texto_normal,
    p_texto_apoio_casa,
    p_motivo,
    'app',
    p_acao_id
  );
end
$function$;
-- 095-WRAPPER-APP-AUTH-FIM

-- 095-AUDIO-DEDUP-INICIO
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
  v_existente public.fabio_fila_audios%rowtype;
  v_unidade uuid;
  v_id uuid;
  v_ja jsonb;
  v_qtd_ja integer := 0;
  v_storage_path text := nullif(btrim(p_storage_path), '');
begin
  if p_professor_id is null then raise exception 'sem_professor_vinculado'; end if;
  if p_origem not in ('app', 'whatsapp') then
    raise exception 'origem_invalida: %', p_origem;
  end if;
  if v_storage_path is null then
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

  -- A chave nao depende de uma unique constraint nova sobre dados legados. O
  -- lock transacional serializa o par professor/path, retorna o primeiro audio
  -- ja existente e evita uma segunda fila quando o POST perde a resposta.
  perform pg_advisory_xact_lock(hashtextextended(
    'fabio-fila-audio:' || p_professor_id::text || ':' || v_storage_path, 0
  ));
  select * into v_existente
    from public.fabio_fila_audios
   where professor_id = p_professor_id
     and storage_path = v_storage_path
   order by id
   limit 1;
  if found then
    if v_existente.aula_id is distinct from p_aula_id then
      raise exception 'storage_path_reutilizado_para_outra_aula';
    end if;
    return jsonb_build_object(
      'audio_id', v_existente.id,
      'status', v_existente.status,
      'modo', case when p_registro_id is null then 'novo' else 'complementar' end,
      'registro_id', p_registro_id,
      'deduplicado', true,
      'aula_ja_registrada', v_qtd_ja > 0,
      'ja_registrados', v_ja
    );
  end if;

  insert into public.fabio_fila_audios(
    professor_id, unidade_id, aula_id, storage_path, duracao_segundos, origem, status
  ) values (
    p_professor_id, v_unidade, p_aula_id, v_storage_path,
    p_duracao_segundos, p_origem, 'pendente'
  ) returning id into v_id;

  if p_registro_id is not null then
    update public.fabio_registros_aula
       set campos = campos || jsonb_build_object('audio_complemento_id', v_id)
     where id = p_registro_id;
  end if;

  return jsonb_build_object(
    'audio_id', v_id, 'status', 'pendente',
    'modo', case when p_registro_id is null then 'novo' else 'complementar' end,
    'registro_id', p_registro_id, 'deduplicado', false,
    'aula_ja_registrada', v_qtd_ja > 0,
    'ja_registrados', v_ja
  );
end
$function$;
-- 095-AUDIO-DEDUP-FIM

-- ACL explicita: o navegador chama apenas app_*, nunca fabio_* ou os nucleos.
revoke all on function public.fn_enfileirar_registro_recibo(uuid, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.fabio_claim_registro_recibo(integer)
  from public, anon, authenticated, service_role;
revoke all on function public.fabio_concluir_registro_recibo(uuid, uuid, text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.fabio_falhar_registro_recibo(uuid, uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.fabio_atualizar_devolutiva_rascunho(integer, uuid, text, text, text, text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.fn_confirmar_registro_core(integer, uuid, uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.app_atualizar_devolutiva_rascunho(uuid, text, text, text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.app_minha_agenda_sessao(date)
  from public, anon, authenticated, service_role;
revoke all on function public.fabio_devolutivas_a_oferecer(integer)
  from public, anon, authenticated, service_role;
revoke all on function public.fn_enfileirar_audio_core(integer, text, integer, uuid, text, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.app_enfileirar_audio(integer, text, integer, uuid)
  from public, anon, authenticated, service_role;

grant execute on function public.fabio_claim_registro_recibo(integer) to service_role;
grant execute on function public.fabio_concluir_registro_recibo(uuid, uuid, text, text) to service_role;
grant execute on function public.fabio_falhar_registro_recibo(uuid, uuid, text) to service_role;
grant execute on function public.fabio_atualizar_devolutiva_rascunho(integer, uuid, text, text, text, text, text)
  to service_role;
grant execute on function public.app_atualizar_devolutiva_rascunho(uuid, text, text, text, text)
  to authenticated;
grant execute on function public.app_minha_agenda_sessao(date) to authenticated;
grant execute on function public.fabio_devolutivas_a_oferecer(integer) to service_role;
grant execute on function public.app_enfileirar_audio(integer, text, integer, uuid)
  to authenticated, service_role;

comment on index public.uq_fabio_notificacoes_registro_recibo_unico is
  'Recibo autoritativo por professor, tipo, registro raiz e canal; a confirmacao pode repetir sem duplicar a saida.';
comment on function public.fabio_claim_registro_recibo(integer) is
  'Worker service_role: reivindica somente recibos cujo registro esta confirmado e cujas devolutivas exigidas estao gerada ou oferecida.';
comment on function public.app_atualizar_devolutiva_rascunho(uuid, text, text, text, text) is
  'Porta autenticada do app: resolve professor por auth.uid() e delega ao nucleo auditado sem expor fabio_* ao navegador.';
