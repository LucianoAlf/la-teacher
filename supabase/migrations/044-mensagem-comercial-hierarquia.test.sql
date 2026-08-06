-- Teste da 044 — o interno fica DEPOIS da regua, e escrito que e interno
--
-- O passo que carrega peso e o de POSICAO. Conferir que a leitura de conversao
-- "aparece no corpo" nao prova nada: ela sempre apareceu. O que protege a
-- familia e ela estar depois do marcador, num bloco que o consultor enxerga
-- como separado antes de dar Ctrl+C.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000000440', 'ZZTESTE unidade 044', 'ZZTESTE044')
on conflict (id) do nothing;
insert into public.unidade_contato_comercial (unidade_id, nome, whatsapp)
values ('00000000-0000-4000-8000-000000000440', 'ZZTESTE Comercial 044', '5521900000044')
on conflict (unidade_id) do nothing;
insert into public.professores (id, nome) values (-44001, 'ZZTESTE Professor 044');
insert into public.leads (id, unidade_id, whatsapp, status) values
  (-44001, '00000000-0000-4000-8000-000000000440', '5521999440001', 'novo'),
  (-44002, '00000000-0000-4000-8000-000000000440', '5521999440002', 'novo');

-- Data FIXA (quinta, 06/08/2026, 16:00 BRT) pra o dia da semana e a hora serem
-- assercao de verdade, e nao "o que der no dia em que rodar".
insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id)
values
  (-44001, -44001, 'ZZTESTE Helena Prado', '00000000-0000-4000-8000-000000000440',
   date '2026-08-06', '16:00', 'experimental_agendada', -44001),
  (-44002, -44002, 'ZZTESTE Faltou 044',   '00000000-0000-4000-8000-000000000440',
   date '2026-08-06', '17:00', 'experimental_agendada', -44001);
insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, categoria, professor_id, cancelada)
values
  (-44001, -944001, '00000000-0000-4000-8000-000000000440', date '2026-08-06',
   (date '2026-08-06' + time '16:00') at time zone 'America/Sao_Paulo', 'experimental', -44001, false),
  (-44002, -944002, '00000000-0000-4000-8000-000000000440', date '2026-08-06',
   (date '2026-08-06' + time '17:00') at time zone 'America/Sao_Paulo', 'experimental', -44001, false);
insert into public.lead_experimental_aulas
  (lead_experimental_id, aula_local_id, estado, casado_por, presenca_status, presenca_respondido_por)
values (-44001, -44001, 'vinculado', 'chave_natural', 'presente', 'professor_la_teacher'),
       (-44002, -44002, 'vinculado', 'chave_natural', 'falta',    'professor_la_teacher');

create temp table _msg(quem text, corpo text) on commit drop;

do $$
declare v_vinc bigint; v_reg uuid;
begin
  select id into v_vinc from lead_experimental_aulas where lead_experimental_id=-44001;
  select public.fn_registrar_experimental_interno(v_vinc,
    'postura e respiracao', 'ELA SE SOLTOU E CANTOU ALTO',
    'REPERTORIO QUE ELA GOSTA', 'MAE PERGUNTOU O PRECO DUAS VEZES') into v_reg;
  perform public.fabio_claim_aviso_comercial(v_reg);
  insert into _msg select 'presente', corpo from fabio_notificacoes
   where referencia_tipo='lead_experimental_registro' and referencia_id=v_reg::text;

  select id into v_vinc from lead_experimental_aulas where lead_experimental_id=-44002;
  select public.fn_registrar_experimental_interno(v_vinc, 'a','b','c','d') into v_reg;
  perform public.fabio_claim_aviso_comercial(v_reg);
  insert into _msg select 'faltou', corpo from fabio_notificacoes
   where referencia_tipo='lead_experimental_registro' and referencia_id=v_reg::text;
end $$;

-- ── A FRONTEIRA: o interno vem depois do marcador, sempre ─────────────────
insert into _res select 'o bloco interno e marcado como interno', 'sim',
  (select case when corpo like '%uso interno, não encaminhar%' then 'sim'
               else 'NAO — o consultor nao tem como saber o que nao repassar' end
     from _msg where quem='presente');

insert into _res select 'a leitura de conversao vem DEPOIS do marcador', 'depois',
  (select case when position('MAE PERGUNTOU O PRECO DUAS VEZES' in corpo)
                  > position('uso interno' in corpo)
               then 'depois'
               else 'ANTES — vaza no Ctrl+C do consultor' end
     from _msg where quem='presente');

insert into _res select 'e depois tambem dos blocos pedagogicos', 'depois',
  (select case when position('MAE PERGUNTOU O PRECO DUAS VEZES' in corpo)
                  > position('REPERTORIO QUE ELA GOSTA' in corpo)
               then 'depois' else 'ANTES' end
     from _msg where quem='presente');

insert into _res select 'ha regua separando os blocos', '2',
  (select (length(corpo) - length(replace(corpo, '━━━━━━━━━━━━━━', '')))
          / length('━━━━━━━━━━━━━━')
     from _msg where quem='presente')::text;

-- ── Acentuacao: era o defeito visivel no primeiro tiro real ───────────────
insert into _res select 'Presenca virou presença (com cedilha)', 'sim',
  (select case when corpo like '%presente ✅%' then 'sim' else 'nao' end
     from _msg where quem='presente');
insert into _res select 'Proximos virou Próximos', 'sim',
  (select case when corpo like '%Próximos passos%' then 'sim' else 'nao' end
     from _msg where quem='presente');
insert into _res select 'e nao sobrou nenhum "Presenca" sem cedilha', 'nao sobrou',
  (select case when corpo like '%Presenca%' then 'SOBROU' else 'nao sobrou' end
     from _msg where quem='presente');

-- ── Quem, quando, e em portugues ──────────────────────────────────────────
insert into _res select 'o nome do aluno vai em destaque', 'sim',
  (select case when corpo like '%*ZZTESTE Helena Prado*%' then 'sim' else 'nao' end
     from _msg where quem='presente');
insert into _res select 'dia da semana em portugues, sem depender de locale', 'sim',
  (select case when corpo like '%quinta%' then 'sim'
               when corpo like '%Thursday%' then 'NAO — to_char pegou locale do servidor'
               else 'nao' end
     from _msg where quem='presente');
insert into _res select 'data e hora em BRT', 'sim',
  (select case when corpo like '%06/08 · 16:00%' then 'sim' else 'nao' end
     from _msg where quem='presente');

-- ── Falta nao pode parecer presenca ───────────────────────────────────────
insert into _res select 'quem faltou aparece como faltou', 'sim',
  (select case when corpo like '%faltou ❌%' then 'sim' else 'nao' end
     from _msg where quem='faltou');
insert into _res select 'e quem faltou NAO aparece como presente', 'nao aparece',
  (select case when corpo like '%presente ✅%' then 'APARECE — falta virou presenca'
               else 'nao aparece' end
     from _msg where quem='faltou');

-- ── O conteudo continua chegando inteiro ──────────────────────────────────
insert into _res select 'a devolutiva pedagogica vai na mensagem', 'sim',
  (select case when corpo like '%ELA SE SOLTOU E CANTOU ALTO%' then 'sim' else 'nao' end
     from _msg where quem='presente');
insert into _res select 'a leitura de conversao NAO sumiu na reforma', 'sim',
  (select case when corpo like '%MAE PERGUNTOU O PRECO DUAS VEZES%' then 'sim'
               else 'NAO — o comercial perdeu o que ele mais precisa' end
     from _msg where quem='presente');

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
