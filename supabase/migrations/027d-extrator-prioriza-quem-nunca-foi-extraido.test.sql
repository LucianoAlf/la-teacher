-- Teste da 027d — a fila gira, ou o lote pega sempre os mesmos?
--
-- O CENÁRIO É DESENHADO PARA AS DUAS ORDENAÇÕES DISCORDAREM. Semeia quatro
-- experimentais numa unidade de teste:
--
--   ZZTESTE-A  aula em +1 dia   JÁ extraído (contexto_ia_em = agora)
--   ZZTESTE-B  aula em +2 dias  JÁ extraído (contexto_ia_em = ontem)
--   ZZTESTE-C  aula em +5 dias  NUNCA extraído
--   ZZTESTE-D  aula em +6 dias  NUNCA extraído
--
-- Pela ordem ANTIGA (só data): A, B, C, D — e um lote de 2 pegaria A e B, que
-- a edge function pularia por "sem_mensagem_nova". C e D nunca entrariam. Foi
-- exatamente isso que aconteceu onze vezes em produção.
--
-- Pela ordem NOVA: C, D, A, B — quem nunca foi extraído na frente, e entre os
-- extraídos o mais antigo (B antes de A) para a fila girar.
--
-- Os dois passos abaixo são o mutante: se alguém apagar a cláusula de
-- prioridade da 027d, o passo 1 acusa; se apagar só a rotação, o passo 2 acusa.
-- Verde nos dois só é possível com as duas cláusulas no lugar.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

-- Unidade e lead próprios do ensaio: nada de pendurar em dado vivo.
insert into public.unidades (id, nome, codigo)
values ('00000000-0000-4000-8000-0000000027d0', 'ZZTESTE unidade 027d', 'ZZTESTE027D')
on conflict (id) do nothing;

insert into public.leads (id, unidade_id, whatsapp, status)
values (-27401, '00000000-0000-4000-8000-0000000027d0', '5521999990000', 'novo');

insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental, status, contexto_ia, contexto_ia_em)
values
  (-27411, -27401, 'ZZTESTE-A', '00000000-0000-4000-8000-0000000027d0',
   (now() at time zone 'America/Sao_Paulo')::date + 1, '10:00', 'experimental_agendada',
   '{"procedencia":{"ultima_mensagem_id":"1"}}'::jsonb, now()),
  (-27412, -27401, 'ZZTESTE-B', '00000000-0000-4000-8000-0000000027d0',
   (now() at time zone 'America/Sao_Paulo')::date + 2, '10:00', 'experimental_agendada',
   '{"procedencia":{"ultima_mensagem_id":"2"}}'::jsonb, now() - interval '1 day'),
  (-27413, -27401, 'ZZTESTE-C', '00000000-0000-4000-8000-0000000027d0',
   (now() at time zone 'America/Sao_Paulo')::date + 5, '10:00', 'experimental_agendada',
   null, null),
  (-27414, -27401, 'ZZTESTE-D', '00000000-0000-4000-8000-0000000027d0',
   (now() at time zone 'America/Sao_Paulo')::date + 6, '10:00', 'experimental_agendada',
   null, null);

-- Limite alto de propósito: o que se mede é a ORDEM RELATIVA dos quatro entre
-- si, não quem cabe num lote. Assim o teste não depende de quantas
-- experimentais reais existem na janela hoje — que muda todo dia.
create temp view _ordem as
  select row_number() over () as pos, nome_aluno
    from public.fn_experimentais_a_extrair(30, 2000);

-- ── Passo 1: quem nunca foi extraído passa na frente ────────────────────────
insert into _res
select 'nunca-extraido primeiro',
       'C,D antes de A,B',
       case when (select max(pos) from _ordem where nome_aluno in ('ZZTESTE-C','ZZTESTE-D'))
               < (select min(pos) from _ordem where nome_aluno in ('ZZTESTE-A','ZZTESTE-B'))
            then 'C,D antes de A,B'
            else 'A ou B na frente — a fila trava nos mesmos'
       end;

-- ── Passo 2: entre os já extraídos, o mais antigo primeiro (a fila gira) ────
insert into _res
select 'rotacao pelo mais antigo',
       'B antes de A',
       case when (select pos from _ordem where nome_aluno = 'ZZTESTE-B')
              < (select pos from _ordem where nome_aluno = 'ZZTESTE-A')
            then 'B antes de A'
            else 'A antes de B — sem rotacao, os mesmos 5 sempre'
       end;

-- ── Passo 3: a janela e o status continuam valendo (não afrouxei nada) ─────
update public.lead_experimentais set status = 'cancelada' where id = -27413;
insert into _res
select 'cancelada continua fora',
       'fora',
       coalesce((select 'dentro' from public.fn_experimentais_a_extrair(30, 2000)
                  where lead_experimental_id = -27413 limit 1), 'fora');

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
