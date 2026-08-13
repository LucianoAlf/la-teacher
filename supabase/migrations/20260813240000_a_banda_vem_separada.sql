-- A banda vem SEPARADA, não somada nem escondida.
--
-- O QUE O ALF PEDIU, em 13/08/2026, corrigindo a minha proposta de juntar tudo
-- num número só: *"tem que vir separado: bandas, qualquer outra coisa tem que
-- vir numa lista separada. Você tem tantos alunos regulares e tantas bandas,
-- tantos alunos nas suas bandas."*
--
-- Somar escondia; excluir mentia. Ramon (33) tem 47 pessoas na carteira: **13
-- regulares e 34 que só existem por atividade extra**. Dizer "47" some com a
-- diferença; dizer "13" faz o professor abrir a agenda e ver gente que o
-- número negou.
--
-- A RÉGUA NÃO É MINHA. `cursos.is_projeto_banda` já é a regra canônica da casa
-- -- está escrita em `regras-negocio-canonicas.md` §1.3 do LA Report e é o que
-- exclui banda/projeto de carteira, ticket médio, churn e contagem de
-- pagantes. Conferido: aplicá-la aqui devolve exatamente os mesmos 13 que a
-- régua de lá produz. Inventar um `nome ILIKE '%banda%'` seria uma segunda
-- verdade -- e o próprio doc marca o filtro por nome como legado a ser morto.
--
-- Hoje são 8 cursos com a marca: Minha Banda Para Sempre, GarageBand, Power
-- Kids, Percussion Kids, Canto Coral, Teoria Musical e os dois Circuitos de
-- Férias. Por isso o campo se chama `atividades_extras` e não `bandas`: nem
-- toda atividade extra é banda, e o nome do curso vai junto para o Fábio dizer
-- qual é qual em vez de generalizar.
--
-- QUEM NÃO DÁ PRA CLASSIFICAR CONTA COMO REGULAR. Se o `curso_id` não existe
-- em `cursos`, a pessoa entra em `regulares`. O erro seguro aqui é aparecer
-- demais: sumir da lista é como um aluno deixa de ser visto.
--
-- UMA FUNÇÃO SÓ, DUAS PORTAS. `fn_carteira_fatiada` é a régua; a RPC do agente
-- e o contexto do Fábio passam a perguntar pra ela. Era esse o defeito do F-C
-- (mesma regra escrita em três lugares) e eu não vou repetir no mesmo dia.
--
-- O QUE ESTA MIGRATION NÃO FAZ: contar TURMAS ("você tem 3 bandas"). O número
-- de turmas mora em `aulas_emusys.turma_nome`, e o caminho de lá até o curso
-- (`curso_emusys_id` -> `cursos.emusys_ids`) está quebrado: medido em
-- 13/08/2026, ele faz o Ramon "dar aula de Violino" e infla Violão de 2 para
-- 34 alunos. Contar turma por cima disso seria número errado com cara de
-- número. Fica anotado como frente própria.

