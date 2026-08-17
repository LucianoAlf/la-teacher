# Consulta letiva do professor (Fase 1) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dar ao professor a resposta sobre a própria vida letiva ("quantas aulas eu dei de 11 a 15/08?", "quantas no Recreio?", "quem faltou?") sem expor financeiro nem dado de outro professor.

**Architecture:** Abordagem **A** — o bridge (que já sabe quem é o professor pela linha da mensagem) classifica a pergunta, extrai período/unidade/métrica de forma determinística, chama uma RPC canônica `security definer` com o `professor_id` que ele já tem, e injeta o resultado no prompt. O Fábio apenas **narra**. O `no_mcp` do Fábio continua intacto: ele nunca ganha acesso ao banco.

**Tech Stack:** PostgreSQL/Supabase (projeto `ouqwbbermlzqqvtqwlul`), PL/pgSQL, Python 3.12 (bridge na VPS, `unittest`), Node (runners de teste/mutante), Docker (`postgres:17-alpine`).

**Spec:** `docs/superpowers/specs/2026-08-17-consulta-letiva-professor-design.md`

## Global Constraints

- `professor_id` vem SEMPRE de `row["professor_id"]` da linha da mensagem — **nunca** do texto do usuário.
- Nenhuma RPC retorna financeiro: `valor_`, `mensalidade`, `pagamento`, `repasse`, `contrato`, `desconto`, `bolsa`, `fatura`, `folha`. Verificado por teste de catálogo.
- Contagem de aulas deduplica por `public.fn_aula_operacional_id(...)`. **Nunca** `count(*)` de linha crua.
- Presença vem de `public.vw_aluno_presenca_semantica_v1`. Os baldes `presentes`, `faltas`, `falta_provavel`, `indeterminado`, `nao_aplicavel` são **separados e jamais somados**.
- `falta_provavel` é identificado por `situacao_chamada = 'registrada_inferida'` — **nunca** por `proveniencia = 'emusys'`.
- Toda RPC: `security definer`, `set search_path to 'pg_catalog', 'public'`, `revoke all ... from public, anon, authenticated`, `grant execute ... to service_role`.
- **Nenhuma migration é aplicada em produção sem OK explícito do Alf.** Ensaio = `BEGIN/ROLLBACK` + mutantes em Docker.
- Duas sessões no mesmo checkout: `git add <arquivos exatos>`, nunca `-A`/`.`/`stash`/`reset --hard`. `ls supabase/migrations` no disco antes de numerar.
- Caso canônico obrigatório: professor 36 (Valdo), 11–15/08/2026 → **36 aulas**, Campo Grande 25, Recreio 11. **Nunca 74 nem 76.**
- Segundo caso canônico (baldes de presença): professor 35 (Rodrigo), 11–15/08/2026 → presentes 40, faltas 7, falta_provavel 6, nao_aplicavel 7.
- Timestamps de migration reservados: `20260817120000` (resumo de aulas), `20260817130000` (presenças). Conferidos livres no disco em 17/08.
- Rollout: **1a** shadow (loga, não muda resposta) → **1b** só professores 36 (Valdo) e 25 (Matheus Felipe Lourenço) → **1c** todos.

---

## File Structure

| Arquivo | Responsabilidade |
|---|---|
| `supabase/migrations/20260817120000_consulta_letiva_resumo_aulas.sql` | RPC `fabio_professor_resumo_aulas` |
| `supabase/migrations/20260817120000_consulta_letiva_resumo_aulas.test.sql` | Contrato de catálogo + caso Valdo em rollback; bloco Docker comentado |
| `scripts/mutantes-20260817120000.mjs` | Mutantes da RPC de aulas (inclui "linha crua = 74") |
| `supabase/migrations/20260817130000_consulta_letiva_presencas.sql` | RPC `fabio_professor_presencas_periodo` |
| `supabase/migrations/20260817130000_consulta_letiva_presencas.test.sql` | Contrato de catálogo + caso Rodrigo em rollback; bloco Docker comentado |
| `scripts/mutantes-20260817130000.mjs` | Mutantes da RPC de presenças (baldes somados) |
| `vps/fabio/fabio_whatsapp_intents.py` | Funções puras: `resolver_periodo`, `extrair_consulta_letiva` |
| `vps/fabio/teste_whatsapp_intents.py` | Testes do extrator |
| `vps/fabio/fabio_whatsapp_actions.py` | Conserto: `ambiguo` em texto não abre ação |
| `vps/fabio/teste_whatsapp_actions.py` | Teste do conserto do roteador |
| `vps/fabio/fabio_chat_bridge.py` | Wiring em shadow: chama RPC, loga, injeta no prompt conforme o gate |

**Ordem:** Tasks 1 e 2 são independentes entre si. Task 3 é independente de 1 e 2. Task 4 é independente de tudo. Task 5 consome 1, 2 e 3.

---

## Task 1: RPC `fabio_professor_resumo_aulas`

**Files:**
- Create: `supabase/migrations/20260817120000_consulta_letiva_resumo_aulas.sql`
- Create: `supabase/migrations/20260817120000_consulta_letiva_resumo_aulas.test.sql`
- Create: `scripts/mutantes-20260817120000.mjs`

**Interfaces:**
- Consumes: `public.fn_aula_operacional_id(integer) returns integer` (já existe, `stable security definer`); tabelas `public.aulas_emusys`, `public.unidades`, `public.fabio_registros_aula`.
- Produces: `public.fabio_professor_resumo_aulas(p_professor_id integer, p_inicio date, p_fim date, p_unidade text default null) returns jsonb` → `{ok, periodo:{inicio,fim}, total_aulas, por_unidade:[{unidade,aulas}], por_dia:[{data,aulas}], registradas, sem_registro}`. Em erro: `{ok:false, motivo:'parametros_obrigatorios'|'periodo_invertido'|'janela_maior_que_90_dias'}`.

- [ ] **Step 1: Conferir que o número da migration está livre no DISCO**

```bash
ls supabase/migrations | grep 20260817
```
Esperado: nenhuma linha. Se houver, renumerar para o próximo horário livre e ajustar todos os nomes de arquivo desta tarefa.

- [ ] **Step 2: Escrever o teste (contrato de catálogo + caso Valdo)**

Criar `supabase/migrations/20260817120000_consulta_letiva_resumo_aulas.test.sql`:

