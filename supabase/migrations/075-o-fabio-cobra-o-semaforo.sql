-- 075 — o Fábio cobra o semáforo
--
-- POR QUE: coleta sem cobrança já foi testada na prática e deu ZERO resposta.
-- O Alf: "falta de tempo, falta de hábito, falta de governança e cobrança".
-- A escada é a mesma da cobrança de presença (066): lembrete, reforço, e a
-- coordenação no fim.
--
-- OS DISPAROS SÃO ANCORADOS NO FIM DO MÊS, NÃO EM DIA DA SEMANA.
-- A primeira versão deste plano usava "a segunda da janela" e "a quinta da
-- janela". É verdade que toda janela de 7 dias tem exatamente uma de cada — mas
-- a ORDEM inverte. Em agosto/2026 a janela é 25/08 (ter) a 31/08 (seg): a
-- quinta cai no dia 27 e a segunda no dia 31, então o "reforço" chegaria quatro
-- dias ANTES do lembrete, e o lembrete no último dia do mês. Quebra em todo mês
-- que não termina em domingo. Ancorado no fim do mês, a ordem e o espaçamento
-- são os mesmos sempre: lembrete no 1º dia da janela, reforço três dias depois,
-- sobrando três dias para o professor agir.
--
-- A FORMA REAL DE public.fabio_notificacoes (medida no banco e em 066/068/043/
-- 036/018 — o plano original supunha `(professor_id, tipo, dia_referencia,
-- mensagem)`, que não existe):
--   • não há coluna `mensagem` — é `corpo` (not null). `titulo` existe e é
--     opcional; fica null aqui, igual ao fabio_claim_aviso_comercial da 036.
--   • `dia_referencia` é GERADA (`(criado_em at time zone 'America/Sao_Paulo')
--     ::date`) — não pode aparecer na lista de colunas do INSERT (Postgres
--     recusa valor explícito em coluna gerada). Para o índice de dedupe bater
--     no DIA SIMULADO (v_dia) — e não no dia real do relógio, que é o que os
--     testes desta função precisam simular —, `criado_em` é escrito
--     explicitamente como a meia-noite de v_dia em America/Sao_Paulo. Em
--     produção (cron chamando com p_dia null) isso não muda nada: v_dia já É
--     hoje, então midnight-de-hoje e "agora" caem no mesmo dia BRT.
--   • `status` não tem default (068) e o CHECK não aceita 'pendente' (066): a
--     linha nasce já em 'processando', com lease_token/lease_expira_em/
--     tentativas — mesmo formato de fabio_claim_notificacao (018) e
--     fabio_claim_aviso_comercial (036). O envio (worker que lê e manda pelo
--     WhatsApp) não é escopo desta task; a linha fica no formato que o resto
--     da fila já usa, inclusive reivindicável se o lease vencer sem ninguém
--     concluir.
--   • `categoria` e `canal` têm CHECK fechado: 'governanca' (mesma categoria
--     de pendencia_registro em 066 — isto é cobrança, não aviso informativo)
--     e 'whatsapp' (mesmo canal de tudo que fala com o professor).
--   • `tipo` tem CHECK fechado numa lista de valores. 'feedback_lembrete',
--     'feedback_reforco' e 'feedback_coordenacao' não estavam nela — vocabulário
--     ESTENDIDO, não substituído, mesma tática de 018 e 036.
--   • `f.feedback` (o "coração") é coluna real de aluno_feedback_professor —
--     isso o plano original já acertou; confirmado contra
--     app_professor_feedback_progresso, que usa exatamente
--     `feedback is not null and pratica_em_casa is not null and evolucao is
--     not null and animo is not null` como "respondido". Este arquivo espelha
--     essa mesma regra.

alter table public.fabio_notificacoes
  drop constraint if exists fabio_notificacoes_tipo_check;
alter table public.fabio_notificacoes
  add constraint fabio_notificacoes_tipo_check
  check (tipo = any (array[
    'briefing_matinal','pendencia_registro','experimental_nova','reagendamento',
    'outro','devolutiva_pronta','devolutiva_destinatario','experimental_registrada',
    'experimental_falta',
    'feedback_lembrete','feedback_reforco','feedback_coordenacao'
  ]));

