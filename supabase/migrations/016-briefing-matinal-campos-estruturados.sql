-- 016-briefing-matinal-campos-estruturados.sql
-- Briefing matinal do Fábio: devolver os campos SEPARADOS em vez de um texto colado e truncado.
--
-- POR QUÊ: o registro do Fábio já guarda tudo estruturado (objetivo, atividades, repertório,
-- dever de casa, próximo passo), mas a RPC grudava tudo num COALESCE e cortava em 110 chars —
-- o nome da música (o que mais ajuda o professor a preparar a aula) morria no corte.
-- O formato aprovado pelo Alf (SIMULAÇÃO 2) precisa de Foco / Trabalho feito / Música separados.
--
-- ADITIVO E NÃO-QUEBRANTE: `resumo_ultima_aula` continua exatamente como era (o Hermes pode
-- seguir usando). O que entra é o objeto `ultima_aula` + os totais do dia.
--
-- Lógica de busca da última aula: INALTERADA (mesmo slot/âncora, mesmo curso base, mesma
-- precedência fatia→tronco→anotações). Só mudou o formato de saída.
-- Read-only (STABLE). Grants preservados: fabio_agent + service_role.

-- Helper: normaliza o texto de um campo do registro pro WhatsApp — colapsa espaços/quebras,
-- devolve NULL quando vazio (aí o jsonb_strip_nulls tira a chave e o Fábio não escreve a linha)
-- e põe um teto de segurança de 300 chars pra um campo maluco não explodir a mensagem.
create or replace function public.fn_briefing_txt(p_txt text)
returns text
language sql immutable parallel safe
as $$
  select left(nullif(btrim(regexp_replace(coalesce(p_txt, ''), '\s+', ' ', 'g')), ''), 300)
$$;

create or replace function public.fabio_briefing_matinal(
  p_professor_id integer,
  p_data date default current_date
) returns jsonb
language plpgsql stable security definer set search_path to 'public'
as $function$
DECLARE
  v_nome text;
  v_res  jsonb;
