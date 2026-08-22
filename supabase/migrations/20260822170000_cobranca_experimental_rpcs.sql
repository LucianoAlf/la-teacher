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
  -- Ruling 17 (22/08/2026): o corte pela janela mora AQUI, na mesma funcao
  -- que fn_experimental_escalonadas usa pro lado da coordenacao
  -- (fn_janela_experimental_dias), nao numa variavel de ambiente do worker
  -- Python. As duas janelas (aluno: FABIO_ESCALONAMENTO_DIAS: registro;
  -- experimental: fn_janela_experimental_dias) sao botoes INDEPENDENTES que
  -- so batem em valor hoje por coincidencia (3 e 3) — se o worker filtrasse
  -- em Python por ESCALONAMENTO_DIAS, mudar essa env var pra trilha do aluno
  -- mudaria em silencio ate onde o professor e cobrado pela experimental, e
  -- a Task 5 (que le fn_janela_experimental_dias direto) continuaria
  -- escalando no valor antigo — a mesma cobranca em dobro que este filtro
  -- existe pra evitar, so que sem ninguem perceber a divergencia. Fonte
  -- unica: so fn_janela_experimental_dias() decide as duas pontas.
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
  where v.professor_id = p_professor_id
    and v.dias_em_atraso < public.fn_janela_experimental_dias();
$$;

comment on function public.fn_experimental_pendencia_do_professor(integer) is
  'O que esta pendente de devolutiva pro professor dado E AINDA DENTRO da janela (dias_em_atraso < fn_janela_experimental_dias()) — Ruling 17, 22/08/2026. Quem passou da janela ja aparece em fn_experimental_escalonadas() pra coordenacao; cobrar aqui tambem seria cobranca em dobro sem ninguem assumir, exatamente o que o comentario da funcao acima explica. NAO filtrar de novo em Python: mudar a janela e sempre mudar fn_janela_experimental_dias(), nunca uma env var do worker — as duas pontas (aqui e o escalonamento) tem que ler a MESMA fonte. p_professor_id e professores.id, NAO usuarios.id — join errado (usuarios.id) devolve a pendencia de OUTRA pessoa em silencio, sem erro (ja aconteceu: prof 10 = Isaque, usuario 10 = Jhonatan).';

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
      -- dias_em_atraso e floor(epoch/86400): granularidade de dia inteiro,
      -- entao empate e a regra, nao a excecao. Sem desempate por vinculo_id
      -- o plano decide a ordem entre empatados, e isso muda a mensagem sem
      -- nada quebrar.
      order by v.dias_em_atraso desc, v.vinculo_id
    ), '[]'::jsonb))
  from public.vw_experimental_pendencia v
  where v.dias_em_atraso >= public.fn_janela_experimental_dias();
$$;

comment on function public.fn_experimental_escalonadas() is
  'O que passou da janela de devolutiva (fn_janela_experimental_dias), pra coordenacao encaminhar. Nao recebe professor_id — e visao de coordenacao, nao de professor. Mesma ressalva das outras duas: professor_id que aparece nas linhas de outras RPCs desta familia e professores.id, NAO usuarios.id.';
