# Painel da coordenação — Plano de implementação (parte 1 de 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Colocar no ar o painel da coordenação com o bloco "quem está em aberto",
a versão plantão no celular e a ação de recado — tudo apoiado em dado que já
existe hoje.

**Architecture:** Duas migrations com RPC `security definer` atrás de
`fn_e_coordenacao_la_teacher()`, consumidas por uma página React responsiva sob o
guard `RequireAdmin` que já existe. A leitura sai da `vw_presenca_pendencia`
(view canônica de "sem presença forte", migration 013); a escrita reusa o canal
de notificação do Fábio, que já tem trava de horário e de duplicata.

**Tech Stack:** Postgres 15 (Supabase, projeto `ouqwbbermlzqqvtqwlul`), React 18 +
TypeScript + Vite, Tailwind, react-router v6 (flags v7), `@supabase/supabase-js`.

**Spec:** `docs/superpowers/specs/2026-08-08-painel-coordenacao-design.md`

## Global Constraints

- **Toda migration vem com `.test.sql` E `scripts/mutantes-NNN.mjs`.** Verde
  não-falsificado é decoração. Âncora podre = FALHA, não aviso.
- **`create or replace` PRESERVA privilégios.** Mutante de permissão precisa
  `grant`/`revoke` de propósito, senão sobrevive e o teste mente.
- **Teste roda em produção dentro de `BEGIN/ROLLBACK`** via
  `node scripts/rodar-teste-sql.mjs <migration> <test>`. Nada de fixture que seja
  pessoa real — ela envelhece junto com a vida dela.
- **Nunca chamar função que ESCREVE dentro de um `WHERE`**: a asserção lê o
  snapshot de ANTES da chamada e o passo passa dos dois jeitos. Chamar primeiro
  para uma temp table, depois medir.
- **O LA Teacher NUNCA recalcula o que o LA Report calcula.** Nada de health
  score, nota ou ranking neste plano.
- **Ordenação por urgência, nunca alfabética.** Esse erro já aconteceu no painel
  de equipe.
- **O selo do painel nunca é `gravado_emusys`** — esse status mente.
- Copy em **português do Brasil**, tom da casa: frase curta, sem "por favor",
  sem exclamação, sentence case.
- Push direto na `main` é liberado neste repo.

## Decisões do Alf sobre os desvios (08/08)

**Sidebar: ENTRA nesta parte 1.** Eu tinha proposto adiar por ser "uma página
só" — e estava errado: a coordenação já tem **duas** telas (`/app/equipe`, que
existe, e `/app/coordenacao`, que nasce aqui). Sidebar com dois itens não é
moldura vazia. Vira parte da Task 3.

**O que copiar do LA Organizer** (`web/src/components/DesktopShell.tsx`, commit
`47f169c`) — clonar o repo `LucianoAlf/LA-Organizer`, **nunca** usar a pasta
`D:/la-organizer`, que não é clone e envelhece em silêncio:

- Shell `fixed inset-0 overflow-hidden`: a janela **não cresce com o conteúdo**,
  só o `<main>` rola. É o que faz um app de desktop não ter faixa vazia embaixo.
- Sidebar fixa à esquerda: **240px expandida, 64px colapsada**, com o estado
  colapsado em `localStorage`.
- `<main>` `absolute right-0 bottom-0 top-14` com `left: sidebarWidth` inline.

**E dois ajustes na §10 da spec, achados no self-review:**

- A spec previa `app_coordenacao_plantao()` como RPC própria do celular. Este
  plano **não a cria**: o plantão é um recorte (`pior_atraso >= 3`, no máximo 8)
  do mesmo dado que o desktop já carregou. RPC nova para filtrar no cliente é ida
  ao banco sem pergunta nova. Se o plantão passar a ter regra própria — outra
  janela, outra fonte —, aí ele ganha RPC.
- A spec descrevia "recado pelo Fábio" como ação, mas **não listava o contrato**.
  Este plano cria `app_coordenacao_recado(p_professor_id, p_corpo)` (Task 2). A
  §10 da spec deve ser atualizada quando esta parte 1 entrar.

## Estrutura de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `supabase/migrations/065-o-painel-da-coordenacao-tem-fonte.sql` | RPC de leitura do bloco 1 e do plantão |
| `supabase/migrations/065-…test.sql` + `scripts/mutantes-065.mjs` | prova |
| `supabase/migrations/066-a-coordenacao-manda-recado.sql` | RPC de escrita (enfileira notificação) |
| `supabase/migrations/066-…test.sql` + `scripts/mutantes-066.mjs` | prova |
| `src/lib/api.ts` | wrappers tipados das duas RPCs |
| `src/pages/app/Coordenacao.tsx` | a página: faixa + tabela no desktop, plantão no celular |
| `src/routes.tsx` | rota `/app/coordenacao` sob `RequireAdmin` |

---

### Task 1: RPC do bloco 1 — `app_coordenacao_em_aberto`

**Files:**
- Create: `supabase/migrations/065-o-painel-da-coordenacao-tem-fonte.sql`
- Create: `supabase/migrations/065-o-painel-da-coordenacao-tem-fonte.test.sql`
- Create: `scripts/mutantes-065.mjs`
- Modify: `package.json` (adicionar `teste:065`)

**Interfaces:**
- Consumes: `public.vw_presenca_pendencia` (migration 013),
  `public.fn_e_coordenacao_la_teacher()` (migration 062).
