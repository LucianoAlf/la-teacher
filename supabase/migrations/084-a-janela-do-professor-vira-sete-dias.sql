-- 084 — a janela do professor vira 7 dias, e o numero passa a ter UM dono
--
-- Ordem do Alf em 10/08, depois de ler o log da Daiana: "abrir uma janela maior
-- de tres dias depois da aula, no maximo, ou uma semana, sete dias, e o
-- professor poder fazer o lancamento, fazer as coisas que ele precisa depois de
-- trabalhar, depois que travar. Agora, so coordenacao pode liberar alguma coisa
-- assim."
--
-- O caso que forcou: a professora tentou registrar as aulas de 04 e 05/08 na
-- noite de 08/08. A janela de 3 dias tinha fechado poucas horas antes; o app
-- mostrou um cadeado mudo escrito "Encerrada" e ela foi pro WhatsApp. La o
-- Fabio gravou UMA das aulas mesmo assim — porque `registrar_aula_fabio` nunca
-- validou janela nenhuma. Ou seja: a porta estava trancada de um lado e aberta
-- do outro, e quem decidia era por onde a professora entrava.
--
-- ── O numero tinha 4 donos e agora tem 1 ────────────────────────────────────
-- `interval '3 days'` estava escrito na mao em `fn_registrar_presencas_core` e
-- em `app_enfileirar_audio`; o cliente tinha a propria copia em
-- `JANELA_POS_AULA_MS`; e a escalacao pra coordenacao tinha um terceiro numero
-- (`p_dias default 3`) que por acaso era igual. Quatro copias do mesmo acordo
-- e' como o acordo se desfaz sem ninguem perceber.
--
-- Agora existe `fn_janela_registro_dias()`. Mudar o prazo e' mudar UMA linha.
--
-- ── Por que a escalacao segue a mesma regua ─────────────────────────────────
-- Enquanto a janela era 3, escalar em >3 dias significava "o professor nao
-- consegue mais fazer, entao vira problema da coordenacao". Com a janela em 7,
-- manter a escalacao em 3 seria entregar pra coordenacao um professor que ainda
-- tem 4 dias pra resolver sozinho — cobrar antes do prazo, na frente de todo
-- mundo. A regua e' uma so: **ate 7 dias e' do professor; depois de 7 e' da
-- coordenacao**, que e' exatamente a fronteira que o Alf desenhou.
--
-- ⚠️ O que esta migration NAO faz: nao cria o botao de "pedir liberacao". A
-- liberacao apos os 7 dias continua sendo ato humano da coordenacao (hoje,
-- mexendo no Emusys ou pedindo pra gente). O canal proprio pra esse pedido e'
-- assunto da SPEC do Fabio, junto com o resto do que ele pode escrever.

create or replace function public.fn_janela_registro_dias()
 returns integer
 language sql
 immutable
as $function$ select 7 $function$;

comment on function public.fn_janela_registro_dias() is
  'Dono unico do prazo: quantos dias depois do FIM da aula o professor ainda '
  'pode lancar chamada e gravar o registro. Depois disso a liberacao e da '
  'coordenacao. Lido por fn_registrar_presencas_core, app_enfileirar_audio, '
  'fn_pendencias_escalonadas e espelhado no cliente (features/agenda/sessao.ts).';

