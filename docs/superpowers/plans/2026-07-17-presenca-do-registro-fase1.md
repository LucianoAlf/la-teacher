# Presença nasce do registro — Fase 1 (núcleo no banco) · Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fazer a presença **nascer da confirmação do registro do Fábio** (`fabio_audio`) e, de brinde, consertar o lockout da chamada do professor — tudo no banco, canônico.

**Architecture:** Extrair o núcleo de escrita de presença de `app_registrar_presencas_aula` para uma função interna `fn_registrar_presencas_core` com **upsert de promoção** (fonte forte vence `emusys`/`null`/`sistema`, nunca outra forte). `fabio_emitir_presenca_por_registro` lê as fatias do registro, deriva ausentes por `campos->>'presenca'` e chama o core com `respondido_por='fabio_audio'`, carimbando o desfecho no `campos` do tronco. `app_confirmar_registro` chama a emissão de forma **não-fatal** no fim.

**Tech Stack:** PostgreSQL (Supabase), migrations em `supabase/migrations/NNN-*.sql`, testes via SQL (transação com `ROLLBACK`). Sem app/edge nesta fase.

## Global Constraints

- **Fontes de presença** (`aluno_presenca.respondido_por`): fortes = `manual`, `professor_la_teacher`, `fabio_audio`; fracas = `emusys`, `sistema`, `null`.
- **Regra de escrita (first-HUMAN-write-wins):** `ON CONFLICT (aluno_id, aula_emusys_id) DO UPDATE ... WHERE aluno_presenca.respondido_por IS NULL OR aluno_presenca.respondido_por IN ('emusys','sistema')`. Nunca sobrescrever fonte forte.
- **Sem novas tabelas.** Só funções + (fase 2) uma view.
- **Não-fatal mas não silencioso:** desfecho da emissão carimbado em `fabio_registros_aula.campos` (`presenca_emitida`, `presenca_emitida_em`, `presenca_aplicado`, `presenca_erro`).
- **Migration:** um arquivo `supabase/migrations/009-presenca-do-registro.sql` (idempotente: `CREATE OR REPLACE`). Cada task acrescenta a esse arquivo.
- **Segurança de produção (piloto vivo):** todo teste roda em transação `BEGIN … ROLLBACK` (não persiste) OU numa branch Supabase. Só aplicar a prod após os 3 testes passarem.
- **Escopo desta fase:** só banco (core + emissão + gancho). A view de pendência + tela do app = Fase 2; governança WhatsApp = Fase 3 (planos separados).

---

## File Structure

- **Create:** `supabase/migrations/009-presenca-do-registro.sql` — as 3 funções desta fase (`fn_registrar_presencas_core`, `fabio_emitir_presenca_por_registro`) + `CREATE OR REPLACE` de `app_registrar_presencas_aula` e `app_confirmar_registro`.
- **Test (efêmero):** scripts SQL rodados via `execute_sql` em transação com `ROLLBACK` — não versionados (ou em `supabase/migrations/tests/009-*.sql` se preferirem manter).

Referência (ler antes): as versões atuais de `app_registrar_presencas_aula` e `app_confirmar_registro` (via `pg_get_functiondef`) — o core é extraído da primeira; o gancho entra na segunda.

---

### Task 1: `fn_registrar_presencas_core` + religar `app_registrar_presencas_aula`

**Files:**
- Create/append: `supabase/migrations/009-presenca-do-registro.sql`

**Interfaces:**
- Produces: `fn_registrar_presencas_core(p_aula_ancora_id int, p_professor_id int, p_alunos_ausentes int[], p_respondido_por text, p_estrito boolean) returns jsonb` — retorna `{aula_id, total_roster, inseridos, promovidos, ja_havia_forte, aplicado}`. Assume `p_aula_ancora_id` já é a âncora (turma ou individual standalone). Faz upsert de promoção.
- Consumes (inalterado externamente): `app_registrar_presencas_aula(p_aula_emusys_id int, p_alunos_ausentes int[])` passa a resolver âncora + validar e chamar o core com `'professor_la_teacher', p_estrito=true`.

