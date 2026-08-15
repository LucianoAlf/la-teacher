# Ocorrência de participação (substituição) em shadow — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dar ao Fábio um lugar canônico pra registrar quem PARTICIPOU no lugar de quem (substituição), separado do roster ESPERADO, rodando em shadow — sem tocar presença/falta/financeiro/Emusys.

**Architecture:** Duas tabelas append-only (fatos + eventos de ciclo de vida) com view de estado; RPCs `security definer` só pra `service_role` que impõem a máquina de estados e a escada de identidade; um detector determinístico puro no `fabio_whatsapp_intents.py`; e uma chamada em shadow no fluxo de registro do WhatsApp, em paralelo ao registro normal. A aula esperada continua vindo de `fabio_aulas_candidatas`/roster — esta camada só observa a divergência.

**Tech Stack:** PostgreSQL (Supabase `ouqwbbermlzqqvtqwlul`, compartilhado), plpgsql; Python 3 (bridge do Fábio na VPS, unittest); harness de teste da casa (`scripts/rodar-teste-sql.mjs` em BEGIN/ROLLBACK contra produção + mutantes em Docker `postgres:17-alpine`).

## Global Constraints

- **Nenhuma migration viva até o Alf revisar o plano.** Aplicar só depois: `node scripts/aplicar-sql.mjs <arquivo>`.
- **Shadow absoluto:** estado `candidata` (e qualquer estado nesta fase) NÃO escreve em presença, falta, reposição, financeiro nem Emusys. O teste conta linhas em `aluno_presenca`/`fabio_registros_aula`/`lead_experimental_*` antes e depois e exige **zero** diferença.
- **Append-only em duas camadas:** grant sem `UPDATE`/`DELETE` **E** trigger `BEFORE UPDATE OR DELETE` que levanta exceção. Ambos testados.
- **Extração determinística primeiro.** LLM só é gancho previsto, não implementado nesta fase.
- **`origem='whatsapp'` exige `origem_message_id` não nulo.** Idempotência estrutural por índice único.
- **Só `service_role`** executa as RPCs e lê/escreve as tabelas. `revoke ... from public, anon, authenticated`.
- **Duas sessões, mesmo checkout:** `git add` nomeando exatamente os arquivos da tarefa; `ls supabase/migrations` no disco antes de fixar número de migration (não confiar só no `git log`).
- **Deploy do bridge** exige `sed -i "s/\r$//"` (repo é CRLF) + `python -m unittest` na venv do Hermes + `systemctl --user restart fabio-chat-bridge.service`.
- Régua canônica da aula operacional: `fn_aula_operacional_id(p_aula_id integer)`. Fonte de identidade do participante: `vw_fabio_carteira_professor` (`professor_id, aluno_id, aluno_nome, unidade_id`).

---

## File Structure

- `supabase/migrations/20260815130000_participacao_ocorrencias_schema.sql` — tabelas, view, constraints, triggers (append-only + coerência de supersede), grants. **+** `.test.sql`.
- `supabase/migrations/20260815140000_participacao_ocorrencias_rpcs.sql` — 5 RPCs (resolver, registrar, confirmar, validar, descartar) + máquina de estados. **+** `.test.sql`.
- `scripts/mutantes-20260815130000.mjs` — mutantes do schema/triggers.
- `scripts/mutantes-20260815140000.mjs` — mutantes das RPCs/estados.
- `vps/fabio/fabio_whatsapp_intents.py` — nova função pura `detectar_substituicao`.
- `vps/fabio/teste_whatsapp_intents.py` — testes do detector.
- `vps/fabio/fabio_whatsapp_actions.py` — chamada em shadow no fluxo de registro.
- `vps/fabio/teste_whatsapp_actions.py` — testes do wiring em shadow (FakeBackend).

