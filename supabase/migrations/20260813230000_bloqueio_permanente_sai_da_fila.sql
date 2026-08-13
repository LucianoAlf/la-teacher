-- O bloqueio PERMANENTE sai da fila; o temporário continua voltando.
--
-- O DEFEITO (latente, nunca disparou). `cleanup_once` no reconciler faz
-- `continue` quando a prova recusa. O `continue` não conclui nada: o lease de
-- 120s expira e a MESMA ação é reivindicada de novo, para sempre. Medido em
-- 13/08/2026: elegíveis = 0, bloqueio permanente = 0, temporário = 0 -- ou
-- seja, não podia disparar hoje. Mas o dia em que disparar ninguém vai ver,
-- porque um laço de limpeza não reclama: ele só gira.
--
-- OS DOIS BLOQUEIOS NÃO SÃO A MESMA COISA. `fabio_provar_limpeza` recusa por
-- dois motivos, e eles têm vidas opostas:
--
--   `acao_ativa_referencia_storage`         -> TEMPORÁRIO. Outra ação aberta
--     aponta pro mesmo áudio. Quando ela fechar, a limpeza passa a ser
--     legítima. Reentrar na fila é o comportamento CERTO -- e é o que continua
--     acontecendo aqui, de propósito.
--
--   `registro_confirmado_referencia_storage` -> PERMANENTE. Um registro de
--     aula confirmado (ou já gravado no Emusys) aponta pro áudio. Isso não se
--     desfaz: o áudio é a EVIDÊNCIA do registro. A limpeza não vai ser
--     autorizada nunca, e insistir a cada 120s é laço puro.
--
-- A DECISÃO. Bloqueio permanente vira CARIMBO com o motivo escrito e sai da
-- fila -- não vira pendência pra alguém resolver. Não há nada a resolver: o
-- áudio está sendo preservado porque deve ser preservado. Criar uma pendência
-- aqui seria inventar tarefa humana pra um estado que já está correto, e a
-- casa já paga caro por pendência fantasma.
--
-- POR QUE UMA PORTA NOVA E NÃO A `fabio_concluir_limpeza`. Aquela função
-- RE-PROVA antes de carimbar e recusa se `pode_remover` for falso -- e essa
-- recusa é defesa em profundidade que eu não vou afrouxar: é ela que impede
-- um worker com bug de apagar evidência. A porta nova carimba o caso oposto
-- (o áudio FICA), então ela exige exatamente o contrário: só age quando a
-- prova recusa, e só com o motivo permanente.
--
-- A CHAVE QUE TIRA DA FILA é a mesma da 20260813160000: o claim já ignora
-- quem tem `payload ? 'limpeza'`. Carimbar aqui reusa esse contrato em vez de
-- inventar um segundo -- duas travas para o mesmo laço seriam duas verdades.

create or replace function public.fabio_arquivar_limpeza_bloqueada(
  p_acao_id uuid,
  p_lease_token uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_a public.fabio_acoes_pendentes%rowtype;
  v_prova jsonb;
  v_motivo text;
begin
  select * into v_a
    from public.fabio_acoes_pendentes
   where id = p_acao_id
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'acao_nao_encontrada');
  end if;
  if v_a.lease_token is distinct from p_lease_token
     or v_a.lease_expira_em < now() then
    return jsonb_build_object('ok', false, 'codigo', 'lease_invalido');
  end if;

  v_prova := public.fabio_provar_limpeza(v_a.id, v_a.storage_path);

  -- Se a limpeza é PERMITIDA, esta não é a porta. Carimbar aqui deixaria um
  -- áudio removível preso na fila para sempre -- o laço ao contrário.
  if coalesce((v_prova ->> 'pode_remover')::boolean, false) is true then
    return jsonb_build_object(
      'ok', false,
      'codigo', 'limpeza_permitida_use_concluir',
      'prova', v_prova
    );
  end if;

  v_motivo := v_prova ->> 'motivo';

  -- Bloqueio TEMPORÁRIO (ou qualquer motivo que eu ainda não conheça) volta
  -- pra fila: soltar o lease agora é melhor que esperar os 120s expirarem.
  -- O default é reentrar, não carimbar: carimbar por engano perde o áudio de
  -- vista, e o custo de reentrar é uma volta de worker.
  if v_motivo is distinct from 'registro_confirmado_referencia_storage' then
    update public.fabio_acoes_pendentes
       set lease_token = null,
           lease_expira_em = null,
           atualizado_em = now()
     where id = v_a.id;
    return jsonb_build_object(
      'ok', false,
      'codigo', 'bloqueio_temporario',
      'motivo', v_motivo,
      'prova', v_prova
    );
  end if;

  update public.fabio_acoes_pendentes
     set payload = coalesce(payload, '{}'::jsonb) || jsonb_build_object(
       'limpeza', jsonb_build_object(
         'removido', false,
         'motivo', v_motivo,
         'decisao', 'audio_preservado_por_registro_confirmado',
         'arquivado_em', now()
       ),
       'prova', v_prova
     ),
         lease_token = null,
         lease_expira_em = null,
         atualizado_em = now()
   where id = v_a.id;

  return jsonb_build_object(
    'ok', true,
    'codigo', 'bloqueio_permanente_arquivado',
    'motivo', v_motivo,
    'prova', v_prova
  );
end;
$function$;

comment on function public.fabio_arquivar_limpeza_bloqueada(uuid, uuid) is
  'Tira da fila de limpeza a acao cujo audio NUNCA podera ser removido, '
  'porque um registro de aula confirmado aponta pra ele. Carimba o motivo em '
  'payload.limpeza -- a mesma chave que o claim da 20260813160000 usa pra '
  'ignorar. Bloqueio temporario (acao ativa referenciando o storage) NAO e '
  'carimbado: solta o lease e volta pra fila, que e o certo.';

-- Porta de worker: quem chama e o reconciler, pela service_role. Nenhum
-- cliente autenticado tem o que fazer com ela.
revoke all on function public.fabio_arquivar_limpeza_bloqueada(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.fabio_arquivar_limpeza_bloqueada(uuid, uuid)
  to service_role;