- Produces: `public.app_coordenacao_em_aberto(p_dias int, p_unidade_id uuid)
  returns jsonb`, com o formato:
  ```json
  { "resumo": { "sem_lancamento": 847, "professores": 38, "ontem": 31,
                "professores_ativos": 44 },
    "professores": [ { "professor_id": 12, "professor_nome": "…",
                       "unidade_nome": "…", "em_aberto": 37,
                       "alunos": 37, "pior_atraso": 5 } ] }
  ```

- [ ] **Step 1: Escrever a migration**

```sql
-- 065: o painel da coordenação tem fonte
--
-- A coordenação precisa ver quem está em aberto AGORA. A fonte é a
-- vw_presenca_pendencia (013), que já é a única resposta canônica para "sem
-- presença forte" — não se recalcula aqui, senão nasce o segundo número.
--
-- Ordena por urgência (em_aberto desc, pior_atraso desc), NUNCA por nome: o
-- painel de equipe já cometeu esse erro e ninguém percebeu porque a tela não
-- diz em que ordem está.

create or replace function public.app_coordenacao_em_aberto(
  p_dias       int  default 7,
  p_unidade_id uuid default null
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_saida jsonb;
begin
  if not public.fn_e_coordenacao_la_teacher() then
    raise exception 'apenas_admin';
  end if;

  create temp table if not exists _pend_tmp on commit drop as
  select * from public.vw_presenca_pendencia where false;
  delete from _pend_tmp;

  insert into _pend_tmp
  select *
    from public.vw_presenca_pendencia
   where data_aula >= current_date - p_dias
     and data_aula <  current_date
     and (p_unidade_id is null or unidade_id = p_unidade_id);

  select jsonb_build_object(
    'resumo', jsonb_build_object(
      'sem_lancamento',      (select count(*) from _pend_tmp),
      'professores',         (select count(distinct professor_id) from _pend_tmp),
      'ontem',               (select count(*) from _pend_tmp
                               where data_aula = current_date - 1),
      'professores_ativos',  (select count(*) from public.professores where ativo)
    ),
    'professores', coalesce((
      select jsonb_agg(
               jsonb_build_object(
                 'professor_id',   t.professor_id,
                 'professor_nome', t.professor_nome,
                 'unidade_nome',   t.unidade_nome,
                 'em_aberto',      t.em_aberto,
                 'alunos',         t.alunos,
                 'pior_atraso',    t.pior_atraso)
               order by t.em_aberto desc, t.pior_atraso desc, t.professor_nome)
        from (select professor_id,
                     professor_nome,
                     unidade_nome,
                     count(*)::int                  as em_aberto,
                     count(distinct aluno_id)::int  as alunos,
                     max(dias_em_atraso)::int       as pior_atraso
                from _pend_tmp
               group by 1, 2, 3) t
    ), '[]'::jsonb)
  ) into v_saida;

  return v_saida;
end;
$function$;

revoke all on function public.app_coordenacao_em_aberto(int, uuid) from public, anon;
grant execute on function public.app_coordenacao_em_aberto(int, uuid) to authenticated;

comment on function public.app_coordenacao_em_aberto(int, uuid) is
  'Bloco 1 do painel da coordenação: quem está com lançamento em aberto, '
  'ordenado por urgência. Fonte única: vw_presenca_pendencia (013). '
  'Só coordenação (fn_e_coordenacao_la_teacher, 062).';
```

- [ ] **Step 2: Escrever o teste**

O teste troca a identidade com `set_config('request.jwt.claims', …)` — é isso
que faz `auth.uid()` responder dentro da transação. Usa um coordenador que já
existe em vez de inserir em `auth.users`.