BEGIN
  SELECT nome INTO v_nome
  FROM public.professores
  WHERE id = p_professor_id AND COALESCE(ativo, true);

  IF v_nome IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'professor_nao_encontrado');
  END IF;

  SELECT jsonb_build_object(
    'ok', true,
    'professor_id', p_professor_id,
    'primeiro_nome', split_part(btrim(v_nome), ' ', 1),
    'data', p_data,
    'fonte_presenca', 'vw_aluno_presenca_semantica_v1',
    'aulas', COALESCE((
      WITH slots AS (
        SELECT
          data_hora_inicio,
          data_hora_fim,
          array_agg(id ORDER BY CASE WHEN tipo = 'turma' THEN 0 ELSE 1 END, id) AS aula_ids,
          (array_agg(id ORDER BY CASE WHEN tipo = 'turma' THEN 0 ELSE 1 END, id))[1] AS aula_ancora
        FROM public.aulas_emusys
        WHERE professor_id = p_professor_id
          AND data_aula = p_data
          AND COALESCE(cancelada, false) = false
        GROUP BY data_hora_inicio, data_hora_fim
      )
      SELECT jsonb_agg(
        jsonb_build_object(
          'hora', to_char(ae.data_hora_inicio AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI'),
          'curso', ae.curso_nome,
          'turma_nome', ae.turma_nome,
          'sala_nome', ae.sala_nome,
          'alunos', COALESCE((
            SELECT jsonb_agg(
              jsonb_build_object(
                'nome', roster.nome,
                'primeiro_nome', split_part(btrim(roster.nome), ' ', 1),
                -- COMPAT: campo antigo, formato idêntico ao anterior (texto colado, 110 chars)
                'resumo_ultima_aula', (u.dados->>'resumo'),
                -- NOVO: os campos separados, do jeito que o briefing aprovado precisa
                'ultima_aula', CASE WHEN u.dados IS NULL THEN NULL ELSE
                  (u.dados - 'resumo') END
              )
              ORDER BY roster.nome
            )
            FROM (
              SELECT DISTINCT a.id, a.nome
              FROM public.aula_alunos_emusys r
              JOIN public.alunos a ON a.id = r.aluno_id
              WHERE r.aula_emusys_id = ANY(s.aula_ids)
            ) roster
            -- LATERAL: a MESMA busca de antes (último registro do mesmo curso base),
            -- só que devolvendo o pacote inteiro em vez de um texto truncado.
            LEFT JOIN LATERAL (
              SELECT jsonb_strip_nulls(jsonb_build_object(
                'data', ae2.data_aula,
                'foco',           public.fn_briefing_txt(COALESCE(fat.campos->>'objetivo',      reg.campos->>'objetivo')),
                'trabalho_feito', public.fn_briefing_txt(COALESCE(fat.campos->>'progresso',
                                                                 fat.campos->>'atividades',
                                                                 reg.campos->>'atividades')),
                'repertorio',     public.fn_briefing_txt(COALESCE(fat.campos->>'repertorio',    reg.campos->>'repertorio')),
                'dever_casa',     public.fn_briefing_txt(COALESCE(fat.campos->>'dever_casa',    reg.campos->>'dever_casa')),
                'proximo_passo',  public.fn_briefing_txt(COALESCE(fat.campos->>'proximo_passo', reg.campos->>'proximo_passo')),
                'observacao',     public.fn_briefing_txt(COALESCE(fat.campos->>'obs_gerais',    reg.campos->>'obs_gerais')),
                'resumo', left(regexp_replace(
                    COALESCE(
                      nullif(btrim(fat.campos->>'progresso'), ''),
                      nullif(btrim(reg.campos->>'atividades'), ''),
                      nullif(btrim(reg.texto_consolidado), ''),
                      nullif(btrim(ae2.anotacoes_fabio), ''),
                      nullif(btrim(ae2.anotacoes), '')
                    ), '\s+', ' ', 'g'), 110)
              )) AS dados
              FROM public.aulas_emusys ae2
              LEFT JOIN public.fabio_registros_aula reg
                ON reg.aula_id = ae2.id AND reg.parent_id IS NULL
              LEFT JOIN public.fabio_registros_aula fat
                ON fat.parent_id = reg.id AND fat.aluno_id = roster.id
              WHERE ae2.professor_id = p_professor_id
                AND ae2.data_aula < p_data
                AND COALESCE(ae2.cancelada, false) = false
                AND public.fn_curso_base(ae2.curso_nome) = public.fn_curso_base(ae.curso_nome)
                AND (
                  EXISTS (SELECT 1 FROM public.aula_alunos_emusys rr
                          WHERE rr.aula_emusys_id = ae2.id AND rr.aluno_id = roster.id)
                  OR EXISTS (SELECT 1 FROM public.vw_aluno_presenca_semantica_v1 ps
                             WHERE ps.aula_emusys_id = ae2.id AND ps.aluno_id = roster.id)
                )
                AND (
                  reg.id IS NOT NULL
                  OR COALESCE(btrim(ae2.anotacoes_fabio), '') <> ''
                  OR COALESCE(btrim(ae2.anotacoes), '') <> ''
                )
              ORDER BY ae2.data_aula DESC, ae2.data_hora_inicio DESC
              LIMIT 1
            ) u ON true
          ), '[]'::jsonb)
        )
        ORDER BY ae.data_hora_inicio
      )
      FROM slots s
      JOIN public.aulas_emusys ae ON ae.id = s.aula_ancora
    ), '[]'::jsonb)
  ) INTO v_res;

  -- Totais do dia prontos ("Hoje você tem 4 aulas com 5 alunos") — o Fábio não precisa contar.
  RETURN v_res || jsonb_build_object(
    'total_aulas',  jsonb_array_length(COALESCE(v_res->'aulas', '[]'::jsonb)),
    'total_alunos', COALESCE((
      SELECT count(DISTINCT al->>'nome')
      FROM jsonb_array_elements(COALESCE(v_res->'aulas','[]'::jsonb)) a,
           jsonb_array_elements(COALESCE(a->'alunos','[]'::jsonb)) al), 0)
  );
END
$function$;

comment on function public.fabio_briefing_matinal(integer, date) is
  'Briefing matinal do professor: agenda do dia + ultima aula registrada por aluno em CAMPOS SEPARADOS (ultima_aula: data/foco/trabalho_feito/repertorio/dever_casa/proximo_passo/observacao) + totais. Mantem resumo_ultima_aula por compatibilidade. Read-only.';

-- Grants: preservar o que já existia (fabio_agent + service_role; nunca anon/authenticated).
revoke all on function public.fabio_briefing_matinal(integer, date) from public, anon, authenticated;
grant execute on function public.fabio_briefing_matinal(integer, date) to service_role, fabio_agent;
