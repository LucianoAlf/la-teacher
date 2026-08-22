# Cobrança da devolutiva da aula experimental — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fazer o Fábio cobrar o professor pela devolutiva da aula experimental — hoje 146 das 169 experimentais sem conteúdo são invisíveis à cobrança.

**Architecture:** Uma view nova (`vw_experimental_pendencia`) com régua própria, três RPCs de leitura, um evento novo no worker que já existe (`--event experimental_lembrete`) disparado por timer de 5min, e duas extensões nos eventos `pendencia` e `escalonamento`. A régua de aluno (`vw_registro_pendencia`) **não é tocada**.

**Tech Stack:** PostgreSQL/Supabase (migrations em `supabase/migrations/`), Python 3 sem dependências novas (`vps/fabio/fabio_notification_worker.py`), systemd user units na VPS.

**Spec:** `docs/superpowers/specs/2026-08-22-cobranca-devolutiva-experimental-design.md` (commit 75cac43)

## Global Constraints

- **Data de corte:** `date '2026-08-22'` — literal exato, em `fn_data_corte_experimental()`.
- **Janela de escalonamento:** `3` dias, em `fn_janela_experimental_dias()`. NUNCA alterar `fn_janela_registro_dias()` (7 dias, é do aluno).
- **Tipo de notificação:** `pendencia_experimental`. NUNCA alterar `pendencia_registro`.
- **Trava de duplicata:** usar `fabio_claim_notificacao_por_referencia` com `p_referencia_tipo = 'experimental_vinculo'` e `p_referencia_id = <vinculo_id como texto>`. O índice `uq_fabio_notif_por_referencia` (UNIQUE em `referencia_tipo, referencia_id, canal`) já garante uma vez por vínculo **para sempre**. Não criar índice novo.
- ⚠️ **`mark_sent` exige o `lease_token` quando o claim é por referência.** Chamar sem token deixa a notificação presa em `processando` com a mensagem já entregue (aconteceu em 03/08/2026). Sempre `mark_sent(notificacao_id, lease_token)`.
- **Professor sem app nunca entra:** todo caminho passa por `fn_professor_usa_app(professor_id)`.
- **Fecha na CONFIRMAÇÃO, não na gravação:** pendência só sai quando existe `lead_experimental_registros` com `status` fora de (`descartado`, `aguardando_confirmacao`).
- **Testes SQL rodam em produção via BEGIN/ROLLBACK** (branches são inviáveis neste projeto). Testes Python rodam na VPS em `~/fabio-chat-bridge` com `set -a && . ~/.hermes/.env && set +a`.
- **Mutante vivo = trava sem teste.** Todo invariante tem mutante que precisa MORRER.
- **Duas sessões, o mesmo checkout:** `git add <arquivo>` nomeando arquivos; nunca `git add -A`. Antes de criar migration, `ls supabase/migrations/` (o `git log` não vê arquivo não commitado da outra sessão).

---

### Task 1: Régua de dados (view + funções + testes)

**Files:**
- Create: `supabase/migrations/20260822160000_cobranca_experimental_regua.sql`
- Create: `supabase/migrations/20260822160000_cobranca_experimental_regua.test.sql`

**Interfaces:**
- Produces: `fn_data_corte_experimental() returns date`; `fn_janela_experimental_dias() returns integer`; view `vw_experimental_pendencia` com colunas `vinculo_id bigint`, `lead_id integer`, `nome_aluno text`, `aula_id integer`, `professor_id integer`, `professor_nome text`, `unidade_id uuid`, `unidade_nome text`, `curso_nome text`, `data_hora_fim timestamptz`, `horas_em_atraso integer`, `dias_em_atraso integer`, `tipo_alvo text` (sempre `'experimental'`).
- Consumes: `fn_professor_usa_app(integer)` e `fn_aula_operacional_id(integer)`, ambas já existentes.

- [ ] **Step 1: Conferir que o número da migration está livre no DISCO**

```bash
ls supabase/migrations/ | grep 20260822 || echo "livre"
```

Se houver colisão, subir o horário (`20260822161000`, etc.). O `git log` não basta — a outra sessão pode ter arquivo não commitado.

- [ ] **Step 2: Escrever o teste primeiro**

Criar `supabase/migrations/20260822160000_cobranca_experimental_regua.test.sql`:

