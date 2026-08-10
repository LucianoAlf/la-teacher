-- Teste da 081. Roda dentro de BEGIN/ROLLBACK do rodar-teste-sql.mjs.
--
-- A view é a fundação do Radar: se ela contar linha em vez de aula, TODO
-- número acima dela dobra. Os passos abaixo guardam as quatro decisões que
-- custaram medição: grão, denominador honesto, janela virada e coorte.
--
-- Rodada de correção (revisão, 10/08) acrescentou três blocos:
--   C1 (crítico) — a view só pode ser lida por service_role. A porta é a
--   função, não a view (a RPC da Task 4 é quem autoriza).
--   I1 — competência vem de fn_competencia_feedback(), nunca current_date
--   cru (UTC), senão o semáforo some das 21h à meia-noite do último dia do
--   mês — mesma armadilha que a 018/073 já pagaram.
--   I2 — o passo estrutural do denominador (linha ~60) não pega um mutante
--   que MANTÉM o identificador (`is not null` em vez de apagar), porque
--   considera_frequencia_denominador nunca é NULL de verdade — as duas
--   formas de neutralizar o filtro colapsam no mesmo resultado. Fixture
--   ZZTESTE prova o comportamento (medição de custo no comentário abaixo).
create temporary table _res(caso text, ok boolean, detalhe text) on commit drop;

-- ── Fixture do I2: aluno cuja ÚNICA aula fica fora do denominador ─────────
-- Medido em 10/08 (pg_get_viewdef + information_schema.view_table_usage)
-- antes de escrever isto: a cadeia PARECIA grande — vw_aluno_sucesso_lista
-- depende de fn_aluno_entra_base_ativa_v131, que depende de
-- vw_alunos_estado_operacional_v131, que depende de
-- emusys_matriculas_estado_atual — mas todo join das duas views do LA Report
-- é LEFT JOIN, e vw_alunos_estado_operacional_v131 tem um fallback pelo
-- `alunos.status` quando não existe linha na tabela do Emusys (é assim que
-- aluno pré-sincronização já funciona hoje). Resultado medido: a cadeia real
-- exige só DUAS tabelas do LA Report — `alunos` (status já nasce 'ativo' por
-- default) e `aluno_presenca` (só aluno_id/unidade_id/data_aula são NOT
-- NULL; aula_emusys_id fica NULL sem quebrar nada, o LEFT JOIN cobre). Isso
-- cabe no orçamento de até 3 tabelas que a revisão pediu — `usuarios` e
-- `professores` não entram nessa conta: são infra da MINHA própria coorte
-- (2 linhas, molde do 041), não da cadeia do LA Report. `unidade_id`
-- reaproveita uma das 3 unidades reais — não precisa existir só pro teste, e
-- reaproveitar (não inserir) tira uma tabela da lista.
insert into public.usuarios (id, nome, email) values
  (-81901, 'ZZTESTE Usuario 081', 'zzteste-081@exemplo.invalido');
insert into public.professores (id, nome, usuario_id) values
  (-81001, 'ZZTESTE Professor 081', -81901);
insert into public.alunos (id, nome, unidade_id, professor_atual_id) values
  (-81101, 'ZZTESTE Aluno 081',
   (select id from public.unidades order by codigo limit 1), -81001);
-- status='pendente' (chamada ainda não respondida) vira resultado_pedagogico
-- = 'indeterminado' na view semântica: não é 'presente' nem 'ausente' forte,
-- não tem aula_emusys (logo aula_cancelada/justificada ficam falsas), não
-- tem origem emusys/sistema. FORA do denominador — e é exatamente o cenário
-- do dia 1 do Radar (aula aconteceu, ninguém confirmou nada ainda).
insert into public.aluno_presenca
  (aluno_id, unidade_id, professor_id, data_aula, horario_aula, status) values
  (-81101, (select id from public.unidades order by codigo limit 1), -81001,
   date '2026-08-04', time '10:00', 'pendente');

do $$
declare
  v_pares_crus int;
  v_aulas      int;
  v_fora       int;
  v_antes      int;
  v_coorte     int;
  v_linhas     int;
