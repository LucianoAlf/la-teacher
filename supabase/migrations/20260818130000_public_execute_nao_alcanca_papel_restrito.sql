-- `PUBLIC` é todo mundo — inclusive os papéis criados para não poder.
--
-- ACHADO (18/08/2026, levantado ao tentar provar a fronteira do Fábio):
-- 179 funções do `public` têm EXECUTE concedido ao pseudo-papel PUBLIC. Como
-- PUBLIC vale para TODO papel do cluster, isso alcança `fabio_agent`,
-- `sol_acesso_restrito`, `mila_acesso_restrito`, `lia_acesso_restrito`,
-- `maria_lareport_rpc`, `ml_jobs` — e alcançaria o `fabio_professor_agente`
-- que acabou de nascer para ser magro.
--
-- Das 179, as que importam são as **38 `SECURITY DEFINER`**: elas rodam com o
-- privilégio do dono, então a falta de privilégio de tabela do papel restrito
-- não segura nada. Entre elas:
--   - `get_faturas_alunos_financeiro_v1` — devolve fatura de aluno;
--   - `app_falta_professor_cancelar_aulas` — CANCELA AULAS;
--   - `materializar_projecao_contrato`, `recalcular_projecao` — ESCREVEM.
-- As outras 141 são `SECURITY INVOKER`: rodam com o privilégio de quem chama,
-- então um papel sem privilégio de tabela não tira nada delas. Ficam como estão.
--
-- POR QUE ESTA REVOGAÇÃO É SEGURA (medido antes de escrever, não depois):
-- as 38 já têm grant EXPLÍCITO para `anon`, `authenticated` e `service_role` —
-- os três papéis por onde o app e as edge functions realmente chegam. Tirar o
-- PUBLIC não remove acesso de nenhum consumidor real; remove de quem nunca
-- deveria ter tido. E o laço abaixo só revoga quando esse grant explícito
-- existe, então é impossível esta migration deixar uma função inalcançável.
--
-- Trigger não se preocupa: a permissão de função de gatilho é checada na
-- CRIAÇÃO do trigger, não a cada disparo.

do $function$
declare
  r record;
  v_revogadas integer := 0;
begin
  for r in
    select p.oid::regprocedure::text as assinatura
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prokind = 'f'
       and p.prosecdef                                    -- só as que ignoram privilégio
       and exists (select 1 from unnest(coalesce(p.proacl, '{}')) a
                    where a::text like '=%')              -- ainda abertas ao PUBLIC
       -- TRAVA DE SEGURANÇA: só solta o PUBLIC se alguém explícito continuar
       -- alcançando. Sem isto, uma função sem grant nominal ficaria órfã.
       and exists (select 1 from unnest(coalesce(p.proacl, '{}')) a
                    where a::text like 'anon=%'
                       or a::text like 'authenticated=%'
                       or a::text like 'service_role=%')
     order by 1
  loop
    execute format('revoke execute on function %s from public', r.assinatura);
    v_revogadas := v_revogadas + 1;
  end loop;

  raise notice 'PUBLIC revogado de % funcoes security definer', v_revogadas;
end
$function$;
