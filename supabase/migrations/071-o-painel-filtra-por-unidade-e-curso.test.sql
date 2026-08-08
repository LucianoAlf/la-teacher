-- 071 (teste) — o painel filtra por unidade e por curso
--
-- O passo que dá nome à migration é "filtrar por curso AGRUPA as modalidades".
-- Ele vem com dois vizinhos que existem só pra ele não ser decoração:
--
--   • a âncora, que exige um curso com mais de uma variante na janela — sem
--     isso agrupar e não agrupar dão o mesmo número;
--   • o contra-passo, que afirma que o total agrupado é MAIOR que o da maior
--     variante sozinha. É ele que morre se alguém trocar a chave pelo nome cru.
--
-- E tem o passo da ASSINATURA VELHA. A 070 tinha 2 argumentos; se a versão
-- antiga sobrevivesse ao lado da nova, o PostgREST recusaria toda chamada com
-- "could not choose the best candidate function" — o painel não degradaria,
-- pararia. Esse é o tipo de estrago que não aparece em teste de resultado.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

-- ─── Guardas ────────────────────────────────────────────────────────────────
do $$
declare v_erro text := 'nao levantou';
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  begin perform public.app_coordenacao_em_aberto(7, null, null);
  exception when others then v_erro := sqlerrm; end;
  insert into _res values ('sem identidade a fila recusa', 'sim',
    case when v_erro like '%apenas_admin%' then 'sim' else 'NAO — ' || v_erro end);
end $$;

do $$
declare v_erro text := 'nao levantou';
begin
  begin perform public.app_coordenacao_professor_detalhe(1, 7, null, null);
  exception when others then v_erro := sqlerrm; end;
  insert into _res values ('sem identidade o detalhe recusa', 'sim',
    case when v_erro like '%apenas_admin%' then 'sim' else 'NAO — ' || v_erro end);
end $$;

do $$
declare v_uid uuid;
begin
  select u.auth_user_id into v_uid
    from public.la_teacher_coordenacao c
    join public.usuarios u on u.id = c.usuario_id
   where u.auth_user_id is not null and coalesce(u.ativo, true) limit 1;
  insert into _res values ('ancora: ha coordenador com login', 'sim',
    case when v_uid is null then 'NAO' else 'sim' end);
  if v_uid is not null then
    perform set_config('request.jwt.claim.sub', v_uid::text, true);
  end if;
end $$;

-- ─── A CHAVE DO CURSO ───────────────────────────────────────────────────────
insert into _res select 'a chave junta as tres modalidades', 'sim',
  case when public.fn_curso_chave('Bateria')
          = public.fn_curso_chave('Bateria T')
       and public.fn_curso_chave('Bateria T')
          = public.fn_curso_chave('Bateria IND')
       then 'sim' else 'NAO' end;

insert into _res select 'a chave ignora a caixa', 'sim',
  case when public.fn_curso_chave('Musicalização para bebês')
          = public.fn_curso_chave('Musicalização Para Bebês')
       then 'sim' else 'NAO' end;

-- Não pode agrupar demais: "Teclado" e "Teoria Musical" são cursos diferentes,
-- e "Home Studio" não termina em modalidade.
insert into _res select 'a chave NAO junta cursos diferentes', 'sim',
  case when public.fn_curso_chave('Teclado') <> public.fn_curso_chave('Teoria Musical')
       and public.fn_curso_chave('Home Studio') = 'home studio'
       then 'sim' else 'NAO' end;

-- ─── Base ───────────────────────────────────────────────────────────────────
create temp table _saida on commit drop as
  select public.app_coordenacao_em_aberto(7, null, null) as j;

create temp table _janela on commit drop as
  select unidade_id, unidade_nome, curso_nome,
         public.fn_curso_chave(curso_nome) as curso_chave,
         professor_id, aula_id, data_aula
    from public.vw_presenca_pendencia
   where data_aula >= current_date - 7 and data_aula < current_date;

insert into _res select 'sem filtro, o total e o da janela inteira',
  (select count(distinct aula_id)::text from _janela),
  (select j->'resumo'->>'sem_lancamento' from _saida);

