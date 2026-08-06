-- Teste da 038 — confirmar grava presenca E avisa, ou nao faz nem uma coisa
--
-- Alem do plano, dois blocos:
--   * permissao (anon nao executa) — revoke sem carrasco e convencao
--   * unidade SEM comercial: a confirmacao nao pode travar por isso, e o
--     rastro tem que ficar visivel. E o ponto onde a 036 e a 038 se encostam,
--     e nenhum dos dois testes sozinho cobria.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000000380', 'ZZTESTE unidade 038', 'ZZTESTE038'),
  ('00000000-0000-4000-8000-000000000381', 'ZZTESTE unidade 038 SEM comercial', 'ZZTESTE038B')
on conflict (id) do nothing;

insert into public.unidade_contato_comercial (unidade_id, nome, whatsapp)
values ('00000000-0000-4000-8000-000000000380', 'ZZTESTE Comercial 038', '5521900000038')
on conflict (unidade_id) do nothing;

-- Usuario ZZTESTE ligado ao professor: a app_confirmar resolve auth.uid(), e
-- o teste roda como service_role (auth.uid() nulo) — sem isto a RPC barra
-- corretamente com 'sem_professor_vinculado' e o teste nao exercita nada.
insert into public.usuarios (id, nome, email, auth_user_id) values
  (-38901, 'ZZTESTE Usuario 038', 'zzteste-038@exemplo.invalido',
   '00000000-0000-4000-8000-000000038901');
insert into public.professores (id, nome, usuario_id) values (-38001, 'ZZTESTE Professor 038', -38901);
insert into public.leads (id, unidade_id, whatsapp, status) values
  (-38001, '00000000-0000-4000-8000-000000000380', '5521999380001', 'novo');
insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id)
values (-38001, -38001, 'ZZTESTE Confirma', '00000000-0000-4000-8000-000000000380',
        current_date+1, '10:00', 'experimental_agendada', -38001);
insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, categoria, professor_id, cancelada)
values (-38001, -938001, '00000000-0000-4000-8000-000000000380', current_date+1,
   (current_date+1 + time '10:00') at time zone 'America/Sao_Paulo', 'experimental', -38001, false);
insert into public.lead_experimental_aulas (lead_experimental_id, aula_local_id, estado, casado_por)
values (-38001, -38001, 'vinculado', 'chave_natural');

create temp table _conf(resultado jsonb) on commit drop;

do $$
declare v_vinc bigint; v_reg uuid; v_out jsonb;
begin
  select id into v_vinc from lead_experimental_aulas where lead_experimental_id=-38001;
  select public.fn_registrar_experimental_interno(v_vinc, 'trabalhou ritmo', 'foi bem',
           'seguir', 'quente') into v_reg;
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000038901"}', true);
  select public.app_confirmar_registro_experimental(v_reg, null) into v_out;
  reset role;
  insert into _conf values (v_out);
end $$;

-- Le o retorno DA CHAMADA QUE CONFIRMOU, nao de uma nova
insert into _res select 'confirmacao gravou presenca', 'true',
  (select resultado->>'presenca_gravada' from _conf);
insert into _res select 'confirmacao reclamou o aviso (com lease)', 'true',
  (select resultado->>'aviso_claimed' from _conf);
