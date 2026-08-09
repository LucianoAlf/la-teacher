-- Teste da 076. Roda dentro de BEGIN/ROLLBACK do rodar-teste-sql.mjs.
create temporary table _res(caso text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_prof   int;
  v_prof2  int;
  v_antes  jsonb;
  v_r      jsonb;
  v_r2     jsonb;
  v_mes    date;
  v_ultimo date;
  v_fase   text;
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
  insert into _res values (
    'destinatario_tipo aceita coordenacao',
    (select pg_get_constraintdef(oid) like '%coordenacao%'
       from pg_constraint
      where conrelid='public.fabio_notificacoes'::regclass
        and conname='fabio_notificacoes_destinatario_tipo_check'),
    'check nao estendido');

  insert into _res values (
    'os tres ramos antigos continuam no chk_notificacao_destinatario',
    (select pg_get_constraintdef(oid) like '%pulada_sem_destinatario%'
        and pg_get_constraintdef(oid) like '%comercial%'
        and pg_get_constraintdef(oid) like '%professor%'
       from pg_constraint
      where conrelid='public.fabio_notificacoes'::regclass
        and conname='chk_notificacao_destinatario'),
    'ramo antigo perdido');

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

    -- Segunda chamada no MESMO dia não cria linha nova.
    v_r2 := public.fn_reservar_cobranca_feedback(
              v_prof, 'feedback_lembrete', 'corpo de teste', date '2026-08-25');
    insert into _res values ('dedupe do professor no mesmo dia',
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
  end if;

  -- ── "X de Y fecharam" só é verdade se `elegiveis` contar quem fechou ────
  -- Mede ANTES, planta um professor que fechou o mês inteiro, mede DEPOIS.
  -- Comparar contra número fixo dependeria de a tabela estar vazia; assim a
  -- prova vale mesmo depois que a coleta real começar.
  v_antes := public.fn_feedback_cobranca_do_dia(date '2026-09-01');

  select v.professor_id into v_prof2
    from public.vw_jornada_professor_atual v
    join public.professores p on p.id = v.professor_id
    join public.alunos a on a.id = v.aluno_id and a.arquivado_em is null
   where p.ativo and p.usuario_id is not null
   group by v.professor_id
   order by count(distinct v.aluno_id) asc, v.professor_id
   limit 1;

  if v_prof2 is null then
    insert into _res values ('quem fechou sai da lista', false,
      'nenhum professor com carteira — teste nao pode rodar');
  else
    -- A carteira tem grão de matrícula/disciplina: o mesmo aluno aparece duas
    -- vezes quando faz dois cursos com o mesmo professor. Sem o `distinct`, o
    -- insert estoura na chave única.
    insert into public.aluno_feedback_professor
      (professor_id, aluno_id, unidade_id, competencia, feedback, pratica_em_casa, evolucao, animo)
    select distinct v.professor_id, v.aluno_id, v.unidade_id, date '2026-08-01',
           'verde', 'sim', 'evoluindo', 'animado'
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

  -- ── Portas fechadas ─────────────────────────────────────────────────────
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
end $$;

select json_build_object(
         'falhas', (select count(*) from _res where not ok),
         'detalhe', coalesce((select json_agg(json_build_object('caso', caso, 'detalhe', detalhe))
                                from _res where not ok), '[]'::json)
       ) as resumo;