```sql
-- Parte executada remotamente (rollback contra producao): contrato de catalogo
-- (existencia, portas fechadas, ZERO identificador financeiro) + o caso
-- canonico do Valdo, que roda contra o dado real porque a RPC e read-only.
-- O bloco Docker no fim fica comentado e o runner de mutantes o extrai.

create temporary table pg_temp._res (caso text, ok boolean, detalhe text) on commit drop;

create or replace function pg_temp.checar(p_caso text, p_ok boolean, p_detalhe text)
returns void language plpgsql as $function$
begin
  insert into pg_temp._res(caso, ok, detalhe) values (p_caso, coalesce(p_ok,false), p_detalhe);
end
$function$;

do $function$
declare
  v_fn oid := to_regprocedure('public.fabio_professor_resumo_aulas(integer,date,date,text)');
  v_def text;
  v_res jsonb;
  v_cru integer;
begin
  perform pg_temp.checar('a RPC existe', v_fn is not null, coalesce(v_fn::text,'<ausente>'));
  if v_fn is null then return; end if;

  perform pg_temp.checar('service_role executa; anon/authenticated nao',
    has_function_privilege('service_role', v_fn, 'EXECUTE')
    and not has_function_privilege('anon', v_fn, 'EXECUTE')
    and not has_function_privilege('authenticated', v_fn, 'EXECUTE'),
    'grants');

  -- Fronteira do financeiro: porta que nao existe, verificada no corpo.
  v_def := pg_get_functiondef(v_fn);
  perform pg_temp.checar('nenhum identificador financeiro no corpo',
    v_def !~* '(valor_|mensalidade|pagamento|repasse|contrato|desconto|bolsa|fatura|folha)',
    'corpo da funcao');

  -- Caso canonico do Valdo (professor 36, 11-15/08). Semana passada e fechada:
  -- se este numero mudar, conferir PRIMEIRO se a agenda mudou, nao o codigo.
  v_res := public.fabio_professor_resumo_aulas(36, date '2026-08-11', date '2026-08-15', null);
  perform pg_temp.checar('Valdo 11-15/08 = 36 aulas',
    (v_res->>'total_aulas')::int = 36, coalesce(v_res->>'total_aulas','<nulo>'));

  -- A armadilha: linha crua devolve 74. A RPC NUNCA pode devolver isso.
  select count(*) into v_cru from public.aulas_emusys ae
   where ae.professor_id=36 and ae.data_aula between date '2026-08-11' and date '2026-08-15'
     and coalesce(ae.cancelada,false)=false;
  perform pg_temp.checar('a linha crua realmente dobra (armadilha viva)', v_cru = 74, v_cru::text);
  perform pg_temp.checar('a RPC nao devolve a contagem crua',
    (v_res->>'total_aulas')::int <> v_cru, format('rpc=%s cru=%s', v_res->>'total_aulas', v_cru));

  perform pg_temp.checar('por_unidade: Campo Grande 25',
    (select (x->>'aulas')::int from jsonb_array_elements(v_res->'por_unidade') x
      where x->>'unidade' = 'Campo Grande') = 25, v_res->>'por_unidade');
  perform pg_temp.checar('por_unidade: Recreio 11',
    (select (x->>'aulas')::int from jsonb_array_elements(v_res->'por_unidade') x
      where x->>'unidade' = 'Recreio') = 11, v_res->>'por_unidade');
  perform pg_temp.checar('por_dia soma o total',
    (select sum((x->>'aulas')::int) from jsonb_array_elements(v_res->'por_dia') x) = 36,
    v_res->>'por_dia');
  perform pg_temp.checar('registradas + sem_registro = total',
    (v_res->>'registradas')::int + (v_res->>'sem_registro')::int = 36,
    format('%s + %s', v_res->>'registradas', v_res->>'sem_registro'));

  -- Recorte por unidade
  v_res := public.fabio_professor_resumo_aulas(36, date '2026-08-11', date '2026-08-15', 'Recreio');
  perform pg_temp.checar('recorte Recreio = 11', (v_res->>'total_aulas')::int = 11,
    coalesce(v_res->>'total_aulas','<nulo>'));

  -- Guardas de parametro
  perform pg_temp.checar('periodo invertido recusa',
    (public.fabio_professor_resumo_aulas(36, date '2026-08-15', date '2026-08-11', null)->>'motivo') = 'periodo_invertido', 'invertido');
  perform pg_temp.checar('janela > 90 dias recusa',
    (public.fabio_professor_resumo_aulas(36, date '2026-01-01', date '2026-08-15', null)->>'motivo') = 'janela_maior_que_90_dias', 'janela');
end
$function$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._res where not ok),
  'detalhe', coalesce((select json_agg(json_build_object('passo', caso, 'esperado','true','obtido', detalhe) order by caso)
                         from pg_temp._res where not ok), '[]'::json)
) as resumo;

/* RESUMO-AULAS-DOCKER-DML-TESTS-INICIO
-- Roda so no PostgreSQL efemero do mutante. O bootstrap (no .mjs) ja criou
-- unidades, aulas_emusys com DUAS linhas por aula (a armadilha), o
-- fn_aula_operacional_id fake que colapsa o par, e fabio_registros_aula.
do $docker$
declare
  v_res jsonb;
begin
  v_res := public.fabio_professor_resumo_aulas(36, date '2026-08-11', date '2026-08-15', null);
  -- 4 aulas operacionais, 8 linhas cruas
  perform pg_temp.checar('docker: total colapsa 8 linhas em 4 aulas',
    (v_res->>'total_aulas')::int = 4, coalesce(v_res->>'total_aulas','<nulo>'));
  perform pg_temp.checar('docker: cancelada fora da contagem',
    (v_res->>'total_aulas')::int <> 5, coalesce(v_res->>'total_aulas','<nulo>'));
  perform pg_temp.checar('docker: por_unidade CG 3 / Recreio 1',
    (select (x->>'aulas')::int from jsonb_array_elements(v_res->'por_unidade') x where x->>'unidade'='Campo Grande') = 3
    and (select (x->>'aulas')::int from jsonb_array_elements(v_res->'por_unidade') x where x->>'unidade'='Recreio') = 1,
    v_res->>'por_unidade');
  perform pg_temp.checar('docker: registradas 2 / sem_registro 2',
    (v_res->>'registradas')::int = 2 and (v_res->>'sem_registro')::int = 2,
    format('%s/%s', v_res->>'registradas', v_res->>'sem_registro'));
  perform pg_temp.checar('docker: outro professor nao vaza',
    (public.fabio_professor_resumo_aulas(99, date '2026-08-11', date '2026-08-15', null)->>'total_aulas')::int = 0,
    'isolamento por professor');
end
$docker$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._res where not ok),
  'detalhe', coalesce((select json_agg(json_build_object('passo', caso, 'esperado','true','obtido', detalhe) order by caso)
                         from pg_temp._res where not ok), '[]'::json)
) as resumo;
RESUMO-AULAS-DOCKER-DML-TESTS-FIM */
```

- [ ] **Step 3: Rodar o teste e ver falhar**

```bash
node scripts/rodar-teste-sql.mjs supabase/migrations/20260817120000_consulta_letiva_resumo_aulas.sql supabase/migrations/20260817120000_consulta_letiva_resumo_aulas.test.sql
```
Esperado: FALHA — o arquivo de migration ainda não existe.

- [ ] **Step 4: Escrever a migration**

Criar `supabase/migrations/20260817120000_consulta_letiva_resumo_aulas.sql`:

