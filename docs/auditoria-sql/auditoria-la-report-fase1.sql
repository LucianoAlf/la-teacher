-- ============================================================
-- AUDITORIA LA REPORT · Fase 1 — Inventário completo
-- Projeto: ouqwbbermlzqqvtqwlul · Fábio + LA Teacher
-- Como usar: rodar no SQL Editor do Supabase e copiar o
-- resultado inteiro (CSV ou JSON) de volta pro chat.
-- Somente leitura — não altera nada no banco.
-- ============================================================

with tabelas as (
  select n.nspname as schema,
         c.relname as nome,
         c.relrowsecurity as rls_ativo,
         coalesce(s.n_live_tup, 0) as linhas_estimadas
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  left join pg_stat_user_tables s on s.relid = c.oid
  where c.relkind = 'r'
    and n.nspname not in ('pg_catalog','information_schema','extensions',
      'graphql','graphql_public','net','pgsodium','pgsodium_masks',
      'realtime','supabase_functions','storage','vault','auth','pgbouncer')
)

select 'A_TABELA' as secao,
       schema || '.' || nome as item,
       'linhas≈' || linhas_estimadas || ' · rls=' || rls_ativo as detalhe
from tabelas

union all
select 'B_COLUNAS',
       table_schema || '.' || table_name,
       string_agg(column_name || ':' || data_type, ', ' order by ordinal_position)
from information_schema.columns
where table_schema = 'public'
group by 1, 2

union all
select 'C_VIEW',
       table_schema || '.' || table_name,
       left(coalesce(view_definition, ''), 180)
from information_schema.views
where table_schema = 'public'

union all
select 'D_RPC_FUNCTION',
       n.nspname || '.' || p.proname,
       'args(' || pg_get_function_arguments(p.oid) || ') → '
         || pg_get_function_result(p.oid)
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'

union all
select 'E_TRIGGER',
       event_object_schema || '.' || event_object_table || ' · ' || trigger_name,
       action_timing || ' ' || event_manipulation
from information_schema.triggers
where trigger_schema = 'public'

union all
select 'F_RLS_POLICY',
       schemaname || '.' || tablename || ' · ' || policyname,
       cmd || ' · roles=' || array_to_string(roles, ',')
from pg_policies

union all
select 'G_FOREIGN_KEY',
       tc.table_schema || '.' || tc.table_name || '.' || kcu.column_name,
       '→ ' || ccu.table_name || '.' || ccu.column_name
from information_schema.table_constraints tc
join information_schema.key_column_usage kcu
  on tc.constraint_name = kcu.constraint_name
 and tc.table_schema = kcu.table_schema
join information_schema.constraint_column_usage ccu
  on ccu.constraint_name = tc.constraint_name
 and ccu.table_schema = tc.table_schema
where tc.constraint_type = 'FOREIGN KEY'
  and tc.table_schema = 'public'

union all
select 'H_EXTENSION', extname, 'v' || extversion
from pg_extension

union all
select 'I_STORAGE_BUCKET', name, 'public=' || public::text
from storage.buckets

order by 1, 2;
