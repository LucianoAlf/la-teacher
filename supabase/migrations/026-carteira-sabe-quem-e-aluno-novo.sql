-- 026 — a carteira passa a dizer há quanto tempo o aluno está na casa
--
-- POR QUE ISSO EXISTE
-- Em 04/08/2026 o Matheus perguntou ao Fábio: "essa Fernanda, quem é?".
-- O Fábio respondeu que não conseguia afirmar se ela era aluna nova — mas o
-- dado estava no banco o tempo todo: `alunos.data_matricula = 03/08`, ou seja,
-- matriculada no dia anterior, com a primeira aula naquele mesmo dia.
--
-- Ele não errou por inventar. Errou porque a carteira que ele lê
-- (vw_fabio_carteira_professor) traz curso, dia, horário e responsável — e não
-- traz DESDE QUANDO a pessoa está na escola. Sem isso ele só sabia dizer que
-- não havia histórico de aula, que é uma resposta verdadeira e inútil.
--
-- O QUE ENTRA (tudo aditivo — nenhuma coluna existente muda de nome ou tipo,
-- e nenhuma view depende desta, conferido em pg_depend antes de mexer)
--
--   data_matricula        o fato, cru
--   dias_desde_matricula  pra ele falar "entrou ontem" em vez de uma data
--   e_aluno_novo          o corte, explícito e documentado abaixo
--   aulas_registradas     quantas aulas dele já foram registradas no Fábio
--
-- POR QUE `aulas_registradas` É SEPARADO DE `e_aluno_novo`
-- A tentação era marcar como novo quem não tem aula registrada. Isso seria
-- falso hoje: só o Matheus usa o registro, então a base inteira apareceria
-- como "aluna nova". São duas perguntas diferentes — "chegou agora?" e "eu já
-- registrei alguma aula dela?" — e o Fábio precisa das duas para dizer
-- "entrou ontem e a primeira aula é hoje" em vez de escolher um dos lados.

