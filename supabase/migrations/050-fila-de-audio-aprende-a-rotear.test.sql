-- Teste da 050 — a fila de áudio aprende a rotear
--
-- O passo que importa é o do ROTEAMENTO, e ele é medido no lugar certo: em
-- `net.http_request_queue`, que é onde `fn_fabio_chama_edge` deposita a chamada
-- pro Hermes. Não pergunto "o código tem um if?" — pergunto "a chamada foi
-- depositada?", que é o que decide se o agente vai receber a experimental.
--
-- E dá pra medir isso em produção sem risco: pg_net enfileira DENTRO da
-- transação, e o worker dele lê de outra conexão — linha não commitada é
-- invisível pra ele. O ROLLBACK apaga antes de existir pra alguém. Por isso o
-- teste não precisa substituir a função por um espião, que é o caminho que eu
-- ia tomar: trocar uma função viva por 2 segundos faria o áudio de quem
-- gravasse nesse intervalo sumir em silêncio.
--
-- A contagem é por audio_id dentro do corpo, não "quantas linhas tem na fila":
-- outra sessão commitando no meio do ensaio quebraria a contagem global.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

-- ── Fixture ─────────────────────────────────────────────────────────────────
insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000000500', 'ZZTESTE unidade 050', 'ZZTESTE050')
on conflict (id) do nothing;

insert into public.usuarios (id, nome, email, auth_user_id) values
  (-50901, 'ZZTESTE Dono 050',  'zz-dono-050@exemplo.invalido',  '00000000-0000-4000-8000-000000050901'),
  (-50902, 'ZZTESTE Outro 050', 'zz-outro-050@exemplo.invalido', '00000000-0000-4000-8000-000000050902');
insert into public.professores (id, nome, usuario_id) values
  (-50001, 'ZZTESTE Professor 050', -50901),
  (-50002, 'ZZTESTE Outro Prof 050', -50902);

-- Quatro leads, não um: `uq_lead_exp_aula_vigente` só deixa UM vínculo vigente
-- por experimental — a regra que impede a mesma experimental de existir duas
-- vezes na agenda. Cada caso do teste precisa da sua própria.
insert into public.leads (id, unidade_id, whatsapp, status) values
  (-50001, '00000000-0000-4000-8000-000000000500', '5521999500001', 'novo'),
  (-50002, '00000000-0000-4000-8000-000000000500', '5521999500002', 'novo'),
  (-50003, '00000000-0000-4000-8000-000000000500', '5521999500003', 'novo'),
  (-50004, '00000000-0000-4000-8000-000000000500', '5521999500004', 'novo'),
  (-50005, '00000000-0000-4000-8000-000000000500', '5521999500005', 'novo');

insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id)
select v.id, v.id, 'ZZTESTE Helena 050 #' || abs(v.id),
       '00000000-0000-4000-8000-000000000500',
       (now() at time zone 'America/Sao_Paulo')::date, '10:00',
       'experimental_agendada', -50001
  from (values (-50001), (-50002), (-50003), (-50004), (-50005)) as v(id);

-- A aula já aconteceu (1h atrás): dentro da janela de gravação.
insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, data_hora_fim,
   categoria, curso_nome, professor_id, cancelada)
values
  (-50001, -950001, '00000000-0000-4000-8000-000000000500',
   (now() at time zone 'America/Sao_Paulo')::date, now() - interval '1 hour',
   now() - interval '10 minutes', 'experimental', 'ZZTESTE Canto', -50001, false),
  -- a MESMA aula, mas de outro professor: a guarda de posse
  (-50002, -950002, '00000000-0000-4000-8000-000000000500',
   (now() at time zone 'America/Sao_Paulo')::date, now() - interval '1 hour',
   now() - interval '10 minutes', 'experimental', 'ZZTESTE Canto', -50002, false),
  -- aula velha demais: a janela de 3 dias
  (-50003, -950003, '00000000-0000-4000-8000-000000000500',
   ((now() at time zone 'America/Sao_Paulo')::date - 9), now() - interval '9 days',
   now() - interval '9 days', 'experimental', 'ZZTESTE Canto', -50001, false),
  -- aula COMUM do mesmo professor: o caminho que não pode mudar
  (-50004, -950004, '00000000-0000-4000-8000-000000000500',
   (now() at time zone 'America/Sao_Paulo')::date, now() - interval '1 hour',
   now() - interval '10 minutes', 'individual', 'ZZTESTE Violao', -50001, false),
  -- a aula do vínculo em 'faltou' (uq_lead_exp_aula_ocupada: uma aula, um vínculo)
  (-50005, -950005, '00000000-0000-4000-8000-000000000500',
   (now() at time zone 'America/Sao_Paulo')::date, now() - interval '1 hour',
   now() - interval '10 minutes', 'experimental', 'ZZTESTE Canto', -50001, false),
  -- aula ÓRFÃ (sem professor). Ela existe porque a guarda de posse só é honesta
  -- com `is distinct from`: com `<>`, null não compara e a comparação vira
  -- nula — o `if` não dispara e a porta abre pra aula de ninguém.
  (-50006, -950006, '00000000-0000-4000-8000-000000000500',
   (now() at time zone 'America/Sao_Paulo')::date, now() - interval '1 hour',
   now() - interval '10 minutes', 'experimental', 'ZZTESTE Canto', null, false);

