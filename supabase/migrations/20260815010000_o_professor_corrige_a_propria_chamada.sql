-- O professor Valdo relatou: já tinha feito a chamada de uma turma, e ao
-- confirmar o registro por áudio teve que "dar presença de novo" — e mesmo
-- assim um aluno (que veio) ficou gravado como ausente, sem forma de corrigir
-- pelo app.
--
-- RAIZ (medida, não deduzida): a coordenação já tinha feito a chamada dessa
-- aula pela tela própria dela (`app_registrar_chamada_agenda`, fonte
-- 'agenda_secretaria') um dia antes. A partir daí, NENHUMA correção do
-- professor — nem pela chamada em lote (`app_registrar_presencas_aula`), nem
-- pela confirmação do registro por áudio (`fabio_emitir_presenca_por_registro`
-- -> `fn_registrar_presencas_core`) — conseguia mudar aquele dado: o guard do
-- `on conflict` só perguntava "a fonte atual é forte?" (`fn_presenca_e_forte`),
-- um booleano só, sem ordem entre as fontes fortes. Uma vez ocupado por
-- QUALQUER fonte forte (inclusive a secretaria, que não estava na sala), o
-- slot travava pra sempre — mesmo pro professor que deu a aula.
--
-- Reproduzido ao vivo (rollback): chamar `fn_registrar_presencas_core` como o
-- professor, pedindo os dois alunos como presentes, devolvia `aplicado:true`
-- mas `inseridos:0, promovidos:0` — sucesso mentiroso, nada escrito.
--
-- CONSERTO: troca o booleano por uma PRECEDÊNCIA (`fn_presenca_precedencia`).
-- O professor (presencialmente na sala: chamada em lote, áudio, WhatsApp)
-- passa a poder corrigir uma entrada da secretaria E corrigir a si mesmo depois
-- (chamada -> áudio, ou um novo áudio). A secretaria continua sem poder pisar
-- numa decisão do professor (a régua é sempre >=, nunca <). E uma eventual
-- correção 'manual' (coordenação corrigindo em definitivo) continua acima de
-- todo mundo, inclusive do professor.
--
-- Escopo do fix: só os DOIS pontos que decidem "posso escrever por cima?" —
-- o guard do `on conflict` no core, e o atalho `chamada_ja_enviada` nas duas
-- portas do professor (app e WhatsApp/áudio). `fn_presenca_e_forte` continua
-- exatamente como está: ela responde "isto é presença humana de verdade?" e
-- essa pergunta segue certa pros outros 11 lugares que a chamam (health-score,
-- pendências, gêmeos, experimental). `app_registrar_chamada_agenda` (a tela da
-- coordenação) também não muda: ela já sobrescreve com trilha de auditoria
-- própria (`aluno_presenca_retificacoes`) de propósito.
--
-- Teste: 20260815010000_o_professor_corrige_a_propria_chamada.test.sql
-- Mutantes: scripts/mutantes-20260815010000.mjs

-- ── A régua nova: precedência, não booleano ─────────────────────────────────
create or replace function public.fn_presenca_precedencia(p_respondido_por text)
returns integer
language sql
immutable
parallel safe
set search_path to 'pg_catalog', 'public'
as $function$
  select case p_respondido_por
    when 'manual'               then 3
    when 'professor_la_teacher' then 2
    when 'fabio_audio'          then 2
    when 'professor_whatsapp'   then 2
    when 'agenda_secretaria'    then 1
    else 0
  end
$function$;

revoke all on function public.fn_presenca_precedencia(text) from public, anon;
grant execute on function public.fn_presenca_precedencia(text) to authenticated, service_role;