**Templates concretos a copiar** (a mecânica do harness já existe e não deve ser reinventada):
- Teste SQL de catálogo + bloco Docker DML: copiar a forma de `supabase/migrations/20260815100000_a_aula_sem_aluno_para_de_engolir_o_trabalho_do_professor.test.sql`.
- Runner de mutantes: copiar `scripts/mutantes-20260815100000.mjs` (bootstrap Docker, extração do bloco DOCKER-DML, baseline verde, cada mutante morre por asserção).

---

## Task 1 — Schema: tabelas, view, triggers append-only + supersede, grants

**Files:**
- Create: `supabase/migrations/20260815130000_participacao_ocorrencias_schema.sql`
- Test: `supabase/migrations/20260815130000_participacao_ocorrencias_schema.test.sql`
- Create: `scripts/mutantes-20260815130000.mjs`

**Interfaces:**
- Produces: tabela `public.fabio_participacao_ocorrencias`, tabela `public.fabio_participacao_ocorrencia_eventos`, view `public.vw_fabio_participacao_ocorrencia_estado`, trigger fn `public.fn_participacao_append_only()`, trigger fn `public.fn_participacao_supersede_coerente()`.
- Consome: `public.fn_aula_operacional_id(integer)` (já existe).

- [ ] **Step 1: Escrever a migration (DDL + triggers + grants)**