```sql
-- 065 (teste): a fonte do painel da coordenação
--
-- PASSO 1: sem identidade, a RPC recusa
do $$
declare v_erro text := 'nao levantou';
begin
  perform set_config('request.jwt.claims', '', true);
  begin
    perform public.app_coordenacao_em_aberto(7, null);
  exception when others then
    v_erro := sqlerrm;
  end;
  if v_erro not like '%apenas_admin%' then
    raise exception 'PASSO 1 FALHOU: esperava apenas_admin, veio %', v_erro;
  end if;
end $$;

-- PASSO 2: com identidade de coordenação, a RPC responde e o resumo bate
--          com a contagem feita direto na view (âncora viva)
do $$
declare
  v_uid   uuid;
  v_saida jsonb;
  v_view  int;
begin
  select u.auth_user_id into v_uid
    from public.la_teacher_coordenacao c
    join public.usuarios u on u.id = c.usuario_id
   where u.auth_user_id is not null
   limit 1;
  if v_uid is null then
    raise exception 'PASSO 2 SEM ÂNCORA: nenhum coordenador com auth_user_id';
  end if;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_uid::text)::text, true);

  v_saida := public.app_coordenacao_em_aberto(7, null);

  select count(*) into v_view
    from public.vw_presenca_pendencia
   where data_aula >= current_date - 7 and data_aula < current_date;

  if (v_saida->'resumo'->>'sem_lancamento')::int <> v_view then
    raise exception 'PASSO 2 FALHOU: RPC disse %, a view diz %',
      v_saida->'resumo'->>'sem_lancamento', v_view;
  end if;
end $$;

-- PASSO 3: ordena por urgência, não por nome
do $$
declare
  v_uid  uuid;
  v_arr  jsonb;
  v_ant  int := 2147483647;
  v_item jsonb;
begin
  select u.auth_user_id into v_uid
    from public.la_teacher_coordenacao c
    join public.usuarios u on u.id = c.usuario_id
   where u.auth_user_id is not null limit 1;
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_uid::text)::text, true);

  v_arr := public.app_coordenacao_em_aberto(7, null) -> 'professores';
  if jsonb_array_length(v_arr) < 2 then
    raise exception 'PASSO 3 SEM ÂNCORA: menos de 2 professores em aberto';
  end if;
  for v_item in select * from jsonb_array_elements(v_arr) loop
    if (v_item->>'em_aberto')::int > v_ant then
      raise exception 'PASSO 3 FALHOU: fila fora de ordem (% depois de %)',
        v_item->>'em_aberto', v_ant;
    end if;
    v_ant := (v_item->>'em_aberto')::int;
  end loop;
end $$;

-- PASSO 4: o filtro de unidade filtra mesmo
do $$
declare
  v_uid uuid; v_todas int; v_uma int; v_unid uuid;
begin
  select u.auth_user_id into v_uid
    from public.la_teacher_coordenacao c
    join public.usuarios u on u.id = c.usuario_id
   where u.auth_user_id is not null limit 1;
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_uid::text)::text, true);

  select unidade_id into v_unid
    from public.vw_presenca_pendencia
   where data_aula >= current_date - 7 and data_aula < current_date
   limit 1;
  if v_unid is null then
    raise exception 'PASSO 4 SEM ÂNCORA: nenhuma pendência para filtrar';
  end if;

  v_todas := (public.app_coordenacao_em_aberto(7, null)
               ->'resumo'->>'sem_lancamento')::int;
  v_uma   := (public.app_coordenacao_em_aberto(7, v_unid)
               ->'resumo'->>'sem_lancamento')::int;

  if v_uma >= v_todas then
    raise exception 'PASSO 4 FALHOU: filtro não filtrou (uma=%, todas=%)',
      v_uma, v_todas;
  end if;
end $$;

-- PASSO 5: a aula de HOJE não entra (a janela é fechada em current_date)
do $$
declare v_uid uuid; v_hoje int;
begin
  select u.auth_user_id into v_uid
    from public.la_teacher_coordenacao c
    join public.usuarios u on u.id = c.usuario_id
   where u.auth_user_id is not null limit 1;
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_uid::text)::text, true);

  select count(*) into v_hoje
    from public.vw_presenca_pendencia where data_aula = current_date;
  if v_hoje = 0 then
    raise exception 'PASSO 5 SEM ÂNCORA: não há aula de hoje na pendência';
  end if;

  if (public.app_coordenacao_em_aberto(7, null)->'resumo'->>'sem_lancamento')::int
     <> (select count(*) from public.vw_presenca_pendencia
          where data_aula >= current_date - 7 and data_aula < current_date) then
    raise exception 'PASSO 5 FALHOU: a janela pegou o dia de hoje';
  end if;
end $$;

-- PASSO 6: anon não pode executar
do $$
begin
  if has_function_privilege('anon',
       'public.app_coordenacao_em_aberto(int, uuid)', 'execute') then
    raise exception 'PASSO 6 FALHOU: anon pode executar a RPC do painel';
  end if;
end $$;
```

- [ ] **Step 3: Rodar o teste e ver passar**

```bash
node scripts/rodar-teste-sql.mjs supabase/migrations/065-o-painel-da-coordenacao-tem-fonte.sql supabase/migrations/065-o-painel-da-coordenacao-tem-fonte.test.sql
```

Esperado: todos os 6 passos verdes. Se o PASSO 3 ou 5 disser "SEM ÂNCORA", o
teste está medindo um banco sem o caso — **isso é falha, não aviso**: pare e
ajuste a janela do passo até haver âncora real.

- [ ] **Step 4: Escrever os mutantes**

`scripts/mutantes-065.mjs` — cada mutante é a migration com UMA alteração, e
cada um tem que ser **morto** por um passo nomeado.

```js
// V1 tira o guard de permissão            -> morre no PASSO 1
// V2 ordena por nome em vez de urgência    -> morre no PASSO 3
// V3 ignora p_unidade_id                   -> morre no PASSO 4
// V4 usa data_aula <= current_date         -> morre no PASSO 5
// V5 dá execute pra anon                   -> morre no PASSO 6
export const MUTANTES = [
  { id: 'V1', mata: 'PASSO 1',
    de: `if not public.fn_e_coordenacao_la_teacher() then\n    raise exception 'apenas_admin';\n  end if;`,
    para: `-- guard removido pelo mutante` },
  { id: 'V2', mata: 'PASSO 3',
    de: `order by t.em_aberto desc, t.pior_atraso desc, t.professor_nome`,
    para: `order by t.professor_nome` },
  { id: 'V3', mata: 'PASSO 4',
    de: `and (p_unidade_id is null or unidade_id = p_unidade_id)`,
    para: `and (p_unidade_id is null or true)` },
  { id: 'V4', mata: 'PASSO 5',
    de: `and data_aula <  current_date`,
    para: `and data_aula <= current_date` },
  { id: 'V5', mata: 'PASSO 6',
    de: `revoke all on function public.app_coordenacao_em_aberto(int, uuid) from public, anon;`,
    para: `grant execute on function public.app_coordenacao_em_aberto(int, uuid) to anon;` },
]
```

- [ ] **Step 5: Rodar os mutantes e ver os 5 morrerem**

```bash
node scripts/mutantes-065.mjs
```

Esperado: `5/5 mortos`. **Mutante sobrevivente é achado, não ruído** — significa
que o teste não mede o que diz medir. Conserte o teste, não o mutante.

- [ ] **Step 6: Aplicar em produção e commitar**

