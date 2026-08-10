# Radar do aluno — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Uma página na coordenação do LA Teacher que responde "quem eu procuro
esta semana, e por quê?" — com Health Score próprio, auditável e com réguas
configuráveis.

**Architecture:** Quatro migrations empilhadas (view de sinais → configuração →
nota → RPC da tela), depois o cliente. Cada camada é testável sozinha. A fonte
de presença é `vw_aluno_presenca_semantica_v1`, que já existe — **não se escreve
view nova de presença**.

**Tech Stack:** Postgres/Supabase (projeto `ouqwbbermlzqqvtqwlul`), React + Vite +
TypeScript + Tailwind, testes SQL via `scripts/rodar-teste-sql.mjs` em
BEGIN/ROLLBACK, mutantes via `scripts/mutantes-NNN.mjs`.

**Spec:** `docs/superpowers/specs/2026-08-10-radar-do-aluno-design.md` — aprovada
pelo Alf em 10/08/2026.

## Global Constraints

Valem para **todas** as tarefas. Copiadas da spec, com os valores exatos.

1. **Grão de aula é `(aluno_id, data_aula, horario_aula)`** — nunca a linha. A
   view semântica tem 1,69 linha por aula (`aula_emusys_id` é id de EVENTO).
2. **Presença é afirmação:** dentro do grupo, `bool_or(considera_presenca)`.
3. **Só entra no denominador o que tem `considera_frequencia_denominador = true`.**
   `aula_justificada`, `falta_provavel` e `indeterminado` ficam fora.
4. **A janela nasce em `2026-08-01`** e cresce até 10 aulas. Nunca busca antes.
5. **Coorte:** só alunos cujo `professor_id` está em
   `professores where ativo and usuario_id is not null`.
6. **Fronteira dura:** pagamento, inadimplência e valor de parcela **nunca**
   aparecem. `alunos.health_score` do LA Report **não** é usado (30% dele é
   pagamento).
7. **Sinal que o professor escreve sobre o aluno** (`feedback`,
   `pratica_em_casa`, `evolucao`, `animo`) **nunca agrega por professor** — nem
   coluna, nem média, nem ranking, nem ordenação.
8. **Sinal sem dado sai da conta e o peso se redistribui** — nunca conta como
   neutro nem como zero.
9. **Todo número aparece com sua base:** `6 de 10`, `apurada em 3 de 4 sinais`.
10. **Guard de toda RPC de tela:** `fn_e_coordenacao_la_teacher()` → senão
    `raise exception 'apenas_admin'`.
11. **Um número só:** resumo, lista e chip de filtro contam a mesma coisa no
    mesmo grão (lição da 080).
12. **Cada faceta ignora o próprio filtro e respeita as outras** (regra da 071).
13. Toda migration tem `.test.sql` + `scripts/mutantes-NNN.mjs`, e **todo
    mutante tem que morrer** antes do commit.

**⚠️ Antes da Task 1:** rodar `ls supabase/migrations/ | tail -3`. Outra sessão
pode ter gravado o 081 sem commitar — o `git log` não vê arquivo não commitado.
Se 081 estiver ocupado, renumerar toda a sequência deste plano (+1 em cada).

---

## File Structure

| Arquivo | Responsabilidade |
|---|---|
| `supabase/migrations/081-os-sinais-do-radar.sql` | `vw_radar_aluno_sinais` — uma linha por aluno da coorte, com os 4 sinais e suas bases |
| `supabase/migrations/082-as-reguas-do-radar.sql` | `radar_config` + `radar_config_historico` + RPCs de leitura/escrita |
| `supabase/migrations/083-a-nota-do-radar.sql` | `fn_radar_nota(jsonb, jsonb)` — pura, recebe sinais e config, devolve nota + decomposição |
| `supabase/migrations/084-a-tela-do-radar.sql` | `app_coordenacao_radar(...)` — guard, filtros facetados, resumo com média e mediana |
| `src/lib/api.ts` | tipos + wrappers `coordenacaoRadar`, `radarConfig`, `salvarRadarConfig` |
| `src/features/coordenacao/components/LinhaRadar.tsx` | uma linha da mesa, com os tooltips |
| `src/features/coordenacao/components/ModalAlunoRadar.tsx` | o modal do aluno |
| `src/features/coordenacao/components/TooltipRadar.tsx` | tooltip acessível, reusado pelos três casos |
| `src/pages/app/CoordenacaoRadar.tsx` | a página (compõe, não estiliza) |
| `src/pages/app/CoordenacaoReguas.tsx` | a aba de configuração |
| `src/pages/app/CoordenacaoFrame.tsx` | troca o item `feedback` por `radar` na sidebar |
| `src/features/feedback/MesaFeedback.tsx` | a linha "Isto não é avaliação sua" |

---

### Task 1: A view dos sinais (migration 081)

**Files:**
- Create: `supabase/migrations/081-os-sinais-do-radar.sql`
- Create: `supabase/migrations/081-os-sinais-do-radar.test.sql`
- Create: `scripts/mutantes-081.mjs`
- Modify: `package.json` (scripts `teste:081` e `mutantes:081`)

**Interfaces:**
- Consumes: `public.vw_aluno_presenca_semantica_v1`, `public.vw_aluno_sucesso_lista`,
  `public.aluno_feedback_professor`, `public.professores`, `public.movimentacoes_admin`
- Produces: `public.vw_radar_aluno_sinais` com as colunas —
  `aluno_id int, aluno_nome text, unidade_id uuid, unidade_codigo text,
  professor_id int, professor_nome text, curso_nome text,
  aulas_medidas int, faltas_janela int, absenteismo_pct numeric,
  faltas_mes int, aulas_mes int,
  feedback text, pratica_em_casa text, evolucao text, animo text,
  observacao text, feedback_competencia date,
  avisou_que_sai boolean, mes_saida date`

- [ ] **Step 1: Escrever o teste que falha**

Criar `supabase/migrations/081-os-sinais-do-radar.test.sql`:

```sql
-- Teste da 081. Roda dentro de BEGIN/ROLLBACK do rodar-teste-sql.mjs.
--
-- A view é a fundação do Radar: se ela contar linha em vez de aula, TODO
-- número acima dela dobra. Os passos abaixo guardam as quatro decisões que
-- custaram medição: grão, denominador honesto, janela virada e coorte.
create temporary table _res(caso text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_pares_crus int;
  v_aulas      int;
  v_fora       int;
  v_antes      int;
  v_coorte     int;
  v_linhas     int;
begin
  -- ── Grão ────────────────────────────────────────────────────────────────
  -- A view semântica tem ~1,69 linha por aula. Se a nossa view herdar isso,
  -- o absenteísmo de todo mundo dobra.
  select count(*) into v_pares_crus
    from public.vw_aluno_presenca_semantica_v1
   where considera_frequencia_denominador and data_aula >= '2026-08-01';
  select count(*) into v_aulas from (
    select aluno_id, data_aula, horario_aula
      from public.vw_aluno_presenca_semantica_v1
     where considera_frequencia_denominador and data_aula >= '2026-08-01'
     group by 1,2,3) x;

  insert into _res values ('a base tem duplicata (senao o teste nao vale)',
    v_pares_crus > v_aulas, format('%s linhas, %s aulas', v_pares_crus, v_aulas));

  insert into _res values ('aulas_medidas conta AULA, nao linha',
    (select coalesce(sum(aulas_medidas),0) from public.vw_radar_aluno_sinais) <= v_aulas,
    format('soma=%s aulas=%s', (select coalesce(sum(aulas_medidas),0) from public.vw_radar_aluno_sinais), v_aulas));

  -- ── Denominador honesto ─────────────────────────────────────────────────
  -- Falta justificada, provavel e indeterminada NAO entram. Quem falta e
  -- repoe nao e quem falta e some.
  select count(*) into v_fora
    from public.vw_aluno_presenca_semantica_v1
   where not considera_frequencia_denominador and data_aula >= '2026-08-01';
  insert into _res values ('existe aula fora do denominador (senao o passo seguinte nao vale)',
    v_fora > 0, format('%s linhas fora', v_fora));

  insert into _res values ('nenhum aluno tem mais aula medida do que aula confirmada',
    not exists (
      select 1 from public.vw_radar_aluno_sinais r
       where r.aulas_medidas > (
         select count(*) from (
           select data_aula, horario_aula
             from public.vw_aluno_presenca_semantica_v1 v
            where v.aluno_id = r.aluno_id and v.considera_frequencia_denominador
              and v.data_aula >= '2026-08-01'
            group by 1,2) y)),
    'ok');

  -- ── A janela virada ─────────────────────────────────────────────────────
  select count(*) into v_antes
    from public.vw_aluno_presenca_semantica_v1
   where data_aula < '2026-08-01' and considera_frequencia_denominador;
  insert into _res values ('existe aula antes de 01/08 (senao o passo seguinte nao vale)',
    v_antes > 0, format('%s linhas antes', v_antes));

  -- Se a janela vazasse pra julho, algum aluno teria mais aula medida do que
  -- existe em agosto. Este passo mede exatamente isso.
  insert into _res values ('a janela nao busca antes de 01/08',
    (select coalesce(max(aulas_medidas),0) from public.vw_radar_aluno_sinais)
      <= (select coalesce(max(n),0) from (
            select count(*) n from public.vw_aluno_presenca_semantica_v1
             where considera_frequencia_denominador and data_aula >= '2026-08-01'
             group by aluno_id) z),
    'ok');

  -- ── Coorte ──────────────────────────────────────────────────────────────
  select count(*) into v_coorte
    from public.professores where coalesce(ativo,true) and usuario_id is not null;
  insert into _res values ('a coorte e menor que a escola (senao o teste nao vale)',
    v_coorte < (select count(*) from public.professores where coalesce(ativo,true)),
    format('%s de %s professores', v_coorte,
           (select count(*) from public.professores where coalesce(ativo,true))));

  insert into _res values ('so entra aluno de professor que ja entrou no app',
    not exists (
      select 1 from public.vw_radar_aluno_sinais r
       where r.professor_id not in (
         select id from public.professores
          where coalesce(ativo,true) and usuario_id is not null)),
    'ok');

  -- ── O absenteismo e coerente com suas proprias colunas ──────────────────
  insert into _res values ('absenteismo bate com faltas/aulas da propria linha',
    not exists (
      select 1 from public.vw_radar_aluno_sinais
       where aulas_medidas > 0
         and absenteismo_pct is distinct from round(100.0*faltas_janela/aulas_medidas, 1)),
    'ok');

  insert into _res values ('sem aula medida, o absenteismo e NULO (nao zero)',
    not exists (select 1 from public.vw_radar_aluno_sinais
                 where aulas_medidas = 0 and absenteismo_pct is not null),
    'ok');

  select count(*) into v_linhas from public.vw_radar_aluno_sinais;
  insert into _res values ('a view devolve alguma coisa', v_linhas > 0, format('%s linhas', v_linhas));

  -- ── Um aluno, uma linha ─────────────────────────────────────────────────
  insert into _res values ('um aluno aparece uma vez so',
    not exists (select 1 from public.vw_radar_aluno_sinais
                 group by aluno_id having count(*) > 1), 'ok');
end $$;

select json_build_object(
         'falhas', (select count(*) from _res where not ok),
         'detalhe', coalesce((select json_agg(json_build_object(
                                'passo', caso, 'esperado', 'ok', 'obtido', detalhe))
                                from _res where not ok), '[]'::json)
       ) as resumo;
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

```bash
npm run teste:081
```

Esperado: erro `relation "public.vw_radar_aluno_sinais" does not exist`.

*(O script `teste:081` ainda não existe neste passo — adicioná-lo ao
`package.json` junto com o Step 3, no formato dos vizinhos:*
`"teste:081": "node scripts/rodar-teste-sql.mjs supabase/migrations/081-os-sinais-do-radar.sql supabase/migrations/081-os-sinais-do-radar.test.sql"`*)*

- [ ] **Step 3: Escrever a migration**

Criar `supabase/migrations/081-os-sinais-do-radar.sql`:

```sql
-- 081 — os sinais do Radar do aluno
--
-- Fundação do Radar: uma linha por aluno da coorte, com os quatro sinais da
-- Fase 1 e a BASE de cada um. Quem lê o número tem que ver de quantas aulas
-- ele saiu.
--
-- A FONTE DE PRESENÇA JÁ EXISTIA. `vw_aluno_presenca_semantica_v1` cruza a
-- presença que nasce do lançamento do professor com a que a secretaria dá no
-- Emusys, e implementa os quatro estados (presente, falta_confirmada,
-- aula_justificada, aula_cancelada) mais os dois "não sei" (falta_provavel,
-- indeterminado). A coluna `considera_frequencia_denominador` já tira da conta
-- o que ninguém confirmou. NÃO se escreve view nova de presença.
--
-- O GRÃO É AULA, NÃO LINHA. A view semântica tem 1,69 linha por aula porque
-- `aula_emusys_id` é id de EVENTO — a mesma aula do mesmo aluno no mesmo
-- horário aparece duas vezes. Isso já está visível na tela do LA Report hoje
-- (o modal lista 03/08 duas vezes). Contar linha dobra toda falta.
--
-- A JANELA NASCE EM 01/08/2026 ("vira a página", decisão do Alf). Julho teve
-- duas semanas de recesso e as três unidades vinham sem compromisso com
-- presença. Aproveitar dado ruim porque é o que tem foi o erro que me fez
-- publicar "126 alunos sumidos" que eram chamada não lançada.
--
-- A COORTE é quem já entrou no app. Os sinais que o professor escreve só
-- existem pra quem está lá, e cobrar/expor quem não tem a tela é o jeito mais
-- rápido de o professor aprender a ignorar o sistema.
create or replace view public.vw_radar_aluno_sinais as
with coorte as (
  select id as professor_id
    from public.professores
   where coalesce(ativo, true) and usuario_id is not null
),
-- Grão honesto: uma linha por AULA. Presença é afirmação — se qualquer linha
-- do grupo diz presente, o aluno veio.
aula as (
  select v.aluno_id,
         v.data_aula,
         v.horario_aula,
         bool_or(v.considera_presenca) as veio
    from public.vw_aluno_presenca_semantica_v1 v
   where v.considera_frequencia_denominador
     and v.data_aula >= date '2026-08-01'
   group by 1, 2, 3
),
-- As 10 últimas aulas medidas de cada aluno.
ordenada as (
  select aluno_id, data_aula, veio,
         row_number() over (partition by aluno_id
                            order by data_aula desc, horario_aula desc nulls last) as rn
    from aula
),
janela as (
  select aluno_id,
         count(*)                          as aulas_medidas,
         count(*) filter (where not veio)  as faltas_janela
    from ordenada
   where rn <= 10
   group by 1
),
-- O outro olhar: o fato do mês corrente.
mes as (
  select aluno_id,
         count(*)                          as aulas_mes,
         count(*) filter (where not veio)  as faltas_mes
    from aula
   where data_aula >= date_trunc('month', current_date)::date
   group by 1
),
-- O semáforo do mês, escrito pelo professor. Uma linha por aluno+professor.
semaforo as (
  select distinct on (f.aluno_id, f.professor_id)
         f.aluno_id, f.professor_id, f.feedback, f.pratica_em_casa,
         f.evolucao, f.animo, nullif(btrim(f.observacao), '') as observacao,
         f.competencia
    from public.aluno_feedback_professor f
   where f.competencia = date_trunc('month', current_date)::date
   order by f.aluno_id, f.professor_id,
            coalesce(f.atualizado_em, f.respondido_em) desc
),
-- Aviso prévio: vive da linha ADM. O join até `alunos` é frágil (só 17 de 33
-- acham par), então ele é SELO, não fonte de dado do aluno.
aviso as (
  select distinct ma.aluno_id, min(ma.mes_saida) as mes_saida
    from public.movimentacoes_admin ma
   where ma.tipo = 'aviso_previo'
     and ma.mes_saida >= date_trunc('month', current_date)::date
     and ma.aluno_id is not null
   group by ma.aluno_id
)
select s.id                                as aluno_id,
       s.nome                              as aluno_nome,
       s.unidade_id,
       s.unidade_codigo,
       s.professor_atual_id                as professor_id,
       s.professor_nome,
       s.curso_nome,
       coalesce(j.aulas_medidas, 0)        as aulas_medidas,
       coalesce(j.faltas_janela, 0)        as faltas_janela,
       -- NULO quando não há base. Zero seria "não faltou", e é mentira
       -- diferente de "não sei".
       case when coalesce(j.aulas_medidas, 0) > 0
            then round(100.0 * j.faltas_janela / j.aulas_medidas, 1)
       end                                 as absenteismo_pct,
       coalesce(m.faltas_mes, 0)           as faltas_mes,
       coalesce(m.aulas_mes, 0)            as aulas_mes,
       sf.feedback,
       sf.pratica_em_casa,
       sf.evolucao,
       sf.animo,
       sf.observacao,
       sf.competencia                      as feedback_competencia,
       (av.aluno_id is not null)           as avisou_que_sai,
       av.mes_saida
  from public.vw_aluno_sucesso_lista s
  join coorte c   on c.professor_id = s.professor_atual_id
  left join janela j  on j.aluno_id = s.id
  left join mes m     on m.aluno_id = s.id
  left join semaforo sf on sf.aluno_id = s.id and sf.professor_id = s.professor_atual_id
  left join aviso av  on av.aluno_id = s.id;

comment on view public.vw_radar_aluno_sinais is
  'Sinais do Radar da coordenação, grão de ALUNO. Presença vem de '
  'vw_aluno_presenca_semantica_v1 no grão de AULA (aluno,dia,hora), janela '
  'desde 01/08/2026, só coorte de professor com login liberado. '
  'absenteismo_pct é NULO sem base — nunca zero.';

revoke all on table public.vw_radar_aluno_sinais from public, anon, authenticated;
grant select on table public.vw_radar_aluno_sinais to service_role;
```

- [ ] **Step 4: Rodar o teste e confirmar que passa**

```bash
npm run teste:081
```

Esperado: `{"falhas": 0, "detalhe": []}`.

- [ ] **Step 5: Escrever os mutantes**

Criar `scripts/mutantes-081.mjs` no molde de `scripts/mutantes-080.mjs` (ler
esse arquivo primeiro para copiar a estrutura de execução), com estes cinco:

| # | Âncora (trecho exato da 081) | Vira | Passo que tem que morrer |
|---|---|---|---|
| V1 | `   group by 1, 2, 3\n)` (no CTE `aula`) | `   group by 1, 2, 3, v.aula_emusys_id\n)` | grão: aulas_medidas dobra |
| V2 | `   where v.considera_frequencia_denominador\n     and v.data_aula >= date '2026-08-01'` | `   where true\n     and v.data_aula >= date '2026-08-01'` | denominador: justificada entra |
| V3 | `     and v.data_aula >= date '2026-08-01'` | `     and v.data_aula >= date '2026-06-01'` | janela vaza pra era contaminada |
| V4 | `  join coorte c   on c.professor_id = s.professor_atual_id` | `  left join coorte c   on c.professor_id = s.professor_atual_id` | coorte cai, escola inteira entra |
| V5 | `       case when coalesce(j.aulas_medidas, 0) > 0\n            then round(100.0 * j.faltas_janela / j.aulas_medidas, 1)\n       end` | `       coalesce(round(100.0 * j.faltas_janela / nullif(j.aulas_medidas,0), 1), 0)` | sem base vira 0% em vez de nulo |

- [ ] **Step 6: Rodar os mutantes e confirmar 5/5 mortos**

```bash
npm run mutantes:081
```

Esperado: `5/5 mutantes mortos`. Se algum sobreviver, **corrigir o teste**, não
o mutante — mutante que sobrevive é passo que não existe.

- [ ] **Step 7: Aplicar em produção e conferir com dado real**

```bash
node scripts/rodar-teste-sql.mjs --aplicar supabase/migrations/081-os-sinais-do-radar.sql
```

Depois, medir (esperado hoje: ~158 alunos, ~1,2 aula medida por aluno):

```sql
select count(*) as alunos, round(avg(aulas_medidas),1) as aulas_por_aluno,
       count(*) filter (where absenteismo_pct is null) as sem_base,
       count(*) filter (where feedback is not null)    as com_semaforo
  from public.vw_radar_aluno_sinais;
