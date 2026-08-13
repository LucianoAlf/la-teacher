-- Uma régua só de precedência
--
-- AUDITORIA DAS PORTAS DE PRESENÇA (F-C, 13/08/2026). O Alf avisou que o motor
-- do WhatsApp passou a gravar aula com baixa automática de presença, igual ao
-- app -- e perguntou se a régua de precedência valia para as duas portas.
--
-- Auditado: **vale**. As duas convergem no mesmo core.
--   app do professor -> app_registrar_presencas_aula   -> fn_registrar_presencas_core
--   WhatsApp / audio -> fabio_emitir_presenca_por_registro -> fn_registrar_presencas_core
-- E o core so sobrescreve fonte fraca; nunca pisa em decisao humana.
--
-- A terceira porta, `app_registrar_chamada_agenda` (a da secretaria, 889
-- linhas e a segunda maior fonte), NAO passa pelo core: ela insere direto e
-- tem regua PROPRIA (`v_humanos`). Conferido: a lista dela e IDENTICA a de
-- `fn_presenca_e_forte`. Nao ha defeito vivo.
--
-- O QUE ESTE ARQUIVO CONSERTA. A mesma regra estava escrita em TRES lugares,
-- e de duas formas incompativeis:
--
--   fn_presenca_e_forte          -> lista POSITIVA (5 fontes fortes)
--   app_registrar_chamada_agenda -> lista POSITIVA (as mesmas 5)
--   fn_registrar_presencas_core  -> lista NEGATIVA: protegia tudo que nao
--                                   fosse ('emusys','sistema')
--
-- Hoje elas concordam so porque o CHECK de `aluno_presenca.respondido_por`
-- fecha o vocabulario em 7 valores, e 5 fortes + 2 fracos sao exatamente
-- complementares. No dia em que alguem acrescentar UMA fonte ao CHECK, o core
-- passa a trata-la como FORTE em silencio -- protegendo do sobrescrito algo
-- que a regua canonica considera fraco. Lista negativa envelhece sozinha.
--
-- O core passa a perguntar para a regua em vez de repetir a lista.
-- `fn_presenca_e_forte(null)` devolve false (medido), entao a clausula nova
-- cobre exatamente os mesmos casos de hoje: null, emusys e sistema.
--
-- Resto da funcao preservado byte a byte a partir de pg_get_functiondef.

CREATE OR REPLACE FUNCTION public.fn_registrar_presencas_core(p_aula_ancora_id integer, p_professor_id integer, p_alunos_ausentes integer[] DEFAULT '{}'::integer[], p_respondido_por text DEFAULT 'professor_la_teacher'::text, p_estrito boolean DEFAULT true)
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
$function$
;