```sql
-- Camada de ocorrência de participação (substituição) — SHADOW.
-- Onde o Fábio registra quem PARTICIPOU no lugar de quem, separado do roster
-- ESPERADO. Nada aqui toca presença/falta/financeiro/Emusys nesta fase.

create table if not exists public.fabio_participacao_ocorrencias (
  id uuid primary key default gen_random_uuid(),
  aula_operacional_id integer not null,
  aula_id integer not null,
  professor_id integer not null,
  aluno_matriculado_id integer not null,
  participante_real_id integer,
  participante_real_nome text,
  participante_real_telefone text,
  tipo text not null default 'substituicao',
  confianca text not null,
  metodo_extracao text not null,
  origem text not null,
  origem_message_id text,
  origem_transcricao text,
  supersede_ocorrencia_id uuid references public.fabio_participacao_ocorrencias(id),
  criado_em timestamptz not null default now(),
  constraint chk_participacao_tipo check (tipo = any (array['substituicao'])),
  constraint chk_participacao_confianca check (confianca = any (array['alta','media','baixa'])),
  constraint chk_participacao_metodo check (metodo_extracao = any (array['deterministico','llm'])),
  constraint chk_participacao_origem check (origem = any (array['whatsapp','manual_admin'])),
  constraint chk_participante_identificado
    check (participante_real_id is not null
           or coalesce(btrim(participante_real_nome), '') <> ''),
  constraint chk_matriculado_difere_participante
    check (participante_real_id is null or participante_real_id <> aluno_matriculado_id),
  constraint chk_origem_message_id
    check (origem <> 'whatsapp' or origem_message_id is not null)
);

comment on table public.fabio_participacao_ocorrencias is
  'Quem participou no lugar de quem (substituicao), separado do roster esperado. Append-only: fatos nunca mudam; correcao e linha nova com supersede_ocorrencia_id. SHADOW: nao toca presenca/falta/financeiro/Emusys.';

-- Idempotencia estrutural: a mesma mensagem do WhatsApp nao gera duas
-- candidatas vigentes pra mesma aula+matriculado.
create unique index if not exists uq_participacao_msg_vigente
  on public.fabio_participacao_ocorrencias (aula_operacional_id, aluno_matriculado_id, origem_message_id)
  where origem_message_id is not null and supersede_ocorrencia_id is null;

create table if not exists public.fabio_participacao_ocorrencia_eventos (
  id uuid primary key default gen_random_uuid(),
  ocorrencia_id uuid not null references public.fabio_participacao_ocorrencias(id),
  evento text not null,
  por_tipo text not null,
  por_id text,
  dados jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now(),
  constraint chk_participacao_evento
    check (evento = any (array['registrada','confirmada','validada','descartada','corrigida'])),
  constraint chk_participacao_por_tipo
    check (por_tipo = any (array['sistema','professor','coordenacao']))
);

create index if not exists idx_participacao_evento_ocorrencia
  on public.fabio_participacao_ocorrencia_eventos (ocorrencia_id, criado_em);

comment on table public.fabio_participacao_ocorrencia_eventos is
  'Ciclo de vida da ocorrencia (append-only). Estado atual = ultimo evento. registrada->candidata na view.';

-- Estado atual = ultimo evento. registrada aparece como candidata.
create or replace view public.vw_fabio_participacao_ocorrencia_estado as
select distinct on (e.ocorrencia_id)
  e.ocorrencia_id,
  case e.evento when 'registrada' then 'candidata' else e.evento end as estado_atual,
  e.criado_em as estado_em,
  e.por_tipo  as estado_por
from public.fabio_participacao_ocorrencia_eventos e
order by e.ocorrencia_id, e.criado_em desc, e.id desc;

comment on view public.vw_fabio_participacao_ocorrencia_estado is
  'Fonte unica do estado atual de cada ocorrencia. registrada->candidata; o resto 1:1.';

-- Append-only camada 2: nem dono nem migration reescrevem/apagam fato.
create or replace function public.fn_participacao_append_only()
returns trigger language plpgsql as $function$
begin
  raise exception 'fabio_participacao e append-only: % bloqueado em %', tg_op, tg_table_name;
end
$function$;

create trigger trg_participacao_ocorrencias_append_only
  before update or delete on public.fabio_participacao_ocorrencias
  for each row execute function public.fn_participacao_append_only();

create trigger trg_participacao_eventos_append_only
  before update or delete on public.fabio_participacao_ocorrencia_eventos
  for each row execute function public.fn_participacao_append_only();

-- Coerencia do supersede: so corrige ocorrencia da MESMA aula + MESMO aluno
-- matriculado, e carimba 'corrigida' na antiga.
create or replace function public.fn_participacao_supersede_coerente()
returns trigger language plpgsql
set search_path to 'pg_catalog', 'public' as $function$
declare
  v_ant public.fabio_participacao_ocorrencias%rowtype;
begin
  if new.supersede_ocorrencia_id is null then
    return new;
  end if;
  select * into v_ant from public.fabio_participacao_ocorrencias where id = new.supersede_ocorrencia_id;
  if not found then
    raise exception 'supersede aponta pra ocorrencia inexistente';
  end if;
  if v_ant.aula_operacional_id <> new.aula_operacional_id
     or v_ant.aluno_matriculado_id <> new.aluno_matriculado_id then
    raise exception 'supersede so corrige a MESMA aula operacional e o MESMO aluno matriculado';
  end if;
  insert into public.fabio_participacao_ocorrencia_eventos (ocorrencia_id, evento, por_tipo, por_id, dados)
  values (v_ant.id, 'corrigida', 'sistema', null, jsonb_build_object('corrigida_por', new.id));
  return new;
end
$function$;

create trigger trg_participacao_supersede_coerente
  before insert on public.fabio_participacao_ocorrencias
  for each row execute function public.fn_participacao_supersede_coerente();

-- Portas fechadas: maquinario de worker.
revoke all on public.fabio_participacao_ocorrencias from public, anon, authenticated;
revoke all on public.fabio_participacao_ocorrencia_eventos from public, anon, authenticated;
revoke all on public.vw_fabio_participacao_ocorrencia_estado from public, anon, authenticated;
grant select, insert on public.fabio_participacao_ocorrencias to service_role;
grant select, insert on public.fabio_participacao_ocorrencia_eventos to service_role;
grant select on public.vw_fabio_participacao_ocorrencia_estado to service_role;
```

- [ ] **Step 2: Escrever o teste (contrato de catálogo + bloco Docker DML)**

