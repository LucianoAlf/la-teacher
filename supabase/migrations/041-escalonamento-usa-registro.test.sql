-- Teste do escalonamento pra coordenacao — cobre 039 + 040 + 041
--
-- POR QUE UM TESTE SO PRAS TRES MIGRATIONS
-- As tres publicam o MESMO objeto (fn_pendencias_escalonadas). A 040 e a 041
-- sao `create or replace` em cima da 039, e a 040 ainda dropa a assinatura de
-- 1 argumento. Testar cada uma isolada testaria codigo que ja nao existe: o
-- que roda em producao e o corpo da 041. As defesas das tres estao aqui, e os
-- mutantes (scripts/mutantes-041.mjs) atacam uma por uma.
--
-- DIVIDA QUE ESTE ARQUIVO PAGA
-- As tres foram aplicadas em producao sob urgencia, sem teste e sem mutante —
-- fora do padrao da casa, e foi exatamente ai que a regua saiu errada TRES
-- vezes seguidas (presenca em vez de registro). Quem pegou foi o Alf lendo a
-- mensagem do WhatsApp, nao um teste.
--
-- Nenhum prontuario real vira bancada: tudo e ZZTESTE, em ids negativos, e o
-- runner roda em transacao descartavel conferindo impressao digital depois.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

-- ── Premissas da fixture ───────────────────────────────────────────────────
-- fn_data_corte_cobranca() e uma constante que a casa move de vez em quando.
-- Se ela andar pra frente do ponto onde a fixture ancora, os casos deixam de
-- exercitar o que dizem exercitar e o teste ficaria verde sem provar nada.
-- Fixture tambem apodrece em silencio; entao ela se declara aqui.
insert into _res select 'premissa: aula de 10 dias atras ainda e cobravel', 'sim',
  case when current_date - 10 >= public.fn_data_corte_cobranca() then 'sim'
       else 'NAO — o corte andou, a fixture apodreceu' end;

insert into _res select 'premissa: o passivo esta acima do limite de 3 dias', 'sim',
  case when current_date - (public.fn_data_corte_cobranca() - 1) > 4 then 'sim'
       else 'NAO — o corte encostou em hoje, o passivo nao testa mais o cobravel' end;

-- ── Cenario ────────────────────────────────────────────────────────────────
insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000000410', 'ZZTESTE CG 041',      'ZZTESTE041A'),
  ('00000000-0000-4000-8000-000000000411', 'ZZTESTE Recreio 041', 'ZZTESTE041B')
on conflict (id) do nothing;

insert into public.usuarios (id, nome, email, auth_user_id) values
  (-41901, 'ZZTESTE Usuario Piloto', 'zzteste-piloto-41@exemplo.invalido',
   '00000000-0000-4000-8000-000000041901'),
  (-41902, 'ZZTESTE Usuario Outro',  'zzteste-outro-41@exemplo.invalido',
   '00000000-0000-4000-8000-000000041902');

insert into public.professores (id, nome, usuario_id) values
  (-41001, 'ZZTESTE Professor Piloto', -41901),
  (-41002, 'ZZTESTE Professor Fora do Escopo', -41902);

-- Dois "Ana": nome completo e o que a coordenacao encaminha, e primeiro nome
-- repete numa escola. Com primeiro nome os dois colapsariam num so.
insert into public.alunos (id, nome, unidade_id) values
  (-41001, 'ZZTESTE Ana Beatriz Souza',   '00000000-0000-4000-8000-000000000410'),
  (-41002, 'ZZTESTE Ana Carolina Lima',   '00000000-0000-4000-8000-000000000410'),
  (-41003, 'ZZTESTE Bruno Dias Martins',  '00000000-0000-4000-8000-000000000411'),
  (-41004, 'ZZTESTE Carlos Eduardo Reis', '00000000-0000-4000-8000-000000000410'),
  (-41005, 'ZZTESTE Diana Freitas Alves', '00000000-0000-4000-8000-000000000410'),
  (-41006, 'ZZTESTE Elisa Nunes Prado',   '00000000-0000-4000-8000-000000000410'),
  (-41007, 'ZZTESTE Fabio Rocha Lima',    '00000000-0000-4000-8000-000000000410'),
  (-41008, 'ZZTESTE Gustavo Pires Sa',    '00000000-0000-4000-8000-000000000410');

