-- Teste da 031 — reabre para o responsável SEM reabrir o que estava errado
--
-- O risco de uma reversão é reverter demais. A 030 fez duas coisas; esta desfaz
-- uma só. O teste existe para provar qual.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

-- ── O que volta: o responsável abre a própria ficha ──────────────────────────
insert into _res
select 'anon volta a executar get_anamnese_publica', 'true',
       has_function_privilege('anon', 'public.get_anamnese_publica(text)', 'EXECUTE')::text;

-- ── O que NÃO volta: a função sem consumidor continua trancada ──────────────
insert into _res
select 'get_anamnese_by_token continua fechada p/ anon', 'false',
       has_function_privilege('anon', 'public.get_anamnese_by_token(character varying)', 'EXECUTE')::text;

insert into _res
select 'get_anamnese_by_token continua fechada p/ authenticated', 'false',
       has_function_privilege('authenticated', 'public.get_anamnese_by_token(character varying)', 'EXECUTE')::text;

-- ── Quem já tinha, continua tendo ───────────────────────────────────────────
insert into _res
select 'coordenacao autenticada continua', 'true',
       has_function_privilege('authenticated', 'public.get_anamnese_publica(text)', 'EXECUTE')::text;

insert into _res
select 'backend continua', 'true',
       has_function_privilege('service_role', 'public.get_anamnese_publica(text)', 'EXECUTE')::text;

-- ── E o PUBLIC nao volta pela porta dos fundos ──────────────────────────────
-- A 030 revogou de PUBLIC e concedeu nominalmente. Se esta migration tivesse
-- devolvido para PUBLIC em vez de `anon`, TODO papel — inclusive os que
-- aparecerem no futuro — herdaria o acesso sem ninguém decidir isso.
insert into _res
select 'PUBLIC nao tem execute direto', 'false',
       coalesce((select true
                   from pg_proc p, aclexplode(p.proacl) a
                  where p.pronamespace = 'public'::regnamespace
                    and p.proname = 'get_anamnese_publica'
                    and a.grantee = 0            -- 0 = PUBLIC
                    and a.privilege_type = 'EXECUTE'
                  limit 1), false)::text;

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