- [ ] **Step 1: Escrever o teste que falha (promoção sobre `emusys`)**

Rodar via `execute_sql` (transação que reverte):

```sql
BEGIN;
-- fixture mínima: usa uma aula real de turma do Matheus (204140) que já tem linha emusys.
-- estado inicial: Anna Clara (29) veio de 'emusys'. Esperado após promover ausentes={}:
--   as 2 linhas viram 'professor_la_teacher' (promovidas), status_presenca 'presente'.
select public.fn_registrar_presencas_core(204140, 25, '{}'::int[], 'professor_la_teacher', false) as r;
-- assert:
do $$
declare n int;
begin
  select count(*) into n from public.aluno_presenca
   where aula_emusys_id=204140 and respondido_por='professor_la_teacher';
  if n < 2 then raise exception 'FALHOU: esperava >=2 promovidas, veio %', n; end if;
end $$;
ROLLBACK;
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `execute_sql` do script acima.
Expected: FAIL — `function fn_registrar_presencas_core(...) does not exist`.

- [ ] **Step 3: Implementar `fn_registrar_presencas_core` na migration 009**

```sql
create or replace function public.fn_registrar_presencas_core(
  p_aula_ancora_id  integer,
  p_professor_id    integer,
  p_alunos_ausentes integer[] default '{}'::integer[],
  p_respondido_por  text      default 'professor_la_teacher',
  p_estrito         boolean   default true
) returns jsonb
language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_aula          public.aulas_emusys%rowtype;
  v_roster_total  integer;
  v_sem_vinculo   integer;
  v_inseridos     integer;
  v_promovidos    integer;
  v_ja_forte      boolean;
begin
  if p_respondido_por not in ('professor_la_teacher','fabio_audio') then
    raise exception 'respondido_por_invalido: %', p_respondido_por;
  end if;

  select * into v_aula from public.aulas_emusys where id = p_aula_ancora_id;
  if not found then
    if p_estrito then raise exception 'aula_nao_encontrada'; end if;
    return jsonb_build_object('aula_id',p_aula_ancora_id,'aplicado',false,'motivo','aula_nao_encontrada');
  end if;
  if coalesce(v_aula.cancelada,false) then
    if p_estrito then raise exception 'aula_cancelada'; end if;
    return jsonb_build_object('aula_id',p_aula_ancora_id,'aplicado',false,'motivo','aula_cancelada');
  end if;

  -- #1 dono da aula: nunca escrever presença na aula de outro professor
  if v_aula.professor_id is distinct from p_professor_id then
    if p_estrito then raise exception 'aula_nao_pertence_ao_professor'; end if;
    return jsonb_build_object('aula_id',v_aula.id,'aplicado',false,'motivo','professor_divergente');
  end if;

  -- janela (só bloqueia em modo estrito; fabio é tolerante)
  if p_estrito then
    if v_aula.data_hora_inicio > now() + interval '15 minutes' then raise exception 'chamada_ainda_nao_disponivel'; end if;
    if coalesce(v_aula.data_hora_fim, v_aula.data_hora_inicio) < now() - interval '24 hours' then raise exception 'janela_de_chamada_encerrada'; end if;
  end if;

  select count(*), count(*) filter (where aluno_id is null)
    into v_roster_total, v_sem_vinculo
  from public.aula_alunos_emusys where aula_emusys_id = v_aula.id;
  if v_roster_total = 0 then
    if p_estrito then raise exception 'roster_nao_sincronizado'; end if;
    return jsonb_build_object('aula_id',v_aula.id,'aplicado',false,'motivo','roster_nao_sincronizado');
  end if;
  if v_sem_vinculo > 0 then
    if p_estrito then raise exception 'roster_incompleto'; end if;
    return jsonb_build_object('aula_id',v_aula.id,'aplicado',false,'motivo','roster_incompleto');
  end if;

  -- #2 ausente fora do roster: em estrito RAISE; em não-estrito ABORTA sem escrever
  -- (senão o id ruim seria ignorado e todo mundo viraria presente por engano)
  if exists (
    select 1 from unnest(coalesce(p_alunos_ausentes,'{}'::int[])) a(aluno_id)
    where not exists (select 1 from public.aula_alunos_emusys r
                      where r.aula_emusys_id = v_aula.id and r.aluno_id = a.aluno_id)
  ) then
    if p_estrito then raise exception 'aluno_ausente_fora_do_roster';
    else return jsonb_build_object('aula_id',v_aula.id,'aplicado',false,'motivo','aluno_ausente_fora_do_roster'); end if;
  end if;

  -- upsert de PROMOÇÃO: fonte forte vence null/emusys/sistema, nunca outra forte
  with up as (
    insert into public.aluno_presenca (
      aluno_id, aula_emusys_id, professor_id, unidade_id, data_aula, horario_aula,
      status, status_presenca, curso_nome, turma_nome, sala_nome, respondido_por, respondido_em)
    select distinct r.aluno_id, v_aula.id, p_professor_id, v_aula.unidade_id, v_aula.data_aula,
      (v_aula.data_hora_inicio at time zone 'America/Sao_Paulo')::time,
      case when r.aluno_id = any(coalesce(p_alunos_ausentes,'{}'::int[])) then 'ausente' else 'presente' end,
      case when r.aluno_id = any(coalesce(p_alunos_ausentes,'{}'::int[])) then 'falta' else 'presente' end,
      v_aula.curso_nome, v_aula.turma_nome, v_aula.sala_nome, p_respondido_por, now()
    from public.aula_alunos_emusys r
    where r.aula_emusys_id = v_aula.id and r.aluno_id is not null
    on conflict (aluno_id, aula_emusys_id) do update
      set status = excluded.status,
          status_presenca = excluded.status_presenca,
          respondido_por = excluded.respondido_por,
          respondido_em = excluded.respondido_em
      where aluno_presenca.respondido_por is null
         or aluno_presenca.respondido_por in ('emusys','sistema')
    returning (xmax = 0) as inserido)
  select count(*) filter (where inserido), count(*) filter (where not inserido)
    into v_inseridos, v_promovidos from up;

  return jsonb_build_object('aula_id', v_aula.id, 'total_roster', v_roster_total,
    'inseridos', coalesce(v_inseridos,0), 'promovidos', coalesce(v_promovidos,0), 'aplicado', true);