```sql
-- Consulta letiva do professor (Fase 1): quantas aulas ele deu num periodo.
-- Read-only. O professor_id vem do BRIDGE (linha da mensagem), nunca do texto.
-- NAO le contrato/mensalidade/repasse/folha: a fronteira do financeiro e uma
-- porta que nao existe, e o teste de catalogo verifica o corpo desta funcao.
--
-- A contagem colapsa eventos pelo fn_aula_operacional_id: desde 09/07 o mesmo
-- horario aparece 2x em aulas_emusys (id de EVENTO), e contar linha crua
-- devolveria 74 no lugar de 36 na semana do Valdo.

create or replace function public.fabio_professor_resumo_aulas(
  p_professor_id integer,
  p_inicio       date,
  p_fim          date,
  p_unidade      text default null
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $fn$
begin
  if p_professor_id is null or p_inicio is null or p_fim is null then
    return jsonb_build_object('ok', false, 'motivo', 'parametros_obrigatorios');
  end if;
  if p_fim < p_inicio then
    return jsonb_build_object('ok', false, 'motivo', 'periodo_invertido');
  end if;
  if (p_fim - p_inicio) > 90 then
    return jsonb_build_object('ok', false, 'motivo', 'janela_maior_que_90_dias');
  end if;

  return (
    with base as (
      select distinct
        coalesce(public.fn_aula_operacional_id(ae.id), ae.id) as aula_op,
        ae.data_aula,
        u.nome as unidade
      from public.aulas_emusys ae
      left join public.unidades u on u.id = ae.unidade_id
      where ae.professor_id = p_professor_id
        and ae.data_aula between p_inicio and p_fim
        and coalesce(ae.cancelada, false) = false
        and (p_unidade is null or u.nome ilike p_unidade)
    ),
    marcada as (
      select b.*,
             exists (
               select 1
                 from public.fabio_registros_aula r
                where r.aula_id = b.aula_op
                  and r.parent_id is null
                  and r.status in ('confirmado', 'gravado_emusys')
             ) as tem_registro
        from base b
    )
    select jsonb_build_object(
      'ok', true,
      'periodo', jsonb_build_object('inicio', p_inicio, 'fim', p_fim),
      'total_aulas', count(*),
      'por_unidade', (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'unidade', coalesce(unidade, '(sem unidade)'), 'aulas', n)
                 order by n desc, coalesce(unidade, '(sem unidade)')), '[]'::jsonb)
          from (select unidade, count(*) as n from marcada group by unidade) q
      ),
      'por_dia', (
        select coalesce(jsonb_agg(jsonb_build_object('data', data_aula, 'aulas', n)
                 order by data_aula), '[]'::jsonb)
          from (select data_aula, count(*) as n from marcada group by data_aula) q
      ),
      'registradas', count(*) filter (where tem_registro),
      'sem_registro', count(*) filter (where not tem_registro)
    )
    from marcada
  );
end
$fn$;

comment on function public.fabio_professor_resumo_aulas(integer, date, date, text) is
  'Consulta letiva Fase 1: total de aulas do PROPRIO professor num periodo, deduplicado por fn_aula_operacional_id. Read-only, sem financeiro.';

revoke all on function public.fabio_professor_resumo_aulas(integer, date, date, text) from public, anon, authenticated;
grant execute on function public.fabio_professor_resumo_aulas(integer, date, date, text) to service_role;
```

- [ ] **Step 5: Rodar o teste e ver passar**

```bash
node scripts/rodar-teste-sql.mjs supabase/migrations/20260817120000_consulta_letiva_resumo_aulas.sql supabase/migrations/20260817120000_consulta_letiva_resumo_aulas.test.sql
```
Esperado: `nenhuma divergência` + linhas vivas e schema idênticos antes/depois.

- [ ] **Step 6: Escrever o runner de mutantes**

Criar `scripts/mutantes-20260817120000.mjs` copiando a estrutura de `scripts/mutantes-20260815140000.mjs`. O bootstrap deve criar, num `postgres:17-alpine` descartável:

```sql
create table public.unidades (id uuid primary key, nome text);
insert into public.unidades values
  ('11111111-1111-1111-1111-111111111111','Campo Grande'),
  ('22222222-2222-2222-2222-222222222222','Recreio');

create table public.aulas_emusys (
  id integer primary key, professor_id integer, unidade_id uuid,
  data_aula date, cancelada boolean default false
);
-- A ARMADILHA: cada aula operacional tem DUAS linhas (id de evento).
-- 4 aulas operacionais (3 CG + 1 Recreio) = 8 linhas; + 1 cancelada (2 linhas).
insert into public.aulas_emusys values
  (1,36,'11111111-1111-1111-1111-111111111111',date '2026-08-11',false),
  (2,36,'11111111-1111-1111-1111-111111111111',date '2026-08-11',false),
  (3,36,'11111111-1111-1111-1111-111111111111',date '2026-08-12',false),
  (4,36,'11111111-1111-1111-1111-111111111111',date '2026-08-12',false),
  (5,36,'11111111-1111-1111-1111-111111111111',date '2026-08-13',false),
  (6,36,'11111111-1111-1111-1111-111111111111',date '2026-08-13',false),
  (7,36,'22222222-2222-2222-2222-222222222222',date '2026-08-14',false),
  (8,36,'22222222-2222-2222-2222-222222222222',date '2026-08-14',false),
  (9,36,'11111111-1111-1111-1111-111111111111',date '2026-08-15',true),
  (10,36,'11111111-1111-1111-1111-111111111111',date '2026-08-15',true);

-- Colapsa o par: id impar e o operacional; o par aponta pro impar anterior.
create or replace function public.fn_aula_operacional_id(p_aula_id integer)
returns integer language sql stable as $f$
  select case when p_aula_id % 2 = 0 then p_aula_id - 1 else p_aula_id end
$f$;

create table public.fabio_registros_aula (
  id serial primary key, aula_id integer, parent_id integer,
  status text, professor_id integer
);
-- 2 das 4 aulas operacionais tem registro concluido
insert into public.fabio_registros_aula (aula_id, parent_id, status, professor_id) values
  (1, null, 'gravado_emusys', 36),
  (3, null, 'confirmado', 36),
  (5, null, 'rascunho', 36);   -- rascunho NAO conta como registrada
```

Mutantes (cada um tem que morrer **por asserção**, não por erro de sintaxe):

| # | mutação | o que prova |
|---|---|---|
| 1 | trocar `coalesce(public.fn_aula_operacional_id(ae.id), ae.id)` por `ae.id` | volta a contar linha crua (8 em vez de 4) |
| 2 | remover `and coalesce(ae.cancelada, false) = false` | aula cancelada entra (5 em vez de 4) |
| 3 | remover o `distinct` do `base` | duplica mesmo com o colapso |
| 4 | trocar `r.status in ('confirmado','gravado_emusys')` por `true` | rascunho passa a contar como registrada (3 em vez de 2) |
| 5 | remover `and ae.professor_id = p_professor_id` | vaza aula de outro professor |
| 6 | trocar o filtro `p_unidade` por sempre-verdadeiro | recorte por unidade para de recortar |
| 7 | acrescentar `'valor_hora_aula', 120` ao `jsonb_build_object` do retorno | **a fronteira do financeiro**: o teste de catálogo tem que matar isso |

> O mutante 7 é o que prova que a fronteira é porta e não promessa. O bootstrap
> do Docker precisa incluir a parte de catálogo do `.test.sql` (a asserção
> `nenhum identificador financeiro no corpo`), senão ele morre por nada e passa
> por morto — verde não-falsificado.

- [ ] **Step 7: Rodar os mutantes**

```bash
node scripts/mutantes-20260817120000.mjs
```
Esperado: `OK baseline verde` + `6/6 mutantes mortos`. Se algum sobreviver, o teste não cobre o caso — **corrigir o teste, nunca afrouxar o mutante**.

- [ ] **Step 8: Commit**

```bash
git add supabase/migrations/20260817120000_consulta_letiva_resumo_aulas.sql supabase/migrations/20260817120000_consulta_letiva_resumo_aulas.test.sql scripts/mutantes-20260817120000.mjs
git commit -m "feat(consulta-letiva): RPC de resumo de aulas do professor (dedup por aula operacional)"
```

---

## Task 2: RPC `fabio_professor_presencas_periodo`

**Files:**
- Create: `supabase/migrations/20260817130000_consulta_letiva_presencas.sql`
- Create: `supabase/migrations/20260817130000_consulta_letiva_presencas.test.sql`
- Create: `scripts/mutantes-20260817130000.mjs`

**Interfaces:**
- Consumes: `public.vw_aluno_presenca_semantica_v1` (colunas usadas: `aluno_id`, `professor_id`, `data_aula`, `curso_nome`, `situacao_chamada`, `resultado_pedagogico`, `considera_presenca`, `considera_falta`); `public.alunos(id, nome)`.
- Produces: `public.fabio_professor_presencas_periodo(p_professor_id integer, p_inicio date, p_fim date) returns jsonb` → `{ok, periodo:{inicio,fim}, presentes, faltas:[{aluno,data,curso}], falta_provavel:[...], indeterminado:[...], nao_aplicavel:[{aluno,data,motivo}]}`. Erros iguais aos da Task 1.

