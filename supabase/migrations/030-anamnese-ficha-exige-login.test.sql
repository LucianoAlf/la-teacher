-- Teste da 030 — quem pode executar o quê, depois do revoke
--
-- O que se mede aqui é permissão, não resultado: `has_function_privilege` é a
-- mesma coisa que o Postgres consulta na hora de decidir se deixa a chamada
-- passar. Testar chamando a função com o papel trocado exigiria SET ROLE dentro
-- do ensaio, que interage mal com SECURITY DEFINER — a permissão é a resposta
-- direta à pergunta.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

-- ── A porta que estava aberta ─────────────────────────────────────────────
insert into _res
select 'anon NAO executa get_anamnese_publica', 'false',
       has_function_privilege('anon', 'public.get_anamnese_publica(text)', 'EXECUTE')::text;

-- ── A coordenação, que é quem de fato usa (8 chamadas autenticadas) ──────
insert into _res
select 'authenticated AINDA executa get_anamnese_publica', 'true',
       has_function_privilege('authenticated', 'public.get_anamnese_publica(text)', 'EXECUTE')::text;

-- ── A função morta some para os dois papéis ──────────────────────────────
insert into _res
select 'anon NAO executa get_anamnese_by_token', 'false',
       has_function_privilege('anon', 'public.get_anamnese_by_token(character varying)', 'EXECUTE')::text;

insert into _res
select 'authenticated NAO executa get_anamnese_by_token', 'false',
       has_function_privilege('authenticated', 'public.get_anamnese_by_token(character varying)', 'EXECUTE')::text;

-- ── O backend não pode ter sido atingido de raspão ───────────────────────
-- A edge function notificar-anamnese conecta com service_role. Se o revoke
-- pegasse ela junto, a anamnese pararia de ser enviada e o "conserto de
-- privacidade" viraria uma queda de serviço.
insert into _res
select 'service_role continua executando', 'true',
       has_function_privilege('service_role', 'public.get_anamnese_publica(text)', 'EXECUTE')::text;

-- ── E as funções continuam existindo (revoke, não drop) ──────────────────
insert into _res
select 'as duas funcoes continuam existindo', '2',
       (select count(*)::text from pg_proc
         where pronamespace = 'public'::regnamespace
           and proname in ('get_anamnese_publica','get_anamnese_by_token'));

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
