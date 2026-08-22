-- RPCs de leitura da cobrança da experimental. Só leem a view da Task 1 —
-- nenhuma régua nova mora aqui (duas cópias da régua divergem em silêncio).

create or replace function public.fn_experimental_lembrete_alvos(p_minutos integer default 20)
returns jsonb language sql stable security definer set search_path to 'public'
as $$
  -- Janela folgada de propósito: se um tick do timer falhar, o próximo ainda
  -- alcança a aula, em vez de perder o lembrete pra sempre.
  select jsonb_build_object('ok', true, 'linhas', coalesce(jsonb_agg(x), '[]'::jsonb))
  from (
    select jsonb_build_object(
      'vinculo_id', v.vinculo_id, 'professor_id', v.professor_id,
      'nome_aluno', v.nome_aluno, 'curso_nome', v.curso_nome,
      'unidade_nome', v.unidade_nome,
      'hora_fim', to_char(v.data_hora_fim at time zone 'America/Sao_Paulo', 'HH24:MI'),
      'horas_em_atraso', v.horas_em_atraso
    ) as x
    from public.vw_experimental_pendencia v
    where v.data_hora_fim >= now() - make_interval(mins => greatest(coalesce(p_minutos, 20), 1))
    order by v.data_hora_fim desc
  ) s;
$$;

create or replace function public.fn_experimental_pendencia_do_professor(p_professor_id integer)
returns jsonb language sql stable security definer set search_path to 'public'
as $$
  select jsonb_build_object('ok', true, 'linhas', coalesce(jsonb_agg(x), '[]'::jsonb))
  from (
    select jsonb_build_object(
      'vinculo_id', v.vinculo_id, 'nome_aluno', v.nome_aluno,
      'curso_nome', v.curso_nome, 'unidade_nome', v.unidade_nome,
      'quando', to_char(v.data_hora_fim at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI'),
      'dias_em_atraso', v.dias_em_atraso
    ) as x
    from public.vw_experimental_pendencia v
    where v.professor_id = p_professor_id
    order by v.data_hora_fim desc
  ) s;
$$;

create or replace function public.fn_experimental_escalonadas()
returns jsonb language sql stable security definer set search_path to 'public'
as $$
  select jsonb_build_object('ok', true,
                            'janela_dias', public.fn_janela_experimental_dias(),
                            'linhas', coalesce(jsonb_agg(x), '[]'::jsonb))
  from (
    select jsonb_build_object(
      'vinculo_id', v.vinculo_id, 'nome_aluno', v.nome_aluno,
      'professor_nome', v.professor_nome, 'unidade_nome', v.unidade_nome,
      'curso_nome', v.curso_nome,
      'quando', to_char(v.data_hora_fim at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI'),
      'dias_em_atraso', v.dias_em_atraso
    ) as x
    from public.vw_experimental_pendencia v
    where v.dias_em_atraso >= public.fn_janela_experimental_dias()
    order by v.dias_em_atraso desc
  ) s;
$$;
