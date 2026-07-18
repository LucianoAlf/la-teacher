-- 014-fabio-presencas-pendentes-professor.sql  (Fase 3 — lado professor / Fábio)
-- RPC read-only: pendência de presença de UM professor, já separada em
--   dentro_janela      (dias_em_atraso <= 3)  → detalhado, com a lista de alunos (o Fábio cutuca)
--   escalar_coordenacao (dias_em_atraso >  3)  → resumo por aula (qtd + atraso) → sobe pra coordenação
-- Lê SÓ a vw_presenca_pendencia (fonte única compartilhada com a Sol). Irmã da
-- fabio_pendencias_professor (registro) — o Fábio combina as duas no Hermes pra montar o DM.
--
-- ⚠️ DECISÃO A CONFIRMAR NO REVIEW: excluí `justificada` (não se cobra falta já abonada
--    pela coordenação). Se quiser incluir, é só tirar o `and not justificada`.
--
-- Backend-only: revogada de anon/authenticated, liberada só pro service_role (Fábio/Hermes).

create or replace function public.fabio_presencas_pendentes_professor(p_professor_id integer)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $function$
  with base as (
    select *
    from public.vw_presenca_pendencia
    where professor_id = p_professor_id
      and not justificada
  ),
  janela as (
    select data_hora_inicio, data_aula, hora, curso_nome,
           jsonb_agg(
             jsonb_build_object('aluno_id', aluno_id, 'nome', aluno_primeiro_nome, 'dias_em_atraso', dias_em_atraso)
             order by aluno_nome
           ) as alunos
    from base
    where dias_em_atraso <= 3
    group by data_hora_inicio, data_aula, hora, curso_nome, aula_id
  ),
  escala as (
    select data_hora_inicio, data_aula, hora,
           count(distinct aluno_id) as qtd_alunos,
           max(dias_em_atraso)      as dias_em_atraso
    from base
    where dias_em_atraso > 3
    group by data_hora_inicio, data_aula, hora, aula_id
  )
  select jsonb_build_object(
    'professor_id', p_professor_id,
    'dentro_janela', coalesce((
      select jsonb_agg(
        jsonb_build_object('data_aula', data_aula, 'hora', hora, 'curso_nome', curso_nome, 'alunos', alunos)
        order by data_hora_inicio desc)
      from janela), '[]'::jsonb),
    'escalar_coordenacao', coalesce((
      select jsonb_agg(
        jsonb_build_object('data_aula', data_aula, 'hora', hora, 'qtd_alunos', qtd_alunos, 'dias_em_atraso', dias_em_atraso)
        order by data_hora_inicio desc)
      from escala), '[]'::jsonb)
  );
$function$;

revoke all on function public.fabio_presencas_pendentes_professor(integer) from public, anon, authenticated;
grant execute on function public.fabio_presencas_pendentes_professor(integer) to service_role;
