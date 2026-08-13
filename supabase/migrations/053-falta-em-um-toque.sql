-- SUPERADA POR: 075-o-fabio-cobra-o-semaforo.sql
--
-- Este arquivo reinstala o `fabio_notificacoes_tipo_check` com **9** tipos. A
-- producao ja tem **13**: a 075 acrescentou os tres de `feedback_*` e a 095 o
-- `registro_recibo`. Replayar este arquivo tenta apertar o CHECK por cima de
-- linhas VIVAS que usam os tipos novos -- por isso o erro e
-- `is violated by some row`, e nao um defeito do que a 053 entregou.
--
-- 053 — a falta em um toque
--
-- APROVADO PELO ALF: "se o aluno faltar experimental, seria outra tela, um
-- toque sem os campos pedagógicos".
--
-- E o motivo de ser outra tela é mais forte que ergonomia: aula que não
-- aconteceu NÃO TEM capítulo pedagógico. A 035 já recusa registro de vínculo
-- em 'faltou' (`experimental_faltou_nao_tem_registro`) exatamente por isso.
-- Um formulário de quatro campos pra quem não deu aula convida a inventar.
--
-- MAS A FALTA PRECISA SAIR PELO MESMO CANO.
-- Pro comercial, "não veio" é a informação mais urgente do dia: é ela que abre
-- a janela de remarcar enquanto a família ainda lembra. Então a falta vira uma
-- notificação irmã da devolutiva — mesma tabela, mesma fila, mesmo worker,
-- mesmo lease. O que muda é o corpo e a referência.
--
-- POR QUE NÃO TEM RAMO DE CORREÇÃO (a 048 tem).
-- Se o professor marcar falta por engano e depois registrar a aula de verdade,
-- o comercial recebe as duas mensagens em sequência — e a segunda conta a
-- história certa. Não é elegante, e é honesto: as duas foram verdade quando
-- saíram. Inventar aqui um "cancelamento de falta" seria máquina pra um caso
-- que a sequência já resolve.
--
-- Teste: 053-falta-em-um-toque.test.sql
-- Mutantes: scripts/mutantes-053.mjs

-- ── 1) O tipo novo no vocabulário da tabela ─────────────────────────────────
alter table public.fabio_notificacoes drop constraint if exists fabio_notificacoes_tipo_check;
alter table public.fabio_notificacoes add constraint fabio_notificacoes_tipo_check
  check (tipo = any (array[
    'briefing_matinal', 'pendencia_registro', 'experimental_nova', 'reagendamento',
    'outro', 'devolutiva_pronta', 'devolutiva_destinatario', 'experimental_registrada',
    'experimental_falta']));

