-- 066 — a coordenação manda recado (e o recado tem autor)
--
-- POR QUE NÃO É "ENFILEIRAR"
-- A fila do Fábio não tem estado de entrada: `status` aceita 'processando',
-- 'enviada', 'falhou' e 'pulada_*' — não existe 'pendente'. A linha NASCE no
-- claim do worker. Então não há caixa onde o painel deposite um recado para
-- alguém levar depois; quem manda, manda na hora.
--
-- Daí a sequência: RESERVA ('processando' com lease) → envia → CONCLUI
-- ('enviada' com recibo, ou 'falhou' com o erro). Enviar primeiro e gravar
-- depois inverteria a ordem do risco: a colisão seria descoberta com o WhatsApp
-- já entregue, e ninguém desentrega mensagem.
--
-- A CHAVE DIÁRIA É COMPARTILHADA DE PROPÓSITO
-- `uq_fabio_notif_recorrente_diario` cobre (professor, tipo, dia_referencia,
-- canal) para 'briefing_matinal' e 'pendencia_registro'. Usando
-- 'pendencia_registro', o recado manual colide com a cobrança AUTOMÁTICA do
-- mesmo dia — e é isso que a gente quer: dois toques de cobrança no mesmo dia
-- queimam o canal, que é o mesmo do briefing das 8h. A RPC devolve
-- 'ja_cobrado_hoje' para a tela poder DIZER isso, em vez de não fazer nada em
-- silêncio.
--
-- QUEM PEDIU FICA REGISTRADO — E É CONFERIDO
-- Auditoria do LA Report em 08/08: `professor_360_ocorrencias.registrado_por` é
-- null em 192 de 192 linhas. Penalidade de 25 pontos sem autor. Como aqui o
-- disparo passa a ser manual, a coluna nasce junto e o autor é VALIDADO contra
-- a lista da coordenação — gravar sem conferir só moveria o problema.

alter table public.fabio_notificacoes
  add column if not exists solicitado_por uuid;

comment on column public.fabio_notificacoes.solicitado_por is
  'Quem pediu o disparo manual (auth.users.id). Null = disparo automatico do '
  'Fabio. Existe porque acao de governanca sem autor nao se audita.';

-- ───────────────────────────────────────────────────────────────────────────
-- RESERVA
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.fn_reservar_recado_coordenacao(
  p_professor_id   int,
  p_corpo          text,
  p_solicitado_por uuid
) returns jsonb
language plpgsql
volatile
security definer
set search_path to 'public'
as $function$
declare
  v_id       uuid;
  v_token    uuid;
  v_telefone text;
  v_ativo    boolean;
begin
  -- Autor conferido, não só anotado.
  if not exists (
    select 1
      from public.la_teacher_coordenacao c
      join public.usuarios u on u.id = c.usuario_id
     where u.auth_user_id = p_solicitado_por
       and coalesce(u.ativo, true)
  ) then
    raise exception 'apenas_admin';
  end if;

  if p_corpo is null or length(btrim(p_corpo)) < 3 then
    raise exception 'recado_vazio';
  end if;

  select p.ativo, nullif(regexp_replace(coalesce(p.telefone_whatsapp,''), '\D', '', 'g'), '')
    into v_ativo, v_telefone
    from public.professores p
   where p.id = p_professor_id;

  if v_ativo is null then
    raise exception 'professor_inexistente';
  end if;
  if not v_ativo then
    raise exception 'professor_inativo';
  end if;
  if v_telefone is null then
    return jsonb_build_object('reservado', false, 'motivo', 'sem_whatsapp');
  end if;

  -- Férias é a ÚNICA coisa que barra cobrança: para categoria 'governanca' a
  -- própria fn_fabio_pode_notificar ignora silêncio e domingo, por projeto.
  if not public.fn_fabio_pode_notificar(p_professor_id, 'governanca', now()) then
    return jsonb_build_object('reservado', false, 'motivo', 'professor_em_pausa');
  end if;

  v_token := gen_random_uuid();

  -- `dia_referencia` NÃO entra na lista: é coluna gerada,
  -- `(criado_em at time zone 'America/Sao_Paulo')::date`. Deixar o banco
  -- calcular é o certo — a virada do dia da dedupe tem que ser a de Brasília,
  -- senão às 21h ela vira e o professor leva duas cobranças na mesma noite.
  --
  -- `status` VAI explícito porque o DEFAULT da coluna é 'pendente', que o
  -- próprio CHECK da tabela não aceita. Omitir quebraria.
  insert into public.fabio_notificacoes
    (professor_id, tipo, categoria, canal, titulo, corpo,
     destinatario_tipo,
     status, tentativas, lease_token, lease_expira_em, solicitado_por)
  values
    (p_professor_id, 'pendencia_registro', 'governanca', 'whatsapp',
     'Recado da coordenação', btrim(p_corpo),
     'professor',
     'processando', 1, v_token, now() + interval '5 minutes', p_solicitado_por)
  on conflict (professor_id, tipo, dia_referencia, canal)
    where tipo = any (array['briefing_matinal','pendencia_registro'])
  do nothing
  returning id into v_id;

  if v_id is null then
    return jsonb_build_object('reservado', false, 'motivo', 'ja_cobrado_hoje');
  end if;

  return jsonb_build_object('reservado', true,
                            'notificacao_id', v_id,
                            'lease_token', v_token,
                            'telefone', v_telefone);
