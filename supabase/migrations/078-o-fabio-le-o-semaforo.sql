-- 078 — o Fábio passa a LER o semáforo (até aqui ele só cobrava)
--
-- MEDIDO EM 09/08/2026, grep na VPS (`~/.hermes` e `~/fabio-chat-bridge`): o
-- único arquivo que tocava `aluno_feedback_professor` era o
-- `fabio_notification_worker.py` — a COBRANÇA. Nada colocava a resposta no
-- contexto dele. Ou seja: o Fábio pedia o feedback todo mês e, no dia seguinte,
-- não sabia o que tinha sido respondido. Perguntar "como está a Amanda?" e
-- receber silêncio sobre a resposta que o próprio Fábio cobrou é o pior tipo de
-- buraco — ele parece desatento justamente onde insistiu.
--
-- E o risco não é só parecer bobo: o Fábio NEGA o que não vê (a lição de
-- `contexto-ausente-vira-negativa-afirmada`). Sem esta migration ele diria
-- "não tenho registro de feedback dela" sobre um aluno que o professor marcou
-- em vermelho na véspera.
--
-- ONDE ENTRA: `fabio_prontuario_aluno` — a porta de leitura do aluno, a mesma
-- que a skill `consultar-prontuario-aluno` manda usar. Assim o semáforo chega
-- pelo caminho que já existe, em vez de virar uma consulta nova que só o Fábio
-- lembra de fazer.
--
-- A FRONTEIRA, QUE É O PONTO DELICADO
-- Esta RPC é a porta do PROFESSOR (ela já exige `p_professor_id` e explode sem
-- ele). O semáforo entra com o MESMO escopo: `professor_id = p_professor_id`.
-- O professor lê o que ELE respondeu — nunca o coração nem a observação de um
-- colega sobre o mesmo aluno. Isso é a decisão de 09/08 sobre a fronteira do
-- Fábio ("o professor não alcança dado de colega") aplicada a um dado novo, e o
-- mutante V2 desta migration existe só pra guardar essa linha.
--
-- PESSOA, NÃO LINHA: `alunos.id` é matrícula. A mesma criança com dois cursos
-- tem duas linhas, e o professor pode ter respondido em qualquer uma delas.
-- Por isso a busca usa `aluno_ids_da_pessoa` — a resolução que o próprio
-- `fn_prontuario_aluno_interno` já devolve — e não o `p_aluno_id` que veio na
-- pergunta. Medido: existem pessoas com duas matrículas no MESMO professor.
--
-- TRÊS COMPETÊNCIAS, não o histórico inteiro: o valor está em "como está agora
-- e como estava" — série longa não muda a conversa e só engorda o prompt.

create or replace function public.fabio_prontuario_aluno(
  p_aluno_id integer,
  p_professor_id integer,
  p_limite integer default 40
) returns jsonb
language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_base jsonb;
  v_cadastro jsonb;
  v_experimental jsonb;
  v_semaforo jsonb;
  v_ids int[];
begin
  if p_professor_id is null then
    raise exception 'professor_id_obrigatorio: o Fabio fala com professor e so pode ler os cursos DELE com este aluno.'
      using errcode = '42501';
  end if;

  v_base := public.fn_prontuario_aluno_interno(p_aluno_id, p_professor_id, p_limite);

  select jsonb_build_object(
           'nome',                 k.aluno_nome,
           'primeiro_nome',        split_part(btrim(k.aluno_nome), ' ', 1),
           'curso',                k.curso_nome,
           'dia_aula',             k.dia_aula,
           'horario_aula',         k.horario_aula,
           'idade',                a.idade_atual,
           'responsavel_nome',     k.responsavel_nome,
           'data_matricula',       k.data_matricula,
           'dias_desde_matricula', k.dias_desde_matricula,
           'e_aluno_novo',         k.e_aluno_novo,
           'aulas_registradas',    k.aulas_registradas
         )
    into v_cadastro
    from vw_fabio_carteira_professor k
    join alunos a on a.id = k.aluno_id
   where k.aluno_id = p_aluno_id
     and k.professor_id = p_professor_id
   limit 1;

  -- Só entra se o aluno for da carteira DESTE professor. O guard de cima já
  -- garante isso, mas a checagem aqui evita que uma mudança futura no
  -- fn_prontuario_aluno_interno abra a porta sem ninguém notar.
  if v_cadastro is not null then
    select e.contexto || jsonb_build_object('data_experimental', e.data_experimental,
                                            'curso_experimental', e.curso)
      into v_experimental
      from vw_fabio_contexto_experimental e
     where e.aluno_id = p_aluno_id
     order by e.data_experimental desc
     limit 1;

    -- O semáforo (078). Todas as matrículas da MESMA pessoa, só as respostas
    -- DESTE professor, três competências mais recentes.
    select array_agg(x)::int[] into v_ids
      from jsonb_array_elements_text(coalesce(v_base -> 'aluno_ids_da_pessoa', '[]'::jsonb)) t(x);
    v_ids := coalesce(v_ids, array[]::int[]) || p_aluno_id;

    select jsonb_agg(jsonb_build_object(
             'competencia',     s.competencia,
             'coracao',         s.feedback,
             'pratica_em_casa', s.pratica_em_casa,
             'evolucao',        s.evolucao,
             'animo',           s.animo,
             'observacao',      nullif(btrim(s.observacao), ''),
             'respondido_em',   coalesce(s.atualizado_em, s.respondido_em))
             order by s.competencia desc)
      into v_semaforo
      from (select f.*
              from public.aluno_feedback_professor f
             where f.aluno_id = any (v_ids)
               and f.professor_id = p_professor_id
             order by f.competencia desc
             limit 3) s;
  end if;

  return v_base
      || jsonb_build_object('cadastro',     coalesce(v_cadastro, '{}'::jsonb))
      || jsonb_build_object('experimental', coalesce(v_experimental, '{}'::jsonb))
      || jsonb_build_object('semaforo',     coalesce(v_semaforo, '[]'::jsonb));
end
$function$;

comment on function public.fabio_prontuario_aluno(integer, integer, integer) is
  'Prontuário do aluno pro Fábio. Desde a 078 traz `semaforo`: as 3 últimas '
  'competências do feedback DESTE professor sobre esta pessoa — nunca o de '
  'colega.';
