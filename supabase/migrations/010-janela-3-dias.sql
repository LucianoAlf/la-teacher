-- 010-janela-3-dias.sql
-- A janela do professor (gravar áudio E fechar a chamada) passa de 24h para 3 DIAS
-- após o fim da aula. Depois disso é com a coordenação (governança — Fase 3).
-- Motivo: 24h é curto demais; o professor perde a janela inteira (piloto).
-- Muda só o limite de janela em 2 RPCs; nada mais do corpo.
--   · app_enfileirar_audio        → janela_de_gravacao_encerrada  (24h -> 3 dias)
--   · fn_registrar_presencas_core → janela_de_chamada_encerrada   (24h -> 3 dias)
-- O lado do client (JANELA_POS_AULA_MS, podeGravar, textos) acompanha.

-- =====================================================================================
-- app_enfileirar_audio — janela de GRAVAÇÃO 24h -> 3 dias (resto do corpo inalterado).
-- =====================================================================================
create or replace function public.app_enfileirar_audio(p_aula_id integer, p_storage_path text, p_duracao_segundos integer, p_registro_id uuid default null::uuid)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_prof     integer := public.fn_professor_do_usuario();
  v_aula     public.aulas_emusys%rowtype;
  v_unidade  uuid;
  v_id       uuid;
  v_ja       jsonb;
  v_qtd_ja   integer := 0;
begin
  if v_prof is null then raise exception 'Usuário sem professor vinculado'; end if;
  if p_storage_path is null or btrim(p_storage_path) = '' then
    raise exception 'storage_path obrigatório';
  end if;

  select * into v_aula from public.aulas_emusys where id = p_aula_id;
  if not found then raise exception 'Aula % não encontrada', p_aula_id; end if;

  if v_aula.professor_id is distinct from v_prof then
    raise exception 'aula_nao_pertence_ao_professor';
  end if;
  if coalesce(v_aula.cancelada, false) then raise exception 'aula_cancelada'; end if;
  if v_aula.data_hora_inicio > now() + interval '15 minutes' then
    raise exception 'gravacao_ainda_nao_disponivel';
  end if;
  if coalesce(v_aula.data_hora_fim, v_aula.data_hora_inicio) < now() - interval '3 days' then
    raise exception 'janela_de_gravacao_encerrada';
  end if;

  v_unidade := v_aula.unidade_id;

  if p_registro_id is not null then
    perform 1 from public.fabio_registros_aula
     where id = p_registro_id and professor_id = v_prof
       and status in ('rascunho','aguardando_confirmacao');
    if not found then
      raise exception 'Registro % não encontrado/permitido para complemento', p_registro_id;
    end if;
  end if;

  -- >>> AVISO DE REGRAVACAO: quem desta aula JA tem relatorio gravado?
  select coalesce(jsonb_agg(jsonb_build_object(
           'aluno_id', x.aluno_id,
           'aluno_nome', x.nome,
           'aula_id', x.aula_id,
           'registrado_em', x.criado_em,
           'previa', left(x.texto, 120)
         ) order by x.nome), '[]'::jsonb), count(*)
    into v_ja, v_qtd_ja
  from (
    select distinct on (r.aluno_id)
           r.aluno_id, a.nome, alvo.id as aula_id,
           alvo.anotacoes_fabio as texto,
           (select max(l.criado_em) from public.aula_registros_fabio_log l where l.aula_id = alvo.id) as criado_em
    from public.aula_alunos_emusys r
    join public.alunos a on a.id = r.aluno_id
    join lateral (
      select ae2.* from public.aulas_emusys ae2
      where ae2.id = public.fn_aula_individual_do_aluno(p_aula_id, r.aluno_id)
    ) alvo on true
    where r.aula_emusys_id = p_aula_id
      and nullif(btrim(coalesce(alvo.anotacoes_fabio,'')), '') is not null
    order by r.aluno_id, alvo.id
  ) x;

  insert into public.fabio_fila_audios
    (professor_id, unidade_id, aula_id, storage_path, duracao_segundos, origem, status)
  values (v_prof, v_unidade, p_aula_id, p_storage_path, p_duracao_segundos, 'app', 'pendente')
  returning id into v_id;

  if p_registro_id is not null then
    update public.fabio_registros_aula
       set campos = campos || jsonb_build_object('audio_complemento_id', v_id)
     where id = p_registro_id;
  end if;

  return jsonb_build_object(
    'audio_id', v_id,
    'status', 'pendente',
    'modo', case when p_registro_id is null then 'novo' else 'complementar' end,
    'registro_id', p_registro_id,
    'aula_ja_registrada', (v_qtd_ja > 0),
    'ja_registrados', v_ja
  );
end
$function$;

-- =====================================================================================
-- fn_registrar_presencas_core — janela de CHAMADA 24h -> 3 dias (só a linha da janela).
-- =====================================================================================
create or replace function public.fn_registrar_presencas_core(
  p_aula_ancora_id  integer,
  p_professor_id    integer,
  p_alunos_ausentes integer[] default '{}'::integer[],
  p_respondido_por  text      default 'professor_la_teacher',
  p_estrito         boolean   default true
) returns jsonb
language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_aula         public.aulas_emusys%rowtype;
  v_roster_total integer;
  v_sem_vinculo  integer;
  v_inseridos    integer;
  v_promovidos   integer;