-- ─── O PASSO DESTA MIGRATION ────────────────────────────────────────────────
create temp table _curso on commit drop as
  select curso_chave,
         count(distinct aula_id)::int as aulas_agrupadas,
         count(distinct curso_nome)::int as variantes,
         (select count(distinct x.aula_id) from _janela x
           where x.curso_nome = (select y.curso_nome from _janela y
                                  where y.curso_chave = j.curso_chave
                                  group by y.curso_nome
                                  order by count(distinct y.aula_id) desc limit 1)
         )::int as aulas_da_maior_variante
    from _janela j
   where curso_chave is not null
   group by curso_chave
   order by count(distinct curso_nome) desc, count(distinct aula_id) desc
   limit 1;

insert into _res select 'ancora: ha curso com mais de uma modalidade na janela', 'sim',
  (select case when coalesce(max(variantes), 0) > 1 then 'sim'
               else 'NAO — todo curso tem 1 nome; agrupar nao falseia' end
     from _curso);

create temp table _saida_curso on commit drop as
  select public.app_coordenacao_em_aberto(7, null, (select curso_chave from _curso)) as j;

insert into _res select 'filtrar por curso AGRUPA as modalidades',
  (select aulas_agrupadas::text from _curso),
  (select j->'resumo'->>'sem_lancamento' from _saida_curso);

insert into _res select 'o total agrupado e MAIOR que o da maior variante sozinha', 'sim',
  (select case when (s.j->'resumo'->>'sem_lancamento')::int > c.aulas_da_maior_variante
               then 'sim'
               else 'NAO — filtrou por nome cru: ' ||
                    (s.j->'resumo'->>'sem_lancamento') || ' de ' ||
                    c.aulas_agrupadas::text || ' aulas do curso' end
     from _saida_curso s, _curso c);

insert into _res select 'filtrar por curso reduz o total', 'sim',
  (select case when (c.j->'resumo'->>'sem_lancamento')::int
                  < (t.j->'resumo'->>'sem_lancamento')::int then 'sim'
               else 'NAO — o filtro nao filtrou' end
     from _saida_curso c, _saida t);

-- ─── Filtro de unidade ──────────────────────────────────────────────────────
create temp table _unid on commit drop as
  select unidade_id, count(distinct aula_id)::int as aulas
    from _janela where unidade_id is not null
   group by unidade_id order by count(distinct aula_id) desc limit 1;

create temp table _saida_unid on commit drop as
  select public.app_coordenacao_em_aberto(7, (select unidade_id from _unid), null) as j;

insert into _res select 'filtrar por unidade bate com a janela',
  (select aulas::text from _unid),
  (select j->'resumo'->>'sem_lancamento' from _saida_unid);

insert into _res select 'filtrar por unidade reduz o total', 'sim',
  (select case when (u.j->'resumo'->>'sem_lancamento')::int
                  < (t.j->'resumo'->>'sem_lancamento')::int then 'sim'
               else 'NAO — o filtro nao filtrou' end
     from _saida_unid u, _saida t);

-- Combinar não pode dar mais que cada um sozinho.
create temp table _saida_ambos on commit drop as
  select public.app_coordenacao_em_aberto(
           7, (select unidade_id from _unid), (select curso_chave from _curso)) as j;

insert into _res select 'combinar os dois filtros nao aumenta o total', 'sim',
  (select case when (a.j->'resumo'->>'sem_lancamento')::int
                  <= least((u.j->'resumo'->>'sem_lancamento')::int,
                           (c.j->'resumo'->>'sem_lancamento')::int) then 'sim'
               else 'NAO — combinar deu mais que filtrar por um so' end
     from _saida_ambos a, _saida_unid u, _saida_curso c);

-- ─── Facetas ────────────────────────────────────────────────────────────────
insert into _res select 'sem filtro, as facetas listam todas as unidades',
  (select count(distinct unidade_id)::text from _janela where unidade_id is not null),
  (select jsonb_array_length(j->'filtros'->'unidades')::text from _saida);

insert into _res select 'sem filtro, as facetas listam todos os cursos agrupados',
  (select count(distinct curso_chave)::text from _janela where curso_chave is not null),
  (select jsonb_array_length(j->'filtros'->'cursos')::text from _saida);

