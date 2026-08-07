-- Teste da 053 — a falta em um toque
--
-- O passo que eu mais quero ver verde é "a devolutiva CONTINUA na fila". Esta
-- migration reescreve `fabio_avisos_comerciais_pendentes`, que é a única porta
-- pela qual a devolutiva da experimental chega ao comercial hoje. Um erro no
-- filtro novo não daria erro nenhum: a devolutiva simplesmente pararia de ser
-- listada, e o consultor deixaria de receber sem que nada acusasse.
--
-- E o segundo é "falta não vira registro": a falta e a devolutiva são caminhos
-- separados de propósito, e o dia em que um contaminar o outro é o dia em que
-- alguém escreve capítulo pedagógico de aula que não aconteceu.

create temp table _res(passo text, esperado text, obtido text) on commit drop;
create temp table _erros(passo text, msg text) on commit drop;
grant select, insert on _erros to authenticated, anon;

-- ── Fixture ─────────────────────────────────────────────────────────────────
insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000000530', 'ZZTESTE unidade 053', 'ZZTESTE053'),
  ('00000000-0000-4000-8000-000000000531', 'ZZTESTE sem comercial', 'ZZTESTE531')
on conflict (id) do nothing;

insert into public.unidade_contato_comercial (unidade_id, nome, whatsapp, ativo)
values ('00000000-0000-4000-8000-000000000530', 'ZZTESTE Consultora', '5521999530001', true);

insert into public.usuarios (id, nome, email, auth_user_id) values
  (-53901, 'ZZTESTE Dono 053', 'zz-dono-053@exemplo.invalido', '00000000-0000-4000-8000-000000053901');
insert into public.professores (id, nome, usuario_id) values (-53001, 'ZZTESTE Rita 053', -53901);
insert into public.professores (id, nome) values (-53002, 'ZZTESTE Outro 053');

insert into public.leads (id, unidade_id, whatsapp, status)
select v.id, v.uni::uuid, '55219995300' || abs(v.id) % 100, 'novo'
  from (values
    (-53001, '00000000-0000-4000-8000-000000000530'),
    (-53002, '00000000-0000-4000-8000-000000000530'),
    (-53003, '00000000-0000-4000-8000-000000000530'),
    (-53004, '00000000-0000-4000-8000-000000000531')) as v(id, uni);

insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id)
select v.id, v.id, 'ZZTESTE Aluno 053 #' || abs(v.id), v.uni::uuid,
       (now() at time zone 'America/Sao_Paulo')::date, '16:00',
       'experimental_agendada', -53001
  from (values
    (-53001, '00000000-0000-4000-8000-000000000530'),
    (-53002, '00000000-0000-4000-8000-000000000530'),
    (-53003, '00000000-0000-4000-8000-000000000530'),
    (-53004, '00000000-0000-4000-8000-000000000531')) as v(id, uni);

insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, data_hora_fim,
   categoria, curso_nome, professor_id, cancelada)
values
  -- 1: o caso feliz (aula já começou)
  (-53001, -953001, '00000000-0000-4000-8000-000000000530',
   (now() at time zone 'America/Sao_Paulo')::date, now() - interval '1 hour',
   now() - interval '10 minutes', 'experimental', 'ZZTESTE Canto', -53001, false),
  -- 2: já tem devolutiva CONFIRMADA — não pode virar falta
  (-53002, -953002, '00000000-0000-4000-8000-000000000530',
   (now() at time zone 'America/Sao_Paulo')::date, now() - interval '1 hour',
   now() - interval '10 minutes', 'experimental', 'ZZTESTE Canto', -53001, false),
  -- 3: aula de OUTRO professor
  (-53003, -953003, '00000000-0000-4000-8000-000000000530',
   (now() at time zone 'America/Sao_Paulo')::date, now() - interval '1 hour',
   now() - interval '10 minutes', 'experimental', 'ZZTESTE Canto', -53002, false),
  -- 4: unidade SEM comercial cadastrado
  (-53004, -953004, '00000000-0000-4000-8000-000000000531',
   (now() at time zone 'America/Sao_Paulo')::date, now() - interval '1 hour',
   now() - interval '10 minutes', 'experimental', 'ZZTESTE Canto', -53001, false);

insert into public.lead_experimental_aulas (id, lead_experimental_id, aula_local_id, estado, casado_por)
values
  (-53001, -53001, -53001, 'vinculado', 'chave_natural'),
  (-53002, -53002, -53002, 'vinculado', 'chave_natural'),
  (-53003, -53003, -53003, 'vinculado', 'chave_natural'),
  (-53004, -53004, -53004, 'vinculado', 'chave_natural');