-- tipo='turma' em todas: a view tem um ramo `tipo='turma' OR NOT EXISTS(turma
-- no mesmo horario)`, e ancorar em turma deixa o cenario ler o que ele testa.
insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, data_hora_fim,
   tipo, curso_nome, turma_nome, professor_id, professor_nome, cancelada, anotacoes)
values
  -- caso principal: cobravel, atrasado, sem conteudo, 2 alunos, unidade CG
  (-41001, -941001, '00000000-0000-4000-8000-000000000410', current_date - 10,
   ((current_date - 10) + time '14:00') at time zone 'America/Sao_Paulo',
   ((current_date - 10) + time '15:00') at time zone 'America/Sao_Paulo',
   'turma', 'ZZTESTE Canto T', 'ZZTESTE Canto T1', -41001, 'ZZTESTE Professor Piloto', false, null),

  -- MESMO professor, OUTRA unidade: prova que a unidade vai por aula
  (-41002, -941002, '00000000-0000-4000-8000-000000000411', current_date - 6,
   ((current_date - 6) + time '09:00') at time zone 'America/Sao_Paulo',
   ((current_date - 6) + time '10:00') at time zone 'America/Sao_Paulo',
   'turma', 'ZZTESTE Bateria T', 'ZZTESTE Bateria T1', -41001, 'ZZTESTE Professor Piloto', false, null),

  -- EXATOS 3 dias: o limite e `> p_dias`, entao esta fica de fora.
  -- Ancorada em now() (e nao em hora de relogio) pra cair em 3 cravados a
  -- qualquer hora do dia — senao o caso de borda vira sorte.
  (-41003, -941003, '00000000-0000-4000-8000-000000000410', current_date - 3,
   now() - interval '3 days' - interval '2 minutes',
   now() - interval '3 days' - interval '1 minute',
   'turma', 'ZZTESTE Teclado T', 'ZZTESTE Teclado T1', -41001, 'ZZTESTE Professor Piloto', false, null),

  -- PASSIVO: antes da data de corte. Atrasadissima, sem conteudo — so o
  -- `cobravel` a segura. Foi ela que virou "18 aulas atrasadas" no grupo.
  (-41004, -941004, '00000000-0000-4000-8000-000000000410', public.fn_data_corte_cobranca() - 1,
   ((public.fn_data_corte_cobranca() - 1) + time '14:00') at time zone 'America/Sao_Paulo',
   ((public.fn_data_corte_cobranca() - 1) + time '15:00') at time zone 'America/Sao_Paulo',
   'turma', 'ZZTESTE Violino T', 'ZZTESTE Violino T1', -41001, 'ZZTESTE Professor Piloto', false, null),

  -- CONTEUDO LANCADO, sem presenca forte: esta aula esta em
  -- vw_presenca_pendencia e NAO esta em vw_registro_pendencia. E o caso que
  -- separa as duas reguas — o professor fez o trabalho dele.
  (-41005, -941005, '00000000-0000-4000-8000-000000000410', current_date - 10,
   ((current_date - 10) + time '16:00') at time zone 'America/Sao_Paulo',
   ((current_date - 10) + time '17:00') at time zone 'America/Sao_Paulo',
   'turma', 'ZZTESTE Baixo T', 'ZZTESTE Baixo T1', -41001, 'ZZTESTE Professor Piloto', false,
   'ZZTESTE conteudo lancado pelo professor'),

  -- OUTRO professor, cobravel e atrasado: se o escopo do piloto vazar, ele
  -- aparece. Hoje isso levaria 16 professores pro grupo da coordenacao.
  (-41006, -941006, '00000000-0000-4000-8000-000000000410', current_date - 10,
   ((current_date - 10) + time '18:00') at time zone 'America/Sao_Paulo',
   ((current_date - 10) + time '19:00') at time zone 'America/Sao_Paulo',
   'turma', 'ZZTESTE Guitarra T', 'ZZTESTE Guitarra T1', -41002, 'ZZTESTE Professor Fora do Escopo', false, null),

  -- terceira cobravel do piloto, com curso_nome NULO: exercita o coalesce
  -- pro turma_nome (mensagem sem "Aula" generico)
  (-41007, -941007, '00000000-0000-4000-8000-000000000410', current_date - 8,
   ((current_date - 8) + time '11:00') at time zone 'America/Sao_Paulo',
   ((current_date - 8) + time '12:00') at time zone 'America/Sao_Paulo',
   'turma', null, 'ZZTESTE Violao T2', -41001, 'ZZTESTE Professor Piloto', false, null);