```sql
-- Teste da régua de cobrança da experimental. Roda em BEGIN/ROLLBACK.
do $$
declare
  v_n integer; v_antes integer; v_depois integer;
  v_prof integer; v_uid integer; v_auth uuid; v_vinculo bigint; v_aula integer;
begin
  -- 1. as funções existem e devolvem o combinado
  if public.fn_data_corte_experimental() <> date '2026-08-22' then
    raise exception 'FALHOU 1a: corte deveria ser 2026-08-22, veio %', public.fn_data_corte_experimental();
  end if;
  if public.fn_janela_experimental_dias() <> 3 then
    raise exception 'FALHOU 1b: janela deveria ser 3, veio %', public.fn_janela_experimental_dias();
  end if;

  -- 2. INVARIANTE 1: a régua de ALUNO não muda. Se esta contagem mudar, a
  --    entrega quebrou o que já estava no ar.
  select count(*) into v_antes from vw_registro_pendencia where cobravel;
  if v_antes = 0 then
    raise exception 'FALHOU 2: baseline de aluno veio 0 — teste nao mede nada';
  end if;

  -- 3. INVARIANTE 2: professor sem app nunca entra
  select count(*) into v_n from vw_experimental_pendencia v
   where not public.fn_professor_usa_app(v.professor_id);
  if v_n <> 0 then
    raise exception 'FALHOU 3: % linha(s) de professor sem app', v_n;
  end if;

  -- 4. INVARIANTE 3: nada antes da data de corte
  select count(*) into v_n from vw_experimental_pendencia v
   where (v.data_hora_fim at time zone 'America/Sao_Paulo')::date < public.fn_data_corte_experimental();
  if v_n <> 0 then
    raise exception 'FALHOU 4: % linha(s) anteriores ao corte', v_n;
  end if;

  -- 5. INVARIANTE 5: registro em aguardando_confirmacao CONTINUA pendente.
  --    Cenário sintético: pego uma pendência real e crio o registro nao
  --    confirmado; ela tem que permanecer. Tudo volta no ROLLBACK.
  select v.vinculo_id, v.aula_id into v_vinculo, v_aula
    from vw_experimental_pendencia v limit 1;
  if v_vinculo is not null then
    insert into lead_experimental_registros (vinculo_id, status, anotacao_pedagogica)
      values (v_vinculo, 'aguardando_confirmacao', 'teste');
    if not exists (select 1 from vw_experimental_pendencia where vinculo_id = v_vinculo) then
      raise exception 'FALHOU 5: pendencia fechou com registro NAO confirmado (vinculo %)', v_vinculo;
    end if;
    update lead_experimental_registros set status = 'confirmado'
     where vinculo_id = v_vinculo and status = 'aguardando_confirmacao';
    if exists (select 1 from vw_experimental_pendencia where vinculo_id = v_vinculo) then
      raise exception 'FALHOU 5b: pendencia NAO fechou com registro confirmado (vinculo %)', v_vinculo;
    end if;
  end if;

  -- 6. INVARIANTE 1 (fecho): a régua de aluno segue idêntica
  select count(*) into v_depois from vw_registro_pendencia where cobravel;
  if v_antes <> v_depois then
    raise exception 'FALHOU 6: regua de aluno mudou (% -> %)', v_antes, v_depois;
  end if;

  raise exception 'VERDE: todos os casos passaram (baseline aluno=%)', v_antes;
end $$;
```

- [ ] **Step 3: Rodar o teste e ver falhar pelo motivo certo**

Rodar o bloco acima via `mcp__supabase__execute_sql`.
Esperado: `ERRO: function public.fn_data_corte_experimental() does not exist` — falha por função ausente, não por typo.

- [ ] **Step 4: Escrever a migration**

Criar `supabase/migrations/20260822160000_cobranca_experimental_regua.sql`:

```sql
-- Cobrança da devolutiva da aula experimental — régua de dados.
-- Spec: docs/superpowers/specs/2026-08-22-cobranca-devolutiva-experimental-design.md
--
-- POR QUE ESTA VIEW EXISTE SEPARADA. vw_registro_pendencia faz
-- `JOIN alunos al ON al.id = r.aluno_id`, e no roster de uma experimental o
-- lead entra com aluno_id NULO — o INNER JOIN derruba a aula inteira. Em 30
-- dias, 146 das 169 experimentais sem conteúdo eram invisíveis à cobrança.
-- Estender aquela view faria a régua de aluno carregar condicional que não é
-- dela; esta trilha tem gatilho próprio (status do lead), janela própria (3
-- dias, não 7) e destinatário próprio.

create or replace function public.fn_data_corte_experimental()
returns date language sql immutable parallel safe
as $$ select date '2026-08-22' $$;

comment on function public.fn_data_corte_experimental() is
  'Data em que a cobranca da experimental passou a valer. Sem ela, o dia 1 despejaria 27 escalonamentos de backlog na coordenacao.';

create or replace function public.fn_janela_experimental_dias()
returns integer language sql immutable
as $$ select 3 $$;

comment on function public.fn_janela_experimental_dias() is
  'Dias ate a experimental sem devolutiva escalar para a coordenacao. Separada de fn_janela_registro_dias() (7 dias, do aluno) de proposito.';

create or replace view public.vw_experimental_pendencia as
select
  v.id                                   as vinculo_id,
  le.id                                  as lead_id,
  le.nome_aluno,
  a.id                                   as aula_id,
  a.professor_id,
  u.nome                                 as professor_nome,
  a.unidade_id,
  un.nome                                as unidade_nome,
  a.curso_nome,
  a.data_hora_fim,
  floor(extract(epoch from now() - a.data_hora_fim) / 3600)::integer  as horas_em_atraso,
  floor(extract(epoch from now() - a.data_hora_fim) / 86400)::integer as dias_em_atraso,
  'experimental'::text                   as tipo_alvo
from public.lead_experimentais le
join public.lead_experimental_aulas v
  on v.lead_experimental_id = le.id
 and v.substituido_em is null
 and v.cancelado_em is null
join public.aulas_emusys a on a.id = v.aula_local_id
left join public.professores pr on pr.id = a.professor_id
left join public.usuarios u on u.id = pr.usuario_id
left join public.unidades un on un.id = a.unidade_id
where
  -- gatilho: a equipe deu presença ao lead (combinado: marcar na chegada)
  le.status in ('experimental_realizada', 'convertido')
  and a.id = public.fn_aula_operacional_id(a.id)
  and coalesce(a.cancelada, false) = false
  and a.data_hora_fim < now()
  -- só a partir do corte: a trilha nasce valendo pra frente
  and (a.data_hora_fim at time zone 'America/Sao_Paulo')::date >= public.fn_data_corte_experimental()
  -- não se cobra quem não tem a ferramenta
  and public.fn_professor_usa_app(a.professor_id)
  -- fecha na CONFIRMAÇÃO: gravado e não confirmado o comercial não recebe
  and not exists (
    select 1 from public.lead_experimental_registros r
     where r.vinculo_id = v.id
       and r.status not in ('descartado', 'aguardando_confirmacao')
  );

comment on view public.vw_experimental_pendencia is
  'Experimental realizada, do corte pra frente, cujo professor tem o app e ainda nao CONFIRMOU a devolutiva. Regua propria: a de aluno (vw_registro_pendencia) nao e tocada.';
```