end
$function$;
```

E religar o wrapper (mantém contrato externo; resolve âncora + a política "chamada só na aula-âncora"):

```sql
create or replace function public.app_registrar_presencas_aula(
  p_aula_emusys_id integer, p_alunos_ausentes integer[] default '{}'::integer[])
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_prof integer := public.fn_professor_do_usuario();
  v_aula public.aulas_emusys%rowtype;
  v_turma_irma integer;
begin
  if v_prof is null then raise exception 'sem_professor_vinculado' using errcode='42501'; end if;
  select * into v_aula from public.aulas_emusys where id = p_aula_emusys_id;
  if not found or v_aula.professor_id is distinct from v_prof then
    raise exception 'aula_nao_pertence_ao_professor' using errcode='42501'; end if;

  if coalesce(v_aula.tipo,'') <> 'turma' then
    select t.id into v_turma_irma from public.aulas_emusys t
     where t.tipo='turma' and t.unidade_id=v_aula.unidade_id
       and t.data_hora_inicio=v_aula.data_hora_inicio
       and t.professor_id is not distinct from v_aula.professor_id
       and coalesce(t.cancelada,false)=false limit 1;
    if v_turma_irma is not null then
      raise exception 'chamada_somente_na_aula_ancora (use a aula % deste horario)', v_turma_irma; end if;
  end if;

  -- #3 curto-circuito "já enviada" só quando TODOS do roster já têm fonte forte
  -- (não basta 1; senão bloquearia completar os outros alunos). emusys NÃO conta.
  if exists (select 1 from public.aula_alunos_emusys r where r.aula_emusys_id=v_aula.id and r.aluno_id is not null)
     and not exists (
       select 1 from public.aula_alunos_emusys r
       where r.aula_emusys_id = v_aula.id and r.aluno_id is not null
         and not exists (
           select 1 from public.aluno_presenca ap
           where ap.aula_emusys_id = v_aula.id and ap.aluno_id = r.aluno_id
             and ap.respondido_por in ('professor_la_teacher','fabio_audio','manual')))
  then
    return jsonb_build_object('aula_id', v_aula.id, 'chamada_ja_enviada', true,
      'inseridos', 0, 'total_roster', (select count(*) from public.aula_alunos_emusys where aula_emusys_id=v_aula.id));
  end if;

  return public.fn_registrar_presencas_core(v_aula.id, v_prof, p_alunos_ausentes, 'professor_la_teacher', true)
       || jsonb_build_object('chamada_ja_enviada', false);