Copiar a forma de `20260815100000_...test.sql`. O trecho remoto (catálogo) confere: as duas tabelas e a view existem; os triggers append-only e supersede existem; `service_role` **não** tem `UPDATE`/`DELETE`; `anon`/`authenticated` não têm nada. O bloco `/* SCHEMA-DOCKER-DML-TESTS-INICIO ... FIM */` roda no Postgres efêmero e prova por DML:

```sql
-- (dentro do bloco Docker) bootstrap minimo: pgcrypto, roles anon/authenticated/
-- service_role, e fn_aula_operacional_id fake que devolve o proprio id.
do $docker$
declare v_id uuid; v_ok boolean;
begin
  insert into public.fabio_participacao_ocorrencias
    (aula_operacional_id, aula_id, professor_id, aluno_matriculado_id,
     participante_real_nome, confianca, metodo_extracao, origem, origem_message_id)
  values (1, 1, 10, 793, 'Juliana', 'media', 'deterministico', 'whatsapp', 'wa:1')
  returning id into v_id;
  insert into public.fabio_participacao_ocorrencia_eventos (ocorrencia_id, evento, por_tipo)
  values (v_id, 'registrada', 'sistema');

  -- estado = candidata (registrada->candidata)
  perform pg_temp.checar_schema('registrada aparece como candidata na view',
    (select estado_atual from public.vw_fabio_participacao_ocorrencia_estado where ocorrencia_id = v_id) = 'candidata', '');

  -- append-only: UPDATE estoura
  begin
    update public.fabio_participacao_ocorrencias set confianca = 'alta' where id = v_id;
    perform pg_temp.checar_schema('UPDATE no fato e bloqueado pelo trigger', false, 'passou, e nao devia');
  exception when others then
    perform pg_temp.checar_schema('UPDATE no fato e bloqueado pelo trigger', true, sqlerrm);
  end;
  -- append-only: DELETE estoura
  begin
    delete from public.fabio_participacao_ocorrencias where id = v_id;
    perform pg_temp.checar_schema('DELETE no fato e bloqueado pelo trigger', false, 'passou');
  exception when others then
    perform pg_temp.checar_schema('DELETE no fato e bloqueado pelo trigger', true, sqlerrm);
  end;

  -- origem whatsapp sem message_id: recusado pelo CHECK
  begin
    insert into public.fabio_participacao_ocorrencias
      (aula_operacional_id, aula_id, professor_id, aluno_matriculado_id,
       participante_real_nome, confianca, metodo_extracao, origem)
    values (1, 1, 10, 793, 'Juliana', 'media', 'deterministico', 'whatsapp');
    perform pg_temp.checar_schema('whatsapp sem message_id e recusado', false, 'entrou');
  exception when check_violation then
    perform pg_temp.checar_schema('whatsapp sem message_id e recusado', true, 'recusado');
  end;

  -- supersede incoerente (outra aula) estoura
  begin
    insert into public.fabio_participacao_ocorrencias
      (aula_operacional_id, aula_id, professor_id, aluno_matriculado_id,
       participante_real_nome, confianca, metodo_extracao, origem, origem_message_id,
       supersede_ocorrencia_id)
    values (999, 999, 10, 793, 'Marina', 'media', 'deterministico', 'whatsapp', 'wa:2', v_id);
    perform pg_temp.checar_schema('supersede de outra aula e recusado', false, 'entrou');
  exception when others then
    perform pg_temp.checar_schema('supersede de outra aula e recusado', true, sqlerrm);
  end;

  -- supersede coerente carimba 'corrigida' na antiga
  insert into public.fabio_participacao_ocorrencias
    (aula_operacional_id, aula_id, professor_id, aluno_matriculado_id,
     participante_real_nome, confianca, metodo_extracao, origem, origem_message_id,
     supersede_ocorrencia_id)
  values (1, 1, 10, 793, 'Marina', 'media', 'deterministico', 'whatsapp', 'wa:3', v_id);
  perform pg_temp.checar_schema('supersede coerente carimba corrigida na antiga',
    exists (select 1 from public.fabio_participacao_ocorrencia_eventos
             where ocorrencia_id = v_id and evento = 'corrigida'), '');
end
$docker$;
```

