-- Teste da 087. Aqui moram as duas regras que a casa já pagou pra aprender:
-- UM NÚMERO SÓ (080) e FACETA CEGA AO PRÓPRIO FILTRO (071/079). E a fronteira
-- nova: nenhum agregado de professor feito com o que o professor escreveu.
create temporary table _res(caso text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_coord uuid;
  v_r     jsonb;
  v_uni   uuid;
  v_chip  int;
begin
  select u.auth_user_id into v_coord
    from public.la_teacher_coordenacao c
    join public.usuarios u on u.id = c.usuario_id
   where u.auth_user_id is not null and coalesce(u.ativo, true) limit 1;

  -- ── Guard ───────────────────────────────────────────────────────────────
  perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
  begin
    perform public.app_coordenacao_radar();
    insert into _res values ('professor nao abre o radar', false, 'passou sem guard');
  exception when others then
    insert into _res values ('professor nao abre o radar',
      sqlerrm like '%apenas_admin%', sqlerrm);
  end;

  perform set_config('request.jwt.claim.sub', v_coord::text, true);
  v_r := public.app_coordenacao_radar();

  -- ── UM NÚMERO SÓ ────────────────────────────────────────────────────────
  insert into _res values ('resumo e lista contam a mesma coisa',
    (v_r #>> '{resumo,alunos}')::int = (v_r ->> 'total_lista')::int,
    format('resumo=%s lista=%s', v_r #>> '{resumo,alunos}', v_r ->> 'total_lista'));

  insert into _res values ('a soma dos chips de unidade e o total',
    (select coalesce(sum((e->>'alunos')::int),0)
       from jsonb_array_elements(v_r #> '{filtros,unidades}') e)
      = (v_r ->> 'total_lista')::int,
    format('chips=%s lista=%s',
      (select coalesce(sum((e->>'alunos')::int),0)
         from jsonb_array_elements(v_r #> '{filtros,unidades}') e),
      v_r ->> 'total_lista'));

  -- ── O chip promete o que o clique entrega ───────────────────────────────
  select (e ->> 'unidade_id')::uuid, (e ->> 'alunos')::int into v_uni, v_chip
    from jsonb_array_elements(v_r #> '{filtros,unidades}') e
   order by (e ->> 'alunos')::int desc limit 1;

  if v_uni is not null then
    insert into _res values ('o chip da unidade bate com a lista que ela abre',
      (public.app_coordenacao_radar(v_uni) ->> 'total_lista')::int = v_chip,
      format('chip=%s lista=%s', v_chip,
             public.app_coordenacao_radar(v_uni) ->> 'total_lista'));

    -- ── FACETA CEGA AO PRÓPRIO FILTRO ─────────────────────────────────────
    insert into _res values ('com unidade escolhida, a lista de unidades NAO encolhe',
      jsonb_array_length(public.app_coordenacao_radar(v_uni) #> '{filtros,unidades}')
        = jsonb_array_length(v_r #> '{filtros,unidades}'),
      format('antes=%s depois=%s',
        jsonb_array_length(v_r #> '{filtros,unidades}'),
        jsonb_array_length(public.app_coordenacao_radar(v_uni) #> '{filtros,unidades}')));

    insert into _res values ('mas a lista de professores RESPEITA a unidade',
      jsonb_array_length(public.app_coordenacao_radar(v_uni) #> '{filtros,professores}')
        <= jsonb_array_length(v_r #> '{filtros,professores}'), 'ok');
  end if;

  -- ── FRONTEIRA: nada do que o professor escreveu vira numero dele ────────
  insert into _res values ('as medias por professor nao carregam semaforo',
    not exists (
      select 1 from jsonb_array_elements(v_r #> '{medias,professores}') p
       where p ? 'feedback' or p ? 'vermelhos' or p ? 'pratica'),
    coalesce((v_r #>> '{medias,professores,0}'), '(vazio)'));

  -- ── FRONTEIRA: pagamento nunca aparece ──────────────────────────────────
  insert into _res values ('a resposta nao menciona pagamento',
    v_r::text not ilike '%inadimplen%' and v_r::text not ilike '%parcela%'
      and v_r::text not ilike '%health_score%', 'ok');

  -- ── A base e declarada ──────────────────────────────────────────────────
  insert into _res values ('o resumo declara desde quando mede',
    (v_r #>> '{resumo,base_desde}') = '2026-08-01', v_r #>> '{resumo,base_desde}');
  insert into _res values ('e a media E a mediana vem as duas',
    (v_r #> '{resumo,absenteismo_media}') is not null
      and (v_r #> '{resumo,absenteismo_mediana}') is not null,
    v_r #>> '{resumo}');

  -- ── A nota respeita o piso ──────────────────────────────────────────────
  insert into _res values ('linha com poucos sinais vem sem nota',
    not exists (
      select 1 from jsonb_array_elements(v_r -> 'linhas') l
       where (l #>> '{nota,suficiente}')::boolean = false
         and (l #> '{nota,nota}') is not null and (l #>> '{nota,nota}') <> 'null'),
    'ok');

  -- ── Status invalido e recusado ──────────────────────────────────────────
  begin
    perform public.app_coordenacao_radar(null, null, 'roxo');
    insert into _res values ('status invalido e recusado', false, 'aceitou');
  exception when others then
    insert into _res values ('status invalido e recusado',
      sqlerrm like '%status_invalido%', sqlerrm);
  end;
end $$;

select json_build_object(
         'falhas', (select count(*) from _res where not ok),
         'detalhe', coalesce((select json_agg(json_build_object(
                                'passo', caso, 'esperado', 'ok', 'obtido', detalhe))
                                from _res where not ok), '[]'::json)
       ) as resumo;
