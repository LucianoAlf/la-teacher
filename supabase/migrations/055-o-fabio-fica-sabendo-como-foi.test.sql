-- Teste da 055 — o Fábio fica sabendo como a experimental foi
--
-- Este teste COMPARA os dois caminhos do professor sobre a mesma experimental,
-- como o da 049 — porque foi exatamente a falta dessa comparação que deixou
-- uma divergência viver antes: cada caminho passava no seu próprio teste.
--
-- A diferença é que agora eu espero uma ASSIMETRIA declarada, não igualdade:
-- os três campos pedagógicos aparecem nos dois, e a leitura de conversão só na
-- tela. Um teste que exigisse igualdade aprovaria o vazamento; um que só olhasse
-- o Fábio aprovaria o corte excessivo. Os dois lados precisam de passo.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000000550', 'ZZTESTE unidade 055', 'ZZTESTE055')
on conflict (id) do nothing;

insert into public.usuarios (id, nome, email, auth_user_id) values
  (-55901, 'ZZTESTE Dono 055', 'zz-dono-055@exemplo.invalido', '00000000-0000-4000-8000-000000055901');
insert into public.professores (id, nome, usuario_id) values (-55001, 'ZZTESTE Prof 055', -55901);

insert into public.leads (id, unidade_id, whatsapp, status)
select v.id, '00000000-0000-4000-8000-000000000550', '55219995500' || abs(v.id) % 100, 'novo'
  from (values (-55001), (-55002)) as v(id);

insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id, contexto_ia)
select v.id, v.id, 'ZZTESTE Aluno 055 #' || abs(v.id),
       '00000000-0000-4000-8000-000000000550',
       (now() at time zone 'America/Sao_Paulo')::date, '16:00',
       'experimental_agendada', -55001,
       jsonb_build_object(
         'quem_e_esse_aluno', jsonb_build_object('historia','CANTA NO CHUVEIRO'),
         'para_a_devolutiva', jsonb_build_object('atencao_conversao','alta'),
         'como_conduzir', 'DEIXE ELA ESCOLHER')
  from (values (-55001), (-55002)) as v(id);

insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, data_hora_fim,
   categoria, curso_nome, professor_id, cancelada)
select v.id, v.id * 10, '00000000-0000-4000-8000-000000000550',
       (now() at time zone 'America/Sao_Paulo')::date,
       ((now() at time zone 'America/Sao_Paulo')::date + time '16:00') at time zone 'America/Sao_Paulo',
       ((now() at time zone 'America/Sao_Paulo')::date + time '17:00') at time zone 'America/Sao_Paulo',
       'experimental', 'ZZTESTE Canto', -55001, false
  from (values (-55001), (-55002)) as v(id);

insert into public.lead_experimental_aulas
  (id, lead_experimental_id, aula_local_id, estado, casado_por, presenca_status, presenca_respondido_por)
values
  -- 1: aconteceu e foi registrada
  (-55001, -55001, -55001, 'realizado', 'chave_natural', 'presente', 'professor_la_teacher'),
  -- 2: ainda não aconteceu — nada de registro
  (-55002, -55002, -55002, 'vinculado', 'chave_natural', null, null);

insert into public.lead_experimental_registros
  (vinculo_id, unidade_id, professor_id, anotacao_pedagogica, devolutiva_familia,
   proximos_passos, leitura_de_conversao, origem, status, audio_id)
values (-55001, '00000000-0000-4000-8000-000000000550', -55001,
  'PEDAGOGICA DO PROFESSOR', 'FAMILIA DO PROFESSOR', 'PROXIMOS DO PROFESSOR',
  'A MAE PERGUNTOU O PRECO', 'app', 'confirmado', null);

create temp table _c(caminho text, j jsonb) on commit drop;

-- caminho 1: a TELA (045)
do $$
declare v_out jsonb;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000055901"}',true);
  select public.app_experimental_do_professor(-55001) into v_out;
  reset role;
  insert into _c values ('tela', v_out);
end $$;

-- caminho 2: o FÁBIO no WhatsApp
insert into _c
select 'fabio', j from (
  select value as j from jsonb_array_elements(public.fabio_experimentais_do_professor(-55001, 7))
   where (value->>'lead_experimental_id')::integer = -55001) s;

insert into _c
select 'fabio_sem_aula', j from (
  select value as j from jsonb_array_elements(public.fabio_experimentais_do_professor(-55001, 7))
   where (value->>'lead_experimental_id')::integer = -55002) s;

