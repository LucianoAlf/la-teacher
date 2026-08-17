-- CONSERTO da fabio_professor_presencas_periodo (substitui a de 20260817130000).
--
-- COMO APARECEU: conversando com o Fábio em shadow, na pergunta "quais alunos
-- faltaram semana passada" do prof. 35. A lista veio com "Gabriel Teixeira
-- Nogueira" DUAS vezes e "Lavynea dos Anjos" DUAS vezes, mesmo dia, mesmo curso.
--
-- A CAUSA e a mesma armadilha ja tratada na RPC de aulas, e eu deixei passar
-- aqui: desde 09/07 a mesma aula tem DUAS linhas (aula_emusys_id e id de
-- EVENTO). Medido:
--   Gabriel  -> aula_emusys_id 205410 e 205407, mas fn_aula_operacional_id = 205407 nos dois
--   Lavynea  -> aula_emusys_id 205448 e 205451, mas fn_aula_operacional_id = 205451 nos dois
--
-- O ESTRAGO era grande porque 'presentes' e contagem de linha:
--   professor 35: presentes 40 -> 23, faltas 7 -> 5, falta_provavel 6 -> 4
--   professor 36: presentes 61 -> 31, faltas 11 -> 9
-- Ou seja: o Fabio diria ao Valdo que 61 alunos estiveram presentes quando foram
-- 31, e citaria o mesmo aluno duas vezes na lista de falta.
--
-- Os testes antigos passaram porque eu afirmei a contagem CRUA da view — que e o
-- numero certo da view e o numero ERRADO pro professor. Quem pegou foi perguntar
-- pro Fabio, nao ler o codigo.
--
-- CONSERTO: uma linha por (aluno, aula operacional). O desempate prefere a linha
-- que TEM veredito (presenca ou falta) sobre a que nao tem, e depois e
-- deterministico por aula_emusys_id — nunca aleatorio.

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
    with bruto as (
      select v.aluno_id,
             coalesce(public.fn_aula_operacional_id(v.aula_emusys_id), v.aula_emusys_id) as aula_op,
             v.aula_emusys_id,
             v.data_aula,
             v.situacao_chamada,
             v.resultado_pedagogico,
             v.considera_presenca,
             v.considera_falta,
             v.curso_nome
        from public.vw_aluno_presenca_semantica_v1 v
       where v.professor_id = p_professor_id
         and v.data_aula between p_inicio and p_fim
    ),
    base as (
      select b.*,
             jsonb_build_object('aluno', al.nome, 'data', b.data_aula, 'curso', b.curso_nome) as linha,
             jsonb_build_object('aluno', al.nome, 'data', b.data_aula, 'motivo', b.resultado_pedagogico) as linha_na
        from bruto b
        join public.alunos al on al.id = b.aluno_id
    )
    -- O dedup e POR BALDE, nao atraves deles. A mesma (aluno, aula operacional)
    -- as vezes tem linhas com semanticas DIFERENTES — a Emily, em 11/08, tem uma
    -- falta_confirmada E uma aula_justificada. Isso e CONFLITO, nao duplicata, e
    -- resolver conflito nao e papel desta RPC: colapsar entre baldes apagaria o
    -- balde perdedor (medido: nao_aplicavel iria de 7 pra 0). O defeito que o
    -- Fabio me mostrou era o mesmo aluno repetido DENTRO do mesmo balde.
    select jsonb_build_object(
      'ok', true,
      'periodo', jsonb_build_object('inicio', p_inicio, 'fim', p_fim),
      'presentes', count(distinct (aluno_id, aula_op)) filter (where considera_presenca),
      'faltas', (
        select coalesce(jsonb_agg(linha order by data_aula, linha->>'aluno'), '[]'::jsonb)
          from (select distinct on (aluno_id, aula_op) aluno_id, aula_op, data_aula, linha
                  from base where considera_falta
                 order by aluno_id, aula_op, aula_emusys_id) q
      ),
      'falta_provavel', (
        select coalesce(jsonb_agg(linha order by data_aula, linha->>'aluno'), '[]'::jsonb)
          from (select distinct on (aluno_id, aula_op) aluno_id, aula_op, data_aula, linha
                  from base where situacao_chamada = 'registrada_inferida'
                 order by aluno_id, aula_op, aula_emusys_id) q
      ),
      'indeterminado', (
        select coalesce(jsonb_agg(linha order by data_aula, linha->>'aluno'), '[]'::jsonb)
          from (select distinct on (aluno_id, aula_op) aluno_id, aula_op, data_aula, linha
                  from base where situacao_chamada = 'indeterminada'
                 order by aluno_id, aula_op, aula_emusys_id) q
      ),
      'nao_aplicavel', (
        select coalesce(jsonb_agg(linha_na order by data_aula, linha_na->>'aluno'), '[]'::jsonb)
          from (select distinct on (aluno_id, aula_op) aluno_id, aula_op, data_aula, linha_na
                  from base where situacao_chamada = 'nao_aplicavel'
                 order by aluno_id, aula_op, aula_emusys_id) q
      )
    )
    from base
  );
end
$fn$;

comment on function public.fabio_professor_presencas_periodo(integer, date, date) is
  'Consulta letiva Fase 1: presencas do PROPRIO professor num periodo, UMA linha por (aluno, aula operacional), com faltas/falta_provavel/indeterminado/nao_aplicavel SEPARADOS. Read-only, sem financeiro.';

revoke all on function public.fabio_professor_presencas_periodo(integer, date, date) from public, anon, authenticated;
grant execute on function public.fabio_professor_presencas_periodo(integer, date, date) to service_role;