- [ ] **Step 1: Escrever o teste**

Criar `supabase/migrations/20260817130000_consulta_letiva_presencas.test.sql` com o mesmo esqueleto de `pg_temp._res` / `pg_temp.checar` da Task 1 (repetido aqui de propósito — cada arquivo de teste é autocontido), e estas asserções na parte remota:

```sql
do $function$
declare
  v_fn oid := to_regprocedure('public.fabio_professor_presencas_periodo(integer,date,date)');
  v_def text;
  v_res jsonb;
begin
  perform pg_temp.checar('a RPC existe', v_fn is not null, coalesce(v_fn::text,'<ausente>'));
  if v_fn is null then return; end if;

  perform pg_temp.checar('service_role executa; anon/authenticated nao',
    has_function_privilege('service_role', v_fn, 'EXECUTE')
    and not has_function_privilege('anon', v_fn, 'EXECUTE')
    and not has_function_privilege('authenticated', v_fn, 'EXECUTE'), 'grants');

  v_def := pg_get_functiondef(v_fn);
  perform pg_temp.checar('nenhum identificador financeiro no corpo',
    v_def !~* '(valor_|mensalidade|pagamento|repasse|contrato|desconto|bolsa|fatura|folha)', 'corpo');

  -- O balde provavel NAO pode ser derivado de proveniencia: no dia em que a
  -- secretaria vereditar um caso do Emusys, a linha continua com proveniencia
  -- 'emusys' e voltaria a ser contada como provavel depois de virar falta.
  perform pg_temp.checar('nao classifica por proveniencia',
    v_def !~* 'proveniencia', 'corpo');

  -- Caso canonico dos baldes: professor 35 (Rodrigo), 11-15/08.
  v_res := public.fabio_professor_presencas_periodo(35, date '2026-08-11', date '2026-08-15');
  perform pg_temp.checar('Rodrigo: presentes 40', (v_res->>'presentes')::int = 40, v_res->>'presentes');
  perform pg_temp.checar('Rodrigo: faltas 7',
    jsonb_array_length(v_res->'faltas') = 7, (v_res->'faltas')::text);
  perform pg_temp.checar('Rodrigo: falta_provavel 6',
    jsonb_array_length(v_res->'falta_provavel') = 6, (v_res->'falta_provavel')::text);
  perform pg_temp.checar('Rodrigo: nao_aplicavel 7',
    jsonb_array_length(v_res->'nao_aplicavel') = 7, (v_res->'nao_aplicavel')::text);
  -- A asercao que protege aluno real: os baldes sao DISJUNTOS.
  perform pg_temp.checar('faltas nao engole falta_provavel',
    jsonb_array_length(v_res->'faltas') <> 13, 'faltas+provavel somados');

  -- Valdo (36) na mesma semana: 61 presentes, 11 faltas, 0 provavel, 6 nao aplicavel
  v_res := public.fabio_professor_presencas_periodo(36, date '2026-08-11', date '2026-08-15');
  perform pg_temp.checar('Valdo: 11 faltas', jsonb_array_length(v_res->'faltas') = 11, (v_res->'faltas')::text);
  perform pg_temp.checar('Valdo: 0 falta_provavel',
    jsonb_array_length(v_res->'falta_provavel') = 0, (v_res->'falta_provavel')::text);

  perform pg_temp.checar('periodo invertido recusa',
    (public.fabio_professor_presencas_periodo(36, date '2026-08-15', date '2026-08-11')->>'motivo') = 'periodo_invertido', 'invertido');
end
$function$;
```

> ⚠️ Os números do Rodrigo (6 prováveis) mudam se a secretaria vereditar esses casos. Se a asserção quebrar, **conferir primeiro se o veredito chegou** (`select situacao_chamada ... where professor_id=35 and data_aula between ...`) antes de suspeitar do código. A prova estrutural que **não** depende de dado vivo é a dos mutantes em Docker, no Step 5.

Bloco Docker comentado (`PRESENCAS-DOCKER-DML-TESTS-INICIO` / `-FIM`) com:

```sql
do $docker$
declare v_res jsonb;
begin
  v_res := public.fabio_professor_presencas_periodo(36, date '2026-08-11', date '2026-08-15');
  perform pg_temp.checar('docker: presentes 3', (v_res->>'presentes')::int = 3, v_res->>'presentes');
  perform pg_temp.checar('docker: faltas 2', jsonb_array_length(v_res->'faltas') = 2, (v_res->'faltas')::text);
  perform pg_temp.checar('docker: falta_provavel 2', jsonb_array_length(v_res->'falta_provavel') = 2, (v_res->'falta_provavel')::text);
  perform pg_temp.checar('docker: indeterminado 1', jsonb_array_length(v_res->'indeterminado') = 1, (v_res->'indeterminado')::text);
  perform pg_temp.checar('docker: nao_aplicavel 1', jsonb_array_length(v_res->'nao_aplicavel') = 1, (v_res->'nao_aplicavel')::text);
  perform pg_temp.checar('docker: outro professor nao vaza',
    (public.fabio_professor_presencas_periodo(99, date '2026-08-11', date '2026-08-15')->>'presentes')::int = 0, 'isolamento');
end
$docker$;
```

- [ ] **Step 2: Rodar e ver falhar**

```bash
node scripts/rodar-teste-sql.mjs supabase/migrations/20260817130000_consulta_letiva_presencas.sql supabase/migrations/20260817130000_consulta_letiva_presencas.test.sql
```
Esperado: FALHA — migration inexistente.

- [ ] **Step 3: Escrever a migration**

```sql
-- Consulta letiva do professor (Fase 1): quem faltou no periodo, com os baldes
-- SEPARADOS. Le a vw_aluno_presenca_semantica_v1, que implementa o contrato
-- v1.4: a ausencia do Emusys e PENDENCIA, nao falta. Somar 'falta_provavel'
-- dentro de 'faltas' reintroduziria a mentira que o contrato eliminou (em junho
-- foram 3.066 "faltas" que nenhum humano afirmou).
--
-- O balde provavel e identificado por situacao_chamada='registrada_inferida',
-- NUNCA por proveniencia='emusys': quando a secretaria vereditar um caso, a
-- linha continua com proveniencia emusys e viraria provavel de novo.

create or replace function public.fabio_professor_presencas_periodo(
  p_professor_id integer,
  p_inicio       date,
  p_fim          date
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $fn$
begin
  if p_professor_id is null or p_inicio is null or p_fim is null then
    return jsonb_build_object('ok', false, 'motivo', 'parametros_obrigatorios');
  end if;
  if p_fim < p_inicio then
    return jsonb_build_object('ok', false, 'motivo', 'periodo_invertido');
  end if;
  if (p_fim - p_inicio) > 90 then
    return jsonb_build_object('ok', false, 'motivo', 'janela_maior_que_90_dias');
  end if;

  return (
    with base as (
      select v.data_aula,
             v.curso_nome,
             v.situacao_chamada,
             v.resultado_pedagogico,
             v.considera_presenca,
             v.considera_falta,
             al.nome as aluno_nome
        from public.vw_aluno_presenca_semantica_v1 v
        join public.alunos al on al.id = v.aluno_id
       where v.professor_id = p_professor_id
         and v.data_aula between p_inicio and p_fim
    )
    select jsonb_build_object(
      'ok', true,
      'periodo', jsonb_build_object('inicio', p_inicio, 'fim', p_fim),
      'presentes', count(*) filter (where considera_presenca),
      'faltas', (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'aluno', aluno_nome, 'data', data_aula, 'curso', curso_nome)
                 order by data_aula, aluno_nome), '[]'::jsonb)
          from base where considera_falta
      ),
      'falta_provavel', (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'aluno', aluno_nome, 'data', data_aula, 'curso', curso_nome)
                 order by data_aula, aluno_nome), '[]'::jsonb)
          from base where situacao_chamada = 'registrada_inferida'
      ),
      'indeterminado', (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'aluno', aluno_nome, 'data', data_aula, 'curso', curso_nome)
                 order by data_aula, aluno_nome), '[]'::jsonb)
          from base where situacao_chamada = 'indeterminada'
      ),
      'nao_aplicavel', (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'aluno', aluno_nome, 'data', data_aula, 'motivo', resultado_pedagogico)
                 order by data_aula, aluno_nome), '[]'::jsonb)
          from base where situacao_chamada = 'nao_aplicavel'
      )
    )
    from base
  );
end
$fn$;

comment on function public.fabio_professor_presencas_periodo(integer, date, date) is
  'Consulta letiva Fase 1: presencas do PROPRIO professor num periodo, com faltas/falta_provavel/indeterminado/nao_aplicavel SEPARADOS. Read-only, sem financeiro.';

revoke all on function public.fabio_professor_presencas_periodo(integer, date, date) from public, anon, authenticated;
grant execute on function public.fabio_professor_presencas_periodo(integer, date, date) to service_role;
```

