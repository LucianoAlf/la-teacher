-- O chão da fronteira: um papel que não consegue ler tabela nenhuma.
--
-- Este é o item 1 da revisão do Alfredo. A migration anterior (100000) sozinha
-- era pré-fundação: guardava a capacidade, mas nada impedia que a ferramenta
-- fosse plugada num papel gordo. Aqui nasce o papel magro.
--
-- A COMPARAÇÃO QUE JUSTIFICA (medido em 17/08/2026):
--   `fabio_agent`, usado hoje pelo postgres-mcp: rolbypassrls = TRUE,
--   SELECT em 412 tabelas do `public` — financeiro, anamnese, dados de
--   qualquer professor. É o papel que a gente NÃO quer do outro lado do Fábio
--   do professor.
--
--   `fabio_professor_agente`, este: sem bypassrls, sem herança, ZERO privilégio
--   de tabela, e `usage` no schema apenas para conseguir chamar função. O que
--   ele pode fazer é exatamente o que receber `grant execute` — e isso, nesta
--   fatia, são duas RPCs letivas (migration 120000).
--
-- ⚠️ SENHA NÃO MORA AQUI. O papel nasce com LOGIN e sem senha: quem define é o
-- Alf/Alfredo, fora do repositório, e o valor vai pro env do MCP na VPS. Senha
-- em migration é senha em git, e git é para sempre.

do $function$
begin
  if not exists (select 1 from pg_roles where rolname = 'fabio_professor_agente') then
    create role fabio_professor_agente login;
  end if;
end
$function$;

-- ⚠️ `nosuperuser`, `nobypassrls` e `noreplication` NÃO entram aqui: alterar
-- esses atributos exige SUPERUSER, e no Supabase nem o `postgres` é superusuário
-- (medido: `rolsuper = false`). O `create role` acima já nasce sem os três — e
-- quem prova isso é o teste, com `pg_roles`, não este comentário. Declarar o que
-- não se pode executar seria migration que quebra no dia da aplicação.
alter role fabio_professor_agente nocreatedb nocreaterole noinherit;

-- ── Item 2 da revisão: revogação explícita, sem contar com o padrão ─────────
revoke all on all tables in schema public from fabio_professor_agente;
revoke all on all sequences in schema public from fabio_professor_agente;
revoke all on all functions in schema public from fabio_professor_agente;
revoke all on all routines in schema public from fabio_professor_agente;
revoke all on schema public from fabio_professor_agente;

-- `usage` é o mínimo para enxergar o schema e chamar função qualificada. Não
-- concede leitura de tabela nenhuma — `usage` em schema não é `select`.
grant usage on schema public to fabio_professor_agente;

-- A tabela da capacidade é o alvo mais óbvio: quem a lê, lê hashes e sabe de
-- quem é cada sessão viva. Revogação nominal, além do `revoke all` acima.
revoke all on table public.fabio_agente_sessoes from fabio_professor_agente;

-- Objeto que ainda não existe também não pode nascer aberto. O padrão do
-- Supabase concede a `anon/authenticated/service_role` em tabela nova; este
-- papel fica fora disso de forma declarada.
alter default privileges for role postgres in schema public
  revoke all on tables from fabio_professor_agente;
alter default privileges for role postgres in schema public
  revoke all on sequences from fabio_professor_agente;
alter default privileges for role postgres in schema public
  revoke all on functions from fabio_professor_agente;

comment on role fabio_professor_agente is
  'Papel do MCP letivo do Fabio. Sem bypassrls, sem privilegio de tabela: so EXECUTE nas RPCs por token. Senha definida fora do repo.';