insert into public.aula_alunos_emusys
  (id, aula_emusys_id, unidade_id, aluno_chave, aluno_id, aluno_nome, aluno_nome_normalizado)
values
  (-41001, -41001, '00000000-0000-4000-8000-000000000410', 'zzteste-41001', -41001, 'ZZTESTE Ana Beatriz Souza',   'zzteste ana beatriz souza'),
  (-41002, -41001, '00000000-0000-4000-8000-000000000410', 'zzteste-41002', -41002, 'ZZTESTE Ana Carolina Lima',   'zzteste ana carolina lima'),
  (-41003, -41002, '00000000-0000-4000-8000-000000000411', 'zzteste-41003', -41003, 'ZZTESTE Bruno Dias Martins',  'zzteste bruno dias martins'),
  (-41004, -41003, '00000000-0000-4000-8000-000000000410', 'zzteste-41004', -41004, 'ZZTESTE Carlos Eduardo Reis', 'zzteste carlos eduardo reis'),
  (-41005, -41004, '00000000-0000-4000-8000-000000000410', 'zzteste-41005', -41005, 'ZZTESTE Diana Freitas Alves', 'zzteste diana freitas alves'),
  (-41006, -41005, '00000000-0000-4000-8000-000000000410', 'zzteste-41006', -41006, 'ZZTESTE Elisa Nunes Prado',   'zzteste elisa nunes prado'),
  (-41007, -41006, '00000000-0000-4000-8000-000000000410', 'zzteste-41007', -41007, 'ZZTESTE Fabio Rocha Lima',    'zzteste fabio rocha lima'),
  (-41008, -41007, '00000000-0000-4000-8000-000000000410', 'zzteste-41008', -41008, 'ZZTESTE Gustavo Pires Sa',    'zzteste gustavo pires sa');

-- ── A rodada sob teste, guardada ───────────────────────────────────────────
-- O retorno fica em tabela: conferir chamando de novo compara com OUTRA
-- rodada, e ai o teste passa a medir o mundo depois do conserto, nao o que a
-- chamada devolveu.
create temp table _piloto(j jsonb) on commit drop;
insert into _piloto select public.fn_pendencias_escalonadas(3, -41001, 12);

create temp table _cortado(j jsonb) on commit drop;
insert into _cortado select public.fn_pendencias_escalonadas(3, -41001, 1);

create temp table _aulas(aula_id bigint, unidade text, hora text, curso text, alunos text)
  on commit drop;
insert into _aulas
select (a->>'aula_id')::bigint, a->>'unidade', a->>'hora', a->>'curso',
       (select string_agg(x, ' | ' order by x) from jsonb_array_elements_text(a->'alunos') x)
  from jsonb_array_elements((select j->'linhas' from _piloto)) p,
       jsonb_array_elements(p->'aulas') a
 where (p->>'professor_id')::integer = -41001;

-- ── Escopo: so o piloto sobe pro grupo ─────────────────────────────────────
insert into _res select 'nenhum professor fora do escopo entra', '0',
  (select count(*)::text
     from jsonb_array_elements((select j->'linhas' from _piloto)) p
    where (p->>'professor_id')::integer is distinct from -41001);

-- ── Regua: registro, nao presenca ──────────────────────────────────────────
insert into _res select 'aula sem conteudo lancado e cobrada', '1',
  (select count(*)::text from _aulas where aula_id = -41001);

