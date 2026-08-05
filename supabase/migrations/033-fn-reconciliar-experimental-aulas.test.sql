-- Teste da 033 — o reconciliador liga o lead a aula CERTA, ou fica na fila
--
-- Cada lead prova UM comportamento; nenhum e prontuario real (ZZTESTE).

create temp table _res(passo text, esperado text, obtido text) on commit drop;

insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000000330', 'ZZTESTE unidade 033',  'ZZTESTE033'),
  ('00000000-0000-4000-8000-000000000331', 'ZZTESTE unidade 033b', 'ZZTESTE033B')
on conflict (id) do nothing;

insert into public.professores (id, nome) values (-33001, 'ZZTESTE Professor Multi-Unidade');

insert into public.leads (id, unidade_id, whatsapp, status) values
  (-33001, '00000000-0000-4000-8000-000000000330', '5521999330001', 'novo'), -- casa exato
  (-33002, '00000000-0000-4000-8000-000000000330', '5521999330002', 'novo'), -- sem par
  (-33003, '00000000-0000-4000-8000-000000000330', '5521999330003', 'novo'), -- 180min deslocado
  (-33004, '00000000-0000-4000-8000-000000000331', '5521999330004', 'novo'); -- so nao casa se filtrar unidade

insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id)
values
  (-33001, -33001, 'ZZTESTE Casa Exato',    '00000000-0000-4000-8000-000000000330', current_date+2, '10:00', 'experimental_agendada', -33001),
  (-33002, -33002, 'ZZTESTE Sem Par',       '00000000-0000-4000-8000-000000000330', current_date+2, '15:00', 'experimental_agendada', -33001),
  (-33003, -33003, 'ZZTESTE Deslocado',     '00000000-0000-4000-8000-000000000330', current_date+2, '13:00', 'experimental_agendada', -33001),
  (-33004, -33004, 'ZZTESTE Outra Unidade', '00000000-0000-4000-8000-000000000331', current_date+2, '10:00', 'experimental_agendada', -33001);

insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, categoria, professor_id, cancelada)
values
  -- casa exato com o lead -33001 (10:00 SP, unidade 330)
  (-33001, -933001, '00000000-0000-4000-8000-000000000330', current_date+2,
   (current_date+2 + time '10:00') at time zone 'America/Sao_Paulo', 'experimental', -33001, false),
  -- 180min de diferenca do lead -33003 (que pede 13:00) — NAO deve casar
  (-33002, -933002, '00000000-0000-4000-8000-000000000330', current_date+2,
   (current_date+2 + time '16:00') at time zone 'America/Sao_Paulo', 'experimental', -33001, false);
-- Nao existe NENHUMA aula na unidade 331: e o "-33001, 10:00, unidade 330"
-- acima que serve de ISCA — mesmo professor, MESMO horario, unidade errada.
-- Se o lead -33004 (unidade 331) casar com ela, a chave natural nao esta
-- filtrando unidade.

select public.fn_reconciliar_experimental_aulas(30, 500);

-- ── Casa exato ───────────────────────────────────────────────────────────
insert into _res
select 'casa exato: vinculado', 'vinculado',
       coalesce((select estado from lead_experimental_aulas
                  where lead_experimental_id=-33001 and substituido_em is null), '(nenhum)');

-- ── Sem par vira pendente/sem_par, nao erro silencioso ─────────────────────
insert into _res
select 'sem par -> pendente/sem_par', 'pendente/sem_par',
       coalesce((select estado||'/'||motivo_pendencia from lead_experimental_aulas
                  where lead_experimental_id=-33002 and substituido_em is null), '(nenhum)');

-- ── Tolerancia ZERO: 180min de diferenca NAO casa ──────────────────────────
insert into _res
select 'deslocado 180min -> pendente (nao casa errado)', 'pendente/sem_par',
       coalesce((select estado||'/'||motivo_pendencia from lead_experimental_aulas
                  where lead_experimental_id=-33003 and substituido_em is null), '(nenhum)');

-- ── Chave natural exige unidade: -33004 NAO pode casar com a isca ──────────
insert into _res
select 'unidade errada nao casa com a isca', 'pendente/sem_par',
       coalesce((select estado||'/'||motivo_pendencia from lead_experimental_aulas
                  where lead_experimental_id=-33004 and substituido_em is null), '(nenhum)');