create or replace function public.fn_carteira_fatiada(p_professor_id integer)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  with pessoas as (
    select c.pessoa_chave, c.curso_ids
      from public.vw_professor_carteira_pessoa_canonica_sombra c
     where c.professor_id = p_professor_id
  ),
  classificada as (
    select p.pessoa_chave,
           -- Curso desconhecido conta como regular: aparecer demais e o erro
           -- seguro; sumir da lista nao e.
           bool_or(not coalesce(cu.is_projeto_banda, false)) as tem_regular,
           bool_or(coalesce(cu.is_projeto_banda, false))     as tem_extra
      from pessoas p
      left join lateral unnest(coalesce(p.curso_ids, array[]::integer[])) as cid on true
      left join public.cursos cu on cu.id = cid
     group by p.pessoa_chave
  ),
  por_atividade as (
    select cu.nome as curso, count(distinct p.pessoa_chave) as alunos
      from pessoas p
      cross join lateral unnest(coalesce(p.curso_ids, array[]::integer[])) as cid
      join public.cursos cu on cu.id = cid
     where coalesce(cu.is_projeto_banda, false)
     group by cu.nome
  )
  select jsonb_build_object(
    'pessoas',            (select count(*) from classificada),
    'regulares',          (select count(*) from classificada where tem_regular),
    'em_atividade_extra', (select count(*) from classificada where tem_extra),
    'so_atividade_extra', (select count(*) from classificada where tem_extra and not tem_regular),
    'atividades_extras',  coalesce((select jsonb_agg(jsonb_build_object('curso', curso, 'alunos', alunos)
                                                     order by alunos desc, curso)
                                      from por_atividade), '[]'::jsonb),
    'fonte',              'vw_professor_carteira_pessoa_canonica_sombra + cursos.is_projeto_banda',
    'nota',               'Fale SEPARADO: os alunos regulares de um lado e cada atividade extra '
                          'com o nome dela do outro. Nao some os dois num numero so, e nao omita '
                          'a atividade extra: o professor da aula pra ela e ve essa gente na agenda. '
                          '`pessoas` e a soma sem repetir quem faz as duas coisas.'
  );
$function$;

comment on function public.fn_carteira_fatiada(integer) is
  'Regua UNICA da carteira fatiada (decisao do Alf, 13/08/2026): regulares x '
  'atividades extras, separados e nomeados. Usa cursos.is_projeto_banda, a '
  'mesma marca canonica do LA Report (regras-negocio-canonicas §1.3) -- nao '
  'reimplementa criterio por nome de curso. Quem tem curso desconhecido conta '
  'como regular, de proposito.';

revoke all on function public.fn_carteira_fatiada(integer) from public, anon, authenticated;
grant execute on function public.fn_carteira_fatiada(integer) to service_role, fabio_agent;

-- A RPC do agente passa a perguntar pra regua em vez de contar por conta.
create or replace function public.app_professor_carteira_contagem(p_professor_id integer)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select public.fn_carteira_fatiada(p_professor_id)
      || jsonb_build_object(
           'professor_id', p_professor_id,
           'matriculas',   (select count(distinct c.aluno_id_canonico)
                              from public.vw_professor_carteira_pessoa_canonica_sombra c
                             where c.professor_id = p_professor_id)
         );
$function$;

comment on function public.app_professor_carteira_contagem(integer) is
  'Carteira contada por PESSOA (decisao do Alf em 13/08/2026), fatiada entre '
  'regulares e atividades extras por fn_carteira_fatiada. `matriculas` vem '
  'junto de proposito: quando diverge de `pessoas`, a diferenca e informacao '
  '(aluno multi-curso), nao erro. PENDENTE: contagem de TURMAS ("3 bandas") -- '
  'o caminho aulas_emusys.curso_emusys_id -> cursos.emusys_ids esta quebrado.';

-- E o contexto que o Fabio realmente fala: ele ja trazia
-- `total_alunos_carteira` calculado da canonica -- o numero certo, mas UM
-- numero, que e exatamente o que o Alf recusou. O total continua (ha codigo
-- lendo), e ao lado dele entra a fatia.
create or replace function public.fabio_contexto_professor(p_professor_id integer, p_data date default CURRENT_DATE)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
DECLARE
  v_nome text;
  v_res jsonb;