insert into public.lead_experimental_aulas (id, lead_experimental_id, aula_local_id, estado, casado_por) values
  (-50001, -50001, -50001, 'vinculado', 'chave_natural'),
  (-50002, -50002, -50002, 'vinculado', 'chave_natural'),  -- aula de outro professor
  (-50003, -50003, -50003, 'vinculado', 'chave_natural'),  -- fora da janela
  (-50004, -50004, -50005, 'faltou',    'chave_natural'),  -- estado que recusa
  (-50005, -50005, -50006, 'vinculado', 'chave_natural');  -- aula sem professor

create temp table _ids(rotulo text, id uuid) on commit drop;
create temp table _erros(passo text, msg text) on commit drop;
-- Os blocos abaixo trocam de papel pra chamar a RPC como o app chama. Sem
-- isto, o `insert` no diário de bordo estoura por permissão e o teste morre
-- ANTES de medir o que veio medir.
grant select, insert on _ids, _erros to authenticated, anon;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1) O ROTEAMENTO — a pergunta que decide tudo
-- ═══════════════════════════════════════════════════════════════════════════

-- 1a) aula COMUM: continua chamando o Hermes, como sempre chamou
do $$
declare v_id uuid;
begin
  insert into public.fabio_fila_audios
    (professor_id, unidade_id, aula_id, storage_path, duracao_segundos, origem, status)
  values (-50001, '00000000-0000-4000-8000-000000000500', -50004,
          'zzteste/050/comum.webm', 30, 'app', 'pendente')
  returning id into v_id;
  insert into _ids values ('comum', v_id);
end $$;

insert into _res select 'a aula comum ainda chama o Hermes', '1',
  (select count(*)::text from net.http_request_queue q
    where convert_from(q.body, 'utf8') like '%' || (select id::text from _ids where rotulo='comum') || '%');

-- 1b) EXPERIMENTAL: o Hermes não é chamado
do $$
declare v_id uuid;
begin
  insert into public.fabio_fila_audios
    (professor_id, unidade_id, aula_id, vinculo_id, storage_path, duracao_segundos, origem, status)
  values (-50001, '00000000-0000-4000-8000-000000000500', -50001, -50001,
          'zzteste/050/experimental.webm', 30, 'app', 'pendente')
  returning id into v_id;
  insert into _ids values ('experimental', v_id);
end $$;

insert into _res select 'a experimental NAO chega no Hermes', '0',
  (select count(*)::text from net.http_request_queue q
    where convert_from(q.body, 'utf8') like '%' || (select id::text from _ids where rotulo='experimental') || '%');

-- ═══════════════════════════════════════════════════════════════════════════
-- 2) A porta do professor
-- ═══════════════════════════════════════════════════════════════════════════

do $$
declare v_out jsonb;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000050901"}',true);

  begin
    select public.app_enfileirar_audio_experimental(-50001, 'zzteste/050/pela-rpc.webm', 42) into v_out;
    insert into _ids values ('rpc', (v_out->>'audio_id')::uuid);
  exception when others then
    insert into _erros values ('rpc feliz', sqlerrm);
  end;

  begin
    perform public.app_enfileirar_audio_experimental(-50002, 'zzteste/050/alheia.webm', 42);
    insert into _erros values ('aula de outro professor', 'NAO LEVANTOU');
  exception when others then
    insert into _erros values ('aula de outro professor', sqlerrm);
  end;

  begin
    perform public.app_enfileirar_audio_experimental(-50003, 'zzteste/050/velha.webm', 42);
    insert into _erros values ('fora da janela', 'NAO LEVANTOU');
  exception when others then
    insert into _erros values ('fora da janela', sqlerrm);
  end;

  begin
    perform public.app_enfileirar_audio_experimental(-50004, 'zzteste/050/faltou.webm', 42);
    insert into _erros values ('experimental com falta', 'NAO LEVANTOU');
  exception when others then
    insert into _erros values ('experimental com falta', sqlerrm);
  end;

  begin
    perform public.app_enfileirar_audio_experimental(-50001, '   ', 42);
    insert into _erros values ('sem storage_path', 'NAO LEVANTOU');
  exception when others then
    insert into _erros values ('sem storage_path', sqlerrm);
  end;

  begin
    perform public.app_enfileirar_audio_experimental(-50005, 'zzteste/050/orfa.webm', 42);
    insert into _erros values ('aula sem professor', 'NAO LEVANTOU');
  exception when others then
    insert into _erros values ('aula sem professor', sqlerrm);
  end;

  reset role;
