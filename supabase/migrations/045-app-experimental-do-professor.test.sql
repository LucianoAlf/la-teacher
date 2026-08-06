-- Teste da 045 — o professor ve a SUA experimental, e so o que e dele ver
--
-- Duas familias de passo:
--   posse  — intruso e sessao orfa nao chegam no dado
--   fronteira — o sinal comercial nao atravessa, o pedagogico atravessa
--
-- O de posse importa mais aqui do que nas migrations de escrita: esta RPC
-- devolve NOME DE LEAD. Uma falha de leitura nao estraga dado nenhum — so
-- entrega a base de leads da escola pra quem pediu.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000000450', 'ZZTESTE unidade 045', 'ZZTESTE045')
on conflict (id) do nothing;

insert into public.usuarios (id, nome, email, auth_user_id) values
  (-45901, 'ZZTESTE Dono 045',    'zz-dono-045@exemplo.invalido',    '00000000-0000-4000-8000-000000045901'),
  (-45902, 'ZZTESTE Intruso 045', 'zz-intruso-045@exemplo.invalido', '00000000-0000-4000-8000-000000045902'),
  (-45903, 'ZZTESTE Orfao 045',   'zz-orfao-045@exemplo.invalido',   '00000000-0000-4000-8000-000000045903');
insert into public.professores (id, nome, usuario_id) values
  (-45001, 'ZZTESTE Professor Dono 045',    -45901),
  (-45002, 'ZZTESTE Professor Intruso 045', -45902);

insert into public.leads (id, unidade_id, whatsapp, status) values
  (-45001, '00000000-0000-4000-8000-000000000450', '5521999450001', 'novo'),
  (-45002, '00000000-0000-4000-8000-000000000450', '5521999450002', 'novo');

-- contexto_ia com TODAS as chaves que existem em producao, inclusive as que
-- nao podem atravessar. Fixture que so tem o permitido nao testa fronteira.
insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id, contexto_ia)
values
  (-45001, -45001, 'ZZTESTE Helena 045', '00000000-0000-4000-8000-000000000450',
   date '2026-08-06', '16:00', 'experimental_agendada', -45001,
   jsonb_build_object(
     'recepcao', jsonb_build_object('aluno','ZZTESTE Helena','responsavel','ZZTESTE Mae',
                                    'data_nascimento','2015-03-10'),
     'quem_e_esse_aluno', jsonb_build_object('historia','GOSTA DE CANTAR EM CASA',
                                             'nivel_declarado','iniciante'),
     'ganchos_de_conexao', jsonb_build_array('GOSTA DE POP','CANTA NO CHUVEIRO'),
     'para_a_devolutiva', jsonb_build_object(
        'o_que_a_familia_espera','GANHAR CONFIANCA',
        'atencao_conversao','quente',
        'porque','MAE PERGUNTOU PRECO 3X'),
     'como_conduzir','DEIXE ELA ESCOLHER A MUSICA')),
  (-45002, -45002, 'ZZTESTE Aula Orfa 045', '00000000-0000-4000-8000-000000000450',
   date '2026-08-06', '18:00', 'experimental_agendada', null, null);

insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, categoria,
   curso_nome, professor_id, cancelada)
values
  (-45001, -945001, '00000000-0000-4000-8000-000000000450', date '2026-08-06',
   (date '2026-08-06' + time '16:00') at time zone 'America/Sao_Paulo', 'experimental',
   'ZZTESTE Canto', -45001, false),
  -- aula SEM professor: existe em producao
  (-45002, -945002, '00000000-0000-4000-8000-000000000450', date '2026-08-06',
   (date '2026-08-06' + time '18:00') at time zone 'America/Sao_Paulo', 'experimental',
   'ZZTESTE Canto', null, false);

insert into public.lead_experimental_aulas
  (lead_experimental_id, aula_local_id, estado, casado_por,
   presenca_status, presenca_respondido_por)
values (-45001, -45001, 'vinculado', 'chave_natural', 'presente', 'professor_la_teacher'),
       (-45002, -45002, 'vinculado', 'chave_natural', null, null);

