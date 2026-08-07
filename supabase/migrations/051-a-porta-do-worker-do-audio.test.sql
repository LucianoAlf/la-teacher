-- Teste da 051 — a porta do worker do áudio
--
-- Dois passos aqui não são sobre o worker funcionar, e sim sobre ele não
-- estragar coisa alheia:
--
--   • "o claim NAO pega audio de aula comum" — as duas filas moram na mesma
--     tabela desde a 050. Se este worker roubar a linha do Hermes, o registro
--     por áudio do dia a dia (25 áudios só do Matheus) para de existir, e para
--     de existir em silêncio: a linha some pra 'transcrevendo' e ninguém liga
--     o sumiço a esta migration.
--
--   • "o claim nao leva o briefing pedagogico" — se o contexto viajar junto, o
--     modelo preenche buraco com ele e o registro deixa de ser o que o
--     professor falou. Fica escrito bonito e não é verdade.

create temp table _res(passo text, esperado text, obtido text) on commit drop;
create temp table _erros(passo text, msg text) on commit drop;
grant select, insert on _erros to authenticated, anon;

-- ── Fixture ─────────────────────────────────────────────────────────────────
insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000000510', 'ZZTESTE unidade 051', 'ZZTESTE051')
on conflict (id) do nothing;

insert into public.usuarios (id, nome, email, auth_user_id) values
  (-51901, 'ZZTESTE Dono 051', 'zz-dono-051@exemplo.invalido', '00000000-0000-4000-8000-000000051901');
insert into public.professores (id, nome, usuario_id) values (-51001, 'ZZTESTE Professor 051', -51901);

insert into public.leads (id, unidade_id, whatsapp, status)
select v.id, '00000000-0000-4000-8000-000000000510', '552199951000' || abs(v.id) % 10, 'novo'
  from (values (-51001), (-51002), (-51003), (-51004), (-51005)) as v(id);

insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id, contexto_ia)
select v.id, v.id, 'ZZTESTE Helena 051 #' || abs(v.id),
       '00000000-0000-4000-8000-000000000510',
       (now() at time zone 'America/Sao_Paulo')::date, '16:00',
       'experimental_agendada', -51001,
       jsonb_build_object(
         'quem_e_esse_aluno', jsonb_build_object('historia','SEGREDO-DO-BRIEFING'),
         'para_a_devolutiva', jsonb_build_object('atencao_conversao','alta'),
         'como_conduzir', 'SEGREDO-DA-DICA')
  from (values (-51001), (-51002), (-51003), (-51004), (-51005)) as v(id);

insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, data_hora_fim,
   categoria, curso_nome, professor_id, cancelada)
select v.id, v.id * 10, '00000000-0000-4000-8000-000000000510',
       (now() at time zone 'America/Sao_Paulo')::date,
       now() - interval '1 hour', now() - interval '10 minutes',
       'experimental', 'ZZTESTE Canto', -51001, false
  from (values (-51001), (-51002), (-51003), (-51004), (-51005), (-51006)) as v(id);

insert into public.lead_experimental_aulas (id, lead_experimental_id, aula_local_id, estado, casado_por)
select v.id, v.id, v.id, 'vinculado', 'chave_natural'
  from (values (-51001), (-51002), (-51003), (-51004), (-51005)) as v(id);

-- ── A fila, montada à mão pra cada caso ─────────────────────────────────────
-- `atualizado_em` vem do INSERT porque o gatilho fn_set_atualizado_em só age
-- em UPDATE — dá pra plantar uma linha "velha" sem depender de relógio.
insert into public.fabio_fila_audios
  (id, professor_id, unidade_id, aula_id, vinculo_id, storage_path, duracao_segundos,
   origem, status, tentativas, criado_em, atualizado_em)
