-- As guardas de ACL que a 093 e a 099 protegiam, agora numa migration viva.
--
-- Cada assercao aqui foi copiada do teste que vai ser marcado como SUPERADO.
-- Sem este arquivo, marcar SUPERADA apagaria a guarda junto com o contrato
-- velho -- e nenhum alarme tocaria.

create temporary table _guardas_res(caso text, ok boolean, detalhe text)
on commit drop;

create or replace function pg_temp.checar_guardas(p_caso text, p_ok boolean, p_detalhe text)
returns void
language plpgsql
as $$
begin
  insert into _guardas_res values (p_caso, coalesce(p_ok, false), p_detalhe);
end
$$;

do $$
begin
  -- Resgatada da 093 -------------------------------------------------------
  perform pg_temp.checar_guardas(
    'fn_materializar_presenca_padrao e interna: ninguem executa',
    not has_function_privilege('anon', 'public.fn_materializar_presenca_padrao(uuid,integer)', 'EXECUTE')
      and not has_function_privilege('authenticated', 'public.fn_materializar_presenca_padrao(uuid,integer)', 'EXECUTE')
      and not has_function_privilege('service_role', 'public.fn_materializar_presenca_padrao(uuid,integer)', 'EXECUTE'),
    'anon/authenticated/service_role'
  );

  perform pg_temp.checar_guardas(
    'fn_remover_campos_comuns_da_fatia e interna: ninguem executa',
    not has_function_privilege('anon', 'public.fn_remover_campos_comuns_da_fatia(jsonb,jsonb)', 'EXECUTE')
      and not has_function_privilege('authenticated', 'public.fn_remover_campos_comuns_da_fatia(jsonb,jsonb)', 'EXECUTE')
      and not has_function_privilege('service_role', 'public.fn_remover_campos_comuns_da_fatia(jsonb,jsonb)', 'EXECUTE'),
    'anon/authenticated/service_role'
  );

  -- Resgatada da 099 -------------------------------------------------------
  perform pg_temp.checar_guardas(
    'app_confirmar_registro e do professor logado, nao do anonimo',
    has_function_privilege('authenticated', 'public.app_confirmar_registro(uuid,text)', 'EXECUTE')
      and not has_function_privilege('anon', 'public.app_confirmar_registro(uuid,text)', 'EXECUTE'),
    'authenticated deve ser true, anon false'
  );
end
$$;

select json_build_object(
  'teste', '20260813170000-guardas-resgatadas-da-presenca',
  'falhas', (select count(*) from _guardas_res where not ok),
  'detalhe', coalesce((select json_agg(json_build_object(
    'passo', caso, 'esperado', 'ok', 'obtido', coalesce(detalhe, '<NULL>'))
  ) from _guardas_res where not ok), '[]'::json)
) as resumo;
