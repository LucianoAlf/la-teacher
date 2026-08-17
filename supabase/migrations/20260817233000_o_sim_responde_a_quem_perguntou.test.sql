-- Este teste SEMEIA a conversa, porque o que está sob prova é uma ORDEM.
--
-- Afirmar contra o corpus ("hoje a RPC devolve false pro professor X") não
-- prova a regra: prova o estado de agora. Aqui a fala do Fábio é plantada em
-- ordem controlada — máquina, LLM, outra ação, empate — e a pergunta é sempre
-- a mesma: esse "sim" está respondendo a QUEM?
--
-- Sem gatilho em `fabio_chat_mensagens` (conferido no `pg_trigger`), então
-- semear aqui não dispara WhatsApp nenhum. Roda no BEGIN/ROLLBACK do runner,
-- que confere resíduo zero.

-- PREAMBULO-INICIO
create temporary table pg_temp._res (caso text, ok boolean, detalhe text) on commit drop;

create or replace function pg_temp.checar(p_caso text, p_ok boolean, p_detalhe text)
returns void language plpgsql as $function$
begin
  insert into pg_temp._res(caso, ok, detalhe) values (p_caso, coalesce(p_ok,false), p_detalhe);
end
$function$;
-- PREAMBULO-FIM

do $function$
declare
  v_fn oid := to_regprocedure('public.fabio_acao_confirmacao_segura(integer,uuid)');
  v_prof integer := 10;          -- professor com histórico real de WhatsApp
  v_prof_mudo integer := 1;      -- existe e nunca falou com o Fábio
  v_acao uuid := gen_random_uuid();
  v_outra uuid := gen_random_uuid();
  v_t timestamptz := now();
begin
  perform pg_temp.checar('a RPC existe', v_fn is not null, coalesce(v_fn::text, '<ausente>'));
  if v_fn is null then return; end if;

  perform pg_temp.checar('a RPC e STABLE (nao escreve)',
    (select provolatile from pg_proc where oid = v_fn) = 's',
    (select provolatile::text from pg_proc where oid = v_fn));
  perform pg_temp.checar('anon NAO executa',
    not has_function_privilege('anon', v_fn, 'EXECUTE'), 'anon');
  perform pg_temp.checar('authenticated NAO executa',
    not has_function_privilege('authenticated', v_fn, 'EXECUTE'), 'authenticated');
  perform pg_temp.checar('service_role executa',
    has_function_privilege('service_role', v_fn, 'EXECUTE'), 'service_role');

  -- ── Professor que nunca ouviu o Fábio: nao ha pergunta pendente ──────────
  perform pg_temp.checar('sem nenhuma fala do Fabio, NAO e segura',
    (public.fabio_acao_confirmacao_segura(v_prof_mudo, v_acao) ->> 'segura') = 'false',
    public.fabio_acao_confirmacao_segura(v_prof_mudo, v_acao)::text);

  -- ── Caso feliz: a ultima fala e o preview DESTA acao ─────────────────────
  insert into public.fabio_chat_mensagens(professor_id, role, kind, content, channel,
                                          wa_message_id, criado_em)
  values (v_prof, 'fabio', 'text', 'preview da aula',  'whatsapp',
          'fabio-preview:' || v_acao::text, v_t + interval '1 min');

  perform pg_temp.checar('ultima fala e o preview DESTA acao -> segura',
    (public.fabio_acao_confirmacao_segura(v_prof, v_acao) ->> 'segura') = 'true',
    public.fabio_acao_confirmacao_segura(v_prof, v_acao)::text);

  -- ── O 15/08 do Isaque: o LLM fala DEPOIS e sequestra o "sim" ─────────────
  insert into public.fabio_chat_mensagens(professor_id, role, kind, content, channel,
                                          wa_message_id, criado_em)
  values (v_prof, 'fabio', 'text',
          'Ajustei: a aula das 14h foi da Juliana. Posso gravar? Responde sim',
          'whatsapp', null, v_t + interval '2 min');

  perform pg_temp.checar('LLM falou por ultimo -> NAO e segura',
    (public.fabio_acao_confirmacao_segura(v_prof, v_acao) ->> 'segura') = 'false',
    public.fabio_acao_confirmacao_segura(v_prof, v_acao)::text);

  -- ── Fala da maquina, mas de OUTRA acao: tambem nao vale ──────────────────
  insert into public.fabio_chat_mensagens(professor_id, role, kind, content, channel,
                                          wa_message_id, criado_em)
  values (v_prof, 'fabio', 'text', 'preview de outra aula', 'whatsapp',
          'fabio-preview:' || v_outra::text, v_t + interval '3 min');

  perform pg_temp.checar('ultima fala e de OUTRA acao -> NAO e segura',
    (public.fabio_acao_confirmacao_segura(v_prof, v_acao) ->> 'segura') = 'false',
    public.fabio_acao_confirmacao_segura(v_prof, v_acao)::text);
  perform pg_temp.checar('e a outra acao, essa sim, esta segura',
    (public.fabio_acao_confirmacao_segura(v_prof, v_outra) ->> 'segura') = 'true',
    public.fabio_acao_confirmacao_segura(v_prof, v_outra)::text);

  -- ── A resposta da maquina (texto) tambem carimba, no formato novo ────────
  insert into public.fabio_chat_mensagens(professor_id, role, kind, content, channel,
                                          wa_message_id, criado_em)
  values (v_prof, 'fabio', 'text', 'Atualizei o rascunho.', 'whatsapp',
          'fabio-acao:' || v_acao::text || ':wa-123', v_t + interval '4 min');

  perform pg_temp.checar('resposta de texto da maquina conta como fala dela',
    (public.fabio_acao_confirmacao_segura(v_prof, v_acao) ->> 'segura') = 'true',
    public.fabio_acao_confirmacao_segura(v_prof, v_acao)::text);

  -- ── Empate no MESMO instante: a duvida tem que fechar, nao abrir ─────────
  insert into public.fabio_chat_mensagens(professor_id, role, kind, content, channel,
                                          wa_message_id, criado_em)
  values (v_prof, 'fabio', 'text', 'fala do LLM no mesmo instante', 'whatsapp',
          null, v_t + interval '4 min');

  perform pg_temp.checar('empate no mesmo instante -> NAO e segura',
    (public.fabio_acao_confirmacao_segura(v_prof, v_acao) ->> 'segura') = 'false',
    public.fabio_acao_confirmacao_segura(v_prof, v_acao)::text);

  -- ── Canal errado nao conta: o app tem outra porta ────────────────────────
  insert into public.fabio_chat_mensagens(professor_id, role, kind, content, channel,
                                          wa_message_id, criado_em)
  values (v_prof, 'fabio', 'text', 'resposta no app', 'app',
          'fabio-preview:' || v_acao::text || ':app', v_t + interval '5 min');

  perform pg_temp.checar('fala no APP nao desempata o WhatsApp',
    (public.fabio_acao_confirmacao_segura(v_prof, v_acao) ->> 'segura') = 'false',
    public.fabio_acao_confirmacao_segura(v_prof, v_acao)::text);
end
$function$;

select json_build_object(
  'total',  (select count(*) from pg_temp._res),
  'falhas', (select count(*) from pg_temp._res where not ok),
  'casos',  (select json_agg(json_build_object(
                      'caso', caso,
                      'veredito', case when ok then 'OK' else 'FALHOU' end,
                      'detalhe', detalhe) order by caso)
               from pg_temp._res)
) as resumo;
