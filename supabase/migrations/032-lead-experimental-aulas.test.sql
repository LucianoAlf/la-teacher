-- Teste da 032 — a tabela de vinculo faz o que os dois indices prometem
--
-- Nao testa a LOGICA do reconciliador (isso e a 033) — testa que a
-- ESTRUTURA (indices, CHECK) impede os estados invalidos por conta propria,
-- mesmo que um bug futuro no reconciliador tente escrever errado.
--
-- Cada passo usa lead/aula PROPRIOS quando testa um indice especifico, pra
-- uma falha nao poder vir do indice errado (ex.: testar "ocupacao" com um
-- lead que ja tem vigencia testaria os dois indices ao mesmo tempo, e um
-- unique_violation nao diz qual dos dois disparou).

create temp table _res(passo text, esperado text, obtido text) on commit drop;

insert into public.unidades (id, nome, codigo)
values ('00000000-0000-4000-8000-000000000320', 'ZZTESTE unidade 032', 'ZZTESTE032')
on conflict (id) do nothing;

insert into public.professores (id, nome) values (-32001, 'ZZTESTE Professor 032');

insert into public.leads (id, unidade_id, whatsapp, status) values
  (-32001, '00000000-0000-4000-8000-000000000320', '5521999320001', 'novo'),
  (-32002, '00000000-0000-4000-8000-000000000320', '5521999320002', 'novo'),
  (-32003, '00000000-0000-4000-8000-000000000320', '5521999320003', 'novo'),
  (-32004, '00000000-0000-4000-8000-000000000320', '5521999320004', 'novo'),
  (-32005, '00000000-0000-4000-8000-000000000320', '5521999320005', 'novo');

insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id)
values
  (-32001, -32001, 'ZZTESTE A (vigencia)',       '00000000-0000-4000-8000-000000000320', current_date+1, '10:00', 'experimental_agendada', -32001),
  (-32002, -32002, 'ZZTESTE B (ocupa realizado)','00000000-0000-4000-8000-000000000320', current_date+1, '11:00', 'experimental_agendada', -32001),
  (-32003, -32003, 'ZZTESTE C (tenta pegar)',    '00000000-0000-4000-8000-000000000320', current_date+1, '12:00', 'experimental_agendada', -32001),
  (-32004, -32004, 'ZZTESTE D (cancela antes)',  '00000000-0000-4000-8000-000000000320', current_date+1, '13:00', 'experimental_agendada', -32001),
  (-32005, -32005, 'ZZTESTE E (reaproveita)',    '00000000-0000-4000-8000-000000000320', current_date+1, '14:00', 'experimental_agendada', -32001);

insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, categoria, professor_id, cancelada)
values
  (-32001, -932001, '00000000-0000-4000-8000-000000000320', current_date+1,
   (current_date+1 + time '15:00') at time zone 'America/Sao_Paulo', 'experimental', -32001, false),
  (-32002, -932002, '00000000-0000-4000-8000-000000000320', current_date+1,
   (current_date+1 + time '16:00') at time zone 'America/Sao_Paulo', 'experimental', -32001, false),
  (-32003, -932003, '00000000-0000-4000-8000-000000000320', current_date+1,
   (current_date+1 + time '17:00') at time zone 'America/Sao_Paulo', 'experimental', -32001, false),
  (-32004, -932004, '00000000-0000-4000-8000-000000000320', current_date+1,
   (current_date+1 + time '18:00') at time zone 'America/Sao_Paulo', 'experimental', -32001, false),
  (-32005, -932005, '00000000-0000-4000-8000-000000000320', current_date+1,
   (current_date+1 + time '19:00') at time zone 'America/Sao_Paulo', 'experimental', -32001, false);

-- ── Passo 1: estado invalido e rejeitado pelo CHECK ─────────────────────────
do $$
begin
  begin
    insert into public.lead_experimental_aulas (lead_experimental_id, estado)
    values (-32001, 'inventado');
    insert into _res values ('estado invalido rejeitado', 'rejeitado', 'ACEITOU');
  exception when check_violation then
    insert into _res values ('estado invalido rejeitado', 'rejeitado', 'rejeitado');
  end;
end $$;

-- ── Passo 2: duas linhas vigentes pro MESMO lead — rejeitado ───────────────
insert into public.lead_experimental_aulas
  (lead_experimental_id, aula_local_id, estado, casado_por)
values (-32001, -32001, 'vinculado', 'chave_natural');

do $$
begin
  begin
    insert into public.lead_experimental_aulas
      (lead_experimental_id, aula_local_id, estado, casado_por)
    values (-32001, -32002, 'vinculado', 'chave_natural');
    insert into _res values ('2 vigentes mesmo lead rejeitado', 'rejeitado', 'ACEITOU');
  exception when unique_violation then
    insert into _res values ('2 vigentes mesmo lead rejeitado', 'rejeitado', 'rejeitado');
  end;
end $$;

-- ── Passo 3: reagendar (substituido_em) libera o lead pra uma linha nova ───
update public.lead_experimental_aulas
   set substituido_em = now()
 where lead_experimental_id = -32001 and substituido_em is null;

