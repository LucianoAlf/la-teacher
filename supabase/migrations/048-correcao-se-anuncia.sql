-- SUPERADA POR: 20260813250000_o_aviso_ao_comercial_volta_a_caber_no_indice.sql
--
-- Estes arquivos recriam `fabio_claim_aviso_comercial` com o `ON CONFLICT` de
-- DOIS predicados. O indice `uq_fabio_notif_por_referencia` ganhou um terceiro
-- (`tipo <> 'registro_recibo'`), entao replayar este arquivo REINTRODUZ o
-- 42P10 vivo que a 20260813250000 consertou. O que este arquivo ensinou
-- continua valendo e esta preservado abaixo como registro.
--
-- 048 — corrigir depois de enviar: a Daiana recebe uma CORREÇÃO, nao silencio
--
-- Decisao do Alf em 06/08/2026: o professor pode corrigir depois de confirmar,
-- e o comercial recebe um aviso de correcao.
--
-- O QUE EU ACHEI TENTANDO IMPLEMENTAR ISSO
-- Eu esperava que corrigir criasse um registro NOVO. Nao cria:
-- uq_lead_exp_registro_vigente e unico por vinculo, e
-- fn_registrar_experimental_interno faz UPDATE na mesma linha. O registro_id
-- nao muda — logo a notificacao e a MESMA linha da fila, ja com status
-- 'enviada'. E o claim recusa retomar enviada, de proposito, pra ninguem
-- receber a mesma devolutiva duas vezes.
--
-- Resultado hoje: corrigir depois de confirmar nao produz mensagem NENHUMA.
-- O professor arruma o prontuario, fica tranquilo, e a Daiana segue com a
-- versao velha. Nada da erro. E o pior estado dos tres possiveis — pior que
-- mandar duas iguais, porque ninguem descobre.
--
-- DUAS MUDANCAS, ESTREITAS.
--
-- (1) O claim ganha UM ramo de retomada: linha 'enviada' cujo CONTEUDO mudou.
--     A comparacao e por conteudo e nao por horario porque now() e constante
--     dentro de uma transacao — `atualizado_em > confirmado_em` seria igual
--     no caminho exato que o teste percorre, e o conserto ficaria sem carrasco.
--     Conteudo tambem e mais honesto: se a mensagem seria a mesma, nao ha
--     correcao. Reconfirmar sem editar continua sem gerar mensagem.
--
-- (2) A confirmacao para de sair pela porta dos fundos quando ja esta
--     confirmada. Ela chama o claim mesmo assim e deixa a decisao com ele —
--     que e onde a idempotencia e ESTRUTURAL (indice + clausula), nao uma
--     lembranca de quem escreveu o if.
--
-- E o cabecalho da mensagem muda: a correcao se anuncia e diz que a anterior
-- nao vale mais. Duas mensagens identicas seriam quase tao ruins quanto o
-- silencio — o comercial nao saberia qual das duas seguir.
--
-- Teste: 048-correcao-se-anuncia.test.sql
-- Mutantes: scripts/mutantes-048.mjs

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
  v_corpo_base text;
  v_ja         record;
  v_e_correcao boolean := false;
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
  v_corpo_base := format(
    E'*%s*\n'
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

  -- CORRECAO: ja saiu uma entrega desta mesma experimental com conteudo
  -- DIFERENTE do que se mandaria agora?
  --
  -- A comparacao e por CONTEUDO, nao por horario. `atualizado_em >
  -- confirmado_em` seria o instinto — e nao funciona: now() e constante dentro
  -- de uma transacao, entao os dois sao iguais no exato caminho que o teste
  -- percorre, e o conserto ficaria sem carrasco possivel. Conteudo tambem diz
  -- a verdade mais direta: se a mensagem seria a mesma, nao ha o que corrigir.
  --
  -- right(...) em vez de LIKE: o texto do professor tem % e _ a vontade, e
  -- LIKE os leria como curinga.
  select n.status, n.corpo into v_ja
    from fabio_notificacoes n
   where n.referencia_tipo = 'lead_experimental_registro'
     and n.referencia_id   = p_registro_id::text
     and n.canal = 'whatsapp';

  v_e_correcao := v_ja.status = 'enviada'
              and right(v_ja.corpo, length(v_corpo_base)) is distinct from v_corpo_base;

  v_corpo := case when v_e_correcao
    then E'✏️ *Correção — a devolutiva desta experimental mudou*\n_a versão anterior não vale mais_\n\n'
    else E'🎓 *Experimental registrada*\n\n' end || v_corpo_base;

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
    -- ou: JA FOI ENTREGUE, e o professor corrigiu o texto depois.
    --
    -- Este ramo desfaz, de proposito e so aqui, a regra "enviada nao e
    -- retomada" — que existe pra o comercial nao receber a mesma devolutiva
    -- duas vezes. A excecao e ESTREITA: v_e_correcao so e verdadeiro quando o
    -- conteudo mudou. Reconfirmar sem editar continua nao gerando mensagem
    -- nenhuma, e o teste tem passo pra isso.
    or (fabio_notificacoes.status = 'enviada' and v_e_correcao)
  returning id into v_id;

  if v_id is null then
    -- ja enviada, ou outro worker esta com o lease VIVO agora
    return jsonb_build_object('ok', true, 'claimed', false, 'motivo', 'lease_vivo_ou_enviada');
  end if;

  return jsonb_build_object('ok', true, 'claimed', true,
                            'notificacao_id', v_id, 'lease_token', v_token);
end
$function$;

CREATE OR REPLACE FUNCTION public.app_confirmar_registro_experimental(p_registro_id uuid, p_confirmado_por integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_vinculo_id  bigint;
  v_status      text;
  v_origem      text;
  v_prof        integer := public.fn_professor_do_usuario();
  v_prof_aula   integer;
  v_presenca_ok boolean;
  v_aviso       jsonb;
  v_not_id      uuid;
begin
  if v_prof is null then
    raise exception 'sem_professor_vinculado';
  end if;

  select r.vinculo_id, r.status, r.origem, ae.professor_id
    into v_vinculo_id, v_status, v_origem, v_prof_aula
    from lead_experimental_registros r
    join lead_experimental_aulas v on v.id = r.vinculo_id
    join aulas_emusys ae on ae.id = v.aula_local_id
   where r.id = p_registro_id
     for update of r;

  if not found then
    raise exception 'registro_inexistente: %', p_registro_id;
  end if;

  -- Mesma guarda da app_registrar_experimental: confirmar tambem e escrita.
  -- Confirmar grava presenca de fonte FORTE, promove o estado do vinculo e
  -- dispara aviso ao comercial — nao e leitura.
  if v_prof_aula is distinct from v_prof then
    raise exception 'aula_de_outro_professor';
  end if;

  if v_status = 'confirmado' then
    -- Confirmar de novo E o caminho da CORRECAO: fn_registrar_experimental_interno
    -- atualiza a MESMA linha (indice uq_lead_exp_registro_vigente e por vinculo),
    -- entao corrigir nao cria registro novo — muda o texto deste.
    --
    -- Antes desta migration o retorno antecipado daqui matava a correcao em
    -- silencio: o professor arrumava o prontuario e a Daiana ficava com a
    -- versao velha, sem nada sinalizando.
    --
    -- Agora a idempotencia mora onde ela e estrutural: o claim so reabre linha
    -- ENTREGUE quando o conteudo mudou. Reconfirmar sem editar passa por aqui,
    -- nao gera mensagem, e devolve ja_confirmado — igual a antes.
    select public.fabio_claim_aviso_comercial(p_registro_id, 0) into v_aviso;
    return jsonb_build_object(
      'registro_id',   p_registro_id,
      'ja_confirmado', true,
      'correcao',      coalesce((v_aviso->>'claimed')::boolean, false),
      'aviso_motivo',  v_aviso->>'motivo');
  end if;

  if v_status = 'descartado' then
    raise exception 'registro_descartado: %', p_registro_id;
  end if;

  update lead_experimental_registros
     set status = 'confirmado', confirmado_em = now(), confirmado_por = p_confirmado_por,
         atualizado_em = now()
   where id = p_registro_id;

  -- Presenca com a fonte certa: registro pelo app e professor_la_teacher;
  -- por audio e fabio_audio. Ambos passam em fn_presenca_e_forte — e NENHUM
  -- deles e 'professor_app', que nao existe no vocabulario e faria a presenca
  -- nascer fraca em silencio. (Bloqueio do Alfredo na revisao da spec.)
  select public.fn_registrar_presenca_experimental(
           v_vinculo_id, 'presente',
           case when v_origem = 'whatsapp' then 'fabio_audio' else 'professor_la_teacher' end)
    into v_presenca_ok;

  -- p_lease_minutos => 0: a confirmacao ENFILEIRA, nao trabalha.
  -- Lease serve pra dizer "estou trabalhando nisto agora". Quem confirma nao
  -- esta: ele enfileira e vai embora. Quem trabalha e o worker, e o lease de
  -- verdade e o dele — com o token que ele mesmo usa pra fechar a linha.
  select public.fabio_claim_aviso_comercial(p_registro_id, 0) into v_aviso;
  v_not_id := (v_aviso->>'notificacao_id')::uuid;

  return jsonb_build_object(
    'registro_id',      p_registro_id,
    'presenca_gravada', v_presenca_ok,
    'notificacao_id',   v_not_id,
    'aviso_claimed',    (v_aviso->>'claimed')::boolean,
    'aviso_motivo',     v_aviso->>'motivo'
  );
end
$function$;