-- ── O core: escreve por cima quando a fonte nova tem precedência >= atual ──
-- Resto da função preservado byte a byte a partir de pg_get_functiondef; único
-- diff é a cláusula WHERE do on conflict.
create or replace function public.fn_registrar_presencas_core(p_aula_ancora_id integer, p_professor_id integer, p_alunos_ausentes integer[] DEFAULT '{}'::integer[], p_respondido_por text DEFAULT 'professor_la_teacher'::text, p_estrito boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_aula public.aulas_emusys%rowtype;
  v_roster_total integer;
  v_sem_vinculo integer;
  v_inseridos integer;
  v_promovidos integer;
  v_gemeos integer;
begin
  if p_respondido_por not in (
    'professor_la_teacher', 'fabio_audio', 'professor_whatsapp') then
    raise exception 'respondido_por_invalido: %', p_respondido_por;
  end if;
  select * into v_aula from public.aulas_emusys where id = p_aula_ancora_id;
  if not found then
    if p_estrito then raise exception 'aula_nao_encontrada'; end if;
    return jsonb_build_object('aula_id', p_aula_ancora_id,
      'aplicado', false, 'motivo', 'aula_nao_encontrada');
  end if;
  if coalesce(v_aula.cancelada, false) then
    if p_estrito then raise exception 'aula_cancelada'; end if;
    return jsonb_build_object('aula_id', v_aula.id,
      'aplicado', false, 'motivo', 'aula_cancelada');
  end if;
  if v_aula.professor_id is distinct from p_professor_id then
    if p_estrito then
      raise exception 'aula_nao_pertence_ao_professor' using errcode = '42501';
    end if;
    return jsonb_build_object('aula_id', v_aula.id,
      'aplicado', false, 'motivo', 'professor_divergente');
  end if;
  if p_estrito then
    if v_aula.data_hora_inicio > now() + interval '15 minutes' then
      raise exception 'chamada_ainda_nao_disponivel';
    end if;
    if coalesce(v_aula.data_hora_fim, v_aula.data_hora_inicio)
        < now() - (public.fn_janela_registro_dias() || ' days')::interval then
      raise exception 'janela_de_chamada_encerrada';
    end if;
  end if;

  select count(*), count(*) filter (where aluno_id is null)
    into v_roster_total, v_sem_vinculo
    from public.aula_alunos_emusys where aula_emusys_id = v_aula.id;
  if v_roster_total = 0 then
    if p_estrito then raise exception 'roster_nao_sincronizado'; end if;
    return jsonb_build_object('aula_id', v_aula.id,
      'aplicado', false, 'motivo', 'roster_nao_sincronizado');
  end if;
  if v_sem_vinculo > 0 then
    if p_estrito then raise exception 'roster_incompleto'; end if;
    return jsonb_build_object('aula_id', v_aula.id,
      'aplicado', false, 'motivo', 'roster_incompleto');
  end if;
  if exists (
    select 1 from unnest(coalesce(p_alunos_ausentes, '{}'::integer[])) a(aluno_id)
     where not exists (select 1 from public.aula_alunos_emusys r
                        where r.aula_emusys_id = v_aula.id
                          and r.aluno_id = a.aluno_id)
  ) then
    if p_estrito then raise exception 'aluno_ausente_fora_do_roster'; end if;
    return jsonb_build_object('aula_id', v_aula.id,
      'aplicado', false, 'motivo', 'aluno_ausente_fora_do_roster');
  end if;

  with up as (
    insert into public.aluno_presenca (
      aluno_id, aula_emusys_id, professor_id, unidade_id, data_aula,
      horario_aula, status, status_presenca, curso_nome, turma_nome,
      sala_nome, respondido_por, respondido_em)
    select distinct r.aluno_id, v_aula.id, p_professor_id, v_aula.unidade_id,
      v_aula.data_aula, (v_aula.data_hora_inicio at time zone 'America/Sao_Paulo')::time,
      case when r.aluno_id = any(coalesce(p_alunos_ausentes, '{}'::integer[]))
           then 'ausente' else 'presente' end,
      case when r.aluno_id = any(coalesce(p_alunos_ausentes, '{}'::integer[]))
           then 'falta' else 'presente' end,
      v_aula.curso_nome, v_aula.turma_nome, v_aula.sala_nome,
      p_respondido_por, now()
      from public.aula_alunos_emusys r
     where r.aula_emusys_id = v_aula.id and r.aluno_id is not null
    on conflict (aluno_id, aula_emusys_id) do update
      set status = excluded.status, status_presenca = excluded.status_presenca,
          respondido_por = excluded.respondido_por, respondido_em = excluded.respondido_em
      where public.fn_presenca_precedencia(excluded.respondido_por)
            >= public.fn_presenca_precedencia(aluno_presenca.respondido_por)
    returning (xmax = 0) as inserido
  )
  select count(*) filter (where inserido), count(*) filter (where not inserido)
    into v_inseridos, v_promovidos from up;

  v_gemeos := public.fn_sincronizar_gemeos_presenca(v_aula.id);
  return jsonb_build_object(
    'aula_id', v_aula.id, 'total_roster', v_roster_total,
    'inseridos', coalesce(v_inseridos, 0),
    'promovidos', coalesce(v_promovidos, 0),
    'ja_havia_forte', v_roster_total - coalesce(v_inseridos, 0)
      - coalesce(v_promovidos, 0),
    'gemeos_sincronizados', coalesce(v_gemeos, 0), 'aplicado', true);
end
$function$;

-- ── As duas portas do professor: o atalho "chamada já enviada" segue a MESMA
-- régua, senão o professor nunca chega a chamar o core acima. ──────────────

create or replace function public.app_registrar_presencas_aula(p_aula_emusys_id integer, p_alunos_ausentes integer[] DEFAULT '{}'::integer[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_prof integer := public.fn_professor_do_usuario();
  v_aula public.aulas_emusys%rowtype;
  v_turma_irma integer;
  v_roster_total integer;
  v_sem_vinculo integer;
  v_res jsonb;
begin
  if v_prof is null then
    raise exception 'sem_professor_vinculado' using errcode = '42501';
  end if;
  select * into v_aula from public.aulas_emusys where id = p_aula_emusys_id;
  if not found or v_aula.professor_id is distinct from v_prof then
    raise exception 'aula_nao_pertence_ao_professor' using errcode = '42501';
  end if;
  if coalesce(v_aula.cancelada, false) then raise exception 'aula_cancelada'; end if;
  if coalesce(v_aula.tipo, '') <> 'turma' then
    select t.id into v_turma_irma from public.aulas_emusys t
     where t.tipo = 'turma' and t.unidade_id = v_aula.unidade_id
       and t.data_hora_inicio = v_aula.data_hora_inicio
       and t.professor_id is not distinct from v_aula.professor_id
       and coalesce(t.cancelada, false) = false limit 1;
    if v_turma_irma is not null then
      raise exception 'chamada_somente_na_aula_ancora (use a aula % deste horario)', v_turma_irma;
    end if;
  end if;
  select count(*) filter (where aluno_id is not null),
         count(*) filter (where aluno_id is null)
    into v_roster_total, v_sem_vinculo
    from public.aula_alunos_emusys where aula_emusys_id = v_aula.id;
  if v_roster_total > 0 and v_sem_vinculo = 0 and not exists (
    select 1 from public.aula_alunos_emusys r
     where r.aula_emusys_id = v_aula.id and r.aluno_id is not null
       and not exists (
         select 1 from public.aluno_presenca ap
          where ap.aula_emusys_id = v_aula.id and ap.aluno_id = r.aluno_id
            and public.fn_presenca_precedencia(ap.respondido_por)
                >= public.fn_presenca_precedencia('professor_la_teacher'))) then
    return jsonb_build_object('aula_id', v_aula.id,
      'total_roster', v_roster_total, 'inseridos', 0,
      'ignorados_first_write_wins', v_roster_total,
      'ja_havia_registros', true, 'chamada_ja_enviada', true);
  end if;
  v_res := public.fn_registrar_presencas_core(
    v_aula.id, v_prof, p_alunos_ausentes, 'professor_la_teacher', true);
  return v_res || jsonb_build_object(
    'chamada_ja_enviada', false,
    'ignorados_first_write_wins', coalesce((v_res->>'total_roster')::int, 0)
      - coalesce((v_res->>'inseridos')::int, 0),
    'ja_havia_registros', (coalesce((v_res->>'total_roster')::int, 0)
      - coalesce((v_res->>'inseridos')::int, 0)) > 0);
end
$function$;

create or replace function public.fabio_registrar_presencas_aula(p_professor_id integer, p_aula_emusys_id integer, p_alunos_ausentes integer[] DEFAULT '{}'::integer[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_aula public.aulas_emusys%rowtype;
  v_turma_irma integer;
  v_roster_total integer;
  v_sem_vinculo integer;
  v_res jsonb;
begin
  select * into v_aula from public.aulas_emusys where id = p_aula_emusys_id;
  if not found or v_aula.professor_id is distinct from p_professor_id then
    raise exception 'aula_nao_pertence_ao_professor' using errcode = '42501';
  end if;
  if coalesce(v_aula.cancelada, false) then raise exception 'aula_cancelada'; end if;
  if coalesce(v_aula.tipo, '') <> 'turma' then
    select t.id into v_turma_irma from public.aulas_emusys t
     where t.tipo = 'turma' and t.unidade_id = v_aula.unidade_id
       and t.data_hora_inicio = v_aula.data_hora_inicio
       and t.professor_id is not distinct from v_aula.professor_id
       and coalesce(t.cancelada, false) = false limit 1;
    if v_turma_irma is not null then
      raise exception 'chamada_somente_na_aula_ancora (use a aula % deste horario)', v_turma_irma;
    end if;
  end if;
  select count(*) filter (where aluno_id is not null),
         count(*) filter (where aluno_id is null)
    into v_roster_total, v_sem_vinculo
    from public.aula_alunos_emusys where aula_emusys_id = v_aula.id;
  if v_roster_total > 0 and v_sem_vinculo = 0 and not exists (
    select 1 from public.aula_alunos_emusys r
     where r.aula_emusys_id = v_aula.id and r.aluno_id is not null
       and not exists (
         select 1 from public.aluno_presenca ap
          where ap.aula_emusys_id = v_aula.id and ap.aluno_id = r.aluno_id
            and public.fn_presenca_precedencia(ap.respondido_por)
                >= public.fn_presenca_precedencia('professor_la_teacher'))) then
    return jsonb_build_object('aula_id', v_aula.id,
      'total_roster', v_roster_total, 'inseridos', 0,
      'ignorados_first_write_wins', v_roster_total,
      'ja_havia_registros', true, 'chamada_ja_enviada', true);
  end if;
  v_res := public.fn_registrar_presencas_core(
    v_aula.id, p_professor_id, p_alunos_ausentes, 'professor_whatsapp', true);
  return v_res || jsonb_build_object(
    'chamada_ja_enviada', false,
    'ignorados_first_write_wins', coalesce((v_res->>'total_roster')::int, 0)
      - coalesce((v_res->>'inseridos')::int, 0),
    'ja_havia_registros', (coalesce((v_res->>'total_roster')::int, 0)
      - coalesce((v_res->>'inseridos')::int, 0)) > 0);
end
$function$;