- [ ] **Step 4: Rodar e ver passar**

```bash
node scripts/rodar-teste-sql.mjs supabase/migrations/20260817130000_consulta_letiva_presencas.sql supabase/migrations/20260817130000_consulta_letiva_presencas.test.sql
```
Esperado: `nenhuma divergência`.

- [ ] **Step 5: Runner de mutantes**

Criar `scripts/mutantes-20260817130000.mjs`. Bootstrap em Docker (a view semântica é complexa; em Docker ela vira **tabela** com as colunas que a RPC lê):

```sql
create table public.alunos (id integer primary key, nome text);
insert into public.alunos values (1,'Ana'),(2,'Bruno'),(3,'Carla'),(4,'Diego'),
  (5,'Elis'),(6,'Fabio A'),(7,'Gil'),(8,'Hugo'),(9,'Iara');

create table public.vw_aluno_presenca_semantica_v1 (
  aluno_id integer, professor_id integer, data_aula date, curso_nome text,
  situacao_chamada text, resultado_pedagogico text,
  considera_presenca boolean, considera_falta boolean, proveniencia text
);
insert into public.vw_aluno_presenca_semantica_v1 values
  (1,36,date '2026-08-11','Piano','registrada','presente',true,false,'agenda_secretaria'),
  (2,36,date '2026-08-11','Piano','registrada','presente',true,false,'la_teacher'),
  (3,36,date '2026-08-12','Piano','registrada','presente',true,false,'emusys'),
  (4,36,date '2026-08-12','Piano','registrada_atestada','falta_confirmada',false,true,'agenda_secretaria'),
  (5,36,date '2026-08-13','Piano','registrada','falta_confirmada',false,true,'la_teacher'),
  (6,36,date '2026-08-13','Piano','registrada_inferida','falta_provavel',false,false,'emusys'),
  (7,36,date '2026-08-14','Piano','registrada_inferida','falta_provavel',false,false,'emusys'),
  (8,36,date '2026-08-14','Piano','indeterminada','indeterminado',false,false,'emusys'),
  (9,36,date '2026-08-15','Piano','nao_aplicavel','aula_justificada',false,false,'emusys');
```

Mutantes:

| # | mutação | o que prova |
|---|---|---|
| 1 | trocar `where considera_falta` por `where considera_falta or situacao_chamada='registrada_inferida'` | soma provável em faltas (2 → 4) |
| 2 | trocar `where considera_falta` por `where not considera_presenca` | engole indeterminado e não aplicável em faltas |
| 3 | trocar `situacao_chamada = 'registrada_inferida'` por `proveniencia = 'emusys'` | classifica por procedência (o balde provável passa a ter 5) |
| 4 | remover `and v.professor_id = p_professor_id` | vaza presença de outro professor |
| 5 | remover o filtro de `data_aula` | ignora o período |
| 6 | trocar `join public.alunos` por `left join` sem `al.nome` — devolver `aluno_id` cru | expõe id em vez de nome (contrato do retorno) |
| 7 | acrescentar `'mensalidade_aluno', 350` ao `jsonb_build_object` do retorno | **a fronteira do financeiro**: o teste de catálogo tem que matar isso |

- [ ] **Step 6: Rodar os mutantes**

```bash
node scripts/mutantes-20260817130000.mjs
```
Esperado: `OK baseline verde` + `6/6 mutantes mortos`.

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/20260817130000_consulta_letiva_presencas.sql supabase/migrations/20260817130000_consulta_letiva_presencas.test.sql scripts/mutantes-20260817130000.mjs
git commit -m "feat(consulta-letiva): RPC de presencas do professor com os baldes separados"
```

---

## Task 3: Extrator determinístico de consulta letiva

**Files:**
- Modify: `vps/fabio/fabio_whatsapp_intents.py`
- Test: `vps/fabio/teste_whatsapp_intents.py`

**Interfaces:**
- Consumes: helpers já existentes no módulo — `_norm(value) -> str`.
- Produces:
  - `resolver_periodo(texto: str, hoje: date) -> tuple[date, date] | None`
  - `extrair_consulta_letiva(texto: str, hoje: date, unidades: list[str]) -> dict | None` → `{"metrica": "aulas"|"presencas", "inicio": date, "fim": date, "unidade": str | None}` ou `None`.
  - `montar_chamada_consulta(row: dict, hoje: date, unidades: list[str]) -> dict | None` → `{"rpc": str, "payload": dict, "pedido": dict}` ou `None`. **É esta função que amarra a identidade**: o `p_professor_id` sai de `row["professor_id"]`, nunca do texto. Existe como função pura justamente para o ataque ser testável sem subir o bridge.
  - `parece_consulta_letiva(texto: str) -> bool` — predicado puro, sem data nem unidades, usado pelo roteador em `actions.py` (que não conhece nenhum dos dois) para não abrir ação de chamada em cima de uma pergunta.

**Nota de desenho:** o extrator é **determinístico** — é a trava. A classificação de intenção continua com o classificador existente. Se o extrator devolver `None` para uma mensagem classificada como consulta, o Fábio **pergunta o período**; ele nunca chuta (foi o chute que criou o defeito do "Ok").

- [ ] **Step 1: Escrever os testes**

Adicionar em `vps/fabio/teste_whatsapp_intents.py` (a classe é `WhatsappIntentsTest`):

```python
    # ── Consulta letiva (Fase 1) ─────────────────────────────────────────────
    # 17/08 e uma segunda-feira; "semana passada" = 10/08 a 16/08.

    def test_consulta_periodo_explicito_do_valdo(self):
        r = extrair_consulta_letiva(
            "Na semana passada de terça-feira dia 11/08 ate sábado dia 15/08 "
            "me informe o total de aulas que eu dei",
            date(2026, 8, 17), ["Campo Grande", "Recreio", "Barra"])
        self.assertEqual(r["metrica"], "aulas")
        self.assertEqual(r["inicio"], date(2026, 8, 11))
        self.assertEqual(r["fim"], date(2026, 8, 15))
        self.assertIsNone(r["unidade"])

    def test_consulta_com_unidade(self):
        r = extrair_consulta_letiva("quantas aulas eu dei no Recreio semana passada",
                                    date(2026, 8, 17), ["Campo Grande", "Recreio", "Barra"])
        self.assertEqual(r["metrica"], "aulas")
        self.assertEqual(r["unidade"], "Recreio")
        self.assertEqual((r["inicio"], r["fim"]), (date(2026, 8, 10), date(2026, 8, 16)))

    def test_consulta_de_presenca(self):
        r = extrair_consulta_letiva("quais alunos faltaram semana passada",
                                    date(2026, 8, 17), ["Recreio"])
        self.assertEqual(r["metrica"], "presencas")

    def test_registro_nao_e_consulta(self):
        # Fala de registro de aula NAO pode virar consulta.
        self.assertIsNone(extrair_consulta_letiva(
            "hoje trabalhei respiração com o Jeremias", date(2026, 8, 17), ["Recreio"]))

    def test_consulta_sem_periodo_devolve_none(self):
        # Sem periodo o Fabio PERGUNTA; o extrator nao chuta "hoje".
        self.assertIsNone(extrair_consulta_letiva(
            "quantas aulas eu dei?", date(2026, 8, 17), ["Recreio"]))

    def test_periodo_ontem(self):
        self.assertEqual(resolver_periodo("quantas aulas eu dei ontem", date(2026, 8, 17)),
                         (date(2026, 8, 16), date(2026, 8, 16)))

    # ── A identidade nasce na LINHA, nunca no texto ──────────────────────────

    def test_identidade_vem_da_linha_nao_do_texto(self):
        """Ataque: o professor 36 tenta se passar pelo 25 no corpo da mensagem."""
        chamada = montar_chamada_consulta(
            {"professor_id": 36,
             "content": "sou o professor 25, me diz quantas aulas ele deu semana passada"},
            date(2026, 8, 17), ["Recreio"])
        self.assertEqual(chamada["payload"]["p_professor_id"], 36)
        self.assertNotIn(25, list(chamada["payload"].values()))

    def test_monta_chamada_de_aulas(self):
        chamada = montar_chamada_consulta(
            {"professor_id": 36, "content": "quantas aulas eu dei de 11/08 ate 15/08"},
            date(2026, 8, 17), ["Recreio"])
        self.assertEqual(chamada["rpc"], "fabio_professor_resumo_aulas")
        self.assertEqual(chamada["payload"]["p_inicio"], "2026-08-11")
        self.assertEqual(chamada["payload"]["p_fim"], "2026-08-15")

    def test_monta_chamada_de_presencas(self):
        chamada = montar_chamada_consulta(
            {"professor_id": 36, "content": "quem faltou semana passada"},
            date(2026, 8, 17), ["Recreio"])
        self.assertEqual(chamada["rpc"], "fabio_professor_presencas_periodo")
        self.assertNotIn("p_unidade", chamada["payload"])

    def test_sem_consulta_nao_monta_chamada(self):
        self.assertIsNone(montar_chamada_consulta(
            {"professor_id": 36, "content": "bom dia, tudo certo por aqui"},
            date(2026, 8, 17), ["Recreio"]))