-- ── chamada ────────────────────────────────────────────────────────────────
create or replace function public.fn_registrar_presencas_core(p_aula_ancora_id integer, p_professor_id integer, p_alunos_ausentes integer[] default '{}'::integer[], p_respondido_por text default 'professor_la_teacher'::text, p_estrito boolean default true)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_aula public.aulas_emusys%rowtype; v_roster_total integer; v_sem_vinculo integer; v_inseridos integer; v_promovidos integer;
begin
  if p_respondido_por not in ('professor_la_teacher','fabio_audio') then raise exception 'respondido_por_invalido: %', p_respondido_por; end if;
  select * into v_aula from public.aulas_emusys where id = p_aula_ancora_id;
  if not found then if p_estrito then raise exception 'aula_nao_encontrada'; end if; return jsonb_build_object('aula_id',p_aula_ancora_id,'aplicado',false,'motivo','aula_nao_encontrada'); end if;
  if coalesce(v_aula.cancelada,false) then if p_estrito then raise exception 'aula_cancelada'; end if; return jsonb_build_object('aula_id',v_aula.id,'aplicado',false,'motivo','aula_cancelada'); end if;
  if v_aula.professor_id is distinct from p_professor_id then if p_estrito then raise exception 'aula_nao_pertence_ao_professor' using errcode='42501'; end if; return jsonb_build_object('aula_id',v_aula.id,'aplicado',false,'motivo','professor_divergente'); end if;
  if p_estrito then
    if v_aula.data_hora_inicio > now() + interval '15 minutes' then raise exception 'chamada_ainda_nao_disponivel'; end if;
    -- prazo com dono unico (084)
    if coalesce(v_aula.data_hora_fim, v_aula.data_hora_inicio) < now() - (public.fn_janela_registro_dias() || ' days')::interval then raise exception 'janela_de_chamada_encerrada'; end if;
  end if;
  select count(*), count(*) filter (where aluno_id is null) into v_roster_total, v_sem_vinculo from public.aula_alunos_emusys where aula_emusys_id = v_aula.id;
  if v_roster_total = 0 then if p_estrito then raise exception 'roster_nao_sincronizado'; end if; return jsonb_build_object('aula_id',v_aula.id,'aplicado',false,'motivo','roster_nao_sincronizado'); end if;
  if v_sem_vinculo > 0 then if p_estrito then raise exception 'roster_incompleto'; end if; return jsonb_build_object('aula_id',v_aula.id,'aplicado',false,'motivo','roster_incompleto'); end if;
  if exists (select 1 from unnest(coalesce(p_alunos_ausentes,'{}'::integer[])) a(aluno_id) where not exists (select 1 from public.aula_alunos_emusys r where r.aula_emusys_id = v_aula.id and r.aluno_id = a.aluno_id)) then
    if p_estrito then raise exception 'aluno_ausente_fora_do_roster'; else return jsonb_build_object('aula_id',v_aula.id,'aplicado',false,'motivo','aluno_ausente_fora_do_roster'); end if;
  end if;
  with up as (
    insert into public.aluno_presenca (aluno_id, aula_emusys_id, professor_id, unidade_id, data_aula, horario_aula, status, status_presenca, curso_nome, turma_nome, sala_nome, respondido_por, respondido_em)
    select distinct r.aluno_id, v_aula.id, p_professor_id, v_aula.unidade_id, v_aula.data_aula, (v_aula.data_hora_inicio at time zone 'America/Sao_Paulo')::time,
      case when r.aluno_id = any(coalesce(p_alunos_ausentes,'{}'::integer[])) then 'ausente' else 'presente' end,
      case when r.aluno_id = any(coalesce(p_alunos_ausentes,'{}'::integer[])) then 'falta' else 'presente' end,
      v_aula.curso_nome, v_aula.turma_nome, v_aula.sala_nome, p_respondido_por, now()
    from public.aula_alunos_emusys r where r.aula_emusys_id = v_aula.id and r.aluno_id is not null
    on conflict (aluno_id, aula_emusys_id) do update set status = excluded.status, status_presenca = excluded.status_presenca, respondido_por = excluded.respondido_por, respondido_em = excluded.respondido_em
      where aluno_presenca.respondido_por is null or aluno_presenca.respondido_por in ('emusys','sistema')
    returning (xmax = 0) as inserido)
  select count(*) filter (where inserido), count(*) filter (where not inserido) into v_inseridos, v_promovidos from up;
  return jsonb_build_object('aula_id', v_aula.id, 'total_roster', v_roster_total, 'inseridos', coalesce(v_inseridos,0), 'promovidos', coalesce(v_promovidos,0), 'ja_havia_forte', v_roster_total - coalesce(v_inseridos,0) - coalesce(v_promovidos,0), 'aplicado', true);
end $function$;