-- A experimental #2 já foi relatada e confirmada.
insert into public.lead_experimental_registros
  (vinculo_id, unidade_id, professor_id, anotacao_pedagogica, devolutiva_familia,
   proximos_passos, leitura_de_conversao, origem, status, confirmado_em)
values (-53002, '00000000-0000-4000-8000-000000000530', -53001,
  'a aula aconteceu', 'foi bem', 'seguir', 'quente', 'app', 'confirmado', now());

-- ═══════════════════════════════════════════════════════════════════════════
-- 1) Um toque
-- ═══════════════════════════════════════════════════════════════════════════
create temp table _saida(rotulo text, j jsonb) on commit drop;
grant select, insert on _saida to authenticated;

do $$
declare v_out jsonb;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000053901"}',true);

  begin
    select public.app_declarar_falta_experimental(-53001) into v_out;
    insert into _saida values ('feliz', v_out);
  exception when others then insert into _erros values ('feliz', sqlerrm);
  end;

  begin
    perform public.app_declarar_falta_experimental(-53002);
    insert into _erros values ('ja confirmada', 'NAO LEVANTOU');
  exception when others then insert into _erros values ('ja confirmada', sqlerrm);
  end;

  begin
    perform public.app_declarar_falta_experimental(-53003);
    insert into _erros values ('outro professor', 'NAO LEVANTOU');
  exception when others then insert into _erros values ('outro professor', sqlerrm);
  end;

  begin
    select public.app_declarar_falta_experimental(-53004) into v_out;
    insert into _saida values ('sem comercial', v_out);
  exception when others then insert into _erros values ('sem comercial', sqlerrm);
  end;

  reset role;
end $$;

insert into _res select 'o toque nao levantou nada', '0',
  (select coalesce((select msg from _erros where passo='feliz'), '0'));

insert into _res select 'a presenca vira falta de fonte forte', 'falta|professor_la_teacher',
  (select coalesce(presenca_status,'?') || '|' || coalesce(presenca_respondido_por,'?')
     from public.lead_experimental_aulas where id = -53001);

insert into _res select 'e o vinculo passa a faltou', 'faltou',
  (select estado from public.lead_experimental_aulas where id = -53001);

-- A falta NÃO cria capítulo pedagógico. Se um dia criar, alguém vai preencher.
insert into _res select 'falta nao vira registro pedagogico', '0',
  (select count(*)::text from public.lead_experimental_registros where vinculo_id = -53001);

insert into _res select 'o aviso foi reivindicado na hora', 'true',
  (select j ->> 'aviso_claimed' from _saida where rotulo='feliz');

-- ── O corpo ─────────────────────────────────────────────────────────────────
create temp table _msg(corpo text, dest text, tipo text, status text) on commit drop;
insert into _msg
select n.corpo, n.destinatario_whatsapp, n.tipo, n.status
  from public.fabio_notificacoes n
 where n.referencia_tipo = 'lead_experimental_falta' and n.referencia_id = '-53001';

insert into _res select 'a mensagem diz que o aluno nao veio', 'sim',
  (select case when corpo like '%não veio%' then 'sim' else 'nao' end from _msg);

insert into _res select 'e traz o nome do aluno', 'sim',
  (select case when corpo like '%ZZTESTE Aluno 053 #53001%' then 'sim' else 'nao' end from _msg);

insert into _res select 'e quem marcou', 'sim',
  (select case when corpo like '%ZZTESTE Rita 053%' then 'sim' else 'nao' end from _msg);

-- Enxuta: nada de rótulo pedagógico, que faria o consultor procurar conteúdo
-- que não existe.
insert into _res select 'e NAO tem bloco pedagogico', 'enxuta',
  (select case when corpo like '%Como foi%' or corpo like '%Próximos passos%'
                 or corpo like '%Leitura de conversão%'
          then 'INCHOU' else 'enxuta' end from _msg);

insert into _res select 'vai pro comercial da unidade', '5521999530001',
  (select dest from _msg);

-- ── Sem comercial: fica visível, não some ───────────────────────────────────
insert into _res select 'unidade sem comercial nao perde o aviso', 'pulada_sem_destinatario',
  (select n.status from public.fabio_notificacoes n
    where n.referencia_tipo = 'lead_experimental_falta' and n.referencia_id = '-53004');

insert into _res select 'e o motivo fica dito', 'sem_destinatario',
  (select j ->> 'aviso_motivo' from _saida where rotulo='sem comercial');