insert into _res select 'aula com conteudo lancado NAO e cobrada', '0',
  (select count(*)::text from _aulas where aula_id = -41005);

insert into _res select 'passivo (antes do corte) NAO e cobrado', '0',
  (select count(*)::text from _aulas where aula_id = -41004);

insert into _res select 'aula com exatos 3 dias NAO e cobrada (limite e >)', '0',
  (select count(*)::text from _aulas where aula_id = -41003);

insert into _res select 'total de aulas cobraveis do piloto', '3',
  (select count(*)::text from _aulas);

-- ── Encaminhavel: a coordenacao copia e manda pro professor ────────────────
insert into _res select 'nome COMPLETO dos dois alunos da mesma aula',
  'ZZTESTE Ana Beatriz Souza | ZZTESTE Ana Carolina Lima',
  (select alunos from _aulas where aula_id = -41001);

insert into _res select 'hora sai no fuso de Sao Paulo', '14:00',
  (select hora from _aulas where aula_id = -41001);

insert into _res select 'curso cai pro nome da turma quando curso_nome e nulo',
  'ZZTESTE Violao T2', (select curso from _aulas where aula_id = -41007);

-- Unidade por aula: o professor da em duas, e um max() no nivel dele
-- carimbaria a unidade errada na mensagem que vai ser encaminhada.
insert into _res select 'unidade da aula de CG', 'ZZTESTE CG 041',
  (select unidade from _aulas where aula_id = -41001);
insert into _res select 'unidade da aula do Recreio', 'ZZTESTE Recreio 041',
  (select unidade from _aulas where aula_id = -41002);

insert into _res select 'o resumo do professor lista as duas unidades',
  'ZZTESTE CG 041 | ZZTESTE Recreio 041',
  (select string_agg(x, ' | ' order by x)
     from jsonb_array_elements((select j->'linhas' from _piloto)) p,
          jsonb_array_elements_text(p->'unidades') x
    where (p->>'professor_id')::integer = -41001);

-- ── Corte da lista: encurta a mensagem sem encurtar o numero ───────────────
insert into _res select 'p_max_aulas=1 manda so uma aula', '1',
  (select jsonb_array_length(p->'aulas')::text
     from jsonb_array_elements((select j->'linhas' from _cortado)) p
    where (p->>'professor_id')::integer = -41001);

insert into _res select 'mas total_aulas continua contando as 3', '3',
  (select p->>'total_aulas'
     from jsonb_array_elements((select j->'linhas' from _cortado)) p
    where (p->>'professor_id')::integer = -41001);

-- ── Contrato do retorno ────────────────────────────────────────────────────
insert into _res select 'a funcao declara de onde leu', 'vw_registro_pendencia (cobravel)',
  (select j->>'fonte' from _piloto);

insert into _res select 'limite_dias volta no retorno', '3',
  (select j->>'limite_dias' from _piloto);

-- ── Permissao: quem manda no grupo e o worker, nao o app ───────────────────
insert into _res select 'authenticated nao executa a funcao', 'sem privilegio',
  case when has_function_privilege('authenticated',
         'public.fn_pendencias_escalonadas(integer,integer,integer)', 'execute')
       then 'EXECUTA — professor consulta pendencia dos colegas' else 'sem privilegio' end;

insert into _res select 'anon nao executa a funcao', 'sem privilegio',
  case when has_function_privilege('anon',
         'public.fn_pendencias_escalonadas(integer,integer,integer)', 'execute')
       then 'EXECUTA' else 'sem privilegio' end;

insert into _res select 'service_role executa (e o worker do Fabio)', 'executa',
  case when has_function_privilege('service_role',
         'public.fn_pendencias_escalonadas(integer,integer,integer)', 'execute')
       then 'executa' else 'NAO EXECUTA — o escalonamento nao roda' end;

-- A 040 dropou a assinatura de 1 argumento de proposito: duas versoes
-- conviveriam e o worker poderia chamar a antiga sem ninguem perceber.
insert into _res select 'a assinatura antiga de 1 argumento nao existe mais', '0',
  (select count(*)::text from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname = 'fn_pendencias_escalonadas'
      and pronargs = 1);

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