-- ── gravacao do audio ──────────────────────────────────────────────────────
create or replace function public.app_enfileirar_audio(p_aula_id integer, p_storage_path text, p_duracao_segundos integer, p_registro_id uuid default null::uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_prof integer := public.fn_professor_do_usuario(); v_aula public.aulas_emusys%rowtype;
  v_unidade uuid; v_id uuid; v_ja jsonb; v_qtd_ja integer := 0;
begin
  if v_prof is null then raise exception 'Usuário sem professor vinculado'; end if;
  if p_storage_path is null or btrim(p_storage_path) = '' then raise exception 'storage_path obrigatório'; end if;
  select * into v_aula from public.aulas_emusys where id = p_aula_id;
  if not found then raise exception 'Aula % não encontrada', p_aula_id; end if;
  if v_aula.professor_id is distinct from v_prof then raise exception 'aula_nao_pertence_ao_professor'; end if;
  if coalesce(v_aula.cancelada, false) then raise exception 'aula_cancelada'; end if;
  if v_aula.data_hora_inicio > now() + interval '15 minutes' then raise exception 'gravacao_ainda_nao_disponivel'; end if;
  -- prazo com dono unico (084)
  if coalesce(v_aula.data_hora_fim, v_aula.data_hora_inicio) < now() - (public.fn_janela_registro_dias() || ' days')::interval then raise exception 'janela_de_gravacao_encerrada'; end if;
  v_unidade := v_aula.unidade_id;
  if p_registro_id is not null then
    perform 1 from public.fabio_registros_aula where id = p_registro_id and professor_id = v_prof and status in ('rascunho','aguardando_confirmacao');
    if not found then raise exception 'Registro % não encontrado/permitido para complemento', p_registro_id; end if;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('aluno_id', x.aluno_id,'aluno_nome', x.nome,'aula_id', x.aula_id,'registrado_em', x.criado_em,'previa', left(x.texto, 120)) order by x.nome), '[]'::jsonb), count(*)
    into v_ja, v_qtd_ja
  from (
    select distinct on (r.aluno_id) r.aluno_id, a.nome, alvo.id as aula_id, alvo.anotacoes_fabio as texto,
           (select max(l.criado_em) from public.aula_registros_fabio_log l where l.aula_id = alvo.id) as criado_em
    from public.aula_alunos_emusys r join public.alunos a on a.id = r.aluno_id
    join lateral (select ae2.* from public.aulas_emusys ae2 where ae2.id = public.fn_aula_individual_do_aluno(p_aula_id, r.aluno_id)) alvo on true
    where r.aula_emusys_id = p_aula_id and nullif(btrim(coalesce(alvo.anotacoes_fabio,'')), '') is not null
    order by r.aluno_id, alvo.id
  ) x;
  insert into public.fabio_fila_audios (professor_id, unidade_id, aula_id, storage_path, duracao_segundos, origem, status)
  values (v_prof, v_unidade, p_aula_id, p_storage_path, p_duracao_segundos, 'app', 'pendente') returning id into v_id;
  if p_registro_id is not null then
    update public.fabio_registros_aula set campos = campos || jsonb_build_object('audio_complemento_id', v_id) where id = p_registro_id;
  end if;
  return jsonb_build_object('audio_id', v_id,'status', 'pendente','modo', case when p_registro_id is null then 'novo' else 'complementar' end,'registro_id', p_registro_id,'aula_ja_registrada', (v_qtd_ja > 0),'ja_registrados', v_ja);
end $function$;

-- ── escalacao: mesma regua da janela ───────────────────────────────────────
-- `p_dias` deixa de ter o 3 fixo no default. Quem chama sem argumento passa a
-- receber a janela vigente; quem passa numero explicito continua mandando.
create or replace function public.fn_pendencias_escalonadas(p_dias integer default null::integer, p_professor_id integer default null::integer, p_max_aulas integer default 12)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
 set statement_timeout to '120s'
as $function$
declare
  v_out jsonb;
  v_dias integer := coalesce(p_dias, public.fn_janela_registro_dias());
begin
  with base as (
    -- a view traz unidade_id; o nome vem do join (ela nao expoe unidade_nome)
    select v.professor_id, v.professor_nome, u.nome as unidade_nome,
           v.aula_ancora_id as aula_id, v.data_aula, v.data_hora_inicio,
           to_char(v.data_hora_inicio at time zone 'America/Sao_Paulo','HH24:MI') as hora,
           v.curso_nome, v.turma_nome, v.aluno_nome, v.dias_em_atraso
      from vw_registro_pendencia v
      left join unidades u on u.id = v.unidade_id
     where v.cobravel                              -- <<< nunca o passivo
       and v.dias_em_atraso > v_dias
       and (p_professor_id is null or v.professor_id = p_professor_id)
  ),
  por_aula as (
    select professor_id, max(professor_nome) as professor_nome, unidade_nome,
           aula_id, max(data_aula) as data_aula, max(data_hora_inicio) as data_hora_inicio,
           max(hora) as hora, max(curso_nome) as curso_nome, max(turma_nome) as turma_nome,
           max(dias_em_atraso) as dias_em_atraso,
           jsonb_agg(distinct aluno_nome) as alunos
      from base
     group by professor_id, aula_id, unidade_nome
  ),
  ranqueada as (
    select *, row_number() over (
             partition by professor_id order by data_hora_inicio desc) as rn,
           count(*) over (partition by professor_id) as total_aulas
      from por_aula
  )
  select coalesce(jsonb_agg(p order by p->>'pior_atraso' desc), '[]'::jsonb)
    into v_out
    from (
      select jsonb_build_object(
               'professor_id',   professor_id,
               'professor_nome', max(professor_nome),
               -- unidade por aula: 26 dos 42 professores dao aula em mais de
               -- uma, e um max() aqui carimbaria a errada no encaminhamento.
               'unidades', (select jsonb_agg(distinct u2) from jsonb_array_elements_text(
                              jsonb_agg(distinct unidade_nome)) u2),
               'pior_atraso',    max(dias_em_atraso),
               'total_aulas',    max(total_aulas),
               'aulas', jsonb_agg(
                   jsonb_build_object(
                     'aula_id',   aula_id,
                     'data_aula', data_aula,
                     'hora',      hora,
                     'curso',     coalesce(curso_nome, turma_nome, 'Aula'),
                     'unidade',   unidade_nome,
                     'dias',      dias_em_atraso,
                     'alunos',    alunos)
                   order by data_hora_inicio desc)
             ) as p
        from ranqueada
       where rn <= p_max_aulas
       group by professor_id
    ) s;

  return jsonb_build_object(
    'ok', true,
    'limite_dias', v_dias,
    'fonte', 'vw_registro_pendencia (cobravel)',
    'professores', jsonb_array_length(v_out),
    'linhas', v_out
  );