```

- [ ] **Step 8: Commit**

```bash
git add supabase/migrations/081-os-sinais-do-radar.sql supabase/migrations/081-os-sinais-do-radar.test.sql scripts/mutantes-081.mjs package.json
git commit -m "feat(radar): a view dos sinais, no grão de aula e com a janela virada"
```

---

### Task 2: As réguas configuráveis (migration 082)

**Files:**
- Create: `supabase/migrations/082-as-reguas-do-radar.sql`
- Create: `supabase/migrations/082-as-reguas-do-radar.test.sql`
- Create: `scripts/mutantes-082.mjs`
- Modify: `package.json`

**Interfaces:**
- Consumes: `public.fn_e_coordenacao_la_teacher()`
- Produces:
  - tabela `public.radar_config(chave text primary key, valor numeric, fabrica numeric, rotulo text, grupo text, ordem int)`
  - tabela `public.radar_config_historico(id uuid, chave text, valor_anterior numeric, valor_novo numeric, mudado_por uuid, mudado_em timestamptz)`
  - `public.app_radar_config() returns jsonb` — leitura, com guard
  - `public.app_radar_config_salvar(p_chave text, p_valor numeric) returns jsonb` — escrita, com guard e histórico

**Chaves e valores de fábrica** (exatos, da spec §6.3):

| chave | fabrica | grupo | rotulo |
|---|---|---|---|
| `peso_absenteismo` | 40 | pesos | Absenteísmo |
| `peso_feedback` | 25 | pesos | Feedback do professor |
| `peso_pratica` | 20 | pesos | Pratica em casa |
| `peso_faltas_mes` | 15 | pesos | Faltas do mês |
| `faixa_critico` | 40 | faixas | Crítico abaixo de |
| `faixa_saudavel` | 70 | faixas | Saudável a partir de |
| `absenteismo_atencao_pct` | 25 | absenteismo | Atenção a partir de |
| `absenteismo_critico_pct` | 50 | absenteismo | Crítico a partir de |
| `minimo_aulas_para_taxa` | 4 | base | Mínimo de aulas pra mostrar taxa |
| `minimo_sinais_para_nota` | 2 | base | Mínimo de sinais pra mostrar nota |

- [ ] **Step 1: Escrever o teste que falha**

Criar `supabase/migrations/082-as-reguas-do-radar.test.sql`:

```sql
-- Teste da 082. As réguas são de gestão, não de engenharia: elas mudam, e o
-- histórico do que mudou é o placar da transição de registro.
create temporary table _res(caso text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_coord uuid;
  v_r     jsonb;
  v_hist  int;
begin
  select u.auth_user_id into v_coord
    from public.la_teacher_coordenacao c
    join public.usuarios u on u.id = c.usuario_id
   where u.auth_user_id is not null and coalesce(u.ativo, true)
   limit 1;

  -- ── As dez chaves existem, com fábrica ──────────────────────────────────
  insert into _res values ('as 10 chaves existem',
    (select count(*) from public.radar_config) = 10,
    format('%s chaves', (select count(*) from public.radar_config)));

  insert into _res values ('toda chave tem valor de fabrica',
    not exists (select 1 from public.radar_config where fabrica is null), 'ok');

  insert into _res values ('o default do absenteismo e 25 (benchmark do Alf)',
    (select fabrica from public.radar_config where chave='absenteismo_atencao_pct') = 25,
    (select fabrica::text from public.radar_config where chave='absenteismo_atencao_pct'));

  -- ── Guard ───────────────────────────────────────────────────────────────
  perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
  begin
    perform public.app_radar_config();
    insert into _res values ('quem nao e coordenacao nao le a config', false, 'passou sem guard');
  exception when others then
    insert into _res values ('quem nao e coordenacao nao le a config',
      sqlerrm like '%apenas_admin%', sqlerrm);
  end;

  perform set_config('request.jwt.claim.sub', v_coord::text, true);

  -- ── Leitura ─────────────────────────────────────────────────────────────
  v_r := public.app_radar_config();
  insert into _res values ('a leitura traz valor E fabrica',
    (v_r #>> '{itens,0,valor}') is not null and (v_r #>> '{itens,0,fabrica}') is not null,
    v_r #>> '{itens,0}');

  -- ── Escrita grava historico ─────────────────────────────────────────────
  select count(*) into v_hist from public.radar_config_historico;
  perform public.app_radar_config_salvar('absenteismo_atencao_pct', 30);

  insert into _res values ('o valor mudou',
    (select valor from public.radar_config where chave='absenteismo_atencao_pct') = 30,
    (select valor::text from public.radar_config where chave='absenteismo_atencao_pct'));

  insert into _res values ('a fabrica NAO mudou (e a referencia do que foi mexido)',
    (select fabrica from public.radar_config where chave='absenteismo_atencao_pct') = 25,
    (select fabrica::text from public.radar_config where chave='absenteismo_atencao_pct'));

  insert into _res values ('a mudanca gravou historico',
    (select count(*) from public.radar_config_historico) = v_hist + 1,
    format('%s -> %s', v_hist, (select count(*) from public.radar_config_historico)));

  insert into _res values ('o historico guarda o valor ANTERIOR',
    (select valor_anterior from public.radar_config_historico
      order by mudado_em desc limit 1) = 25,
    (select valor_anterior::text from public.radar_config_historico
      order by mudado_em desc limit 1));

  -- ── Chave desconhecida nao cria linha nova ──────────────────────────────
  begin
    perform public.app_radar_config_salvar('peso_inventado', 99);
    insert into _res values ('chave desconhecida e recusada', false, 'aceitou');
  exception when others then
    insert into _res values ('chave desconhecida e recusada',
      sqlerrm like '%chave_desconhecida%', sqlerrm);
  end;
end $$;

select json_build_object(
         'falhas', (select count(*) from _res where not ok),
         'detalhe', coalesce((select json_agg(json_build_object(
                                'passo', caso, 'esperado', 'ok', 'obtido', detalhe))
                                from _res where not ok), '[]'::json)
       ) as resumo;
```

- [ ] **Step 2: Rodar e confirmar que falha**

```bash
npm run teste:082
```

Esperado: `relation "public.radar_config" does not exist`.

- [ ] **Step 3: Escrever a migration**

Criar `supabase/migrations/082-as-reguas-do-radar.sql`:

```sql
-- 082 — as réguas do Radar
--
-- Pesos, faixas e linhas de alerta são decisão de GESTÃO, não de engenharia.
-- Decisão do Alf (10/08/2026): configuráveis já na Fase 1, mexidas pela
-- coordenação e por ele.
--
-- A RÉGUA NASCE FROUXA E APERTA COM O TEMPO — intenção dele: *"posso querer
-- descer nesse primeiro momento para 30%, e aumentar aos poucos, de acordo com
-- que a equipe vai amadurecendo"*. Isso inverte o instinto de engenharia
-- (começar apertado e afrouxar) e está certo: alerta que dispara em todo mundo
-- no dia 1 é alerta que a equipe aprende a ignorar, e hábito perdido não volta.
--
-- POR ISSO A COLUNA `fabrica` EXISTE E NUNCA MUDA. Ela é a referência do que
-- foi mexido, visível na tela ao lado do valor atual — sem precisar consultar
-- histórico. E a tela NÃO escreve "recomendado" nem "padrão do sistema" ao
-- lado do número: isso transformaria escolha de gestão em regra técnica, e
-- daqui a três meses ninguém mexe porque "o sistema recomenda".
--
-- O HISTÓRICO É PLACAR, NÃO AUDITORIA. O par (linha do alerta × média da
-- escola) ao longo do tempo é o registro do amadurecimento: a linha apertando
-- enquanto a média cai é a prova de que o lançamento melhorou. É o placar da
-- cobrança da Sol e da ferramenta de presença.
create table if not exists public.radar_config (
  chave    text primary key,
  valor    numeric not null,
  fabrica  numeric not null,
  rotulo   text    not null,
  grupo    text    not null,
  ordem    int     not null
);

create table if not exists public.radar_config_historico (
  id              uuid primary key default gen_random_uuid(),
  chave           text        not null references public.radar_config(chave),
  valor_anterior  numeric     not null,
  valor_novo      numeric     not null,
  mudado_por      uuid,
  mudado_em       timestamptz not null default now()
);

create index if not exists radar_config_historico_chave_idx
  on public.radar_config_historico (chave, mudado_em desc);

insert into public.radar_config (chave, valor, fabrica, rotulo, grupo, ordem) values
  ('peso_absenteismo',         40, 40, 'Absenteísmo',                    'pesos',       1),
  ('peso_feedback',            25, 25, 'Feedback do professor',          'pesos',       2),
  ('peso_pratica',             20, 20, 'Pratica em casa',                'pesos',       3),
  ('peso_faltas_mes',          15, 15, 'Faltas do mês',                  'pesos',       4),
  ('faixa_critico',            40, 40, 'Crítico abaixo de',              'faixas',      5),
  ('faixa_saudavel',           70, 70, 'Saudável a partir de',           'faixas',      6),
  ('absenteismo_atencao_pct',  25, 25, 'Atenção a partir de',            'absenteismo', 7),
  ('absenteismo_critico_pct',  50, 50, 'Crítico a partir de',            'absenteismo', 8),
  ('minimo_aulas_para_taxa',    4,  4, 'Mínimo de aulas pra mostrar taxa','base',       9),
  ('minimo_sinais_para_nota',   2,  2, 'Mínimo de sinais pra mostrar nota','base',     10)
on conflict (chave) do nothing;

alter table public.radar_config           enable row level security;
alter table public.radar_config_historico enable row level security;
-- Sem policy: só as RPCs security definer abaixo alcançam as tabelas.

create or replace function public.app_radar_config()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.fn_e_coordenacao_la_teacher() then
    raise exception 'apenas_admin';
  end if;

  return jsonb_build_object(
    'itens', coalesce((
      select jsonb_agg(jsonb_build_object(
               'chave', chave, 'valor', valor, 'fabrica', fabrica,
               'rotulo', rotulo, 'grupo', grupo, 'mexido', valor <> fabrica)
             order by ordem)
        from public.radar_config), '[]'::jsonb));
end $$;

create or replace function public.app_radar_config_salvar(p_chave text, p_valor numeric)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_anterior numeric;
  v_quem     uuid;
begin
  if not public.fn_e_coordenacao_la_teacher() then
    raise exception 'apenas_admin';
  end if;

  select valor into v_anterior from public.radar_config where chave = p_chave;
  if v_anterior is null then
    -- Chave nova não se cria por aqui: config que aceita chave qualquer vira
    -- lixo silencioso que ninguém lê e ninguém apaga.
    raise exception 'chave_desconhecida';
  end if;

  if v_anterior = p_valor then
    return jsonb_build_object('ok', true, 'mudou', false);
  end if;

  begin
    v_quem := nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
  exception when others then
    v_quem := null;
  end;

  update public.radar_config set valor = p_valor where chave = p_chave;

  insert into public.radar_config_historico (chave, valor_anterior, valor_novo, mudado_por)
  values (p_chave, v_anterior, p_valor, v_quem);

  return jsonb_build_object('ok', true, 'mudou', true,
                            'de', v_anterior, 'para', p_valor);
end $$;

revoke all on function public.app_radar_config()                       from public;
revoke all on function public.app_radar_config_salvar(text, numeric)   from public;
grant execute on function public.app_radar_config()                    to authenticated;
grant execute on function public.app_radar_config_salvar(text, numeric) to authenticated;
```

- [ ] **Step 4: Rodar e confirmar que passa**

```bash
npm run teste:082
```

Esperado: `{"falhas": 0}`.

- [ ] **Step 5: Escrever os mutantes**

`scripts/mutantes-082.mjs`, quatro mutantes:

| # | Âncora | Vira | Mata |
|---|---|---|---|
| V1 | `  if not public.fn_e_coordenacao_la_teacher() then\n    raise exception 'apenas_admin';\n  end if;\n\n  return jsonb_build_object(\n    'itens'` | `  if false then\n    raise exception 'apenas_admin';\n  end if;\n\n  return jsonb_build_object(\n    'itens'` | guard da leitura |
| V2 | `  insert into public.radar_config_historico (chave, valor_anterior, valor_novo, mudado_por)\n  values (p_chave, v_anterior, p_valor, v_quem);` | `  if false then\n  insert into public.radar_config_historico (chave, valor_anterior, valor_novo, mudado_por)\n  values (p_chave, v_anterior, p_valor, v_quem);\n  end if;` | histórico some |
| V3 | `    raise exception 'chave_desconhecida';` | `    insert into public.radar_config(chave,valor,fabrica,rotulo,grupo,ordem) values (p_chave,p_valor,p_valor,p_chave,'outros',99); return jsonb_build_object('ok',true);` | chave qualquer é aceita |
| V4 | `  update public.radar_config set valor = p_valor where chave = p_chave;` | `  update public.radar_config set valor = p_valor, fabrica = p_valor where chave = p_chave;` | a fábrica deixa de ser referência |

- [ ] **Step 6: Rodar os mutantes**

```bash
npm run mutantes:082
```

Esperado: `4/4 mutantes mortos`.

- [ ] **Step 7: Aplicar em produção**

```bash
node scripts/rodar-teste-sql.mjs --aplicar supabase/migrations/082-as-reguas-do-radar.sql
```

- [ ] **Step 8: Commit**

```bash
git add supabase/migrations/082-as-reguas-do-radar.sql supabase/migrations/082-as-reguas-do-radar.test.sql scripts/mutantes-082.mjs package.json
git commit -m "feat(radar): as réguas viram configuração, com fábrica visível e histórico"
```

---

### Task 3: A nota (migration 083)

**Files:**
- Create: `supabase/migrations/083-a-nota-do-radar.sql`
- Create: `supabase/migrations/083-a-nota-do-radar.test.sql`
- Create: `scripts/mutantes-083.mjs`
- Modify: `package.json`

**Interfaces:**
- Consumes: nada do banco — a função é **pura**, recebe tudo por parâmetro.
- Produces: `public.fn_radar_nota(p_sinais jsonb, p_config jsonb) returns jsonb`

  `p_sinais` = `{"absenteismo_pct": 60, "aulas_medidas": 10, "feedback": "vermelho", "pratica_em_casa": "nao", "faltas_mes": 2, "aulas_mes": 4}`
  `p_config` = `{"peso_absenteismo": 40, ..., "minimo_sinais_para_nota": 2, ...}`

  Retorno:
  ```json
  {"nota": 38, "status": "critico", "sinais_apurados": 3, "sinais_totais": 4,
   "suficiente": true,
   "decomposicao": [{"sinal":"absenteismo","valor":"60% (6 de 10)","score":40,
                     "peso":40,"peso_efetivo":53.3,"contribuiu":21.3,"de":53.3}]}
  ```

**Por que função pura:** o teste consegue variar peso e sinal sem tocar em
configuração nem em dado real, e o mesmo cálculo serve à RPC da tela e a
qualquer worker futuro.

- [ ] **Step 1: Escrever o teste que falha**

Criar `supabase/migrations/083-a-nota-do-radar.test.sql`:

```sql
-- Teste da 083. A nota é o coração do Radar e a parte mais fácil de mentir:
-- ela precisa ABRIR (mostrar de onde veio), REDISTRIBUIR peso de sinal ausente
-- e SE CALAR quando não tem base.
create temporary table _res(caso text, ok boolean, detalhe text) on commit drop;

do $$
declare
  cfg   jsonb := jsonb_build_object(
    'peso_absenteismo', 40, 'peso_feedback', 25, 'peso_pratica', 20,
    'peso_faltas_mes', 15, 'faixa_critico', 40, 'faixa_saudavel', 70,
    'minimo_sinais_para_nota', 2);
  v     jsonb;
begin
  -- ── Todos os sinais presentes: os pesos somam 100 e nada se redistribui ──
  v := public.fn_radar_nota(jsonb_build_object(
         'absenteismo_pct', 0, 'aulas_medidas', 10, 'feedback', 'verde',
         'pratica_em_casa', 'sim', 'faltas_mes', 0, 'aulas_mes', 4), cfg);
  insert into _res values ('aluno perfeito tira 100', (v->>'nota')::numeric = 100, v->>'nota');
  insert into _res values ('e o status e saudavel', v->>'status' = 'saudavel', v->>'status');
  insert into _res values ('com 4 sinais, apurados = 4', (v->>'sinais_apurados')::int = 4,
    v->>'sinais_apurados');

  v := public.fn_radar_nota(jsonb_build_object(
         'absenteismo_pct', 100, 'aulas_medidas', 10, 'feedback', 'vermelho',
         'pratica_em_casa', 'nao', 'faltas_mes', 4, 'aulas_mes', 4), cfg);
  insert into _res values ('aluno no pior caso tira 0', (v->>'nota')::numeric = 0, v->>'nota');
  insert into _res values ('e o status e critico', v->>'status' = 'critico', v->>'status');

  -- ── A DECOMPOSICAO ABRE ─────────────────────────────────────────────────
  v := public.fn_radar_nota(jsonb_build_object(
         'absenteismo_pct', 0, 'aulas_medidas', 10, 'feedback', 'verde',
         'pratica_em_casa', 'sim', 'faltas_mes', 0, 'aulas_mes', 4), cfg);
  insert into _res values ('a decomposicao tem uma linha por sinal',
    jsonb_array_length(v->'decomposicao') = 4,
    (jsonb_array_length(v->'decomposicao'))::text);
  insert into _res values ('cada linha diz quanto CONTRIBUIU (nao so o peso)',
    not exists (select 1 from jsonb_array_elements(v->'decomposicao') d
                 where d->>'contribuiu' is null), 'ok');
  insert into _res values ('a soma das contribuicoes e a nota',
    round((select sum((d->>'contribuiu')::numeric)
             from jsonb_array_elements(v->'decomposicao') d)) = (v->>'nota')::numeric,
    v->>'nota');

  -- ── SINAL AUSENTE SAI DA CONTA E O PESO SE REDISTRIBUI ──────────────────
  -- Sem feedback e sem pratica, sobram absenteismo (40) e faltas do mes (15).
  -- Se os dois estao perfeitos, a nota tem que ser 100 — e NAO 55, que seria
  -- o resultado de contar os ausentes como zero.
  v := public.fn_radar_nota(jsonb_build_object(
         'absenteismo_pct', 0, 'aulas_medidas', 10,
         'faltas_mes', 0, 'aulas_mes', 4), cfg);
  insert into _res values ('sinal ausente NAO puxa a nota pra baixo',
    (v->>'nota')::numeric = 100, v->>'nota');
  insert into _res values ('e nao conta como neutro (que daria 77,5)',
    (v->>'nota')::numeric <> 77.5, v->>'nota');
  insert into _res values ('apurados = 2 de 4', (v->>'sinais_apurados')::int = 2,
    v->>'sinais_apurados');
  insert into _res values ('o peso efetivo do absenteismo subiu de 40',
    (select (d->>'peso_efetivo')::numeric from jsonb_array_elements(v->'decomposicao') d
      where d->>'sinal' = 'absenteismo') > 40,
    (select d->>'peso_efetivo' from jsonb_array_elements(v->'decomposicao') d
      where d->>'sinal' = 'absenteismo'));

  -- ── PISO DE COBERTURA: com 1 sinal, a nota SE CALA ──────────────────────
  v := public.fn_radar_nota(jsonb_build_object('faltas_mes', 0, 'aulas_mes', 4), cfg);
  insert into _res values ('com 1 sinal, suficiente = false',
    (v->>'suficiente')::boolean = false, v->>'suficiente');
  insert into _res values ('e a nota vem NULA (nao um numero bonito)',
    v->>'nota' is null, coalesce(v->>'nota','(nulo)'));
  insert into _res values ('mas a decomposicao continua vindo (pra tela explicar)',
    jsonb_array_length(v->'decomposicao') >= 1,
    (jsonb_array_length(v->'decomposicao'))::text);

  -- ── Sem sinal nenhum ────────────────────────────────────────────────────
  v := public.fn_radar_nota('{}'::jsonb, cfg);
  insert into _res values ('sem sinal nenhum, nota nula e apurados 0',
    v->>'nota' is null and (v->>'sinais_apurados')::int = 0, v::text);

  -- ── As faixas vem da config, nao do codigo ──────────────────────────────
  v := public.fn_radar_nota(jsonb_build_object(
         'absenteismo_pct', 0, 'aulas_medidas', 10, 'feedback', 'verde',
         'pratica_em_casa', 'sim', 'faltas_mes', 0, 'aulas_mes', 4),
       cfg || jsonb_build_object('faixa_saudavel', 101));
  insert into _res values ('subindo a faixa_saudavel, 100 deixa de ser saudavel',
    v->>'status' <> 'saudavel', v->>'status');
end $$;

select json_build_object(
         'falhas', (select count(*) from _res where not ok),
         'detalhe', coalesce((select json_agg(json_build_object(
                                'passo', caso, 'esperado', 'ok', 'obtido', detalhe))
                                from _res where not ok), '[]'::json)
       ) as resumo;
```

- [ ] **Step 2: Rodar e confirmar que falha**

```bash
npm run teste:083
```

Esperado: `function public.fn_radar_nota(jsonb, jsonb) does not exist`.

- [ ] **Step 3: Escrever a migration**

Criar `supabase/migrations/083-a-nota-do-radar.sql`:

```sql
-- 083 — a nota do Radar
--
-- Função PURA: recebe os sinais e a config, devolve nota + decomposição. Não
-- lê tabela. Assim o teste varia peso e sinal sem tocar em configuração nem em
-- dado real, e o mesmo cálculo serve à tela e a qualquer worker futuro.
--
-- TRÊS AMARRAS QUE IMPEDEM A NOTA DE VIRAR OPINIÃO COM CARA DE NÚMERO:
--
-- 1. A NOTA SEMPRE ABRE. Devolve `decomposicao` com quanto cada sinal
--    CONTRIBUIU — não só o peso. Peso é a regra; contribuição é o efeito, e é
--    o efeito que explica por que a nota é 38. O LA Report já calcula a
--    contribuição e não a mostra; o tooltip de lá diz "peso 10%", que responde
--    a pergunta errada.
--
-- 2. SINAL SEM DADO SAI DA CONTA E O PESO SE REDISTRIBUI. Nunca conta como
--    neutro nem como zero. O LA Report usa `ELSE 50 -- sem feedback = neutro`:
--    com o semáforo em 0% respondido, 20% da nota de TODO MUNDO vira a mesma
--    constante e a nota mexe menos que a realidade. Contar como zero seria
--    pior — é o mesmo defeito do "não-marcado = falta" que a presença já teve.
--
-- 3. PISO DE COBERTURA. Com menos de `minimo_sinais_para_nota` sinais, a nota
--    vem NULA. "NOTA 38 · apurada em 1 de 4" é perigoso porque quem lê fixa no
--    38 e ignora a legenda. Medido em 10/08: subindo em ~20/08 seria 1 sinal
--    vivo (absenteísmo com 3 aulas, abaixo do piso; semáforo só abre em 25/08);
--    em ~01/09 são 3. A nota acende no começo de setembro, e isso é esperado.
create or replace function public.fn_radar_nota(p_sinais jsonb, p_config jsonb)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_dec        jsonb := '[]'::jsonb;
  v_peso_vivo  numeric := 0;
  v_apurados   int := 0;
  v_bruto      numeric := 0;
  v_nota       numeric;
  v_status     text;
  v_minimo     int := coalesce((p_config->>'minimo_sinais_para_nota')::int, 2);
  r            record;
begin
  -- Cada sinal vira (nome, score 0-100, peso, rótulo do valor). Score nulo =
  -- sinal ausente: entra na decomposição como SEM DADO e fica fora do peso.
  for r in
    select * from (values
      ('absenteismo',
       case when (p_sinais->>'absenteismo_pct') is not null
            then greatest(0, 100 - (p_sinais->>'absenteismo_pct')::numeric) end,
       coalesce((p_config->>'peso_absenteismo')::numeric, 0),
       case when (p_sinais->>'absenteismo_pct') is not null
            then format('%s%% (%s de %s)', p_sinais->>'absenteismo_pct',
                        coalesce((p_sinais->>'aulas_medidas')::int, 0)
                          - round(coalesce((p_sinais->>'aulas_medidas')::numeric,0)
                            * (1 - (p_sinais->>'absenteismo_pct')::numeric/100)),
                        p_sinais->>'aulas_medidas') end),
      ('feedback',
       case p_sinais->>'feedback'
            when 'verde' then 100 when 'amarelo' then 50 when 'vermelho' then 0 end,
       coalesce((p_config->>'peso_feedback')::numeric, 0),
       p_sinais->>'feedback'),
      ('pratica',
       case p_sinais->>'pratica_em_casa'
            when 'sim' then 100 when 'as_vezes' then 50 when 'nao' then 0 end,
       coalesce((p_config->>'peso_pratica')::numeric, 0),
       p_sinais->>'pratica_em_casa'),
      ('faltas_mes',
       case when coalesce((p_sinais->>'aulas_mes')::int, 0) > 0
            then greatest(0, 100 - 100.0 * (p_sinais->>'faltas_mes')::numeric
                                        / (p_sinais->>'aulas_mes')::numeric) end,
       coalesce((p_config->>'peso_faltas_mes')::numeric, 0),
       case when coalesce((p_sinais->>'aulas_mes')::int, 0) > 0
            then format('%s de %s no mês', p_sinais->>'faltas_mes', p_sinais->>'aulas_mes') end)
    ) as t(sinal, score, peso, valor)
  loop
    if r.score is null then
      v_dec := v_dec || jsonb_build_object(
        'sinal', r.sinal, 'valor', null, 'score', null,
        'peso', r.peso, 'peso_efetivo', null, 'contribuiu', null, 'sem_dado', true);
    else
      v_apurados  := v_apurados + 1;
      v_peso_vivo := v_peso_vivo + r.peso;
      v_bruto     := v_bruto + r.score * r.peso;
      v_dec := v_dec || jsonb_build_object(
        'sinal', r.sinal, 'valor', r.valor, 'score', r.score,
        'peso', r.peso, 'sem_dado', false);
    end if;
  end loop;

  -- Redistribuição: o peso efetivo é a fatia do sinal DENTRO do que sobrou.
  if v_peso_vivo > 0 then
    v_nota := round(v_bruto / v_peso_vivo);
    v_dec := (
      select jsonb_agg(
        case when (d->>'sem_dado')::boolean then d
             else d || jsonb_build_object(
               'peso_efetivo', round(100.0 * (d->>'peso')::numeric / v_peso_vivo, 1),
               'contribuiu',   round((d->>'score')::numeric * (d->>'peso')::numeric
                                     / v_peso_vivo, 1),
               'de',           round(100.0 * (d->>'peso')::numeric / v_peso_vivo, 1))
        end order by ord)
        from jsonb_array_elements(v_dec) with ordinality as e(d, ord));
  end if;

  -- O piso: com pouca cobertura a nota se cala, mas a decomposição vai junto
  -- pra tela poder explicar o silêncio.
  if v_apurados < v_minimo then
    v_nota := null;
  end if;

  v_status := case
    when v_nota is null then null
    when v_nota < coalesce((p_config->>'faixa_critico')::numeric, 40)   then 'critico'
    when v_nota >= coalesce((p_config->>'faixa_saudavel')::numeric, 70) then 'saudavel'
    else 'atencao' end;

  return jsonb_build_object(
    'nota', v_nota,
    'status', v_status,
    'sinais_apurados', v_apurados,
    'sinais_totais', 4,
    'suficiente', v_apurados >= v_minimo,
    'decomposicao', v_dec);
end $$;

comment on function public.fn_radar_nota(jsonb, jsonb) is
  'Nota do Radar. PURA. Sinal sem dado sai da conta e o peso se redistribui '
  '(nunca neutro, nunca zero). Abaixo de minimo_sinais_para_nota a nota vem '
  'NULA — mas a decomposicao vem, pra tela explicar.';

revoke all on function public.fn_radar_nota(jsonb, jsonb) from public;
grant execute on function public.fn_radar_nota(jsonb, jsonb) to authenticated;
```

- [ ] **Step 4: Rodar e confirmar que passa**

```bash
npm run teste:083
```

Esperado: `{"falhas": 0}`. Se o passo *"a soma das contribuicoes e a nota"*
falhar por arredondamento, o defeito é do código (a soma tem que fechar) —
corrigir a fórmula, **não** afrouxar a asserção.

- [ ] **Step 5: Escrever os mutantes**

`scripts/mutantes-083.mjs`, cinco mutantes:

| # | Âncora | Vira | Mata |
|---|---|---|---|
| V1 | `  if v_apurados < v_minimo then\n    v_nota := null;\n  end if;` | `  if false then\n    v_nota := null;\n  end if;` | piso de cobertura |
| V2 | `      v_apurados  := v_apurados + 1;\n      v_peso_vivo := v_peso_vivo + r.peso;` | `      v_apurados  := v_apurados + 1;\n      v_peso_vivo := coalesce((p_config->>'peso_absenteismo')::numeric,0) + coalesce((p_config->>'peso_feedback')::numeric,0) + coalesce((p_config->>'peso_pratica')::numeric,0) + coalesce((p_config->>'peso_faltas_mes')::numeric,0);` | redistribuição (nota vira 55 em vez de 100) |
| V3 | `    if r.score is null then` | `    if false then` | sinal ausente vira zero |
| V4 | `    when v_nota < coalesce((p_config->>'faixa_critico')::numeric, 40)   then 'critico'` | `    when v_nota < 40 then 'critico'` | faixa deixa de vir da config |
| V5 | `               'contribuiu',   round((d->>'score')::numeric * (d->>'peso')::numeric\n                                     / v_peso_vivo, 1),` | `               'contribuiu',   null,` | a decomposição para de dizer o efeito |

- [ ] **Step 6: Rodar os mutantes**

```bash
npm run mutantes:083
```

Esperado: `5/5 mutantes mortos`.

- [ ] **Step 7: Aplicar em produção**

```bash
node scripts/rodar-teste-sql.mjs --aplicar supabase/migrations/083-a-nota-do-radar.sql
```

- [ ] **Step 8: Commit**

```bash
git add supabase/migrations/083-a-nota-do-radar.sql supabase/migrations/083-a-nota-do-radar.test.sql scripts/mutantes-083.mjs package.json
git commit -m "feat(radar): a nota abre, redistribui peso de sinal ausente e se cala sem base"
```

---

### Task 4: A RPC da tela (migration 084)

**Files:**
- Create: `supabase/migrations/084-a-tela-do-radar.sql`
- Create: `supabase/migrations/084-a-tela-do-radar.test.sql`
- Create: `scripts/mutantes-084.mjs`
- Modify: `package.json`

**Interfaces:**
- Consumes: `vw_radar_aluno_sinais` (Task 1), `radar_config` (Task 2),
  `fn_radar_nota` (Task 3), `fn_e_coordenacao_la_teacher()`
- Produces: `public.app_coordenacao_radar(p_unidade_id uuid default null,
  p_professor_id int default null, p_status text default null,
  p_limite int default 200) returns jsonb`

  Retorno:
  ```json
  {"config": {...}, "resumo": {"alunos": 158, "criticos": 4, "atencao": 12,
     "sem_nota": 140, "absenteismo_media": 31.3, "absenteismo_mediana": 0.0,
     "aulas_por_aluno": 1.2, "base_desde": "2026-08-01"},
   "medias": {"escola": 31.3, "unidades": [...], "professores": [...]},
   "linhas": [...], "total_lista": 158, "truncado": false,
   "filtros": {"unidades": [...], "professores": [...], "status": [...]}}
  ```

- [ ] **Step 1: Escrever o teste que falha**

Criar `supabase/migrations/084-a-tela-do-radar.test.sql`:

```sql
-- Teste da 084. Aqui moram as duas regras que a casa já pagou pra aprender:
-- UM NÚMERO SÓ (080) e FACETA CEGA AO PRÓPRIO FILTRO (071/079). E a fronteira
-- nova: nenhum agregado de professor feito com o que o professor escreveu.
create temporary table _res(caso text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_coord uuid;
  v_r     jsonb;
  v_uni   uuid;
  v_chip  int;
begin
  select u.auth_user_id into v_coord
    from public.la_teacher_coordenacao c
    join public.usuarios u on u.id = c.usuario_id
   where u.auth_user_id is not null and coalesce(u.ativo, true) limit 1;

  -- ── Guard ───────────────────────────────────────────────────────────────
  perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
  begin
    perform public.app_coordenacao_radar();
    insert into _res values ('professor nao abre o radar', false, 'passou sem guard');
  exception when others then
    insert into _res values ('professor nao abre o radar',
      sqlerrm like '%apenas_admin%', sqlerrm);
  end;

  perform set_config('request.jwt.claim.sub', v_coord::text, true);
  v_r := public.app_coordenacao_radar();

  -- ── UM NÚMERO SÓ ────────────────────────────────────────────────────────
  insert into _res values ('resumo e lista contam a mesma coisa',
    (v_r #>> '{resumo,alunos}')::int = (v_r ->> 'total_lista')::int,
    format('resumo=%s lista=%s', v_r #>> '{resumo,alunos}', v_r ->> 'total_lista'));

  insert into _res values ('a soma dos chips de unidade e o total',
    (select coalesce(sum((e->>'alunos')::int),0)
       from jsonb_array_elements(v_r #> '{filtros,unidades}') e)
      = (v_r ->> 'total_lista')::int,
    format('chips=%s lista=%s',
      (select coalesce(sum((e->>'alunos')::int),0)
         from jsonb_array_elements(v_r #> '{filtros,unidades}') e),
      v_r ->> 'total_lista'));

  -- ── O chip promete o que o clique entrega ───────────────────────────────
  select (e ->> 'unidade_id')::uuid, (e ->> 'alunos')::int into v_uni, v_chip
    from jsonb_array_elements(v_r #> '{filtros,unidades}') e
   order by (e ->> 'alunos')::int desc limit 1;

  if v_uni is not null then
    insert into _res values ('o chip da unidade bate com a lista que ela abre',
      (public.app_coordenacao_radar(v_uni) ->> 'total_lista')::int = v_chip,
      format('chip=%s lista=%s', v_chip,
             public.app_coordenacao_radar(v_uni) ->> 'total_lista'));

    -- ── FACETA CEGA AO PRÓPRIO FILTRO ─────────────────────────────────────
    insert into _res values ('com unidade escolhida, a lista de unidades NAO encolhe',
      jsonb_array_length(public.app_coordenacao_radar(v_uni) #> '{filtros,unidades}')
        = jsonb_array_length(v_r #> '{filtros,unidades}'),
      format('antes=%s depois=%s',
        jsonb_array_length(v_r #> '{filtros,unidades}'),
        jsonb_array_length(public.app_coordenacao_radar(v_uni) #> '{filtros,unidades}')));

    insert into _res values ('mas a lista de professores RESPEITA a unidade',
      jsonb_array_length(public.app_coordenacao_radar(v_uni) #> '{filtros,professores}')
        <= jsonb_array_length(v_r #> '{filtros,professores}'), 'ok');
  end if;

  -- ── FRONTEIRA: nada do que o professor escreveu vira numero dele ────────
  insert into _res values ('as medias por professor nao carregam semaforo',
    not exists (
      select 1 from jsonb_array_elements(v_r #> '{medias,professores}') p
       where p ? 'feedback' or p ? 'vermelhos' or p ? 'pratica'),
    coalesce((v_r #>> '{medias,professores,0}'), '(vazio)'));

  -- ── FRONTEIRA: pagamento nunca aparece ──────────────────────────────────
  insert into _res values ('a resposta nao menciona pagamento',
    v_r::text not ilike '%inadimplen%' and v_r::text not ilike '%parcela%'
      and v_r::text not ilike '%health_score%', 'ok');

  -- ── A base e declarada ──────────────────────────────────────────────────
  insert into _res values ('o resumo declara desde quando mede',
    (v_r #>> '{resumo,base_desde}') = '2026-08-01', v_r #>> '{resumo,base_desde}');
  insert into _res values ('e a media E a mediana vem as duas',
    (v_r #> '{resumo,absenteismo_media}') is not null
      and (v_r #> '{resumo,absenteismo_mediana}') is not null,
    v_r #>> '{resumo}');

  -- ── A nota respeita o piso ──────────────────────────────────────────────
  insert into _res values ('linha com poucos sinais vem sem nota',
    not exists (
      select 1 from jsonb_array_elements(v_r -> 'linhas') l
       where (l #>> '{nota,suficiente}')::boolean = false
         and (l #> '{nota,nota}') is not null and (l #>> '{nota,nota}') <> 'null'),
    'ok');

  -- ── Status invalido e recusado ──────────────────────────────────────────
  begin
    perform public.app_coordenacao_radar(null, null, 'roxo');
    insert into _res values ('status invalido e recusado', false, 'aceitou');
  exception when others then
    insert into _res values ('status invalido e recusado',
      sqlerrm like '%status_invalido%', sqlerrm);
  end;
end $$;

select json_build_object(
         'falhas', (select count(*) from _res where not ok),
         'detalhe', coalesce((select json_agg(json_build_object(
                                'passo', caso, 'esperado', 'ok', 'obtido', detalhe))
                                from _res where not ok), '[]'::json)
       ) as resumo;
```

- [ ] **Step 2: Rodar e confirmar que falha**

```bash
npm run teste:084
```

- [ ] **Step 3: Escrever a migration**

Criar `supabase/migrations/084-a-tela-do-radar.sql`:

```sql
-- 084 — a RPC da tela do Radar
--
-- Junta os três: sinais (081) + réguas (082) + nota (083). Molde da 077/079.
--
-- UM NÚMERO SÓ (lição da 080): resumo, `total_lista` e chips contam a mesma
-- coisa, no mesmo grão. Na tela do semáforo isso apareceu como 1.155 no topo e
-- 1.161 na lista, e a causa era grão diferente entre as duas contas.
--
-- CADA FACETA IGNORA O PRÓPRIO FILTRO E RESPEITA AS OUTRAS (regra da 071).
-- Sem isso, escolher uma unidade encolhe a lista de unidades e não há como
-- voltar pra "todas" sem F5.
--
-- FRONTEIRA (§2.1 da spec): as médias por professor carregam SÓ absenteísmo.
-- Semáforo, prática, evolução e ânimo são opinião do professor sobre o aluno —
-- agregá-los por professor dá a ele incentivo pra responder verde, e aí a
-- fonte apodrece em silêncio. Cobra-se que ele responda; nunca se avalia o que
-- ele respondeu.
create or replace function public.app_coordenacao_radar(
  p_unidade_id   uuid    default null,
  p_professor_id integer default null,
  p_status       text    default null,
  p_limite       integer default 200)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cfg    jsonb;
  v_status text := nullif(btrim(coalesce(p_status, '')), '');
  v_r      jsonb;
begin
  if not public.fn_e_coordenacao_la_teacher() then
    raise exception 'apenas_admin';
  end if;

  if v_status is not null and v_status not in ('critico','atencao','saudavel','sem_nota') then
    raise exception 'status_invalido';
  end if;

  select jsonb_object_agg(chave, valor) into v_cfg from public.radar_config;

  with base as (
    select s.*, public.fn_radar_nota(
             jsonb_build_object(
               'absenteismo_pct', s.absenteismo_pct,
               'aulas_medidas',   s.aulas_medidas,
               'feedback',        s.feedback,
               'pratica_em_casa', s.pratica_em_casa,
               'faltas_mes',      s.faltas_mes,
               'aulas_mes',       s.aulas_mes), v_cfg) as nota
      from public.vw_radar_aluno_sinais s
  ),
  com_status as (
    select b.*, coalesce(b.nota ->> 'status', 'sem_nota') as status_calc
      from base b
  ),
  -- Cada faceta é cega ao próprio filtro (071).
  fac_uni  as (select * from com_status
                where (p_professor_id is null or professor_id = p_professor_id)
                  and (v_status is null or status_calc = v_status)),
  fac_prof as (select * from com_status
                where (p_unidade_id is null or unidade_id = p_unidade_id)
                  and (v_status is null or status_calc = v_status)),
  fac_st   as (select * from com_status
                where (p_unidade_id is null or unidade_id = p_unidade_id)
                  and (p_professor_id is null or professor_id = p_professor_id)),
  linha as (select * from com_status
             where (p_unidade_id is null or unidade_id = p_unidade_id)
               and (p_professor_id is null or professor_id = p_professor_id)
               and (v_status is null or status_calc = v_status))
  select jsonb_build_object(
    'config', v_cfg,
    'resumo', (select jsonb_build_object(
        'alunos',              count(*),
        'criticos',            count(*) filter (where status_calc = 'critico'),
        'atencao',             count(*) filter (where status_calc = 'atencao'),
        'saudaveis',           count(*) filter (where status_calc = 'saudavel'),
        'sem_nota',            count(*) filter (where status_calc = 'sem_nota'),
        'avisaram_que_saem',   count(*) filter (where avisou_que_sai),
        'absenteismo_media',   round(avg(absenteismo_pct), 1),
        'absenteismo_mediana', round(percentile_cont(0.5)
                                 within group (order by absenteismo_pct)::numeric, 1),
        'aulas_por_aluno',     round(avg(aulas_medidas), 1),
        'com_base',            count(*) filter (where absenteismo_pct is not null),
        'base_desde',          '2026-08-01') from linha),
    'medias', jsonb_build_object(
        'escola',   (select round(avg(absenteismo_pct),1) from com_status),
        'unidades', coalesce((select jsonb_agg(jsonb_build_object(
                       'unidade_id', unidade_id, 'unidade', unidade_codigo,
                       'absenteismo_media', round(avg(absenteismo_pct),1)) order by unidade_codigo)
                     from com_status where unidade_codigo is not null
                     group by unidade_id, unidade_codigo), '[]'::jsonb),
        -- SÓ absenteísmo. Ver a fronteira no cabeçalho.
        'professores', coalesce((select jsonb_agg(jsonb_build_object(
                       'professor_id', professor_id, 'professor', professor_nome,
                       'absenteismo_media', round(avg(absenteismo_pct),1)) order by professor_nome)
                     from com_status where professor_id is not null
                     group by professor_id, professor_nome), '[]'::jsonb)),
    'linhas', coalesce((select jsonb_agg(jsonb_build_object(
        'aluno_id', aluno_id, 'aluno', aluno_nome,
        'curso', curso_nome, 'unidade', unidade_codigo,
        'professor_id', professor_id, 'professor', professor_nome,
        'nota', nota, 'status', status_calc,
        'absenteismo_pct', absenteismo_pct, 'aulas_medidas', aulas_medidas,
        'faltas_janela', faltas_janela,
        'faltas_mes', faltas_mes, 'aulas_mes', aulas_mes,
        'feedback', feedback, 'pratica_em_casa', pratica_em_casa,
        'evolucao', evolucao, 'animo', animo, 'observacao', observacao,
        'avisou_que_sai', avisou_que_sai, 'mes_saida', mes_saida)
        order by (nota ->> 'nota') is null,        -- quem tem nota primeiro
                 (nota ->> 'nota')::numeric asc,   -- pior nota no topo
                 aluno_nome)
      from (select * from linha
             order by (nota ->> 'nota') is null, (nota ->> 'nota')::numeric asc, aluno_nome
             limit p_limite) x), '[]'::jsonb),
    'total_lista', (select count(*) from linha),
    'truncado',    (select count(*) from linha) > p_limite,
    'filtros', jsonb_build_object(
      'unidades', coalesce((select jsonb_agg(jsonb_build_object(
            'unidade_id', unidade_id, 'unidade', unidade_codigo, 'alunos', n) order by unidade_codigo)
          from (select unidade_id, unidade_codigo, count(*) n from fac_uni
                 where unidade_codigo is not null group by 1,2) u), '[]'::jsonb),
      'professores', coalesce((select jsonb_agg(jsonb_build_object(
            'professor_id', professor_id, 'professor', professor_nome, 'alunos', n) order by professor_nome)
          from (select professor_id, professor_nome, count(*) n from fac_prof
                 where professor_id is not null group by 1,2) p), '[]'::jsonb),
      'status', coalesce((select jsonb_agg(jsonb_build_object(
            'status', status_calc, 'alunos', n) order by status_calc)
          from (select status_calc, count(*) n from fac_st group by 1) s), '[]'::jsonb))
  ) into v_r;

  return v_r;
end $$;

revoke all on function public.app_coordenacao_radar(uuid, integer, text, integer) from public;
grant execute on function public.app_coordenacao_radar(uuid, integer, text, integer) to authenticated;
```

- [ ] **Step 4: Rodar e confirmar que passa**

```bash
npm run teste:084
```

- [ ] **Step 5: Escrever os mutantes**

`scripts/mutantes-084.mjs`, seis mutantes:

| # | Âncora | Vira | Mata |
|---|---|---|---|
| V1 | `  if not public.fn_e_coordenacao_la_teacher() then\n    raise exception 'apenas_admin';` | `  if false then\n    raise exception 'apenas_admin';` | guard |
| V2 | `  fac_uni  as (select * from com_status\n                where (p_professor_id is null or professor_id = p_professor_id)` | `  fac_uni  as (select * from com_status\n                where (p_unidade_id is null or unidade_id = p_unidade_id) and (p_professor_id is null or professor_id = p_professor_id)` | faceta se filtra (beco sem volta) |
| V3 | `    'total_lista', (select count(*) from linha),` | `    'total_lista', (select count(*) from com_status),` | resumo e lista discordam |
| V4 | `                       'absenteismo_media', round(avg(absenteismo_pct),1)) order by professor_nome)\n                     from com_status where professor_id is not null` | `                       'absenteismo_media', round(avg(absenteismo_pct),1), 'vermelhos', count(*) filter (where feedback='vermelho')) order by professor_nome)\n                     from com_status where professor_id is not null` | **agregado de professor com semáforo** |
| V5 | `  if v_status is not null and v_status not in ('critico','atencao','saudavel','sem_nota') then\n    raise exception 'status_invalido';\n  end if;` | `  if false then\n    raise exception 'status_invalido';\n  end if;` | status inventado passa |
| V6 | `        'absenteismo_mediana', round(percentile_cont(0.5)\n                                 within group (order by absenteismo_pct)::numeric, 1),` | `        'absenteismo_mediana', null,` | mediana some do resumo |

- [ ] **Step 6: Rodar os mutantes**

```bash
npm run mutantes:084
```

Esperado: `6/6 mutantes mortos`.

- [ ] **Step 7: Aplicar em produção e medir**

```bash
node scripts/rodar-teste-sql.mjs --aplicar supabase/migrations/084-a-tela-do-radar.sql
```

Conferir com dado real (esperado hoje: ~158 alunos, quase todos `sem_nota`
porque o semáforo ainda não foi respondido — isso é o piso funcionando):

```sql
select jsonb_pretty(public.app_coordenacao_radar() -> 'resumo');
```

- [ ] **Step 8: Commit**

```bash
git add supabase/migrations/084-a-tela-do-radar.sql supabase/migrations/084-a-tela-do-radar.test.sql scripts/mutantes-084.mjs package.json
git commit -m "feat(radar): a RPC da tela, com um número só e faceta cega ao próprio filtro"
```

---

### Task 5: Os tipos e wrappers no cliente

**Files:**
- Modify: `src/lib/api.ts`

**Interfaces:**
- Consumes: `app_coordenacao_radar`, `app_radar_config`, `app_radar_config_salvar`
- Produces: `RadarLinha`, `RadarResposta`, `RadarConfig`, `FiltroRadar`,
  `SEM_FILTRO_RADAR`, `coordenacaoRadar()`, `radarConfig()`, `salvarRadarConfig()`

- [ ] **Step 1: Ler o padrão existente**

Abrir `src/lib/api.ts` e localizar `coordenacaoFeedbackMes` — os tipos e o
wrapper do Radar seguem **exatamente** esse molde (`rpcSolta`, `if (error)
throw error`, `return data as unknown as T`).

- [ ] **Step 2: Adicionar os tipos e wrappers**

Acrescentar em `src/lib/api.ts`, logo depois do bloco de
`coordenacaoFeedbackMes`:

```ts
/** Uma linha da mesa do Radar. `nota.nota` é null quando falta cobertura. */
export type RadarNota = {
  nota: number | null
  status: 'critico' | 'atencao' | 'saudavel' | null
  sinais_apurados: number
  sinais_totais: number
  suficiente: boolean
  decomposicao: Array<{
    sinal: string
    valor: string | null
    score: number | null
    peso: number
    peso_efetivo: number | null
    contribuiu: number | null
    de: number | null
    sem_dado: boolean
  }>
}

export type RadarLinha = {
  aluno_id: number
  aluno: string
  curso: string | null
  unidade: string | null
  professor_id: number | null
  professor: string | null
  nota: RadarNota
  status: 'critico' | 'atencao' | 'saudavel' | 'sem_nota'
  /** NULL quando não há aula medida — nunca zero. Ver migration 081. */
  absenteismo_pct: number | null
  aulas_medidas: number
  faltas_janela: number
  faltas_mes: number
  aulas_mes: number
  feedback: string | null
  pratica_em_casa: string | null
  evolucao: string | null
  animo: string | null
  observacao: string | null
  avisou_que_sai: boolean
  mes_saida: string | null
}

export type RadarResposta = {
  config: Record<string, number>
  resumo: {
    alunos: number
    criticos: number
    atencao: number
    saudaveis: number
    sem_nota: number
    avisaram_que_saem: number
    absenteismo_media: number | null
    absenteismo_mediana: number | null
    aulas_por_aluno: number | null
    com_base: number
    base_desde: string
  }
  medias: {
    escola: number | null
    unidades: Array<{ unidade_id: string; unidade: string; absenteismo_media: number | null }>
    professores: Array<{ professor_id: number; professor: string; absenteismo_media: number | null }>
  }
  linhas: RadarLinha[]
  total_lista: number
  truncado: boolean
  filtros: {
    unidades: Array<{ unidade_id: string; unidade: string; alunos: number }>
    professores: Array<{ professor_id: number; professor: string; alunos: number }>
    status: Array<{ status: string; alunos: number }>
  }
}

export type FiltroRadar = {
  unidadeId: string | null
  professorId: number | null
  status: 'critico' | 'atencao' | 'saudavel' | 'sem_nota' | null
}

export const SEM_FILTRO_RADAR: FiltroRadar = {
  unidadeId: null,
  professorId: null,
  status: null,
}

export async function coordenacaoRadar(
  filtro: FiltroRadar = SEM_FILTRO_RADAR,
): Promise<RadarResposta> {
  const { data, error } = await rpcSolta('app_coordenacao_radar', {
    p_unidade_id: filtro.unidadeId,
    p_professor_id: filtro.professorId,
    p_status: filtro.status,
    p_limite: 200,
  })
  if (error) throw error
  return data as unknown as RadarResposta
}

export type RadarConfigItem = {
  chave: string
  valor: number
  fabrica: number
  rotulo: string
  grupo: 'pesos' | 'faixas' | 'absenteismo' | 'base'
  mexido: boolean
}

export async function radarConfig(): Promise<{ itens: RadarConfigItem[] }> {
  const { data, error } = await rpcSolta('app_radar_config', {})
  if (error) throw error
  return data as unknown as { itens: RadarConfigItem[] }
}

export async function salvarRadarConfig(chave: string, valor: number): Promise<void> {
  const { error } = await rpcSolta('app_radar_config_salvar', {
    p_chave: chave,
    p_valor: valor,
  })
  if (error) throw error
}
```

- [ ] **Step 3: Conferir que compila**

```bash
npm run build
```

Esperado: build verde. Se `rpcSolta` reclamar do nome da RPC, é porque
`src/lib/db.ts` está desatualizado — usar o mesmo cast que
`coordenacaoFeedbackMes` já usa e anotar como follow-up.

- [ ] **Step 4: Commit**

```bash
git add src/lib/api.ts
git commit -m "feat(radar): tipos e wrappers do Radar no cliente"
```

---

### Task 6: A mesa do Radar e a troca na sidebar

**Files:**
- Create: `src/features/coordenacao/components/TooltipRadar.tsx`
- Create: `src/features/coordenacao/components/LinhaRadar.tsx`
- Create: `src/pages/app/CoordenacaoRadar.tsx`
- Modify: `src/pages/app/CoordenacaoFrame.tsx`
- Modify: `src/routes.tsx`
- Modify: `src/pages/app/CoordenacaoFeedback.tsx`

**Interfaces:**
- Consumes: `coordenacaoRadar`, `RadarResposta`, `RadarLinha` (Task 5)
- Produces: rota `/app/coordenacao/radar`

- [ ] **Step 1: Ler os padrões da casa**

Abrir e ler, nesta ordem — o Radar reusa, não reinventa:
`src/pages/app/CoordenacaoFeedback.tsx` (composição de página),
`src/features/coordenacao/components/LinhaSemaforo.tsx` (cartão de aluno),
`src/features/coordenacao/components/FiltrosSemaforo.tsx` (selects facetados),
`src/features/coordenacao/components/PainelNumero.tsx` (KPI).

**Regra:** nenhuma cor, raio ou sombra novos. O que faltar se extrai do app do
professor. Não nasce Design System paralelo.

- [ ] **Step 2: Criar o tooltip**

`src/features/coordenacao/components/TooltipRadar.tsx`:

```tsx
import { useId, useState, type ReactNode } from 'react'

/**
 * Tooltip do Radar — obrigatório, não enfeite (pedido do Alf, 10/08).
 *
 * Todo número do Radar aparece com a base dele. O "21% de presença" da tela do
 * LA Report não diz de quantas aulas saiu, e é exatamente por isso que ninguém
 * percebeu que ele vinha de linhas dobradas.
 *
 * Abre no hover E no foco: quem navega por teclado tem que alcançar a mesma
 * informação, senão o dado só existe pra quem usa mouse.
 */
export function TooltipRadar({
  children,
  conteudo,
}: {
  children: ReactNode
  conteudo: ReactNode
}) {
  const [aberto, setAberto] = useState(false)
  const id = useId()

  return (
    <span className="relative inline-flex">
      <span
        tabIndex={0}
        aria-describedby={aberto ? id : undefined}
        onMouseEnter={() => setAberto(true)}
        onMouseLeave={() => setAberto(false)}
        onFocus={() => setAberto(true)}
        onBlur={() => setAberto(false)}
        className="cursor-help underline decoration-dotted underline-offset-4"
      >
        {children}
      </span>
      {aberto ? (
        <span
          id={id}
          role="tooltip"
          className="absolute left-0 top-full z-20 mt-1 w-max max-w-xs rounded-lg border border-border bg-surface p-3 text-xs leading-relaxed text-text shadow-lg"
        >
          {conteudo}
        </span>
      ) : null}
    </span>
  )
}
```

- [ ] **Step 3: Criar a linha da mesa**

`src/features/coordenacao/components/LinhaRadar.tsx` — uma linha com as sete
colunas da spec (`Aluno · Health Score · Faltas · Absenteísmo · Prática ·
Feedback · Status`), cada número com seu tooltip.

Regras que o componente tem que cumprir, e que o revisor vai conferir:

1. `nota.nota === null` → mostra `—` e o tooltip diz
   `apurada em {sinais_apurados} de {sinais_totais} · insuficiente`. **Nunca**
   um número.
2. `absenteismo_pct === null` → mostra `enchendo: {aulas_medidas} de {minimo}`.
   **Nunca** `0%`.
3. O tooltip da nota lista a decomposição com **`contribuiu X de Y`** — nunca
   só o peso.
4. O tooltip do absenteísmo declara a janela, a base e as médias de professor e
   unidade ao lado.
5. `avisou_que_sai` vira selo na linha; **não** entra na nota.

Esqueleto do tooltip da nota (o resto segue o padrão visual do `LinhaSemaforo`):

```tsx
<TooltipRadar
  conteudo={
    <>
      <strong>
        {linha.nota.nota ?? '—'} · {linha.status}
      </strong>
      <ul className="mt-2 space-y-1">
        {linha.nota.decomposicao.map((d) => (
          <li key={d.sinal} className="flex justify-between gap-3">
            <span className={d.sem_dado ? 'text-text-muted' : undefined}>
              {d.sinal} {d.valor ? `· ${d.valor}` : ''}
            </span>
            <span>
              {d.sem_dado
                ? 'sem dado (fora da conta)'
                : `contribuiu ${d.contribuiu} de ${d.de}`}
            </span>
          </li>
        ))}
      </ul>
      <p className="mt-2 text-text-muted">
        apurada em {linha.nota.sinais_apurados} de {linha.nota.sinais_totais} sinais
      </p>
    </>
  }
>
  {linha.nota.nota ?? '—'}
</TooltipRadar>
```

- [ ] **Step 4: Criar a página**

`src/pages/app/CoordenacaoRadar.tsx`, no molde de `CoordenacaoFeedback.tsx`:
compõe casca + KPIs + filtros + lista. **Não estiliza** (regra do
`docs/frontend-tokens.md`).

KPIs do topo, nesta ordem: `Crítico` · `Atenção` · `Avisaram que saem` ·
`Absenteísmo médio`. O quarto mostra **média e mediana juntas** e o cabeçalho
declara a base:

```tsx
<p className="mb-4 text-[11.5px] text-text-muted">
  Absenteísmo desde {dados.resumo.base_desde} · {dados.resumo.aulas_por_aluno} aula
  por aluno em média
  {dados.resumo.aulas_por_aluno !== null && dados.resumo.aulas_por_aluno < 4
    ? ' — ainda enchendo'
    : ''}
</p>
```

Estado vazio em três casos, como na tela de Feedback: filtro não achou ninguém
/ ninguém na coorte ainda / ninguém precisa de atenção.

- [ ] **Step 5: Trocar o item da sidebar**

Em `src/pages/app/CoordenacaoFrame.tsx`, no array `ITENS`, **substituir** o
item `feedback` por:

```tsx
  {
    id: 'radar',
    para: '/app/coordenacao/radar',
    rotulo: 'Radar',
    icone: 'fa-solid fa-radar',
  },
```

E no mapa `ROTA`, trocar `feedback: '/app/coordenacao/feedback'` por
`radar: '/app/coordenacao/radar'`.

Em `abaAtiva`, a tela de Feedback passa a **acender o Radar** — ela é filha
dele:

```tsx
  const abaAtiva = pathname.startsWith('/app/coordenacao/perfil')
    ? 'perfil'
    : // A tela de Feedback deixou de ser item de menu (decisão do Alf, 10/08):
      // ela é o "ver o mês inteiro" do cartão Coração vermelho do Radar. Item
      // aceso tem que dizer a verdade sobre onde você está.
      pathname.startsWith('/app/coordenacao/radar') ||
        pathname.startsWith('/app/coordenacao/feedback')
      ? 'radar'
      : ...
```

- [ ] **Step 6: Registrar a rota**

Em `src/routes.tsx`, dentro de `RequireAdmin`, ao lado da rota de feedback:

```tsx
import CoordenacaoRadarPage from './pages/app/CoordenacaoRadar'
// ...
{ path: '/app/coordenacao/radar', element: <CoordenacaoRadarPage /> },
```

- [ ] **Step 7: Dar saída à tela de Feedback**

`CoordenacaoFeedback.tsx` deixou de ser destino de menu, então precisa de
volta. Passar `aoVoltar` ao `CoordenacaoFrame`:

```tsx
  const nav = useNavigate()
  // ...
  <CoordenacaoFrame
    titulo="Feedback do mês"
    icone="fa-solid fa-heart-pulse"
    aoVoltar={() => nav('/app/coordenacao/radar')}
  >
```

- [ ] **Step 8: Build e verificação ao vivo**

```bash
npm run build
```

Depois, com o preview aberto e sessão de coordenação, conferir na tela:
1. a sidebar mostra `Painel · Radar · Equipe` e **só um** item aceso;
2. estando em `/app/coordenacao/feedback`, quem acende é o **Radar**;
3. o KPI de absenteísmo mostra média **e** mediana e declara a base;
4. uma linha sem nota mostra `—`, não um número.

- [ ] **Step 9: Commit**

```bash
git add src/features/coordenacao/components/TooltipRadar.tsx src/features/coordenacao/components/LinhaRadar.tsx src/pages/app/CoordenacaoRadar.tsx src/pages/app/CoordenacaoFrame.tsx src/pages/app/CoordenacaoFeedback.tsx src/routes.tsx
git commit -m "feat(radar): a mesa do Radar e a porta do aluno na sidebar"
```

---

### Task 7: O modal do aluno

**Files:**
- Create: `src/features/coordenacao/components/ModalAlunoRadar.tsx`
- Modify: `src/pages/app/CoordenacaoRadar.tsx`

**Interfaces:**
- Consumes: `RadarLinha` (Task 5), `TooltipRadar` (Task 6)
- Produces: `<ModalAlunoRadar linha={...} aoFechar={...} medias={...} />`

- [ ] **Step 1: Criar o modal**

Conteúdo, na ordem:

1. **Cabeçalho:** nome, `curso · unidade · com {professor}`, selo do status e —
   quando `avisou_que_sai` — o selo "avisou que sai · {mes_saida}".
2. **A nota aberta**, com a decomposição em lista (não em tooltip: aqui ela é o
   conteúdo principal), cada linha com `contribuiu X de Y` e as linhas
   `sem_dado` marcadas como *fora da conta*.
3. **O absenteísmo com a base declarada:** `{faltas_janela} faltas em
   {aulas_medidas} aulas medidas · desde 01/08` e, ao lado, `professor {x}% ·
   unidade {y}%`.
4. **O semáforo do mês:** o coração, a frase das três perguntas e a observação
   entre aspas com `border-l-2 border-brand` (mesmo tratamento do
   `LinhaSemaforo`).
5. **Link "ver o mês inteiro"** → `/app/coordenacao/feedback`.

A frase das três perguntas usa o mesmo mapa `FRASE` que `LinhaSemaforo.tsx` já
tem — **importar de lá**, não recriar.

- [ ] **Step 2: Abrir o modal a partir da linha**

Em `CoordenacaoRadar.tsx`, estado `const [aberto, setAberto] = useState<RadarLinha | null>(null)`,
a linha chama `setAberto(linha)` e o modal fecha no `Escape` e no clique fora.

- [ ] **Step 3: Build e verificação**

```bash
npm run build
```

Ao vivo: abrir um aluno com nota e conferir que a soma das contribuições bate
com a nota exibida; abrir um sem nota e conferir que o modal explica o
silêncio (`apurada em 1 de 4 · insuficiente`).

- [ ] **Step 4: Commit**

```bash
git add src/features/coordenacao/components/ModalAlunoRadar.tsx src/pages/app/CoordenacaoRadar.tsx
git commit -m "feat(radar): o modal do aluno, com a nota aberta e a base declarada"
```

---

### Task 8: A aba Réguas

**Files:**
- Create: `src/pages/app/CoordenacaoReguas.tsx`
- Modify: `src/routes.tsx`
- Modify: `src/pages/app/CoordenacaoRadar.tsx` (link para as réguas)

**Interfaces:**
- Consumes: `radarConfig`, `salvarRadarConfig`, `RadarConfigItem` (Task 5)
- Produces: rota `/app/coordenacao/reguas`

- [ ] **Step 1: Criar a tela**

Quatro grupos (`pesos`, `faixas`, `absenteismo`, `base`), cada item com input
numérico, o **valor de fábrica visível ao lado** e um selo discreto quando
`mexido` for verdadeiro.

**Copy proibida nesta tela:** "recomendado", "padrão do sistema", "sugerido".
O default é ponto de partida, não verdade — escrever isso ao lado do número
transformaria escolha de gestão em regra técnica, e daqui a três meses ninguém
mexe porque "o sistema recomenda". O rótulo do valor de fábrica é **"de
fábrica: 25"**, e só.

Texto de abertura da tela:

```tsx
<p className="mb-6 text-[13px] leading-relaxed text-text-muted">
  Estas réguas são de gestão, não do sistema. Elas podem começar frouxas e
  apertar conforme a equipe amadurece — cada mudança fica registrada com quem
  mudou e quando.
</p>
```

- [ ] **Step 2: Salvar no blur, com confirmação visível**

Cada input salva no `onBlur` (não a cada tecla), chama `salvarRadarConfig` e
mostra um toast. Em caso de erro, **reverte o valor na tela** — campo que
mostra um número que o banco não tem é a mentira mais cara desta tela.

- [ ] **Step 3: Registrar a rota e o link**

`src/routes.tsx`, dentro de `RequireAdmin`:

```tsx
{ path: '/app/coordenacao/reguas', element: <CoordenacaoReguasPage /> },
```

Na página do Radar, um link discreto no rodapé dos filtros: `Réguas`.

- [ ] **Step 4: Build e verificação ao vivo**

```bash
npm run build
```

Ao vivo: mudar `absenteismo_atencao_pct` de 25 para 30, voltar ao Radar e
conferir que a contagem de atenção mudou; conferir no banco que o histórico
gravou:

```sql
select chave, valor_anterior, valor_novo, mudado_em
  from public.radar_config_historico order by mudado_em desc limit 3;
```

- [ ] **Step 5: Commit**

```bash
git add src/pages/app/CoordenacaoReguas.tsx src/routes.tsx src/pages/app/CoordenacaoRadar.tsx
git commit -m "feat(radar): a aba Réguas, com fábrica visível e histórico"
```

---

### Task 9: A regra visível na mesa do professor

**Files:**
- Modify: `src/features/feedback/MesaFeedback.tsx`

**Interfaces:**
- Consumes: nada novo.
- Produces: nada novo — é uma linha de copy.

**Por que é tarefa e não detalhe:** o semáforo é escrito pelo professor sobre o
aluno. Se ele suspeitar que aquilo vira número sobre ele, passa a responder mais
verde do que a realidade — e a fonte apodrece em silêncio, porque ninguém
enxerga um semáforo mentindo. A regra existe no banco (a 084 não agrega
semáforo por professor, e o mutante V4 guarda isso), mas **regra que o professor
não sabe que existe não muda comportamento.**

- [ ] **Step 1: Adicionar a linha**

Em `src/features/feedback/MesaFeedback.tsx`, logo abaixo do microcopy que já
existe (`Cada resposta salva sozinha — não tem botão de salvar.`):

```tsx
<p className="mb-4 flex items-start gap-2 text-[11.5px] leading-relaxed text-text-muted">
  <i className="fa-solid fa-shield-halved mt-0.5 text-brand-text" aria-hidden />
  <span>
    Isto não é avaliação sua. O que você marcar aqui não vira número sobre
    você — serve pra coordenação chegar no aluno sabendo do que falar.
  </span>
</p>
```

- [ ] **Step 2: Build e verificação**

```bash
npm run build
```

Ao vivo, com sessão de professor: a linha aparece acima dos cartões, antes do
primeiro aluno.

- [ ] **Step 3: Commit**

```bash
git add src/features/feedback/MesaFeedback.tsx
git commit -m "feat(feedback): o professor lê, na mesa, que aquilo não é avaliação dele"
```

---

## O que a spec pede e este plano NÃO faz

**O selo de presenteísmo** (aluno `presente` + `pratica_em_casa = não`,
repetido) fica para a Fase 2, e o motivo é aritmético: a spec define "repetido"
como dois meses seguidos, e existe **um** ciclo de semáforo (agosto, que nem
foi respondido ainda). Implementar agora seria escrever uma regra que não pode
ser testada com dado real — e um selo que nunca acende é indistinguível de um
selo quebrado. Volta quando setembro fechar, e a fonte já estará pronta:
`feedback` e `pratica_em_casa` saem da mesma linha da `vw_radar_aluno_sinais`.

**Nada mais da spec ficou de fora.** Conferido seção a seção.

## Fechamento

- [ ] **Rodar a bateria inteira**

```bash
node scripts/rodar-todos-os-testes.mjs
npm run build
```

- [ ] **Atualizar o `RETOMADA.md`** com o estado medido (não de memória):
  quantos alunos o Radar mostra, quantos com nota, o absenteísmo médio e a
  data em que a janela enche.

- [ ] **Push**

```bash
git push origin main
```

- [ ] **Conferir a produção** pelo bundle servido, não pelo painel da Vercel:
  o marcador `"Estas réguas são de gestão"` tem que estar no JS de produção.