- [ ] **Step 5: Aplicar e rodar o teste — verde**

Aplicar via `mcp__supabase__apply_migration` (nome `cobranca_experimental_regua`), depois rodar o teste do Step 2.
Esperado: `VERDE: todos os casos passaram (baseline aluno=507)`.

- [ ] **Step 6: Matar os mutantes**

Rodar num DO block com ROLLBACK, substituindo a view por versões mutadas e checando que o teste falha:

| Mutante | Como | Tem que |
|---|---|---|
| M1: sem `fn_professor_usa_app` | remover a linha do where | MORRER no caso 3 |
| M2: sem data de corte | remover a linha do corte | MORRER no caso 4 |
| M3: fecha no gravar | trocar `not in ('descartado','aguardando_confirmacao')` por `<> 'descartado'` | MORRER no caso 5 |
| M4 (controle): view original | — | PASSAR |

⚠️ M1 e M2 podem sobreviver se os dados de hoje não distinguirem. Se sobreviverem, **escrever o cenário sintético** (UPDATE temporário dentro do ROLLBACK) — nunca apagar a trava. Conferir antes que os triggers das tabelas tocadas não chamam `net.http`:

```sql
select c.relname, p.proname, pg_get_functiondef(p.oid) ilike '%net.http%' as chama_http
from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_proc p on p.oid=t.tgfoid
join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and not t.tgisinternal
  and c.relname in ('lead_experimentais','lead_experimental_aulas','lead_experimental_registros');
```

- [ ] **Step 7: Conferir o volume real**

```sql
select count(*) as pendencias_hoje,
       count(*) filter (where dias_em_atraso >= public.fn_janela_experimental_dias()) as escalariam
from vw_experimental_pendencia;
```

Esperado: número pequeno (na medição de 22/08: **2**, não 27). Se vier na casa das dezenas, a data de corte não está sendo aplicada — parar e investigar antes de seguir.

- [ ] **Step 8: Commit**

```bash
git add supabase/migrations/20260822160000_cobranca_experimental_regua.sql supabase/migrations/20260822160000_cobranca_experimental_regua.test.sql
git commit -m "feat(experimental): regua de cobranca da devolutiva da experimental"
```

---

### Task 2: RPCs de leitura

**Files:**
- Create: `supabase/migrations/20260822170000_cobranca_experimental_rpcs.sql`
- Create: `supabase/migrations/20260822170000_cobranca_experimental_rpcs.test.sql`

**Interfaces:**
- Consumes: `vw_experimental_pendencia`, `fn_janela_experimental_dias()` (Task 1).
- Produces:
  - `fn_experimental_lembrete_alvos(p_minutos integer default 20) returns jsonb` — aulas encerradas nos últimos N minutos, agrupadas por professor.
  - `fn_experimental_pendencia_do_professor(p_professor_id integer) returns jsonb` — tudo que está pendente daquele professor.
  - `fn_experimental_escalonadas() returns jsonb` — o que passou da janela, para a coordenação.

Todas devolvem `{"ok": true, "linhas": [...]}`; `linhas` é `[]` quando não há nada (vazio é resposta, `null` é ignorância).

- [ ] **Step 1: Escrever o teste primeiro**

Criar `supabase/migrations/20260822170000_cobranca_experimental_rpcs.test.sql`:

```sql
do $$
declare r jsonb;
begin
  -- forma: sempre {ok, linhas}, linhas nunca null
  r := public.fn_experimental_lembrete_alvos(20);
  if (r->>'ok')::boolean is not true or jsonb_typeof(r->'linhas') <> 'array' then
    raise exception 'FALHOU 1: forma errada em lembrete_alvos: %', r;
  end if;

  r := public.fn_experimental_pendencia_do_professor(-1);
  if jsonb_array_length(r->'linhas') <> 0 then
    raise exception 'FALHOU 2: professor inexistente devia vir vazio, veio %', r;
  end if;

  r := public.fn_experimental_escalonadas();
  if jsonb_typeof(r->'linhas') <> 'array' then
    raise exception 'FALHOU 3: escalonadas devia ser array, veio %', jsonb_typeof(r->'linhas');
  end if;

  -- janela: nada com menos dias que a janela pode aparecer no escalonamento
  if exists (
    select 1 from jsonb_array_elements(public.fn_experimental_escalonadas()->'linhas') x
     where (x->>'dias_em_atraso')::int < public.fn_janela_experimental_dias()
  ) then
    raise exception 'FALHOU 4: escalonamento trouxe caso dentro da janela';
  end if;

  -- lembrete: janela de minutos é respeitada
  if exists (
    select 1 from jsonb_array_elements(public.fn_experimental_lembrete_alvos(20)->'linhas') x
     where (x->>'horas_em_atraso')::int > 1
  ) then
    raise exception 'FALHOU 5: lembrete trouxe aula de mais de 1h atras com janela de 20min';
  end if;

  raise exception 'VERDE: RPCs ok';
end $$;
```

- [ ] **Step 2: Rodar e ver falhar**

Esperado: `function public.fn_experimental_lembrete_alvos(integer) does not exist`.

- [ ] **Step 3: Escrever a migration**

