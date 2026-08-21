-- Briefing matinal (pedido do Isaque, 21/08/2026): a "última aula" mostrada
-- passa a ser a última em que o aluno esteve PRESENTE (pula falta_confirmada /
-- falta_provavel pela vw_aluno_presenca_semantica_v1) — nunca mais "aluna
-- ausente" nem em branco. E acrescenta faltou_data / faltou_recente para o
-- worker avisar "Faltou na última aula · data".
--
-- Regressão que isto conserta: a versão anterior pegava a última aula com
-- QUALQUER conteúdo, e para aluno em falta longa isso trazia a anotação do
-- Emusys ("aluna ausente") como trabalho feito. Medido no caso real da Vanessa
-- (Isaque/Piano): antes = 20/08 "aluna ausente"; depois = 18/06 conteúdo real
-- (Cuckuo/French Children Song) + ⚠️ faltou 20/08. Alunos que estavam presentes
-- na última (Antônio, Isabela, João Vitor, Pedro) ficam idênticos.
--
-- Fonte da verdade é a função DEPLOYADA (o histórico de migrations do briefing
-- estava em 016/017, defasado do banco). Testado ao vivo via função temporária
-- __t21 comparada à viva, e via render end-to-end no fabio_notification_worker.
CREATE OR REPLACE FUNCTION public.fabio_briefing_matinal(p_professor_id integer, p_data date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_nome text; v_res jsonb;
BEGIN
  SELECT nome INTO v_nome FROM public.professores
  WHERE id = p_professor_id AND COALESCE(ativo, true);
  IF v_nome IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'professor_nao_encontrado');
  END IF;
  SELECT jsonb_build_object(
    'ok', true, 'professor_id', p_professor_id,
    'primeiro_nome', split_part(btrim(v_nome), ' ', 1),
    'data', p_data, 'fonte_presenca', 'vw_aluno_presenca_semantica_v1',
    'aulas', COALESCE((
      WITH slots AS (
        SELECT data_hora_inicio, data_hora_fim,
          array_agg(id ORDER BY CASE WHEN tipo = 'turma' THEN 0 ELSE 1 END, id) AS aula_ids,
          (array_agg(id ORDER BY CASE WHEN tipo = 'turma' THEN 0 ELSE 1 END, id))[1] AS aula_ancora
        FROM public.aulas_emusys
        WHERE professor_id = p_professor_id AND data_aula = p_data
          AND COALESCE(cancelada, false) = false
        GROUP BY data_hora_inicio, data_hora_fim
      )
      SELECT jsonb_agg(jsonb_build_object(
          'hora', to_char(ae.data_hora_inicio AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI'),
          'curso', ae.curso_nome, 'turma_nome', ae.turma_nome, 'sala_nome', ae.sala_nome,
          'alunos', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'nome', roster.nome,
                'primeiro_nome', split_part(btrim(roster.nome), ' ', 1),
                'resumo_ultima_aula', (u.dados->>'resumo'),
                'ultima_aula', CASE WHEN u.dados IS NULL THEN NULL ELSE (u.dados - 'resumo') END,
                'faltou_data', f.falta_data,
                'faltou_recente', (f.falta_data IS NOT NULL
                    AND (u.dados IS NULL OR (u.dados->>'data')::date < f.falta_data))
              ) ORDER BY roster.nome)
            FROM (
              SELECT DISTINCT a.id, a.nome FROM public.aula_alunos_emusys r
              JOIN public.alunos a ON a.id = r.aluno_id
              WHERE r.aula_emusys_id = ANY(s.aula_ids)
            ) roster
            LEFT JOIN LATERAL (
              SELECT jsonb_strip_nulls(jsonb_build_object(
                'data', ae2.data_aula,
                'foco',           public.fn_briefing_txt(COALESCE(fat.campos->>'objetivo',      reg.campos->>'objetivo')),
                'trabalho_feito', public.fn_briefing_txt(COALESCE(fat.campos->>'progresso',
                                                                 fat.campos->>'atividades',
                                                                 reg.campos->>'atividades',
                                                                 reg.texto_consolidado,
                                                                 ae2.anotacoes_fabio,
                                                                 ae2.anotacoes)),
                'repertorio',     public.fn_briefing_txt(COALESCE(fat.campos->>'repertorio',    reg.campos->>'repertorio')),
                'dever_casa',     public.fn_briefing_txt(COALESCE(fat.campos->>'dever_casa',    reg.campos->>'dever_casa')),
                'proximo_passo',  public.fn_briefing_txt(COALESCE(fat.campos->>'proximo_passo', reg.campos->>'proximo_passo')),
                'observacao',     public.fn_briefing_txt(COALESCE(fat.campos->>'obs_gerais',    reg.campos->>'obs_gerais')),
                'resumo', left(regexp_replace(COALESCE(
                      nullif(btrim(fat.campos->>'progresso'), ''),
                      nullif(btrim(reg.campos->>'atividades'), ''),
                      nullif(btrim(reg.texto_consolidado), ''),
                      nullif(btrim(ae2.anotacoes_fabio), ''),
                      nullif(btrim(ae2.anotacoes), '')
                    ), '\s+', ' ', 'g'), 110)
              )) AS dados
              FROM public.aulas_emusys ae2
              LEFT JOIN public.fabio_registros_aula reg ON reg.aula_id = ae2.id AND reg.parent_id IS NULL
              LEFT JOIN public.fabio_registros_aula fat ON fat.parent_id = reg.id AND fat.aluno_id = roster.id
              WHERE ae2.professor_id = p_professor_id AND ae2.data_aula < p_data
                AND COALESCE(ae2.cancelada, false) = false
                AND public.fn_curso_base(ae2.curso_nome) = public.fn_curso_base(ae.curso_nome)
                AND (EXISTS (SELECT 1 FROM public.aula_alunos_emusys rr WHERE rr.aula_emusys_id = ae2.id AND rr.aluno_id = roster.id)
                  OR EXISTS (SELECT 1 FROM public.vw_aluno_presenca_semantica_v1 ps WHERE ps.aula_emusys_id = ae2.id AND ps.aluno_id = roster.id))
                AND (reg.id IS NOT NULL OR COALESCE(btrim(ae2.anotacoes_fabio), '') <> '' OR COALESCE(btrim(ae2.anotacoes), '') <> '')
                -- pula aula em que o aluno FALTOU: o conteúdo tem que ser da última PRESENÇA
                AND NOT EXISTS (
                  SELECT 1 FROM public.vw_aluno_presenca_semantica_v1 psx
                  WHERE psx.aula_emusys_id = ae2.id AND psx.aluno_id = roster.id
                    AND psx.resultado_pedagogico IN ('falta_confirmada','falta_provavel')
                )
              ORDER BY ae2.data_aula DESC, ae2.data_hora_inicio DESC LIMIT 1
            ) u ON true
            -- data da falta mais recente (para o aviso "Faltou na última aula")
            LEFT JOIN LATERAL (
              SELECT ae3.data_aula AS falta_data
              FROM public.aulas_emusys ae3
              JOIN public.vw_aluno_presenca_semantica_v1 ps3
                ON ps3.aula_emusys_id = ae3.id AND ps3.aluno_id = roster.id
              WHERE ae3.professor_id = p_professor_id AND ae3.data_aula < p_data
                AND COALESCE(ae3.cancelada, false) = false
                AND public.fn_curso_base(ae3.curso_nome) = public.fn_curso_base(ae.curso_nome)
                AND ps3.resultado_pedagogico IN ('falta_confirmada','falta_provavel')
              ORDER BY ae3.data_aula DESC, ae3.data_hora_inicio DESC LIMIT 1
            ) f ON true
          ), '[]'::jsonb)
        ) ORDER BY ae.data_hora_inicio)
      FROM slots s JOIN public.aulas_emusys ae ON ae.id = s.aula_ancora
    ), '[]'::jsonb)
  ) INTO v_res;
  RETURN v_res || jsonb_build_object(
    'total_aulas',  jsonb_array_length(COALESCE(v_res->'aulas', '[]'::jsonb)),
    'total_alunos', COALESCE((SELECT count(DISTINCT al->>'nome')
      FROM jsonb_array_elements(COALESCE(v_res->'aulas','[]'::jsonb)) a,
           jsonb_array_elements(COALESCE(a->'alunos','[]'::jsonb)) al), 0));
END
$function$;
