-- As nove guardas de ACL que a 090, a 091 e a 095 protegiam -- e que estavam
-- apagadas porque os baselines das tres estao vermelhos.
--
-- Cada passo aqui foi copiado dos testes originais. O objetivo nao e provar
-- que a porta esta fechada hoje (isso ja foi medido); e garantir que, se
-- alguem abrir, ALGUEM AVISA.

create temporary table _guardas_wa_res(caso text, ok boolean, detalhe text)
on commit drop;

create or replace function pg_temp.checar_wa(p_caso text, p_ok boolean, p_detalhe text)
returns void
language plpgsql
as $$
begin
  insert into _guardas_wa_res values (p_caso, coalesce(p_ok, false), p_detalhe);
end
$$;

do $$
declare
  r record;
begin
  -- Portas de worker: anon e authenticated fora, service_role dentro.
  for r in
    select unnest(array[
      'public.fabio_iniciar_acao(integer,text,text,text,jsonb)',
      'public.fabio_confirmar_registro(integer,uuid,text)',
      'public.fabio_claim_registro_recibo(integer,integer)',
      'public.fabio_concluir_registro_recibo(uuid,uuid,text,text)',
      'public.fabio_falhar_registro_recibo(uuid,uuid,text)',
      'public.fabio_registro_recibo_dados(integer,uuid)'
    ]) as fn
  loop
    perform pg_temp.checar_wa(
      'porta de worker fechada para o cliente: ' || r.fn,
      not has_function_privilege('anon', r.fn, 'EXECUTE')
        and not has_function_privilege('authenticated', r.fn, 'EXECUTE')
        and has_function_privilege('service_role', r.fn, 'EXECUTE'),
      format('anon=%s auth=%s sr=%s',
             has_function_privilege('anon', r.fn, 'EXECUTE'),
             has_function_privilege('authenticated', r.fn, 'EXECUTE'),
             has_function_privilege('service_role', r.fn, 'EXECUTE'))
    );
  end loop;

  -- Interna de verdade: ninguem executa, nem o worker.
  perform pg_temp.checar_wa(
    'fn_confirmar_registro_core e interna: ninguem executa',
    not has_function_privilege('anon', 'public.fn_confirmar_registro_core(integer,uuid,uuid,text)', 'EXECUTE')
      and not has_function_privilege('authenticated', 'public.fn_confirmar_registro_core(integer,uuid,uuid,text)', 'EXECUTE')
      and not has_function_privilege('service_role', 'public.fn_confirmar_registro_core(integer,uuid,uuid,text)', 'EXECUTE'),
    'anon/authenticated/service_role'
  );

  -- Tabelas do fluxo de acao: o cliente nao le.
  for r in
    select unnest(array['public.fabio_acoes_pendentes', 'public.fabio_acao_eventos']) as tb
  loop
    perform pg_temp.checar_wa(
      'tabela do fluxo de acao fechada para o cliente: ' || r.tb,
      not has_table_privilege('anon', r.tb, 'SELECT')
        and not has_table_privilege('authenticated', r.tb, 'SELECT'),
      format('anon=%s auth=%s',
             has_table_privilege('anon', r.tb, 'SELECT'),
             has_table_privilege('authenticated', r.tb, 'SELECT'))
    );
  end loop;
end
$$;

select json_build_object(
  'teste', '20260813180000-guardas-resgatadas-do-whatsapp',
  'falhas', (select count(*) from _guardas_wa_res where not ok),
  'detalhe', coalesce((select json_agg(json_build_object(
    'passo', caso, 'esperado', 'ok', 'obtido', coalesce(detalhe, '<NULL>'))
  ) from _guardas_wa_res where not ok), '[]'::json)
) as resumo;
