-- 041 — o escalonamento cobra REGISTRO, nao presenca
--
-- Erro que esta migration conserta: a 039/040 liam vw_presenca_pendencia, que
-- responde "esta aula tem presenca de fonte forte?". Pergunta legitima, regua
-- errada pra governanca do professor.
--
-- Presenca e CONSEQUENCIA: nasce quando o professor lanca o conteudo, ou
-- quando a secretaria marca no Emusys. Cobrar por ela fazia o Fabio dizer ao
-- Matheus, na frente da coordenacao, que ele tinha 18 aulas atrasadas — quando
-- todas as 18 ja tinham presenca lancada pelo Emusys (fonte fraca pelo criterio
-- da Fase 2, mas dadas e marcadas na pratica). Cobranca errada no grupo queima
-- a governanca no primeiro uso.
--
-- A fonte certa ja existia: vw_registro_pendencia, com a coluna `cobravel` —
-- a mesma que fn_pendencias_do_professor usa com o comentario "nunca o
-- passivo". Medido para o professor 25 em 05/08/2026:
--     cobravel = true  ->  5 aulas, todas de 04/08   (o que se cobra)
--     cobravel = false -> 12 aulas, 29/06 a 09/07    (passivo, nao se cobra)
--
-- Agora as DUAS mensagens (professor e coordenacao) saem da mesma fonte e do
-- mesmo criterio. Enquanto eram duas, elas podiam discordar — e discordaram.

create or replace function public.fn_pendencias_escalonadas(
  p_dias         integer default 3,
  p_professor_id integer default null,
  p_max_aulas    integer default 12
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
set statement_timeout to '120s'
as $function$
declare
  v_out jsonb;
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
       and v.dias_em_atraso > p_dias
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
    'limite_dias', p_dias,
    'fonte', 'vw_registro_pendencia (cobravel)',
    'professores', jsonb_array_length(v_out),
    'linhas', v_out
  );
end
$function$;

revoke all on function public.fn_pendencias_escalonadas(integer,integer,integer) from public, anon, authenticated;
grant execute on function public.fn_pendencias_escalonadas(integer,integer,integer) to service_role;

comment on function public.fn_pendencias_escalonadas(integer,integer,integer) is
'Aulas COBRAVEIS sem registro de conteudo, acima do limite de dias, detalhadas por aula para a coordenacao encaminhar. Le vw_registro_pendencia (cobravel), a MESMA fonte de fn_pendencias_do_professor — presenca nao entra aqui: ela e consequencia do lancamento, nao o que se cobra.';
