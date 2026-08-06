-- 036 — o aviso ao comercial e do Fabio, com destinatario resolvido no BANCO
--
-- Nao pelo n8n: o dedup de la e staticData na memoria do workflow (reimportar
-- apaga o historico e repete mensagem), sem retry, sem recibo, e o rastro fica
-- em executionData que expira. A fila do Fabio tem lease, tentativas e recibo.
--
-- E o contato mora em TABELA, nao dentro do fluxo: em um mes a pessoa do
-- Recreio mudou (Cleiton virou gerente, entrou a Daiana) e o no do n8n
-- continua chamado "Clayton". Contato em tabela se corrige com um update.

create table public.unidade_contato_comercial (
  unidade_id    uuid primary key references public.unidades(id),
  nome          text not null,
  whatsapp      text not null,
  ativo         boolean not null default true,
  atualizado_em timestamptz not null default now()
);

revoke all on table public.unidade_contato_comercial from public, anon, authenticated;
grant select on table public.unidade_contato_comercial to service_role;

-- A fila aprende a falar com quem nao e professor. professor_id vira opcional,
-- e um CHECK garante que todo aviso tenha EXATAMENTE um destinatario resolvido
-- — destinatario ausente tem que ser impossivel, nao improvavel.
alter table public.fabio_notificacoes alter column professor_id drop not null;
alter table public.fabio_notificacoes
  add column destinatario_tipo text not null default 'professor'
    check (destinatario_tipo in ('professor','comercial')),
  add column destinatario_whatsapp text;

-- ATENCAO ao ramo do meio: sem ele, o CHECK se contradiz com o proprio rastro
-- de "sem destinatario" — que grava, por definicao, destinatario_whatsapp nulo.
-- A primeira versao deste plano tinha essa contradicao e quebraria em runtime
-- exatamente no caminho de excecao (achado do Alfredo). O rastro de ausencia
-- precisa de excecao EXPLICITA, senao a unica forma de registrar a falta de
-- destinatario seria... nao registrar.
-- O ramo de excecao e ESTREITO de proposito: nao basta "tem esse status".
-- `status = 'pulada_sem_destinatario' or ...` liberaria qualquer linha com esse
-- status, inclusive aviso de professor mal formado — a excecao viraria porta.
-- Aqui ela descreve exatamente UM formato: rastro comercial, sem professor e
-- sem telefone. (Achado do Alfredo na revisao do f722171.)
alter table public.fabio_notificacoes
  add constraint chk_notificacao_destinatario check (
    (status = 'pulada_sem_destinatario'
      and destinatario_tipo = 'comercial'
      and professor_id is null
      and destinatario_whatsapp is null)
    or
    (destinatario_tipo = 'professor' and professor_id is not null)
    or
    (destinatario_tipo = 'comercial' and destinatario_whatsapp is not null)
  );

-- Vocabulario existente estendido, nao substituido: o CHECK de tipo hoje aceita
-- briefing_matinal, pendencia_registro, experimental_nova, reagendamento, outro,
-- devolutiva_pronta, devolutiva_destinatario.
alter table public.fabio_notificacoes drop constraint if exists fabio_notificacoes_tipo_check;
alter table public.fabio_notificacoes add constraint fabio_notificacoes_tipo_check
  check (tipo in ('briefing_matinal','pendencia_registro','experimental_nova','reagendamento',
                  'outro','devolutiva_pronta','devolutiva_destinatario','experimental_registrada'));

-- 'pulada_preferencia' e sobre preferencia do professor. Falta de destinatario
-- e outra coisa, e precisa ser VISIVEL — nao pode se disfarcar de preferencia.
alter table public.fabio_notificacoes drop constraint if exists fabio_notificacoes_status_check;
alter table public.fabio_notificacoes add constraint fabio_notificacoes_status_check
  check (status in ('processando','enviada','falhou','pulada_preferencia','pulada_sem_destinatario'));

-- CLAIM canonico, no mesmo formato de fabio_claim_notificacao_por_referencia
-- (018): lease com token, tentativas, backoff e retorno {claimed, lease_token}.
-- A primeira versao deste plano dava INSERT cru com status='processando' — o
-- que esvaziava o argumento que ganhou a decisao contra o n8n ("a fila do
-- Fabio tem lease, retry e recibo"). Achado do Alfredo.
--
-- A idempotencia NAO e reimplementada aqui: ela e estrutural, do indice
-- uq_fabio_notif_por_referencia (referencia_tipo, referencia_id, canal). Este
-- ON CONFLICT so decide QUANDO vale retomar: falhou com backoff vencido, ou o
-- dono anterior sumiu (lease expirado). Enviada nao e retomada.
create or replace function public.fabio_claim_aviso_comercial(
  p_registro_id   uuid,
  p_lease_minutos integer default 10
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
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
      and fabio_notificacoes.lease_expira_em < now())
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

revoke all on function public.fabio_claim_aviso_comercial(uuid,integer) from public, anon, authenticated;
grant execute on function public.fabio_claim_aviso_comercial(uuid,integer) to service_role;

comment on table public.unidade_contato_comercial is
'Quem recebe o aviso comercial de cada unidade. Em tabela, nao no fluxo: a pessoa muda (Recreio trocou em um mes) e o no do n8n continua com o nome antigo.';
comment on function public.fabio_claim_aviso_comercial(uuid,integer) is
'Enfileira o aviso da experimental registrada pro comercial da unidade, com lease. Sem contato cadastrado NAO some: vira status pulada_sem_destinatario, e e retomado quando o contato aparecer.';

-- Contatos vigentes, conferidos com o n8n em 05/08/2026 (os tres batem).
-- Vitoria tem DDD 31 porque e de Minas — esta correto.
insert into public.unidade_contato_comercial (unidade_id, nome, whatsapp)
select id, 'Vitória', '553171422022'  from public.unidades where codigo = 'CG'
on conflict (unidade_id) do nothing;
insert into public.unidade_contato_comercial (unidade_id, nome, whatsapp)
select id, 'Kailane', '5521984690143' from public.unidades where codigo = 'BARRA'
on conflict (unidade_id) do nothing;
insert into public.unidade_contato_comercial (unidade_id, nome, whatsapp)
select id, 'Daiana',  '5521968060404' from public.unidades where codigo = 'REC'
on conflict (unidade_id) do nothing;
