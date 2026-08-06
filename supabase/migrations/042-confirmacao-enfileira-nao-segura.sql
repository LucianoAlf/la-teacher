-- 042 — a confirmacao ENFILEIRA o aviso; quem trabalha e o worker
--
-- Defeito de desenho da 038, que so apareceu ao construir o consumidor.
-- Medido em transacao descartavel, 06/08/2026:
--
--   1) confirmacao enfileira ......... claimed: true, lease de 10 min
--   2) worker chega pra entregar ..... claimed: FALSE
--   3) motivo ........................ lease_vivo_ou_enviada
--
-- A confirmacao pegava o lease e nao trabalhava. O comercial receberia a
-- devolutiva 10 minutos depois da aula em vez de na hora, e o envio entraria
-- no log como recuperacao de lease abandonado, com tentativas incrementando.
-- Nenhum erro em lugar nenhum — fila com dono errado nao levanta excecao,
-- so nao entrega.
--
-- SAO DUAS MUDANCAS, e a segunda so existe porque o teste reprovou a primeira:
--
-- (1) a confirmacao passa p_lease_minutos => 0 — ela enfileira, nao segura.
--
-- (2) o claim aceita lease VENCIDO com <= em vez de <.
--     So com (1), lease_expira_em fica igual a now(), e now() e constante
--     dentro de uma transacao: `now() < now()` e falso, entao o worker
--     continuava barrado. Em producao passaria por acidente (transacoes
--     diferentes, o relogio anda alguns segundos) — e conserto que depende do
--     relogio ter andado e conserto que nenhum teste consegue provar.
--     Com <=, um lease que chegou na validade esta vencido, em qualquer
--     transacao. Lease vivo continua sendo estritamente futuro, entao ninguem
--     rouba trabalho de quem esta trabalhando — o teste tem passo pra isso.
--
-- Teste: 042-confirmacao-enfileira-nao-segura.test.sql
-- Mutantes: scripts/mutantes-042-confirmacao.mjs

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
  v_corpo := format(
    E'Experimental registrada — %s\n\nQuando: %s\nPresenca: %s\n\nComo foi: %s\n\nProximos passos: %s\n\n[interno] Leitura: %s',
    v_reg.nome_aluno,
    to_char(v_reg.data_hora_inicio at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI'),
    coalesce(v_reg.presenca_status, 'nao informada'),
    coalesce(v_reg.devolutiva_familia, '(nao preenchido)'),
    coalesce(v_reg.proximos_passos, '(nao preenchido)'),
    coalesce(v_reg.leitura_de_conversao, '(nao preenchido)'));

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
    -- Idempotente: confirmar duas vezes nao duplica aviso nem regrava presenca.
    return jsonb_build_object('registro_id', p_registro_id, 'ja_confirmado', true);
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

comment on function public.app_confirmar_registro_experimental(uuid,integer) is
'Confirma o registro da experimental: marca confirmado, grava presenca de fonte forte e ENFILEIRA o aviso ao comercial na mesma transacao — sem segurar lease, porque quem entrega e o worker. Resolve auth.uid() e exige que a aula seja do professor logado.';