create temp table _v(quem text, id bigint) on commit drop;
insert into _v select 'dono', id from lead_experimental_aulas where lead_experimental_id=-45001;
insert into _v select 'orfa', id from lead_experimental_aulas where lead_experimental_id=-45002;

create temp table _r(quem text, j jsonb) on commit drop;

do $$
declare v_out jsonb; v_id bigint;
begin
  -- O id sai da tabela temp ANTES de trocar de papel: `authenticated` nao tem
  -- privilegio em tabela temp da sessao, e o erro aparecia dentro da RPC como
  -- se fosse defeito dela.
  select id into v_id from _v where quem='dono';
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000045901"}',true);
  select public.app_experimental_do_professor(v_id) into v_out;
  reset role;
  insert into _r values ('dono', v_out);
end $$;

-- ── O professor ve a aula dele ────────────────────────────────────────────
insert into _res select 'devolve o nome do aluno', 'ZZTESTE Helena 045',
  (select coalesce(j->>'nome_aluno','(nulo)') from _r where quem='dono');
insert into _res select 'devolve a hora em BRT', '16:00',
  (select coalesce(j->>'hora','(nulo)') from _r where quem='dono');
insert into _res select 'devolve a unidade', 'ZZTESTE unidade 045',
  (select coalesce(j->>'unidade_nome','(nulo)') from _r where quem='dono');
insert into _res select 'devolve o curso', 'ZZTESTE Canto',
  (select coalesce(j->>'curso','(nulo)') from _r where quem='dono');
insert into _res select 'marca a presenca como forte', 'true',
  (select coalesce(j->>'presenca_e_forte','(nulo)') from _r where quem='dono');

-- ── O pedagogico atravessa ────────────────────────────────────────────────
insert into _res select 'a historia do aluno chega', 'GOSTA DE CANTAR EM CASA',
  (select coalesce(j->'contexto'->'quem_e_esse_aluno'->>'historia','(nulo)')
     from _r where quem='dono');
insert into _res select 'os ganchos de conexao chegam', '2',
  (select coalesce(jsonb_array_length(j->'contexto'->'ganchos_de_conexao')::text,'(nulo)')
     from _r where quem='dono');
insert into _res select 'o que a familia espera chega', 'GANHAR CONFIANCA',
  (select coalesce(j->'contexto'->'para_a_devolutiva'->>'o_que_a_familia_espera','(nulo)')
     from _r where quem='dono');
insert into _res select 'a dica de conducao chega', 'DEIXE ELA ESCOLHER A MUSICA',
  (select coalesce(j->>'como_conduzir','(nulo)') from _r where quem='dono');

-- ── O comercial NAO atravessa ─────────────────────────────────────────────
-- O professor conduz melhor sabendo que ela canta no chuveiro. Nao conduz
-- melhor sabendo que a mae ja perguntou o preco — conduz diferente.
insert into _res select 'o sinal de conversao NAO chega ao professor', 'ausente',
  (select case when (j->'contexto'->'para_a_devolutiva') ? 'atencao_conversao'
               then 'CHEGOU — a aula vira venda' else 'ausente' end
     from _r where quem='dono');
insert into _res select 'e o PORQUE do sinal muito menos', 'ausente',
  (select case when j::text like '%MAE PERGUNTOU PRECO 3X%'
               then 'VAZOU O PRECO' else 'ausente' end
     from _r where quem='dono');
insert into _res select 'nem por outro caminho no JSON inteiro', 'ausente',
  (select case when j::text like '%quente%' then 'VAZOU' else 'ausente' end
     from _r where quem='dono');

-- ── POSSE: quem nao e dono nao chega no dado ──────────────────────────────
do $$
declare v_id bigint;
begin
  select id into v_id from _v where quem='dono';
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000045902"}',true);
    perform public.app_experimental_do_professor(v_id);
    reset role;
    insert into _res values ('intruso NAO le experimental alheia', 'barrado',
      'LEU — nome de lead entregue a quem nao e o professor');
  exception when others then
    reset role;
    insert into _res values ('intruso NAO le experimental alheia', 'barrado', 'barrado');
  end;
