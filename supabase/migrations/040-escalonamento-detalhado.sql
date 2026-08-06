-- 040 — o escalonamento precisa ser ENCAMINHAVEL
--
-- A 039 mandava so o resumo ("19 alunos, ha 37 dias"). Nao serve: a
-- coordenacao copia a mensagem do grupo e encaminha pro professor, e um
-- resumo nao diz o que ele tem que fazer. Quem recebe o encaminhamento
-- precisa ver aula, horario, curso e NOME DO ALUNO — os mesmos dados que
-- estariam na cobranca dele.
--
-- Achado do Alf em 05/08/2026, olhando a primeira mensagem real no grupo.

create or replace function public.fn_pendencias_escalonadas(
  p_dias        integer default 3,
  p_professor_id integer default null,
  p_max_aulas   integer default 12
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
    select professor_id, professor_nome, unidade_nome,
           aula_id, data_aula, hora, curso_nome, turma_nome,
           aluno_nome, dias_em_atraso
      from vw_presenca_pendencia
     where dias_em_atraso > p_dias
       and (p_professor_id is null or professor_id = p_professor_id)
  ),
  por_aula as (
    select professor_id, max(professor_nome) as professor_nome,
           unidade_nome,
           aula_id, max(data_aula) as data_aula, max(hora) as hora,
           max(curso_nome) as curso_nome, max(turma_nome) as turma_nome,
           max(dias_em_atraso) as dias_em_atraso,
           -- nome COMPLETO: quem recebe o encaminhamento precisa identificar
           -- o aluno, e primeiro nome repete demais numa escola.
           jsonb_agg(distinct aluno_nome) as alunos
      from base
     group by professor_id, aula_id, unidade_nome
  ),
  ranqueada as (
    select *, row_number() over (
             partition by professor_id
             order by data_aula desc, hora desc) as rn,
           count(*) over (partition by professor_id) as total_aulas
      from por_aula
  )
  select coalesce(jsonb_agg(p order by p->>'pior_atraso' desc), '[]'::jsonb)
    into v_out
    from (
      select jsonb_build_object(
               'professor_id',   professor_id,
               'professor_nome', max(professor_nome),
               -- unidade vai POR AULA: 26 dos 42 professores dao aula em mais
               -- de uma unidade, e um max() aqui carimbaria a errada na
               -- mensagem que a coordenacao vai encaminhar.
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
                   order by data_aula desc, hora)
             ) as p
        from ranqueada
       where rn <= p_max_aulas
       group by professor_id
    ) s;

  return jsonb_build_object(
    'ok', true,
    'limite_dias', p_dias,
    'professores', jsonb_array_length(v_out),
    'linhas', v_out
  );
end
$function$;

revoke all on function public.fn_pendencias_escalonadas(integer,integer,integer) from public, anon, authenticated;
grant execute on function public.fn_pendencias_escalonadas(integer,integer,integer) to service_role;

-- A assinatura de 1 argumento da 039 sai de cena: duas versoes conviveriam e o
-- worker poderia chamar a antiga sem ninguem perceber.
drop function if exists public.fn_pendencias_escalonadas(integer);

comment on function public.fn_pendencias_escalonadas(integer,integer,integer) is
'Pendencias acima do limite de dias, DETALHADAS por aula (curso, horario, nomes dos alunos), para a coordenacao encaminhar ao professor. p_max_aulas limita quantas aulas por professor entram na mensagem.';
