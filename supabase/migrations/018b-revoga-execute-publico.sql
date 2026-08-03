-- 018b-revoga-execute-publico.sql
--
-- Fecha um buraco que a PRÓPRIA 018 abriu, descoberto conferindo a ACL logo
-- depois de aplicar.
--
-- As funções originais tinham EXECUTE só para {postgres, service_role,
-- fabio_agent}: PUBLIC já havia sido revogado em algum momento. Ao recriá-las,
-- elas nasceram com o grant padrão do Postgres para PUBLIC e com os default
-- privileges do Supabase para anon/authenticated.
--
-- Todas são SECURITY DEFINER. Do jeito que ficou por alguns minutos, um
-- chamador ANÔNIMO poderia reivindicar e concluir notificação de qualquer
-- professor.
--
-- ⚠️ O landmine 2 da 018 dizia "DROP leva os grants junto" e eu devolvi os que
--    faltavam. Mas o DROP levou também a REVOGAÇÃO que existia — e disso eu não
--    tinha me lembrado. Depois de recriar função: conferir a ACL INTEIRA, não só
--    se quem eu quero está lá.

revoke all on function
  public.fabio_claim_notificacao(integer, text, text, text, text, text, boolean),
  public.fabio_claim_notificacao_por_referencia(integer, text, text, text, text, text, text, text, integer),
  public.fabio_marcar_notificacao_enviada(uuid, uuid, text),
  public.fabio_marcar_notificacao_falhou(uuid, text, uuid, integer)
from public, anon, authenticated;

grant execute on function
  public.fabio_claim_notificacao(integer, text, text, text, text, text, boolean),
  public.fabio_claim_notificacao_por_referencia(integer, text, text, text, text, text, text, text, integer),
  public.fabio_marcar_notificacao_enviada(uuid, uuid, text),
  public.fabio_marcar_notificacao_falhou(uuid, text, uuid, integer)
to service_role, fabio_agent;
