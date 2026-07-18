# Base de presença pra governança da Sol — de onde puxar "alunos sem presença"

_2026-07-18 · handoff Alf → Hugo · **fonte única compartilhada com o Fábio**_

## TL;DR

Use a view **`public.vw_presenca_pendencia`**. Ela responde uma pergunta só:

> "quais alunos ficaram **sem presença real** (chamada de verdade, não o default do Emusys), por aula / unidade / dia?"

É a **mesma fonte** que o Fábio (lado professor) vai ler. Sol e Fábio bebem do mesmo lugar → nunca divergem. Você **não precisa reimplementar "o que é presença"** — a regra já está no banco.

---

## A regra (o coração)

"Presença real" = presença de **fonte forte**. A regra vive numa função única: **`public.fn_presenca_e_forte(respondido_por text) → boolean`**.

- **FORTE** (conta como chamada): `professor_la_teacher`, `fabio_audio`, `manual`, `professor_whatsapp`.
- **FRACA** (NÃO conta): `emusys`, `sistema`, `null` — o default que o Emusys joga pra todo mundo.

> Contexto: medimos que ~4.254 de ~4.266 aulas "verdes" no app eram fantasma (só Emusys). A Fase 2 (selo honesto) passou o app a olhar a fonte; esta view leva a mesma régua pra governança.

A view **já aplica** essa regra + a **regra de ouro**: só aula **encerrada** (`data_hora_fim < now()`), **roster conciliado** (aluno_id not null), **janela operacional de 45 dias**, e **âncora do slot** (turma, ou individual sem turma-irmã) pra não contar a mesma presença 2×.

---

## Colunas da view

| coluna | o que é |
|---|---|
| `unidade_id`, `unidade_nome` | pra rotear pro grupo certo |
| `professor_id`, `professor_nome` | dono / contexto |
| `aula_id`, `tipo`, `curso_nome`, `turma_nome`, `hora` | contexto da aula |
| `data_aula`, `data_hora_inicio`, `data_hora_fim` | quando |
| `aluno_id`, `aluno_nome`, `aluno_primeiro_nome` | quem ficou sem presença |
| `justificada` | `true` = falta já justificada pela coordenação (dá pra excluir da cobrança) |
| `dias_em_atraso` | dias desde a aula (pra escala 3+ dias → coordenação) |

**Grão** = 1 linha por `(aula, aluno)` sem presença forte. Você agrega como precisar.

---

## Query pronta — Sol, "sem presença ontem por unidade" (o cron diário)

```sql
select unidade_nome,
       count(distinct aluno_id)               as alunos,
       count(distinct aula_id)                as aulas,
       jsonb_agg(distinct aluno_primeiro_nome) as nomes
from public.vw_presenca_pendencia
where data_aula = current_date - 1
  and not justificada
group by unidade_nome
order by alunos desc;
```

**Referência real (17/07/2026):** Recreio 71 alunos / 64 aulas · Campo Grande 42 / 34 · Barra 39 / 35 (159 linhas). Os números são altos porque a adoção do app "forte" ainda é só piloto — a governança é justamente o que os derrete.

## Query — escala pra coordenação (professor parado 3+ dias)

```sql
select professor_nome, unidade_nome,
       count(distinct aluno_id) as alunos,
       max(dias_em_atraso)      as pior_atraso
from public.vw_presenca_pendencia
where dias_em_atraso >= 3
  and not justificada
group by professor_nome, unidade_nome
order by pior_atraso desc;
```

---

## Onde plugar — **NÃO é um cron do zero**

O motor de alerta **já roda**: cron `alertas-diarios` (11h) → edge function → WhatsApp via `whatsapp-notificacoes` (UAZAPI) + `governanca.agente_grupos`. A Sol já está viva (fila `bi_messages`, `reset-sol-stuck-messages`). O trabalho é **adicionar o gatilho** que:

1. lê `vw_presenca_pendencia` (query da Sol acima);
2. resolve o grupo da unidade em `governanca.agente_grupos`;
3. posta no tom da Sol — seguindo o `docs/contrato-de-alerta-v1.md` (operacional-cordial, digest diário 8h, anti-fadiga, escalonamento respeitoso).

```sql
-- rota unidade → grupo da Sol
select * from governanca.agente_grupos where /* agente = Sol, por unidade */ ;
```

---

## Tabelas-base (proveniência, se precisar cavar)

`aluno_presenca` (a presença) · `aulas_emusys` (aulas, sincronizadas do Emusys pelos crons `sync-presenca-*`) · `aula_alunos_emusys` (roster) · `unidades` · `aluno_presenca_administrativo` (justificadas).

## Notas

- A view é **backend-only** (revogada de `anon`/`authenticated`) — consuma via **`service_role`**.
- Migration da view: `supabase/migrations/013-vw-presenca-pendencia.sql`.
- A regra `fn_presenca_e_forte` veio da Fase 2: `supabase/migrations/012-selo-honesto-presenca.sql`.
- Estratégia e papéis: `docs/presenca-estrategia-e-papeis.md` (os 2 KPIs; a Sol ataca o de **Registro**).
