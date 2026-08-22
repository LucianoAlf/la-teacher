-- Fecha a porta da cobranca da experimental para anon e authenticated.
--
-- POR QUE ISTO EXISTE
-- As migrations 20260822160000 (view) e 20260822170000 (RPCs) criaram objetos
-- no schema `public` sem revoke. No Supabase o schema `public` e o schema
-- EXPOSTO do PostgREST e tem default privileges para `anon` e `authenticated`,
-- entao objeto novo nasce alcancavel pela chave publicavel -- a mesma que vai
-- no bundle do PWA e e legivel por qualquer visitante.
--
-- Medido em 22/08/2026 antes deste arquivo:
--   vw_experimental_pendencia  -> anon=arwdDxtm, authenticated=arwdDxtm
--   as 3 fn_experimental_*     -> =X (PUBLIC), anon=X, authenticated=X
-- e as tres funcoes sao SECURITY DEFINER, ou seja rodam como `postgres`:
-- RLS nas tabelas de baixo NAO e rede de protecao. Um POST em
-- /rest/v1/rpc/fn_experimental_lembrete_alvos com p_minutos alto devolvia
-- nome do lead, curso, unidade e professor sem login.
--
-- Os gemeos da trilha do ALUNO ja faziam o certo, e e neles que este arquivo
-- se espelha:
--   fn_pendencias_do_professor / fn_pendencias_escalonadas -> postgres + service_role
--   vw_registro_pendencia                                  -> sem anon
--
-- QUEM PRECISA DE VERDADE: so `service_role`. O worker da VPS
-- (fabio_notification_worker.py -> bridge.sb_post) manda a
-- LAREPORT_SUPABASE_SERVICE_ROLE no apikey/Authorization. Nada no app do
-- professor le estes objetos direto; quando ler, a porta certa e uma RPC
-- security definer AUTO-ESCOPADA pelo auth.uid() (padrao do
-- app_minhas_pendencias), nunca a view crua.

revoke all on function public.fn_experimental_lembrete_alvos(integer)          from public, anon, authenticated;
revoke all on function public.fn_experimental_pendencia_do_professor(integer)  from public, anon, authenticated;
revoke all on function public.fn_experimental_escalonadas()                    from public, anon, authenticated;

grant execute on function public.fn_experimental_lembrete_alvos(integer)         to service_role;
grant execute on function public.fn_experimental_pendencia_do_professor(integer) to service_role;
grant execute on function public.fn_experimental_escalonadas()                   to service_role;

revoke all on public.vw_experimental_pendencia from anon, authenticated;
grant select on public.vw_experimental_pendencia to service_role;