-- ATENCAO: aqui havia um passo exigindo que o aviso nascesse com LEASE VIVO.
-- Era o defeito escrito como se fosse contrato — a confirmacao segurava o
-- lease de 10 min e o worker nao conseguia entregar. A 042 conserta, e o
-- carrasco do comportamento certo mora la
-- (042-confirmacao-enfileira-nao-segura.test.sql, passo "o worker CONSEGUE
-- reivindicar o aviso"). Este arquivo continua rodando contra o corpo da 038,
-- entao ele so nao pode afirmar o contrario do que vale hoje.
insert into _res select 'aviso da confirmacao entrou na fila', 'sim',
  coalesce((select case when n.lease_token is not null then 'sim' else 'nao' end
              from fabio_notificacoes n
             where n.referencia_tipo='lead_experimental_registro'
               and n.referencia_id = (select (resultado->>'registro_id') from _conf)), '(nenhum)');
insert into _res select 'o aviso foi pro numero do comercial da unidade', '5521900000038',
  coalesce((select n.destinatario_whatsapp from fabio_notificacoes n
             where n.referencia_tipo='lead_experimental_registro'
               and n.referencia_id = (select (resultado->>'registro_id') from _conf)), '(nenhum)');

insert into _res
select 'registro ficou confirmado', 'confirmado',
       (select r.status from lead_experimental_registros r
          join lead_experimental_aulas v on v.id=r.vinculo_id
         where v.lead_experimental_id=-38001);
insert into _res
select 'presenca nasceu de fonte FORTE', 'true',
       (select public.fn_presenca_e_forte(presenca_respondido_por)::text
          from lead_experimental_aulas where lead_experimental_id=-38001);
insert into _res
select 'a fonte gravada e do vocabulario do aluno', 'professor_la_teacher',
       (select presenca_respondido_por from lead_experimental_aulas where lead_experimental_id=-38001);
insert into _res
select 'presenca forte promoveu o estado', 'realizado',
       (select estado from lead_experimental_aulas where lead_experimental_id=-38001);

-- ── AUTORIZACAO: intruso NAO confirma registro alheio ──────────────────────
-- Confirmar nao e leitura: grava presenca de fonte FORTE, promove o estado do
-- vinculo e dispara aviso ao comercial. Precisa da mesma prova da 035 — provar
-- so que o dono consegue deixaria a porta aberta sem ninguem ver.
insert into public.usuarios (id, nome, email, auth_user_id) values
  (-38902, 'ZZTESTE Usuario Intruso 038', 'zzteste-intruso-038@exemplo.invalido',
   '00000000-0000-4000-8000-000000038902');
insert into public.professores (id, nome, usuario_id)
values (-38002, 'ZZTESTE Professor Intruso 038', -38902);

insert into public.leads (id, unidade_id, whatsapp, status) values
  (-38002, '00000000-0000-4000-8000-000000000380', '5521999380002', 'novo');
insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id)
values (-38002, -38002, 'ZZTESTE Alvo do Intruso', '00000000-0000-4000-8000-000000000380',
        current_date+1, '15:00', 'experimental_agendada', -38001);
insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, categoria, professor_id, cancelada)
values (-38002, -938002, '00000000-0000-4000-8000-000000000380', current_date+1,
   (current_date+1 + time '15:00') at time zone 'America/Sao_Paulo', 'experimental', -38001, false);
insert into public.lead_experimental_aulas (lead_experimental_id, aula_local_id, estado, casado_por)
values (-38002, -38002, 'vinculado', 'chave_natural');

do $$
declare v_vinc bigint; v_reg uuid;
begin
  select id into v_vinc from lead_experimental_aulas where lead_experimental_id=-38002;
  select public.fn_registrar_experimental_interno(v_vinc, 'aula do -38001','b','c','d')
    into v_reg;

  begin
    set local role authenticated;
    perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000038902"}', true);
    perform public.app_confirmar_registro_experimental(v_reg, null);
    reset role;
    insert into _res values ('intruso NAO confirma registro alheio', 'barrado',
      'CONFIRMOU — gravou presenca e disparou aviso de aula que nao e dele');
  exception when others then
    reset role;
    insert into _res values ('intruso NAO confirma registro alheio', 'barrado', 'barrado');
  end;
end $$;

insert into _res
select 'registro alheio segue nao confirmado', 'aguardando_confirmacao',
       (select r.status from lead_experimental_registros r
          join lead_experimental_aulas v on v.id=r.vinculo_id
         where v.lead_experimental_id=-38002);
insert into _res
select 'intruso nao gravou presenca no vinculo alheio', 'ausente',
       case when (select presenca_respondido_por from lead_experimental_aulas
                    where lead_experimental_id=-38002) is null
            then 'ausente' else 'GRAVOU' end;
insert into _res
select 'intruso nao disparou aviso ao comercial', '0',
       (select count(*)::text from fabio_notificacoes
         where referencia_tipo='lead_experimental_registro'
           and referencia_id=(select r.id::text from lead_experimental_registros r
                                join lead_experimental_aulas v on v.id=r.vinculo_id
                               where v.lead_experimental_id=-38002));

-- E o DONO confirma normalmente o mesmo registro (senao "barrar todo mundo"
-- passaria como se fosse autorizacao funcionando)
do $$
declare v_reg uuid;
begin
  select r.id into v_reg from lead_experimental_registros r
    join lead_experimental_aulas v on v.id=r.vinculo_id
   where v.lead_experimental_id=-38002;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000038901"}', true);
    perform public.app_confirmar_registro_experimental(v_reg, null);
    reset role;
    insert into _res values ('dono confirma o mesmo registro', 'ok', 'ok');
  exception when others then
    reset role;
    insert into _res values ('dono confirma o mesmo registro', 'ok', 'BARROU: '||sqlerrm);
  end;
