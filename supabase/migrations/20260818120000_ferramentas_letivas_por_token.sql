-- As duas primeiras ferramentas do Fábio. Nenhuma aceita `professor_id`.
--
-- Item 4 da revisão do Alfredo: sem estas, a fatia não fecha — a capacidade
-- existiria sem nada do outro lado dela.
--
-- O DESENHO EM UMA LINHA: o modelo escolhe *o que perguntar* (período, unidade);
-- ele não escolhe *de quem*. O "de quem" vem do token, que o bridge cunhou a
-- partir da linha da mensagem.
--
-- Estas funções não calculam nada: delegam para as RPCs canônicas
-- `fabio_professor_resumo_aulas` e `fabio_professor_presencas_periodo`, que já
-- tratam a armadilha da aula-gêmea (o mesmo horário aparece 2x desde 09/07 —
-- linha crua daria 74 aulas onde o professor deu 36) e já separam os baldes de
-- presença. Duplicar o cálculo aqui seria criar uma segunda verdade.

create or replace function public.fabio_prof_aulas_periodo(
  p_token text,
  p_inicio date,
  p_fim date,
  p_unidade text default null
)
returns jsonb
language plpgsql
volatile                      -- resolve o token, e resolver CONSOME um uso
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_sessao jsonb;
  v_professor integer;
begin
  v_sessao := public.fabio_agente_resolver(p_token);
  if (v_sessao ->> 'ok') is distinct from 'true' then
    -- Recusa ESTRUTURADA: o Fábio precisa saber que falhou pra perguntar de
    -- novo, em vez de improvisar um número ou prometer "já te trago".
    return jsonb_build_object('ok', false,
      'codigo', coalesce(v_sessao ->> 'codigo', 'token_invalido'),
      'orientacao', 'Sessao expirada. Peca ao professor que repita a pergunta.');
  end if;
  v_professor := (v_sessao ->> 'professor_id')::integer;

  if p_inicio is null or p_fim is null then
    return jsonb_build_object('ok', false, 'codigo', 'periodo_incompleto',
      'orientacao', 'Pergunte de que dia a que dia.');
  end if;
  if p_fim < p_inicio then
    return jsonb_build_object('ok', false, 'codigo', 'periodo_invertido');
  end if;
  -- Janela com teto: pergunta de ano inteiro é relatório, não conversa — e
  -- varredura sem limite num banco compartilhado é problema de todo mundo.
  if p_fim - p_inicio > 92 then
    return jsonb_build_object('ok', false, 'codigo', 'periodo_longo_demais',
      'orientacao', 'Peca um periodo de ate 3 meses.');
  end if;

  return public.fabio_professor_resumo_aulas(v_professor, p_inicio, p_fim, p_unidade);
end
$function$;

comment on function public.fabio_prof_aulas_periodo(text, date, date, text) is
  'Ferramenta do Fabio: aulas do professor DONO DO TOKEN. Nao aceita professor_id — identidade vem da capacidade, nunca do modelo.';

create or replace function public.fabio_prof_presencas_periodo(
  p_token text,
  p_inicio date,
  p_fim date
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_sessao jsonb;
  v_professor integer;
begin
  v_sessao := public.fabio_agente_resolver(p_token);
  if (v_sessao ->> 'ok') is distinct from 'true' then
    return jsonb_build_object('ok', false,
      'codigo', coalesce(v_sessao ->> 'codigo', 'token_invalido'),
      'orientacao', 'Sessao expirada. Peca ao professor que repita a pergunta.');
  end if;
  v_professor := (v_sessao ->> 'professor_id')::integer;

  if p_inicio is null or p_fim is null then
    return jsonb_build_object('ok', false, 'codigo', 'periodo_incompleto',
      'orientacao', 'Pergunte de que dia a que dia.');
  end if;
  if p_fim < p_inicio then
    return jsonb_build_object('ok', false, 'codigo', 'periodo_invertido');
  end if;
  if p_fim - p_inicio > 92 then
    return jsonb_build_object('ok', false, 'codigo', 'periodo_longo_demais',
      'orientacao', 'Peca um periodo de ate 3 meses.');
  end if;

  return public.fabio_professor_presencas_periodo(v_professor, p_inicio, p_fim);
end
$function$;

comment on function public.fabio_prof_presencas_periodo(text, date, date) is
  'Ferramenta do Fabio: presencas do professor DONO DO TOKEN, em baldes separados (presente/falta/provavel/nao aplicavel). Nao aceita professor_id.';

-- ── Item 5 da revisão: grant SÓ para o papel do agente ──────────────────────
-- Nem `service_role`: o bridge não precisa destas portas — ele já fala com as
-- RPCs canônicas com o professor_id que ele mesmo resolveu. Toda porta a mais
-- é uma porta a mais para errar.
revoke all on function public.fabio_prof_aulas_periodo(text, date, date, text)
  from public, anon, authenticated, service_role;
grant execute on function public.fabio_prof_aulas_periodo(text, date, date, text)
  to fabio_professor_agente;

revoke all on function public.fabio_prof_presencas_periodo(text, date, date)
  from public, anon, authenticated, service_role;
grant execute on function public.fabio_prof_presencas_periodo(text, date, date)
  to fabio_professor_agente;
