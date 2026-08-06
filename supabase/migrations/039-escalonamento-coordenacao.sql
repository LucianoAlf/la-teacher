-- 039 — quem passou do prazo sobe pra coordenacao
--
-- Desenho do Alfredo em
-- docs/2026-07-18-fabio-governanca-presenca-professor-alfredo.md:
--   1. fim do dia — Fabio cutuca o professor
--   2. manha seguinte — cutuca de novo
--   3. mais de 3 dias — o Fabio PARA e a bola vai pro grupo da coordenacao
--
-- POR QUE UMA FUNCAO, E NAO SELECT DIRETO NA VIEW
-- vw_presenca_pendencia e a fonte canonica (013) e continua sendo — mas ela
-- leva ~21s pra agregar por professor (medido em 05/08/2026: o EXISTS de
-- "aula individual dentro de turma" varre ~3,6M blocos). Via PostgREST isso
-- estoura o statement_timeout e volta 57014. Agregar aqui dentro, com timeout
-- proprio, mantem a fonte unica e tira o worker da linha de tiro.
--
-- A LENTIDAO DA VIEW E DIVIDA REGISTRADA, nao resolvida aqui: mexer no plano
-- dela agora seria mexer no que a coordenacao e o relatorio ja consomem, sem
-- teste, com a governanca parada. Ver task #82.

create or replace function public.fn_pendencias_escalonadas(p_dias integer default 3)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
set statement_timeout to '120s'
as $function$
declare
  v_linhas jsonb;
begin
  select coalesce(jsonb_agg(x order by x->>'pior_atraso' desc), '[]'::jsonb)
    into v_linhas
    from (
      select jsonb_build_object(
               'professor_id',   professor_id,
               'professor_nome', max(professor_nome),
               'unidade_nome',   max(unidade_nome),
               'alunos',         count(distinct aluno_id),
               'aulas',          count(distinct aula_id),
               'pior_atraso',    max(dias_em_atraso)
             ) as x
        from vw_presenca_pendencia
       where dias_em_atraso > p_dias
       group by professor_id
    ) s;

  return jsonb_build_object(
    'ok', true,
    'limite_dias', p_dias,
    'professores', jsonb_array_length(v_linhas),
    'linhas', v_linhas
  );
end
$function$;

revoke all on function public.fn_pendencias_escalonadas(integer) from public, anon, authenticated;
grant execute on function public.fn_pendencias_escalonadas(integer) to service_role;

comment on function public.fn_pendencias_escalonadas(integer) is
'Agrega vw_presenca_pendencia por professor acima do limite de dias (default 3), para o escalonamento do Fabio ao grupo da coordenacao. statement_timeout proprio porque a view custa ~21s.';
