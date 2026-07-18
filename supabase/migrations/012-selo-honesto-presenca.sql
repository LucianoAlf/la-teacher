-- 012-selo-honesto-presenca.sql  (Fase 2 — selo honesto de chamada)
-- Hoje o app decide "chamada feita" com QUALQUER linha de presença (ap.id is not null),
-- inclusive o DEFAULT do Emusys. Medição em prod (30d, aulas encerradas c/ roster completo):
-- ~4.254 de ~4.266 aulas "verdes" eram fantasma (só emusys); 11 honestas no sistema inteiro.
--
-- Este patch faz o RPC da agenda contar só FONTE FORTE. O cliente NÃO muda de lógica:
-- chamadaCompleta (sessao.ts) e o "N de M" (SessaoRow) já leem tem_presenca_registrada /
-- n_registradas — ficam honestos sozinhos.
--
-- ⚠️ app_minha_agenda_sessao é sensível. O corpo abaixo é o ATUAL, verbatim, com só
--    DUAS mudanças (marcadas com  -- <<< FASE 2):
--      (a) n_registradas              -> count(distinct aluno) filter (forte)
--      (b) tem_presenca_registrada    -> ap.id not null AND forte
--    `create or replace` PRESERVA os grants existentes.
--
-- Precedência (mesma da Fase 1 / migration 009):
--   FORTE = professor_la_teacher, fabio_audio, manual, professor_whatsapp
--   FRACA = emusys, sistema, null

-- =====================================================================================
-- 1) Fonte ÚNICA da regra forte/fraca — imutável, reutilizável por RPC/analytics.
-- =====================================================================================
create or replace function public.fn_presenca_e_forte(p_respondido_por text)
returns boolean
language sql immutable parallel safe
as $function$
  select coalesce(
    p_respondido_por in ('professor_la_teacher','fabio_audio','manual','professor_whatsapp'),
    false)
$function$;

-- =====================================================================================
-- 2) RPC da agenda — source-aware. Corpo atual, verbatim, exceto as 2 linhas <<< FASE 2.
-- =====================================================================================
create or replace function public.app_minha_agenda_sessao(p_data date default current_date)
returns jsonb
language plpgsql stable security definer set search_path to 'public'
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
        and ae.cancelada = false
    ), slots as (
      select
        data_hora_inicio,
        data_hora_fim,
        (array_agg(id order by case when tipo = 'turma' then 0 else 1 end, id))[1] as aula_id_ancora
      from aulas_dia
      group by data_hora_inicio, data_hora_fim
    ), ancoras as (
      select ae.*
      from slots s
      join aulas_dia ae on ae.id = s.aula_id_ancora
    )
    select jsonb_agg(
      jsonb_build_object(
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
        'roster_incompleto', coalesce(roster.n_sem_vinculo, 0) > 0,
        'alunos', coalesce(roster.alunos, '[]'::jsonb)
      )
      order by ae.data_hora_inicio, ae.id
    )
    from ancoras ae
    left join lateral (
      select
        count(*) as n_alunos,
        -- <<< FASE 2 (a): só FONTE FORTE, distinct por aluno (trava defensiva).
        count(distinct ap.aluno_id) filter (where public.fn_presenca_e_forte(ap.respondido_por)) as n_registradas,
        count(*) filter (where r.aluno_id is null) as n_sem_vinculo,
        bool_or(nullif(btrim(coalesce(aula_alvo.anotacoes_fabio, '')), '') is not null) as tem_registro,
        jsonb_agg(
          jsonb_build_object(
            'aluno_id', r.aluno_id,
            'nome', r.aluno_nome,
            'aula_id_alvo', coalesce(aula_alvo.id, ae.id),
            'presenca', coalesce(
              ap.status_presenca,
              case ap.status when 'presente' then 'presente' when 'ausente' then 'falta' end,
              'a_confirmar'
            ),
            -- <<< FASE 2 (b): "chamada feita" deste aluno = presença de FONTE FORTE (não o default Emusys).
            'tem_presenca_registrada', (ap.id is not null and public.fn_presenca_e_forte(ap.respondido_por)),
            'tem_registro', nullif(btrim(coalesce(aula_alvo.anotacoes_fabio, '')), '') is not null,
            'justificada', coalesce(adm.justificada, false)
          )
          order by r.aluno_nome
        ) as alunos
      from public.aula_alunos_emusys r
      left join public.aluno_presenca ap
        on ap.aula_emusys_id = ae.id
       and ap.aluno_id = r.aluno_id
      left join public.aluno_presenca_administrativo adm
        on adm.aula_emusys_id = ae.id
       and adm.aluno_id = r.aluno_id
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
      where r.aula_emusys_id = ae.id
    ) roster on true
  ), '[]'::jsonb);
end;
$function$;