```sql
-- RPCs de leitura da cobrança da experimental. Só leem a view da Task 1 —
-- nenhuma régua nova mora aqui (duas cópias da régua divergem em silêncio).

create or replace function public.fn_experimental_lembrete_alvos(p_minutos integer default 20)
returns jsonb language sql stable security definer set search_path to 'public'
as $$
  -- Janela folgada de propósito: se um tick do timer falhar, o próximo ainda
  -- alcança a aula, em vez de perder o lembrete pra sempre.
  select jsonb_build_object('ok', true, 'linhas', coalesce(jsonb_agg(x), '[]'::jsonb))
  from (
    select jsonb_build_object(
      'vinculo_id', v.vinculo_id, 'professor_id', v.professor_id,
      'nome_aluno', v.nome_aluno, 'curso_nome', v.curso_nome,
      'unidade_nome', v.unidade_nome,
      'hora_fim', to_char(v.data_hora_fim at time zone 'America/Sao_Paulo', 'HH24:MI'),
      'horas_em_atraso', v.horas_em_atraso
    ) as x
    from public.vw_experimental_pendencia v
    where v.data_hora_fim >= now() - make_interval(mins => greatest(coalesce(p_minutos, 20), 1))
    order by v.data_hora_fim desc
  ) s;
$$;

create or replace function public.fn_experimental_pendencia_do_professor(p_professor_id integer)
returns jsonb language sql stable security definer set search_path to 'public'
as $$
  select jsonb_build_object('ok', true, 'linhas', coalesce(jsonb_agg(x), '[]'::jsonb))
  from (
    select jsonb_build_object(
      'vinculo_id', v.vinculo_id, 'nome_aluno', v.nome_aluno,
      'curso_nome', v.curso_nome, 'unidade_nome', v.unidade_nome,
      'quando', to_char(v.data_hora_fim at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI'),
      'dias_em_atraso', v.dias_em_atraso
    ) as x
    from public.vw_experimental_pendencia v
    where v.professor_id = p_professor_id
    order by v.data_hora_fim desc
  ) s;
$$;

create or replace function public.fn_experimental_escalonadas()
returns jsonb language sql stable security definer set search_path to 'public'
as $$
  select jsonb_build_object('ok', true,
                            'janela_dias', public.fn_janela_experimental_dias(),
                            'linhas', coalesce(jsonb_agg(x), '[]'::jsonb))
  from (
    select jsonb_build_object(
      'vinculo_id', v.vinculo_id, 'nome_aluno', v.nome_aluno,
      'professor_nome', v.professor_nome, 'unidade_nome', v.unidade_nome,
      'curso_nome', v.curso_nome,
      'quando', to_char(v.data_hora_fim at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI'),
      'dias_em_atraso', v.dias_em_atraso
    ) as x
    from public.vw_experimental_pendencia v
    where v.dias_em_atraso >= public.fn_janela_experimental_dias()
    order by v.dias_em_atraso desc
  ) s;
$$;
```

- [ ] **Step 4: Aplicar, rodar o teste — verde**

Esperado: `VERDE: RPCs ok`.

- [ ] **Step 5: Mutante da janela**