- [ ] **Step 3: Escrever o runner de mutantes** — copiar `scripts/mutantes-20260815100000.mjs`. Mutantes (cada um morre por asserção):
  1. remove o trigger append-only → o `UPDATE` deixa de estourar (o teste "UPDATE bloqueado" morre).
  2. troca a view pra `evento` cru (sem o `case ... 'candidata'`) → "registrada aparece como candidata" morre.
  3. remove a checagem de aula no supersede → "supersede de outra aula recusado" morre.
  4. remove o `insert ... 'corrigida'` do trigger → "carimba corrigida" morre.
  5. remove o `chk_origem_message_id` → "whatsapp sem message_id recusado" morre.

- [ ] **Step 4: Rodar mutantes (todos mortos) e o ensaio contra produção (rollback, sem resíduo)**

Run:
```bash
node scripts/mutantes-20260815130000.mjs
node scripts/rodar-teste-sql.mjs supabase/migrations/20260815130000_participacao_ocorrencias_schema.sql supabase/migrations/20260815130000_participacao_ocorrencias_schema.test.sql
```
Expected: `N/N mutantes mortos`; `nenhuma divergência` + `linhas vivas idênticas` + `schema idêntico`.

- [ ] **Step 5: Commit** (NÃO aplicar em produção ainda — aguarda revisão do plano)

```bash
git add supabase/migrations/20260815130000_participacao_ocorrencias_schema.sql supabase/migrations/20260815130000_participacao_ocorrencias_schema.test.sql scripts/mutantes-20260815130000.mjs
git commit -m "feat(participacao): schema append-only da ocorrencia de substituicao (shadow)"
```

---

## Task 2 — RPCs: resolver identidade, registrar candidata, máquina de estados

**Files:**
- Create: `supabase/migrations/20260815140000_participacao_ocorrencias_rpcs.sql`
- Test: `supabase/migrations/20260815140000_participacao_ocorrencias_rpcs.test.sql`
- Create: `scripts/mutantes-20260815140000.mjs`

**Interfaces:**
- Consome: tabelas/view da Task 1; `vw_fabio_carteira_professor`; `fn_aula_operacional_id(integer)`.
- Produces (assinaturas exatas que o bridge na Task 4 chama):
  - `fabio_resolver_participante(p_professor_id integer, p_unidade_id uuid, p_nome text) returns jsonb` → `{cardinalidade int, candidatos:[{aluno_id,nome}], origem text}`.
  - `fabio_participacao_registrar_candidata(p_aula_id integer, p_professor_id integer, p_aluno_matriculado_id integer, p_participante_real_id integer, p_participante_nome text, p_participante_telefone text, p_confianca text, p_metodo_extracao text, p_origem_message_id text, p_origem_transcricao text) returns jsonb` → `{ok, ocorrencia_id, estado, precisa_confirmar, motivo_ambiguidade}`.
  - `fabio_participacao_confirmar(p_ocorrencia_id uuid, p_professor_id integer) returns jsonb` → `{ok, estado}`.
  - `fabio_participacao_validar(p_ocorrencia_id uuid, p_validado_por uuid) returns jsonb` → `{ok, estado}`.
  - `fabio_participacao_descartar(p_ocorrencia_id uuid, p_motivo text, p_por_tipo text, p_por_id text) returns jsonb` → `{ok, estado}`.

- [ ] **Step 1: Escrever a migration com as 5 RPCs**

