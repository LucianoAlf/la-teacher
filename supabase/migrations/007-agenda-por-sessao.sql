-- ============================================================================
-- LA TEACHER · MIGRAÇÃO 007 — AGENDA POR SESSÃO (contrato v3, Sprint 3)
-- Aplicada no banco como: la_teacher_008 → 008b → 008c (esta é a 008c vigente).
-- Espelho de documentação extraído do banco em 08/07/2026.
--
-- POR QUÊ: o Emusys representa a mesma aula real de formas redundantes —
-- 1 aula tipo 'turma' (explodida em 1 linha/aluno na presença) + 1 aula
-- 'individual' POR aluno no mesmo horário (a "aula do aluno", com matrícula).
-- A UI mostrava tudo cru (15 linhas p/ 6 aulas). Esta RPC entrega SESSÕES:
--   · 1 sessão de turma por aula tipo 'turma' real (>1 aluno na presença)
--   · alunos da turma casados com a aula individual deles (aula_id_alvo) —
--     é NELA que a fatia do Fábio grava (nunca na âncora: evita vazamento)
--   · individuais avulsas (aluno fora de turma no slot) viram sessões próprias
--   · presença REAL (aluno_presenca.status) · tem_registro considera
--     anotacoes_fabio OU anotacoes (legado) · data_hora_fim p/ "rolando agora"
--
-- Casos-limite documentados:
--   · turma com 1 aluno na presença (having >1) não vira sessão de turma;
--     aparece pela individual paralela. Turma de 1 SEM individual → some
--     da agenda (não ocorre na carteira-piloto; evolução futura).
--   · "ausente" em aula futura = presença não lançada, NÃO "faltou"
--     (sync de presença é retroativo) — distinção é da UI.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.app_minha_agenda_sessao(p_data date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_prof integer := public.fn_professor_do_usuario();
begin
  if v_prof is null then return jsonb_build_object('erro','sem_professor_vinculado'); end if;

  return coalesce((
    with aulas_prof as (
      select ae.id, ae.data_hora_inicio, ae.data_hora_fim, ae.turma_nome, ae.tipo,
             ae.curso_nome, ae.qtd_alunos, ae.anotacoes_fabio, ae.anotacoes
      from public.aulas_emusys ae
      where ae.professor_id = v_prof and ae.data_aula = p_data and ae.cancelada = false
    ),
    -- registro/presença de cada aula individual, por aluno (pra casar com o aluno da turma)
    ind_por_aluno as (
      select ai.data_hora_inicio, ap.aluno_id, ai.id as aula_individual,
             coalesce(ap.status,'presente') as presenca,
             ((ai.anotacoes_fabio is not null and btrim(ai.anotacoes_fabio)<>'')
               or (ai.anotacoes is not null and btrim(ai.anotacoes)<>'')) as tem_reg
      from aulas_prof ai
      join public.aluno_presenca ap on ap.aula_emusys_id = ai.id
      where ai.tipo = 'individual'
    ),
    -- SESSÕES DE TURMA: uma por aula tipo 'turma' com >1 aluno na presença
    turmas as (
      select t.id as aula_turma, t.data_hora_inicio, t.data_hora_fim, t.curso_nome, t.turma_nome,
             count(distinct ap.aluno_id) as n_alunos
      from aulas_prof t
      join public.aluno_presenca ap on ap.aula_emusys_id = t.id
      where t.tipo = 'turma'
      group by t.id, t.data_hora_inicio, t.data_hora_fim, t.curso_nome, t.turma_nome
      having count(distinct ap.aluno_id) > 1
    ),
    turmas_json as (
      select tu.aula_turma, tu.data_hora_inicio, tu.data_hora_fim, tu.curso_nome, tu.turma_nome, tu.n_alunos,
        jsonb_agg(
          jsonb_build_object(
            'aluno_id', a.id, 'nome', a.nome,
            'aula_id_alvo', coalesce(ipa.aula_individual, tu.aula_turma),
            'presenca', coalesce(ipa.presenca, tap.status, 'presente'),
            'tem_registro', coalesce(ipa.tem_reg, false)
          ) order by a.nome
        ) as alunos,
        count(*) filter (where coalesce(ipa.tem_reg,false)) as n_registradas
      from turmas tu
      join public.aluno_presenca tap on tap.aula_emusys_id = tu.aula_turma
      join public.alunos a on a.id = tap.aluno_id
      left join ind_por_aluno ipa on ipa.data_hora_inicio = tu.data_hora_inicio and ipa.aluno_id = a.id
      group by tu.aula_turma, tu.data_hora_inicio, tu.data_hora_fim, tu.curso_nome, tu.turma_nome, tu.n_alunos
    ),
    -- alunos que JÁ estão em alguma turma (pra não duplicar como individual)
    alunos_em_turma as (
      select tu.data_hora_inicio, ap.aluno_id
      from turmas tu join public.aluno_presenca ap on ap.aula_emusys_id = tu.aula_turma
    ),
    -- SESSÕES INDIVIDUAIS: aulas individuais cujo aluno não está numa turma no mesmo horário
    individuais as (
      select ai.id as aula_individual, ai.data_hora_inicio, ai.data_hora_fim, ai.curso_nome, ai.turma_nome,
             ap.aluno_id, a.nome as aluno_nome, coalesce(ap.status,'presente') as presenca,
             ((ai.anotacoes_fabio is not null and btrim(ai.anotacoes_fabio)<>'')
               or (ai.anotacoes is not null and btrim(ai.anotacoes)<>'')) as tem_reg
      from aulas_prof ai
      join public.aluno_presenca ap on ap.aula_emusys_id = ai.id
      join public.alunos a on a.id = ap.aluno_id
      where ai.tipo = 'individual'
        and not exists (select 1 from alunos_em_turma et
                        where et.data_hora_inicio = ai.data_hora_inicio and et.aluno_id = ap.aluno_id)
    ),
    -- montar sessões (turmas + individuais) num array só
    todas as (
      select data_hora_inicio, data_hora_fim, curso_nome, turma_nome, 'turma' as tipo,
             aula_turma as aula_id_ancora, n_alunos, n_registradas, alunos
      from turmas_json
      union all
      select data_hora_inicio, data_hora_fim, curso_nome, turma_nome, 'individual' as tipo,
             aula_individual as aula_id_ancora, 1 as n_alunos,
             (case when tem_reg then 1 else 0 end) as n_registradas,
             jsonb_build_array(jsonb_build_object(
               'aluno_id', aluno_id, 'nome', aluno_nome, 'aula_id_alvo', aula_individual,
               'presenca', presenca, 'tem_registro', tem_reg)) as alunos
      from individuais
    )
    select jsonb_agg(
      jsonb_build_object(
        'hora', to_char(data_hora_inicio at time zone 'America/Sao_Paulo','HH24:MI'),
        'hora_fim', to_char(data_hora_fim at time zone 'America/Sao_Paulo','HH24:MI'),
        'data_hora_inicio', data_hora_inicio,
        'data_hora_fim', data_hora_fim,
        'curso', curso_nome,
        'turma_nome', turma_nome,
        'tipo', tipo,
        'aula_id_ancora', aula_id_ancora,
        'n_alunos', n_alunos,
        'n_registradas', n_registradas,
        'alunos', alunos
      ) order by data_hora_inicio, tipo
    )
    from todas
  ), '[]'::jsonb);
end $function$;

revoke all on function public.app_minha_agenda_sessao(date) from public, anon;
grant execute on function public.app_minha_agenda_sessao(date) to authenticated;