-- O beco sem saída: escolher uma unidade não pode apagar as outras da lista.
insert into _res select 'filtrar unidade NAO apaga as outras unidades da lista',
  (select jsonb_array_length(j->'filtros'->'unidades')::text from _saida),
  (select jsonb_array_length(j->'filtros'->'unidades')::text from _saida_unid);

insert into _res select 'filtrar curso NAO apaga os outros cursos da lista',
  (select jsonb_array_length(j->'filtros'->'cursos')::text from _saida),
  (select jsonb_array_length(j->'filtros'->'cursos')::text from _saida_curso);

-- Mas a faceta CRUZADA respeita o outro filtro: a lista de cursos de uma
-- unidade não pode oferecer curso que não existe lá (clicar e ver zero).
insert into _res select 'ancora: filtrar unidade muda a lista de cursos', 'sim',
  (select case when jsonb_array_length(u.j->'filtros'->'cursos')
                  < jsonb_array_length(t.j->'filtros'->'cursos') then 'sim'
               else 'NAO — a unidade tem todos os cursos; o passo abaixo nao falseia' end
     from _saida_unid u, _saida t);

insert into _res select 'a lista de cursos da unidade so tem curso que existe la',
  (select count(distinct curso_chave)::text from _janela
    where unidade_id = (select unidade_id from _unid) and curso_chave is not null),
  (select jsonb_array_length(j->'filtros'->'cursos')::text from _saida_unid);

-- O rótulo tem que dizer o que o filtro FAZ. Se a opção se chamasse
-- "Bateria T" mas o clique trouxesse as 129 aulas de toda a bateria, a
-- coordenação leria o resultado como erro.
insert into _res select 'ancora: ha curso que so existe em modalidade', 'sim',
  (select case when count(*) > 0 then 'sim'
               else 'NAO — todo curso tem uma variante sem sufixo; o rotulo '
                    || 'sairia limpo por acaso' end
     from (select curso_chave from _janela
            where curso_chave is not null
            group by curso_chave
           having bool_and(curso_nome ~* '\s+(t|ind)$')) t);

insert into _res select 'o rotulo do curso NAO mostra a modalidade', 'sim',
  (select case when count(*) = 0 then 'sim'
               else 'NAO — ' || string_agg(x->>'nome', ', ') end
     from _saida, lateral jsonb_array_elements(j->'filtros'->'cursos') x
    where (x->>'nome') ~* '\s+(t|ind)$');

insert into _res select 'cada opcao traz a contagem', 'sim',
  (select case when bool_and((x->>'aulas')::int > 0) then 'sim'
               else 'NAO — opcao com contagem zerada ou ausente' end
     from _saida, lateral jsonb_array_elements(j->'filtros'->'cursos') x);

-- ─── O cruzamento fila × detalhe, SOB FILTRO ────────────────────────────────
create temp table _alvo on commit drop as
  select (j->'professores'->0->>'professor_id')::int as professor_id,
         (j->'professores'->0->>'aulas')::int        as aulas_na_fila
    from _saida_curso;

insert into _res select 'ancora: o curso filtrado tem alguem na fila', 'sim',
  (select case when professor_id is not null then 'sim' else 'NAO' end from _alvo);

insert into _res select 'o detalhe FILTRADO bate com a linha filtrada',
  (select aulas_na_fila::text from _alvo),
  (select (public.app_coordenacao_professor_detalhe(
             (select professor_id from _alvo), 7, null,
             (select curso_chave from _curso)))->>'aulas');

-- E sem filtro o mesmo professor tem MAIS aulas do que no recorte — senão o
-- filtro do detalhe é enfeite.
insert into _res select 'sem filtro o detalhe do mesmo professor traz mais', 'sim',
  (select case when (public.app_coordenacao_professor_detalhe(
                       (select professor_id from _alvo), 7, null, null))->>'aulas' is null
               then 'NAO — detalhe vazio'
               when ((public.app_coordenacao_professor_detalhe(
                        (select professor_id from _alvo), 7, null, null))->>'aulas')::int
                    >= (select aulas_na_fila from _alvo) then 'sim'
               else 'NAO — o filtro do detalhe nao filtra' end);