Trocar `>= public.fn_janela_experimental_dias()` por `>= 0` em `fn_experimental_escalonadas` (dentro de ROLLBACK) e rodar o teste: o caso 4 tem que MORRER. Restaurar.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260822170000_cobranca_experimental_rpcs.sql supabase/migrations/20260822170000_cobranca_experimental_rpcs.test.sql
git commit -m "feat(experimental): RPCs de leitura da cobranca da experimental"
```

---

### Task 3: Evento `experimental_lembrete` no worker

**Files:**
- Modify: `vps/fabio/fabio_notification_worker.py` (dict `EVENTS` ~linha 65; `--event` choices ~linha 1742; função nova)
- Create: `vps/fabio/teste_experimental_lembrete.py`
- Create: `vps/fabio/fabio-experimental-lembrete.systemd.txt` (unit + timer, para o Hugo/Alf instalarem)

**Interfaces:**
- Consumes: `fn_experimental_lembrete_alvos(20)` (Task 2); `rpc()`, `deliver()`, `mark_sent()`, `log()` do próprio worker.
- Produces: `format_lembrete_experimental(linha: dict) -> str` (puro, testável) e `run_experimental_lembrete(channel: str, dry_run: bool) -> dict`.

- [ ] **Step 1: Escrever o teste primeiro**

Criar `vps/fabio/teste_experimental_lembrete.py`:

```python
#!/usr/bin/env python3
"""Teste do lembrete imediato da experimental (fabio_notification_worker).

POR QUE ELE EXISTE. O lembrete roda de 5 em 5 minutos. Sem trava, o mesmo
professor recebe a mesma cobranca 12 vezes por hora — e cobranca repetida
ensina a ignorar. A trava real e o indice uq_fabio_notif_por_referencia, que
so morde se a referencia for (experimental_vinculo, vinculo_id): errar o
carimbo aqui desliga a trava sem nenhum erro aparecer.

Rodar:  python3 teste_experimental_lembrete.py
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fabio_notification_worker import (  # noqa: E402
    format_lembrete_experimental, REFERENCIA_TIPO_EXPERIMENTAL,
)

falhas: list[str] = []
total = 0


def checar(nome, esperado, obtido):
    global total
    total += 1
    if esperado != obtido:
        falhas.append(f"{nome}\n    esperado: {esperado!r}\n    obtido:   {obtido!r}")


LINHA = {"vinculo_id": 2275, "professor_id": 10, "nome_aluno": "Davi Nakashima",
         "curso_nome": "Aula Experimental", "unidade_nome": "Barra",
         "hora_fim": "19:00", "horas_em_atraso": 0}

texto = format_lembrete_experimental(LINHA)

# 1. o que o professor precisa pra saber DE QUEM se trata
checar("1. cita o nome do lead", True, "Davi Nakashima" in texto)
checar("1b. cita o horario", True, "19:00" in texto)

# 2. o lembrete VENDE a ferramenta (e o habito que o Alf quer criar).
#    Sem isso vira mais uma cobranca e o professor nao entende pra que serve.
checar("2. explica que o comercial usa", True, "comercial" in texto.lower())

# 3. NEGATIVO: nao pode vazar jargao de sistema pro professor
for termo in ("vinculo", "vinculo_id", "lead_experimental", "None", "null"):
    checar(f"3. nao vaza '{termo}'", False, termo in texto)

# 4. a referencia da trava e o VINCULO — se virar 'devolutiva' ou o id da aula,
#    o indice unico deixa de morder e o professor leva 12 mensagens por hora
checar("4. carimbo da referencia e experimental_vinculo",
       "experimental_vinculo", REFERENCIA_TIPO_EXPERIMENTAL)

# 5. formas degeneradas nao podem explodir o worker no meio do lote
checar("5. sem nome nao explode", True, isinstance(
    format_lembrete_experimental({**LINHA, "nome_aluno": None}), str))
checar("5b. sem hora nao explode", True, isinstance(
    format_lembrete_experimental({**LINHA, "hora_fim": None}), str))

print(f"\n{total - len(falhas)}/{total} passaram")
if falhas:
    print("\nFALHAS:")
    for f in falhas:
        print(f"  x {f}")
    sys.exit(1)
print("tudo verde")
```

- [ ] **Step 2: Rodar e ver falhar**

```bash
scp -i ~/.ssh/id_ed25519_lahq_fabio_claude_code vps/fabio/teste_experimental_lembrete.py fabio@89.116.73.186:'~/fabio-chat-bridge/'
ssh -i ~/.ssh/id_ed25519_lahq_fabio_claude_code fabio@89.116.73.186 'cd ~/fabio-chat-bridge && set -a && . ~/.hermes/.env && set +a && python3 -B teste_experimental_lembrete.py'
```

Esperado: `ImportError: cannot import name 'format_lembrete_experimental'`.

- [ ] **Step 3: Implementar no worker**

Em `vps/fabio/fabio_notification_worker.py`, adicionar após o dict `EVENTS`:

```python
# A referência que liga a notificação ao vínculo. É ela que aciona o índice
# uq_fabio_notif_por_referencia (UNIQUE em referencia_tipo, referencia_id,
# canal) e garante UM lembrete por vínculo — pra sempre, não por dia. O
# lembrete imediato existe pra criar o hábito no calor da aula; quem insiste
# depois é a recobrança (noite/manhã) e o escalonamento, cada um com a trava
# dele. Mudar este literal desliga a trava sem erro nenhum aparecer.
REFERENCIA_TIPO_EXPERIMENTAL = "experimental_vinculo"

EVENTS["experimental_lembrete"] = EventSpec(
    "pendencia_experimental", "governanca", DEFAULT_PENDENCIA_TIME)


def format_lembrete_experimental(linha: Dict[str, Any]) -> str:
    nome = (linha.get("nome_aluno") or "o lead").strip()
    hora = (linha.get("hora_fim") or "").strip()
    quando = f", {hora}" if hora else ""
    return (
        f"🎓 *Experimental agora há pouco — {nome}{quando}*\n\n"
        "Manda a devolutiva enquanto está fresco: o comercial usa ela pra falar "
        "com a família ainda hoje. É rápido — grava o áudio e confirma. 🎤"
    )


def run_experimental_lembrete(channel: str, dry_run: bool = False) -> Dict[str, Any]:
    spec = EVENTS["experimental_lembrete"]
    alvos = (rpc("fn_experimental_lembrete_alvos", {"p_minutos": 20}) or {}).get("linhas") or []
    resultados = []
    for linha in alvos:
        pid = linha.get("professor_id")
        vinculo = linha.get("vinculo_id")
        if not pid or not vinculo:
            continue
        corpo = format_lembrete_experimental(linha)
        if dry_run:
            resultados.append({"vinculo_id": vinculo, "status": "dry_run_ready"})
            continue
        claim = rpc("fabio_claim_notificacao_por_referencia", {
            "p_professor_id": int(pid),
            "p_tipo": spec.tipo,
            "p_categoria": spec.categoria,
            "p_canal": channel,
            "p_corpo": corpo,
            "p_referencia_tipo": REFERENCIA_TIPO_EXPERIMENTAL,
            "p_referencia_id": str(vinculo),
            "p_titulo": "Experimental sem devolutiva",
            "p_lease_minutos": 10,
        }) or {}
        if not claim.get("claimed"):
            resultados.append({"vinculo_id": vinculo, "status": "ja_avisado"})
            continue
        notificacao_id = claim.get("notificacao_id")
        lease_token = claim.get("lease_token")
        try:
            deliver(pid, channel, corpo)
            # O claim POR REFERENCIA escreve lease_token; mark_sent SEM token
            # nao casa com nenhum lado da cerca (018) e a notificacao fica
            # presa em 'processando' com a mensagem ja entregue.
            if not mark_sent(notificacao_id, lease_token):
                log("notificacao_enviada_mas_nao_fechada",
                    notificacao_id=str(notificacao_id), professor_id=pid)
                resultados.append({"vinculo_id": vinculo, "status": "entregue_mas_nao_fechada"})
                continue
            resultados.append({"vinculo_id": vinculo, "status": "enviada"})
        except Exception as exc:
            mark_failed(notificacao_id, str(exc), lease_token)
            resultados.append({"vinculo_id": vinculo, "status": "falhou", "erro": str(exc)[:200]})
    return {"ok": True, "alvos": len(alvos), "resultados": resultados}
```

Adicionar `"experimental_lembrete"` à lista `choices` do argumento `--event` (~linha 1742) e o despacho em `main()`, junto dos outros eventos.

- [ ] **Step 4: Rodar o teste — verde**

Esperado: `12/12 passaram` (ou o total que sair), `tudo verde`.

- [ ] **Step 5: Matar os mutantes**

Arena isolada na VPS (symlink de tudo, cópia real só do arquivo mutado):

| Mutante | Como | Tem que |
|---|---|---|
| M1: trava desligada | `REFERENCIA_TIPO_EXPERIMENTAL = "devolutiva"` | MORRER no caso 4 |
| M2: mensagem sem contexto | retirar a frase do comercial | MORRER no caso 2 |
| M3: vaza jargão | trocar `"o lead"` por `f"vinculo {linha['vinculo_id']}"` | MORRER no caso 3 |
| M4 (controle) | sem mutação | PASSAR |

- [ ] **Step 6: Dry-run contra o banco real**

```bash
ssh ... 'cd ~/fabio-chat-bridge && set -a && . ~/.hermes/.env && set +a && python3 -B fabio_notification_worker.py --event experimental_lembrete --channel whatsapp --dry-run'
```

Esperado: `alvos` pequeno e nenhum envio. ⚠️ Dry-run **não prova** a tubulação (CHECK, índice único e UAZAPI só aparecem no envio real) — quem prova é a Task 6.

- [ ] **Step 7: Escrever a unit e o timer**

Criar `vps/fabio/fabio-experimental-lembrete.systemd.txt`:

```ini
# ~/.config/systemd/user/fabio-experimental-lembrete.service
[Unit]
Description=Fábio — lembra o professor da devolutiva logo após a experimental

[Service]
Type=oneshot
WorkingDirectory=/home/fabio/fabio-chat-bridge
EnvironmentFile=/home/fabio/.hermes/.env
ExecStart=/usr/bin/flock -n /tmp/fabio-experimental-lembrete.lock /usr/bin/python3 fabio_notification_worker.py --event experimental_lembrete --channel whatsapp --json

# ~/.config/systemd/user/fabio-experimental-lembrete.timer
[Unit]
Description=Dispara o lembrete da experimental a cada 5 minutos

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
AccuracySec=30s

[Install]
WantedBy=timers.target
```

- [ ] **Step 8: Commit**

```bash
git add vps/fabio/fabio_notification_worker.py vps/fabio/teste_experimental_lembrete.py vps/fabio/fabio-experimental-lembrete.systemd.txt
git commit -m "feat(experimental): lembrete imediato apos a aula experimental"
```

---

### Task 4: Seção carimbada na recobrança

**Files:**
- Modify: `vps/fabio/fabio_notification_worker.py` (`format_pendencias`, ~linha 428)
- Create: `vps/fabio/teste_pendencia_secao_experimental.py`

**Interfaces:**
- Consumes: `fn_experimental_pendencia_do_professor(professor_id)` (Task 2).
- Produces: `format_secao_experimental(linhas: list) -> Optional[str]`, e `format_pendencias` passa a anexar essa seção.

- [ ] **Step 1: Escrever o teste primeiro**

Criar `vps/fabio/teste_pendencia_secao_experimental.py`:

```python
#!/usr/bin/env python3
"""Teste da secao carimbada da experimental dentro da cobranca de pendencias.