create or replace function public.fn_enfileirar_cobranca_feedback(
  p_dia date default null
) returns jsonb
language plpgsql security definer set search_path to 'public'
as $$
declare
  v_dia       date        := coalesce(p_dia, public.fn_hoje_brt());
  v_comp      date        := public.fn_competencia_feedback(v_dia);
  v_ultimo    date        := (date_trunc('month', v_dia) + interval '1 month - 1 day')::date;
  -- Ancora a coluna GERADA dia_referencia (derivada de criado_em) no dia
  -- SIMULADO v_dia, não no relógio real da sessão — ver nota no cabeçalho.
  v_criado_em timestamptz := (v_dia::timestamp) at time zone 'America/Sao_Paulo';
  v_fase      text;
  v_n         int  := 0;
begin
  -- Dia 1º: a competência que interessa é a do mês que ACABOU.
  if extract(day from v_dia) = 1 then
    v_fase := 'coordenacao';
    v_comp := (date_trunc('month', v_dia) - interval '1 month')::date;
  elsif v_dia = v_ultimo - 6 then   -- primeiro dia da janela
    v_fase := 'lembrete';
  elsif v_dia = v_ultimo - 3 then   -- três dias depois, sempre depois
    v_fase := 'reforco';
  else
    return jsonb_build_object('fase', 'nenhuma', 'enfileirados', 0);
  end if;

  with alvo as (
    select p.id as professor_id,
           count(distinct v.aluno_id) as total,
           count(distinct f.aluno_id) filter (
             where f.feedback is not null and f.pratica_em_casa is not null
               and f.evolucao is not null and f.animo is not null) as ok
      from public.professores p
      join public.vw_jornada_professor_atual v on v.professor_id = p.id
      join public.alunos a on a.id = v.aluno_id and a.arquivado_em is null
      left join public.aluno_feedback_professor f
             on f.professor_id = p.id and f.aluno_id = v.aluno_id
            and f.competencia  = v_comp
     group by p.id
    having count(distinct v.aluno_id) > 0
  ),
  pendentes as (
    -- 'lembrete' vai pra todo mundo; 'reforco' e 'coordenacao' só pra quem
    -- não fechou. Cobrar quem já fez é o jeito mais rápido de ensinar o
    -- professor a ignorar o Fábio.
    select * from alvo
     where v_fase = 'lembrete' or ok < total
  ),
  gravados as (
    insert into public.fabio_notificacoes
      (professor_id, tipo, categoria, canal, corpo, destinatario_tipo,
       status, tentativas, lease_token, lease_expira_em, criado_em)
    select pe.professor_id,
           'feedback_' || v_fase,
           'governanca',
           'whatsapp',
           case v_fase
             when 'lembrete' then
               'Semana de feedback dos alunos. Você já respondeu ' || pe.ok ||
               ' de ' || pe.total || '. É com isso que a coordenação chega antes ' ||
               'da evasão — e tem aluno perto da renovação.'
             when 'reforco' then
               'Faltam ' || (pe.total - pe.ok) || ' alunos no seu feedback do mês. ' ||
               'Dá pra fechar em poucos minutos pelo app.'
             else
               'Fechou o mês com ' || pe.ok || ' de ' || pe.total || ' alunos ' ||
               'respondidos no feedback.'
           end,
           'professor',
           'processando', 1, gen_random_uuid(), now() + interval '10 minutes', v_criado_em
      from pendentes pe
    on conflict do nothing
    returning 1
  )
  select count(*) into v_n from gravados;

  return jsonb_build_object('fase', v_fase, 'competencia', v_comp, 'enfileirados', v_n);
end $$;

revoke all on function public.fn_enfileirar_cobranca_feedback(date) from public, anon, authenticated;

-- Índice único que sustenta o `on conflict do nothing`. Índice e ON CONFLICT
-- são UM contrato: quem mexe num mexe no outro.
create unique index if not exists fabio_notificacoes_feedback_dia_unico
  on public.fabio_notificacoes (professor_id, tipo, dia_referencia)
  where tipo like 'feedback_%';

comment on function public.fn_enfileirar_cobranca_feedback(date) is
  'Enfileira a cobranca do feedback mensal em fabio_notificacoes: lembrete no '
  '1o dia da janela dos ultimos 7 dias do mes, reforco 3 dias depois so pra '
  'quem nao fechou, coordenacao no dia 1 olhando o mes que acabou. So '
  'enfileira (status processando + lease) — o envio por WhatsApp e outro '
  'pedaco, ainda nao agendado no cron. So service_role: revoke de '
  'public/anon/authenticated.';