-- ── Recusas ─────────────────────────────────────────────────────────────────
insert into _res select 'aula ja relatada nao vira falta', 'experimental_ja_registrada_como_realizada',
  (select case when msg like '%ja_registrada_como_realizada%'
          then 'experimental_ja_registrada_como_realizada' else msg end
     from _erros where passo='ja confirmada');

insert into _res select 'e a devolutiva confirmada continua de pe', 'confirmado',
  (select status from public.lead_experimental_registros where vinculo_id = -53002);

insert into _res select 'aula de outro professor e recusada', 'aula_de_outro_professor',
  (select case when msg like '%aula_de_outro_professor%' then 'aula_de_outro_professor' else msg end
     from _erros where passo='outro professor');

-- ═══════════════════════════════════════════════════════════════════════════
-- 2) A FILA — o passo que protege o caminho que já funcionava
-- ═══════════════════════════════════════════════════════════════════════════
-- Uma devolutiva com lease vencido: o worker TEM que continuar enxergando.
insert into public.fabio_notificacoes
  (professor_id, destinatario_tipo, destinatario_whatsapp, tipo, categoria, corpo,
   canal, status, tentativas, lease_token, lease_expira_em, referencia_tipo, referencia_id)
values (null, 'comercial', '5521999530001', 'experimental_registrada', 'informativa',
  'ZZTESTE devolutiva antiga', 'whatsapp', 'processando', 1,
  gen_random_uuid(), now() - interval '1 minute',
  'lead_experimental_registro', '00000000-0000-4000-8000-0000005300f0');

create temp table _fila(j jsonb) on commit drop;
insert into _fila select public.fabio_avisos_comerciais_pendentes(50);

insert into _res select 'a devolutiva CONTINUA na fila', 'sim',
  (select case when j::text like '%00000000-0000-4000-8000-0000005300f0%' then 'sim' else 'nao' end
     from _fila);

insert into _res select 'e a falta sem destinatario tambem aparece', 'sim',
  (select case when j::text like '%"vinculo_id": "-53004"%' then 'sim' else 'nao' end from _fila);

-- O worker precisa saber QUAL claim chamar. Sem o tipo no payload ele chuta.
insert into _res select 'a fila diz o tipo de cada item', 'sim',
  (select case when j::text like '%experimental_falta%'
                 and j::text like '%experimental_registrada%' then 'sim' else 'nao' end
     from _fila);

-- Só um dos dois ids vem preenchido por item — é isso que faz o desvio ser
-- decidível em vez de adivinhado.
insert into _res select 'devolutiva traz registro_id e vinculo_id nulo', 'sim',
  (select case when count(*) = 1 then 'sim' else 'nao' end
     from jsonb_array_elements((select j from _fila)) e
    where e.value ->> 'registro_id' = '00000000-0000-4000-8000-0000005300f0'
      and e.value ->> 'vinculo_id' is null);

insert into _res select 'falta traz vinculo_id e registro_id nulo', 'sim',
  (select case when count(*) = 1 then 'sim' else 'nao' end
     from jsonb_array_elements((select j from _fila)) e
    where e.value ->> 'vinculo_id' = '-53004'
      and e.value ->> 'registro_id' is null);

-- ═══════════════════════════════════════════════════════════════════════════
-- 3) Quem NÃO pode
-- ═══════════════════════════════════════════════════════════════════════════
do $$
begin
  set local role anon;
  begin
    perform public.app_declarar_falta_experimental(-53001);
    insert into _erros values ('anon', 'NAO LEVANTOU');
  exception when others then insert into _erros values ('anon', sqlerrm);
  end;
  reset role;

  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000053901"}',true);
  begin
    perform public.fabio_claim_aviso_falta_experimental(-53001, 5);
    insert into _erros values ('prof no claim', 'NAO LEVANTOU');
  exception when others then insert into _erros values ('prof no claim', sqlerrm);
  end;
  begin
    perform public.fabio_avisos_comerciais_pendentes(5);
    insert into _erros values ('prof na fila', 'NAO LEVANTOU');
  exception when others then insert into _erros values ('prof na fila', sqlerrm);
  end;
  reset role;
end $$;

insert into _res select 'anonimo nao declara falta de ninguem', 'barrado',
  (select case when msg = 'NAO LEVANTOU' then 'PASSOU' else 'barrado' end
     from _erros where passo='anon');

insert into _res select 'professor nao mexe na fila do comercial', '2',
  (select count(*)::text from _erros
    where passo in ('prof no claim','prof na fila') and msg <> 'NAO LEVANTOU');

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
