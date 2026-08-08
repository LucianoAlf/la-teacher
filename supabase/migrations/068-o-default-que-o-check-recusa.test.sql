-- 068 (teste) — o default que o próprio CHECK recusa
--
-- Este teste é sobre o SCHEMA, não sobre a agenda de ninguém: ele não depende
-- de quem já foi cobrado hoje, de preferência de professor nem de férias. O
-- único dado vivo que ele pede é UM professor que exista, pra pendurar a FK.
-- Fixture que é uma pessoa de verdade envelhece junto com a vida dela — aqui
-- não tem nenhuma.
--
-- A função que ESCREVE é chamada dentro de um bloco e guardada numa variável
-- antes de ser medida. Chamar função que escreve dentro de um `WHERE` faz a
-- asserção ler o snapshot de ANTES da chamada (mordeu na 056 e na 057).

create temp table _res(passo text, esperado text, obtido text) on commit drop;

create temp table _ctx on commit drop as
select (select min(id) from public.professores) as prof;

insert into _res select 'ancora: existe professor pra pendurar a linha', 'sim',
  (select case when prof is not null then 'sim' else 'NAO — tabela professores vazia' end from _ctx);

-- ───────────────────────────────────────────────────────────────────────────
-- ÂNCORAS — o que esta migration NÃO pode ter mexido.
--
-- As duas existem porque há dois "consertos" tentadores e errados:
--   • alargar o CHECK pra aceitar 'pendente' — legitimaria um estado de entrada
--     que a fila não tem. A linha nasce no claim; não existe caixa de entrada.
--   • tirar o NOT NULL — aí o INSERT omisso passa a gravar null EM SILÊNCIO,
--     que é pior que o erro confuso de hoje.
-- Sem estas duas âncoras, os dois passariam como se fossem a correção.
-- ───────────────────────────────────────────────────────────────────────────
insert into _res select 'ancora: o CHECK do status segue com os 5 estados de sempre',
  'CHECK ((status = ANY (ARRAY[''processando''::text, ''enviada''::text, ''falhou''::text, ''pulada_preferencia''::text, ''pulada_sem_destinatario''::text])))',
  coalesce((select pg_get_constraintdef(oid) from pg_constraint
             where conrelid = 'public.fabio_notificacoes'::regclass
               and conname = 'fabio_notificacoes_status_check'), 'NAO EXISTE MAIS');

insert into _res select 'ancora: status continua NOT NULL', 'sim',
  (select case when a.attnotnull then 'sim'
               else 'NAO — sem NOT NULL o INSERT omisso grava null em silencio' end
     from pg_attribute a
    where a.attrelid = 'public.fabio_notificacoes'::regclass and a.attname = 'status');

-- ───────────────────────────────────────────────────────────────────────────
-- O DEFEITO — este é o passo que muda de cor com a migration.
--
-- ANTES: o default 'pendente' entra sozinho e morre no CHECK → 23514, com uma
-- mensagem que fala da constraint e nunca da causa (o default).
-- DEPOIS: sem default, o NOT NULL levanta 23502 dizendo o nome da coluna.
-- ───────────────────────────────────────────────────────────────────────────
do $$
declare v_estado text; v_msg text;
begin
  begin
    insert into public.fabio_notificacoes (professor_id, tipo, categoria, corpo, canal)
    values ((select prof from _ctx), 'outro', 'informativa', 'linha sem status', 'app');
    v_estado := 'nao levantou — a linha ENTROU';
  exception when others then
    v_estado := sqlstate;
    v_msg    := sqlerrm;
  end;

  insert into _res values ('INSERT sem status falha por NOT NULL, nao por CHECK', '23502', v_estado);

  -- Procura `column "status"`, não só `status`: a mensagem do CHECK cita o NOME
  -- DA CONSTRAINT (`fabio_notificacoes_status_check`), que já contém a palavra.
  -- Um `like '%status%'` ficaria verde nos dois mundos e não mediria nada.
  insert into _res values ('e o erro nomeia a COLUNA, nao a constraint', 'sim',
    case when coalesce(v_msg, '') like '%column "status"%' then 'sim'
         else 'NAO — ' || coalesce(v_msg, v_estado) end);
end $$;

insert into _res select 'o DEFAULT contraditorio sumiu da coluna', 'sem default',
  coalesce((select pg_get_expr(d.adbin, d.adrelid)
              from pg_attribute a
              join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
             where a.attrelid = 'public.fabio_notificacoes'::regclass and a.attname = 'status'),
           'sem default');

-- ───────────────────────────────────────────────────────────────────────────
-- NÃO-REGRESSÃO — todo caminho de escrita de hoje informa o status. Nenhum
-- deles pode ter sido afetado.
-- ───────────────────────────────────────────────────────────────────────────
do $$
declare v_st text;
begin
  insert into public.fabio_notificacoes (professor_id, tipo, categoria, corpo, canal, status)
  values ((select prof from _ctx), 'outro', 'informativa', 'linha com status explicito', 'app', 'processando')
  returning status into v_st;
  insert into _res values ('com status explicito a linha entra normal', 'processando', coalesce(v_st, 'null'));
exception when others then
  insert into _res values ('com status explicito a linha entra normal', 'processando', 'ERRO — ' || sqlerrm);
end $$;

do $$
declare v_estado text;
begin
  begin
    insert into public.fabio_notificacoes (professor_id, tipo, categoria, corpo, canal, status)
    values ((select prof from _ctx), 'outro', 'informativa', 'linha pendente na marra', 'app', 'pendente');
    v_estado := 'nao levantou — "pendente" ENTROU';
  exception when others then v_estado := sqlstate;
  end;
  insert into _res values ('"pendente" explicito continua barrado pelo CHECK', '23514', v_estado);
end $$;

-- O produtor de verdade, não só um INSERT cru: se a coluna tivesse sido mexida
-- de um jeito que quebrasse a fila, é aqui que apareceria.
create temp table _claim(j jsonb) on commit drop;

do $$
declare v_j jsonb;
begin
  v_j := public.fabio_claim_notificacao(
           (select prof from _ctx), 'outro', 'informativa', 'app',
           'regressao 068: o produtor real ainda reserva', 'Teste 068', true);
  insert into _claim values (v_j);
  insert into _res values ('o produtor real ainda reserva', 'true', coalesce(v_j->>'claimed', 'null'));
end $$;

insert into _res select 'e a linha dele nasce em processando', 'processando',
  coalesce((select n.status from public.fabio_notificacoes n, _claim c
             where n.id = (c.j->>'notificacao_id')::uuid), 'nao achei a linha');

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