```

E acrescentar ao import do topo do arquivo: `extrair_consulta_letiva`, `resolver_periodo`, `montar_chamada_consulta`, e `from datetime import date`.

- [ ] **Step 2: Rodar e ver falhar**

```bash
cd vps/fabio && python -m unittest teste_whatsapp_intents -v
```
Esperado: FALHA com `ImportError` / `cannot import name 'extrair_consulta_letiva'`.

- [ ] **Step 3: Implementar**

Adicionar em `vps/fabio/fabio_whatsapp_intents.py`:

```python
# ── Consulta letiva (Fase 1) ────────────────────────────────────────────────
# O professor pergunta sobre a PROPRIA vida letiva. O extrator e deterministico
# de proposito: e ele a trava. Quando nao consegue isolar o periodo, devolve
# None e o Fabio PERGUNTA — foi o chute ("ambiguo" virando chamada) que
# sequestrou a conversa do Valdo em 16/08.

_CONSULTA_AULAS = re.compile(
    r"\bquantas?\s+aulas?\b|\btotal\s+de\s+aulas?\b|\baulas?\s+que\s+eu\s+dei\b|\bministrei\b"
)
_CONSULTA_PRESENCA = re.compile(
    r"\bquais?\s+alunos?\b.*\bfalt|\bquem\s+faltou\b|\bfaltaram\b|\bfaltas?\b|\bpresen[çc]as?\b"
)
_DATA_EXPLICITA = re.compile(r"\b(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?\b")


def resolver_periodo(texto: str, hoje: date) -> "tuple[date, date] | None":
    """Isola o período pedido. Devolve None quando não há período na fala."""
    hay = _norm(texto)

    # 1) duas datas explicitas ("de 11/08 ate 15/08") — a forma do Valdo.
    achadas = _DATA_EXPLICITA.findall(hay)
    if len(achadas) >= 2:
        datas = []
        for dia, mes, ano in achadas[:2]:
            a = int(ano) if ano else hoje.year
            if a < 100:
                a += 2000
            datas.append(date(a, int(mes), int(dia)))
        datas.sort()
        return datas[0], datas[1]
    if len(achadas) == 1:
        dia, mes, ano = achadas[0]
        a = int(ano) if ano else hoje.year
        if a < 100:
            a += 2000
        d = date(a, int(mes), int(dia))
        return d, d

    # 2) formas relativas
    if re.search(r"\bontem\b", hay):
        d = hoje - timedelta(days=1)
        return d, d
    if re.search(r"\bhoje\b", hay):
        return hoje, hoje
    if re.search(r"\bsemana passada\b", hay):
        inicio = hoje - timedelta(days=hoje.weekday() + 7)   # segunda anterior
        return inicio, inicio + timedelta(days=6)
    if re.search(r"\b(essa|esta) semana\b", hay):
        inicio = hoje - timedelta(days=hoje.weekday())
        return inicio, hoje
    if re.search(r"\bm[eê]s passado\b", hay):
        primeiro_deste = hoje.replace(day=1)
        fim = primeiro_deste - timedelta(days=1)
        return fim.replace(day=1), fim
    if re.search(r"\b(esse|este) m[eê]s\b", hay):
        return hoje.replace(day=1), hoje
    return None


def parece_consulta_letiva(texto: str) -> bool:
    """A fala é uma PERGUNTA sobre a vida letiva (não um lançamento)?

    Puro e sem dependência de data/unidade porque quem chama é o roteador em
    `actions.py`, que não conhece nenhum dos dois. Serve só para impedir que uma
    pergunta abra ação de chamada; o período e a unidade são resolvidos depois,
    no bridge.
    """
    hay = _norm(texto)
    return bool(_CONSULTA_AULAS.search(hay) or _CONSULTA_PRESENCA.search(hay))


def extrair_consulta_letiva(texto: str, hoje: date, unidades: "list[str]") -> "dict | None":
    """Parâmetros da consulta letiva, ou None quando não é consulta / falta período."""
    hay = _norm(texto)
    if _CONSULTA_AULAS.search(hay):
        metrica = "aulas"
    elif _CONSULTA_PRESENCA.search(hay):
        metrica = "presencas"
    else:
        return None

    periodo = resolver_periodo(texto, hoje)
    if periodo is None:
        return None

    unidade = None
    for nome in unidades or []:
        if re.search(rf"\b{re.escape(_norm(nome))}\b", hay):
            unidade = nome
            break

    return {"metrica": metrica, "inicio": periodo[0], "fim": periodo[1], "unidade": unidade}