POR QUE ELE EXISTE. O Alf pediu UMA mensagem com lead e aluno SEPARADOS —
"pra nao misturar". Duas mensagens no mesmo horario viram ruido e ele ignora
as duas; misturar sem carimbo apaga a diferenca entre lead e aluno, que e
exatamente o que ele nao quer.

Rodar:  python3 teste_pendencia_secao_experimental.py
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fabio_notification_worker import format_secao_experimental  # noqa: E402

falhas: list[str] = []
total = 0


def checar(nome, esperado, obtido):
    global total
    total += 1
    if esperado != obtido:
        falhas.append(f"{nome}\n    esperado: {esperado!r}\n    obtido:   {obtido!r}")


LINHAS = [{"vinculo_id": 2275, "nome_aluno": "Davi Nakashima",
           "curso_nome": "Aula Experimental", "unidade_nome": "Barra",
           "quando": "21/08 18:00", "dias_em_atraso": 1}]

texto = format_secao_experimental(LINHAS)

checar("1. tem cabecalho proprio de experimental", True, "Experimentais" in texto)
checar("2. cita o lead pelo nome", True, "Davi" in texto)
checar("3. diz que o comercial espera (a urgencia e comercial)", True,
       "comercial" in texto.lower())

# NEGATIVO: sem pendencia a secao NAO existe — secao vazia polui a mensagem
# do professor que esta em dia e ensina a ignorar o resto.
checar("4. lista vazia devolve None", None, format_secao_experimental([]))
checar("4b. None devolve None", None, format_secao_experimental(None))

# NEGATIVO: a secao NAO pode falar de aula de aluno — e o "nao misturar"
checar("5. nao usa a palavra 'aluno' no cabecalho", False,
       "aluno" in texto.split("\n")[0].lower())

print(f"\n{total - len(falhas)}/{total} passaram")
if falhas:
    print("\nFALHAS:")
    for f in falhas:
        print(f"  x {f}")
    sys.exit(1)
print("tudo verde")
```

- [ ] **Step 2: Rodar e ver falhar**

Esperado: `ImportError: cannot import name 'format_secao_experimental'`.

- [ ] **Step 3: Implementar**

```python
def format_secao_experimental(linhas: Optional[list]) -> Optional[str]:
    """Seção da experimental dentro da mensagem de pendências.

    Carimbada e separada de propósito (pedido do Alf): lead não é aluno, e
    misturar os dois na mesma lista apaga a diferença. Uma mensagem só, duas
    seções — duas mensagens no mesmo horário competiriam por atenção.
    """
    if not linhas:
        return None
    itens = []
    for l in linhas:
        nome = (l.get("nome_aluno") or "lead").split()[0]
        quando = l.get("quando") or ""
        itens.append(f"{nome} ({quando})" if quando else nome)
    plural = "s" if len(itens) > 1 else ""
    return (f"🎓 *Experimentais* — {len(itens)} sem devolutiva: "
            f"{', '.join(itens)} · _o comercial está esperando_")
