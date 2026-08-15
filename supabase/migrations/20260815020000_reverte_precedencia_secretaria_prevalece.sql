-- REVERSÃO da 20260815010000.
--
-- Eu inverti uma REGRA DE NEGÓCIO da casa achando que era defeito técnico.
-- A regra real, confirmada pelo Alf em 15/08/2026:
--
--   A SECRETARIA é quem dá presença (lança no Emusys / LA Report), e é a
--   resposta dela que PREVALECE. O professor lança CONTEÚDO — o relatório da
--   aula. O professor PODE dar presença, dentro da janela dele, mas não
--   sobrescreve a resposta da secretaria. Se ele discorda, REPORTA à
--   secretaria e ela corrige na fonte.
--
-- Ou seja: o `first write wins` entre fontes fortes é INTENCIONAL, não bug.
-- Esta migration devolve, byte a byte, o corpo que as três funções tinham
-- antes da minha alteração, e remove a régua de precedência que eu inventei.
--
-- O relato do Valdo continua valendo como pendência — mas é OUTRO problema,
-- de exibição/sincronismo, não de precedência: quando a secretaria já deu a
-- presença, o app do professor tem que MOSTRAR aquela presença já dada (em
-- tempo real), pra ele não precisar lançar de novo na hora do relatório.
--
-- Teste: 20260815020000_reverte_precedencia_secretaria_prevalece.test.sql

drop function if exists public.fn_presenca_precedencia(text);

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
      where not public.fn_presenca_e_forte(aluno_presenca.respondido_por)
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
            and public.fn_presenca_e_forte(ap.respondido_por))) then
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
            and public.fn_presenca_e_forte(ap.respondido_por))) then
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