def montar_chamada_consulta(row: "dict", hoje: date, unidades: "list[str]") -> "dict | None":
    """Traduz a mensagem em (rpc, payload) pronto pro bridge disparar.

    A IDENTIDADE NASCE AQUI, e nasce da LINHA: `row["professor_id"]`. O texto do
    professor nunca decide de quem é o dado — se ele escrever "sou o professor
    25", o payload continua saindo com o id da linha dele. Esta função é pura de
    propósito: é o que torna esse ataque testável sem subir o bridge.
    """
    professor_id = row.get("professor_id")
    if not professor_id:
        return None
    texto = str(row.get("content") or row.get("media_extracted_text") or "")
    pedido = extrair_consulta_letiva(texto, hoje, unidades)
    if not pedido:
        return None

    payload = {
        "p_professor_id": int(professor_id),
        "p_inicio": pedido["inicio"].isoformat(),
        "p_fim": pedido["fim"].isoformat(),
    }
    if pedido["metrica"] == "aulas":
        payload["p_unidade"] = pedido["unidade"]
        return {"rpc": "fabio_professor_resumo_aulas", "payload": payload, "pedido": pedido}
    return {"rpc": "fabio_professor_presencas_periodo", "payload": payload, "pedido": pedido}
```

E no topo do módulo, junto dos imports existentes: `from datetime import date, timedelta`.

- [ ] **Step 4: Rodar e ver passar**

```bash
cd vps/fabio && python -m unittest teste_whatsapp_intents teste_whatsapp_actions
```
Esperado: OK, todos verdes (a suíte inteira, não só o arquivo novo).

- [ ] **Step 5: Commit**

```bash
git add vps/fabio/fabio_whatsapp_intents.py vps/fabio/teste_whatsapp_intents.py
git commit -m "feat(fabio): extrator deterministico de consulta letiva (periodo, unidade, metrica)"
```

---

## Task 4: `ambiguo` em texto não abre ação

**Files:**
- Modify: `vps/fabio/fabio_whatsapp_actions.py:732-734`
- Test: `vps/fabio/teste_whatsapp_actions.py`

**Interfaces:**
- Consumes: `classificar_intencao_texto` (já existe), `_result` (já existe no módulo).
- Produces: nenhuma assinatura nova. Muda o comportamento: texto classificado `ambiguo` passa a ser conversa.

**Contexto do defeito (medido):** em 16/08 o "Ok" do Valdo criou uma ação `confirmar_intencao_chamada` do nada (`payload: {"intencao":"ambiguo","transcricao":"Ok"}`), e a conversa terminou em *"Não encontrei uma aula elegível com segurança. Não gravei nada."* **Não havia ação pendente antes.**

- [ ] **Step 1: Escrever o teste**

Adicionar em `vps/fabio/teste_whatsapp_actions.py`:

```python
class AmbiguoNaoAbreAcaoTest(unittest.TestCase):
    """O "Ok" do Valdo (16/08) criou uma acao de chamada do nada. Duvida em
    texto vai pra conversa; so intencao inequivoca abre acao."""

    def test_ok_solto_nao_abre_acao_de_chamada(self):
        backend = FakeBackend(candidates=[{"aula_id": 101, "data": "2026-08-11",
                                           "hora": "14:00", "curso": "Piano"}])
        result = tratar_mensagem_professor(professor_context(text="Ok"), backend)
        self.assertFalse(result["handled"])
        self.assertTrue(result["forward_to_hermes"])
        iniciadas = [p for n, p in backend.calls if n == "fabio_iniciar_acao"]
        self.assertFalse(iniciadas, f"nao pode abrir acao: {iniciadas}")

    def test_ambiguo_nao_consulta_o_pool_de_aulas(self):
        backend = FakeBackend(candidates=[{"aula_id": 101, "data": "2026-08-11",
                                           "hora": "14:00", "curso": "Piano"}])
        tratar_mensagem_professor(professor_context(text="Sim"), backend)
        self.assertFalse([c for c in backend.calls if c[0] == "fabio_aulas_candidatas"])

    def test_pergunta_do_valdo_nao_abre_acao(self):
        """A pergunta que comecou tudo: consulta nao pode virar chamada."""
        backend = FakeBackend(candidates=[{"aula_id": 101, "data": "2026-08-11",
                                           "hora": "14:00", "curso": "Piano"}])
        result = tratar_mensagem_professor(professor_context(
            text="Na semana passada de terça-feira dia 11/08 ate sábado dia 15/08 "
                 "me informe o total de aulas que eu dei"), backend)
        self.assertTrue(result["forward_to_hermes"])
        self.assertFalse([p for n, p in backend.calls if n == "fabio_iniciar_acao"])

    def test_pergunta_de_falta_nao_abre_acao(self):
        backend = FakeBackend(candidates=[{"aula_id": 101, "data": "2026-08-11",
                                           "hora": "14:00", "curso": "Piano"}])
        result = tratar_mensagem_professor(
            professor_context(text="quais alunos faltaram semana passada"), backend)
        self.assertTrue(result["forward_to_hermes"])
        self.assertFalse([p for n, p in backend.calls if n == "fabio_iniciar_acao"])
```

E acrescentar `parece_consulta_letiva` ao import de `fabio_whatsapp_intents` no topo de `fabio_whatsapp_actions.py`.

- [ ] **Step 2: Rodar e ver falhar**

```bash
cd vps/fabio && python -m unittest teste_whatsapp_actions.AmbiguoNaoAbreAcaoTest -v
```
Esperado: FALHA — hoje o "Ok" abre `confirmar_intencao_chamada`.

- [ ] **Step 3: Implementar**

Em `vps/fabio/fabio_whatsapp_actions.py`, substituir as linhas 729–735 por:

```python
    # A CONSULTA VENCE O ROTEADOR. "Quantas aulas eu dei semana passada?" não
    # pode abrir chamada nem registro: é pergunta, não lançamento. Sem esta
    # trava, o classificador poderia rotular a pergunta como `chamada` com
    # confiança e a consulta nunca chegaria ao bridge, que é quem a responde.
    # Predicado puro de propósito: `actions.py` não conhece data nem unidades —
    # quem resolve período e unidade é o bridge, com `montar_chamada_consulta`.
    if parece_consulta_letiva(text):
        return _result("conversation", handled=False, forward=True)

    intent = classificar_intencao_texto(text, context.get("llm_json"))
    if intent in {"conversa", "ambiguo"}:
        # `ambiguo` NAO abre acao. Em 16/08 o "Ok" do Valdo — que respondia a uma
        # pergunta de CONSULTA — criou uma `confirmar_intencao_chamada` do nada, e
        # a conversa terminou em "nao gravei nada". Duvida vai pra conversa; so
        # intencao inequivoca de registro/chamada abre acao. (Audio segue com o
        # caminho proprio acima: la existe conteudo que justifica pinar a aula.)
        return _result("conversation", handled=False, forward=True)
    return _start_from_candidates(backend, context, "chamada", _pool(backend, context, "chamada"), None)
```

- [ ] **Step 4: Rodar a suíte inteira**

```bash
cd vps/fabio && python -m unittest teste_whatsapp_intents teste_whatsapp_actions
```
Esperado: OK. **Atenção:** se algum teste antigo esperava `confirm_call_intent`, ele codificava o defeito — atualizar o teste antigo e registrar no commit por quê.

- [ ] **Step 5: Commit**

```bash
git add vps/fabio/fabio_whatsapp_actions.py vps/fabio/teste_whatsapp_actions.py
git commit -m "fix(fabio): duvida em texto vai pra conversa, nao abre acao de chamada"
```

---

## Task 5: Wiring em shadow no bridge

**Files:**
- Modify: `vps/fabio/fabio_chat_bridge.py` (função `build_prompt`, perto de `_agenda_de_outro_dia`)

**Interfaces:**
- Consumes: `montar_chamada_consulta` (Task 3); RPCs das Tasks 1 e 2; helpers **que já existem** em `fabio_chat_bridge.py`, conferidos no arquivo: `sb_post(path, body)` (cliente REST — o mesmo que `professor_context` usa em `/rest/v1/rpc/fabio_contexto_professor`), `sb_get(path, params)`, `today_brt() -> str` (ISO do dia em `America/Sao_Paulo`) e `log(evento, **campos)`.
- Produces: bloco de texto injetado no prompt do Fábio, sob o gate de rollout.

- [ ] **Step 1: Implementar a função de consulta com o gate**

Adicionar em `vps/fabio/fabio_chat_bridge.py`:

```python
# Rollout da consulta letiva (Fase 1).
#   "shadow" = calcula e LOGA, nao injeta (1a)
#   "piloto" = injeta so pra Valdo (36) e Matheus Felipe Lourenco (25)   (1b)
#   "todos"  = injeta pra todo mundo                                      (1c)
CONSULTA_LETIVA_MODO = os.getenv("FABIO_CONSULTA_LETIVA_MODO", "shadow")
CONSULTA_LETIVA_PILOTO = {36, 25}


