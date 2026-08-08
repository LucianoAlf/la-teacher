-- Teste da 061 — a experimental remarcada volta a ter ficha
--
-- Cinco leads, todos com aula livre esperando no espelho, diferindo APENAS no
-- estado do vínculo e no status do lead. Sem essa simetria o teste não separa
-- "ressuscitou" de "reconciliou como sempre reconciliou".
--
--   A  cancelado + lead agendado                → RESSUSCITA (defeito 1)
--   B  realizado  + lead agendado               → não toca (a aula aconteceu)
--   C  faltou     + lead agendado               → não toca (a família faltou)
--   D  cancelado  + lead cancelado              → não toca (não remarcou nada)
--   E  cancelado  + lead agendado + presença forte → não toca (quem estava na
--                                                     sala decidiu)
--   F  pendente disputando aula já ocupada      → vira 'ambiguo' (defeito 3)
--
-- B, C, D e E são o que impede a correção de virar um "descancela tudo". E é
-- o mais fácil de perder de vista: o vínculo está cancelado, o lead voltou,
-- e mesmo assim alguém já registrou presença de fonte forte ali.
--
-- O passo "a rodada não teve erro" é o que pega o defeito 2 (`v_vinculo :=
-- null` deixando o record não atribuído): sem ele, A "falha calada" — o
-- `exception when others` do laço desfaz a subtransação inteira e o vínculo
-- volta a aparecer cancelado, sem que nada acuse o porquê.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000000610', 'ZZTESTE unidade 061', 'ZZTESTE061')
on conflict (id) do nothing;

insert into public.professores (id, nome, telefone_whatsapp, ativo) values
  (-61001, 'ZZTESTE Prof 061', '5521991110611', true);

insert into public.leads (id, unidade_id, whatsapp, status)
select v.id, '00000000-0000-4000-8000-000000000610', '5521991116' || abs(v.id) % 1000, 'novo'
  from (values (-61001),(-61002),(-61003),(-61004),(-61005),(-61006),(-61007)) as v(id);

-- Amanhã, cinco horários distintos: cada lead com o SEU par, sem disputa.
insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id)
values
  (-61001, -61001, 'ZZTESTE A remarcou',      '00000000-0000-4000-8000-000000000610',
   (now() at time zone 'America/Sao_Paulo')::date + 1, '08:00', 'experimental_agendada', -61001),
  (-61002, -61002, 'ZZTESTE B ja aconteceu',  '00000000-0000-4000-8000-000000000610',
   (now() at time zone 'America/Sao_Paulo')::date + 1, '09:00', 'experimental_agendada', -61001),
  (-61003, -61003, 'ZZTESTE C faltou',        '00000000-0000-4000-8000-000000000610',
   (now() at time zone 'America/Sao_Paulo')::date + 1, '10:00', 'experimental_agendada', -61001),
  (-61004, -61004, 'ZZTESTE D segue cancelada','00000000-0000-4000-8000-000000000610',
   (now() at time zone 'America/Sao_Paulo')::date + 1, '11:00', 'cancelada', -61001),
  (-61005, -61005, 'ZZTESTE E tem presenca',  '00000000-0000-4000-8000-000000000610',
   (now() at time zone 'America/Sao_Paulo')::date + 1, '12:00', 'experimental_agendada', -61001),
  -- F: dois leads pro MESMO aluno no MESMO horário — é o que a remarcação
  -- duplicada produz na vida real. Um leva a aula; o outro tem que virar
  -- 'ambiguo', não "+1 erro" invisível.
  (-61006, -61006, 'ZZTESTE F dono da aula',  '00000000-0000-4000-8000-000000000610',
   (now() at time zone 'America/Sao_Paulo')::date + 1, '13:00', 'experimental_agendada', -61001),
  (-61007, -61007, 'ZZTESTE F duplicata',     '00000000-0000-4000-8000-000000000610',
   (now() at time zone 'America/Sao_Paulo')::date + 1, '13:00', 'experimental_agendada', -61001);

-- As cinco aulas no espelho: livres, categoria certa, hora exata.
insert into public.aulas_emusys
  (id, emusys_id, unidade_id, professor_id, data_aula, data_hora_inicio, categoria, cancelada)
select v.id, abs(v.id), '00000000-0000-4000-8000-000000000610', -61001,
       (now() at time zone 'America/Sao_Paulo')::date + 1,
       (((now() at time zone 'America/Sao_Paulo')::date + 1) + v.hora) at time zone 'America/Sao_Paulo',
       'experimental', false
  from (values (-61001,'08:00'::time),(-61002,'09:00'),(-61003,'10:00'),
               (-61004,'11:00'),(-61005,'12:00'),(-61006,'13:00')) as v(id, hora);
-- Só UMA aula às 13:00 pros dois leads F: é a disputa.