-- E a isca continua exclusiva do lead -33001 (ninguem mais a ocupa)
insert into _res
select 'aula-isca continua so do lead -33001', '1',
       (select count(*)::text from lead_experimental_aulas
         where aula_local_id=-33001 and substituido_em is null and estado <> 'cancelado');

-- ── Idempotencia: rodar de novo nao duplica nem muda o ja vinculado ────────
select public.fn_reconciliar_experimental_aulas(30, 500);
insert into _res
select 'idempotente: 1 linha vigente apos 2 rodadas', '1',
       (select count(*)::text from lead_experimental_aulas
         where lead_experimental_id=-33001 and substituido_em is null);

-- ── Estado 'manual' sobrevive a nova rodada MESMO que o status mude ────────
-- Nao basta rodar de novo sem mudar nada: o teste real e o status do lead
-- virar 'cancelada' (que, pra qualquer outro estado, rebaixaria pra
-- 'cancelado' com cancelado_em preenchido). 'manual' tem que ignorar isso
-- por completo — nem o estado nem cancelado_em podem mudar.
update lead_experimental_aulas set estado='manual', casado_por='manual'
 where lead_experimental_id=-33002 and substituido_em is null;
update public.lead_experimentais set status='cancelada' where id=-33002;
select public.fn_reconciliar_experimental_aulas(30, 500);
insert into _res
select 'manual sobrevive mesmo com lead cancelado', 'manual',
       (select estado from lead_experimental_aulas
         where lead_experimental_id=-33002 and substituido_em is null);
insert into _res
select 'manual nao ganha cancelado_em por sincronizacao', 'ausente',
       case when (select cancelado_em from lead_experimental_aulas
                    where lead_experimental_id=-33002 and substituido_em is null) is null
            then 'ausente' else 'PREENCHIDO — atropelou decisao humana' end;

-- ── Sincronizacao de estado: status muda pra experimental_faltou ──────────
update public.lead_experimentais set status='experimental_faltou' where id=-33001;
select public.fn_reconciliar_experimental_aulas(30, 500);
insert into _res
select 'faltou sincroniza estado', 'faltou',
       (select estado from lead_experimental_aulas
         where lead_experimental_id=-33001 and substituido_em is null);
insert into _res
select 'faltou mantem aula_local_id (nao desvincula)', 'presente',
       case when (select aula_local_id from lead_experimental_aulas
                    where lead_experimental_id=-33001 and substituido_em is null) is not null
            then 'presente' else 'sumiu' end;

-- ── Sincronizacao: cancelar DEPOIS de realizado nao regride o estado ───────
update public.lead_experimentais set status='experimental_realizada' where id=-33002;
delete from lead_experimental_aulas where lead_experimental_id=-33002 and estado='manual';
insert into public.lead_experimental_aulas (lead_experimental_id, aula_local_id, estado, casado_por)
values (-33002, -33002, 'realizado', 'chave_natural');
update public.lead_experimentais set status='cancelada' where id=-33002;
select public.fn_reconciliar_experimental_aulas(30, 500);
insert into _res
select 'cancelar apos realizado nao regride estado', 'realizado',
       (select estado from lead_experimental_aulas
         where lead_experimental_id=-33002 and substituido_em is null);
insert into _res
select 'cancelar apos realizado registra cancelado_em', 'presente',
       case when (select cancelado_em from lead_experimental_aulas
                    where lead_experimental_id=-33002 and substituido_em is null) is not null
            then 'presente' else 'ausente' end;

-- ── Contrato 3: aluno_id na PROPRIA lead_experimentais dispara o recibo ────
insert into public.alunos (id, nome, unidade_id)
values (-33001, 'ZZTESTE Aluno Convertido', '00000000-0000-4000-8000-000000000330');
update public.lead_experimentais set aluno_id = -33001, status='convertido' where id=-33001;
select public.fn_reconciliar_experimental_aulas(30, 500);
insert into _res
select 'matricula com recibo: aluno_id gravado', '-33001',
       coalesce((select aluno_id::text from lead_experimental_aulas
                  where lead_experimental_id=-33001 and substituido_em is null), '(nulo)');
insert into _res
select 'matricula com recibo: quem/como gravado', 'reconciliador:emusys_sync',
       coalesce((select aluno_vinculado_por from lead_experimental_aulas
                  where lead_experimental_id=-33001 and substituido_em is null), '(nulo)');

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