end;
$function$;

-- ───────────────────────────────────────────────────────────────────────────
-- CONCLUSÃO
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.fn_concluir_recado_coordenacao(
  p_notificacao_id uuid,
  p_lease_token    uuid,
  p_ok             boolean,
  p_recibo         text default null,
  p_erro           text default null
) returns jsonb
language plpgsql
volatile
security definer
set search_path to 'public'
as $function$
declare
  v_afetadas int;
begin
  -- O lease é a prova de que quem conclui é quem reservou. Sem ele, uma
  -- chamada perdida marcaria 'enviada' uma mensagem que nunca saiu.
  update public.fabio_notificacoes
     set status       = case when p_ok then 'enviada' else 'falhou' end,
         enviada_em   = case when p_ok then now() else enviada_em end,
         envio_recibo = case when p_ok then p_recibo else envio_recibo end,
         last_error   = case when p_ok then null else left(coalesce(p_erro,'erro'), 500) end,
         lease_token  = null,
         lease_expira_em = null
   where id = p_notificacao_id
     and lease_token = p_lease_token;

  get diagnostics v_afetadas = row_count;
  return jsonb_build_object('concluida', v_afetadas = 1);
end;
$function$;

-- ───────────────────────────────────────────────────────────────────────────
-- Estas duas são da EDGE FUNCTION, não do navegador. `create or replace`
-- PRESERVA privilégios: sem os revokes explícitos, um grant antigo sobrevive
-- à substituição e o mutante de permissão passa batido.
-- ───────────────────────────────────────────────────────────────────────────
revoke all on function public.fn_reservar_recado_coordenacao(int, text, uuid) from public;
revoke all on function public.fn_reservar_recado_coordenacao(int, text, uuid) from anon;
revoke all on function public.fn_reservar_recado_coordenacao(int, text, uuid) from authenticated;

revoke all on function public.fn_concluir_recado_coordenacao(uuid, uuid, boolean, text, text) from public;
revoke all on function public.fn_concluir_recado_coordenacao(uuid, uuid, boolean, text, text) from anon;
revoke all on function public.fn_concluir_recado_coordenacao(uuid, uuid, boolean, text, text) from authenticated;

comment on function public.fn_reservar_recado_coordenacao(int, text, uuid) is
  'Reserva o recado da coordenacao em fabio_notificacoes (processando + lease) '
  'antes do envio. Confere o autor contra la_teacher_coordenacao. Colide com a '
  'cobranca automatica do mesmo dia de proposito. So service_role.';

comment on function public.fn_concluir_recado_coordenacao(uuid, uuid, boolean, text, text) is
  'Fecha o recado reservado: enviada + recibo, ou falhou + erro. O lease_token '
  'prova que quem conclui e quem reservou. So service_role.';