```

Em `format_pendencias`, após montar a seção de aulas, anexar:

```python
    exp = (rpc("fn_experimental_pendencia_do_professor",
               {"p_professor_id": int(prof.get("professor_id"))}) or {}).get("linhas")
    secao = format_secao_experimental(exp)
    if secao:
        partes.append(secao)
```

(`partes` é a lista de blocos que `format_pendencias` já junta; se o nome local for outro, usar o existente — não renomear.)

- [ ] **Step 4: Rodar o teste — verde**

- [ ] **Step 5: Matar os mutantes**

| Mutante | Como | Tem que |
|---|---|---|
| M1: seção vazia aparece | `if linhas is None: return None` (deixa `[]` montar) | MORRER no caso 4 |
| M2: sem carimbo | trocar `Experimentais` por `Aulas` | MORRER nos casos 1 e 5 |
| M3: sem urgência | remover o trecho do comercial | MORRER no caso 3 |

- [ ] **Step 6: Provar que a mensagem de ALUNO não mudou**

Rodar o evento em dry-run para um professor **sem** pendência de experimental e conferir que o texto é idêntico ao de antes:

```bash
ssh ... 'cd ~/fabio-chat-bridge && set -a && . ~/.hermes/.env && set +a && python3 -B fabio_notification_worker.py --event pendencia --channel whatsapp --dry-run --json' | head -40
```

- [ ] **Step 7: Commit**

```bash
git add vps/fabio/fabio_notification_worker.py vps/fabio/teste_pendencia_secao_experimental.py
git commit -m "feat(experimental): secao carimbada da experimental na cobranca de pendencias"
```

---

### Task 5: Escalonamento com janela própria

**Files:**
- Modify: `vps/fabio/fabio_notification_worker.py` (`format_escalonamento`, ~linha 654; despacho do evento `escalonamento`)
- Create: `vps/fabio/teste_escalonamento_experimental.py`

**Interfaces:**
- Consumes: `fn_experimental_escalonadas()` (Task 2).
- Produces: `format_escalonamento_experimental(linhas: list) -> Optional[str]`.

- [ ] **Step 1: Escrever o teste primeiro**

```python
#!/usr/bin/env python3
"""Teste do escalonamento da experimental para a coordenacao.

POR QUE ELE EXISTE. Escalonamento e a mensagem que chega em quem NAO deu a
aula. Se ela nao disser de quem e a aula, qual unidade e ha quanto tempo, a
coordenacao nao consegue agir e a mensagem vira ruido — e ruido em canal de
coordenacao mata a credibilidade de todo o resto.

Rodar:  python3 teste_escalonamento_experimental.py
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fabio_notification_worker import format_escalonamento_experimental  # noqa: E402

falhas: list[str] = []
total = 0


def checar(nome, esperado, obtido):
    global total
    total += 1
    if esperado != obtido:
        falhas.append(f"{nome}\n    esperado: {esperado!r}\n    obtido:   {obtido!r}")


LINHAS = [{"vinculo_id": 2275, "nome_aluno": "Davi Nakashima",
           "professor_nome": "Isaque Mendes da Silva", "unidade_nome": "Barra",
           "curso_nome": "Aula Experimental", "quando": "13/08 18:00",
           "dias_em_atraso": 3}]

texto = format_escalonamento_experimental(LINHAS)

# quem age precisa dos quatro: quem, onde, quando, quem devia ter feito
checar("1. cita o lead", True, "Davi Nakashima" in texto)
checar("2. cita a unidade", True, "Barra" in texto)
checar("3. cita quando foi a aula", True, "13/08" in texto)
checar("4. cita o professor", True, "Isaque" in texto)
checar("5. diz o custo (o comercial nao recebeu)", True, "comercial" in texto.lower())

checar("6. lista vazia devolve None", None, format_escalonamento_experimental([]))

print(f"\n{total - len(falhas)}/{total} passaram")
if falhas:
    print("\nFALHAS:")
    for f in falhas:
        print(f"  x {f}")
    sys.exit(1)
print("tudo verde")
```

- [ ] **Step 2: Rodar e ver falhar**

- [ ] **Step 3: Implementar**

```python
def format_escalonamento_experimental(linhas: Optional[list]) -> Optional[str]:
    """Bloco da experimental no escalonamento à coordenação.

    Separado do escalonamento de aluno: a janela é de 3 dias
    (fn_janela_experimental_dias), não 7, porque o lead esfria.
    """
    if not linhas:
        return None
    blocos = ["🎓 *Experimentais sem devolutiva*"]
    for l in linhas:
        blocos.append(
            f"• *{l.get('nome_aluno') or 'lead'}* — {l.get('unidade_nome') or '?'}, "
            f"{l.get('quando') or '?'} · prof. {l.get('professor_nome') or '?'} "
            f"· há {l.get('dias_em_atraso')} dia(s)"
        )
    blocos.append("_O comercial não recebeu o retorno dessas experimentais._")
    return "\n".join(blocos)
```

No despacho do evento `escalonamento`, anexar o bloco ao texto do grupo (usar `enviar_grupo(texto, evento="escalonamento")`, que já existe).

- [ ] **Step 4: Rodar o teste — verde**

- [ ] **Step 5: Matar os mutantes**

| Mutante | Como | Tem que |
|---|---|---|
| M1: sem unidade | remover `unidade_nome` do texto | MORRER no caso 2 |
| M2: sem professor | remover `professor_nome` | MORRER no caso 4 |
| M3: vazio vira bloco | `if linhas is None: return None` | MORRER no caso 6 |

- [ ] **Step 6: Commit**

```bash
git add vps/fabio/fabio_notification_worker.py vps/fabio/teste_escalonamento_experimental.py
git commit -m "feat(experimental): escalonamento da experimental com janela propria de 3 dias"
```

---

### Task 6: Rollout — primeiro envio real, depois a chave

**Files:**
- Modify: `vps/fabio/fabio_notification_worker.py` (override de destinatário)
- Modify: `RETOMADA.md`

**Interfaces:**
- Consumes: tudo das Tasks 1-5.
- Produces: variável de ambiente `FABIO_EXPERIMENTAL_DEST_OVERRIDE` (WhatsApp único que recebe TODOS os lembretes de experimental enquanto valer).

- [ ] **Step 1: Implementar o override**

```python
# Passo 2 do rollout: a máquina roda inteira — detecta, monta, grava na fila,
# envia de verdade — mas tudo cai num número só. Existe porque dry-run que
# monta a mensagem e para antes de gravar passa verde e NÃO prova nada: CHECK,
# índice único e resposta da UAZAPI só aparecem no envio real (aconteceu duas
# vezes em 22/08, com erro_tipo e com casado_por). Vazio = envio normal.
EXPERIMENTAL_DEST_OVERRIDE = os.getenv("FABIO_EXPERIMENTAL_DEST_OVERRIDE", "").strip()
```

Em `run_experimental_lembrete`, antes de `deliver`:

```python
        destino = EXPERIMENTAL_DEST_OVERRIDE or None
        if destino:
            deliver_to_number(destino, corpo)   # helper já usado pelo aviso comercial
        else:
            deliver(pid, channel, corpo)
```

(Se o worker não expuser `deliver_to_number`, usar o mesmo caminho que o `fabio_aviso_comercial_worker.py` usa para mandar a número fixo — **não** inventar cliente novo.)

- [ ] **Step 2: Instalar unit e timer na VPS, com override ligado**

```bash
# como fabio, com FABIO_EXPERIMENTAL_DEST_OVERRIDE=<whatsapp do Alf> no ~/.hermes/.env
systemctl --user daemon-reload
systemctl --user enable --now fabio-experimental-lembrete.timer
systemctl --user list-timers fabio-experimental-lembrete.timer --all
```

- [ ] **Step 3: Provar a tubulação com envio real**

Esperar uma experimental terminar (ou conferir com a fila do dia) e verificar:

```sql
select tipo, status, destinatario_whatsapp, referencia_tipo, referencia_id,
       to_char(enviada_em at time zone 'America/Sao_Paulo','DD/MM HH24:MI') as enviada,
       left(coalesce(last_error,''),80) as erro
from fabio_notificacoes
where tipo = 'pendencia_experimental'
order by criado_em desc limit 5;
```

Esperado: `status='enviada'`, destinatário = número do Alf, `referencia_tipo='experimental_vinculo'`.

- [ ] **Step 4: Provar a trava de duplicata NO AR**

Rodar o worker duas vezes seguidas e conferir que a segunda não cria linha nova:

```bash
ssh ... 'cd ~/fabio-chat-bridge && set -a && . ~/.hermes/.env && set +a && for i in 1 2; do python3 -B fabio_notification_worker.py --event experimental_lembrete --channel whatsapp --json; done'
```

Esperado: a segunda rodada devolve `status: "ja_avisado"` para os mesmos vínculos. Se criar linha nova, **parar o timer** e investigar a referência antes de qualquer coisa.

- [ ] **Step 5: Virar a chave**

Remover `FABIO_EXPERIMENTAL_DEST_OVERRIDE` do `~/.hermes/.env`, reiniciar o timer, e acompanhar o primeiro dia:

```sql
select count(*) filter (where status='enviada') as enviadas,
       count(*) filter (where status<>'enviada') as nao_enviadas
from fabio_notificacoes
where tipo='pendencia_experimental' and criado_em > now() - interval '1 day';
```

- [ ] **Step 6: Checkpoint no RETOMADA e commit**

Registrar: o que subiu, o volume do primeiro dia, e o que ficou pendente. Commitar e **push** (commit local é trabalho invisível).

```bash
git add vps/fabio/fabio_notification_worker.py RETOMADA.md
git commit -m "feat(experimental): rollout da cobranca da experimental"
git push origin main
```

---

## Auto-revisão do plano

**Cobertura da spec:** gatilho (Task 1, where do status do lead) · cadência imediata (Task 3) · recobrança (Task 4) · escalonamento 3 dias (Tasks 2 e 5) · professor sem app fora (Task 1) · uma mensagem carimbada (Task 4) · view nova sem tocar a de aluno (Task 1, invariante 1) · data de corte (Task 1) · fecha na confirmação (Task 1) · trava de duplicata (Task 3) · rollout em 3 passos (Task 6). **Sem lacunas.**

**Badge LEAD no app:** a spec cita, mas o app já mostra o carimbo de experimental na agenda (visto em produção). Não há tarefa porque não há mudança a fazer — se na execução descobrir que a tela de pendências não mostra, abrir tarefa própria em vez de embutir aqui.

**Nomes conferidos entre tarefas:** `fn_experimental_lembrete_alvos`, `fn_experimental_pendencia_do_professor`, `fn_experimental_escalonadas`, `format_lembrete_experimental`, `format_secao_experimental`, `format_escalonamento_experimental`, `REFERENCIA_TIPO_EXPERIMENTAL` — usados com a mesma grafia em todas as tarefas.