end $$;

-- Aula orfa (professor_id nulo) + sessao sem professor: `null = null` e NULL,
-- nao TRUE, entao o join nao casa. O mesmo caso que abriu buraco na 035 e na
-- 038 — aqui o teste existe desde o comeco.
do $$
declare v_id bigint;
begin
  select id into v_id from _v where quem='orfa';
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000045903"}',true);
    perform public.app_experimental_do_professor(v_id);
    reset role;
    insert into _res values ('sessao sem professor NAO le aula orfa', 'barrado',
      'LEU — null casando com null');
  exception when others then
    reset role;
    insert into _res values ('sessao sem professor NAO le aula orfa', 'barrado', 'barrado');
  end;
end $$;

-- E o dono continua lendo (senao "barrar todos" passaria por autorizacao)
do $$
declare v_out jsonb; v_id bigint;
begin
  select id into v_id from _v where quem='dono';
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000045901"}',true);
    select public.app_experimental_do_professor(v_id) into v_out;
    reset role;
    insert into _res values ('o dono continua lendo a dele', 'ok',
      case when v_out ? 'nome_aluno' then 'ok' else 'VEIO VAZIO' end);
  exception when others then
    reset role;
    insert into _res values ('o dono continua lendo a dele', 'ok', 'BARROU: '||sqlerrm);
  end;
end $$;

-- ── Registro em andamento volta pra tela ─────────────────────────────────
do $$
declare v_reg uuid; v_out jsonb; v_id bigint;
begin
  select id into v_id from _v where quem='dono';
  select public.fn_registrar_experimental_interno(
    v_id, 'RASCUNHO PEDAGOGICO','b','c','d') into v_reg;
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000045901"}',true);
  select public.app_experimental_do_professor(v_id) into v_out;
  reset role;
  insert into _r values ('com_registro', v_out);
end $$;

insert into _res select 'o registro em andamento volta pra tela', 'RASCUNHO PEDAGOGICO',
  (select coalesce(j->'registro'->>'anotacao_pedagogica','(nulo)') from _r where quem='com_registro');
insert into _res select 'com o status dele', 'aguardando_confirmacao',
  (select coalesce(j->'registro'->>'status','(nulo)') from _r where quem='com_registro');
insert into _res select 'antes de registrar, o bloco vem nulo', 'nulo',
  (select case when (j->'registro') is null or j->>'registro' is null then 'nulo'
               else 'PREENCHIDO' end from _r where quem='dono');

-- Registrar de novo descarta o anterior (indice uq_lead_exp_registro_vigente).
-- A tela tem que reabrir o VIGENTE — se ela pegar o descartado, o professor
-- revisa e confirma um texto que ele proprio ja tinha substituido.
do $$
declare v_reg uuid; v_out jsonb; v_id bigint;
begin
  select id into v_id from _v where quem='dono';
  select public.fn_registrar_experimental_interno(
    v_id, 'VERSAO NOVA DEPOIS DE REESCREVER','b2','c2','d2') into v_reg;
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000045901"}',true);
  select public.app_experimental_do_professor(v_id) into v_out;
  reset role;
  insert into _r values ('reescrito', v_out);
end $$;

insert into _res select 'a tela reabre o registro VIGENTE, nao o descartado',
  'VERSAO NOVA DEPOIS DE REESCREVER',
  (select coalesce(j->'registro'->>'anotacao_pedagogica','(nulo)') from _r where quem='reescrito');

-- ── Permissao ─────────────────────────────────────────────────────────────
insert into _res select 'anon nao le experimental', 'sem privilegio',
  case when has_function_privilege('anon','public.app_experimental_do_professor(bigint)','execute')
       then 'LE — base de leads exposta' else 'sem privilegio' end;
insert into _res select 'authenticated le (e a tela do professor)', 'executa',
  case when has_function_privilege('authenticated','public.app_experimental_do_professor(bigint)','execute')
       then 'executa' else 'NAO EXECUTA — a tela nao abre' end;

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