values
  -- 1: o caso feliz
  ('00000000-0000-4000-8000-000000051001', -51001, '00000000-0000-4000-8000-000000000510',
   -51001, -51001, 'zz/051/feliz.webm', 40, 'app', 'pendente', 0,
   now() - interval '1 minute', now() - interval '1 minute'),
  -- 2: preso há 20 min — a retomada tem que pegar
  ('00000000-0000-4000-8000-000000051002', -51001, '00000000-0000-4000-8000-000000000510',
   -51002, -51002, 'zz/051/preso.webm', 40, 'app', 'transcrevendo', 1,
   now() - interval '30 minutes', now() - interval '20 minutes'),
  -- 3: preso há 2 min — ainda é de alguém, não pode ser roubado
  ('00000000-0000-4000-8000-000000051003', -51001, '00000000-0000-4000-8000-000000000510',
   -51003, -51003, 'zz/051/recente.webm', 40, 'app', 'transcrevendo', 1,
   now() - interval '10 minutes', now() - interval '2 minutes'),
  -- 4: gastou as três tentativas — sai de circulação
  ('00000000-0000-4000-8000-000000051004', -51001, '00000000-0000-4000-8000-000000000510',
   -51004, -51004, 'zz/051/perdido.webm', 40, 'app', 'transcrevendo', 3,
   now() - interval '2 hours', now() - interval '90 minutes'),
  -- 5: AULA COMUM (sem vinculo) — é do Hermes, este worker não encosta
  ('00000000-0000-4000-8000-000000051006', -51001, '00000000-0000-4000-8000-000000000510',
   -51006, null, 'zz/051/comum.webm', 40, 'app', 'pendente', 0,
   now() - interval '5 minutes', now() - interval '5 minutes');

-- O caso 5 (vinculo -51005) tem registro digitado à mão ANTES do áudio: é ele
-- que prova que gravar não apaga.
insert into public.lead_experimental_registros
  (vinculo_id, unidade_id, professor_id, anotacao_pedagogica, devolutiva_familia,
   proximos_passos, leitura_de_conversao, origem, status)
values (-51005, '00000000-0000-4000-8000-000000000510', -51001,
  'DIGITADO-PEDAGOGICA', 'DIGITADO-FAMILIA', 'DIGITADO-PROXIMOS', 'DIGITADO-CONVERSAO',
  'app', 'aguardando_confirmacao');

insert into public.fabio_fila_audios
  (id, professor_id, unidade_id, aula_id, vinculo_id, storage_path, duracao_segundos,
   origem, status, tentativas, criado_em, atualizado_em)
values
  ('00000000-0000-4000-8000-000000051005', -51001, '00000000-0000-4000-8000-000000000510',
   -51005, -51005, 'zz/051/preserva.webm', 40, 'app', 'pendente', 0,
   now() - interval '3 minutes', now() - interval '3 minutes');

-- ═══════════════════════════════════════════════════════════════════════════
-- 1) O claim
-- ═══════════════════════════════════════════════════════════════════════════
create temp table _claim(j jsonb) on commit drop;
insert into _claim select public.fabio_claim_audio_experimental(10);

insert into _res select 'o claim pega o pendente da experimental', 'sim',
  (select case when j::text like '%zz/051/feliz.webm%' then 'sim' else 'nao' end from _claim);

insert into _res select 'e retoma o que ficou preso 20min', 'sim',
  (select case when j::text like '%zz/051/preso.webm%' then 'sim' else 'nao' end from _claim);

insert into _res select 'mas NAO rouba o que esta preso ha 2min', 'nao',
  (select case when j::text like '%zz/051/recente.webm%' then 'sim' else 'nao' end from _claim);

insert into _res select 'nem o que ja gastou as 3 tentativas', 'nao',
  (select case when j::text like '%zz/051/perdido.webm%' then 'sim' else 'nao' end from _claim);

insert into _res select 'e o esgotado vira erro (para de circular)', 'erro',
  (select status from public.fabio_fila_audios where id = '00000000-0000-4000-8000-000000051004');

-- O passo que protege a fila do Hermes.
insert into _res select 'o claim NAO pega audio de aula comum', 'nao',
  (select case when j::text like '%zz/051/comum.webm%' then 'sim' else 'nao' end from _claim);

insert into _res select 'e a aula comum continua pendente pro Hermes', 'pendente',
  (select status from public.fabio_fila_audios where id = '00000000-0000-4000-8000-000000051006');

