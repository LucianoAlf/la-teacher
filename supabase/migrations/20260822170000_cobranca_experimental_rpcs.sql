-- RPCs de leitura da cobrança da experimental. Só leem a view da Task 1 —
-- nenhuma régua nova mora aqui (duas cópias da régua divergem em silêncio).

create or replace function public.fn_experimental_lembrete_alvos(p_minutos integer default 20)
returns jsonb language sql stable security definer set search_path to 'public'
as $$
  -- Janela folgada de propósito: se um tick do timer falhar, o próximo ainda
  -- alcança a aula, em vez de perder o lembrete pra sempre.
  --
  -- jsonb_agg(x order by ...) em vez de "order by" na subquery que alimenta
  -- o agg: um "order by" fora do jsonb_agg não é ordenação garantida do
  -- resultado agregado (achatamento de subquery ou plano paralelo pode
  -- descartá-lo) — a mensagem sairia fora de ordem sem nada quebrar.
  select jsonb_build_object('ok', true, 'linhas', coalesce(
    jsonb_agg(
      jsonb_build_object(
        'vinculo_id', v.vinculo_id, 'professor_id', v.professor_id,
        'nome_aluno', v.nome_aluno, 'curso_nome', v.curso_nome,
        'unidade_nome', v.unidade_nome,
        'hora_fim', to_char(v.data_hora_fim at time zone 'America/Sao_Paulo', 'HH24:MI'),
        'horas_em_atraso', v.horas_em_atraso
      )
      order by v.data_hora_fim desc
    ), '[]'::jsonb))
  from public.vw_experimental_pendencia v
  where v.data_hora_fim >= now() - make_interval(mins => greatest(coalesce(p_minutos, 20), 1));
$$;

comment on function public.fn_experimental_lembrete_alvos(integer) is
  'Aulas experimentais encerradas nos ultimos p_minutos, agrupadas por professor, pra disparar o lembrete de devolutiva. professor_id aqui e professores.id, NAO usuarios.id — os dois espacos colidem entre pessoas diferentes nesta base (ver vw_experimental_pendencia).';

create or replace function public.fn_experimental_pendencia_do_professor(p_professor_id integer)
returns jsonb language sql stable security definer set search_path to 'public'
as $$
  select jsonb_build_object('ok', true, 'linhas', coalesce(
    jsonb_agg(
      jsonb_build_object(
        'vinculo_id', v.vinculo_id, 'nome_aluno', v.nome_aluno,
        'curso_nome', v.curso_nome, 'unidade_nome', v.unidade_nome,
        'quando', to_char(v.data_hora_fim at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI'),
        'dias_em_atraso', v.dias_em_atraso
      )
      order by v.data_hora_fim desc
    ), '[]'::jsonb))
  from public.vw_experimental_pendencia v
  where v.professor_id = p_professor_id;
$$;

comment on function public.fn_experimental_pendencia_do_professor(integer) is
  'Tudo que esta pendente de devolutiva pro professor dado. p_professor_id e professores.id, NAO usuarios.id — join errado (usuarios.id) devolve a pendencia de OUTRA pessoa em silencio, sem erro (ja aconteceu: prof 10 = Isaque, usuario 10 = Jhonatan).';

create or replace function public.fn_experimental_escalonadas()
returns jsonb language sql stable security definer set search_path to 'public'
as $$
  select jsonb_build_object('ok', true,
                            'janela_dias', public.fn_janela_experimental_dias(),
                            'linhas', coalesce(
    jsonb_agg(
      jsonb_build_object(
        'vinculo_id', v.vinculo_id, 'nome_aluno', v.nome_aluno,
        'professor_nome', v.professor_nome, 'unidade_nome', v.unidade_nome,
        'curso_nome', v.curso_nome,
        'quando', to_char(v.data_hora_fim at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI'),
        'dias_em_atraso', v.dias_em_atraso
      )
      order by v.dias_em_atraso desc
    ), '[]'::jsonb))
  from public.vw_experimental_pendencia v
  where v.dias_em_atraso >= public.fn_janela_experimental_dias();
$$;

comment on function public.fn_experimental_escalonadas() is
  'O que passou da janela de devolutiva (fn_janela_experimental_dias), pra coordenacao encaminhar. Nao recebe professor_id — e visao de coordenacao, nao de professor. Mesma ressalva das outras duas: professor_id que aparece nas linhas de outras RPCs desta familia e professores.id, NAO usuarios.id.';