```bash
node scripts/aplicar-sql.mjs supabase/migrations/065-o-painel-da-coordenacao-tem-fonte.sql
git add supabase/migrations/065-* scripts/mutantes-065.mjs package.json
git commit -m "feat(065): o painel da coordenacao tem fonte"
git push origin main
```

---

### Task 2: RPC de recado — `app_coordenacao_recado`

**Files:**
- Create: `supabase/migrations/066-a-coordenacao-manda-recado.sql`
- Create: `supabase/migrations/066-a-coordenacao-manda-recado.test.sql`
- Create: `scripts/mutantes-066.mjs`
- Modify: `package.json` (adicionar `teste:066`)

**Interfaces:**
- Consumes: `public.fn_e_coordenacao_la_teacher()`,
  `public.fabio_claim_notificacao_por_referencia(...)`,
  `public.fn_fabio_pode_notificar(int, text, timestamptz)`.
- Produces: `public.app_coordenacao_recado(p_professor_id int, p_corpo text)
  returns jsonb` → `{"enfileirado": true, "notificacao_id": "…"}` ou
  `{"enfileirado": false, "motivo": "janela_de_silencio"}`.

> ⚠️ **REPLANEJADA EM 08/08, durante a execução.** O Step 1 abaixo mandava ler o
> canal antes de escrever em cima dele. Eu li — e o que ele diz muda a tarefa.
> **Os Steps 1 e 2 originais estão superados**; a forma correta está no bloco
> "Como ficou" logo abaixo. Os Steps 3 a 6 seguem valendo com os ajustes ali.
>
> **O que a leitura mostrou:**
>
> 1. `fn_fabio_pode_notificar` só aceita categoria `'governanca'` ou
>    `'informativa'` — `'coordenacao'` levanta `categoria_invalida`. Cobrança de
>    lançamento é **governança**.
> 2. Para `governanca`, **silêncio e domingo nunca bloqueiam** — só férias
>    (`pausa_ate`). Está escrito na função: *"bypass estrutural, não decisão de
>    prompt do Fábio"*. Logo **não existe "janela de silêncio" na cobrança**, e o
>    estado `silencio` que o Step 2 da Task 4 previa vira `pausa` (professor de
>    férias).
> 3. `fabio_claim_notificacao_por_referencia` é **a função do WORKER**, não do
>    produtor: ela insere já com `status='processando'`, `tentativas=1` e um
>    lease de N minutos. Usá-la a partir do painel criaria uma notificação
>    "já sendo enviada por ninguém", que só sairia quando o lease vencesse — por
>    acidente, não por projeto.
> 4. **A fila não tem estado de entrada.** O `status` aceita apenas
>    `processando`, `enviada`, `falhou`, `pulada_preferencia`,
>    `pulada_sem_destinatario`. Não há `pendente`: a linha nasce no claim. Então
>    **o painel não tem onde depositar um recado** para o worker levar depois.
>
> **Como ficou:** o recado segue o padrão que o convite já usa — **edge function
> com envio síncrono**. Faz sentido além da restrição técnica: a coordenação
> clicou e está olhando a tela, então ela merece saber se chegou, não "foi
> enfileirado". A função:
>
> 1. valida `fn_e_coordenacao_la_teacher()` pelo JWT de quem chamou;
> 2. checa `fn_fabio_pode_notificar(professor_id, 'governanca', now())` — a única
>    coisa que barra é férias;
> 3. envia pelo mesmo caminho de WhatsApp do `professor-liberar-acesso`;
> 4. grava em `fabio_notificacoes` com `tipo='pendencia_registro'`,
>    `categoria='governanca'`, `canal='whatsapp'`,
>    `destinatario_tipo='professor'`, `status='enviada'` e `envio_recibo`.
>
> **A dedupe muda de mecanismo junto.** O índice
> `uq_fabio_notif_recorrente_diario` já cobre
> `(professor_id, tipo, dia_referencia, canal)` justamente para
> `pendencia_registro` — então basta preencher `dia_referencia = current_date` e
> o segundo clique do dia colide sozinho. **Índice único e `on conflict` são um
> contrato só**: quem escreve tem que tratar a colisão, não descobrir na
> exceção.
>
> Isso torna a Task 2 uma **edge function + migration pequena** (só o helper de
> gravação), não a RPC única que estava planejada.

- [ ] **Step 1 (SUPERADO — feito, resultado no bloco acima): Ler o canal antes de escrever em cima dele**

Antes de qualquer linha, leia a fonte das duas funções — não confie na assinatura.
Rode esta consulta (pelo MCP do Supabase ou pelo `scripts/aplicar-sql.mjs` com um
arquivo temporário):

```sql
select p.proname, p.prosrc
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('fabio_claim_notificacao_por_referencia',
                    'fn_fabio_pode_notificar');
```

E descubra o nome real da tabela de fila (os passos 3 e 4 do teste dependem dele):

```sql
select c.relname
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r'
  and c.relname like 'fabio_notific%';
```

O que precisa ficar claro antes de seguir: se
`fabio_claim_notificacao_por_referencia` **cria** a notificação (com dedupe pela
referência) ou apenas **reivindica** uma já existente. O nome diz "claim", os
argumentos (`p_corpo`, `p_titulo`) dizem "cria". **Escreva a resposta como
comentário no topo da migration.** Se ela apenas reivindica, este plano muda: a
inserção passa a ser direta na tabela de notificação, e o passo 3 do teste
verifica a linha inserida em vez do retorno.