end $$;

-- ── AULA ORFA: o buraco que a 035 expos, no caminho da confirmacao ────────
-- Aula com professor_id nulo EXISTE em producao. Com uma sessao tambem sem
-- professor, `null is distinct from null` da FALSE e a guarda de posse deixa
-- passar sozinha — quem segura e a exigencia de usuario resolvido, la em cima.
-- Sem este caso, o mutante que remove essa exigencia sobrevive: o teste do
-- intruso nao serve, porque o intruso TEM professor.
insert into public.usuarios (id, nome, email, auth_user_id) values
  (-38903, 'ZZTESTE Usuario Sem Professor', 'zzteste-orfao-038@exemplo.invalido',
   '00000000-0000-4000-8000-000000038903');
insert into public.leads (id, unidade_id, whatsapp, status) values
  (-38004, '00000000-0000-4000-8000-000000000380', '5521999380004', 'novo');
insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id)
values (-38004, -38004, 'ZZTESTE Aula Orfa', '00000000-0000-4000-8000-000000000380',
        current_date+1, '18:00', 'experimental_agendada', null);
insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, categoria, professor_id, cancelada)
values (-38004, -938004, '00000000-0000-4000-8000-000000000380', current_date+1,
   (current_date+1 + time '18:00') at time zone 'America/Sao_Paulo', 'experimental', null, false);
insert into public.lead_experimental_aulas (lead_experimental_id, aula_local_id, estado, casado_por)
values (-38004, -38004, 'vinculado', 'chave_natural');

do $$
declare v_vinc bigint; v_reg uuid;
begin
  select id into v_vinc from lead_experimental_aulas where lead_experimental_id=-38004;
  select public.fn_registrar_experimental_interno(v_vinc, 'orfa','b','c','d') into v_reg;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000038903"}', true);
    perform public.app_confirmar_registro_experimental(v_reg, null);
    reset role;
    insert into _res values ('sessao sem professor nao confirma aula orfa', 'barrado',
      'CONFIRMOU — null is distinct from null e false');
  exception when others then
    reset role;
    insert into _res values ('sessao sem professor nao confirma aula orfa', 'barrado', 'barrado');
  end;
end $$;

insert into _res
select 'aula orfa segue sem presenca gravada', 'ausente',
       case when (select presenca_respondido_por from lead_experimental_aulas
                    where lead_experimental_id=-38004) is null
            then 'ausente' else 'GRAVOU' end;
insert into _res
select 'aula orfa nao gerou aviso ao comercial', '0',
       (select count(*)::text from fabio_notificacoes
         where referencia_tipo='lead_experimental_registro'
           and referencia_id=(select r.id::text from lead_experimental_registros r
                                join lead_experimental_aulas v on v.id=r.vinculo_id
                               where v.lead_experimental_id=-38004));

-- ── Idempotencia: confirmar 2x nao duplica aviso ───────────────────────────
-- A nao-duplicacao do AVISO e estrutural (indice uq_fabio_notif_por_referencia,
-- da 036) — ela sobrevive mesmo sem o return antecipado daqui. O que o return
-- antecipado protege e o REGISTRO: sem ele, a segunda confirmacao reescreve
-- confirmado_em/confirmado_por e a hora real da confirmacao se perde.
-- confirmado_em NAO serve de sonda aqui: dentro de uma transacao now() e
-- constante, entao ele fica igual com ou sem o return antecipado. A sonda e
-- confirmado_por, com um valor DIFERENTE na segunda chamada — se o return
-- antecipado sumir, a autoria da confirmacao e reescrita pela repeticao.
create temp table _conf2(resultado jsonb) on commit drop;

do $$
declare v_reg uuid; v_out jsonb;
begin
  select r.id into v_reg from lead_experimental_registros r
    join lead_experimental_aulas v on v.id=r.vinculo_id
   where v.lead_experimental_id=-38001;
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000038901"}', true);
  select public.app_confirmar_registro_experimental(v_reg, -38001) into v_out;
  reset role;
  insert into _conf2 values (v_out);
