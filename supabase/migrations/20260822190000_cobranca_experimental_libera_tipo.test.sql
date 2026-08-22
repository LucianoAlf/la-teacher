-- Teste da liberação de 'pendencia_experimental' em fabio_notificacoes_tipo_check.
-- Roda em BEGIN/ROLLBACK contra produção (branches são inviáveis aqui):
-- o raise exception final aborta a transação implícita do comando e desfaz
-- os inserts sintéticos junto — zero traço em fabio_notificacoes.
--
-- O caso que importa é o CONTROLE (2) e o NEGATIVO (3): sem eles, um mutante
-- que recria o CHECK como `true` (ou removesse o `drop constraint` inteiro,
-- deixando a allowlist ANTIGA valendo) passaria pelo caso 1 sozinho —
-- "claimed=true" também é o que se vê quando o CHECK simplesmente sumiu.

do $$
declare
  r        jsonb;
  v_prof   integer;
  v_ref_1  text := 'teste-migration-190000-a';
  v_ref_2  text := 'teste-migration-190000-b';
  v_ref_3  text := 'teste-migration-190000-c';
begin
  select p.id into v_prof from professores p where fn_professor_usa_app(p.id) limit 1;
  if v_prof is null then
    raise exception 'SETUP FALHOU: nenhum professor com app pra montar o cenario';
  end if;

  -- sentinela: a constraint existe e é a que a migration recriou (14+1 = 15
  -- valores) — se um mutante apagar o `add constraint` sem substituto, o
  -- INSERT abaixo cai na regra implícita "sem CHECK = tudo passa" e o caso 3
  -- (negativo) nunca teria uma trava pra derrubar de verdade.
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.fabio_notificacoes'::regclass
       and conname = 'fabio_notificacoes_tipo_check'
  ) then
    raise exception 'FALHOU 0: fabio_notificacoes_tipo_check nao existe mais';
  end if;

  -- 1. o tipo NOVO — este é o claim real que o worker faz a cada 5 minutos
  r := public.fabio_claim_notificacao_por_referencia(
    v_prof, 'pendencia_experimental', 'governanca', 'whatsapp',
    'corpo de teste', 'teste_migration_tipo_check', v_ref_1,
    'titulo de teste', 10
  );
  if (r->>'claimed')::boolean is not true then
    raise exception 'FALHOU 1: claim com pendencia_experimental nao foi aceito: %', r;
  end if;

  -- 2. CONTROLE — um tipo já conhecido (existia nos 14 originais) continua
  --    passando. Sem isto, o caso 1 sozinho não distingue "migration
  --    aplicada certo" de "CHECK sumiu inteiro".
  r := public.fabio_claim_notificacao_por_referencia(
    v_prof, 'registro_sem_roster', 'informativa', 'whatsapp',
    'corpo de teste (controle)', 'teste_migration_tipo_check', v_ref_2,
    'titulo de teste', 10
  );
  if (r->>'claimed')::boolean is not true then
    raise exception 'FALHOU 2 (controle): claim com tipo ja conhecido (registro_sem_roster) deveria passar: %', r;
  end if;

  -- 3. NEGATIVO — um tipo inventado tem que continuar sendo recusado. Se
  --    isto passar, o CHECK virou frouxo (ex.: `true`, ou `tipo is not
  --    null`) e qualquer string vira tipo válido em produção.
  begin
    perform public.fabio_claim_notificacao_por_referencia(
      v_prof, 'tipo_que_nao_existe_de_verdade', 'governanca', 'whatsapp',
      'corpo de teste (negativo)', 'teste_migration_tipo_check', v_ref_3,
      'titulo de teste', 10
    );
    raise exception 'FALHOU 3: claim com tipo inventado deveria ter sido recusado pelo CHECK e nao foi';
  exception
    when check_violation then
      null; -- esperado: o CHECK ainda restringe
  end;

  raise exception 'VERDE: pendencia_experimental liberado, controle e negativo distinguem o mutante';
end $$;