- [ ] **Step 2: Escrever a migration**

```sql
-- 066: a coordenação manda recado
--
-- Não constrói canal: reusa o do Fábio, que já tem trava de horário
-- (fn_fabio_pode_notificar) e de duplicata por referência. A coordenação não
-- fura a janela de silêncio do professor — quem manda recado às 23h queima o
-- canal inteiro, e o canal é o mesmo do briefing das 8h.
--
-- A referência é ('coordenacao_recado', professor_id::text || ':' || data), pra
-- que dois cliques no mesmo dia não virem duas mensagens.

create or replace function public.app_coordenacao_recado(
  p_professor_id int,
  p_corpo        text
) returns jsonb
language plpgsql
volatile
security definer
set search_path to 'public'
as $function$
declare
  v_id     uuid;
  v_pode   boolean;
begin
  if not public.fn_e_coordenacao_la_teacher() then
    raise exception 'apenas_admin';
  end if;

  if p_corpo is null or length(btrim(p_corpo)) < 3 then
    raise exception 'recado_vazio';
  end if;

  v_pode := public.fn_fabio_pode_notificar(p_professor_id, 'coordenacao', now());
  if not v_pode then
    return jsonb_build_object('enfileirado', false,
                              'motivo', 'janela_de_silencio');
  end if;

  select public.fabio_claim_notificacao_por_referencia(
           p_professor_id,
           'coordenacao_recado',
           'coordenacao',
           'whatsapp',
           btrim(p_corpo),
           'coordenacao_recado',
           p_professor_id::text || ':' || current_date::text,
           'Recado da coordenação',
           15
         ) into v_id;

  return jsonb_build_object('enfileirado', v_id is not null,
                            'notificacao_id', v_id);
end;
$function$;

revoke all on function public.app_coordenacao_recado(int, text) from public, anon;
grant execute on function public.app_coordenacao_recado(int, text) to authenticated;

comment on function public.app_coordenacao_recado(int, text) is
  'Enfileira recado da coordenação pro professor pelo canal do Fábio. '
  'Respeita fn_fabio_pode_notificar e deduplica por (professor, dia).';
```

- [ ] **Step 3: Escrever o teste**

⚠️ `app_coordenacao_recado` **escreve**. Nunca chamá-la dentro de um `WHERE`:
chame primeiro, guarde o retorno numa variável, e só então meça. Chamada dentro
de um `WHERE` faz a asserção ler o snapshot de antes e o passo passa dos dois
jeitos — isso já mordeu duas vezes (056, 057).

```sql
-- PASSO 1: sem identidade, recusa
do $$
declare v_erro text := 'nao levantou';
begin
  perform set_config('request.jwt.claims', '', true);
  begin perform public.app_coordenacao_recado(25, 'oi');
  exception when others then v_erro := sqlerrm; end;
  if v_erro not like '%apenas_admin%' then
    raise exception 'PASSO 1 FALHOU: veio %', v_erro;
  end if;
end $$;

-- PASSO 2: recado vazio é recusado (com identidade válida)
do $$
declare v_uid uuid; v_erro text := 'nao levantou';
begin
  select u.auth_user_id into v_uid from public.la_teacher_coordenacao c
    join public.usuarios u on u.id = c.usuario_id
   where u.auth_user_id is not null limit 1;
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_uid::text)::text, true);
  begin perform public.app_coordenacao_recado(25, '  ');
  exception when others then v_erro := sqlerrm; end;
  if v_erro not like '%recado_vazio%' then
    raise exception 'PASSO 2 FALHOU: veio %', v_erro;
  end if;
end $$;

-- PASSO 3: recado válido enfileira UMA linha (chamada fora do WHERE)
do $$
declare v_uid uuid; v_prof int; v_antes int; v_depois int; v_r jsonb;
begin
  select u.auth_user_id into v_uid from public.la_teacher_coordenacao c
    join public.usuarios u on u.id = c.usuario_id
   where u.auth_user_id is not null limit 1;
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_uid::text)::text, true);

  select id into v_prof from public.professores where ativo order by id limit 1;
  select count(*) into v_antes from public.fabio_notificacoes
   where professor_id = v_prof;

  v_r := public.app_coordenacao_recado(v_prof, 'Teste de recado da coordenacao');

  select count(*) into v_depois from public.fabio_notificacoes
   where professor_id = v_prof;

  if (v_r->>'enfileirado')::boolean and v_depois <> v_antes + 1 then
    raise exception 'PASSO 3 FALHOU: disse enfileirado mas gravou % linha(s)',
      v_depois - v_antes;
  end if;
end $$;

-- PASSO 4: dois cliques no mesmo dia não viram duas mensagens
do $$
declare v_uid uuid; v_prof int; v_antes int; v_depois int;
begin
  select u.auth_user_id into v_uid from public.la_teacher_coordenacao c
    join public.usuarios u on u.id = c.usuario_id
   where u.auth_user_id is not null limit 1;
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_uid::text)::text, true);
  select id into v_prof from public.professores where ativo order by id limit 1;

  perform public.app_coordenacao_recado(v_prof, 'Primeiro recado do dia');
  select count(*) into v_antes from public.fabio_notificacoes
   where professor_id = v_prof;
  perform public.app_coordenacao_recado(v_prof, 'Segundo recado do mesmo dia');
  select count(*) into v_depois from public.fabio_notificacoes
   where professor_id = v_prof;

  if v_depois > v_antes then
    raise exception 'PASSO 4 FALHOU: o segundo clique virou mensagem nova';
  end if;
end $$;

-- PASSO 5: anon não pode executar
do $$
begin
  if has_function_privilege('anon',
       'public.app_coordenacao_recado(int, text)', 'execute') then
    raise exception 'PASSO 5 FALHOU: anon pode mandar recado';
  end if;
end $$;
```