begin
  -- ── Grão ────────────────────────────────────────────────────────────────
  -- A view semântica tem ~1,69 linha por aula. Se a nossa view herdar isso,
  -- o absenteísmo de todo mundo dobra.
  select count(*) into v_pares_crus
    from public.vw_aluno_presenca_semantica_v1
   where considera_frequencia_denominador and data_aula >= '2026-08-01';
  select count(*) into v_aulas from (
    select aluno_id, data_aula, horario_aula
      from public.vw_aluno_presenca_semantica_v1
     where considera_frequencia_denominador and data_aula >= '2026-08-01'
     group by 1,2,3) x;

  insert into _res values ('a base tem duplicata (senao o teste nao vale)',
    v_pares_crus > v_aulas, format('%s linhas, %s aulas', v_pares_crus, v_aulas));

  insert into _res values ('aulas_medidas conta AULA, nao linha',
    (select coalesce(sum(aulas_medidas),0) from public.vw_radar_aluno_sinais) <= v_aulas,
    format('soma=%s aulas=%s', (select coalesce(sum(aulas_medidas),0) from public.vw_radar_aluno_sinais), v_aulas));

  -- ── Denominador honesto ─────────────────────────────────────────────────
  -- Falta justificada, provavel e indeterminada NAO entram. Quem falta e
  -- repoe nao e quem falta e some.
  select count(*) into v_fora
    from public.vw_aluno_presenca_semantica_v1
   where not considera_frequencia_denominador and data_aula >= '2026-08-01';
  insert into _res values ('existe aula fora do denominador (senao o passo seguinte nao vale)',
    v_fora > 0, format('%s linhas fora', v_fora));

  insert into _res values ('nenhum aluno tem mais aula medida do que aula confirmada',
    not exists (
      select 1 from public.vw_radar_aluno_sinais r
       where r.aulas_medidas > (
         select count(*) from (
           select data_aula, horario_aula
             from public.vw_aluno_presenca_semantica_v1 v
            where v.aluno_id = r.aluno_id and v.considera_frequencia_denominador
              and v.data_aula >= '2026-08-01'
            group by 1,2) y)),
    'ok');

  -- O passo acima só pega o filtro se, HOJE, existir aluno da coorte com aula
  -- fora do denominador que não tem par confirmado no mesmo horário — e medido
  -- em 10/08 isso é zero (187 de 187 slots da coorte já têm confirmado junto).
  -- Dado bom demais não é prova: a mesma lacuna do `fn_hoje_brt` (018/073), onde
  -- só o CORPO da rotina prova a regra em qualquer hora do dia. Aqui o corpo é
  -- a definição da view — se o filtro sumir, o identificador some do texto.
  --
  -- Barato, mas não basta sozinho: pega DELEÇÃO (`where true`), não pega
  -- NEUTRALIZAÇÃO (`where v.considera_frequencia_denominador is not null` —
  -- sempre verdadeiro, porque a coluna nunca é NULL de verdade — mantém o
  -- identificador no texto e produz o MESMO defeito). Por isso o fixture
  -- ZZTESTE logo abaixo, que prova o COMPORTAMENTO e pega os dois de uma vez.
  insert into _res values (
    'a view cita considera_frequencia_denominador no filtro da aula [ancora dado-independente]',
    pg_get_viewdef('public.vw_radar_aluno_sinais'::regclass) ilike '%considera_frequencia_denominador%',
    'ok');

  insert into _res values (
    'aluno ZZTESTE 081 aparece na view (senao os passos seguintes nao valem)',
    exists (select 1 from public.vw_radar_aluno_sinais where aluno_id = -81101),
    'ok');

  -- A prova de verdade: um aluno cuja ÚNICA aula está FORA do denominador (a
  -- 'pendente' semeada acima) tem que ficar com aulas_medidas = 0, não 1. Se
  -- o filtro virar `true` OU `is not null` (equivalentes — a coluna nunca é
  -- NULL), essa aula passa a contar e o número sobe pra 1.
  insert into _res values (
    'aluno so com aula fora do denominador: aulas_medidas fica 0 (nao 1)',
    (select aulas_medidas from public.vw_radar_aluno_sinais where aluno_id = -81101) = 0,
    format('aulas_medidas=%s',
           (select aulas_medidas::text from public.vw_radar_aluno_sinais where aluno_id = -81101)));

  -- ── A janela virada ─────────────────────────────────────────────────────
  select count(*) into v_antes
    from public.vw_aluno_presenca_semantica_v1
   where data_aula < '2026-08-01' and considera_frequencia_denominador;
  insert into _res values ('existe aula antes de 01/08 (senao o passo seguinte nao vale)',
    v_antes > 0, format('%s linhas antes', v_antes));

  -- Se a janela vazasse pra julho, algum aluno teria mais aula medida do que
  -- existe em agosto. Este passo mede exatamente isso.
  insert into _res values ('a janela nao busca antes de 01/08',
    (select coalesce(max(aulas_medidas),0) from public.vw_radar_aluno_sinais)
      <= (select coalesce(max(n),0) from (
            select count(*) n from public.vw_aluno_presenca_semantica_v1
             where considera_frequencia_denominador and data_aula >= '2026-08-01'
             group by aluno_id) z),
    'ok');

  -- ── Coorte ──────────────────────────────────────────────────────────────
  select count(*) into v_coorte
    from public.professores where coalesce(ativo,true) and usuario_id is not null;
  insert into _res values ('a coorte e menor que a escola (senao o teste nao vale)',
    v_coorte < (select count(*) from public.professores where coalesce(ativo,true)),
    format('%s de %s professores', v_coorte,
           (select count(*) from public.professores where coalesce(ativo,true))));

  insert into _res values ('so entra aluno de professor que ja entrou no app',
    not exists (
      select 1 from public.vw_radar_aluno_sinais r
       where r.professor_id not in (
         select id from public.professores
          where coalesce(ativo,true) and usuario_id is not null)),
    'ok');

  -- ── O absenteismo e coerente com suas proprias colunas ──────────────────
  insert into _res values ('absenteismo bate com faltas/aulas da propria linha',
    not exists (
      select 1 from public.vw_radar_aluno_sinais
       where aulas_medidas > 0
         and absenteismo_pct is distinct from round(100.0*faltas_janela/aulas_medidas, 1)),
    'ok');

  insert into _res values ('sem aula medida, o absenteismo e NULO (nao zero)',
    not exists (select 1 from public.vw_radar_aluno_sinais
                 where aulas_medidas = 0 and absenteismo_pct is not null),
    'ok');

  select count(*) into v_linhas from public.vw_radar_aluno_sinais;
  insert into _res values ('a view devolve alguma coisa', v_linhas > 0, format('%s linhas', v_linhas));

  -- ── Um aluno, uma linha ─────────────────────────────────────────────────
  insert into _res values ('um aluno aparece uma vez so',
    not exists (select 1 from public.vw_radar_aluno_sinais
                 group by aluno_id having count(*) > 1), 'ok');

  -- ── Competência é BRT, nao UTC cru (I1) ──────────────────────────────────
  -- current_date da conexão é UTC. Entre 21h e meia-noite BRT do último dia
  -- do mês ele já é dia 1 do mês seguinte — a 018 e a 073 já pagaram esse
  -- preço pra fn_hoje_brt/fn_competencia_feedback existirem. Se a 081 voltar
  -- a usar current_date cru, o semáforo (que o professor grava com
  -- fn_competencia_feedback, via app_professor_feedback_salvar da 074) some
  -- do Radar exatamente nessas 3h por mês — inclusive o que acabou de ser
  -- escrito. Corpo da view é a prova que não depende da hora em que RODA.
  insert into _res values (
    'a view usa fn_competencia_feedback, nao current_date cru [ancora horario-independente]',
    pg_get_viewdef('public.vw_radar_aluno_sinais'::regclass) ilike '%fn_competencia_feedback%'
      and pg_get_viewdef('public.vw_radar_aluno_sinais'::regclass) not ilike '%current_date%',
    'ok');

  -- ── A porta e a funcao, nao a view (C1) ──────────────────────────────────
  -- Achado crítico da revisão: sem isto, a view roda como DEFINER (dono é
  -- quem aplicou a migration) e passa por cima da RLS de
  -- aluno_feedback_professor — qualquer authenticated lia observacao/
  -- feedback/avisou_que_sai de aluno de OUTRO professor pelo PostgREST. A
  -- fronteira mais dura da casa: o canal do professor nunca alcança dado de
  -- colega. A RPC da Task 4 (security definer, com guard) é quem lê daqui
  -- pra frente — mesmo padrão de vw_fabio_contexto_experimental (028).
  insert into _res values ('a view NAO e legivel por authenticated (a porta e a funcao)',
    not has_table_privilege('authenticated', 'public.vw_radar_aluno_sinais', 'SELECT'),
    'ok');
end $$;

select json_build_object(
         'falhas', (select count(*) from _res where not ok),
         'detalhe', coalesce((select json_agg(json_build_object(
                                'passo', caso, 'esperado', 'ok', 'obtido', detalhe))
                                from _res where not ok), '[]'::json)
       ) as resumo;