insert into _res select 'o que foi pego fica em transcrevendo', 'transcrevendo',
  (select status from public.fabio_fila_audios where id = '00000000-0000-4000-8000-000000051001');

insert into _res select 'e a tentativa e contada', '1',
  (select tentativas::text from public.fabio_fila_audios where id = '00000000-0000-4000-8000-000000051001');

insert into _res select 'o claim leva o nome do aluno', 'sim',
  (select case when j::text like '%ZZTESTE Helena 051%' then 'sim' else 'nao' end from _claim);

insert into _res select 'e o que ja estava escrito (pra nao apagar)', 'sim',
  (select case when j::text like '%DIGITADO-PEDAGOGICA%' then 'sim' else 'nao' end from _claim);

-- A fronteira: o briefing fica em casa.
insert into _res select 'o claim nao leva o briefing pedagogico', 'nao',
  (select case when j::text like '%SEGREDO-DO-BRIEFING%' or j::text like '%SEGREDO-DA-DICA%'
                 or j::text like '%atencao_conversao%'
          then 'sim' else 'nao' end from _claim);

-- ═══════════════════════════════════════════════════════════════════════════
-- 2) Gravar
-- ═══════════════════════════════════════════════════════════════════════════
create temp table _grav(rotulo text, j jsonb) on commit drop;

insert into _grav
select 'feliz', public.fabio_gravar_registro_experimental_de_audio(
  '00000000-0000-4000-8000-000000051001',
  'TRANSCRICAO CRUA DO PROFESSOR',
  jsonb_build_object(
    'anotacao_pedagogica',  'DO AUDIO pedagogica',
    'devolutiva_familia',   'DO AUDIO familia',
    'proximos_passos',      'DO AUDIO proximos',
    'leitura_de_conversao', 'DO AUDIO conversao',
    'campo_inventado',      'NAO DEVE ENTRAR'));

insert into _res select 'gravar cria o registro aguardando confirmacao', 'aguardando_confirmacao',
  (select r.status from public.lead_experimental_registros r where r.vinculo_id = -51001);

insert into _res select 'com os quatro campos do audio', '4',
  (select ((r.anotacao_pedagogica  = 'DO AUDIO pedagogica')::int
         + (r.devolutiva_familia   = 'DO AUDIO familia')::int
         + (r.proximos_passos      = 'DO AUDIO proximos')::int
         + (r.leitura_de_conversao = 'DO AUDIO conversao')::int)::text
     from public.lead_experimental_registros r where r.vinculo_id = -51001);

insert into _res select 'e carimbado com o audio de origem', 'sim',
  (select case when r.audio_id = '00000000-0000-4000-8000-000000051001' then 'sim' else 'nao' end
     from public.lead_experimental_registros r where r.vinculo_id = -51001);

insert into _res select 'a fila fecha como normalizado', 'normalizado',
  (select status from public.fabio_fila_audios where id = '00000000-0000-4000-8000-000000051001');

insert into _res select 'e guarda a transcricao como evidencia', 'TRANSCRICAO CRUA DO PROFESSOR',
  (select transcricao from public.fabio_fila_audios where id = '00000000-0000-4000-8000-000000051001');

-- Lista branca: chave desconhecida não vira campo.
insert into _res select 'campo fora da lista branca nao entra', 'nao',
  (select case when r::text like '%NAO DEVE ENTRAR%' then 'sim' else 'nao' end
     from public.lead_experimental_registros r where r.vinculo_id = -51001);

-- ── Preservação: o áudio só falou de UM campo ───────────────────────────────
insert into _grav
select 'preserva', public.fabio_gravar_registro_experimental_de_audio(
  '00000000-0000-4000-8000-000000051005',
  'so falei de como foi',
  jsonb_build_object('anotacao_pedagogica', 'DO AUDIO so essa'));

insert into _res select 'o campo que o audio cobriu e substituido', 'DO AUDIO so essa',
  (select anotacao_pedagogica from public.lead_experimental_registros where vinculo_id = -51005);

insert into _res select 'e os TRES que ele nao cobriu sobrevivem', '3',
  (select ((devolutiva_familia   = 'DIGITADO-FAMILIA')::int
         + (proximos_passos      = 'DIGITADO-PROXIMOS')::int
         + (leitura_de_conversao = 'DIGITADO-CONVERSAO')::int)::text
     from public.lead_experimental_registros where vinculo_id = -51005);

