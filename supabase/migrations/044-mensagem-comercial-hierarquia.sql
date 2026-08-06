-- 044 — a mensagem ao comercial ganha hierarquia, e o interno ganha fronteira
--
-- O primeiro tiro real (06/08/2026, para o Alf) chegou certo e feio: "Presenca",
-- "Proximos" sem acento, tudo no mesmo peso visual, e a leitura de conversao
-- separada do bloco pedagogico so por um "[interno]" no meio do texto corrido.
--
-- Os acentos eram defeito simples. A ORDEM nao e: o consultor copia mensagem do
-- Fabio e encaminha — e a familia nao pode receber o "por que ele converte".
-- Aqui o interno vai SEMPRE por ultimo, depois de uma regua, marcado com
-- cadeado e com a instrucao escrita. O teste confere a POSICAO no texto, nao so
-- a presenca das palavras: um mutante que sobe a leitura pro meio do bloco
-- pedagogico morre.
--
-- Dia da semana montado com CASE em vez de to_char(...,'Day'), que depende do
-- lc_time do servidor e devolveria "Thursday" sem avisar ninguem.
--
-- Teste: 044-mensagem-comercial-hierarquia.test.sql
-- Mutantes: scripts/mutantes-044.mjs

CREATE OR REPLACE FUNCTION public.fabio_claim_aviso_comercial(p_registro_id uuid, p_lease_minutos integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_reg      record;
  v_contato  record;
  v_corpo    text;
  v_id       uuid;
  v_token    uuid := gen_random_uuid();
begin
  select r.*, le.nome_aluno, ae.data_hora_inicio, v.presenca_status
    into v_reg
    from lead_experimental_registros r
    join lead_experimental_aulas v on v.id = r.vinculo_id
    join lead_experimentais le on le.id = v.lead_experimental_id
    join aulas_emusys ae on ae.id = v.aula_local_id
   where r.id = p_registro_id;

  if not found then
    raise exception 'registro_inexistente: %', p_registro_id;
  end if;

  select * into v_contato
    from unidade_contato_comercial
   where unidade_id = v_reg.unidade_id and ativo;

  -- NAO usar `found` daqui pra baixo: qualquer select que alguem insira no meio
  -- o sobrescreve em silencio. A pergunta "achou contato?" fica presa a uma
  -- variavel propria.
  -- Este e o UNICO lugar do sistema onde o bloco family-safe e a leitura de
  -- conversao aparecem juntos — porque aqui o destinatario E o circulo interno.
  -- HIERARQUIA SEMANTICA (padrao aprovado pelo Alf na governanca, 05/08):
  -- quem/quando primeiro, bloco pedagogico no meio, e o interno SEMPRE por
  -- ultimo, depois de uma regua e marcado. O consultor copia e encaminha
  -- mensagem do Fabio — se a leitura de conversao estiver no meio do texto
  -- pedagogico, ela vai junto pra familia num Ctrl+C descuidado. A ordem aqui
  -- e defesa, nao estetica: o teste confere a POSICAO, nao so a presenca.
  --
  -- Dia da semana montado na mao: to_char(...,'Day') depende de lc_time do
  -- servidor e devolveria "Thursday" sem avisar ninguem.
  v_corpo := format(
    E'🎓 *Experimental registrada*\n\n'
    '*%s*\n'
    '_%s · %s · %s_\n'
    '━━━━━━━━━━━━━━\n'
    '*Como foi*\n%s\n\n'
    '*Próximos passos*\n%s\n'
    '━━━━━━━━━━━━━━\n'
    '🔒 *Leitura de conversão* — uso interno, não encaminhar\n%s',
    v_reg.nome_aluno,
    case extract(dow from v_reg.data_hora_inicio at time zone 'America/Sao_Paulo')
      when 0 then 'domingo' when 1 then 'segunda' when 2 then 'terça'
      when 3 then 'quarta'  when 4 then 'quinta' when 5 then 'sexta'
      else 'sábado' end,
    to_char(v_reg.data_hora_inicio at time zone 'America/Sao_Paulo', 'DD/MM · HH24:MI'),
    case coalesce(v_reg.presenca_status, 'nao informada')
      when 'presente' then 'presente ✅'
      when 'falta'    then 'faltou ❌'
      else 'presença não informada' end,
    coalesce(v_reg.devolutiva_familia, '_(não preenchido)_'),
    coalesce(v_reg.proximos_passos, '_(não preenchido)_'),
    coalesce(v_reg.leitura_de_conversao, '_(não preenchido)_'));

  if v_contato.unidade_id is null then
    -- Sem destinatario: fica VISIVEL na fila, nao some. E idempotente pelo
    -- mesmo indice de referencia — repetir nao empilha rastro.
    insert into fabio_notificacoes
      (professor_id, destinatario_tipo, tipo, categoria, corpo, canal, status,
       motivo_pulada, referencia_tipo, referencia_id, destinatario_whatsapp)
    values
      (null, 'comercial', 'experimental_registrada', 'informativa', v_corpo, 'whatsapp',
       'pulada_sem_destinatario', 'sem_contato_comercial_na_unidade',
       'lead_experimental_registro', p_registro_id::text, null)
    on conflict (referencia_tipo, referencia_id, canal)
      where referencia_tipo is not null and referencia_id is not null
    do nothing;
    return jsonb_build_object('ok', true, 'claimed', false, 'motivo', 'sem_destinatario');
  end if;

  insert into fabio_notificacoes
    (professor_id, destinatario_tipo, destinatario_whatsapp, tipo, categoria, corpo,
     canal, status, tentativas, lease_token, lease_expira_em,
     referencia_tipo, referencia_id)
  values
    (null, 'comercial', v_contato.whatsapp, 'experimental_registrada', 'informativa', v_corpo,
     'whatsapp', 'processando', 1, v_token, now() + make_interval(mins => p_lease_minutos),
     'lead_experimental_registro', p_registro_id::text)
  on conflict (referencia_tipo, referencia_id, canal)
    where referencia_tipo is not null and referencia_id is not null
  do update set
    status                = 'processando',
    tentativas            = fabio_notificacoes.tentativas + 1,
    corpo                 = excluded.corpo,   -- reprocessa com conteudo fresco
    destinatario_whatsapp = excluded.destinatario_whatsapp,
    lease_token           = excluded.lease_token,
    lease_expira_em       = excluded.lease_expira_em,
    last_error            = null
  where
    -- falhou: pode tentar de novo, respeitando o backoff
    (fabio_notificacoes.status = 'falhou'
      and (fabio_notificacoes.proxima_tentativa_em is null
           or fabio_notificacoes.proxima_tentativa_em <= now()))
    -- ou: o dono anterior sumiu. A janela mede o LEASE, nao a criacao.
    or (fabio_notificacoes.status = 'processando'
      and fabio_notificacoes.lease_expira_em is not null
      and fabio_notificacoes.lease_expira_em <= now())
    -- ou: era rastro de falta de destinatario e agora HA destinatario
    or (fabio_notificacoes.status = 'pulada_sem_destinatario')
  returning id into v_id;

  if v_id is null then
    -- ja enviada, ou outro worker esta com o lease VIVO agora
    return jsonb_build_object('ok', true, 'claimed', false, 'motivo', 'lease_vivo_ou_enviada');
  end if;

  return jsonb_build_object('ok', true, 'claimed', true,
                            'notificacao_id', v_id, 'lease_token', v_token);
end
$function$;