-- ─── O que a 070 garantiu e não pode regredir ───────────────────────────────
insert into _res select 'somar as AULAS das linhas devolve o total do resumo',
  (select j->'resumo'->>'sem_lancamento' from _saida),
  (select coalesce(sum((x->>'aulas')::int), 0)::text
     from _saida, lateral jsonb_array_elements(j->'professores') x);

insert into _res select 'a fila NAO repete professor', 'sim',
  (select case when count(*) = count(distinct (x->>'professor_id')::int) then 'sim'
               else 'NAO — professor repetido' end
     from _saida, lateral jsonb_array_elements(j->'professores') x);

insert into _res select 'a fila desce por urgencia', 'sim',
  (select case when bool_and(ok) then 'sim' else 'NAO — fila fora de ordem' end
     from (
       select (x->>'aulas')::int
              <= lag((x->>'aulas')::int, 1, 2147483647) over (order by ord) as ok
         from _saida, lateral jsonb_array_elements(j->'professores')
              with ordinality t(x, ord)
     ) s);

insert into _res select 'a linha traz a foto de quem tem', 'sim',
  (select case when bool_and(x->>'foto_url' is not null) then 'sim'
               else 'NAO — veio linha sem foto_url' end
     from _saida, lateral jsonb_array_elements(j->'professores') x
    where (x->>'professor_id')::int in (
      select id from public.professores where coalesce(foto_url,'') <> ''));

insert into _res select 'a aula de HOJE nao entra na cobranca',
  (select count(distinct aula_id)::text from public.vw_presenca_pendencia
    where data_aula >= current_date - 7 and data_aula < current_date),
  (select j->'resumo'->>'sem_lancamento' from _saida);

-- ─── Assinatura e permissões ────────────────────────────────────────────────
-- Se a versão de 2 argumentos sobreviver, o PostgREST fica AMBÍGUO e o painel
-- para de funcionar inteiro. Este passo é o que impede um `create or replace`
-- distraído no futuro.
-- ⚠️ Aqui morreu um teste meu: a primeira versão comparava
-- `pg_get_function_identity_arguments(oid)` com 'integer, uuid'. Essa função
-- devolve os NOMES junto ("p_dias integer, p_unidade_id uuid"), então a
-- comparação nunca casava, o count dava 0, o esperado era 0 — verde eterno.
-- Quem denunciou foi o mutante V11, que sobreviveu apagando o `drop`.
-- Contar as sobrecargas é a asserção honesta: o que quebra o PostgREST é
-- existir MAIS DE UMA função com o mesmo nome.
insert into _res select 'so existe UMA fila publicada', '1',
  (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname='public' and p.proname='app_coordenacao_em_aberto');

insert into _res select 'so existe UM detalhe publicado', '1',
  (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname='public' and p.proname='app_coordenacao_professor_detalhe');

insert into _res select 'a fila publicada e a de 3 parametros', '3',
  (select coalesce(max(p.pronargs), -1)::text
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname='public' and p.proname='app_coordenacao_em_aberto');

insert into _res select 'o detalhe publicado e o de 4 parametros', '4',
  (select coalesce(max(p.pronargs), -1)::text
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname='public' and p.proname='app_coordenacao_professor_detalhe');

insert into _res select 'anon NAO executa a fila', 'sim',
  (select case when has_function_privilege('anon',
       'public.app_coordenacao_em_aberto(int, uuid, text)', 'execute')
     then 'NAO — anon pode executar' else 'sim' end);

insert into _res select 'authenticated executa a fila', 'sim',
  (select case when has_function_privilege('authenticated',
       'public.app_coordenacao_em_aberto(int, uuid, text)', 'execute')
     then 'sim' else 'NAO' end);

insert into _res select 'anon NAO executa o detalhe', 'sim',
  (select case when has_function_privilege('anon',
       'public.app_coordenacao_professor_detalhe(int, int, uuid, text)', 'execute')
     then 'NAO — anon pode executar' else 'sim' end);

insert into _res select 'authenticated executa o detalhe', 'sim',
  (select case when has_function_privilege('authenticated',
       'public.app_coordenacao_professor_detalhe(int, int, uuid, text)', 'execute')
     then 'sim' else 'NAO' end);

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