end
$function$;

-- ── a experimental usa a MESMA regua ───────────────────────────────────────
-- Ela tinha a terceira copia do `interval '3 days'`. Deixar a experimental em 3
-- e a aula normal em 7 seria dar ao professor duas regras com a mesma frase na
-- tela ("a janela de gravacao fecha X dias depois da aula") — o jeito mais
-- rapido de ensinar que o prazo do app e' chute. O registro da experimental
-- atrasado ainda serve ao comercial; nao registrado nao serve a ninguem.
create or replace function public.app_enfileirar_audio_experimental(p_vinculo_id bigint, p_storage_path text, p_duracao_segundos integer)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_prof    integer := public.fn_professor_do_usuario();
  v_vinculo record;
  v_aula    public.aulas_emusys%rowtype;
  v_id      uuid;
begin
  if v_prof is null then
    raise exception 'sem_professor_vinculado';
  end if;
  if p_storage_path is null or btrim(p_storage_path) = '' then
    raise exception 'storage_path obrigatório';
  end if;

  select v.id, v.estado, v.aula_local_id
    into v_vinculo
    from public.lead_experimental_aulas v
   where v.id = p_vinculo_id and v.substituido_em is null;

  if not found then
    raise exception 'vinculo_inexistente_ou_sem_aula: %', p_vinculo_id;
  end if;

  -- As MESMAS travas de estado do formulário (fn_registrar_experimental_interno).
  -- Falhar aqui é falhar antes: descobrir que a aula não aceita registro depois
  -- de o professor falar dois minutos é a pior hora possível.
  if v_vinculo.estado = 'pendente' then
    raise exception 'experimental_sem_aula_vinculada';
  elsif v_vinculo.estado = 'faltou' then
    raise exception 'experimental_faltou_nao_tem_registro';
  elsif v_vinculo.estado = 'cancelado' then
    raise exception 'experimental_cancelada';
  end if;

  select * into v_aula from public.aulas_emusys where id = v_vinculo.aula_local_id;
  if not found then
    raise exception 'vinculo_inexistente_ou_sem_aula: %', p_vinculo_id;
  end if;

  -- A posse mora aqui, e é `=` de propósito: com `is not distinct from`, aula
  -- órfã + professor órfão dariam null = null = verdadeiro, e a guarda abriria.
  if v_aula.professor_id is distinct from v_prof then
    raise exception 'aula_de_outro_professor';
  end if;
  if coalesce(v_aula.cancelada, false) then
    raise exception 'aula_cancelada';
  end if;
  if v_aula.data_hora_inicio > now() + interval '15 minutes' then
    raise exception 'gravacao_ainda_nao_disponivel';
  end if;
  -- prazo com dono unico (084)
  if coalesce(v_aula.data_hora_fim, v_aula.data_hora_inicio) < now() - (public.fn_janela_registro_dias() || ' days')::interval then
    raise exception 'janela_de_gravacao_encerrada';
  end if;

  insert into public.fabio_fila_audios
    (professor_id, unidade_id, aula_id, vinculo_id, storage_path, duracao_segundos, origem, status)
  values
    (v_prof, v_aula.unidade_id, v_aula.id, p_vinculo_id, p_storage_path, p_duracao_segundos, 'app', 'pendente')
  returning id into v_id;

  return jsonb_build_object('audio_id', v_id, 'status', 'pendente', 'vinculo_id', p_vinculo_id);
end
$function$;
