-- Teste da 046 — a dica passa pela lista branca, e passa como TEXTO
--
-- O teste da 045 ja cobre posse e a fronteira do sinal comercial; este cobre
-- o que a 046 muda: de onde a dica vem e em que forma ela chega. O caso que
-- carrega peso e o do LLM devolvendo OBJETO em vez de string — porque e o
-- unico jeito de uma chave inventada por modelo atravessar uma lista branca
-- que so lista nomes.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

-- ── Nivel 1: a lista branca, sozinha ──────────────────────────────────────
insert into _res select 'a dica atravessa a lista branca', 'DEIXE ELA ESCOLHER A MUSICA',
  coalesce(public.fn_experimental_contexto_seguro(
    jsonb_build_object('como_conduzir','DEIXE ELA ESCOLHER A MUSICA')) ->> 'como_conduzir', '(nulo)');

-- LLM devolvendo objeto: `->>` transforma em texto. Sem isso, as chaves que
-- ele inventou entrariam inteiras — e a lista branca teria um buraco do
-- tamanho de um objeto.
insert into _res select 'objeto do LLM vira TEXTO, nao objeto', 'string',
  jsonb_typeof(public.fn_experimental_contexto_seguro(
    jsonb_build_object('como_conduzir',
      jsonb_build_object('dica','x','preco_que_a_mae_falou','R$ 450'))) -> 'como_conduzir');

insert into _res select 'sem dica, a chave nem aparece', 'ausente',
  case when public.fn_experimental_contexto_seguro(
         jsonb_build_object('ganchos_de_conexao', jsonb_build_array('a'))) ? 'como_conduzir'
       then 'APARECE VAZIA' else 'ausente' end;

-- A 046 nao pode ter comido nada do que ja passava.
insert into _res select 'os ganchos continuam passando', '2',
  coalesce(jsonb_array_length(public.fn_experimental_contexto_seguro(
    jsonb_build_object('ganchos_de_conexao', jsonb_build_array('a','b'))) -> 'ganchos_de_conexao')::text, '(nulo)');
insert into _res select 'o porque do sinal continua barrado', 'ausente',
  case when public.fn_experimental_contexto_seguro(
         jsonb_build_object('para_a_devolutiva',
           jsonb_build_object('porque','PRECO','o_que_a_familia_espera','x')))::text like '%PRECO%'
       then 'VAZOU' else 'ausente' end;

-- ── Nivel 2: a RPC do professor ───────────────────────────────────────────
insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000000460', 'ZZTESTE unidade 046', 'ZZTESTE046')
on conflict (id) do nothing;
insert into public.usuarios (id, nome, email, auth_user_id) values
  (-46901, 'ZZTESTE Dono 046', 'zz-dono-046@exemplo.invalido', '00000000-0000-4000-8000-000000046901');
insert into public.professores (id, nome, usuario_id) values (-46001, 'ZZTESTE Professor 046', -46901);
insert into public.leads (id, unidade_id, whatsapp, status) values
  (-46001, '00000000-0000-4000-8000-000000000460', '5521999460001', 'novo');
insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id, contexto_ia)
values (-46001, -46001, 'ZZTESTE Helena 046', '00000000-0000-4000-8000-000000000460',
   date '2026-08-06', '16:00', 'experimental_agendada', -46001,
   jsonb_build_object(
     'ganchos_de_conexao', jsonb_build_array('CANTA NO CHUVEIRO'),
     'para_a_devolutiva', jsonb_build_object('atencao_conversao','quente','porque','PRECO 3X'),
     'como_conduzir','DEIXE ELA ESCOLHER A MUSICA'));
insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, categoria, curso_nome, professor_id, cancelada)
values (-46001, -946001, '00000000-0000-4000-8000-000000000460', date '2026-08-06',
   (date '2026-08-06' + time '16:00') at time zone 'America/Sao_Paulo', 'experimental',
   'ZZTESTE Canto', -46001, false);
insert into public.lead_experimental_aulas (lead_experimental_id, aula_local_id, estado, casado_por)
values (-46001, -46001, 'vinculado', 'chave_natural');

create temp table _r(j jsonb) on commit drop;
do $$
declare v_id bigint; v_out jsonb;
begin
  select id into v_id from lead_experimental_aulas where lead_experimental_id=-46001;
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000046901"}',true);
  select public.app_experimental_do_professor(v_id) into v_out;
  reset role;
  insert into _r values (v_out);
end $$;

insert into _res select 'a dica chega na tela do professor', 'DEIXE ELA ESCOLHER A MUSICA',
  (select coalesce(j->>'como_conduzir','(nulo)') from _r);

-- Vivia em dois lugares no mesmo payload antes: dentro de `contexto` e no topo.
-- Dois lugares e um deles ficar velho e a mesma coisa.
insert into _res select 'e mora num lugar so no payload', 'so no topo',
  (select case when (j->'contexto') ? 'como_conduzir' then 'DUPLICADA' else 'so no topo' end from _r);

insert into _res select 'o sinal comercial segue fora', 'ausente',
  (select case when j::text like '%quente%' then 'VAZOU' else 'ausente' end from _r);
insert into _res select 'e o preco segue fora', 'ausente',
  (select case when j::text like '%PRECO 3X%' then 'VAZOU' else 'ausente' end from _r);
insert into _res select 'o gancho pedagogico segue chegando', 'sim',
  (select case when j::text like '%CANTA NO CHUVEIRO%' then 'sim' else 'nao' end from _r);

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
