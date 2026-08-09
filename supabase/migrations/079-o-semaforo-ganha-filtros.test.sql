-- Teste da 079. Roda dentro de BEGIN/ROLLBACK do rodar-teste-sql.mjs.
--
-- O que precisa ficar provado:
--   1. filtrar por "saudável" mostra o verde CALADO (o que a lista padrão esconde)
--   2. filtrar por professor não devolve aluno de colega
--   3. cada faceta ignora o próprio filtro (senão vira beco sem saída)
--   4. `sem_resposta` é um coração de verdade, não um buraco
create temporary table _res(caso text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_coord  uuid;
  v_prof   int;
  v_uni    uuid;
  v_alunos int[];
  v_prof2  int;
  v_uni2   uuid;
  v_aluno2 int;
  v_comp   date := public.fn_competencia_feedback(null);
  v_r      jsonb;
  v_lista  jsonb;
  v_erro   text;
begin
  select u.auth_user_id into v_coord
    from public.la_teacher_coordenacao c
    join public.usuarios u on u.id = c.usuario_id
   where u.auth_user_id is not null and coalesce(u.ativo, true)
   limit 1;

  select v.professor_id, (array_agg(distinct v.unidade_id))[1]
    into v_prof, v_uni
    from public.vw_jornada_professor_atual v
    join public.alunos a on a.id = v.aluno_id and a.arquivado_em is null
   where v.unidade_id is not null
   group by v.professor_id
  having count(distinct v.aluno_id) >= 3
   limit 1;

  select array_agg(x.aluno_id) into v_alunos from (
    select distinct v.aluno_id
      from public.vw_jornada_professor_atual v
      join public.alunos a on a.id = v.aluno_id and a.arquivado_em is null
     where v.professor_id = v_prof
     order by v.aluno_id limit 3) x;

  -- Um aluno de OUTRO professor E outra unidade: a isca dos dois filtros.
  select v.professor_id, v.unidade_id, v.aluno_id
    into v_prof2, v_uni2, v_aluno2
    from public.vw_jornada_professor_atual v
    join public.alunos a on a.id = v.aluno_id and a.arquivado_em is null
   where v.unidade_id is not null and v.unidade_id <> v_uni
     and v.professor_id <> v_prof and not (v.aluno_id = any(v_alunos))
   limit 1;

  insert into _res values ('cenario montado',
    v_coord is not null and array_length(v_alunos,1) = 3 and v_prof2 is not null,
    format('prof=%s uni=%s prof2=%s uni2=%s', v_prof, v_uni, v_prof2, v_uni2));

  insert into public.aluno_feedback_professor
    (aluno_id, professor_id, unidade_id, competencia, feedback,
     pratica_em_casa, evolucao, animo, observacao, respondido_em)
  values
    (v_alunos[1], v_prof, v_uni, v_comp, 'vermelho', 'nao','parado','desanimado', null, now()),
    -- VERDE CALADO: fora da lista padrão, dentro do filtro "saudável".
    (v_alunos[2], v_prof, v_uni, v_comp, 'verde', 'sim','evoluindo','animado', null, now()),
    (v_aluno2,   v_prof2, v_uni2, v_comp, 'verde', 'sim','evoluindo','animado',
     'ISCA_079 recado do outro professor', now());

  perform set_config('request.jwt.claim.sub', v_coord::text, true);

  -- ── 1. Sem filtro: verde calado NÃO aparece ───────────────────────────────
  v_r := public.app_coordenacao_feedback_mes();
  insert into _res values ('sem filtro, verde calado fica fora',
    not exists (select 1 from jsonb_array_elements(v_r -> 'alunos') e
                 where (e ->> 'aluno_id')::int = v_alunos[2]),
    (v_r ->> 'total_lista'));

  -- ── 2. Filtrando por SAUDÁVEL, o verde calado aparece ─────────────────────
  v_r := public.app_coordenacao_feedback_mes(null, null, 200, 'verde');
  v_lista := v_r -> 'alunos';
  insert into _res values ('filtro saudavel mostra o verde calado',
    exists (select 1 from jsonb_array_elements(v_lista) e
             where (e ->> 'aluno_id')::int = v_alunos[2]),
    v_lista::text);
  insert into _res values ('filtro saudavel nao traz vermelho',
    not exists (select 1 from jsonb_array_elements(v_lista) e
                 where e ->> 'feedback' = 'vermelho'),
    'lista de verdes');

  -- ── 3. `sem_resposta` é um coração de verdade ─────────────────────────────
  v_r := public.app_coordenacao_feedback_mes(null, null, 5, 'sem_resposta');
  insert into _res values ('sem_resposta lista quem nao respondeu',
    (v_r ->> 'total_lista')::int > 100
      and jsonb_array_length(v_r -> 'alunos') = 5
      and (v_r ->> 'truncado')::boolean,
    format('total=%s itens=%s', v_r ->> 'total_lista',
           jsonb_array_length(v_r -> 'alunos')));

  begin
    perform public.app_coordenacao_feedback_mes(null, null, 200, 'roxo');
    insert into _res values ('coracao invalido explode', false, 'aceitou roxo');
  exception when others then
    v_erro := sqlerrm;
    insert into _res values ('coracao invalido explode',
      v_erro = 'coracao_invalido', v_erro);
  end;

  -- ── 4. Filtro de PROFESSOR não devolve aluno de colega ────────────────────
  v_r := public.app_coordenacao_feedback_mes(null, null, 200, null, v_prof);
  insert into _res values ('filtro de professor nao traz aluno de colega',
    not exists (select 1 from jsonb_array_elements(v_r -> 'alunos') e
                 where (e ->> 'professor_id')::int <> v_prof)
    and not exists (select 1 from jsonb_array_elements(v_r -> 'alunos') e
                     where (e ->> 'aluno_id')::int = v_aluno2),
    format('professor %s', v_prof));

  -- Sem o filtro a isca aparece — senão o passo acima passaria por acidente.
  v_r := public.app_coordenacao_feedback_mes();
  insert into _res values ('sem filtro, a isca do colega aparece',
    exists (select 1 from jsonb_array_elements(v_r -> 'alunos') e
             where (e ->> 'aluno_id')::int = v_aluno2),
    format('isca %s', v_aluno2));

  -- ── 5. FACETAS: cada uma cega pro próprio filtro ──────────────────────────
  v_r := public.app_coordenacao_feedback_mes(null, v_uni);
  insert into _res values ('filtrando unidade, o seletor de unidade mantem as outras',
    jsonb_array_length(v_r #> '{filtros,unidades}') >= 2,
    (v_r #> '{filtros,unidades}')::text);

  v_r := public.app_coordenacao_feedback_mes(null, null, 200, null, v_prof);
  insert into _res values ('filtrando professor, o seletor de professor mantem os outros',
    jsonb_array_length(v_r #> '{filtros,professores}') >= 2,
    format('%s opcoes', jsonb_array_length(v_r #> '{filtros,professores}')));

  v_r := public.app_coordenacao_feedback_mes(null, null, 200, 'verde');
  insert into _res values ('filtrando coracao, o seletor de coracao mantem os outros',
    jsonb_array_length(v_r #> '{filtros,coracoes}') >= 2,
    (v_r #> '{filtros,coracoes}')::text);

  -- E a faceta RESPEITA as outras: com o professor escolhido, o seletor de
  -- unidade só oferece as unidades dele.
  v_r := public.app_coordenacao_feedback_mes(null, null, 200, null, v_prof2);
  insert into _res values ('faceta de unidade respeita o filtro de professor',
    not exists (select 1 from jsonb_array_elements(v_r #> '{filtros,unidades}') e
                 where (e ->> 'unidade_id')::uuid not in (
                   select distinct v.unidade_id from public.vw_jornada_professor_atual v
                    where v.professor_id = v_prof2 and v.unidade_id is not null)),
    (v_r #> '{filtros,unidades}')::text);
end $$;

select json_build_object(
         'falhas', (select count(*) from _res where not ok),
         'detalhe', coalesce((select json_agg(json_build_object('caso', caso, 'detalhe', detalhe))
                                from _res where not ok), '[]'::json)
       ) as resumo;
