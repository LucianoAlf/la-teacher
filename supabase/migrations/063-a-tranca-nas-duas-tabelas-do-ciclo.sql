-- 063 — a tranca nas duas tabelas do ciclo da experimental
--
-- Achado do Alfredo, aberto desde a 034/035: `lead_experimental_aulas` e
-- `lead_experimental_registros` estão com RLS DESLIGADO. São as duas tabelas
-- que guardam o ciclo inteiro da experimental — o vínculo lead↔aula e o
-- prontuário que o professor dita.
--
-- A PORTA JÁ ESTAVA FECHADA; FALTAVA A TRANCA
-- Medido em 08/08/2026: nenhuma das duas tem grant pra `anon` ou
-- `authenticated`. Ninguém alcança por PostgREST hoje. O risco não é o de
-- agora, é o da próxima migration: no Supabase, tudo que mora em `public` é
-- publicado pela API, e basta um `grant` distraído — ou um
-- `grant select on all tables in schema public` de alguém apressado — pra
-- tabela virar leitura aberta sem que nada acuse. RLS ligada faz esse deslize
-- não ter efeito.
--
-- SEM POLICY, DE PROPÓSITO
-- Nenhum caminho legítimo passa por aqui como `authenticated`: o cliente é
-- proibido de fazer `from('tabela')` (regra da 001), as telas falam com RPCs
-- `security definer` de dono `postgres`, e os workers da VPS usam a
-- service_role. Definer do dono e service_role passam por cima de RLS — é por
-- isso que ligar sem policy não quebra nada, e é o mesmo desenho de
-- `professor_acesso_codigos` (056) e `la_teacher_coordenacao` (062).
--
-- O `revoke` é redundante HOJE e existe pra continuar sendo amanhã: declarar a
-- ausência de privilégio deixa a intenção no arquivo, não no acaso do que
-- alguém lembrou de não conceder.
--
-- Teste: 063-a-tranca-nas-duas-tabelas-do-ciclo.test.sql
-- Mutantes: scripts/mutantes-063.mjs

alter table public.lead_experimental_aulas     enable row level security;
alter table public.lead_experimental_registros enable row level security;

revoke all on table public.lead_experimental_aulas     from public, anon, authenticated;
revoke all on table public.lead_experimental_registros from public, anon, authenticated;

comment on table public.lead_experimental_aulas is
'Vinculo lead<->aula da experimental. RLS ligada e SEM policy: so security definer (dono postgres) e service_role entram. O cliente fala com app_experimental_do_professor / app_minha_agenda_sessao.';

comment on table public.lead_experimental_registros is
'Prontuario da experimental ditado pelo professor. RLS ligada e SEM policy — mesma razao da lead_experimental_aulas. A fronteira family-safe mora nas RPCs, nao na tabela.';
