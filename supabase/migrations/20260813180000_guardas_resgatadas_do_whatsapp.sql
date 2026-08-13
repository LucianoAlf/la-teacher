-- Guardas resgatadas da 090, 091 e 095
--
-- POR QUE. As tres migrations tem baseline VERMELHO e, por isso, as suites de
-- mutante delas nao provam nada -- todo mutante "morre" por erro, nao por
-- assercao. Os motivos, medidos em 13/08/2026:
--
--   090 -> `create table fabio_acoes_pendentes` sem `if not exists`: nao e
--          replayavel por construcao. O runner agregado ja a rotula
--          "sem harness reaplicavel".
--   091 -> `cannot change return type of existing function`: a 092 mudou de
--          proposito a assinatura de `fabio_status_audio_fila`. Contrato
--          superado.
--   095 -> `42P10`: o ON CONFLICT sem o predicado do indice PARCIAL. Corrigido
--          quatro minutos depois do incidente pela
--          `20260812004430_fix_registro_recibo_partial_conflict.sql`.
--
-- O PROBLEMA REAL NAO ERA O PLACAR, E SIM O QUE ELE ESCONDIA: as tres
-- carregavam guardas de ACL que estao APAGADAS ha semanas. Todas as nove
-- portas foram MEDIDAS em producao antes deste resgate e estavam corretas --
-- nao havia vazamento. Mas ninguem estava olhando, e regressao nenhuma seria
-- percebida.
--
-- Os revokes abaixo sao idempotentes e reafirmam o estado medido. Nada aqui
-- alarga nem estreita permissao.

-- Portas de worker: so o service_role entra.
revoke all on function public.fabio_iniciar_acao(integer, text, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.fabio_iniciar_acao(integer, text, text, text, jsonb)
  to service_role;

revoke all on function public.fabio_confirmar_registro(integer, uuid, text)
  from public, anon, authenticated;
grant execute on function public.fabio_confirmar_registro(integer, uuid, text)
  to service_role;

revoke all on function public.fabio_claim_registro_recibo(integer, integer)
  from public, anon, authenticated;
grant execute on function public.fabio_claim_registro_recibo(integer, integer)
  to service_role;

revoke all on function public.fabio_concluir_registro_recibo(uuid, uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.fabio_concluir_registro_recibo(uuid, uuid, text, text)
  to service_role;

revoke all on function public.fabio_falhar_registro_recibo(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.fabio_falhar_registro_recibo(uuid, uuid, text)
  to service_role;

revoke all on function public.fabio_registro_recibo_dados(integer, uuid)
  from public, anon, authenticated;
grant execute on function public.fabio_registro_recibo_dados(integer, uuid)
  to service_role;

-- Interna: chamada so de dentro de outra funcao, ninguem alcanca de fora --
-- nem o worker.
revoke all on function public.fn_confirmar_registro_core(integer, uuid, uuid, text)
  from public, anon, authenticated, service_role;

-- As tabelas do fluxo de acao do WhatsApp nao sao lidas pelo cliente.
revoke all on table public.fabio_acoes_pendentes from public, anon, authenticated;
revoke all on table public.fabio_acao_eventos    from public, anon, authenticated;