end
$function$;
```

- [ ] **Step 4: Aplicar (na branch/transação) e rodar o teste do Step 1**

Run: aplicar as duas funções via `execute_sql`; depois o script do Step 1.
Expected: PASS — a `r` traz `promovidos>=2`, o assert não levanta.

- [ ] **Step 5: Teste de regressão da chamada (não quebrou o professor)**

```sql
BEGIN;
-- aula sem presença forte: professor marca 1 ausente -> insere/promove; 2ª chamada -> chamada_ja_enviada
-- (rodar com uma aula de teste; asserts sobre respondido_por='professor_la_teacher' e status)
select public.fn_registrar_presencas_core(204140, 25, '{29}'::int[], 'professor_la_teacher', true) as r1;
do $$ declare s text; begin
  select status_presenca into s from public.aluno_presenca where aula_emusys_id=204140 and aluno_id=29;
  if s <> 'falta' then raise exception 'FALHOU: ausente nao virou falta (%).', s; end if;
end $$;
ROLLBACK;
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/009-presenca-do-registro.sql
git commit -m "feat(presenca): fn_registrar_presencas_core com upsert de promocao + religa chamada"
```

---

### Task 2: `fabio_emitir_presenca_por_registro` (+ carimbo no tronco)

**Files:**
- Append: `supabase/migrations/009-presenca-do-registro.sql`

**Interfaces:**
- Consumes: `fn_registrar_presencas_core(...)` (Task 1); `fn_aula_individual_do_aluno(aula, aluno)` e a resolução de âncora.
- Produces: `fabio_emitir_presenca_por_registro(p_registro_id uuid) returns jsonb` — retorna `{aula_id, presentes, ausentes, aplicado}`; carimba `campos` do tronco.

- [ ] **Step 1: Escrever o teste que falha**

```sql
BEGIN;
-- fixture: um registro de turma (tronco + fatias) com 1 fatia campos.presenca='ausente'.
-- (montar tronco em fabio_registros_aula com parent_id null + fatias; usar aula de turma real 204140, alunos 29 e 1605)
-- Esperado: aluno 29 vira falta (fabio_audio), aluno 1605 presente (fabio_audio); tronco.campos.presenca_aplicado=true
with tronco as (
  insert into public.fabio_registros_aula (aula_id, unidade_id, professor_id, molde, campos, status, origem)
  values (204140, '2ec861f6-023f-4d7b-9927-3960ad8c2a92', 25, 'C', '{}'::jsonb, 'aguardando_confirmacao','audio')
  returning id)
insert into public.fabio_registros_aula (parent_id, aula_id, aluno_id, professor_id, molde, campos, status, origem)
select t.id, 204140, x.aluno_id, 25, 'C', jsonb_build_object('presenca', x.p), 'aguardando_confirmacao','audio'
from tronco t, (values (29,'ausente'),(1605,'presente')) x(aluno_id,p);

select public.fabio_emitir_presenca_por_registro((select id from public.fabio_registros_aula where parent_id is null and aula_id=204140 order by criado_em desc limit 1));
do $$ declare s text; begin
  select status_presenca into s from public.aluno_presenca where aula_emusys_id=204140 and aluno_id=29;
  if s <> 'falta' then raise exception 'FALHOU: aluno 29 devia ser falta, veio %', s; end if;