Pontos que o código DEVE conter (o implementador escreve o corpo completo; estas são as regras inegociáveis):
- `fabio_resolver_participante`: busca em `vw_fabio_carteira_professor` por `professor_id` e nome casando por **token** (mesma régua de `_nome_tokens` do casador: palavra ≥3, sem sobrenome comum) — primeiro no professor, depois na unidade; devolve `cardinalidade` = nº de alunos distintos que batem, `candidatos`, e `origem` (`carteira`/`unidade`/`externo`). NÃO decide.
- `fabio_participacao_registrar_candidata`: `security definer`, `set search_path`. Resolve `aula_operacional_id := fn_aula_operacional_id(p_aula_id)`. Insere o FATO (`origem='whatsapp'`, exige `p_origem_message_id`) e o evento `registrada` (`por_tipo='sistema'`). Define `precisa_confirmar := (p_participante_real_id is null) or (p_confianca <> 'alta')`. **Não** lê nem escreve presença/registro/Emusys. Idempotente por `origem_message_id` (o índice único protege; em conflito devolve a ocorrência existente com `ja_existia=true`).
- Máquina de estados (as três RPCs de transição consultam a view de estado antes de inserir o evento):
  - `confirmar`: só de `candidata`; de `confirmada` é idempotente (devolve estado sem inserir); de `descartada`/`validada`/`corrigida` → `{ok:false, motivo}`.
  - `validar`: só de `confirmada`; idempotente de `validada`; senão `{ok:false}`.
  - `descartar`: de `candidata`/`confirmada`; de `validada`/`corrigida`/`descartada` → `{ok:false}` (validada só se desfaz por correção).
- Todas: `revoke ... from public, anon, authenticated`; `grant execute ... to service_role`.

- [ ] **Step 2: Escrever o teste (bloco Docker DML)** — bootstrap com as tabelas da Task 1 + uma `vw_fabio_carteira_professor` fake com dois alunos ("Billy", "Marcelo") e um "Felipe" duplicado (pra cardinalidade > 1). Casos:
  - registrar candidata com participante externo → `precisa_confirmar=true`, estado `candidata`, e **zero** linhas novas em qualquer tabela de presença (contar antes/depois — usar tabelas fake mínimas no bootstrap OU asserir que a RPC não referencia nenhuma).
  - `resolver_participante('Felipe')` → `cardinalidade=2`; `('Billy')` → `1`; `('Ninguém')` → `0`.
  - máquina de estados: `validar` uma `candidata` → `ok:false`; `confirmar` → `candidata→confirmada`; `validar` → `confirmada→validada`; `descartar` a `validada` → `ok:false`; `confirmar` de novo (idempotente) → `ok:true` sem novo evento.
  - idempotência: registrar duas vezes o mesmo `origem_message_id` → uma ocorrência só.

- [ ] **Step 3: Runner de mutantes** (copiar template). Mutantes:
  1. `precisa_confirmar` fixo em `false` → o caso "externo pede confirmação" morre.
  2. `validar` aceita de `candidata` (remove a checagem de `confirmada`) → "validar candidata recusa" morre.
  3. `descartar` aceita `validada` → "descartar validada recusa" morre.
  4. `resolver_participante` casa por nome inteiro (não token) → "Billy resolve cardinalidade 1" morre.
  5. remove o guard de idempotência (ou o `on conflict`) → "mesma mensagem = uma ocorrência" morre.

- [ ] **Step 4: Rodar mutantes + ensaio rollback**

Run:
```bash
node scripts/mutantes-20260815140000.mjs
node scripts/rodar-teste-sql.mjs supabase/migrations/20260815140000_participacao_ocorrencias_rpcs.sql supabase/migrations/20260815140000_participacao_ocorrencias_rpcs.test.sql
```
Expected: todos mutantes mortos; sem divergência/resíduo.

- [ ] **Step 5: Commit** (sem aplicar)

