-- O áudio que morre EM VOO volta pra fila (e não invade a experimental).
--
-- 15/08/2026 — o professor Valdo mandou um áudio de aula pelo WhatsApp. O
-- Fábio respondeu "Áudio recebido. Vou processar a aula e te mostro o resumo
-- antes de gravar." e nunca mais falou. Auditado:
--
--   14:05:41  fila criada, trigger dispara, edge responde 200 enviado_ao_fabio
--   14:05:47  fabio_transcrever_audio_fila -> 400 InvalidSignature
--             (o `:` do wa_message_id do UAZAPI no nome do objeto — corrigido
--              em fabio_whatsapp_actions.py, fora desta migration)
--   ...       a linha ficou em 'transcrevendo' PARA SEMPRE
--
-- A causa do SILÊNCIO ETERNO é aqui: `fn_fabio_retry_fila` só olhava
-- `pendente` e `erro`. Quem morre no meio do caminho — 'transcrevendo' e
-- 'transcrito' — não era `pendente` (já saiu de lá) nem `erro` (ninguém
-- chegou a escrever erro nenhum). Ficava órfã: sem retry, sem alerta, sem
-- ninguém sabendo. O professor só vê o silêncio.
--
-- Não era só o Valdo: no momento do conserto havia 2 áudios de APP parados em
-- 'transcrito' desde 13/08 22:02 — dois professores que também perderam o
-- registro e ninguém soube.
--
-- DUAS mudanças, e a segunda é o que torna a primeira segura:
--
-- 1. Estados em voo entram no retry depois de 15 min parados. A janela é
--    folgada de propósito: transcrição de áudio longo em CPU leva minutos, e
--    reenfileirar quem ainda está vivo seria pior que esperar. Não há risco de
--    registro duplicado — `fabio_criar_registro_aula` já devolve "ja_existia"
--    quando o audio_id tem registro.
--
-- 2. `vinculo_id is null` passa a ser exigido. Isso NÃO é faxina de passagem:
--    o worker da experimental reivindica linhas com
--    `status in.(pendente,transcrevendo)` — sem esta guarda, o item 1 acima
--    passaria a roubar áudio de experimental e mandar pro Hermes, que é
--    exatamente o "registro no lugar errado" contra o qual
--    `trg_fabio_fila_dispara` já se protege. O retry só agora aprende a
--    fronteira que o trigger sempre teve.

create or replace function public.fn_fabio_retry_fila()
returns integer
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  r record;
  n integer := 0;
begin
  for r in
    select f.id
      from public.fabio_fila_audios f
     where (
             f.status in ('pendente', 'erro')
             -- Morreu em voo: o Hermes carimbou o estado intermediário e a
             -- etapa seguinte falhou sem escrever erro. Sem esta linha, fica
             -- órfã pra sempre.
             or (
               f.status in ('transcrevendo', 'transcrito')
               and f.atualizado_em < now() - interval '15 minutes'
             )
           )
       -- A experimental tem worker próprio e usa 'transcrevendo' também.
       -- Mesma fronteira de trg_fabio_fila_dispara.
       and f.vinculo_id is null
       and f.erro_tipo = 'transitorio'
       and f.status <> 'erro_terminal'
       and f.tentativas < 3
       and f.criado_em > now() - interval '3 days'
       and f.atualizado_em < now() - (least(greatest(f.tentativas, 1), 12) * interval '5 minutes')
     order by f.atualizado_em
     limit 10
  loop
    update public.fabio_fila_audios
       set tentativas = tentativas + 1,
           atualizado_em = now()
     where id = r.id;
    perform public.fn_fabio_chama_edge(r.id);
    n := n + 1;
  end loop;
  return n;
end
$function$;

comment on function public.fn_fabio_retry_fila() is
  'Reenfileira áudio do Fábio que falhou OU morreu em voo (transcrevendo/transcrito parados >15min). Só aula comum: a experimental tem worker próprio (vinculo_id).';