**Se o nome da tabela de notificação não for `fabio_notificacoes`**, descubra o
nome real no Step 1 e substitua nos passos 3 e 4 antes de rodar.

- [ ] **Step 4: Rodar o teste**

```bash
node scripts/rodar-teste-sql.mjs supabase/migrations/066-a-coordenacao-manda-recado.sql supabase/migrations/066-a-coordenacao-manda-recado.test.sql
```

Esperado: 5 passos verdes.

- [ ] **Step 5: Escrever e rodar os mutantes**

```js
// V1 tira o guard                      -> morre no PASSO 1
// V2 aceita corpo vazio                -> morre no PASSO 2
// V3 ignora fn_fabio_pode_notificar    -> morre se a janela estiver fechada;
//    se estiver aberta o passo vira SEM ÂNCORA — nesse caso rode o teste
//    fixando `now()` dentro da janela de silêncio via parâmetro
// V4 muda a referência pra incluir now() -> morre no PASSO 4 (dedupe some)
// V5 dá execute pra anon               -> morre no PASSO 5
```

```bash
node scripts/mutantes-066.mjs
```

Esperado: `5/5 mortos`.

- [ ] **Step 6: Aplicar e commitar**

```bash
node scripts/aplicar-sql.mjs supabase/migrations/066-a-coordenacao-manda-recado.sql
git add supabase/migrations/066-* scripts/mutantes-066.mjs package.json
git commit -m "feat(066): a coordenacao manda recado pelo canal do Fabio"
git push origin main
```

---

### Task 3: Rota, guard e wrappers

**Files:**
- Modify: `src/lib/api.ts` (adicionar dois wrappers no fim do arquivo)
- Modify: `src/routes.tsx:108-115` (adicionar a rota ao bloco do `RequireAdmin`)
- Create: `src/pages/app/Coordenacao.tsx` (só o esqueleto + a faixa de números)

**Interfaces:**
- Consumes: `app_coordenacao_em_aberto`, `app_coordenacao_recado` (Tasks 1 e 2).
- Produces: `coordenacaoEmAberto(dias?, unidadeId?)` e
  `coordenacaoRecado(professorId, corpo)` exportados de `src/lib/api.ts`;
  componente `default` de `src/pages/app/Coordenacao.tsx`.

- [ ] **Step 1: Wrappers em `src/lib/api.ts`**

Siga o padrão dos wrappers que já existem no arquivo (mesma forma de chamar
`supabase.rpc` e de propagar erro).

```ts
export type CoordenacaoLinha = {
  professor_id: number
  professor_nome: string
  unidade_nome: string
  em_aberto: number
  alunos: number
  pior_atraso: number
}

export type CoordenacaoEmAberto = {
  resumo: {
    sem_lancamento: number
    professores: number
    ontem: number
    professores_ativos: number
  }
  professores: CoordenacaoLinha[]
}

export async function coordenacaoEmAberto(
  dias = 7,
  unidadeId: string | null = null,
): Promise<CoordenacaoEmAberto> {
  const { data, error } = await supabase.rpc('app_coordenacao_em_aberto', {
    p_dias: dias,
    p_unidade_id: unidadeId,
  })
  if (error) throw error
  return data as CoordenacaoEmAberto
}

export async function coordenacaoRecado(
  professorId: number,
  corpo: string,
): Promise<{ enfileirado: boolean; motivo?: string }> {
  const { data, error } = await supabase.rpc('app_coordenacao_recado', {
    p_professor_id: professorId,
    p_corpo: corpo,
  })
  if (error) throw error
  return data as { enfileirado: boolean; motivo?: string }
}
```

- [ ] **Step 2: Rota**

Em `src/routes.tsx`, importe a página e acrescente-a ao bloco que já existe do
`RequireAdmin` — o mesmo que guarda `/app/equipe`:

```tsx
import CoordenacaoPage from './pages/app/Coordenacao'
```

```tsx
        {
          // Guard PRÓPRIO, fora do RequireProfessor: a coordenação não tem
          // professor vinculado, e o guard do professor manda quem não tem pra
          // "Vínculo pendente" — a dona do painel bateria na tela de quem não
          // tem acesso.
          element: <RequireAdmin />,
          children: [
            { path: '/app/equipe', element: <EquipePage /> },
            { path: '/app/coordenacao', element: <CoordenacaoPage /> },
          ],
        },
```

- [ ] **Step 3: Página com a faixa de números**