```bash
git add supabase/migrations/20260815140000_participacao_ocorrencias_rpcs.sql supabase/migrations/20260815140000_participacao_ocorrencias_rpcs.test.sql scripts/mutantes-20260815140000.mjs
git commit -m "feat(participacao): RPCs de substituicao com maquina de estados + escada de identidade (shadow)"
```

---

## Task 3 — Detector determinístico `detectar_substituicao`

**Files:**
- Modify: `vps/fabio/fabio_whatsapp_intents.py`
- Test: `vps/fabio/teste_whatsapp_intents.py`

**Interfaces:**
- Produces: `detectar_substituicao(texto: str, roster_nomes: list[str]) -> dict | None` → `{"matriculado": <nome do roster>, "participante": <nome citado>}` ou `None`. Reusa `_norm` e a régua de token de `_nome_tokens` (já existem no módulo).

- [ ] **Step 1: Escrever os testes que falham** (a frase EXATA do Isaque + as quatro frases fortes + o negativo)

```python
def test_detecta_substituicao_frase_do_isaque(self):
    from fabio_whatsapp_intents import detectar_substituicao
    r = detectar_substituicao(
        "quem fez aula no lugar do Jeremias foi a Juliana",
        ["Jeremias Ou Yuan Ma"])
    self.assertEqual(r["matriculado"], "Jeremias Ou Yuan Ma")
    self.assertEqual(_norm(r["participante"]), "juliana")

def test_detecta_quatro_frases_fortes(self):
    from fabio_whatsapp_intents import detectar_substituicao
    roster = ["Jeremias Ou Yuan Ma"]
    for frase in ("no lugar do Jeremias veio a Marina",
                  "quem fez foi a Marina",
                  "a Marina substituiu o Jeremias",
                  "a Marina veio no lugar dele"):
        with self.subTest(frase=frase):
            self.assertIsNotNone(detectar_substituicao(frase, roster), frase)

def test_sem_substituicao_devolve_none(self):
    from fabio_whatsapp_intents import detectar_substituicao
    self.assertIsNone(detectar_substituicao(
        "aula do Jeremias, trabalhamos escala", ["Jeremias Ou Yuan Ma"]))
```

- [ ] **Step 2: Rodar e ver falhar** — `cd vps/fabio && python -m unittest teste_whatsapp_intents` → FAIL (`detectar_substituicao` não existe).

- [ ] **Step 3: Implementar `detectar_substituicao`** — padrões fortes (`no lugar d[eoa]`, `quem fez foi`, `substituiu`, `veio no lugar`, `no lugar dele/dela`); o matriculado casa contra `roster_nomes` por token; o participante é o outro nome citado (heurística: nome próprio capitalizado / token ≥3 fora do roster). Devolve `None` se não isolar o par.

- [ ] **Step 4: Rodar e ver passar** — `python -m unittest teste_whatsapp_intents` → OK.

- [ ] **Step 5: Mutação manual de sanidade + commit** — trocar o conjunto de frases fortes por vazio e confirmar que os 3 testes caem; restaurar.

```bash
git add vps/fabio/fabio_whatsapp_intents.py vps/fabio/teste_whatsapp_intents.py
git commit -m "feat(fabio): detector deterministico de substituicao (X no lugar de Y)"
```

---

## Task 4 — Wiring em shadow no fluxo de registro do WhatsApp

**Files:**
- Modify: `vps/fabio/fabio_whatsapp_actions.py`
- Test: `vps/fabio/teste_whatsapp_actions.py`

**Interfaces:**
- Consome: `detectar_substituicao` (Task 3); `fabio_resolver_participante`, `fabio_participacao_registrar_candidata` (Task 2).
- Produces: chamada em shadow depois da aula pinada, sem alterar o resultado do registro normal.

