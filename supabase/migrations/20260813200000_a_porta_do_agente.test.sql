-- Contrato da porta do agente.
--
-- O ponto deste teste nao e "a funcao existe" -- e que ela esteja alcancavel
-- por QUEM de fato chama. A `20260813190000` publicou a contagem so para
-- `service_role`, e o consumidor real (o postgres-mcp do Hermes) conecta como
-- `fabio_agent`. Resultado medido em 13/08/2026: o Fabio respondia o numero
-- certo por conta propria e dizia "preciso conferir" quando cobrado dos tres
-- numeros -- porque nunca conseguiu chamar a funcao.

create temporary table _porta_res(caso text, ok boolean, detalhe text)
on commit drop;

create or replace function pg_temp.checar_porta(p_caso text, p_ok boolean, p_detalhe text)
returns void
language plpgsql
as $$
begin
  insert into _porta_res values (p_caso, coalesce(p_ok, false), p_detalhe);
end
$$;

do $$
begin
  perform pg_temp.checar_porta(
    'o papel que o agente REALMENTE usa alcanca a contagem',
    has_function_privilege('fabio_agent',
      'public.app_professor_carteira_contagem(integer)', 'EXECUTE'),
    'fabio_agent e quem o postgres-mcp do Hermes usa'
  );

  perform pg_temp.checar_porta(
    'o worker da ponte continua alcancando',
    has_function_privilege('service_role',
      'public.app_professor_carteira_contagem(integer)', 'EXECUTE'),
    'service_role'
  );

  -- A porta se abriu para o agente, nao para o mundo.
  perform pg_temp.checar_porta(
    'abrir para o agente NAO abriu para o cliente',
    not has_function_privilege('anon',
      'public.app_professor_carteira_contagem(integer)', 'EXECUTE')
    and not has_function_privilege('authenticated',
      'public.app_professor_carteira_contagem(integer)', 'EXECUTE'),
    'anon/authenticated seguem fora'
  );

  -- O argumento de que isto nao alarga nada: o agente ja lia os mesmos dados
  -- por outro caminho. Se um dia isso deixar de ser verdade, a justificativa
  -- da migration cai junto -- e este passo avisa.
  perform pg_temp.checar_porta(
    'o agente ja alcancava os mesmos dados pela via crua (nada novo foi aberto)',
    has_table_privilege('fabio_agent', 'public.vw_fabio_carteira_professor', 'SELECT'),
    'se isto virar false, revisar a justificativa da 20260813200000'
  );
end
$$;

select json_build_object(
  'teste', '20260813200000-a-porta-do-agente',
  'falhas', (select count(*) from _porta_res where not ok),
  'detalhe', coalesce((select json_agg(json_build_object(
    'passo', caso, 'esperado', 'ok', 'obtido', coalesce(detalhe, '<NULL>'))
  ) from _porta_res where not ok), '[]'::json)
) as resumo;
