-- 076 — o carteiro da cobrança (e a coordenação recebe de verdade)
--
-- A 075 enfileirava e ninguém buscava. Aqui a fila vira o que a casa já usa em
-- briefing, pendência e devolutiva: RESERVA ('processando' + lease) → envia →
-- CONCLUI — e, a partir desta revisão (09/08), com a MESMA volta que aquelas
-- três já têm: uma RESERVA que morreu no meio do caminho pode ser reclamada,
-- não só criada. A primeira versão desta migration copiava só a forma dos três
-- passos e usava `on conflict ... do nothing` — tinha o desenho, mas não a
-- resiliência (ver "POR QUE A RESERVA GANHOU VOLTA", no fim deste cabeçalho).
-- Quem executa os três passos é o fabio_notification_worker.py; o banco
-- responde "quem cobrar hoje", "reserve esta linha pra mim" e, se for o caso,
-- "pode reclamar esta MESMA linha de novo".
--
-- POR QUE NÃO FICA UM pg_cron ENFILEIRANDO
-- `status` não tem estado de entrada: aceita 'processando', 'enviada', 'falhou'
-- e 'pulada_*' — não existe 'pendente'. Linha que nasce 'processando' com lease
-- de 10 minutos e espera horas por um coletor não é fila, é mentira: parece em
-- voo e não está. Por isso a fn_enfileirar_cobranca_feedback CAI aqui. Ela
-- também convidava ao erro no próprio comentário ("ainda não agendado no
-- cron") — agendar aquilo encheria a tabela em silêncio.
--
-- POR QUE A COORDENAÇÃO PRECISA DE UM QUARTO RAMO NO CHECK
-- A lista do dia 1º vai pro GRUPO da coordenação no WhatsApp, o mesmo que já
-- recebe o escalonamento da presença. Grupo não é professor nem lead comercial:
-- é `destinatario_tipo='coordenacao'`, `professor_id` nulo e o JID em
-- `destinatario_whatsapp`. O CHECK é ESTENDIDO, nunca substituído — os três
-- ramos que já existiam continuam palavra por palavra.
--
-- POR QUE A RESERVA GANHOU VOLTA (revisão de 09/08, achado da revisão de código)
-- A primeira versão copiou o `on conflict ... do nothing` da 066 sem examinar
-- se ele servia AQUI. Pra 066 serve: o recado é disparado por gente, e gente
-- re-clica se algo falhar. Esta fila não tem quem re-clique — ela dispara em
-- exatamente três dias do mês (o dia 1º, e os dois âncorados no fim do mês
-- anterior), o timer roda uma vez por dia, e no dia seguinte a um desses três
-- a função já responde `fase:'nenhuma'`. Um worker que morre entre a RESERVA e
-- o envio, ou um envio de WhatsApp que falha, deixava a linha presa em
-- 'processando' com lease morto — e toda chamada seguinte no mesmo dia batia
-- em `ja_cobrado_hoje`/`ja_entregue_hoje`, achando que já tinha sido feito. Sem
-- uma segunda chance NO MESMO CICLO, aquele professor (ou a coordenação
-- inteira) perdia a cobrança até o mês seguinte. Por isso os dois
-- `do nothing` viraram `do update` que RECLAMA a própria linha quando ela está
-- seguramente livre — mesma forma que fabio_claim_notificacao já usa (018):
--   • reclamável quando `status='falhou'`, ou `status='processando'` com
--     `lease_expira_em` JÁ VENCIDO — o dono anterior sumiu de verdade;
--   • NUNCA reclamável quando `status='enviada'` (ou `pulada_*`) — essa é a
--     cerca contra o envio duplicado — nem quando `processando` com lease
--     AINDA VIVO: outro worker pode estar no meio do envio agora, e reclamar
--     aqui seria a mesma linha sendo mandada duas vezes;
--   • ao reclamar: `lease_token`/`lease_expira_em` novos, `tentativas+1`,
--     `corpo` fresco (o texto de "faltam N alunos" pode ter mudado desde a
--     tentativa morta), `last_error` limpo;
--   • `criado_em` NUNCA muda no reclaim — `dia_referencia` é GERADA a partir
--     dele, e mexer nela moveria a própria chave de dedupe pra outro dia.
-- Quando o WHERE do DO UPDATE não bate (linha não está numa situação segura
-- pra reclamar), o Postgres não insere nem atualiza nada e a cláusula
-- RETURNING não devolve linha — o `if v_id is null` de cada função continua
-- valendo, com o mesmo motivo de antes.

-- ───────────────────────────────────────────────────────────────────────────
-- 1. O destinatário aprende 'coordenacao'
-- ───────────────────────────────────────────────────────────────────────────
alter table public.fabio_notificacoes
  drop constraint if exists fabio_notificacoes_destinatario_tipo_check;
alter table public.fabio_notificacoes
  add constraint fabio_notificacoes_destinatario_tipo_check
  check (destinatario_tipo = any (array['professor','comercial','coordenacao']));

alter table public.fabio_notificacoes
  drop constraint if exists chk_notificacao_destinatario;
alter table public.fabio_notificacoes
  add constraint chk_notificacao_destinatario
  check (
       (status = 'pulada_sem_destinatario' and destinatario_tipo = 'comercial'
        and professor_id is null and destinatario_whatsapp is null)
    or (destinatario_tipo = 'professor'   and professor_id is not null)
    or (destinatario_tipo = 'comercial'   and destinatario_whatsapp is not null)
    or (destinatario_tipo = 'coordenacao' and professor_id is null
        and destinatario_whatsapp is not null)
  );

-- ───────────────────────────────────────────────────────────────────────────
-- 2. Duas chaves, dois índices
-- ───────────────────────────────────────────────────────────────────────────
drop index if exists public.fabio_notificacoes_feedback_dia_unico;

create unique index if not exists fabio_notificacoes_feedback_prof_dia_unico
  on public.fabio_notificacoes (professor_id, tipo, dia_referencia)
  where tipo = any (array['feedback_lembrete','feedback_reforco']);

-- `destinatario_whatsapp` entrou na chave na revisão de 09/08: hoje só existe
-- UM grupo de coordenação, então (tipo, dia_referencia) e (tipo,
-- dia_referencia, destinatario_whatsapp) dedupam igual. No dia em que um
-- segundo grupo existir (por unidade, por exemplo), a chave de 2 colunas
-- trataria os dois GRUPOS DIFERENTES como o mesmo destinatário — o segundo JID
-- do dia bateria em `ja_entregue_hoje` e nunca receberia nada.
-- `drop` explícito porque este índice JÁ EXISTE em produção (076 aplicada em
-- 09/08 com a definição antiga): `create ... if not exists` casa por NOME —
-- sem o drop, a definição nova nunca substitui a antiga.
drop index if exists public.fabio_notificacoes_feedback_coord_dia_unico;
create unique index if not exists fabio_notificacoes_feedback_coord_dia_unico
  on public.fabio_notificacoes (tipo, dia_referencia, destinatario_whatsapp)
  where tipo = 'feedback_coordenacao';

-- ───────────────────────────────────────────────────────────────────────────
-- 3. QUEM COBRAR HOJE — leitura pura, sem escrever nada
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.fn_feedback_cobranca_do_dia(
  p_dia date default null
) returns jsonb
language plpgsql stable security definer set search_path to 'public'
as $$
declare
  v_dia    date := coalesce(p_dia, public.fn_hoje_brt());
  v_ultimo date := (date_trunc('month', v_dia) + interval '1 month - 1 day')::date;
  v_fase   text;
  v_comp   date;
  v_profs  jsonb;
  v_eleg   int;
begin
  -- Ancorado no FIM DO MÊS, nunca em dia da semana: em agosto/2026 a janela é
  -- 25/08 (ter) a 31/08 (seg), então "a quinta" cai no 27 e "a segunda" no 31 —
  -- o reforço chegaria quatro dias antes do lembrete.
  if extract(day from v_dia) = 1 then
    v_fase := 'coordenacao';
    v_comp := (date_trunc('month', v_dia) - interval '1 month')::date;
  elsif v_dia = v_ultimo - 6 then
    v_fase := 'lembrete';
    v_comp := public.fn_competencia_feedback(v_dia);
  elsif v_dia = v_ultimo - 3 then
    v_fase := 'reforco';
    v_comp := public.fn_competencia_feedback(v_dia);
  else
    return jsonb_build_object('dia', v_dia, 'fase', 'nenhuma', 'competencia', null,
                              'elegiveis', 0, 'professores', '[]'::jsonb);
  end if;

  with alvo as (
    select p.id   as professor_id,
           p.nome as professor_nome,
           count(distinct v.aluno_id) as total,
           count(distinct f.aluno_id) filter (
             where f.feedback is not null and f.pratica_em_casa is not null
               and f.evolucao is not null and f.animo is not null) as ok,
           array_agg(distinct v.unidade_nome)
             filter (where v.unidade_nome is not null) as unidades
      from public.professores p
      join public.vw_jornada_professor_atual v on v.professor_id = p.id
      join public.alunos a on a.id = v.aluno_id and a.arquivado_em is null
      left join public.aluno_feedback_professor f
             on f.professor_id = p.id and f.aluno_id = v.aluno_id
            and f.competencia  = v_comp
     -- `usuario_id is not null` é o mesmo recorte do resto do worker: cobrar
     -- quem não consegue abrir a tela é o jeito mais rápido de ensinar o
     -- professor a ignorar o Fábio.
     where p.ativo and p.usuario_id is not null
     group by p.id, p.nome
    having count(distinct v.aluno_id) > 0
  )
  -- `elegiveis` conta TODO professor com carteira; `professores` traz só quem
  -- será cobrado. O FILTER separa os dois na mesma varredura — sem ele, a
  -- mensagem da coordenação teria que chamar a função duas vezes pra saber a
  -- régua, e a segunda chamada devolveria a lista filtrada de novo.
  select count(*)::int,
         coalesce(
           jsonb_agg(jsonb_build_object(
             'professor_id', professor_id,
             'nome',         professor_nome,
             'total',        total,
             'ok',           ok,
             'faltam',       total - ok,
             'unidades',     to_jsonb(coalesce(unidades, array[]::text[]))
           ) order by professor_nome)
           -- lembrete vai pra todo mundo; reforço e coordenação só pra quem
           -- não fechou.
           filter (where v_fase = 'lembrete' or ok < total),
         '[]'::jsonb)
    into v_eleg, v_profs
    from alvo;

  return jsonb_build_object('dia', v_dia, 'fase', v_fase, 'competencia', v_comp,
                            'elegiveis', v_eleg, 'professores', v_profs);
end $$;

-- ───────────────────────────────────────────────────────────────────────────
-- 4. RESERVA — professor
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.fn_reservar_cobranca_feedback(
  p_professor_id int,
  p_tipo         text,
  p_corpo        text,
  p_dia          date default null
) returns jsonb
language plpgsql volatile security definer set search_path to 'public'
as $$
declare
  v_dia       date        := coalesce(p_dia, public.fn_hoje_brt());
  -- `dia_referencia` é GERADA a partir de criado_em. Em produção (p_dia nulo,
  -- v_dia = hoje de verdade) grava o INSTANTE real — é o que faz qualquer
  -- leitura de `enviada_em - criado_em`, na tabela compartilhada, medir tempo
  -- de fila de verdade em vez de sempre bater em meia-noite. Só quando v_dia é
  -- um dia SIMULADO (o teste passando p_dia explícito, diferente de hoje) é
  -- que criado_em precisa virar meia-noite BRT daquele dia, pra
  -- dia_referencia — a chave de dedupe — cair no dia certo.
  v_criado_em timestamptz := case when v_dia = public.fn_hoje_brt() then now()
                                   else (v_dia::timestamp) at time zone 'America/Sao_Paulo' end;
  v_id        uuid;
  v_token     uuid;
  v_ativo     boolean;
  v_telefone  text;
begin
  if p_tipo <> all (array['feedback_lembrete','feedback_reforco']) then
    raise exception 'tipo_invalido';
  end if;
  if p_corpo is null or length(btrim(p_corpo)) < 3 then
    raise exception 'corpo_vazio';
  end if;

  select p.ativo,
         nullif(regexp_replace(coalesce(p.telefone_whatsapp,''), '\D', '', 'g'), '')
    into v_ativo, v_telefone
    from public.professores p
   where p.id = p_professor_id;

  if v_ativo is null then
    raise exception 'professor_inexistente';
  end if;
  if not v_ativo then
    return jsonb_build_object('reservado', false, 'motivo', 'professor_inativo');
  end if;
  if v_telefone is null then
    return jsonb_build_object('reservado', false, 'motivo', 'sem_whatsapp');
  end if;
  -- Férias é a única coisa que barra governança — silêncio e domingo não.
  if not public.fn_fabio_pode_notificar(p_professor_id, 'governanca', now()) then
    return jsonb_build_object('reservado', false, 'motivo', 'professor_em_pausa');
  end if;

  v_token := gen_random_uuid();

  insert into public.fabio_notificacoes
    (professor_id, tipo, categoria, canal, titulo, corpo, destinatario_tipo,
     status, tentativas, lease_token, lease_expira_em, criado_em)
  values
    (p_professor_id, p_tipo, 'governanca', 'whatsapp',
     'Feedback dos alunos', btrim(p_corpo), 'professor',
     'processando', 1, v_token, now() + interval '10 minutes', v_criado_em)
  on conflict (professor_id, tipo, dia_referencia)
    where tipo = any (array['feedback_lembrete','feedback_reforco'])
  -- reclamo (professor): dono anterior falhou, ou lease vencido de verdade.
  do update set
    status          = 'processando',
    tentativas      = fabio_notificacoes.tentativas + 1,
    corpo           = excluded.corpo,
    lease_token     = excluded.lease_token,
    lease_expira_em = excluded.lease_expira_em,
    last_error      = null
  where
    fabio_notificacoes.status = 'falhou'
    or (fabio_notificacoes.status = 'processando'
        and fabio_notificacoes.lease_expira_em < now())
  returning id into v_id;

  if v_id is null then
    return jsonb_build_object('reservado', false, 'motivo', 'ja_cobrado_hoje');
  end if;

  return jsonb_build_object('reservado', true, 'notificacao_id', v_id,
                            'lease_token', v_token, 'telefone', v_telefone);
end $$;

-- ───────────────────────────────────────────────────────────────────────────
-- 5. RESERVA — coordenação (uma linha por dia, pro grupo)
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.fn_reservar_cobranca_feedback_coordenacao(
  p_corpo    text,
  p_whatsapp text,
  p_dia      date default null
) returns jsonb
language plpgsql volatile security definer set search_path to 'public'
as $$
declare
  v_dia       date        := coalesce(p_dia, public.fn_hoje_brt());
  v_criado_em timestamptz := case when v_dia = public.fn_hoje_brt() then now()
                                   else (v_dia::timestamp) at time zone 'America/Sao_Paulo' end;
  v_id        uuid;
  v_token     uuid;
begin
  if p_corpo is null or length(btrim(p_corpo)) < 3 then
    raise exception 'corpo_vazio';
  end if;
  if p_whatsapp is null or length(btrim(p_whatsapp)) < 5 then
    raise exception 'destinatario_vazio';
  end if;

  v_token := gen_random_uuid();

  -- professor_id fica NULO de propósito: quem recebe é o grupo. É o quarto ramo
  -- do chk_notificacao_destinatario, criado acima.
  insert into public.fabio_notificacoes
    (tipo, categoria, canal, titulo, corpo, destinatario_tipo,
     destinatario_whatsapp, status, tentativas, lease_token, lease_expira_em,
     criado_em)
  values
    ('feedback_coordenacao', 'governanca', 'whatsapp',
     'Feedback do mês — quem não fechou', btrim(p_corpo), 'coordenacao',
     btrim(p_whatsapp), 'processando', 1, v_token,
     now() + interval '10 minutes', v_criado_em)
  on conflict (tipo, dia_referencia, destinatario_whatsapp)
    where tipo = 'feedback_coordenacao'
  -- reclamo (coordenacao): mesma regra do professor, ver cabecalho.
  do update set
    status          = 'processando',
    tentativas      = fabio_notificacoes.tentativas + 1,
    corpo           = excluded.corpo,
    lease_token     = excluded.lease_token,
    lease_expira_em = excluded.lease_expira_em,
    last_error      = null
  where
    fabio_notificacoes.status = 'falhou'
    or (fabio_notificacoes.status = 'processando'
        and fabio_notificacoes.lease_expira_em < now())
  returning id into v_id;

  if v_id is null then
    return jsonb_build_object('reservado', false, 'motivo', 'ja_entregue_hoje');
  end if;

  return jsonb_build_object('reservado', true, 'notificacao_id', v_id,
                            'lease_token', v_token);
end $$;

-- ───────────────────────────────────────────────────────────────────────────
-- 6. O depósito sem coletor sai de cena
-- ───────────────────────────────────────────────────────────────────────────
drop function if exists public.fn_enfileirar_cobranca_feedback(date);

-- ───────────────────────────────────────────────────────────────────────────
-- 7. Nenhuma das três é do navegador.
-- `revoke ... from anon` sozinho NÃO fecha função nova: o pg_default_acl de
-- `public` concede a anon e authenticated, e o Postgres concede ao PUBLIC.
-- ───────────────────────────────────────────────────────────────────────────
revoke all on function public.fn_feedback_cobranca_do_dia(date)
  from public, anon, authenticated;
revoke all on function public.fn_reservar_cobranca_feedback(int, text, text, date)
  from public, anon, authenticated;
revoke all on function public.fn_reservar_cobranca_feedback_coordenacao(text, text, date)
  from public, anon, authenticated;

comment on function public.fn_feedback_cobranca_do_dia(date) is
  'Leitura pura: diz a fase do dia (lembrete/reforco/coordenacao/nenhuma) e '
  'quem cobrar, ancorado no fim do mes. Nao escreve nada. So service_role.';
comment on function public.fn_reservar_cobranca_feedback(int, text, text, date) is
  'Reserva a cobranca do feedback de UM professor (processando + lease) antes '
  'do envio, com volta: falhou ou lease morto pode ser reclamado, enviada e '
  'lease vivo nunca. Respeita ferias via fn_fabio_pode_notificar. So service_role.';
comment on function public.fn_reservar_cobranca_feedback_coordenacao(text, text, date) is
  'Reserva a entrega do dia 1o pro GRUPO da coordenacao: professor_id nulo, '
  'destinatario_tipo coordenacao, JID em destinatario_whatsapp, com a mesma '
  'volta da reserva do professor. So service_role.';
