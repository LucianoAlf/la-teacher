# Fase 2 — Selo honesto de chamada (source-aware)

**Data:** 2026-07-18
**Status:** design aprovado (aguardando review do spec pelo Alf) → writing-plans

## Motivo (o que o dado provou)

O app decide "chamada feita" com `tem_presenca_registrada = (ap.id is not null)` —
**qualquer** linha de presença conta, inclusive o **default do Emusys**. Ele nunca
olha `respondido_por` (quem marcou).

Medição em prod (últimos 30 dias, aulas já encerradas com roster completo):

| unidade | 🟢 "verde" na tela | falso (só Emusys) | verde honesto |
|---|---|---|---|
| Recreio | 2.015 | 2.011 | 4 |
| Campo Grande | 1.401 | 1.393 | 7 |
| Barra | 850 | 850 | 0 |

De ~4.266 aulas pintadas de "Chamada feita", **~4.254 são fantasma** (só Emusys);
**11** honestas no sistema inteiro. O selo verde é essencialmente fake — o professor
vê "feito" e não age. Isso é a "cegueira operacional" que a análise de retenção já
apontava (CG tem problema de REGISTRO, não de aluno), agora quantificada e localizada
no selo do app.

## Objetivo

O selo de chamada passa a refletir a **fonte** da presença: só é "feita" quando há
presença de **fonte forte** (chamada real), não o default do Emusys. Sem tela nova —
conserta os selos e pendências onde já existem.

## A regra (mesma precedência da Fase 1)

- **Forte** (conta como chamada real): `professor_la_teacher`, `fabio_audio`, `manual`, `professor_whatsapp`.
- **Fraca** (não conta): `emusys`, `sistema`, `null`.

Fonte única da regra: helper imutável no banco, reutilizável por outros consumidores.

```sql
create or replace function public.fn_presenca_e_forte(p_respondido_por text)
returns boolean language sql immutable parallel safe as $$
  select coalesce(p_respondido_por in
    ('professor_la_teacher','fabio_audio','manual','professor_whatsapp'), false)
$$;
```

## Mudanças

### 1. RPC `app_minha_agenda_sessao` (única mudança de backend)

No lateral do roster, os dois sinais que hoje contam "qualquer presença" passam a
contar **só forte**:

- **Por aluno** — `'tem_presenca_registrada', (ap.id is not null and public.fn_presenca_e_forte(ap.respondido_por))`
  (antes: `ap.id is not null`).
- **Por aula** — `count(distinct ap.aluno_id) filter (where public.fn_presenca_e_forte(ap.respondido_por)) as n_registradas`
  (antes: `count(ap.id)`). O `distinct` é **trava defensiva** (Alfredo). Verificado: existe
  `UNIQUE(aluno_id, aula_emusys_id)` e o JOIN casa `ap.aula_emusys_id = ae.id` (não-nulo) → não há
  como inflar; o `distinct` blinda contra regressão futura. (As 102 duplicatas reais do banco são
  linhas legadas com `aula_emusys_id NULL`, que nunca entram nesse JOIN.)

Nada mais no RPC muda. `presenca` (status por aluno) segue vindo de `ap.status_presenca`
(ver "Fora de escopo"). RPC confirmado **app-only** (7 consumidores, todos LA Teacher).

### 2. Cliente (`src/features/agenda/*`) — zero mudança de lógica

`chamadaCompleta` (sessao.ts) já usa `tem_presenca_registrada`; `SessaoRow` já usa
`n_registradas`/`n_alunos`. Com o RPC honesto, os dois ficam honestos **sozinhos**.
Só atualizar os comentários de doc em `AlunoSessao.tem_presenca_registrada` e
`SessaoAula.n_registradas` (api.ts) para "presença de fonte forte — chamada real,
não o default do Emusys".

### 3. Ripple automático (mesmo sinal, sem código novo)

- **Selo da agenda do dia** (SessaoRow): só-Emusys cai de 🟢 "Chamada" para 🟡 "Sem chamada"; parcial vira "N de M" (só fortes).
- **Card "Chamadas pendentes" + alerta de hoje** (Home via `pendencias.ts` → `statusSessao`): pendências reais reaparecem.
- **Contador "X chamadas feitas hoje"** (`contarChamadasFeitas`): passa a contar só as de verdade.
- **Semana compacta** (`useSemana`): lê o mesmo RPC — qualquer estado derivado de `statusSessao` fica honesto junto.

## Fora de escopo (decisão explícita)

- **Display de presença por aluno** (`presenca` = presente/falta/a_confirmar) segue
  vindo do Emusys. Motivo: mantém a **tela de chamada intacta** (ela lê `presenca`
  como pré-preenchimento) — evita efeito colateral. Consequência menor: o subtítulo
  pode mostrar "(faltou)" vindo do Emusys mesmo com selo "Sem chamada". Aceitável;
  se incomodar, vira Fase 2.1 (mostrar 'a_confirmar' para fonte fraca).
- **Sem 1-toque de confirmação** novo — o professor faz a chamada normal (que já
  promove sobre o Emusys). Decidido no brainstorm.
- **View semântica pesada** (`vw_aluno_presenca_semantica_v1`) não é usada — é da
  camada analítica (LA Report), não conhece `fabio_audio`. Reusar a precedência da
  Fase 1 é mais limpo pro selo do app.

## Casos de teste (contra o print real do Matheus, 16/07)

| cenário | fontes | selo esperado |
|---|---|---|
| turma toda forte, presente | prof/manual/fábio | 🟢 "Chamada" |
| turma toda forte, todos falta | forte | 🔴 "Faltaram" |
| turma só Emusys (16h Julia+Marina) | emusys | 🟡 "Sem chamada" |
| mista 1 forte + 1 emusys (18h Anna+Braz) | manual + emusys | 🟡 "1 de 2" |
| sem linha (17h Letícia) | — | 🟡 "Sem chamada" (como hoje) |
| passou 3 dias | qualquer | 🔵 "Encerrada" (não vira pendência — janela protege) |
| contador do dia | — | conta só selos honestos |

## Impacto de dado e rollout

- **Zero migração de dado.** Mudança é de leitura (RPC) + helper novo. Idempotente.
- **Retroativo por natureza:** o histórico "verde" passa a aparecer honesto
  (Encerrada/pendente). É o objetivo — o KPI "chamada feita" era ~99,8% fake. **Não
  inunda** o professor: a janela de 3 dias já joga o passado pra "Encerrada"
  (coordenação); só as recentes viram tarefa acionável.
- **Perceptível:** os números de "chamadas feitas" vão CAIR brutalmente de propósito. Comunicar
  (frase do Alfredo): **"não caiu a operação; caiu a mentira do indicador."**
- **Rollout:** ship direto (mudança de selo, read-only). Sem flag.
- **Aplicação:** Claude Code **escreve** a migration; Alfredo **revisa o SQL completo antes de rodar**
  (`app_minha_agenda_sessao` é sensível). NÃO aplicada pelo Claude Code.

## Arquivos

- `supabase/migrations/012-selo-honesto-presenca.sql` — helper `fn_presenca_e_forte`
  + `create or replace` do `app_minha_agenda_sessao` com os 2 sinais source-aware.
- `src/lib/api.ts` — só comentários de doc (`AlunoSessao.tem_presenca_registrada`, `SessaoAula.n_registradas`).
- (Nenhuma mudança de lógica no cliente.)