-- ── Recusas ─────────────────────────────────────────────────────────────────
do $$
begin
  begin
    perform public.fabio_gravar_registro_experimental_de_audio(
      '00000000-0000-4000-8000-000000051002', '   ', '{}'::jsonb);
    insert into _erros values ('sem transcricao', 'NAO LEVANTOU');
  exception when others then insert into _erros values ('sem transcricao', sqlerrm);
  end;

  begin
    perform public.fabio_gravar_registro_experimental_de_audio(
      '00000000-0000-4000-8000-000000051006', 'texto', '{}'::jsonb);
    insert into _erros values ('audio de aula comum', 'NAO LEVANTOU');
  exception when others then insert into _erros values ('audio de aula comum', sqlerrm);
  end;
end $$;

insert into _res select 'gravar recusa normalizar sem evidencia', 'transcricao_obrigatoria',
  (select case when msg like '%transcricao_obrigatoria%' then 'transcricao_obrigatoria' else msg end
     from _erros where passo='sem transcricao');

insert into _res select 'gravar recusa audio que nao e de experimental', 'audio_nao_e_de_experimental',
  (select case when msg like '%audio_nao_e_de_experimental%' then 'audio_nao_e_de_experimental' else msg end
     from _erros where passo='audio de aula comum');

-- ═══════════════════════════════════════════════════════════════════════════
-- 3) Desistir avisando
-- ═══════════════════════════════════════════════════════════════════════════
create temp table _falhou(rotulo text, j jsonb) on commit drop;

-- -51002 foi retomado no claim: tentativas subiu pra 2. Falhar agora devolve
-- pra fila (ainda tem chance).
insert into _falhou select 'segunda',
  public.fabio_falhou_audio_experimental('00000000-0000-4000-8000-000000051002', 'whisper caiu');

insert into _res select 'falha antes da 3a devolve pra fila', 'pendente',
  (select status from public.fabio_fila_audios where id = '00000000-0000-4000-8000-000000051002');

insert into _res select 'e o motivo fica escrito', 'whisper caiu',
  (select erro from public.fabio_fila_audios where id = '00000000-0000-4000-8000-000000051002');

-- Agora leva pra 3 e falha de novo: vira erro e para.
update public.fabio_fila_audios set tentativas = 3
 where id = '00000000-0000-4000-8000-000000051002';
insert into _falhou select 'terceira',
  public.fabio_falhou_audio_experimental('00000000-0000-4000-8000-000000051002', 'whisper caiu de novo');

insert into _res select 'na 3a falha para de circular', 'erro',
  (select status from public.fabio_fila_audios where id = '00000000-0000-4000-8000-000000051002');

-- ═══════════════════════════════════════════════════════════════════════════
-- 4) Quem NÃO pode
-- ═══════════════════════════════════════════════════════════════════════════
do $$
begin
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000051901"}',true);

  begin
    perform public.fabio_claim_audio_experimental(1);
    insert into _erros values ('prof no claim', 'NAO LEVANTOU');
  exception when others then insert into _erros values ('prof no claim', sqlerrm);
  end;

  begin
    perform public.fabio_gravar_registro_experimental_de_audio(
      '00000000-0000-4000-8000-000000051003', 'x', '{}'::jsonb);
    insert into _erros values ('prof no gravar', 'NAO LEVANTOU');
  exception when others then insert into _erros values ('prof no gravar', sqlerrm);
  end;

  begin
    perform public.fabio_falhou_audio_experimental('00000000-0000-4000-8000-000000051003', 'x');
    insert into _erros values ('prof no falhou', 'NAO LEVANTOU');
  exception when others then insert into _erros values ('prof no falhou', sqlerrm);
  end;

  reset role;
end $$;

insert into _res select 'professor nao mexe na fila do worker', '3',
  (select count(*)::text from _erros
    where passo in ('prof no claim','prof no gravar','prof no falhou')
      and msg <> 'NAO LEVANTOU');

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