```tsx
import { useEffect, useState } from 'react'
import { AppFrame } from './AppFrame'
import { EmptyState } from '../../components/ui'
import { coordenacaoEmAberto, type CoordenacaoEmAberto } from '../../lib/api'

export default function CoordenacaoPage() {
  const [dados, setDados] = useState<CoordenacaoEmAberto | null>(null)
  const [erro, setErro] = useState(false)

  useEffect(() => {
    let vivo = true
    coordenacaoEmAberto(7, null)
      .then((d) => vivo && setDados(d))
      .catch(() => vivo && setErro(true))
    return () => {
      vivo = false
    }
  }, [])

  if (erro) {
    return (
      <AppFrame>
        <EmptyState
          icon="fa-solid fa-triangle-exclamation"
          title="Não consegui carregar agora"
          description="Deu um problema de conexão. Recarrega a página e tenta de novo."
        />
      </AppFrame>
    )
  }

  const r = dados?.resumo

  return (
    <AppFrame>
      <div className="mx-auto w-full max-w-5xl px-4 py-4">
        <h1 className="text-[20px] font-medium text-text-primary">Coordenação</h1>

        <div className="mt-4 grid grid-cols-2 gap-2 md:grid-cols-4">
          <Numero rotulo="Sem lançamento · 7 dias" valor={r?.sem_lancamento} alerta />
          <Numero
            rotulo="Professores afetados"
            valor={r?.professores}
            sufixo={r ? ` de ${r.professores_ativos}` : undefined}
          />
          <Numero rotulo="Só de ontem" valor={r?.ontem} />
          <Numero rotulo="Na fila" valor={dados?.professores.length} />
        </div>
      </div>
    </AppFrame>
  )
}

function Numero(props: {
  rotulo: string
  valor?: number
  sufixo?: string
  alerta?: boolean
}) {
  return (
    <div className="rounded-lg bg-surface-1 p-3">
      <p className="text-[12px] text-text-secondary">{props.rotulo}</p>
      <p
        className={`text-[24px] font-medium ${
          props.alerta ? 'text-danger' : 'text-text-primary'
        }`}
      >
        {props.valor ?? '—'}
        {props.sufixo ? (
          <span className="text-[14px] text-text-muted">{props.sufixo}</span>
        ) : null}
      </p>
    </div>
  )
}
```

- [ ] **Step 4: Ver no navegador**

Suba o dev server pelo preview do editor (nunca por `Bash`) e abra
`/app/coordenacao` autenticado como coordenação. Esperado: os quatro números
carregam com valores diferentes de `—`.

- [ ] **Step 5: Commitar**

```bash
git add src/lib/api.ts src/routes.tsx src/pages/app/Coordenacao.tsx
git commit -m "feat(coordenacao): rota, guard e a faixa de numeros"
git push origin main
```

---

### Task 4: A tabela "quem está em aberto" com a ação de recado

**Files:**
- Modify: `src/pages/app/Coordenacao.tsx` (acrescentar a tabela abaixo da faixa)

**Interfaces:**
- Consumes: `CoordenacaoLinha[]` de `dados.professores` (Task 3),
  `coordenacaoRecado` (Task 3).
- Produces: nada para tarefas seguintes.

- [ ] **Step 1: A tabela, só no desktop**

`hidden md:block` — no celular esta tabela não aparece: quem responde pelo
celular é o plantão da Task 5. Tabela de cinco colunas em tela de 375px vira
rolagem lateral, e rolagem lateral é a forma mais rápida de alguém parar de
abrir o painel.

```tsx
      <div className="mt-4 hidden overflow-hidden rounded-xl border border-border md:block">
        <div className="flex items-center justify-between border-b border-border px-4 py-2.5">
          <span className="text-[14px] font-medium">Quem está em aberto</span>
          <span className="text-[12px] text-text-muted">ordenado por urgência</span>
        </div>
        <table className="w-full table-fixed text-[13px]">
          <thead>
            <tr className="text-[12px] text-text-secondary">
              <th className="w-[44%] px-4 py-2 text-left font-normal">Professor</th>
              <th className="w-[16%] px-1 py-2 text-right font-normal">Em aberto</th>
              <th className="w-[14%] px-1 py-2 text-right font-normal">Alunos</th>
              <th className="w-[12%] px-1 py-2 text-right font-normal">Atraso</th>
              <th className="w-[14%] px-4 py-2 text-right font-normal">Ação</th>
            </tr>
          </thead>
          <tbody>
            {dados?.professores.map((p) => (
              <tr key={p.professor_id} className="border-t border-border">
                <td className="px-4 py-2.5">
                  <span className="block truncate text-text-primary">
                    {p.professor_nome}
                  </span>
                  <span className="block text-[11px] text-text-muted">
                    {p.unidade_nome}
                  </span>
                </td>
                <td className="px-1 py-2.5 text-right font-medium text-danger">
                  {p.em_aberto}
                </td>
                <td className="px-1 py-2.5 text-right text-text-secondary">
                  {p.alunos}
                </td>
                <td className="px-1 py-2.5 text-right text-text-secondary">
                  {p.pior_atraso}d
                </td>
                <td className="px-4 py-2.5 text-right">
                  <BotaoRecado professor={p} />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
```

- [ ] **Step 2: O botão de recado**

Estados explícitos, sem otimismo: só diz "enviado" depois que o banco confirmou.
E a janela de silêncio tem resposta própria — o professor não recebe às 23h, e a
coordenação precisa **saber disso**, não achar que mandou.

```tsx
function BotaoRecado({ professor }: { professor: CoordenacaoLinha }) {
  const [estado, setEstado] = useState<
    'parado' | 'enviando' | 'enviado' | 'silencio' | 'erro'
  >('parado')

  async function mandar() {
    setEstado('enviando')
    try {
      const r = await coordenacaoRecado(
        professor.professor_id,
        `Oi! Ficaram ${professor.em_aberto} lançamentos em aberto na sua agenda. ` +
          `Consegue dar uma olhada hoje?`,
      )
      setEstado(r.enfileirado ? 'enviado' : 'silencio')
    } catch {
      setEstado('erro')
    }
  }

  if (estado === 'enviado') {
    return <span className="text-[12px] text-success">recado enviado</span>
  }
  if (estado === 'silencio') {
    return <span className="text-[12px] text-text-muted">fora de horário</span>
  }
  if (estado === 'erro') {
    return <span className="text-[12px] text-danger">não deu — tenta de novo</span>
  }
  return (
    <button
      onClick={mandar}
      disabled={estado === 'enviando'}
      className="text-[12px] text-text-secondary underline-offset-2 hover:underline"
    >
      {estado === 'enviando' ? 'enviando…' : 'mandar recado'}
    </button>
  )
}
```

