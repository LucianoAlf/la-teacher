-- O "sim" do professor pertence a quem falou por último com ele.
--
-- INCIDENTE (15/08/2026, professor 10 — reconstruído do banco e do log da VPS):
--   16:53  o LLM mostra preview da aula das 14h (Jeremias) e das 15h (Marcelo),
--          mas a ação viva na máquina é a das 13h (Billy)
--   16:55  "Juliana fez aula no lugar do jeremias" + "Sim" chegam colados;
--          `message_batch_collected count=2` → a máquina determinística é
--          PULADA inteira (fabio_chat_bridge.py:3197) e o LLM responde sozinho
--   16:56  o LLM promete o que não tem mão pra fazer: "Ajustei... Posso gravar
--          esse registro agora? Responde sim"
--   16:57  "Sim" sozinha → a máquina roda e confirma a ação ativa: a das 13h
--   17:03  carimbo: T_Sá_13 • 13:00 — aula ERRADA no prontuário do aluno
--
-- Consertar só o lote não resolveria: se a máquina tivesse colhido o "sim" das
-- 16:55, ela gravaria a das 13h do mesmo jeito. O que separa uma confirmação
-- legítima de uma sequestrada é QUEM falou por último — e disso o banco já
-- tinha o registro, sem precisar de coluna nova.
--
-- A MARCA JÁ EXISTIA: as falas da máquina carregam o id da ação no
-- `wa_message_id` (`fabio-preview:<acao>` desde a 090; `fabio-acao:<acao>:<msg>`
-- a partir de agora, para as respostas de texto). As falas do LLM entram com
-- `wa_message_id` nulo. Então "quem falou por último" é uma consulta, não uma
-- inferência.
--
-- Esta função só LÊ. Quem decide não gravar é o bridge — aqui mora o fato.

create or replace function public.fabio_acao_confirmacao_segura(
  p_professor_id integer,
  p_acao_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  with ultima as (
    select
      m.wa_message_id,
      coalesce(m.wa_message_id, '') like '%' || p_acao_id::text || '%' as e_desta_acao
    from public.fabio_chat_mensagens m
    where m.professor_id = p_professor_id
      and m.role = 'fabio'
      and m.channel = 'whatsapp'
    order by
      m.criado_em desc,
      -- Empate no mesmo instante: quem NÃO é desta ação vence o desempate, e
      -- a resposta sai `segura=false`. Na dúvida a trava fecha; trava que
      -- escolhe o caminho permissivo no empate não é trava.
      (coalesce(m.wa_message_id, '') like '%' || p_acao_id::text || '%') asc,
      m.id desc
    limit 1
  )
  select jsonb_build_object(
    'ok', true,
    -- Sem nenhuma fala do Fábio, `segura` é false: não existe pergunta pendente
    -- que esse "sim" pudesse estar respondendo.
    'segura', coalesce((select e_desta_acao from ultima), false),
    'ultima_fala_wa_id', (select wa_message_id from ultima)
  );
$function$;

comment on function public.fabio_acao_confirmacao_segura(integer, uuid) is
  'O "sim" so vale para a acao que falou por ultimo com o professor. Fala da maquina carrega o id da acao no wa_message_id; fala do LLM vem sem. Incidente de 15/08/2026: LLM prometeu gravar a aula das 14h e a maquina colheu o sim para a das 13h.';

-- Porta fechada: quem chama é o bridge, com a chave de serviço. O app não vê.
revoke all on function public.fabio_acao_confirmacao_segura(integer, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.fabio_acao_confirmacao_segura(integer, uuid)
  to service_role;