create or replace view public.vw_fabio_carteira_professor as
 SELECT j.unidade_id,
    u.codigo AS unidade_codigo,
    u.nome AS unidade_nome,
    p.id AS professor_id,
    p.nome AS professor_nome,
    pu.id AS professores_unidade_id,
    pu.emusys_id AS emusys_professor_id,
    pu.validacao_status AS professor_emusys_validacao_status,
    a.id AS aluno_id,
    a.nome AS aluno_nome,
    COALESCE(a.emusys_student_id, j.emusys_aluno_id::text) AS emusys_student_id,
    COALESCE(a.emusys_matricula_id, j.emusys_matricula_id::text) AS emusys_matricula_id,
    j.status_matricula::character varying(20) AS aluno_status,
    COALESCE(c.id, j.curso_id) AS curso_id,
    COALESCE(c.nome, j.curso_nome_emusys::character varying)::character varying(100) AS curso_nome,
    tm.codigo AS tipo_matricula_codigo,
    tm.nome AS tipo_matricula_nome,
    COALESCE(a.dia_aula, j.dia_semana::character varying)::character varying(20) AS dia_aula,
    COALESCE(a.horario_aula, NULLIF(j.horario, ''::text)::time without time zone) AS horario_aula,
    a.telefone,
    a.whatsapp,
    a.email,
    a.responsavel_nome,
    a.responsavel_telefone,
    a.valor_parcela,
        CASE
            WHEN p.id IS NULL THEN 'sem_professor_la'::text
            WHEN pu.emusys_id IS NULL THEN 'professor_sem_emusys_id'::text
            WHEN a.emusys_student_id IS NULL AND j.emusys_aluno_id IS NULL THEN 'aluno_sem_id_emusys'::text
            WHEN COALESCE(a.dia_aula, j.dia_semana::character varying) IS NULL OR COALESCE(a.horario_aula, NULLIF(j.horario, ''::text)::time without time zone) IS NULL THEN 'sem_horario'::text
            ELSE 'ok'::text
        END AS qualidade_contexto,
    j.id AS jornada_id,
    j.emusys_matricula_disciplina_id,
    -- ─── novo em 026 ───────────────────────────────────────────────────────
    a.data_matricula,
    CASE WHEN a.data_matricula IS NULL THEN NULL
         ELSE (CURRENT_DATE - a.data_matricula) END AS dias_desde_matricula,
    -- 30 dias é o corte, e é uma escolha, não uma verdade: é o intervalo em
    -- que "chegou agora" ainda muda como o professor conduz a aula. Está aqui
    -- em vez de espalhado no prompt do Fábio para poder ser discutido e mudado
    -- num lugar só. Sem data_matricula devolve false, nunca null: "não sei
    -- quando entrou" não pode virar "é aluno novo".
    COALESCE(a.data_matricula >= CURRENT_DATE - 30, false) AS e_aluno_novo,
    COALESCE(reg.total, 0)::integer AS aulas_registradas
   FROM aluno_jornada_matricula_disciplina j
     JOIN alunos a ON a.id = j.aluno_id
     JOIN unidades u ON u.id = j.unidade_id
     JOIN professores p ON p.id = j.professor_id AND p.ativo = true
     JOIN professores_unidades pu ON pu.professor_id = p.id AND pu.unidade_id = j.unidade_id AND pu.emusys_ativo = true AND pu.validacao_status <> 'ignorado'::text
     LEFT JOIN cursos c ON c.id = COALESCE(j.curso_id, a.curso_id)
     LEFT JOIN tipos_matricula tm ON tm.id = a.tipo_matricula_id
     LEFT JOIN (
       -- Só o que virou registro de verdade conta. Rascunho e descartado não
       -- são aula dada, e contá-los faria o Fábio dizer que já tem histórico
       -- de alguém que nunca teve.
       SELECT r.aluno_id, count(*) AS total
         FROM fabio_registros_aula r
        WHERE r.aluno_id IS NOT NULL
          AND r.status IN ('confirmado', 'gravado_emusys')
        GROUP BY r.aluno_id
     ) reg ON reg.aluno_id = a.id
  WHERE j.status_matricula = 'ativa'::text AND a.arquivado_em IS NULL;

comment on view public.vw_fabio_carteira_professor is
'Carteira do professor que o Fabio le. Desde a 026 diz tambem HA QUANTO TEMPO o aluno esta na casa (data_matricula, dias_desde_matricula, e_aluno_novo) e quantas aulas dele ja foram registradas.';

-- ─────────────────────────────────────────────────────────────────────────
-- O prontuário passa a dizer QUEM É, não só o que a pessoa já fez
--
-- Alargar a carteira não bastava: quando o professor pergunta sobre um aluno,
-- o bridge chama fabio_prontuario_aluno, e ela devolvia só linha do tempo e
-- cursos. Para a Fernanda isso era literalmente `linha_do_tempo: []` — o Fábio
-- não tinha nada além do vazio, e foi honesto sobre o vazio.
--
-- O bloco `cadastro` sai da própria vw_fabio_carteira_professor, que já filtra
-- por professor. Assim o guard de "só os alunos DELE" continua sendo um só, no
-- mesmo lugar — em vez de virar uma segunda regra que pode divergir da
-- primeira. A lógica interna do prontuário não é tocada.

create or replace function public.fabio_prontuario_aluno(
  p_aluno_id integer,
  p_professor_id integer,
  p_limite integer default 40
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_base jsonb;
  v_cadastro jsonb;
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

  -- Sem cadastro devolve objeto vazio, nunca some a chave: assim quem consome
  -- distingue "não achei" de "esqueci de pedir".
  return v_base || jsonb_build_object('cadastro', coalesce(v_cadastro, '{}'::jsonb));
end
$function$;

comment on function public.fabio_prontuario_aluno(integer, integer, integer) is
'Prontuario do aluno para o professor. Desde a 026 inclui o bloco `cadastro` (quem e, desde quando, quantas aulas registradas) alem da linha do tempo.';
