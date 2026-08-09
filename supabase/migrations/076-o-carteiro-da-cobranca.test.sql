-- Teste da 076. Roda dentro de BEGIN/ROLLBACK do rodar-teste-sql.mjs.
create temporary table _res(caso text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_prof   int;
  v_prof2  int;
  v_antes  jsonb;
  v_r      jsonb;
  v_r2     jsonb;
  v_r3     jsonb;
  v_r4     jsonb;
  v_mes    date;
  v_ultimo date;
  v_lemb   date;
  v_ref    date;
  v_i      int;
begin
  -- ── A régua, nos 12 meses do ano ────────────────────────────────────────
  -- O defeito que isto pega: âncora em dia da semana faz o reforço chegar
  -- ANTES do lembrete em todo mês que não termina em domingo.
  for v_i in 1..12 loop
    v_mes    := make_date(2026, v_i, 1);
    v_ultimo := (date_trunc('month', v_mes) + interval '1 month - 1 day')::date;
    v_lemb   := v_ultimo - 6;
    v_ref    := v_ultimo - 3;

    insert into _res values (
      format('regua %s: lembrete antes do reforco', to_char(v_mes,'MM')),
      v_lemb < v_ref,
      format('lembrete %s, reforco %s', v_lemb, v_ref));

    insert into _res values (
      format('regua %s: fase do lembrete', to_char(v_mes,'MM')),
      (public.fn_feedback_cobranca_do_dia(v_lemb) ->> 'fase') = 'lembrete',
      public.fn_feedback_cobranca_do_dia(v_lemb) ->> 'fase');

    insert into _res values (
      format('regua %s: fase do reforco', to_char(v_mes,'MM')),
      (public.fn_feedback_cobranca_do_dia(v_ref) ->> 'fase') = 'reforco',
      public.fn_feedback_cobranca_do_dia(v_ref) ->> 'fase');

    insert into _res values (
      format('regua %s: dia 1 e coordenacao do mes anterior', to_char(v_mes,'MM')),
      (public.fn_feedback_cobranca_do_dia(v_mes) ->> 'fase') = 'coordenacao'
        and (public.fn_feedback_cobranca_do_dia(v_mes) ->> 'competencia')::date
            = (v_mes - interval '1 month')::date,
      public.fn_feedback_cobranca_do_dia(v_mes) ->> 'competencia');

    -- Um dia fora das três âncoras não dispara nada.
    insert into _res values (
      format('regua %s: dia neutro nao dispara', to_char(v_mes,'MM')),
      (public.fn_feedback_cobranca_do_dia(v_ultimo - 10) ->> 'fase') = 'nenhuma',
      public.fn_feedback_cobranca_do_dia(v_ultimo - 10) ->> 'fase');
  end loop;

  -- ── O depósito sem coletor não existe mais ──────────────────────────────
  insert into _res values (
    'fn_enfileirar_cobranca_feedback foi removida',
    not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                 where n.nspname='public' and p.proname='fn_enfileirar_cobranca_feedback'),
    'ainda existe');

  -- ── O quarto ramo do CHECK, sem perder os três antigos ──────────────────
  -- `exists(...)`, não subquery escalar solta: uma subquery escalar sobre
  -- pg_constraint devolve NULL (não false) quando a constraint não bate — e
  -- `not ok` com ok NULL é NULL, que o `where not ok` da apuração final
  -- exclui em silêncio. Uma migration que derrubasse ou renomeasse o CHECK
  -- passaria aqui SEM registrar falha nenhuma. `exists` nunca é NULL: bate
  -- em true ou false, sempre um dos dois. (achado da revisão, 09/08)
  insert into _res values (
    'destinatario_tipo aceita coordenacao',
    exists (select 1 from pg_constraint
             where conrelid='public.fabio_notificacoes'::regclass
               and conname='fabio_notificacoes_destinatario_tipo_check'
               and pg_get_constraintdef(oid) like '%coordenacao%'),
    'check nao estendido ou nao existe');

  insert into _res values (
    'os tres ramos antigos continuam no chk_notificacao_destinatario',
    exists (select 1 from pg_constraint
             where conrelid='public.fabio_notificacoes'::regclass
               and conname='chk_notificacao_destinatario'
               and pg_get_constraintdef(oid) like '%pulada_sem_destinatario%'
               and pg_get_constraintdef(oid) like '%comercial%'
               and pg_get_constraintdef(oid) like '%professor%'),
    'ramo antigo perdido ou constraint nao existe');

  -- ── Reserva do professor ────────────────────────────────────────────────
  select id into v_prof from public.professores
   where ativo and usuario_id is not null
     and nullif(regexp_replace(coalesce(telefone_whatsapp,''),'\D','','g'),'') is not null
   order by id limit 1;

  if v_prof is null then
    insert into _res values ('reserva do professor', false,
      'nenhum professor ativo com whatsapp — teste nao pode rodar');
  else
    v_r := public.fn_reservar_cobranca_feedback(
             v_prof, 'feedback_lembrete', 'corpo de teste', date '2026-08-25');
    insert into _res values ('reserva grava processando + lease',
      (v_r->>'reservado')::boolean
        and exists (select 1 from public.fabio_notificacoes
                     where id = (v_r->>'notificacao_id')::uuid
                       and status='processando' and lease_token is not null
                       and destinatario_tipo='professor'
                       and dia_referencia = date '2026-08-25'),
      v_r::text);

    -- Segunda chamada no MESMO dia, com lease AINDA VIVO, não cria linha nova
    -- nem reclama a existente — é também o caso que prova que um lease vivo
    -- nunca é reclamável (mutante V8 mexe exatamente nesta cerca).
    v_r2 := public.fn_reservar_cobranca_feedback(
              v_prof, 'feedback_lembrete', 'corpo de teste', date '2026-08-25');
    insert into _res values ('dedupe do professor no mesmo dia (lease vivo nao reclama)',
      not (v_r2->>'reservado')::boolean and v_r2->>'motivo' = 'ja_cobrado_hoje',
      v_r2::text);

    -- Conclusão exige o lease certo.
    insert into _res values ('concluir com token errado nao fecha',
      not public.fabio_marcar_notificacao_enviada(
            (v_r->>'notificacao_id')::uuid, gen_random_uuid(), 'recibo'),
      'fechou com token errado');
    insert into _res values ('concluir com o lease certo fecha',
      public.fabio_marcar_notificacao_enviada(
        (v_r->>'notificacao_id')::uuid, (v_r->>'lease_token')::uuid, 'recibo'),
      'nao fechou com o token certo');

    -- Tipo fora do vocabulário é erro, não linha silenciosa.
    begin
      perform public.fn_reservar_cobranca_feedback(
                v_prof, 'feedback_coordenacao', 'corpo', date '2026-08-25');
      insert into _res values ('tipo invalido barrado', false, 'aceitou tipo errado');
    exception when others then
      insert into _res values ('tipo invalido barrado', sqlerrm like '%tipo_invalido%', sqlerrm);
    end;

    -- ── RESERVA tem volta (revisão 09/08) ─────────────────────────────────
    -- Linha nova, tipo/dia diferentes da de cima pra não colidir com a que
    -- já está 'enviada'. A cadeia: processando fresco → lease morto (worker
    -- caiu) → reclamado com token novo → marcado enviada → tentativa de
    -- reclamar de novo (bloqueada) → marcado falhou → reclamado de novo.
    v_r := public.fn_reservar_cobranca_feedback(
             v_prof, 'feedback_reforco', 'corpo original', date '2026-08-28');

    -- Simula o worker morrendo entre a RESERVA e o envio: lease no passado.
    update public.fabio_notificacoes
       set lease_expira_em = now() - interval '1 minute'
     where id = (v_r->>'notificacao_id')::uuid;

    v_r2 := public.fn_reservar_cobranca_feedback(
              v_prof, 'feedback_reforco', 'corpo depois do worker cair', date '2026-08-28');
    insert into _res values ('processando com lease morto pode ser reclamado',
      (v_r2->>'reservado')::boolean
        and (v_r2->>'notificacao_id') = (v_r->>'notificacao_id')
        and (v_r2->>'lease_token') is distinct from (v_r->>'lease_token'),
      format('r1=%s  r2=%s', v_r::text, v_r2::text));

    -- 'enviada' é a cerca: nem lease morto reclama uma linha já entregue.
    update public.fabio_notificacoes
       set status = 'enviada', enviada_em = now()
     where id = (v_r2->>'notificacao_id')::uuid;

    v_r3 := public.fn_reservar_cobranca_feedback(
              v_prof, 'feedback_reforco', 'corpo depois de enviada', date '2026-08-28');
    insert into _res values ('enviada nao pode ser reclamada',
      not (v_r3->>'reservado')::boolean and v_r3->>'motivo' = 'ja_cobrado_hoje',
      v_r3::text);

    -- 'falhou' pode ser reclamado — é o caso do envio que deu erro.
    update public.fabio_notificacoes
       set status = 'falhou'
     where id = (v_r2->>'notificacao_id')::uuid;

    v_r4 := public.fn_reservar_cobranca_feedback(
              v_prof, 'feedback_reforco', 'corpo apos falha', date '2026-08-28');
    insert into _res values ('falhou pode ser reclamado',
      (v_r4->>'reservado')::boolean
        and (v_r4->>'notificacao_id') = (v_r2->>'notificacao_id')
        and (v_r4->>'lease_token') is distinct from (v_r2->>'lease_token'),
      v_r4::text);
  end if;

  -- ── "X de Y fecharam" só é verdade se `elegiveis` contar quem fechou ────
  -- Mede ANTES, planta um professor que fechou o mês inteiro, mede DEPOIS.
  -- Comparar contra número fixo dependeria de a tabela estar vazia; assim a
  -- prova vale mesmo depois que a coleta real começar.
  v_antes := public.fn_feedback_cobranca_do_dia(date '2026-09-01');

  -- O pivô PRECISA vir da própria lista "antes": escolher por "menor
  -- carteira" arriscava sortear alguém que já tivesse fechado 100% (delta
  -- viraria 0, não -1, e o teste ficaria vermelho à toa quando a coleta real
  -- de agosto chegasse). Escolhendo de dentro de v_antes->'professores' ele
  -- está garantidamente na lista antes de eu fechar a carteira dele.
  -- (achado da revisão, 09/08)
  select (e->>'professor_id')::int into v_prof2
    from jsonb_array_elements(v_antes->'professores') e
   limit 1;

  if v_prof2 is null then
    insert into _res values ('quem fechou sai da lista', false,
      'nenhum professor pendente em 01/09 — teste nao pode rodar');
  else
    -- A carteira tem grão de matrícula/disciplina: o mesmo aluno aparece duas
    -- vezes quando faz dois cursos com o mesmo professor. Sem o `distinct`, o
    -- insert estoura na chave única. `origem` marcado — mesma prática da
    -- 075 — pra uma linha plantada em teste nunca se confundir com dado real
    -- se algum dia vazar de um BEGIN/ROLLBACK que não deu rollback.
    insert into public.aluno_feedback_professor
      (professor_id, aluno_id, unidade_id, competencia, feedback, pratica_em_casa,
       evolucao, animo, origem)
    select distinct v.professor_id, v.aluno_id, v.unidade_id, date '2026-08-01',
           'verde', 'sim', 'evoluindo', 'animado', 'teste_mutante_076'
      from public.vw_jornada_professor_atual v
      join public.alunos a on a.id = v.aluno_id and a.arquivado_em is null
     where v.professor_id = v_prof2
    on conflict do nothing;

    v_r := public.fn_feedback_cobranca_do_dia(date '2026-09-01');

    insert into _res values ('quem fechou sai da lista da coordenacao',
      not exists (select 1 from jsonb_array_elements(v_r->'professores') e
                   where (e->>'professor_id')::int = v_prof2)
      and jsonb_array_length(v_r->'professores')
          = jsonb_array_length(v_antes->'professores') - 1,
      format('antes=%s depois=%s',
             jsonb_array_length(v_antes->'professores'),
             jsonb_array_length(v_r->'professores')));

    insert into _res values ('mas continua contando em elegiveis',
      (v_r->>'elegiveis')::int = (v_antes->>'elegiveis')::int
        and (v_r->>'elegiveis')::int > jsonb_array_length(v_r->'professores'),
      format('elegiveis antes=%s depois=%s lista=%s',
             v_antes->>'elegiveis', v_r->>'elegiveis',
             jsonb_array_length(v_r->'professores')));

    -- E no LEMBRETE ele volta: a primeira cobrança vai pra todo mundo.
    insert into _res values ('lembrete cobra ate quem ja fechou',
      exists (select 1
                from jsonb_array_elements(
                       public.fn_feedback_cobranca_do_dia(date '2026-08-25')->'professores') e
               where (e->>'professor_id')::int = v_prof2),
      'sumiu do lembrete');
  end if;

  -- ── Reserva da coordenação ──────────────────────────────────────────────
  v_r := public.fn_reservar_cobranca_feedback_coordenacao(
           'lista de teste', '120363304349910605@g.us', date '2026-09-01');
  insert into _res values ('coordenacao grava no grupo, sem professor',
    (v_r->>'reservado')::boolean
      and exists (select 1 from public.fabio_notificacoes
                   where id = (v_r->>'notificacao_id')::uuid
                     and destinatario_tipo = 'coordenacao'
                     and professor_id is null
                     and destinatario_whatsapp = '120363304349910605@g.us'
                     and status = 'processando'),
    v_r::text);

  v_r2 := public.fn_reservar_cobranca_feedback_coordenacao(
            'lista de teste', '120363304349910605@g.us', date '2026-09-01');
  insert into _res values ('dedupe da coordenacao no mesmo dia',
    not (v_r2->>'reservado')::boolean and v_r2->>'motivo' = 'ja_entregue_hoje',
    v_r2::text);

  -- ── Portas fechadas — e a que TEM que ficar aberta ──────────────────────
  -- Presença é afirmação, não ausência: provar que anon/authenticated estão
  -- de fora não prova que o chamador de verdade (service_role, via
  -- fabio_notification_worker.py) ainda consegue entrar. 018 documenta essa
  -- exata armadilha neste repo — um `drop function` antes do `create` leva
  -- os grants junto, e a suíte continuava verde porque só checava quem
  -- devia estar FORA, nunca quem devia estar DENTRO. (achado da revisão, 09/08)
  insert into _res values ('anon nao executa as tres',
    not has_function_privilege('anon','public.fn_feedback_cobranca_do_dia(date)','execute')
    and not has_function_privilege('anon','public.fn_reservar_cobranca_feedback(int,text,text,date)','execute')
    and not has_function_privilege('anon','public.fn_reservar_cobranca_feedback_coordenacao(text,text,date)','execute'),
    'anon executa alguma');
  insert into _res values ('authenticated nao executa as tres',
    not has_function_privilege('authenticated','public.fn_feedback_cobranca_do_dia(date)','execute')
    and not has_function_privilege('authenticated','public.fn_reservar_cobranca_feedback(int,text,text,date)','execute')
    and not has_function_privilege('authenticated','public.fn_reservar_cobranca_feedback_coordenacao(text,text,date)','execute'),
    'authenticated executa alguma');
  insert into _res values ('service_role executa as tres',
    has_function_privilege('service_role','public.fn_feedback_cobranca_do_dia(date)','execute')
    and has_function_privilege('service_role','public.fn_reservar_cobranca_feedback(int,text,text,date)','execute')
    and has_function_privilege('service_role','public.fn_reservar_cobranca_feedback_coordenacao(text,text,date)','execute'),
    'service_role sem execute em alguma das tres');
end $$;

select json_build_object(
         'falhas', (select count(*) from _res where not ok),
         'detalhe', coalesce((select json_agg(json_build_object('caso', caso, 'detalhe', detalhe))
                                from _res where not ok), '[]'::json)
       ) as resumo;
