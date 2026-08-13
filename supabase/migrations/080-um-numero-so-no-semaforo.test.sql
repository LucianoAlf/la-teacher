-- Teste da 080. Roda dentro de BEGIN/ROLLBACK do rodar-teste-sql.mjs.
--
-- Um número só: o KPI do topo, o contador da lista e o chip do filtro têm que
-- responder a mesma pergunta. O passo que importa é a INVARIANTE — com um
-- coração escolhido, a lista é o grupo inteiro, então `total_lista` e o número
-- daquele coração no resumo TÊM que bater. Com `distinct aluno_id` no resumo
-- eles divergiam em 6 (os alunos que fazem aula com dois professores).
create temporary table _res(caso text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_coord  uuid;
  v_pares  int;
  v_unicos int;
  v_uni    uuid;
  v_r      jsonb;
  v_chip   int;
  v_lista  int;
begin
  select u.auth_user_id into v_coord
    from public.la_teacher_coordenacao c
    join public.usuarios u on u.id = c.usuario_id
   where u.auth_user_id is not null and coalesce(u.ativo, true)
   limit 1;

  select count(*), count(distinct aluno_id) into v_pares, v_unicos from (
    select v.aluno_id, v.professor_id
      from public.vw_jornada_professor_atual v
      join public.alunos a on a.id = v.aluno_id and a.arquivado_em is null
     group by v.aluno_id, v.professor_id) x;

  -- Sem aluno com dois professores, o passo seguinte passaria por acidente.
  insert into _res values ('a base tem aluno com dois professores (senao o teste nao vale)',
    v_pares > v_unicos, format('%s pares, %s alunos distintos', v_pares, v_unicos));

  perform set_config('request.jwt.claim.sub', v_coord::text, true);

  -- ── O grão ────────────────────────────────────────────────────────────────
  -- SEM filtro nenhum, o resumo cobre o universo inteiro: tem que ser o número
  -- de PARES. (Com um coração escolhido este número muda, porque o recorte
  -- muda — foi assim que a primeira versão deste teste se enganou sozinha.)
  v_r := public.app_coordenacao_feedback_mes();
  insert into _res values ('o numero e o de PARES, nao o de alunos distintos',
    (v_r #>> '{resumo,alunos}')::int = v_pares
      and (v_r #>> '{resumo,alunos}')::int <> v_unicos,
    format('resumo=%s pares=%s unicos=%s', v_r #>> '{resumo,alunos}', v_pares, v_unicos));

  -- ── A invariante ──────────────────────────────────────────────────────────
  -- Com um coração escolhido a lista é o GRUPO INTEIRO daquele coração, então
  -- o contador da lista e o número daquele coração no resumo têm que bater. Era
  -- aqui que a tela mostrava 1155 no topo e 1161 na lista.
  v_r := public.app_coordenacao_feedback_mes(null, null, 1, 'sem_resposta');
  insert into _res values ('resumo e lista contam a mesma coisa',
    (v_r #>> '{resumo,alunos}')::int = (v_r ->> 'total_lista')::int
      and (v_r #>> '{resumo,sem_resposta}')::int = (v_r ->> 'total_lista')::int,
    format('resumo=%s sem_resposta=%s lista=%s', v_r #>> '{resumo,alunos}',
           v_r #>> '{resumo,sem_resposta}', v_r ->> 'total_lista'));

  -- ── O chip do filtro promete o que o clique entrega ───────────────────────
  select (e ->> 'unidade_id')::uuid, (e ->> 'alunos')::int
    into v_uni, v_chip
    from jsonb_array_elements(v_r #> '{filtros,unidades}') e
   order by (e ->> 'alunos')::int desc
   limit 1;

  v_r := public.app_coordenacao_feedback_mes(null, v_uni, 1, 'sem_resposta');
  v_lista := (v_r ->> 'total_lista')::int;
  insert into _res values ('o chip da unidade bate com a lista que ela abre',
    v_chip = v_lista, format('chip=%s lista=%s', v_chip, v_lista));

  -- Pessoa se conta uma vez: professor não vira par. A referência tem que ser
  -- montada no MESMO grão da função (uma linha por aluno+professor, unidade
  -- resolvida por `(array_agg(...))[1]`) — comparar com a view crua compara
  -- duas perguntas diferentes e o passo falha sem haver defeito.
  --
  -- A CHAMADA VEM INLINE, sem reusar `v_r`. O passo do chip logo acima
  -- reatribui `v_r` com o coração `sem_resposta`, e este passo estava lendo
  -- aquele recorte contra uma referência que só filtra por UNIDADE: comparava
  -- duas perguntas diferentes. Medido em 13/08/2026, com a unidade maior:
  -- **sem coração = 30, referência = 30** (a função acerta), e o passo
  -- reprovava exibindo os **28** do recorte `sem_resposta`. O próprio
  -- cabeçalho deste arquivo já avisava que "com um coração escolhido este
  -- número muda" -- a asserção é que não tinha lido o próprio aviso.
  insert into _res values ('professores continuam contados como pessoa',
    (public.app_coordenacao_feedback_mes(null, v_uni, 1) #>> '{resumo,professores}')::int = (
      select count(distinct professor_id) from (
        select v.aluno_id, v.professor_id, (array_agg(v.unidade_id))[1] as unidade_id
          from public.vw_jornada_professor_atual v
          join public.alunos a on a.id = v.aluno_id and a.arquivado_em is null
         group by v.aluno_id, v.professor_id) g
       where g.unidade_id = v_uni),
    v_r #>> '{resumo,professores}');
end $$;

select json_build_object(
         'falhas', (select count(*) from _res where not ok),
         'detalhe', coalesce((select json_agg(json_build_object(
                                'passo', caso, 'esperado', 'ok', 'obtido', detalhe))
                                from _res where not ok), '[]'::json)
       ) as resumo;