- [ ] **Step 3: Conferir no navegador**

Abra `/app/coordenacao` no desktop. Esperado: a fila desce de mais lançamentos
para menos. Clique "mandar recado" no **seu próprio** professor de teste (o
Matheus) e confirme que vira "recado enviado" — e que o segundo clique no mesmo
dia **não** gera segunda mensagem (a dedupe da Task 2).

- [ ] **Step 4: Commitar**

```bash
git add src/pages/app/Coordenacao.tsx
git commit -m "feat(coordenacao): a fila de quem esta em aberto, com recado na linha"
git push origin main
```

---

### Task 5: O plantão no celular

**Files:**
- Modify: `src/pages/app/Coordenacao.tsx` (bloco `md:hidden`)

**Interfaces:**
- Consumes: os mesmos `dados.professores` da Task 3. **Não** cria RPC nova: o
  plantão é um recorte do mesmo dado, e recorte no cliente não precisa de ida ao
  banco.
- Produces: nada.

- [ ] **Step 1: A lista curta**

O celular mostra **só quem tem atraso de 3 dias ou mais**, no máximo 8 — é o que
não pode esperar. O resto fica no desktop, e a tela diz isso em vez de fingir que
não existe.

```tsx
      <div className="mt-4 md:hidden">
        <p className="mb-2 text-[13px] font-medium">Precisa de decisão agora</p>
        {(dados?.professores ?? [])
          .filter((p) => p.pior_atraso >= 3)
          .slice(0, 8)
          .map((p) => (
            <div
              key={p.professor_id}
              className="mb-2 rounded-lg border border-border p-3"
            >
              <p className="text-[14px] text-text-primary">{p.professor_nome}</p>
              <p className="text-[12px] text-text-secondary">
                {p.em_aberto} em aberto · {p.pior_atraso} dias · {p.unidade_nome}
              </p>
              <div className="mt-2">
                <BotaoRecado professor={p} />
              </div>
            </div>
          ))}
        {dados && dados.professores.filter((p) => p.pior_atraso >= 3).length === 0 ? (
          <p className="text-[13px] text-text-secondary">
            Nada atrasado há 3 dias ou mais. O painel completo está no computador.
          </p>
        ) : null}
      </div>
```

- [ ] **Step 2: Conferir nos dois tamanhos**

No preview, alterne entre 375px e 1280px. Esperado: no celular só o plantão, sem
tabela e **sem rolagem lateral**; no desktop só a tabela, sem o plantão.

- [ ] **Step 3: Commitar**

```bash
git add src/pages/app/Coordenacao.tsx
git commit -m "feat(coordenacao): o plantao no celular"
git push origin main
```

---

### Task 6: Verificação e suíte inteira

**Files:**
- Modify: `RETOMADA.md` (mover o painel de PRÓXIMO PASSO para ONDE ESTAMOS)

- [ ] **Step 1: Rodar a suíte inteira**

```bash
npm run teste:tudo
```

Esperado: os 39 que já passavam **mais** os dois novos = 41 passam, 0 falham.
Se algum dos 39 antigos ficar vermelho, **pare**: a 065/066 mexeu em algo que
não devia.

- [ ] **Step 2: Build limpo**

```bash
npm run build
```

Esperado: `tsc` sem erro e o bundle gerado.

- [ ] **Step 3: Conferir ao vivo, com gente de verdade**

Entre em `https://la-teacher.vercel.app/app/coordenacao` com a conta do Alf.
Confirme os três: a faixa bate com o que a `vw_presenca_pendencia` diz, a fila
está por urgência, e o recado chega no WhatsApp do professor de teste.

**Não marque esta tarefa como pronta sem o recado ter chegado.** Código pronto
não é funcionalidade no ar.

- [ ] **Step 4: Atualizar o RETOMADA e commitar**

```bash
git add RETOMADA.md
git commit -m "docs(retomada): o painel da coordenacao esta no ar"
git push origin main
```

---

## Parte 2 (plano próprio, ainda não escrito)

O bloco 2 — "o que os professores registraram" — sai deste plano de propósito:
ele depende do **Fábio gerar os sinais**, o que é skill nova + worker na VPS +
tabela `fabio_registro_sinais`. Subsistema independente, e hoje com **1 professor
alimentando** contra as 847 linhas que o bloco 1 já tem.

Escopo da parte 2, para não se perder:

1. Tabela `fabio_registro_sinais` (`registro_id`, `tipo`, `motivo`,
   `skill_versao`, `criado_em`) + RLS + revoke.
2. Skill do Fábio que lê o registro e grava o sinal — tipos `risco`, `destaque`,
   `estagnacao`.
3. `estagnacao` pelo `eixos`: **60 dias sem eixo novo, mínimo 4 registros no
   período** (sem o mínimo, aluno que faltou o mês vira falso positivo).
4. `silencio_professor` **não é linha na tabela** — é derivado na consulta,
   comparando o ritmo do professor com o dele mesmo.
5. RPC `app_coordenacao_sinais` + o bloco na tela.
6. Adiados com motivo medido: repertório (texto livre) e Jornada Pedagógica
   (não existe o lado do "deveria").