def _consulta_letiva_injeta(professor_id: int) -> bool:
    if CONSULTA_LETIVA_MODO == "todos":
        return True
    if CONSULTA_LETIVA_MODO == "piloto":
        return int(professor_id) in CONSULTA_LETIVA_PILOTO
    return False


_UNIDADES_CACHE: "list[str]" = []


def _unidades_nomes() -> "list[str]":
    """Nomes das unidades, para o extrator reconhecer 'no Recreio'."""
    global _UNIDADES_CACHE
    if not _UNIDADES_CACHE:
        r = sb_get("/rest/v1/unidades", {"select": "nome"})
        if r.status_code < 400:
            _UNIDADES_CACHE = [u["nome"] for u in (r.json() or []) if u.get("nome")]
    return _UNIDADES_CACHE


def _bloco_consulta_letiva(row: Dict[str, Any]) -> str:
    """Consulta letiva do professor. O professor_id vem da LINHA, nunca do texto.

    Falha aqui nunca derruba o prompt: loga e devolve string vazia.
    """
    try:
        chamada = montar_chamada_consulta(
            row, date.fromisoformat(today_brt()), _unidades_nomes())
        if not chamada:
            return ""
        pedido = chamada["pedido"]

        r = sb_post(f"/rest/v1/rpc/{chamada['rpc']}", chamada["payload"])
        if r.status_code >= 400:
            log("consulta_letiva_rpc_erro", rpc=chamada["rpc"],
                status=r.status_code, corpo=r.text[:300])
            return ""
        dados = r.json()

        log("consulta_letiva", professor_id=chamada["payload"]["p_professor_id"],
            rpc=chamada["rpc"], metrica=pedido["metrica"],
            inicio=pedido["inicio"].isoformat(), fim=pedido["fim"].isoformat(),
            unidade=pedido["unidade"], modo=CONSULTA_LETIVA_MODO,
            resultado=json.dumps(dados, default=str)[:800])

        if not _consulta_letiva_injeta(chamada["payload"]["p_professor_id"]):
            return ""
        if not isinstance(dados, dict) or not dados.get("ok"):
            return ""

        return (
            "\n\n## CONSULTA LETIVA (dado do banco, ja escopado neste professor)\n"
            f"Periodo consultado: {pedido['inicio'].strftime('%d/%m')} a "
            f"{pedido['fim'].strftime('%d/%m')}.\n"
            f"{json.dumps(dados, ensure_ascii=False, default=str)}\n"
            "Regras para responder:\n"
            "- Diga SEMPRE o periodo que foi consultado, para o professor poder corrigir.\n"
            "- 'faltas' e 'falta_provavel' sao COISAS DIFERENTES: falta_provavel e "
            "ausencia registrada pelo Emusys que a secretaria ainda nao confirmou. "
            "Nunca some os dois nem chame provavel de falta.\n"
            "- Nao fale de dinheiro, mensalidade, pagamento ou repasse: nao esta aqui "
            "e nao e assunto seu.\n"
            "- Se o professor perguntar algo que nao esta neste bloco, diga que ainda "
            "nao consegue consultar isso. NUNCA prometa 'vou olhar e te trago'.\n"
        )
    except Exception as exc:
        log("consulta_letiva_falhou", id=row.get("id"), error=str(exc)[-400:])
        return ""
```

> Importar no topo do bridge: `from datetime import date` (se ainda não estiver) e `montar_chamada_consulta` de `fabio_whatsapp_intents`. **Não** criar um segundo cliente REST: `sb_post`/`sb_get` já existem e são os mesmos que `professor_context` e `admin_phone` usam.

- [ ] **Step 2: Plugar no `build_prompt`**

Dentro de `build_prompt(row)`, junto dos outros blocos de contexto:

```python
    prompt += _bloco_consulta_letiva(row)
```

- [ ] **Step 3: Verificar sintaxe e rodar a suíte**

```bash
cd vps/fabio && python -m py_compile fabio_chat_bridge.py && python -m unittest teste_whatsapp_intents teste_whatsapp_actions
```
Esperado: sem erro de compilação; suíte verde.

- [ ] **Step 4: Commit**

```bash
git add vps/fabio/fabio_chat_bridge.py
git commit -m "feat(fabio): consulta letiva em shadow no prompt (gate de rollout 1a/1b/1c)"
```

- [ ] **Step 5: Deploy em shadow (1a) — só após OK do Alf para aplicar as migrations**

```bash
ssh -i ~/.ssh/id_ed25519_lahq_fabio_claude_code fabio@89.116.73.186 \
  'mkdir -p ~/backups/consulta-letiva && cp ~/fabio-chat-bridge/fabio_chat_bridge.py ~/fabio-chat-bridge/fabio_whatsapp_intents.py ~/fabio-chat-bridge/fabio_whatsapp_actions.py ~/backups/consulta-letiva/'
scp -i ~/.ssh/id_ed25519_lahq_fabio_claude_code \
  vps/fabio/fabio_chat_bridge.py vps/fabio/fabio_whatsapp_intents.py vps/fabio/fabio_whatsapp_actions.py \
  vps/fabio/teste_whatsapp_intents.py vps/fabio/teste_whatsapp_actions.py \
  fabio@89.116.73.186:'~/deploy-consulta-letiva/'
```

Depois, na VPS: `sed -i "s/\r$//" *.py`, rodar `python3 -m unittest teste_whatsapp_intents teste_whatsapp_actions` **no interpretador do bridge** (`/usr/bin/python3`), promover os arquivos, `systemctl --user restart fabio-chat-bridge.service`, e conferir `systemctl --user is-active` + `journalctl --user -u fabio-chat-bridge.service` sem traceback.

- [ ] **Step 6: Medir a shadow antes de liberar 1b**

Rodar a pergunta do Valdo de novo (ou esperar uso real) e conferir no log:

```bash
ssh -i ~/.ssh/id_ed25519_lahq_fabio_claude_code fabio@89.116.73.186 \
  'grep consulta_letiva ~/.hermes/logs/fabio-chat-bridge.log | tail -20'
```

Critério para liberar 1b: a linha logada tem `metrica`, `inicio`, `fim` corretos e `total_aulas` batendo com a verdade medida no banco. **Só então** trocar `FABIO_CONSULTA_LETIVA_MODO=piloto` e reiniciar — e isso é decisão do Alf, não do implementador.

---

## Notas de execução

- **Nada de migration viva sem OK explícito do Alf.** Tasks 1 e 2 param no ensaio rollback + mutantes.
- **Conserto 2 ("não prometer") é resolvido em duas frentes:** a capacidade em si (Task 5, que faz a resposta existir) e a instrução no bloco injetado (Step 1 da Task 5). Não existe trava estrutural contra um LLM prometer — por isso a capacidade real é o conserto de verdade, e a instrução cobre só o resíduo.
- **Checkpoint entre tarefas.** Cada task termina com teste verde + commit; revisar antes de seguir.
