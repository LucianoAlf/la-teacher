-- Consulta letiva do professor (Fase 1): quem faltou no periodo, com os baldes
-- SEPARADOS. Read-only, security definer, so service_role. O p_professor_id vem
-- do BRIDGE (linha da mensagem), nunca do texto.
--
-- POR QUE OS BALDES NAO SE SOMAM. A vw_aluno_presenca_semantica_v1 implementa o
-- contrato v1.4: a ausencia do Emusys e PENDENCIA, nao falta ("o Emusys nao tem
-- falta, tem ausente"). Ate julho esse fantasma virava falta_confirmada
-- automatica — foram 3.066 "faltas" em junho que NENHUM humano afirmou. De
-- agosto em diante quem afirma falta e gente: agenda_secretaria (646 em agosto),
-- la_teacher (38), fabio_audio (10). O que sobra do Emusys fica em
-- 'registrada_inferida' / falta_provavel (205 entre 03 e 15/08).
--
-- Somar falta_provavel dentro de faltas reintroduziria exatamente a mentira que
-- o contrato eliminou — e o Fabio acusaria aluno real de uma falta que o banco
-- se recusa a afirmar.
--
-- E o balde provavel e identificado por situacao_chamada, NUNCA por
-- proveniencia='emusys': no dia em que a secretaria vereditar um desses casos, a
-- linha continua com proveniencia emusys e voltaria a ser contada como provavel
-- depois de ja ter virado falta confirmada.

create or replace function public.fabio_professor_presencas_periodo(
  p_professor_id integer,
  p_inicio       date,
  p_fim          date
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $fn$
begin
  if p_professor_id is null or p_inicio is null or p_fim is null then
    return jsonb_build_object('ok', false, 'motivo', 'parametros_obrigatorios');
  end if;
  if p_fim < p_inicio then
    return jsonb_build_object('ok', false, 'motivo', 'periodo_invertido');
  end if;
  if (p_fim - p_inicio) > 90 then
    return jsonb_build_object('ok', false, 'motivo', 'janela_maior_que_90_dias');
  end if;

  return (
    with base as (
      select v.data_aula,
             v.situacao_chamada,
             v.considera_presenca,
             v.considera_falta,
             -- O professor le NOME, nunca id de aluno. A projecao mora num
             -- lugar so: se mudar, muda para os quatro baldes de uma vez.
             jsonb_build_object('aluno', al.nome, 'data', v.data_aula, 'curso', v.curso_nome) as linha,
             jsonb_build_object('aluno', al.nome, 'data', v.data_aula, 'motivo', v.resultado_pedagogico) as linha_na
        from public.vw_aluno_presenca_semantica_v1 v
        join public.alunos al on al.id = v.aluno_id
       where v.professor_id = p_professor_id
         and v.data_aula between p_inicio and p_fim
    )
    select jsonb_build_object(
      'ok', true,
      'periodo', jsonb_build_object('inicio', p_inicio, 'fim', p_fim),
      'presentes', count(*) filter (where considera_presenca),
      'faltas', (
        select coalesce(jsonb_agg(linha order by data_aula, linha->>'aluno'), '[]'::jsonb)
          from base where considera_falta
      ),
      'falta_provavel', (
        select coalesce(jsonb_agg(linha order by data_aula, linha->>'aluno'), '[]'::jsonb)
          from base where situacao_chamada = 'registrada_inferida'
      ),
      'indeterminado', (
        select coalesce(jsonb_agg(linha order by data_aula, linha->>'aluno'), '[]'::jsonb)
          from base where situacao_chamada = 'indeterminada'
      ),
      'nao_aplicavel', (
        select coalesce(jsonb_agg(linha_na order by data_aula, linha_na->>'aluno'), '[]'::jsonb)
          from base where situacao_chamada = 'nao_aplicavel'
      )
    )
    from base
  );
end
$fn$;

comment on function public.fabio_professor_presencas_periodo(integer, date, date) is
  'Consulta letiva Fase 1: presencas do PROPRIO professor num periodo, com faltas/falta_provavel/indeterminado/nao_aplicavel SEPARADOS e jamais somados. Read-only, sem financeiro.';

revoke all on function public.fabio_professor_presencas_periodo(integer, date, date) from public, anon, authenticated;
grant execute on function public.fabio_professor_presencas_periodo(integer, date, date) to service_role;