do $$
begin
  begin
    insert into public.lead_experimental_aulas
      (lead_experimental_id, aula_local_id, estado, casado_por)
    values (-32001, -32002, 'vinculado', 'chave_natural');
    insert into _res values ('reagendar cria 2a linha vigente', 'aceito', 'aceito');
  exception when unique_violation then
    insert into _res values ('reagendar cria 2a linha vigente', 'aceito', 'REJEITOU');
  end;
end $$;

-- ── Passo 3b: cancelar SEM reagendar continua sendo a linha vigente ────────
-- Lead -32001, apos o passo 3, tem UMA vigente (aula -32002, sem cancelado_em).
-- Aqui ela e cancelada (cancelado_em preenchido) SEM nunca ter sido reagendada
-- (substituido_em continua null). Pela regra do Contrato 1, isso NAO libera
-- espaco pra uma segunda linha vigente — so `substituido_em` faz isso. Se o
-- indice de vigencia olhasse `cancelado_em` (o mutante M2), esta insercao
-- indevida passaria a ser aceita.
--
-- Usa aula -32005, dedicada e nao usada por nenhum outro passo: sob o
-- mutante essa insercao NAO estoura excecao nenhuma (o indice de vigencia
-- fica permissivo demais e deixa passar), entao o resultado tem que aparecer
-- como divergencia limpa em _res, nao como um crash em outro passo por causa
-- de uma aula que ficou ocupada por engano.
update public.lead_experimental_aulas
   set cancelado_em = now()
 where lead_experimental_id = -32001 and substituido_em is null;

do $$
begin
  begin
    insert into public.lead_experimental_aulas
      (lead_experimental_id, aula_local_id, estado, casado_por)
    values (-32001, -32005, 'vinculado', 'chave_natural');
    insert into _res values
      ('cancelar sem reagendar NAO libera vigencia', 'rejeitado', 'ACEITOU — indice errado');
  exception when unique_violation then
    insert into _res values
      ('cancelar sem reagendar NAO libera vigencia', 'rejeitado', 'rejeitado');
  end;
end $$;

-- ── Passo 4: aula REALIZADA continua ocupada mesmo com cancelado_em depois ─
-- Lead -32002 (fresco) fica com a aula -32003, 'realizado', cancelada DEPOIS.
insert into public.lead_experimental_aulas
  (lead_experimental_id, aula_local_id, estado, casado_por, cancelado_em)
values (-32002, -32003, 'realizado', 'chave_natural', now());

-- Lead -32003 (fresco, sem vigencia propria) tenta pegar a MESMA aula -32003.
-- Se falhar, so pode ser o indice de OCUPACAO (o de vigencia nao tem motivo
-- pra disparar: -32003 nunca teve vinculo antes).
do $$
begin
  begin
    insert into public.lead_experimental_aulas
      (lead_experimental_id, aula_local_id, estado, casado_por)
    values (-32003, -32003, 'vinculado', 'chave_natural');
    insert into _res values
      ('aula realizada+cancelada depois continua ocupada', 'rejeitado', 'ACEITOU — BUG');
  exception when unique_violation then
    insert into _res values
      ('aula realizada+cancelada depois continua ocupada', 'rejeitado', 'rejeitado');
  end;
end $$;

-- ── Passo 5: aula CANCELADA antes de realizar libera pra outro lead ────────
-- Lead -32004 (fresco) fica com a aula -32004, 'cancelado' ANTES de realizar.
insert into public.lead_experimental_aulas
  (lead_experimental_id, aula_local_id, estado, casado_por, cancelado_em)
values (-32004, -32004, 'cancelado', 'chave_natural', now());

-- Lead -32005 (fresco) tenta pegar a MESMA aula -32004. Deve CONSEGUIR.
do $$
begin
  begin
    insert into public.lead_experimental_aulas
      (lead_experimental_id, aula_local_id, estado, casado_por)
    values (-32005, -32004, 'vinculado', 'chave_natural');
    insert into _res values ('aula cancelada antes libera p/ outro lead', 'aceito', 'aceito');
  exception when unique_violation then
    insert into _res values
      ('aula cancelada antes libera p/ outro lead', 'aceito', 'REJEITOU — regra errada');
  end;
end $$;

-- ── Passo 6: motivo_pendencia so aceita os dois valores ────────────────────
do $$
begin
  begin
    insert into public.lead_experimental_aulas (lead_experimental_id, motivo_pendencia)
    values (-32001, 'qualquer_coisa');
    insert into _res values ('motivo_pendencia invalido rejeitado', 'rejeitado', 'ACEITOU');
  exception when check_violation then
    insert into _res values ('motivo_pendencia invalido rejeitado', 'rejeitado', 'rejeitado');
  end;
end $$;

-- ── Passo 7: colunas do Contrato 3 existem com os tipos certos ─────────────
insert into _res
select 'colunas de recibo da matricula existem', '4',
       (select count(*)::text from information_schema.columns
         where table_schema='public' and table_name='lead_experimental_aulas'
           and column_name in ('aluno_id','aluno_vinculado_em','aluno_vinculado_por','aluno_origem'));

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