-- ── O Fábio para de negar o capítulo ────────────────────────────────────────
insert into _res select 'o Fabio sabe que houve registro', 'sim',
  (select case when j -> 'registro' is not null and j -> 'registro' <> 'null'::jsonb
          then 'sim' else 'nao' end from _c where caminho='fabio');

insert into _res select 'e sabe que foi confirmado', 'true',
  (select j -> 'registro' ->> 'confirmado' from _c where caminho='fabio');

insert into _res select 'e leva o que aconteceu na aula', 'sim',
  (select case when j::text like '%PEDAGOGICA DO PROFESSOR%' then 'sim' else 'nao' end
     from _c where caminho='fabio');

insert into _res select 'e o que foi dito pra familia', 'sim',
  (select case when j::text like '%FAMILIA DO PROFESSOR%' then 'sim' else 'nao' end
     from _c where caminho='fabio');

insert into _res select 'e os proximos passos', 'sim',
  (select case when j::text like '%PROXIMOS DO PROFESSOR%' then 'sim' else 'nao' end
     from _c where caminho='fabio');

insert into _res select 'e a presenca', 'presente',
  (select j ->> 'presenca' from _c where caminho='fabio');

-- ── A assimetria DECLARADA ──────────────────────────────────────────────────
insert into _res select 'a tela mostra a leitura de conversao (e dele)', 'sim',
  (select case when j::text like '%A MAE PERGUNTOU O PRECO%' then 'sim' else 'nao' end
     from _c where caminho='tela');

insert into _res select 'e o Fabio NAO leva a leitura de conversao', 'barrado',
  (select case when j::text like '%A MAE PERGUNTOU O PRECO%' then 'VAZOU' else 'barrado' end
     from _c where caminho='fabio');

-- O corte da 049 continua valendo — não pode ter sido desfeito na reescrita.
insert into _res select 'e o sinal de conversao continua barrado nos dois', 'barrado',
  (select case when bool_or(j::text like '%atencao_conversao%') then 'VAZOU' else 'barrado' end
     from _c where caminho in ('tela','fabio'));

-- ── Aula que não aconteceu: registro nulo, não inventado ────────────────────
insert into _res select 'sem registro, o campo vem nulo (nao vazio)', 'nulo',
  (select case when j -> 'registro' = 'null'::jsonb then 'nulo' else j -> 'registro' #>> '{}' end
     from _c where caminho='fabio_sem_aula');

insert into _res select 'e a presenca dela tambem', 'nulo',
  (select case when j -> 'presenca' = 'null'::jsonb then 'nulo' else j ->> 'presenca' end
     from _c where caminho='fabio_sem_aula');

-- ── Uma linha por experimental: o LEFT JOIN não pode multiplicar ────────────
-- lead_experimental_aulas guarda o histórico de vínculos substituídos. Sem o
-- filtro `substituido_em is null`, uma experimental remarcada apareceria duas
-- vezes na resposta do Fábio, com dois registros diferentes.
insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, data_hora_fim,
   categoria, curso_nome, professor_id, cancelada)
values (-55003, -550030, '00000000-0000-4000-8000-000000000550',
  (now() at time zone 'America/Sao_Paulo')::date,
  ((now() at time zone 'America/Sao_Paulo')::date + time '15:00') at time zone 'America/Sao_Paulo',
  ((now() at time zone 'America/Sao_Paulo')::date + time '16:00') at time zone 'America/Sao_Paulo',
  'experimental', 'ZZTESTE Canto', -55001, false);
insert into public.lead_experimental_aulas
  (id, lead_experimental_id, aula_local_id, estado, casado_por, substituido_em)
values (-55003, -55001, -55003, 'vinculado', 'chave_natural', now());

insert into _res select 'vinculo substituido nao duplica a experimental', '1',
  (select count(*)::text from jsonb_array_elements(
            public.fabio_experimentais_do_professor(-55001, 7)) e
    where (e.value ->> 'lead_experimental_id')::integer = -55001);

-- ── A guarda de posse da 029 continua ───────────────────────────────────────
create temp table _erros(passo text, msg text) on commit drop;
do $$
begin
  begin
    perform public.fabio_experimentais_do_professor(null, 7);
    insert into _erros values ('sem professor', 'NAO LEVANTOU');
  exception when others then insert into _erros values ('sem professor', sqlerrm);
  end;
end $$;

insert into _res select 'professor nulo continua sendo recusado', 'professor_id_obrigatorio',
  (select case when msg like '%professor_id_obrigatorio%' then 'professor_id_obrigatorio' else msg end
     from _erros where passo='sem professor');

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