-- Os vínculos, todos VIGENTES e todos sem aula (é o estado real dos presos:
-- o cancelado da produção tinha aula_local_id nulo).
insert into public.lead_experimental_aulas
  (id, lead_experimental_id, estado, cancelado_em, presenca_respondido_por)
values
  (-61001, -61001, 'cancelado', now(), null),
  (-61002, -61002, 'realizado', null,  null),
  (-61003, -61003, 'faltou',    null,  null),
  (-61004, -61004, 'cancelado', now(), null),
  (-61005, -61005, 'cancelado', now(), 'professor_la_teacher'),
  -- F: um já é dono da aula; o outro chega pendente e vai bater no índice.
  (-61006, -61006, 'vinculado', null, null),
  (-61007, -61007, 'pendente',  null, null);

update public.lead_experimental_aulas set aula_local_id = -61006 where id = -61006;

create temp table _rodada(j jsonb) on commit drop;
insert into _rodada select public.fn_reconciliar_experimental_aulas(7, 500);

-- A rodada não pode ter engolido erro: o corpo do laço tem
-- `exception when others` que conta e segue, então uma falha no ramo novo
-- apareceria aqui e em lugar nenhum mais.
insert into _res select 'a rodada nao teve erro', '0', (select j ->> 'erros' from _rodada);

-- ------------------------------------------------------------------
-- A: o defeito. Sem a 061 este é o único passo que falha.
insert into _res select 'A) cancelado + lead agendado volta a ter ficha', 'vinculado',
  (select v.estado from public.lead_experimental_aulas v
    where v.lead_experimental_id = -61001 and v.substituido_em is null);

insert into _res select 'A) e a ficha aponta pra aula certa', '-61001',
  (select v.aula_local_id::text from public.lead_experimental_aulas v
    where v.lead_experimental_id = -61001 and v.substituido_em is null);

-- O histórico não some: a linha cancelada continua lá, fora de vigência.
insert into _res select 'A) o cancelado vira historico, nao lixo', '1',
  (select count(*)::text from public.lead_experimental_aulas v
    where v.lead_experimental_id = -61001 and v.substituido_em is not null
      and v.estado = 'cancelado');

-- B, C: o que aconteceu na sala é intocável.
insert into _res select 'B) realizado continua realizado', 'realizado',
  (select v.estado from public.lead_experimental_aulas v
    where v.lead_experimental_id = -61002 and v.substituido_em is null);

insert into _res select 'C) faltou continua faltou', 'faltou',
  (select v.estado from public.lead_experimental_aulas v
    where v.lead_experimental_id = -61003 and v.substituido_em is null);

-- D: sem remarcação não há ressurreição.
insert into _res select 'D) lead ainda cancelado nao ressuscita', 'cancelado',
  (select v.estado from public.lead_experimental_aulas v
    where v.lead_experimental_id = -61004 and v.substituido_em is null);

insert into _res select 'D) e nao ganha aula nenhuma', 'NULO',
  (select coalesce(v.aula_local_id::text,'NULO') from public.lead_experimental_aulas v
    where v.lead_experimental_id = -61004 and v.substituido_em is null);

-- E: presença forte é decisão de quem estava presente.
insert into _res select 'E) presenca forte barra a ressurreicao', 'cancelado',
  (select v.estado from public.lead_experimental_aulas v
    where v.lead_experimental_id = -61005 and v.substituido_em is null);

insert into _res select 'E) e a presenca continua registrada', 'professor_la_teacher',
  (select v.presenca_respondido_por from public.lead_experimental_aulas v
    where v.lead_experimental_id = -61005 and v.substituido_em is null);

-- F: aula ocupada vira ambiguidade com nome, não erro engolido.
insert into _res select 'F) o dono da aula continua dono', 'vinculado',
  (select v.estado from public.lead_experimental_aulas v
    where v.lead_experimental_id = -61006 and v.substituido_em is null);

insert into _res select 'F) a duplicata vira ambiguo, nao erro', 'pendente/ambiguo',
  (select v.estado || '/' || coalesce(v.motivo_pendencia,'SEM MOTIVO')
     from public.lead_experimental_aulas v
    where v.lead_experimental_id = -61007 and v.substituido_em is null);

insert into _res select 'F) e a duplicata nao rouba a aula', 'NULO',
  (select coalesce(v.aula_local_id::text,'NULO') from public.lead_experimental_aulas v
    where v.lead_experimental_id = -61007 and v.substituido_em is null);

-- Nenhum dos sete pode ter gerado linha vigente duplicada.
insert into _res select 'nenhum lead fica com duas linhas vigentes', '0',
  (select count(*)::text from (
     select lead_experimental_id from public.lead_experimental_aulas
      where lead_experimental_id in (-61001,-61002,-61003,-61004,-61005,-61006,-61007)
        and substituido_em is null
      group by 1 having count(*) > 1) t);

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