end $$;
ROLLBACK;
```
Expected: FAIL — função não existe.

- [ ] **Step 2: Rodar e ver falhar** — `execute_sql`; Expected: FAIL.

- [ ] **Step 3: Implementar a emissão**

```sql
create or replace function public.fabio_emitir_presenca_por_registro(p_registro_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_reg      public.fabio_registros_aula%rowtype;
  v_ausentes integer[];
  v_ancora   integer;
  v_res      jsonb;
begin
  select * into v_reg from public.fabio_registros_aula where id = p_registro_id and parent_id is null;
  if not found then return jsonb_build_object('aplicado',false,'motivo','registro_nao_encontrado'); end if;

  -- ausentes = alunos cujas fatias tem campos.presenca='ausente' (ou o proprio tronco, caso 1 aluno)
  if v_reg.aluno_id is not null then
    v_ausentes := case when coalesce(v_reg.campos->>'presenca','presente')='ausente'
                       then array[v_reg.aluno_id] else '{}'::int[] end;
  else
    select coalesce(array_agg(f.aluno_id) filter (
             where coalesce(f.campos->>'presenca','presente')='ausente' and f.aluno_id is not null),'{}')
      into v_ausentes
    from public.fabio_registros_aula f where f.parent_id = p_registro_id;
  end if;

  -- ancora da chamada = turma-irma do MESMO professor se existir, senao a propria aula
  -- #4 filtra por professor_id: nao pegar turma de outro professor no mesmo horario/unidade
  select coalesce((
    select t.id from public.aulas_emusys t
     where t.tipo='turma'
       and t.unidade_id       = (select unidade_id from public.aulas_emusys where id=v_reg.aula_id)
       and t.data_hora_inicio = (select data_hora_inicio from public.aulas_emusys where id=v_reg.aula_id)
       and t.professor_id is not distinct from v_reg.professor_id
       and coalesce(t.cancelada,false)=false limit 1), v_reg.aula_id) into v_ancora;

  begin
    v_res := public.fn_registrar_presencas_core(v_ancora, v_reg.professor_id, v_ausentes, 'fabio_audio', false);
  exception when others then
    v_res := jsonb_build_object('aplicado',false,'erro', sqlerrm);
  end;

  -- carimbo no tronco (nao-silencioso)
  update public.fabio_registros_aula
     set campos = coalesce(campos,'{}'::jsonb) || jsonb_build_object(
           'presenca_emitida', true,
           'presenca_emitida_em', now(),
           'presenca_aplicado', coalesce((v_res->>'aplicado')::boolean, false),
           'presenca_erro', v_res->>'erro')
   where id = p_registro_id;

  return v_res || jsonb_build_object('ausentes', to_jsonb(v_ausentes));
end
$function$;
```

- [ ] **Step 4: Aplicar e rodar o teste do Step 1** — Expected: PASS (aluno 29 = falta, `fabio_audio`).

- [ ] **Step 5: Teste de idempotência (direto, não via confirmar)**

```sql
BEGIN;
-- (mesma fixture do Step 1) chamar 2x seguidas
select public.fabio_emitir_presenca_por_registro(:rid);
select public.fabio_emitir_presenca_por_registro(:rid);
do $$ declare n int; begin
  select count(*) into n from public.aluno_presenca where aula_emusys_id=204140 and aluno_id in (29,1605);
  if n <> 2 then raise exception 'FALHOU idempotencia: % linhas', n; end if;
end $$;
ROLLBACK;
```
Expected: PASS (2 linhas, sem duplicar).

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/009-presenca-do-registro.sql
git commit -m "feat(presenca): fabio_emitir_presenca_por_registro com promocao + carimbo no tronco"
```

---

### Task 3: Gancho não-fatal em `app_confirmar_registro`

**Files:**
- Append: `supabase/migrations/009-presenca-do-registro.sql`

**Interfaces:**
- Consumes: `fabio_emitir_presenca_por_registro(uuid)` (Task 2). Mantém todo o corpo atual de `app_confirmar_registro`; só adiciona a chamada não-fatal + o campo `presenca` no retorno.

- [ ] **Step 1: Escrever o teste que falha (retorno tem `presenca`)**

```sql
-- app_confirmar_registro usa auth.uid(); testar via impersonacao do professor (jwt claims) OU
-- validar indiretamente: apos confirmar, a emissao rodou (linhas fabio_audio) e o tronco tem presenca_aplicado.
-- Teste minimo: o retorno JSON passa a conter a chave 'presenca'.
BEGIN;
-- (montar registro confirmavel do prof 25; setar jwt do prof; chamar app_confirmar_registro)
-- assert:
do $$ declare j jsonb; begin
  -- j := resultado de app_confirmar_registro(:rid,'novo');
  if not (j ? 'presenca') then raise exception 'FALHOU: retorno sem chave presenca'; end if;
end $$;
ROLLBACK;
```
Expected: FAIL (retorno atual não tem `presenca`).

- [ ] **Step 2: Rodar e ver falhar.**

- [ ] **Step 3: Adicionar o gancho ao fim de `app_confirmar_registro`**

Reaplicar `app_confirmar_registro` (corpo atual **inalterado**) com, imediatamente antes do `return`:

```sql
  -- === GANCHO PRESENÇA (não-fatal) ===
  declare v_presenca jsonb;
  begin
    v_presenca := public.fabio_emitir_presenca_por_registro(p_registro_id);
  exception when others then
    v_presenca := jsonb_build_object('aplicado', false, 'erro', sqlerrm);
  end;

  return jsonb_build_object('registro_id', p_registro_id, 'modo', p_modo,
    'gravadas', v_gravadas, 'ausentes_puladas', v_puladas, 'pendencias', v_pend,
    'presenca', v_presenca);
```

(Declarar `v_presenca jsonb;` no bloco `declare` do topo em vez de inline, se preferir o estilo da função.)

- [ ] **Step 4: Aplicar e rodar o teste do Step 1** — Expected: PASS (retorno tem `presenca`; presença emitida).

- [ ] **Step 5: Teste não-fatal** — confirmar um registro cuja aula esteja fora da janela/roster incompleto → a confirmação **conclui** e `presenca.aplicado=false` com `motivo`/`erro`. Expected: PASS (confirmação não levanta).

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/009-presenca-do-registro.sql
git commit -m "feat(presenca): app_confirmar_registro emite presenca (nao-fatal)"
```

---

## Self-Review

**Cobertura da spec (Fase 1):** ✔ core com promoção (1.1) → Task 1; ✔ emissão + carimbo (1.2) → Task 2; ✔ gancho não-fatal (1.3) → Task 3. View de pendência (1.4) e app (3) = Fase 2, fora deste plano.

**Placeholders:** os fixtures dos testes (montar tronco/fatias, setar jwt) estão descritos mas não 100% literais porque dependem de ids de teste do ambiente — o executor deve materializá-los com dados do próprio banco (ex.: aula 204140, prof 25). Marcado explicitamente; não é "TODO de implementação", é dado de fixture.

**Consistência de tipos:** `fn_registrar_presencas_core(int,int,int[],text,boolean)→jsonb` usado igual em Task 1 (wrapper) e Task 2 (emissão). `fabio_emitir_presenca_por_registro(uuid)→jsonb` usado igual em Task 2 e Task 3. `respondido_por` sempre nos mesmos literais.

**Risco/segurança:** Task 1 altera `app_registrar_presencas_aula` (RPC viva do piloto) — regressão coberta no Step 5; a mudança de `do nothing`→promoção é intencional (conserta lockout). Aplicar em branch/transação e só promover a prod com os testes verdes.

---

## Nota de execução (ambiente)

- Escritas no banco (aplicar migration/execute_sql DDL) passam pela regra `mcp__…__execute_sql` já liberada. **Recomendo criar uma branch Supabase** (`create_branch`) pra testar sem tocar no piloto, e `merge_branch` ao fim.
- Fase 2 (view `vw_presenca_pendencia_fabio` + tela do professor no app) e Fase 3 (governança WhatsApp, lado do Alfredo) entram como planos próprios.