BEGIN
  SELECT nome
    INTO v_nome
  FROM public.professores
  WHERE id = p_professor_id
    AND COALESCE(ativo, true);

  IF v_nome IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'motivo', 'professor_nao_encontrado'
    );
  END IF;

  SELECT jsonb_build_object(
    'ok', true,
    'professor_id', p_professor_id,
    'nome', v_nome,
    'primeiro_nome', split_part(btrim(v_nome), ' ', 1),
    'unidades', COALESCE((
      SELECT jsonb_agg(x.nome ORDER BY x.nome)
      FROM (
        SELECT DISTINCT u.nome
        FROM public.vw_professor_carteira_pessoa_canonica_sombra c
        JOIN public.unidades u ON u.id = c.unidade_id
        WHERE c.professor_id = p_professor_id
      ) x
    ), '[]'::jsonb),
    'total_alunos_carteira', (
      SELECT count(*)
      FROM public.vw_professor_carteira_pessoa_canonica_sombra c
      WHERE c.professor_id = p_professor_id
    ),
    'carteira', public.fn_carteira_fatiada(p_professor_id),
    'fonte_carteira', 'vw_professor_carteira_pessoa_canonica_sombra',
    'hoje', jsonb_build_object(
      'data', p_data,
      'total_aulas', (
        SELECT count(DISTINCT (ae.data_hora_inicio, ae.data_hora_fim))
        FROM public.aulas_emusys ae
        WHERE ae.professor_id = p_professor_id
          AND ae.data_aula = p_data
          AND COALESCE(ae.cancelada, false) = false
      ),
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
            'hora', to_char(
              ae.data_hora_inicio AT TIME ZONE 'America/Sao_Paulo',
              'HH24:MI'
            ),
            'curso', ae.curso_nome,
            'alunos', COALESCE((
              SELECT jsonb_agg(roster.nome ORDER BY roster.nome)
              FROM (
                SELECT DISTINCT a.id, a.nome
                FROM public.aula_alunos_emusys r
                JOIN public.alunos a ON a.id = r.aluno_id
                WHERE r.aula_emusys_id = ANY(s.aula_ids)
              ) roster
            ), '[]'::jsonb),
            'chamada_feita', EXISTS (
              SELECT 1
              FROM public.vw_aluno_presenca_semantica_v1 ps
              WHERE ps.aula_emusys_id = ANY(s.aula_ids)
                AND ps.resultado_pedagogico IN ('presente', 'falta_confirmada')
            ),
            'chamada_situacao', CASE
              WHEN EXISTS (
                SELECT 1
                FROM public.vw_aluno_presenca_semantica_v1 ps
                WHERE ps.aula_emusys_id = ANY(s.aula_ids)
                  AND ps.resultado_pedagogico IN ('presente', 'falta_confirmada')
              ) THEN 'confirmada'
              WHEN EXISTS (
                SELECT 1
                FROM public.vw_aluno_presenca_semantica_v1 ps
                WHERE ps.aula_emusys_id = ANY(s.aula_ids)
              ) THEN 'evidencia_inconclusiva'
              ELSE 'nao_registrada'
            END
          )
          ORDER BY ae.data_hora_inicio
        )
        FROM slots s
        JOIN public.aulas_emusys ae ON ae.id = s.aula_ancora
      ), '[]'::jsonb)
    ),
    'pendencias_cobraveis', (
      SELECT COALESCE(
        (public.fn_pendencias_do_professor(p_professor_id, false))->>'total_alunos',
        '0'
      )::integer
    ),
    -- O passivo EXISTE e nao se cobra. Sao duas coisas diferentes, e o Fabio
    -- precisava das duas: com so o numero de cobraveis no contexto, ele leu 0 e
    -- respondeu ao Matheus que "em julho nao ficou nenhuma aula pendente" —
    -- eram 12, de 29/06 a 09/07. Numero ausente do contexto vira negativa
    -- afirmada na resposta.
    -- Mesma fonte da cobranca (vw_registro_pendencia), lado de la do corte.
    'registro_fora_da_cobranca', (
      select jsonb_build_object(
               'aulas',  count(distinct aula_ancora_id),
               'alunos', count(*),
               'de',     min(data_aula),
               'ate',    max(data_aula),
               'corte',  public.fn_data_corte_cobranca(),
               'nota',   'Aulas sem conteudo lancado ANTERIORES a data de corte. Nao entram em cobranca nem em escalonamento, mas existem: se perguntarem por esse periodo, informe o numero em vez de dizer que nao ha nada.')
        from public.vw_registro_pendencia
       where professor_id = p_professor_id and not cobravel
    )
  )
  INTO v_res;

  RETURN v_res;
END
$function$;
