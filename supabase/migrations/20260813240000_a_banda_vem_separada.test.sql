-- A carteira vem fatiada, e a fatia bate com a régua canônica da casa.

create temporary table _fatia_res(caso text, ok boolean, detalhe text) on commit drop;

create or replace function pg_temp.checar_fatia(p_caso text, p_ok boolean, p_detalhe text)
returns void language plpgsql as $$
begin insert into _fatia_res values (p_caso, coalesce(p_ok,false), p_detalhe); end $$;

do $$
declare
  v33 jsonb;  -- Ramon: 13 regulares + 34 so de atividade extra = 47
  v25 jsonb;  -- Matheus: 20, nenhuma atividade extra
  vctx jsonb;
  v_conferencia integer;
begin
  v33 := public.fn_carteira_fatiada(33);
  v25 := public.fn_carteira_fatiada(25);

  perform pg_temp.checar_fatia(
    'Ramon: 47 pessoas = 13 regulares + 34 so de atividade extra',
    (v33->>'pessoas')::int = 47
      and (v33->>'regulares')::int = 13
      and (v33->>'so_atividade_extra')::int = 34
      and (v33->>'em_atividade_extra')::int = 39,
    coalesce(v33::text,'<NULL>'));

  perform pg_temp.checar_fatia(
    'as atividades extras vem NOMEADAS, nao so contadas',
    jsonb_array_length(coalesce(v33->'atividades_extras','[]'::jsonb)) >= 2
      and exists (select 1 from jsonb_array_elements(v33->'atividades_extras') a
                   where a->>'curso' ilike '%banda%'),
    coalesce((v33->'atividades_extras')::text,'<NULL>'));

  perform pg_temp.checar_fatia(
    'Matheus: 20 regulares e NENHUMA atividade extra -- a lista fica vazia',
    (v25->>'pessoas')::int = 20
      and (v25->>'regulares')::int = 20
      and (v25->>'em_atividade_extra')::int = 0
      and jsonb_array_length(coalesce(v25->'atividades_extras','[]'::jsonb)) = 0,
    coalesce(v25::text,'<NULL>'));

  -- A soma nao pode inventar nem perder gente: regulares + so_extra = pessoas.
  perform pg_temp.checar_fatia(
    'regulares + so_atividade_extra fecha com o total, em TODO professor',
    not exists (
      select 1
        from (select distinct professor_id as pid
                from public.vw_professor_carteira_pessoa_canonica_sombra) p
       cross join lateral public.fn_carteira_fatiada(p.pid) f
       where (f->>'regulares')::int + (f->>'so_atividade_extra')::int
             <> (f->>'pessoas')::int),
    'identidade da fatia');

  -- A regua e a MARCA canonica, nao o nome do curso. Se alguem trocar o
  -- criterio por ILIKE, este passo cai.
  select count(*) into v_conferencia
    from public.vw_professor_carteira_pessoa_canonica_sombra c
   where c.professor_id = 33
     and exists (select 1 from unnest(coalesce(c.curso_ids, array[]::integer[])) cid
                  join public.cursos cu on cu.id = cid
                 where not coalesce(cu.is_projeto_banda,false));
  perform pg_temp.checar_fatia(
    'os regulares derivam de cursos.is_projeto_banda, medido a parte',
    (v33->>'regulares')::int = v_conferencia,
    format('fatia=%s conferencia=%s', v33->>'regulares', v_conferencia));

  -- O contexto que o Fabio fala carrega a fatia, nao so o total.
  vctx := public.fabio_contexto_professor(33);
  perform pg_temp.checar_fatia(
    'o contexto do Fabio carrega a carteira fatiada',
    (vctx->'carteira'->>'regulares')::int = 13
      and (vctx->>'total_alunos_carteira')::int = 47
      and coalesce(vctx->'carteira'->>'nota','') <> '',
    coalesce((vctx->'carteira')::text,'<NULL>'));

  -- O resto do contexto nao pode ter sido perdido na reescrita.
  perform pg_temp.checar_fatia(
    'o contexto preserva agenda, pendencias e o passivo fora da cobranca',
    vctx ? 'hoje' and vctx->'hoje' ? 'aulas'
      and vctx ? 'pendencias_cobraveis'
      and vctx ? 'registro_fora_da_cobranca'
      and (vctx->>'ok')::boolean is true,
    coalesce((select jsonb_agg(k) from jsonb_object_keys(vctx) k)::text,'<NULL>'));

  -- A RPC do agente pergunta pra regua em vez de recontar.
  perform pg_temp.checar_fatia(
    'a RPC do agente deriva da regua unica',
    (select pg_get_functiondef(p.oid) from pg_proc p
       join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='app_professor_carteira_contagem')
      ilike '%fn_carteira_fatiada%'
    and (public.app_professor_carteira_contagem(33)->>'regulares')::int = 13,
    coalesce(public.app_professor_carteira_contagem(33)::text,'<NULL>'));

  perform pg_temp.checar_fatia(
    'ACL: worker e agente dentro, cliente fora',
    has_function_privilege('service_role','public.fn_carteira_fatiada(integer)','EXECUTE')
      and has_function_privilege('fabio_agent','public.fn_carteira_fatiada(integer)','EXECUTE')
      and not has_function_privilege('anon','public.fn_carteira_fatiada(integer)','EXECUTE')
      and not has_function_privilege('authenticated','public.fn_carteira_fatiada(integer)','EXECUTE'),
    'porta de worker/agente');
end $$;

select json_build_object(
  'teste', '20260813240000-a-banda-vem-separada',
  'falhas', (select count(*) from _fatia_res where not ok),
  'detalhe', coalesce((select json_agg(json_build_object(
    'passo', caso, 'esperado','ok','obtido', coalesce(detalhe,'<NULL>'))
  ) from _fatia_res where not ok), '[]'::json)
) as resumo;