end $$;

insert into _res select 'a RPC enfileira e devolve o audio_id', '1',
  (select count(*)::text from _ids where rotulo='rpc');

insert into _res select 'e a linha nasce marcada como experimental', 'sim',
  (select case when f.vinculo_id = -50001 and f.aula_id = -50001
                and f.professor_id = -50001 and f.status = 'pendente'
          then 'sim' else 'nao' end
     from public.fabio_fila_audios f
     join _ids i on i.id = f.id and i.rotulo = 'rpc');

-- E, por ser experimental, ela também não chamou o Hermes: é a mesma prova do
-- passo 1b vista pelo caminho que o professor usa de verdade.
insert into _res select 'nem pela RPC o Hermes e chamado', '0',
  (select count(*)::text from net.http_request_queue q
    where convert_from(q.body, 'utf8') like '%' || (select id::text from _ids where rotulo='rpc') || '%');

insert into _res select 'a RPC recusa aula de outro professor', 'aula_de_outro_professor',
  (select case when msg like '%aula_de_outro_professor%' then 'aula_de_outro_professor' else msg end
     from _erros where passo='aula de outro professor');

insert into _res select 'a RPC recusa fora da janela', 'janela_de_gravacao_encerrada',
  (select case when msg like '%janela_de_gravacao_encerrada%' then 'janela_de_gravacao_encerrada' else msg end
     from _erros where passo='fora da janela');

insert into _res select 'a RPC recusa experimental com falta', 'experimental_faltou_nao_tem_registro',
  (select case when msg like '%experimental_faltou%' then 'experimental_faltou_nao_tem_registro' else msg end
     from _erros where passo='experimental com falta');

-- Aula de ninguém também não é dele. Sem este passo, trocar `is distinct from`
-- por `<>` passa despercebido: null não compara, o if não dispara, e a porta
-- abre pra órfã — o mesmo buraco que já apareceu na 036 e na 038.
insert into _res select 'a RPC recusa aula sem professor', 'aula_de_outro_professor',
  (select case when msg like '%aula_de_outro_professor%' then 'aula_de_outro_professor' else msg end
     from _erros where passo='aula sem professor');

insert into _res select 'a RPC recusa storage_path vazio', 'storage_path obrigatório',
  (select case when msg like '%storage_path obrigat%' then 'storage_path obrigatório' else msg end
     from _erros where passo='sem storage_path');

insert into _res select 'a RPC feliz nao levantou nada', '0',
  (select count(*)::text from _erros where passo='rpc feliz');

-- ═══════════════════════════════════════════════════════════════════════════
-- 3) Quem NÃO pode
-- ═══════════════════════════════════════════════════════════════════════════

do $$
begin
  set local role anon;
  begin
    perform public.app_enfileirar_audio_experimental(-50001, 'zzteste/050/anon.webm', 10);
    insert into _erros values ('anon', 'NAO LEVANTOU');
  exception when others then
    insert into _erros values ('anon', sqlerrm);
  end;
  reset role;
end $$;

insert into _res select 'anonimo nao enfileira nada', 'barrado',
  (select case when msg = 'NAO LEVANTOU' then 'PASSOU' else 'barrado' end
     from _erros where passo='anon');

-- Sem professor vinculado o usuário autenticado também não passa.
do $$
begin
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-0000000509ff"}',true);
  begin
    perform public.app_enfileirar_audio_experimental(-50001, 'zzteste/050/sem-prof.webm', 10);
    insert into _erros values ('sem professor', 'NAO LEVANTOU');
  exception when others then
    insert into _erros values ('sem professor', sqlerrm);
  end;
  reset role;
end $$;

insert into _res select 'autenticado sem professor tambem nao', 'sem_professor_vinculado',
  (select case when msg like '%sem_professor%' then 'sem_professor_vinculado' else msg end
     from _erros where passo='sem professor');

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
