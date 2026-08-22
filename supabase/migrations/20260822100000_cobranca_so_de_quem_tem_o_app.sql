-- Cobrança de registro só alcança quem TEM o aplicativo.
--
-- POR QUE. O relatório das 7h de 22/08 dizia "42 professor(es) passaram dos 7d
-- sem registrar (1106 aulas)". Medido: são 44 professores ativos e apenas 10
-- têm o app liberado. Os outros 34 estavam sendo cobrados por não usar uma
-- ferramenta que nunca receberam — e não é só ruído de relatório: a mesma
-- `vw_registro_pendencia` alimenta o worker que MANDA a cobrança no WhatsApp,
-- o escalonamento pra coordenação e o contexto do Fábio.
--
-- `cobravel` só olhava a data de corte. Passa a olhar também se o professor
-- tem acesso ao app. A liberação é auto-mantida: criar o login É o ato de
-- liberar, então a próxima leva entra sozinha, sem migration nova.
--
-- Convergência que sustenta a régua (medida em 22/08): três contagens
-- independentes dão o MESMO 10 — quem tem `auth_user_id`, quem registrou nos
-- últimos 30d e quem gravou áudio nos últimos 30d.
--
-- INVARIANTE que o teste sustenta: para quem JÁ tem o app, nada muda. A
-- mudança só pode SUBTRAIR linhas de quem não tem app — nunca alterar as de
-- quem tem.
--
-- Impacto medido antes de aplicar: 2388 -> 507 linhas cobráveis; 44 -> 10
-- professores.

create or replace function public.fn_professor_usa_app(p_professor_id integer)
returns boolean
language sql
stable
set search_path to 'public'
as $$
  -- SQL/STABLE de propósito: o planner inlina o predicado no plano da view
  -- em vez de chamar função por linha.
  select exists (
    select 1
      from public.professores pr
      join public.usuarios u on u.id = pr.usuario_id
     where pr.id = p_professor_id
       and coalesce(pr.ativo, true)
       and coalesce(u.ativo, true)
       -- ter login É ter o app: é assim que a liberação acontece.
       and u.auth_user_id is not null
  );
$$;

comment on function public.fn_professor_usa_app(integer) is
  'Professor tem o aplicativo liberado (login criado e ativo). Régua única de quem pode ser COBRADO por registro — ver vw_registro_pendencia.cobravel.';

-- View idêntica à anterior; a ÚNICA mudança é a expressão de `cobravel`.
create or replace view public.vw_registro_pendencia as
 SELECT ae.professor_id,
    ae.professor_nome,
    ae.unidade_id,
    ae.id AS aula_ancora_id,
    alvo.id AS aula_alvo_id,
    ae.data_aula,
    ae.data_hora_inicio,
    ae.data_hora_fim,
    ae.curso_nome,
    fn_curso_base(ae.curso_nome::text) AS curso_base,
    ae.turma_nome,
    ae.tipo,
    r.aluno_id,
    al.nome AS aluno_nome,
    split_part(btrim(al.nome::text), ' '::text, 1) AS aluno_primeiro_nome,
    pres.status_presenca,
    pres.chamada_feita,
    floor(EXTRACT(epoch FROM now() - ae.data_hora_fim) / 86400::numeric)::integer AS dias_em_atraso,
    -- <<< MUDANÇA: não se cobra conteúdo de quem não tem a ferramenta.
    (ae.data_aula >= fn_data_corte_cobranca() AND fn_professor_usa_app(ae.professor_id)) AS cobravel,
    NULLIF(btrim(COALESCE(alvo.anotacoes, ''::text)), ''::text) IS NOT NULL AS tem_plano_emusys
   FROM aulas_emusys ae
     JOIN aula_alunos_emusys r ON r.aula_emusys_id = ae.id
     JOIN alunos al ON al.id = r.aluno_id
     JOIN LATERAL ( SELECT COALESCE(( SELECT i.id
                   FROM aulas_emusys i
                     JOIN aula_alunos_emusys ri ON ri.aula_emusys_id = i.id AND ri.aluno_id = r.aluno_id
                  WHERE i.tipo::text = 'individual'::text AND i.unidade_id = ae.unidade_id AND i.data_hora_inicio = ae.data_hora_inicio AND NOT i.data_hora_fim IS DISTINCT FROM ae.data_hora_fim AND NOT i.curso_nome::text IS DISTINCT FROM ae.curso_nome::text AND NOT i.professor_id IS DISTINCT FROM ae.professor_id AND COALESCE(i.cancelada, false) = false
                  ORDER BY i.id DESC
                 LIMIT 1), ae.id) AS id) alvo_id ON true
     JOIN aulas_emusys alvo ON alvo.id = alvo_id.id
     JOIN LATERAL ( SELECT count(*) > 0 AS chamada_feita,
                CASE
                    WHEN bool_or(g.st = 'presente'::text) THEN 'presente'::text
                    WHEN count(*) > 0 THEN 'falta'::text
                    ELSE NULL::text
                END AS status_presenca
           FROM ( SELECT ap2.status_presenca AS st
                   FROM aulas_emusys gem
                     JOIN aluno_presenca ap2 ON ap2.aula_emusys_id = gem.id AND ap2.aluno_id = r.aluno_id
                  WHERE gem.unidade_id = ae.unidade_id AND gem.data_hora_inicio = ae.data_hora_inicio AND NOT gem.data_hora_fim IS DISTINCT FROM ae.data_hora_fim AND NOT gem.curso_nome::text IS DISTINCT FROM ae.curso_nome::text AND NOT gem.professor_id IS DISTINCT FROM ae.professor_id AND COALESCE(gem.cancelada, false) = false) g) pres ON true
  WHERE ae.id = fn_aula_operacional_id(ae.id) AND ae.professor_id IS NOT NULL AND COALESCE(ae.cancelada, false) = false AND ae.data_hora_fim < now() AND COALESCE(pres.status_presenca, 'presente'::text) <> 'falta'::text AND NULLIF(btrim(COALESCE(alvo.anotacoes_fabio, ''::text)), ''::text) IS NULL;

comment on view public.vw_registro_pendencia is
  'Aulas encerradas sem conteúdo registrado. `cobravel` = dentro da data de corte E professor com o app liberado (fn_professor_usa_app).';