- [ ] **Step 1: Escrever os testes (FakeBackend)** — o dublê registra a chamada `fabio_participacao_registrar_candidata` e prova: (a) quando a transcrição tem "no lugar do Jeremias foi a Juliana" e a aula foi pinada, a ocorrência é registrada; (b) o **resultado do registro normal não muda** (o `fabio_enfileirar_audio`/preview segue igual); (c) participante ambíguo → `precisa_confirmar` e o Fábio pergunta; (d) transcrição sem substituição → nenhuma chamada de participação. O dublê de `fabio_resolver_participante` devolve cardinalidade controlada; o de `registrar_candidata` devolve `{ok, ocorrencia_id, precisa_confirmar}`.

- [ ] **Step 2: Rodar e ver falhar** — `python -m unittest teste_whatsapp_actions` → FAIL.

- [ ] **Step 3: Implementar o wiring** — no ponto em que a aula é pinada (dentro/depois de `_select_and_enqueue_audio` e do caminho de refino), rodar `detectar_substituicao(transcricao, roster_da_aula)`; se achar par, `fabio_resolver_participante` → montar confiança (`alta` só se determinístico + participante único) → `fabio_participacao_registrar_candidata` em shadow. **Falha aqui nunca derruba o registro** (try/except que só loga). Se `precisa_confirmar`, anexar uma pergunta curta ao reply ("Foi a Juliana no lugar do Jeremias? Tem mais de uma Juliana — qual?"), sem bloquear o registro.

- [ ] **Step 4: Rodar e ver passar** — `python -m unittest teste_whatsapp_intents teste_whatsapp_actions` → OK.

- [ ] **Step 5: Deploy + falsificação ao vivo (só depois das migrations aplicadas)** — `scp` dos dois arquivos, `sed -i "s/\r$//"`, `unittest` na venv do Hermes, `systemctl --user restart fabio-chat-bridge.service`. Falsificação: rodar `detectar_substituicao` contra a transcrição real logada do Isaque em `fabio_chat_mensagens` e confirmar o par (Jeremias, Juliana). Commitar.

```bash
git add vps/fabio/fabio_whatsapp_actions.py vps/fabio/teste_whatsapp_actions.py
git commit -m "feat(fabio): registra substituicao em shadow no fluxo de registro do WhatsApp"
```

---

## Self-Review

**Spec coverage:**
- Tabela `fabio_participacao_ocorrencias` + eventos + view → Task 1. ✅
- Máquina de estados (transições permitidas/bloqueadas) → Task 2 Step 1/2. ✅
- `origem_message_id` obrigatório no WhatsApp → Task 1 (CHECK) + Task 2 (RPC exige). ✅
- Supersede coerente (mesma aula+aluno) → Task 1 (trigger). ✅
- Append-only em duas camadas (grant + trigger) → Task 1 + teste dos dois. ✅
- Extração determinística primeiro → Task 3; LLM fica como gancho não implementado (spec: fora de escopo). ✅
- Escada de identidade (carteira→unidade→externo) → Task 2 (`fabio_resolver_participante`). ✅
- Confiança atribuída por regra do chamador → Task 4 Step 3. ✅
- Shadow sem efeito operacional → Global Constraints + Task 2/Task 4 testes. ✅
- Teste contra a frase real do Isaque → Task 3 + Task 4 Step 5. ✅
- Validação da coordenação como portão futuro → `fabio_participacao_validar` existe (Task 2), sem efeito nesta fase. ✅

**Placeholder scan:** as RPCs da Task 2 Step 1 descrevem regras + assinaturas exatas em vez de despejar 200 linhas de plpgsql — as assinaturas e invariantes estão completas nos Interfaces e nas regras; o corpo é transcrição direta dessas regras. Os templates de teste/mutante apontam para arquivos reais existentes (não é "similar a"), com os mutantes listados um a um. Sem TBD/TODO.

**Type consistency:** os nomes de RPC e o shape de retorno usados na Task 4 batem com os `Produces` da Task 2; `detectar_substituicao(texto, roster_nomes)` idêntico entre Task 3 e Task 4; nomes de tabela/coluna idênticos entre Task 1, 2 e a spec.