-- ── 2) O aviso de falta entra na fila ───────────────────────────────────────
create or replace function public.fabio_claim_aviso_falta_experimental(
  p_vinculo_id     bigint,
  p_lease_minutos  integer default 10
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_vinc    record;
  v_contato record;
  v_corpo   text;
  v_id      uuid;
  v_token   uuid := gen_random_uuid();
begin
  -- A unidade vem da AULA, não do vínculo: `lead_experimental_aulas` não tem
  -- essa coluna, e é a aula que diz onde a experimental acontece de fato.
  select v.id, ae.unidade_id, le.nome_aluno, ae.data_hora_inicio, p.nome as professor_nome
    into v_vinc
    from lead_experimental_aulas v
    join lead_experimentais le on le.id = v.lead_experimental_id
    join aulas_emusys ae on ae.id = v.aula_local_id
    left join professores p on p.id = ae.professor_id
   where v.id = p_vinculo_id and v.substituido_em is null;

  if not found then
    raise exception 'vinculo_inexistente_ou_sem_aula: %', p_vinculo_id;
  end if;

  select * into v_contato
    from unidade_contato_comercial
   where unidade_id = v_vinc.unidade_id and ativo;

  -- Curto de propósito. Aqui não há nada pedagógico pra contar, e enfeitar a
  -- ausência com texto faria o consultor procurar conteúdo que não existe.
  -- Dia da semana na mão: to_char(...,'Day') depende de lc_time do servidor.
  v_corpo := format(
    E'🚫 *Experimental — o aluno não veio*\n\n'
    '*%s*\n'
    '_%s · %s_\n'
    '━━━━━━━━━━━━━━\n'
    'Marcado pelo professor %s.\n'
    'Vale falar com a família enquanto está fresco, pra remarcar.',
    v_vinc.nome_aluno,
    case extract(dow from v_vinc.data_hora_inicio at time zone 'America/Sao_Paulo')
      when 0 then 'domingo' when 1 then 'segunda' when 2 then 'terça'
      when 3 then 'quarta'  when 4 then 'quinta' when 5 then 'sexta'
      else 'sábado' end,
    to_char(v_vinc.data_hora_inicio at time zone 'America/Sao_Paulo', 'DD/MM · HH24:MI'),
    coalesce(v_vinc.professor_nome, '(não identificado)'));

  if v_contato.unidade_id is null then
    -- Sem comercial cadastrado o rastro NÃO some: fica visível na fila e é
    -- retomado quando alguém cadastrar o contato (mesma promessa da 036, e o
    -- mesmo varredor da 043 cumpre — por isso a fila lista este status).
    insert into fabio_notificacoes
      (professor_id, destinatario_tipo, tipo, categoria, corpo, canal, status,
       motivo_pulada, referencia_tipo, referencia_id, destinatario_whatsapp)
    values
      (null, 'comercial', 'experimental_falta', 'informativa', v_corpo, 'whatsapp',
       'pulada_sem_destinatario', 'sem_contato_comercial_na_unidade',
       'lead_experimental_falta', p_vinculo_id::text, null)
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
    (null, 'comercial', v_contato.whatsapp, 'experimental_falta', 'informativa', v_corpo,
     'whatsapp', 'processando', 1, v_token, now() + make_interval(mins => p_lease_minutos),
     'lead_experimental_falta', p_vinculo_id::text)
  on conflict (referencia_tipo, referencia_id, canal)
    where referencia_tipo is not null and referencia_id is not null
  do update set
    status                = 'processando',
    tentativas            = fabio_notificacoes.tentativas + 1,
    corpo                 = excluded.corpo,
    destinatario_whatsapp = excluded.destinatario_whatsapp,
    lease_token           = excluded.lease_token,
    lease_expira_em       = excluded.lease_expira_em,
    last_error            = null
  where
    (fabio_notificacoes.status = 'falhou'
      and (fabio_notificacoes.proxima_tentativa_em is null
           or fabio_notificacoes.proxima_tentativa_em <= now()))
    or (fabio_notificacoes.status = 'processando'
      and fabio_notificacoes.lease_expira_em is not null
      and fabio_notificacoes.lease_expira_em <= now())
    or (fabio_notificacoes.status = 'pulada_sem_destinatario')
    -- Sem ramo de correção: falta entregue não é reenviada. Ver cabeçalho.
  returning id into v_id;

  if v_id is null then
    return jsonb_build_object('ok', true, 'claimed', false, 'motivo', 'lease_vivo_ou_enviada');
  end if;

  return jsonb_build_object('ok', true, 'claimed', true,
                            'notificacao_id', v_id, 'lease_token', v_token);
end
$function$;

revoke all on function public.fabio_claim_aviso_falta_experimental(bigint, integer) from public, anon, authenticated;
grant execute on function public.fabio_claim_aviso_falta_experimental(bigint, integer) to service_role;

-- ── 3) A porta do professor ─────────────────────────────────────────────────
create or replace function public.app_declarar_falta_experimental(p_vinculo_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_prof     integer := public.fn_professor_do_usuario();
  v_vinc     record;
  v_aula     public.aulas_emusys%rowtype;
  v_registro record;
  v_gravou   boolean;
  v_aviso    jsonb;
begin
  if v_prof is null then
    raise exception 'sem_professor_vinculado';
  end if;

  select v.id, v.estado, v.aula_local_id
    into v_vinc
    from lead_experimental_aulas v
   where v.id = p_vinculo_id and v.substituido_em is null;
  if not found then
    raise exception 'vinculo_inexistente_ou_sem_aula: %', p_vinculo_id;
  end if;
  if v_vinc.estado = 'cancelado' then
    raise exception 'experimental_cancelada';
  end if;

  select * into v_aula from public.aulas_emusys where id = v_vinc.aula_local_id;
  if not found then
    raise exception 'vinculo_inexistente_ou_sem_aula: %', p_vinculo_id;
  end if;
  -- `is distinct from` e não `<>`: aula órfã + professor órfão fariam
  -- null <> null virar nulo, e a guarda abriria pra aula de ninguém.
  if v_aula.professor_id is distinct from v_prof then
    raise exception 'aula_de_outro_professor';
  end if;
  if v_aula.data_hora_inicio > now() + interval '15 minutes' then
    raise exception 'gravacao_ainda_nao_disponivel';
  end if;

  -- Aula JÁ RELATADA não vira falta. Se a devolutiva foi confirmada, ela já
  -- saiu pro comercial contando uma aula que aconteceu — deixar "faltou"
  -- passar por cima produziria duas verdades contraditórias no mesmo dia, e a
  -- segunda apagaria a primeira sem que ninguém tivesse decidido isso.
  select r.id, r.status into v_registro
    from lead_experimental_registros r
   where r.vinculo_id = p_vinculo_id and r.status <> 'descartado';
  if v_registro.status = 'confirmado' then
    raise exception 'experimental_ja_registrada_como_realizada';
  end if;

  v_gravou := public.fn_registrar_presenca_experimental(
                p_vinculo_id, 'falta', 'professor_la_teacher');

  -- Lease ZERO: quem enfileira não trabalha. Foi o conserto da 042 — com lease
  -- vivo, o worker recebia `lease_vivo_ou_enviada` e o aviso só sairia 10
  -- minutos depois, registrado como recuperação de abandono. Nada dava erro.
  v_aviso := public.fabio_claim_aviso_falta_experimental(p_vinculo_id, 0);

  return jsonb_build_object(
    'vinculo_id',       p_vinculo_id,
    'presenca_gravada', v_gravou,
    'aviso_claimed',    v_aviso ->> 'claimed',
    'aviso_motivo',     v_aviso ->> 'motivo',
    'notificacao_id',   v_aviso ->> 'notificacao_id');
end
$function$;

comment on function public.app_declarar_falta_experimental(bigint) is
  'Um toque: grava a falta com fonte forte (professor_la_teacher) e enfileira o '
  'aviso curto pro comercial, na MESMA transação. Sem campos pedagógicos — aula '
  'que não aconteceu não tem capítulo.';

revoke all on function public.app_declarar_falta_experimental(bigint) from public, anon;
grant execute on function public.app_declarar_falta_experimental(bigint) to authenticated;

-- ── 4) A fila enxerga os dois tipos ─────────────────────────────────────────
-- Sem isto o aviso de falta fica na tabela e ninguém varre: seria o defeito de
-- sempre — o gancho existe, o chamador não. E o worker precisa saber QUAL
-- claim chamar, por isso `tipo` e `vinculo_id` passam a viajar no payload.
create or replace function public.fabio_avisos_comerciais_pendentes(p_lote integer default 10)
returns jsonb
language sql
stable security definer
set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(x order by prioridade, criado_em), '[]'::jsonb)
    from (
      select
        case when n.status = 'pulada_sem_destinatario' then 1 else 0 end as prioridade,
        n.criado_em,
        jsonb_build_object(
          'notificacao_id', n.id,
          'tipo',           n.tipo,
          -- Um dos dois vem nulo: é ele que diz qual claim o worker chama.
          'registro_id',    case when n.referencia_tipo = 'lead_experimental_registro'
                                 then n.referencia_id end,
          'vinculo_id',     case when n.referencia_tipo = 'lead_experimental_falta'
                                 then n.referencia_id end,
          'status',         n.status,
          'tentativas',     n.tentativas,
          'criado_em',      n.criado_em
        ) as x
      from fabio_notificacoes n
      where n.destinatario_tipo = 'comercial'
        and n.tipo in ('experimental_registrada', 'experimental_falta')
        and n.referencia_tipo in ('lead_experimental_registro', 'lead_experimental_falta')
        and (
          (n.status = 'processando'
            and n.lease_expira_em is not null
            and n.lease_expira_em <= now())
          or (n.status = 'falhou'
            and (n.proxima_tentativa_em is null or n.proxima_tentativa_em <= now()))
          or (n.status = 'pulada_sem_destinatario')
        )
      order by prioridade, n.criado_em
      limit greatest(coalesce(p_lote, 10), 1)
    ) s
$function$;

revoke all on function public.fabio_avisos_comerciais_pendentes(integer) from public, anon, authenticated;
grant execute on function public.fabio_avisos_comerciais_pendentes(integer) to service_role;