end $$;

insert into _res
select 'a 2a confirmacao se declara repetida', 'true',
       (select coalesce(resultado->>'ja_confirmado', '(nao declarou)') from _conf2);

insert into _res
select 'confirmar 2x nao reescreve a autoria', 'nulo',
       coalesce((select r.confirmado_por::text from lead_experimental_registros r
                   join lead_experimental_aulas v on v.id=r.vinculo_id
                  where v.lead_experimental_id=-38001), 'nulo');

insert into _res
select 'confirmar 2x nao duplica aviso', '1',
       (select count(*)::text from fabio_notificacoes
         where referencia_tipo='lead_experimental_registro'
           and referencia_id=(select r.id::text from lead_experimental_registros r
                                join lead_experimental_aulas v on v.id=r.vinculo_id
                               where v.lead_experimental_id=-38001));

-- ── Unidade SEM comercial nao trava a confirmacao ─────────────────────────
-- Onde a 036 e a 038 se encostam. Se a falta de contato levantasse excecao, a
-- transacao inteira voltaria: o professor registraria a aula, apertaria
-- confirmar, e o trabalho dele sumiria por causa de um cadastro que nao e dele.
insert into public.leads (id, unidade_id, whatsapp, status) values
  (-38003, '00000000-0000-4000-8000-000000000381', '5521999380003', 'novo');
insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id)
values (-38003, -38003, 'ZZTESTE Sem Comercial', '00000000-0000-4000-8000-000000000381',
        current_date+1, '16:00', 'experimental_agendada', -38001);
insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, categoria, professor_id, cancelada)
values (-38003, -938003, '00000000-0000-4000-8000-000000000381', current_date+1,
   (current_date+1 + time '16:00') at time zone 'America/Sao_Paulo', 'experimental', -38001, false);
insert into public.lead_experimental_aulas (lead_experimental_id, aula_local_id, estado, casado_por)
values (-38003, -38003, 'vinculado', 'chave_natural');

create temp table _conf_sem(resultado jsonb) on commit drop;

do $$
declare v_vinc bigint; v_reg uuid; v_out jsonb;
begin
  select id into v_vinc from lead_experimental_aulas where lead_experimental_id=-38003;
  select public.fn_registrar_experimental_interno(v_vinc, 'x','y','z','w') into v_reg;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000038901"}', true);
    select public.app_confirmar_registro_experimental(v_reg, null) into v_out;
    reset role;
    insert into _conf_sem values (v_out);
  exception when others then
    reset role;
    insert into _conf_sem values (jsonb_build_object('EXPLODIU', sqlerrm));
  end;
end $$;

insert into _res select 'sem comercial, a confirmacao NAO explode', 'confirmou',
  (select case when resultado ? 'EXPLODIU' then 'EXPLODIU: '||(resultado->>'EXPLODIU')
               else 'confirmou' end from _conf_sem);
insert into _res select 'sem comercial, o aviso nao foi reclamado', 'false',
  (select coalesce(resultado->>'aviso_claimed', '(nulo)') from _conf_sem);
insert into _res select 'sem comercial, o motivo fica explicito', 'sem_destinatario',
  (select coalesce(resultado->>'aviso_motivo', '(nulo)') from _conf_sem);
insert into _res select 'sem comercial, a presenca foi gravada assim mesmo', 'true',
  (select coalesce(resultado->>'presenca_gravada', '(nulo)') from _conf_sem);
insert into _res select 'sem comercial, o rastro fica VISIVEL na fila', 'pulada_sem_destinatario',
  coalesce((select n.status from fabio_notificacoes n
             where n.referencia_tipo='lead_experimental_registro'
               and n.referencia_id = (select (resultado->>'registro_id') from _conf_sem)), '(nenhum)');

-- ── Permissao ─────────────────────────────────────────────────────────────
insert into _res select 'anon nao confirma registro', 'sem privilegio',
  case when has_function_privilege('anon',
         'public.app_confirmar_registro_experimental(uuid,integer)','execute')
       then 'EXECUTA — confirma sem estar logado' else 'sem privilegio' end;
insert into _res select 'authenticated confirma (e a tela do professor)', 'executa',
  case when has_function_privilege('authenticated',
         'public.app_confirmar_registro_experimental(uuid,integer)','execute')
       then 'executa' else 'NAO EXECUTA — o professor nao consegue confirmar' end;

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
