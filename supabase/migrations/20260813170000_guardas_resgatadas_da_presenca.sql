-- Guardas resgatadas da 093 e da 099
--
-- POR QUE ESTE ARQUIVO EXISTE. As migrations 093 e 099 pararam de ser
-- replayaveis: a `20260812163000_recibo_so_whatsapp_e_fila_ativa` redefiniu o
-- `fabio_criar_registro` DE PROPOSITO, e os testes daquelas duas cobram o
-- contrato antigo. A 099, por exemplo, exige recibo para registro com
-- `origem='app'`, e a resposta viva hoje e literalmente
-- `{"motivo":"origem_app","skipped":true}` -- o comportamento novo e correto.
-- O caminho da casa para isso e marcar `-- SUPERADA POR:`.
--
-- SO QUE MARCAR SUPERADA DESARMA A SUITE INTEIRA JUNTO, e as duas carregavam
-- guardas de ACL que nao tem nada de superado:
--
--   093 -> `fn_materializar_presenca_padrao` e `fn_remover_campos_comuns_da_fatia`
--          nao podem ser executaveis por NINGUEM (nem service_role): sao
--          internas, chamadas so de dentro de outras funcoes.
--   099 -> `app_confirmar_registro` e do professor logado: `authenticated` sim,
--          `anon` nao.
--
-- As tres ACLs foram MEDIDAS em producao em 13/08/2026 antes deste resgate e
-- estavam corretas. Este arquivo nao conserta nada -- ele impede que a
-- marcacao de SUPERADA leve as guardas junto, em silencio. Esta casa ja perdeu
-- mutante de seguranca exatamente assim.
--
-- Os revokes abaixo sao idempotentes e reafirmam o que ja vale. `service_role`
-- NAO e mexido em `app_confirmar_registro` (hoje true, e continua).

-- Internas: porta fechada para todo mundo, inclusive o worker.
revoke all on function public.fn_materializar_presenca_padrao(uuid, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.fn_remover_campos_comuns_da_fatia(jsonb, jsonb)
  from public, anon, authenticated, service_role;

-- Porta do professor logado: authenticated entra, anon nao.
revoke all on function public.app_confirmar_registro(uuid, text) from public, anon;
grant execute on function public.app_confirmar_registro(uuid, text) to authenticated;
