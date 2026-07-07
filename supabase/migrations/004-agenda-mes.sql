-- =============================================================================
-- 004 · RPC de agenda por INTERVALO (app_minha_agenda_mes)
-- =============================================================================
-- Pré-requisito para a Home mostrar "meu mês": app_minha_agenda(p_data) só
-- retorna 1 dia. useSemana.ts hoje monta a faixa da semana com 7 chamadas em
-- paralelo (uma por dia) — não escala para 30-35 dias. Esta RPC devolve o
-- intervalo inteiro numa chamada só, mesma view/gate/formato da RPC de dia.
--
-- Diferença deliberada: filtra `cancelada = false`. app_minha_agenda(dia) não
-- filtra porque nunca precisou — presença nunca gravava aula cancelada. A
-- sync-grade-futura-emusys (migração 003) passou a gravar `cancelada=true`
-- para fantasmas (aula remarcada/cancelada), então essa RPC precisa excluir.
--
-- Nota de escopo: vw_fabio_aulas_contexto faz LEFT JOIN aluno_presenca — uma
-- turma com presença já registrada gera 1 linha POR ALUNO. Não afeta o uso
-- atual (mês à frente: aula futura ainda não tem aluno_presenca, 1 linha por
-- aula). Só vira relevante se esta RPC for reaproveitada para meses passados.
-- =============================================================================

create or replace function public.app_minha_agenda_mes(
  p_inicio date default current_date,
  p_fim date default current_date + 35
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare v_prof integer := public.fn_professor_do_usuario();
begin
  if v_prof is null then
    return jsonb_build_object('erro', 'sem_professor_vinculado');
  end if;

  if p_fim < p_inicio then
    raise exception 'p_fim (%) não pode ser anterior a p_inicio (%)', p_fim, p_inicio;
  end if;

  return (
    select jsonb_build_object(
      'inicio', p_inicio,
      'fim', p_fim,
      'total', count(*),
      'aulas', coalesce(jsonb_agg(to_jsonb(v) order by v.data_hora_inicio), '[]'::jsonb))
    from public.vw_fabio_aulas_contexto v
    where v.professor_id = v_prof
      and v.data_aula between p_inicio and p_fim
      and coalesce(v.cancelada, false) = false
  );
end
$function$;

revoke all on function public.app_minha_agenda_mes(date, date) from public, anon;
grant execute on function public.app_minha_agenda_mes(date, date) to authenticated;