begin
  if p_respondido_por not in ('professor_la_teacher','fabio_audio') then
    raise exception 'respondido_por_invalido: %', p_respondido_por;
  end if;

  select * into v_aula from public.aulas_emusys where id = p_aula_ancora_id;
  if not found then
    if p_estrito then raise exception 'aula_nao_encontrada'; end if;
    return jsonb_build_object('aula_id',p_aula_ancora_id,'aplicado',false,'motivo','aula_nao_encontrada');
  end if;

  if coalesce(v_aula.cancelada,false) then
    if p_estrito then raise exception 'aula_cancelada'; end if;
    return jsonb_build_object('aula_id',v_aula.id,'aplicado',false,'motivo','aula_cancelada');
  end if;

  if v_aula.professor_id is distinct from p_professor_id then
    if p_estrito then raise exception 'aula_nao_pertence_ao_professor' using errcode='42501'; end if;
    return jsonb_build_object('aula_id',v_aula.id,'aplicado',false,'motivo','professor_divergente');
  end if;

  -- janela operacional (só no modo estrito; Fábio é tolerante a atraso)
  if p_estrito then
    if v_aula.data_hora_inicio > now() + interval '15 minutes' then
      raise exception 'chamada_ainda_nao_disponivel';
    end if;
    if coalesce(v_aula.data_hora_fim, v_aula.data_hora_inicio) < now() - interval '3 days' then
      raise exception 'janela_de_chamada_encerrada';
    end if;
  end if;

  select count(*), count(*) filter (where aluno_id is null)
    into v_roster_total, v_sem_vinculo
  from public.aula_alunos_emusys where aula_emusys_id = v_aula.id;

  if v_roster_total = 0 then
    if p_estrito then raise exception 'roster_nao_sincronizado'; end if;
    return jsonb_build_object('aula_id',v_aula.id,'aplicado',false,'motivo','roster_nao_sincronizado');
  end if;
  if v_sem_vinculo > 0 then
    if p_estrito then raise exception 'roster_incompleto'; end if;
    return jsonb_build_object('aula_id',v_aula.id,'aplicado',false,'motivo','roster_incompleto');
  end if;

  if exists (
    select 1 from unnest(coalesce(p_alunos_ausentes,'{}'::integer[])) a(aluno_id)
    where not exists (select 1 from public.aula_alunos_emusys r
                      where r.aula_emusys_id = v_aula.id and r.aluno_id = a.aluno_id)
  ) then
    if p_estrito then raise exception 'aluno_ausente_fora_do_roster';
    else return jsonb_build_object('aula_id',v_aula.id,'aplicado',false,'motivo','aluno_ausente_fora_do_roster'); end if;
  end if;

  with up as (
    insert into public.aluno_presenca (
      aluno_id, aula_emusys_id, professor_id, unidade_id, data_aula, horario_aula,
      status, status_presenca, curso_nome, turma_nome, sala_nome, respondido_por, respondido_em)
    select distinct r.aluno_id, v_aula.id, p_professor_id, v_aula.unidade_id, v_aula.data_aula,
      (v_aula.data_hora_inicio at time zone 'America/Sao_Paulo')::time,
      case when r.aluno_id = any(coalesce(p_alunos_ausentes,'{}'::integer[])) then 'ausente' else 'presente' end,
      case when r.aluno_id = any(coalesce(p_alunos_ausentes,'{}'::integer[])) then 'falta'   else 'presente' end,
      v_aula.curso_nome, v_aula.turma_nome, v_aula.sala_nome, p_respondido_por, now()
    from public.aula_alunos_emusys r
    where r.aula_emusys_id = v_aula.id and r.aluno_id is not null
    on conflict (aluno_id, aula_emusys_id) do update
      set status          = excluded.status,
          status_presenca = excluded.status_presenca,
          respondido_por  = excluded.respondido_por,
          respondido_em   = excluded.respondido_em
      where aluno_presenca.respondido_por is null
         or aluno_presenca.respondido_por in ('emusys','sistema')
    returning (xmax = 0) as inserido)
  select count(*) filter (where inserido), count(*) filter (where not inserido)
    into v_inseridos, v_promovidos
  from up;

  return jsonb_build_object(
    'aula_id',        v_aula.id,
    'total_roster',   v_roster_total,
    'inseridos',      coalesce(v_inseridos,0),
    'promovidos',     coalesce(v_promovidos,0),
    'ja_havia_forte', v_roster_total - coalesce(v_inseridos,0) - coalesce(v_promovidos,0),
    'aplicado',       true);
end
$function$;

-- os 2 helpers internos seguem sem grant de anon/authenticated (mantidos da 009);
-- o CREATE OR REPLACE acima não recria grants, então a trava da 009 permanece.
