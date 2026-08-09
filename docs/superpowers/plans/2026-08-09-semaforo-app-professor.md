# Semáforo do aluno no app do professor — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fazer o professor registrar, dentro do app, o coração de cada aluno
(verde/amarelo/vermelho) com três perguntas estruturadas e uma observação livre
opcional — e o Fábio cobrar isso na última semana do mês.

**Architecture:** Três migrations (schema → RPCs → governança), três RPCs
`security definer` que o app consome por wrappers em `api.ts`, uma tela nova em
`src/features/feedback/`, um card na Home e uma edge function de transcrição
que não persiste nada. Grava na tabela que já existe e que o health score já lê
(`aluno_feedback_professor`) — decisão do Alf: *"não cria duas verdades"*.

**Tech Stack:** Postgres/Supabase (migrations + RPCs + pg_cron), React + Vite +
TypeScript + Tailwind (tokens do LA Teacher), Deno (edge function), Node
(harness de teste e mutantes).

**Spec:** `docs/superpowers/specs/2026-08-09-semaforo-app-professor-design.md`

## Global Constraints

- **Fuso:** toda data de "hoje" nasce em BRT via `public.fn_hoje_brt()`. **Nunca**
  `current_date` cru — entre 21h e meia-noite o servidor já está em amanhã (foi o
  que derrubou o teste 018).
- **Toda migration vem com `.test.sql` e `scripts/mutantes-NNN.mjs`.** Âncora
  podre (o trecho procurado não aparece exatamente 1 vez) é **FALHA**, não aviso.
- **Migration tem que ser reaplicável**: a suíte reaplica cada arquivo em
  `BEGIN`/`ROLLBACK`. Use `create or replace`, `drop ... if exists` antes de
  `add constraint`, e `add column if not exists`.
- **`create or replace function` PRESERVA privilégios** — mutante de permissão
  precisa `grant` de propósito, senão sobrevive.
- **`revoke ... from anon` sozinho NÃO fecha a porta de uma função NOVA.**
  Medido neste projeto: `pg_default_acl` de `public` concede EXECUTE a `anon` e
  a `authenticated`, e o Postgres concede a `PUBLIC` — uma função nova nasce com
  `{=X/postgres, anon=X, authenticated=X, …}`. Revogar só de `anon` deixa o
  PUBLIC, e `has_function_privilege('anon', …)` continua `true`. **Use sempre
  `revoke all on function … from public, anon;`** (acrescentando `authenticated`
  quando a função não é do app). As migrations 065–072 usam a forma abreviada e
  hoje negam `anon` — mas só porque suas funções já existiam e o
  `create or replace` preservou o privilégio já apertado. É armadilha para
  função nova, e as da 074 e da 075 são todas novas.
- **Design System:** só componentes e tokens existentes (`docs/frontend-tokens.md`
  e `src/components/ui/`). Não recriar botão, card, rótulo ou badge. Nenhuma cor,
  raio ou sombra do LA Report vem junto.
- **Rótulo de campo do DS:** `text-[11px] font-bold uppercase tracking-[.5px]`.
  **Título de card:** `text-[13px] font-bold uppercase tracking-[.5px]`.
- **Os tokens semânticos são em INGLÊS.** Conferido em `tailwind.config.ts`:
  `success` · `danger` · `warning` · `info` · `brand`, cada um com as variantes
  `-text` e `-soft`, mais `on-brand`; fundo é `bg-app` / `bg-surface` /
  `bg-inset`. **Não existem** `sucesso-text`, `atencao-text`, `perigo-text`,
  `brand-contrast` nem `bg-base` — os nomes em português são os `tom` das
  PROPS de componentes (`<PainelNumero tom="perigo">`), não classes. Classe
  inexistente não quebra o build: some em silêncio, e o semáforo renderiza sem
  cor. Na dúvida, `grep` no `tailwind.config.ts` antes de escrever.
- **Página não estiliza** — compõe. Estilo mora no componente.
- **`observacao` nunca é selecionada** em RPC, view ou edge function que alimente
  devolutiva, relatório do responsável ou qualquer coisa visível à família.
- **Vocabulário do coração:** `verde` · `amarelo` · `vermelho` (a coluna
  `feedback` já existe assim). Não traduzir para `saudavel/atencao/critico`.
- **Valores das perguntas:** `pratica_em_casa` ∈ {`sim`,`as_vezes`,`nao`};
  `evolucao` ∈ {`evoluindo`,`parado`,`regredindo`}; `animo` ∈
  {`animado`,`neutro`,`desanimado`}.
- **"Respondido"** = coração **e** as três perguntas preenchidas. Observação não
  entra na conta.
- **Commit e push** ao fim de cada task. Commit local não sobrevive; o Alfredo
  audita o diff, não o relato.
- Mensagem de commit termina com `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.

## ⚠️ Duas consequências fora do LA Teacher (decisão humana antes da Task 2)

1. **A RLS de `aluno_feedback_professor` hoje é escancarada.** As duas policies
   existentes são `auth.role() = 'authenticated'` sem checagem de dono — ou seja,
   qualquer professor logado leria e escreveria a observação crua de **todos** os
   alunos de **todos** os colegas. Nada vazou porque a tabela tem 0 linhas, mas
   no dia em que a coleta começar isso viola a fronteira que o Alf pediu. A
   Task 2 substitui essas policies por dono-e-coordenação.
2. **Isso afeta o formulário do LA Report** (`FeedbackProfessorPage`), que grava
   direto na tabela pelo cliente. Medido: a tabela tem 0 linhas e o Alf disse que
   o envio é manual e não acontece mais — *"está de enfeite"*.
   **DECIDIDO PELO ALF em 09/08: aplicar direto, sem esperar aviso ao Alfredo.**
   Não pare para pedir confirmação — a decisão já foi tomada com o trade-off na
   mesa. Registre no commit o que mudou, para o diff contar a história.

## File Structure

| Arquivo | Responsabilidade |
|---|---|
| `supabase/migrations/073-o-semaforo-ganha-as-perguntas.sql` | Colunas novas + checks + `fn_hoje_brt` + `fn_competencia_feedback` + `fn_janela_feedback_aberta` |
| `supabase/migrations/073-*.test.sql` | Prova dos checks, da janela e do fuso |
| `scripts/mutantes-073.mjs` | Mutantes da 073 |
| `supabase/migrations/074-a-mesa-do-professor.sql` | As três RPCs + RLS por dono |
| `supabase/migrations/074-*.test.sql` | Guards, dedupe, respondido, arquivado, carteira alheia |
| `scripts/mutantes-074.mjs` | Mutantes da 074 |
| `supabase/migrations/075-o-fabio-cobra-o-semaforo.sql` | Enfileiramento do lembrete + escalonamento + cron |
| `supabase/migrations/075-*.test.sql` | Prova das três datas e da idempotência |
| `scripts/mutantes-075.mjs` | Mutantes da 075 |
| `src/lib/api.ts` (modificar) | Tipos + 3 wrappers + wrapper da transcrição |
| `src/features/feedback/MesaFeedback.tsx` | A lista, os dois blocos, a barrinha |
| `src/features/feedback/CardAlunoFeedback.tsx` | A linha que expande no toque do coração |
| `src/features/feedback/CampoObservacao.tsx` | Textarea + microfone + transcrição |
| `src/features/feedback/CardFeedbackHome.tsx` | O card que sobe na Home na última semana |
| `src/features/feedback/index.ts` | Barrel |
| `src/pages/app/Feedback.tsx` | Página que compõe |
| `src/routes.tsx` (modificar) | Rota `/app/feedback` |
| `src/pages/app/Home.tsx` (modificar) | Monta o `CardFeedbackHome` |
| `src/pages/app/Alunos.tsx` (modificar) | Entrada permanente para a mesa |
| `supabase/functions/transcrever-audio/index.ts` | Áudio → texto, sem persistir |

---

### Task 1: Migration 073 — as colunas e as réguas de data

**Files:**
- Create: `supabase/migrations/073-o-semaforo-ganha-as-perguntas.sql`
- Create: `supabase/migrations/073-o-semaforo-ganha-as-perguntas.test.sql`
- Create: `scripts/mutantes-073.mjs`
- Modify: `package.json` (scripts `teste:073` e `mutantes:073`)

**Interfaces:**
- Consumes: nada.
- Produces: colunas `pratica_em_casa`, `evolucao`, `animo`, `teve_aula_no_mes`,
  `origem`, `atualizado_em` em `public.aluno_feedback_professor`;
  `public.fn_hoje_brt() returns date`;
  `public.fn_competencia_feedback(p_dia date default null) returns date`;
  `public.fn_janela_feedback_aberta(p_dia date default null) returns boolean`.

- [ ] **Step 1: Escrever a migration**

Crie `supabase/migrations/073-o-semaforo-ganha-as-perguntas.sql`:

```sql
-- 073 — o semáforo ganha as perguntas (e as réguas de data)
--
-- POR QUE: `aluno_feedback_professor` existe desde sempre e tem ZERO linhas.
-- `calcular_health_score_aluno` já LÊ essa tabela, com peso configurado — ou
-- seja, o pilar pedagógico do score sempre valeu zero. Esta migration prepara a
-- tabela para a coleta nascer dentro do app do professor.
--
-- DECISÃO DO ALF: grava na tabela que o score já lê. "Não cria duas verdades."
--
-- `origem` NÃO tem default de propósito: um default 'la_teacher' rotularia como
-- nosso qualquer linha vinda do formulário antigo do LA Report. Quem escreve é
-- que declara de onde veio.

alter table public.aluno_feedback_professor
  add column if not exists pratica_em_casa  text,
  add column if not exists evolucao         text,
  add column if not exists animo            text,
  add column if not exists teve_aula_no_mes boolean,
  add column if not exists origem           text,
  add column if not exists atualizado_em    timestamptz not null default now();

-- `drop if exists` antes do `add`: `add constraint` não é idempotente, e a
-- suíte reaplica cada migration. Sem isso o arquivo sai da suíte em silêncio.
alter table public.aluno_feedback_professor
  drop constraint if exists aluno_feedback_pratica_valida;
alter table public.aluno_feedback_professor
  add  constraint aluno_feedback_pratica_valida
       check (pratica_em_casa is null or pratica_em_casa in ('sim','as_vezes','nao'));

alter table public.aluno_feedback_professor
  drop constraint if exists aluno_feedback_evolucao_valida;
alter table public.aluno_feedback_professor
  add  constraint aluno_feedback_evolucao_valida
       check (evolucao is null or evolucao in ('evoluindo','parado','regredindo'));

alter table public.aluno_feedback_professor
  drop constraint if exists aluno_feedback_animo_valido;
alter table public.aluno_feedback_professor
  add  constraint aluno_feedback_animo_valido
       check (animo is null or animo in ('animado','neutro','desanimado'));

alter table public.aluno_feedback_professor
  drop constraint if exists aluno_feedback_cor_valida;
alter table public.aluno_feedback_professor
  add  constraint aluno_feedback_cor_valida
       check (feedback in ('verde','amarelo','vermelho'));

comment on column public.aluno_feedback_professor.teve_aula_no_mes is
  'Snapshot: o professor deu aula pra esse aluno na competência? Gravado e não '
  'calculado depois porque a agenda muda — sem isso ninguém sabe se o coração '
  'veio de observação recente ou de memória.';

-- ─── As réguas de data ──────────────────────────────────────────────────────
-- Tudo que é "hoje" passa por aqui. `current_date` cru é UTC: entre 21h e
-- meia-noite BRT ele já é amanhã, e foi isso que derrubou o teste 018.
create or replace function public.fn_hoje_brt()
returns date language sql stable parallel safe as $$
  select (now() at time zone 'America/Sao_Paulo')::date
$$;

create or replace function public.fn_competencia_feedback(p_dia date default null)
returns date language sql stable parallel safe as $$
  select date_trunc('month', coalesce(p_dia, public.fn_hoje_brt()))::date
$$;

-- Janela = os ÚLTIMOS 7 DIAS do mês. Qualquer janela de 7 dias contém
-- exatamente uma segunda e uma quinta, então os disparos da 075 são
-- não-ambíguos em todo mês, inclusive fevereiro.
create or replace function public.fn_janela_feedback_aberta(p_dia date default null)
returns boolean language sql stable parallel safe as $$
  select with_dia.d >= (date_trunc('month', with_dia.d) + interval '1 month - 7 days')::date
    from (select coalesce(p_dia, public.fn_hoje_brt()) as d) as with_dia
$$;

grant execute on function public.fn_hoje_brt() to authenticated;
grant execute on function public.fn_competencia_feedback(date) to authenticated;
grant execute on function public.fn_janela_feedback_aberta(date) to authenticated;
revoke all on function public.fn_janela_feedback_aberta(date) from anon;
```

- [ ] **Step 2: Escrever o teste**

Crie `supabase/migrations/073-o-semaforo-ganha-as-perguntas.test.sql`:

```sql
-- 073 (teste) — o semáforo ganha as perguntas
--
-- O passo que dá nome à migration é o par "check recusa valor inválido" +
-- "janela abre exatamente nos últimos 7 dias". A âncora do fuso exige que a
-- competência calculada às 22h BRT ainda seja o mês corrente.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

-- ─── Os checks recusam lixo ─────────────────────────────────────────────────
do $$
declare v_erro text := 'nao levantou'; v_aluno int; v_unid uuid; v_prof int;
begin
  select v.aluno_id, v.unidade_id, v.professor_id
    into v_aluno, v_unid, v_prof
    from public.vw_jornada_professor_atual v limit 1;

  insert into _res values ('ancora: ha aluno na jornada pra testar o check',
    'sim', case when v_aluno is null then 'NAO' else 'sim' end);

  begin
    insert into public.aluno_feedback_professor
      (aluno_id, professor_id, unidade_id, competencia, feedback, pratica_em_casa)
    values (v_aluno, v_prof, v_unid, public.fn_competencia_feedback(), 'verde', 'talvez');
  exception when others then v_erro := sqlerrm; end;
  insert into _res values ('check recusa pratica_em_casa invalida', 'sim',
    case when v_erro like '%aluno_feedback_pratica_valida%' then 'sim' else 'NAO — ' || v_erro end);
end $$;

do $$
declare v_erro text := 'nao levantou'; v_aluno int; v_unid uuid; v_prof int;
begin
  select v.aluno_id, v.unidade_id, v.professor_id into v_aluno, v_unid, v_prof
    from public.vw_jornada_professor_atual v limit 1;
  begin
    insert into public.aluno_feedback_professor
      (aluno_id, professor_id, unidade_id, competencia, feedback)
    values (v_aluno, v_prof, v_unid, public.fn_competencia_feedback(), 'roxo');
  exception when others then v_erro := sqlerrm; end;
  insert into _res values ('check recusa cor invalida', 'sim',
    case when v_erro like '%aluno_feedback_cor_valida%' then 'sim' else 'NAO — ' || v_erro end);
end $$;

-- ─── A janela abre nos últimos 7 dias e não antes ───────────────────────────
insert into _res values ('janela FECHADA no dia 24 de agosto', 'false',
  public.fn_janela_feedback_aberta(date '2026-08-24')::text);
insert into _res values ('janela ABERTA no dia 25 de agosto (31-7+1)', 'true',
  public.fn_janela_feedback_aberta(date '2026-08-25')::text);
insert into _res values ('janela ABERTA no ultimo dia do mes', 'true',
  public.fn_janela_feedback_aberta(date '2026-08-31')::text);
insert into _res values ('janela FECHADA no dia 1', 'false',
  public.fn_janela_feedback_aberta(date '2026-09-01')::text);
-- Fevereiro: a régua é relativa ao fim do mês, não a um dia fixo.
insert into _res values ('fevereiro: janela FECHADA em 21/02', 'false',
  public.fn_janela_feedback_aberta(date '2026-02-21')::text);
insert into _res values ('fevereiro: janela ABERTA em 22/02', 'true',
  public.fn_janela_feedback_aberta(date '2026-02-22')::text);

-- ─── Toda janela de 7 dias tem uma segunda e uma quinta ─────────────────────
insert into _res
select 'todo mes de 2026 tem 1 segunda e 1 quinta na janela', 'sim',
  case when count(*) filter (where segs <> 1 or quis <> 1) = 0 then 'sim'
       else 'NAO — ' || count(*) filter (where segs <> 1 or quis <> 1) || ' mes(es)' end
from (
  select m,
         count(*) filter (where extract(isodow from d) = 1) as segs,
         count(*) filter (where extract(isodow from d) = 4) as quis
    from generate_series(date '2026-01-01', date '2026-12-01', interval '1 month') m,
         lateral generate_series(m::date, (m + interval '1 month - 1 day')::date, interval '1 day') d
   where public.fn_janela_feedback_aberta(d::date)
   group by m
) por_mes;

-- ─── O fuso: às 22h BRT a competência ainda é o mês corrente ────────────────
-- Sem isso, no dia 31 às 22h a competência viraria o mês seguinte e o professor
-- perderia o trabalho do mês inteiro.
insert into _res values ('competencia de 31/08 as 22h BRT ainda e agosto', '2026-08-01',
  public.fn_competencia_feedback(date '2026-08-31')::text);
insert into _res values ('fn_hoje_brt e a data BRT, nao a UTC', 'sim',
  case when public.fn_hoje_brt() = (now() at time zone 'America/Sao_Paulo')::date
       then 'sim' else 'NAO' end);

-- ─── Veredito ───────────────────────────────────────────────────────────────
-- Alias `resumo` com `falhas` NUMÉRICO: é o contrato que
-- `scripts/rodar-teste-sql.mjs` exige (`typeof resumo.falhas !== 'number'`) e
-- que os 54 `.test.sql` do repo usam. Um alias diferente faz o harness dizer
-- "não veio resumo estruturado" e reprovar sem explicar.
select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
```

- [ ] **Step 3: Rodar o teste e ver passar**

```bash
npm run teste:073
```
Esperado: `falhas: []`. Se alguma âncora vier `NAO`, o teste não está provando
nada — conserte a âncora antes de seguir.

Antes disso, adicione ao `package.json`, na seção `scripts`:

```json
"teste:073": "node scripts/rodar-teste-sql.mjs supabase/migrations/073-o-semaforo-ganha-as-perguntas.sql supabase/migrations/073-o-semaforo-ganha-as-perguntas.test.sql",
"mutantes:073": "node scripts/mutantes-073.mjs"
```

- [ ] **Step 4: Escrever os mutantes**

Crie `scripts/mutantes-073.mjs`:

```js
// Mutantes da 073 — o semáforo ganha as perguntas.
//
// V2 é o motivo do arquivo existir: a régua da janela em UTC. Ela sobrevive a
// qualquer teste que use `current_date` dos dois lados — foi assim que o 018
// ficou vermelho por três horas por dia sem ninguém entender.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/073-o-semaforo-ganha-as-perguntas.sql'
const TESTE = 'supabase/migrations/073-o-semaforo-ganha-as-perguntas.test.sql'
const TEMP = 'supabase/migrations/_mutante-073.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'V1 — a janela abre 10 dias antes do fim do mes',
    pega: 'passos "janela FECHADA no dia 24" e "fevereiro: FECHADA em 21/02"',
    de: `  select with_dia.d >= (date_trunc('month', with_dia.d) + interval '1 month - 7 days')::date`,
    para: `  select with_dia.d >= (date_trunc('month', with_dia.d) + interval '1 month - 10 days')::date`,
  },
  {
    nome: 'V2 — hoje volta a ser UTC [a armadilha do 018]',
    pega: 'passo "fn_hoje_brt e a data BRT, nao a UTC"',
    de: `  select (now() at time zone 'America/Sao_Paulo')::date`,
    para: `  select current_date`,
  },
  {
    nome: 'V3 — a competencia arredonda pra semana em vez de mes',
    pega: 'passo "competencia de 31/08 as 22h BRT ainda e agosto"',
    de: `  select date_trunc('month', coalesce(p_dia, public.fn_hoje_brt()))::date`,
    para: `  select date_trunc('week', coalesce(p_dia, public.fn_hoje_brt()))::date`,
  },
  {
    nome: 'V4 — o check de pratica_em_casa aceita qualquer coisa',
    pega: 'passo "check recusa pratica_em_casa invalida"',
    de: `       check (pratica_em_casa is null or pratica_em_casa in ('sim','as_vezes','nao'));`,
    para: `       check (true);`,
  },
  {
    nome: 'V5 — o check da cor aceita qualquer coisa',
    pega: 'passo "check recusa cor invalida"',
    de: `       check (feedback in ('verde','amarelo','vermelho'));`,
    para: `       check (true);`,
  },
]

let mortos = 0
let stale = 0

for (const m of MUTANTES) {
  const n = fonte.split(m.de).length - 1
  if (n !== 1) {
    console.log(`STALE  ${m.nome} — ancora aparece ${n} vez(es), esperava 1`)
    stale++
    continue
  }
  writeFileSync(TEMP, fonte.replace(m.de, m.para))
  let passou = true
  try {
    execFileSync('node', ['scripts/rodar-teste-sql.mjs', TEMP, TESTE], { stdio: 'pipe' })
  } catch {
    passou = false
  }
  if (!passou) {
    mortos++
    console.log(`OK     morto: ${m.nome}  (${m.pega})`)
  } else {
    console.log(`FALHA  SOBREVIVEU: ${m.nome}  (${m.pega})`)
  }
}

try { unlinkSync(TEMP) } catch {}
console.log(`\n${mortos}/${MUTANTES.length} mutantes mortos` + (stale ? `  —  ${stale} ANCORA(S) PODRE(S)` : ''))
process.exitCode = mortos === MUTANTES.length && stale === 0 ? 0 : 1
```

- [ ] **Step 5: Rodar os mutantes**

```bash
npm run mutantes:073
```
Esperado: `5/5 mutantes mortos`. Um sobrevivente significa que o teste não
cobre aquele comportamento — escreva o passo que falta e rode de novo. **Não
apague o mutante.**

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/073-o-semaforo-ganha-as-perguntas.sql supabase/migrations/073-o-semaforo-ganha-as-perguntas.test.sql scripts/mutantes-073.mjs package.json && git commit -m "feat(073): o semaforo ganha as tres perguntas e as reguas de data" && git push origin main
```

---

### Task 2: Migration 074 — as três RPCs e a RLS por dono

**Files:**
- Create: `supabase/migrations/074-a-mesa-do-professor.sql`
- Create: `supabase/migrations/074-a-mesa-do-professor.test.sql`
- Create: `scripts/mutantes-074.mjs`
- Modify: `package.json`

**Interfaces:**
- Consumes: `public.fn_hoje_brt()`, `public.fn_competencia_feedback(date)`,
  `public.fn_janela_feedback_aberta(date)` (Task 1); `public.fn_professor_do_usuario()`
  e `public.fn_e_coordenacao_la_teacher()` (já existem).
- Produces:
  - `app_professor_feedback_mesa(p_competencia date default null) returns jsonb`
  - `app_professor_feedback_salvar(p_aluno_id int, p_feedback text, p_pratica_em_casa text default null, p_evolucao text default null, p_animo text default null, p_observacao text default null, p_competencia date default null) returns jsonb`
  - `app_professor_feedback_progresso(p_competencia date default null) returns jsonb`

Forma do JSON da mesa:
```json
{ "competencia": "2026-08-01", "janela_aberta": true, "total": 38, "respondidos": 12,
  "alunos": [ { "aluno_id": 812, "nome": "Ana Beatriz", "cursos": "Violão",
    "teve_aula_no_mes": true, "dias_sem_aula": null, "feedback": "verde",
    "pratica_em_casa": "sim", "evolucao": "evoluindo", "animo": "animado",
    "observacao": "…", "completo": true } ] }
```
`salvar` e `progresso` devolvem `{ competencia, total, respondidos, janela_aberta }`.

**Fatos medidos que o implementador precisa saber:**
- A carteira canônica é `public.vw_jornada_professor_atual` filtrada por
  `professor_id`. É de lá que `app_minha_carteira` lê.
- Ela tem **uma linha por matrícula/disciplina**: 1.224 linhas para 1.165 alunos.
  **Sem dedupe a barrinha conta gente duas vezes e nunca fecha.**
- **A coluna de "última aula que aconteceu" é `ultima_aula_registrada`**, não
  `data_ultima_aula`. `data_ultima_aula` é o fim do CONTRATO: 1.191 das 1.224
  linhas estão no futuro, uma delas em 2032. Usar a coluna errada deixa o bloco
  "não viu" vazio pra sempre e faz `dias_sem_aula` vir negativo.
- Hoje o corte dá 911 alunos "viu no mês" × 244 "não viu" × 10 sem registro
  nenhum. A mediana de dias desde a última aula é 5.
- A view só contém `status_matricula = 'ativa'` e hoje nenhum aluno arquivado.

- [ ] **Step 1: Escrever a migration**

Crie `supabase/migrations/074-a-mesa-do-professor.sql`:

```sql
-- 074 — a mesa do professor (o semáforo dentro do app)
--
-- POR QUE: até aqui a percepção do professor não existia como dado. Esta
-- migration abre as três portas: ler a mesa, salvar UM aluno (é o que cada
-- toque chama) e devolver o progresso.
--
-- RLS: as duas policies antigas eram `auth.role() = 'authenticated'` sem
-- checagem de dono — qualquer professor logado leria a observação crua sobre os
-- alunos de qualquer colega. Nada vazou porque a tabela tinha 0 linhas. Aqui
-- elas viram dono-e-coordenação. Isso afeta o formulário do LA Report, que
-- gravava direto pelo cliente; ele está sem uso (0 linhas) e o envio era manual.

-- ─── Leitura da mesa ────────────────────────────────────────────────────────
create or replace function public.app_professor_feedback_mesa(
  p_competencia date default null
) returns jsonb
language plpgsql stable security definer set search_path to 'public'
as $$
declare
  v_prof  integer := public.fn_professor_do_usuario();
  v_comp  date    := public.fn_competencia_feedback(p_competencia);
  v_hoje  date    := public.fn_hoje_brt();
  v_saida jsonb;
begin
  if v_prof is null then
    return jsonb_build_object('erro','sem_professor_vinculado');
  end if;

  with carteira as (
    -- UMA linha por aluno. A carteira tem uma por matrícula/disciplina.
    select v.aluno_id,
           min(v.aluno_nome)                        as aluno_nome,
           (array_agg(v.unidade_id))[1]             as unidade_id,
           string_agg(distinct v.curso_nome, ' · ') as cursos,
           max(v.ultima_aula_registrada)            as ultima_aula
      from public.vw_jornada_professor_atual v
      join public.alunos a on a.id = v.aluno_id
     where v.professor_id = v_prof
       and a.arquivado_em is null
     group by v.aluno_id
  ),
  resp as (
    select f.aluno_id, f.feedback, f.pratica_em_casa, f.evolucao, f.animo,
           f.observacao,
           (f.feedback is not null and f.pratica_em_casa is not null
            and f.evolucao is not null and f.animo is not null) as completo
      from public.aluno_feedback_professor f
     where f.professor_id = v_prof
       and f.competencia  = v_comp
  )
  select jsonb_build_object(
    'competencia',   v_comp,
    'janela_aberta', public.fn_janela_feedback_aberta(v_hoje),
    'total',         count(*),
    'respondidos',   count(*) filter (where coalesce(r.completo, false)),
    'alunos', coalesce(jsonb_agg(jsonb_build_object(
        'aluno_id',         c.aluno_id,
        'nome',             c.aluno_nome,
        'cursos',           c.cursos,
        -- Snapshot do bloco: NULL (nunca teve aula registrada) cai no bloco
        -- "não viu", que é onde ele tem que aparecer.
        'teve_aula_no_mes', coalesce(c.ultima_aula >= v_comp, false),
        'dias_sem_aula',    case when coalesce(c.ultima_aula >= v_comp, false)
                                 then null else v_hoje - c.ultima_aula end,
        'feedback',         r.feedback,
        'pratica_em_casa',  r.pratica_em_casa,
        'evolucao',         r.evolucao,
        'animo',            r.animo,
        'observacao',       r.observacao,
        'completo',         coalesce(r.completo, false))
      order by coalesce(c.ultima_aula >= v_comp, false) desc,
               case when coalesce(c.ultima_aula >= v_comp, false)
                    then c.aluno_nome end asc,
               c.ultima_aula asc nulls first), '[]'::jsonb))
    into v_saida
    from carteira c
    left join resp r on r.aluno_id = c.aluno_id;

  return v_saida;
end $$;

-- ─── Progresso ──────────────────────────────────────────────────────────────
create or replace function public.app_professor_feedback_progresso(
  p_competencia date default null
) returns jsonb
language plpgsql stable security definer set search_path to 'public'
as $$
declare
  v_prof  integer := public.fn_professor_do_usuario();
  v_comp  date    := public.fn_competencia_feedback(p_competencia);
  v_total integer;
  v_ok    integer;
begin
  if v_prof is null then
    return jsonb_build_object('erro','sem_professor_vinculado');
  end if;

  select count(distinct v.aluno_id) into v_total
    from public.vw_jornada_professor_atual v
    join public.alunos a on a.id = v.aluno_id
   where v.professor_id = v_prof and a.arquivado_em is null;

  -- "Respondido" é coração E as três perguntas. Sem isso a barrinha fecharia
  -- 38/38 com a metade das perguntas vazia, e o Fábio pararia de cobrar quem
  -- não terminou. O `exists` impede que aluno que saiu da carteira conte no
  -- numerador e faça respondidos > total.
  select count(*) into v_ok
    from public.aluno_feedback_professor f
   where f.professor_id     = v_prof
     and f.competencia      = v_comp
     and f.feedback         is not null
     and f.pratica_em_casa  is not null
     and f.evolucao         is not null
     and f.animo            is not null
     and exists (select 1
                   from public.vw_jornada_professor_atual v
                   join public.alunos a on a.id = v.aluno_id
                  where v.professor_id = v_prof
                    and v.aluno_id     = f.aluno_id
                    and a.arquivado_em is null);

  return jsonb_build_object(
    'competencia',   v_comp,
    'total',         v_total,
    'respondidos',   v_ok,
    'janela_aberta', public.fn_janela_feedback_aberta(public.fn_hoje_brt()));
end $$;

-- ─── Salvar UM aluno (é o que cada toque chama) ─────────────────────────────
create or replace function public.app_professor_feedback_salvar(
  p_aluno_id        integer,
  p_feedback        text,
  p_pratica_em_casa text default null,
  p_evolucao        text default null,
  p_animo           text default null,
  p_observacao      text default null,
  p_competencia     date default null
) returns jsonb
language plpgsql security definer set search_path to 'public'
as $$
declare
  v_prof    integer := public.fn_professor_do_usuario();
  v_comp    date    := public.fn_competencia_feedback(p_competencia);
  v_unidade uuid;
  v_teve    boolean;
begin
  if v_prof is null then
    raise exception 'sem_professor_vinculado';
  end if;

  -- O professor vem SEMPRE do usuário logado, nunca de parâmetro.
  select (array_agg(v.unidade_id))[1],
         coalesce(max(v.ultima_aula_registrada) >= v_comp, false)
    into v_unidade, v_teve
    from public.vw_jornada_professor_atual v
    join public.alunos a on a.id = v.aluno_id
   where v.professor_id = v_prof
     and v.aluno_id     = p_aluno_id
     and a.arquivado_em is null;

  if v_unidade is null then
    raise exception 'aluno_fora_da_sua_carteira';
  end if;

  insert into public.aluno_feedback_professor
    (aluno_id, professor_id, unidade_id, competencia, feedback,
     pratica_em_casa, evolucao, animo, observacao,
     teve_aula_no_mes, origem, respondido_em, atualizado_em)
  values
    (p_aluno_id, v_prof, v_unidade, v_comp, p_feedback,
     p_pratica_em_casa, p_evolucao, p_animo, nullif(btrim(p_observacao), ''),
     v_teve, 'la_teacher', now(), now())
  on conflict (aluno_id, professor_id, competencia) do update
     set feedback         = excluded.feedback,
         pratica_em_casa  = excluded.pratica_em_casa,
         evolucao         = excluded.evolucao,
         animo            = excluded.animo,
         observacao       = excluded.observacao,
         teve_aula_no_mes = excluded.teve_aula_no_mes,
         atualizado_em    = now();
  -- `origem` e `respondido_em` NÃO entram no update: a primeira resposta é que
  -- data o registro, e reescrever a origem apagaria de onde ele veio.

  return public.app_professor_feedback_progresso(v_comp);
end $$;

-- ─── RLS por dono ───────────────────────────────────────────────────────────
drop policy if exists "Authenticated users can manage feedback"   on public.aluno_feedback_professor;
drop policy if exists "Authenticated users can read all feedback" on public.aluno_feedback_professor;
drop policy if exists feedback_professor_dono                     on public.aluno_feedback_professor;
drop policy if exists feedback_coordenacao_le                     on public.aluno_feedback_professor;

create policy feedback_professor_dono on public.aluno_feedback_professor
  for all to authenticated
  using      (professor_id = public.fn_professor_do_usuario())
  with check (professor_id = public.fn_professor_do_usuario());

create policy feedback_coordenacao_le on public.aluno_feedback_professor
  for select to authenticated
  using (public.fn_e_coordenacao_la_teacher());

-- ─── Portas ─────────────────────────────────────────────────────────────────
grant execute on function public.app_professor_feedback_mesa(date)      to authenticated;
grant execute on function public.app_professor_feedback_progresso(date) to authenticated;
grant execute on function public.app_professor_feedback_salvar(integer, text, text, text, text, text, date) to authenticated;
-- `from public, anon`, não só `from anon`: função nova nasce com EXECUTE para
-- PUBLIC (Postgres) e para anon/authenticated (default_acl do Supabase).
-- Revogar só de `anon` deixa o PUBLIC e a porta continua aberta.
revoke all on function public.app_professor_feedback_mesa(date)      from public, anon;
revoke all on function public.app_professor_feedback_progresso(date) from public, anon;
revoke all on function public.app_professor_feedback_salvar(integer, text, text, text, text, text, date) from public, anon;
```

- [ ] **Step 2: Escrever o teste**

Crie `supabase/migrations/074-a-mesa-do-professor.test.sql`:

```sql
-- 074 (teste) — a mesa do professor
--
-- Os passos que dão nome à migration: o DEDUPE (a carteira tem 1.224 linhas
-- para 1.165 alunos — sem dedupe a barrinha nunca fecha), o RESPONDIDO
-- (coração + as três perguntas) e a COLUNA CERTA de última aula
-- (`ultima_aula_registrada`, não `data_ultima_aula`, que é o fim do contrato e
-- está no futuro em 1.191 das 1.224 linhas).
--
-- O aluno arquivado é arquivado DENTRO da transação e some no rollback do
-- harness: fixture em banco compartilhado vaza, transação não.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

-- ─── Guardas ────────────────────────────────────────────────────────────────
do $$
declare v_saida jsonb;
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  v_saida := public.app_professor_feedback_mesa(null);
  insert into _res values ('sem identidade a mesa devolve erro', 'sim',
    case when v_saida ? 'erro' then 'sim' else 'NAO — ' || v_saida::text end);
end $$;

do $$
declare v_erro text := 'nao levantou';
begin
  begin perform public.app_professor_feedback_salvar(1, 'verde');
  exception when others then v_erro := sqlerrm; end;
  insert into _res values ('sem identidade o salvar recusa', 'sim',
    case when v_erro like '%sem_professor_vinculado%' then 'sim' else 'NAO — ' || v_erro end);
end $$;

-- ─── Escolhe um professor com carteira e assume a identidade dele ───────────
create temp table _ctx on commit drop as
  select v.professor_id, u.auth_user_id
    from public.vw_jornada_professor_atual v
    join public.professores p on p.id = v.professor_id
    join public.usuarios u    on u.id = p.usuario_id
   where u.auth_user_id is not null and coalesce(u.ativo, true)
   group by v.professor_id, u.auth_user_id
  having count(distinct v.aluno_id) >= 3
   limit 1;

insert into _res select 'ancora: ha professor com login e 3+ alunos', 'sim',
  case when count(*) = 0 then 'NAO' else 'sim' end from _ctx;

do $$
declare v_uid uuid;
begin
  select auth_user_id into v_uid from _ctx;
  if v_uid is not null then
    perform set_config('request.jwt.claim.sub', v_uid::text, true);
  end if;
end $$;

-- ─── A âncora do dedupe ─────────────────────────────────────────────────────
insert into _res
select 'ancora: esse professor tem aluno com 2 matriculas', 'sim',
  case when count(*) > 0 then 'sim'
       else 'NAO — sem duplicata, o dedupe nao falseia' end
from (select v.aluno_id
        from public.vw_jornada_professor_atual v, _ctx c
       where v.professor_id = c.professor_id
       group by v.aluno_id having count(*) > 1) d;

create temp table _mesa on commit drop as
  select public.app_professor_feedback_mesa(null) as j;

insert into _res
select 'a mesa conta ALUNO, nao matricula', 'sim',
  case when (select (j->>'total')::int from _mesa)
          = (select count(distinct v.aluno_id)::int
               from public.vw_jornada_professor_atual v, _ctx c
              where v.professor_id = c.professor_id)
       then 'sim' else 'NAO — total=' || (select j->>'total' from _mesa) end;

insert into _res
select 'nenhum aluno aparece duas vezes na mesa', 'sim',
  case when count(*) = 0 then 'sim' else 'NAO — ' || count(*) || ' repetido(s)' end
from (select a->>'aluno_id' as id
        from _mesa, lateral jsonb_array_elements(j->'alunos') a
       group by 1 having count(*) > 1) r;

-- ─── A coluna certa de última aula ──────────────────────────────────────────
insert into _res
select 'ancora: data_ultima_aula esta no FUTURO (e a coluna errada)', 'sim',
  case when count(*) > 0 then 'sim'
       else 'NAO — sem contrato futuro, trocar a coluna nao falseia' end
from public.vw_jornada_professor_atual v, _ctx c
where v.professor_id = c.professor_id
  and v.data_ultima_aula > public.fn_hoje_brt();

insert into _res
select 'ninguem tem dias_sem_aula negativo', 'sim',
  case when count(*) = 0 then 'sim' else 'NAO — ' || count(*) || ' negativo(s)' end
from _mesa, lateral jsonb_array_elements(j->'alunos') a
where (a->>'dias_sem_aula') is not null and (a->>'dias_sem_aula')::int < 0;

insert into _res
select 'quem tem aula no mes esta no bloco "viu"', 'sim',
  case when count(*) = 0 then 'sim' else 'NAO — ' || count(*) || ' fora do bloco' end
from _mesa, lateral jsonb_array_elements(j->'alunos') a
join (select v.aluno_id, max(v.ultima_aula_registrada) as ult
        from public.vw_jornada_professor_atual v, _ctx c
       where v.professor_id = c.professor_id group by v.aluno_id) u
  on u.aluno_id = (a->>'aluno_id')::int
where (u.ult >= public.fn_competencia_feedback())
  and (a->>'teve_aula_no_mes')::boolean is false;

-- ─── Salvar: só a própria carteira ──────────────────────────────────────────
do $$
declare v_erro text := 'nao levantou'; v_alheio int;
begin
  select v.aluno_id into v_alheio
    from public.vw_jornada_professor_atual v, _ctx c
   where v.professor_id <> c.professor_id limit 1;
  insert into _res values ('ancora: existe aluno de outro professor', 'sim',
    case when v_alheio is null then 'NAO' else 'sim' end);
  begin perform public.app_professor_feedback_salvar(v_alheio, 'verde');
  exception when others then v_erro := sqlerrm; end;
  insert into _res values ('salvar recusa aluno fora da carteira', 'sim',
    case when v_erro like '%aluno_fora_da_sua_carteira%' then 'sim' else 'NAO — ' || v_erro end);
end $$;

-- ─── "Respondido" é coração + as TRÊS perguntas ─────────────────────────────
do $$
declare v_aluno int; v_prog jsonb; v_antes int;
begin
  select (a->>'aluno_id')::int into v_aluno
    from _mesa, lateral jsonb_array_elements(j->'alunos') a limit 1;
  select (j->>'respondidos')::int into v_antes from _mesa;

  v_prog := public.app_professor_feedback_salvar(v_aluno, 'amarelo');
  insert into _res values ('so o coracao NAO conta como respondido',
    v_antes::text, v_prog->>'respondidos');

  v_prog := public.app_professor_feedback_salvar(
    v_aluno, 'amarelo', 'as_vezes', 'parado', 'neutro', 'observacao de teste');
  insert into _res values ('coracao + as 3 perguntas conta como respondido',
    (v_antes + 1)::text, v_prog->>'respondidos');
end $$;

-- ─── Arquivado sai da mesa (arquivado dentro da transação) ──────────────────
do $$
declare v_aluno int; v_total_antes int; v_total_depois int;
begin
  select (j->>'total')::int into v_total_antes from _mesa;
  select (a->>'aluno_id')::int into v_aluno
    from _mesa, lateral jsonb_array_elements(j->'alunos') a limit 1;

  update public.alunos set arquivado_em = now() where id = v_aluno;
  select (public.app_professor_feedback_mesa(null)->>'total')::int into v_total_depois;

  insert into _res values ('arquivar um aluno tira ele do denominador',
    (v_total_antes - 1)::text, v_total_depois::text);

  update public.alunos set arquivado_em = null where id = v_aluno;
end $$;

-- ─── A porta ────────────────────────────────────────────────────────────────
insert into _res
select 'anon NAO executa a mesa', 'sim',
  case when has_function_privilege('anon',
        'public.app_professor_feedback_mesa(date)', 'execute')
       then 'NAO — anon executa' else 'sim' end;

insert into _res
select 'anon NAO executa o salvar', 'sim',
  case when has_function_privilege('anon',
        'public.app_professor_feedback_salvar(integer, text, text, text, text, text, date)', 'execute')
       then 'NAO — anon executa' else 'sim' end;

-- ─── A fronteira: a RLS deixou de ser escancarada ───────────────────────────
insert into _res
select 'nenhuma policy solta por auth.role() sobrou', 'sim',
  case when count(*) = 0 then 'sim' else 'NAO — ' || string_agg(policyname, ', ') end
from pg_policies
where schemaname = 'public' and tablename = 'aluno_feedback_professor'
  and coalesce(qual, '') like '%auth.role()%';

-- ─── Veredito ───────────────────────────────────────────────────────────────
-- Alias `resumo` com `falhas` NUMÉRICO: é o contrato que
-- `scripts/rodar-teste-sql.mjs` exige (`typeof resumo.falhas !== 'number'`) e
-- que os 54 `.test.sql` do repo usam. Um alias diferente faz o harness dizer
-- "não veio resumo estruturado" e reprovar sem explicar.
select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
```

- [ ] **Step 3: Adicionar os scripts e rodar o teste**

Adicione ao `package.json`:
```json
"teste:074": "node scripts/rodar-teste-sql.mjs supabase/migrations/074-a-mesa-do-professor.sql supabase/migrations/074-a-mesa-do-professor.test.sql",
"mutantes:074": "node scripts/mutantes-074.mjs"
```

```bash
npm run teste:074
```
Esperado: `falhas: []`, e **nenhuma âncora com `NAO`**.

- [ ] **Step 4: Escrever os mutantes**

Crie `scripts/mutantes-074.mjs` com o mesmo runner da Task 1 (copie o bloco
`let mortos = 0 … process.exitCode`, trocando `073` por `074`), `ORIGINAL =
'supabase/migrations/074-a-mesa-do-professor.sql'`, `TESTE =
'supabase/migrations/074-a-mesa-do-professor.test.sql'`, `TEMP =
'supabase/migrations/_mutante-074.sql'`, e esta lista:

```js
const MUTANTES = [
  {
    nome: 'V1 — a mesa perde o dedupe e conta matricula [a barrinha nunca fecha]',
    pega: 'passos "a mesa conta ALUNO" e "nenhum aluno aparece duas vezes"',
    de: `     group by v.aluno_id
  ),
  resp as (`,
    para: `     group by v.aluno_id, v.id
  ),
  resp as (`,
  },
  {
    nome: 'V2 — volta a coluna errada de ultima aula (fim do contrato, ate 2032)',
    pega: 'passos "ninguem tem dias_sem_aula negativo" e "quem tem aula no mes..."',
    de: `           max(v.ultima_aula_registrada)            as ultima_aula`,
    para: `           max(v.data_ultima_aula)::date            as ultima_aula`,
  },
  {
    nome: 'V3 — "respondido" volta a ser so o coracao',
    pega: 'passo "so o coracao NAO conta como respondido"',
    de: `     and f.feedback         is not null
     and f.pratica_em_casa  is not null
     and f.evolucao         is not null
     and f.animo            is not null`,
    para: `     and f.feedback         is not null`,
  },
  {
    nome: 'V4 — o salvar aceita aluno de qualquer professor',
    pega: 'passo "salvar recusa aluno fora da carteira"',
    de: `   where v.professor_id = v_prof
     and v.aluno_id     = p_aluno_id
     and a.arquivado_em is null;

  if v_unidade is null then
    raise exception 'aluno_fora_da_sua_carteira';
  end if;`,
    para: `   where v.aluno_id     = p_aluno_id
     and a.arquivado_em is null;

  if v_unidade is null then
    raise exception 'aluno_fora_da_sua_carteira';
  end if;`,
  },
  {
    nome: 'V5 — o denominador volta a contar aluno arquivado',
    pega: 'passo "arquivar um aluno tira ele do denominador"',
    de: `     where v.professor_id = v_prof
       and a.arquivado_em is null
     group by v.aluno_id`,
    para: `     where v.professor_id = v_prof
     group by v.aluno_id`,
  },
  {
    nome: 'V6 — teve_aula_no_mes gravado sempre true',
    pega: 'passo "quem tem aula no mes esta no bloco viu" (via mesa)',
    de: `        'teve_aula_no_mes', coalesce(c.ultima_aula >= v_comp, false),`,
    para: `        'teve_aula_no_mes', true,`,
  },
  {
    nome: 'V7 — a mesa volta a atender sem identidade',
    pega: 'passo "sem identidade a mesa devolve erro"',
    de: `  if v_prof is null then
    return jsonb_build_object('erro','sem_professor_vinculado');
  end if;

  with carteira as (`,
    para: `  if false then
    return jsonb_build_object('erro','sem_professor_vinculado');
  end if;

  with carteira as (`,
  },
  {
    nome: 'V8 — o salvar volta a atender sem identidade',
    pega: 'passo "sem identidade o salvar recusa"',
    de: `  if v_prof is null then
    raise exception 'sem_professor_vinculado';
  end if;`,
    para: `  if false then
    raise exception 'sem_professor_vinculado';
  end if;`,
  },
  {
    nome: 'V9 — a mesa fica aberta pro anon',
    pega: 'passo "anon NAO executa a mesa"',
    de: `revoke all on function public.app_professor_feedback_mesa(date)      from public, anon;`,
    para: `grant execute on function public.app_professor_feedback_mesa(date) to anon;`,
  },
  {
    nome: 'V10 — o salvar fica aberto pro anon',
    pega: 'passo "anon NAO executa o salvar"',
    de: `revoke all on function public.app_professor_feedback_salvar(integer, text, text, text, text, text, date) from public, anon;`,
    para: `grant execute on function public.app_professor_feedback_salvar(integer, text, text, text, text, text, date) to anon;`,
  },
  {
    nome: 'V11 — a RLS escancarada volta [a fronteira do texto cru]',
    pega: 'passo "nenhuma policy solta por auth.role() sobrou"',
    de: `create policy feedback_professor_dono on public.aluno_feedback_professor
  for all to authenticated
  using      (professor_id = public.fn_professor_do_usuario())
  with check (professor_id = public.fn_professor_do_usuario());`,
    para: `create policy feedback_professor_dono on public.aluno_feedback_professor
  for all to authenticated
  using      (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');`,
  },
]
```

- [ ] **Step 5: Rodar os mutantes**

```bash
npm run mutantes:074
```
Esperado: `11/11 mutantes mortos`, zero âncoras podres.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/074-a-mesa-do-professor.sql supabase/migrations/074-a-mesa-do-professor.test.sql scripts/mutantes-074.mjs package.json && git commit -m "feat(074): a mesa do professor e a RLS por dono" && git push origin main
```

- [ ] **Step 7: Aplicar em produção**

O harness só roda em `BEGIN`/`ROLLBACK` — nada do que você testou existe no banco
ainda. As tasks de UI que vêm depois precisam das RPCs vivas, então a 074 é
aplicada aqui, **depois** de teste e mutantes verdes.

Aplique o conteúdo de `supabase/migrations/074-a-mesa-do-professor.sql` no projeto
`ouqwbbermlzqqvtqwlul` com a ferramenta MCP `apply_migration` (carregue o schema
com ToolSearch: `select:mcp__4c04bb52-f946-4fe8-85f6-b01d200f8c20__apply_migration`),
com o nome `074-a-mesa-do-professor`.

Depois **prove ao vivo** que a porta fechou — este é o ponto em que a forma
abreviada do `revoke` engana:

```sql
select has_function_privilege('anon','public.app_professor_feedback_mesa(date)','execute') as anon_mesa,
       has_function_privilege('anon','public.app_professor_feedback_salvar(integer, text, text, text, text, text, date)','execute') as anon_salvar,
       (select proacl::text from pg_proc where oid = 'public.app_professor_feedback_mesa(date)'::regprocedure) as acl_mesa;
```
Esperado: `anon_mesa` e `anon_salvar` em `false`, e o `acl_mesa` **sem** a entrada
`=X/postgres` (que é o PUBLIC). Se `anon` vier `true`, o `revoke` não pegou —
conserte antes de seguir.

---

### Task 3: Os contratos no cliente (`api.ts`)

**Files:**
- Modify: `src/lib/api.ts`

**Interfaces:**
- Consumes: as três RPCs da Task 2.
- Produces: `FeedbackAluno`, `FeedbackMesa`, `FeedbackProgresso`, `CORACOES`,
  `PRATICA`, `EVOLUCAO`, `ANIMO`, `feedbackMesa()`, `feedbackSalvar()`,
  `feedbackProgresso()`.

- [ ] **Step 1: Adicionar tipos e wrappers**

Acrescente a `src/lib/api.ts`, seguindo o estilo dos wrappers vizinhos
(`supabase.rpc`, `if (error) throw error`, cast do retorno):

```ts
/** As três cores do coração. O vocabulário é o da coluna `feedback`. */
export type Coracao = 'verde' | 'amarelo' | 'vermelho'
export type Pratica = 'sim' | 'as_vezes' | 'nao'
export type Evolucao = 'evoluindo' | 'parado' | 'regredindo'
export type Animo = 'animado' | 'neutro' | 'desanimado'

/** Rótulos das opções — a tela não inventa texto. */
export const CORACOES: { valor: Coracao; rotulo: string }[] = [
  { valor: 'verde', rotulo: 'Saudável' },
  { valor: 'amarelo', rotulo: 'Atenção' },
  { valor: 'vermelho', rotulo: 'Crítico' },
]
export const PRATICA: { valor: Pratica; rotulo: string }[] = [
  { valor: 'sim', rotulo: 'sim' },
  { valor: 'as_vezes', rotulo: 'às vezes' },
  { valor: 'nao', rotulo: 'não' },
]
export const EVOLUCAO: { valor: Evolucao; rotulo: string }[] = [
  { valor: 'evoluindo', rotulo: 'evoluindo' },
  { valor: 'parado', rotulo: 'parado' },
  { valor: 'regredindo', rotulo: 'regredindo' },
]
export const ANIMO: { valor: Animo; rotulo: string }[] = [
  { valor: 'animado', rotulo: 'animado' },
  { valor: 'neutro', rotulo: 'neutro' },
  { valor: 'desanimado', rotulo: 'desanimado' },
]

export interface FeedbackAluno {
  aluno_id: number
  nome: string
  cursos: string | null
  teve_aula_no_mes: boolean
  dias_sem_aula: number | null
  feedback: Coracao | null
  pratica_em_casa: Pratica | null
  evolucao: Evolucao | null
  animo: Animo | null
  observacao: string | null
  /** Coração E as três perguntas. É o que a barrinha conta. */
  completo: boolean
}

export interface FeedbackProgresso {
  competencia: string
  total: number
  respondidos: number
  janela_aberta: boolean
}

export interface FeedbackMesa extends FeedbackProgresso {
  alunos: FeedbackAluno[]
}

/** A mesa do mês corrente do professor logado. */
export async function feedbackMesa(): Promise<FeedbackMesa> {
  const { data, error } = await supabase.rpc('app_professor_feedback_mesa', {
    p_competencia: null,
  })
  if (error) throw error
  return data as unknown as FeedbackMesa
}

/**
 * Salva UM aluno. É o que cada toque chama — não existe botão "Salvar".
 * Devolve o progresso pra barrinha não precisar de segunda chamada.
 */
export async function feedbackSalvar(entrada: {
  alunoId: number
  feedback: Coracao
  praticaEmCasa?: Pratica | null
  evolucao?: Evolucao | null
  animo?: Animo | null
  observacao?: string | null
}): Promise<FeedbackProgresso> {
  const { data, error } = await supabase.rpc('app_professor_feedback_salvar', {
    p_aluno_id: entrada.alunoId,
    p_feedback: entrada.feedback,
    p_pratica_em_casa: entrada.praticaEmCasa ?? null,
    p_evolucao: entrada.evolucao ?? null,
    p_animo: entrada.animo ?? null,
    p_observacao: entrada.observacao ?? null,
    p_competencia: null,
  })
  if (error) throw error
  return data as unknown as FeedbackProgresso
}

/** Só os números — alimenta o card da Home sem carregar a mesa inteira. */
export async function feedbackProgresso(): Promise<FeedbackProgresso> {
  const { data, error } = await supabase.rpc('app_professor_feedback_progresso', {
    p_competencia: null,
  })
  if (error) throw error
  return data as unknown as FeedbackProgresso
}
```

- [ ] **Step 2: Verificar que compila**

```bash
npm run build
```
Esperado: build sem erro de tipo. Se `supabase.rpc` reclamar do nome da função,
o `src/types/db.ts` está desatualizado — use o cast `as never` no objeto de
parâmetros, como já é feito em outros wrappers recentes, e deixe um comentário
`// FOLLOW-UP: remover o cast quando db.ts for regenerado`.

- [ ] **Step 3: Commit**

```bash
git add src/lib/api.ts && git commit -m "feat(api): contratos do semaforo do aluno" && git push origin main
```

---

### Task 4: A mesa (tela do professor)

**Files:**
- Create: `src/features/feedback/CardAlunoFeedback.tsx`
- Create: `src/features/feedback/MesaFeedback.tsx`
- Create: `src/features/feedback/index.ts`
- Create: `src/pages/app/Feedback.tsx`
- Modify: `src/routes.tsx`
- Modify: `src/pages/app/Alunos.tsx`

**Interfaces:**
- Consumes: `feedbackMesa()`, `feedbackSalvar()`, `FeedbackMesa`,
  `FeedbackAluno`, `CORACOES`, `PRATICA`, `EVOLUCAO`, `ANIMO` (Task 3).
- Produces: `<MesaFeedback />` (sem props — carrega sozinha),
  `<CardAlunoFeedback aluno onSalvo />`.
- O `CampoObservacao` entra na Task 5; nesta task o campo é um `<textarea>`
  simples com o mesmo placeholder, e a Task 5 o substitui.

- [ ] **Step 1: Escrever o card do aluno**

Crie `src/features/feedback/CardAlunoFeedback.tsx`:

```tsx
import { useState } from 'react'
import { Card } from '../../components/ui'
import {
  feedbackSalvar, CORACOES, PRATICA, EVOLUCAO, ANIMO,
  type FeedbackAluno, type Coracao, type Pratica, type Evolucao, type Animo,
} from '../../lib/api'

/**
 * A linha de um aluno na mesa.
 *
 * Abre no toque do coração — independente da cor — e mostra as três perguntas
 * mais o convite de observação. Cada toque SALVA: não existe botão "Salvar".
 * Com 38 alunos e cinco campos, um botão no fim é convite a perder trabalho.
 *
 * O ✓ só aparece quando o aluno está COMPLETO (coração + as três perguntas).
 * Um card com coração e perguntas vazias fica visivelmente começado — é o que
 * o Fábio vai cobrar.
 */
export function CardAlunoFeedback({
  aluno,
  aoSalvar,
  aoFalhar,
}: {
  aluno: FeedbackAluno
  aoSalvar: (progresso: { total: number; respondidos: number }) => void
  aoFalhar: (mensagem: string) => void
}) {
  const [estado, setEstado] = useState(aluno)
  const [aberto, setAberto] = useState(false)
  const [salvando, setSalvando] = useState(false)

  const completo =
    !!estado.feedback && !!estado.pratica_em_casa && !!estado.evolucao && !!estado.animo

  async function salvar(mudanca: Partial<FeedbackAluno>) {
    const novo = { ...estado, ...mudanca }
    setEstado(novo)
    if (!novo.feedback) return
    setSalvando(true)
    try {
      const p = await feedbackSalvar({
        alunoId: novo.aluno_id,
        feedback: novo.feedback,
        praticaEmCasa: novo.pratica_em_casa,
        evolucao: novo.evolucao,
        animo: novo.animo,
        observacao: novo.observacao,
      })
      aoSalvar({ total: p.total, respondidos: p.respondidos })
    } catch {
      aoFalhar('Não consegui salvar. Toca de novo.')
    } finally {
      setSalvando(false)
    }
  }

  return (
    <Card className="mb-2 p-3.5">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="truncate text-[15px] font-bold text-text-primary">{estado.nome}</p>
          <p className="text-[11.5px] text-text-muted">
            {estado.cursos ?? 'Sem curso'}
            {estado.dias_sem_aula != null ? ` · você não vê há ${estado.dias_sem_aula} dias` : null}
          </p>
        </div>
        {completo ? (
          <i className="fa-solid fa-circle-check text-sucesso-text" aria-label="respondido" />
        ) : salvando ? (
          <i className="fa-solid fa-circle-notch fa-spin text-text-muted" aria-label="salvando" />
        ) : null}
      </div>

      {/* Os três corações. Tocar em qualquer um abre o resto. */}
      <div className="mt-3 flex items-center gap-2">
        {CORACOES.map((c) => (
          <button
            key={c.valor}
            type="button"
            onClick={() => {
              setAberto(true)
              void salvar({ feedback: c.valor as Coracao })
            }}
            aria-pressed={estado.feedback === c.valor}
            className={`flex flex-1 flex-col items-center gap-1 rounded-xl border py-2 transition-colors ${
              estado.feedback === c.valor
                ? 'border-transparent bg-bg-inset'
                : 'border-border-subtle'
            }`}
          >
            <i
              className={`fa-heart text-lg ${
                estado.feedback === c.valor ? 'fa-solid' : 'fa-regular text-text-muted'
              } ${
                estado.feedback === c.valor && c.valor === 'verde' ? 'text-sucesso-text' : ''
              } ${
                estado.feedback === c.valor && c.valor === 'amarelo' ? 'text-atencao-text' : ''
              } ${
                estado.feedback === c.valor && c.valor === 'vermelho' ? 'text-perigo-text' : ''
              }`}
              aria-hidden
            />
            <span className="text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">
              {c.rotulo}
            </span>
          </button>
        ))}
      </div>

      {aberto || estado.feedback ? (
        <div className="mt-3 space-y-3 border-t border-border-subtle pt-3">
          <Pergunta
            rotulo="Pratica em casa?"
            opcoes={PRATICA}
            valor={estado.pratica_em_casa}
            aoEscolher={(v) => void salvar({ pratica_em_casa: v as Pratica })}
          />
          <Pergunta
            rotulo="Está evoluindo?"
            opcoes={EVOLUCAO}
            valor={estado.evolucao}
            aoEscolher={(v) => void salvar({ evolucao: v as Evolucao })}
          />
          <Pergunta
            rotulo="Como está o ânimo?"
            opcoes={ANIMO}
            valor={estado.animo}
            aoEscolher={(v) => void salvar({ animo: v as Animo })}
          />

          <div>
            <span className="mb-1 block text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">
              Observação
            </span>
            <textarea
              rows={2}
              defaultValue={estado.observacao ?? ''}
              onBlur={(e) => void salvar({ observacao: e.target.value })}
              placeholder="Algo que vale a coordenação saber — um elogio, um ponto de melhoria, uma mudança que você notou."
              className="w-full resize-none rounded-lg border border-border-subtle bg-bg-inset px-3 py-2 text-[13px] text-text-primary placeholder:text-text-muted"
            />
          </div>
        </div>
      ) : null}
    </Card>
  )
}

/** Uma pergunta de três chips. O rótulo usa a receita de rótulo do DS. */
function Pergunta({
  rotulo,
  opcoes,
  valor,
  aoEscolher,
}: {
  rotulo: string
  opcoes: { valor: string; rotulo: string }[]
  valor: string | null
  aoEscolher: (v: string) => void
}) {
  return (
    <div>
      <span className="mb-1 block text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">
        {rotulo}
      </span>
      <div className="flex gap-2">
        {opcoes.map((o) => (
          <button
            key={o.valor}
            type="button"
            onClick={() => aoEscolher(o.valor)}
            aria-pressed={valor === o.valor}
            className={`flex-1 rounded-lg border px-2 py-1.5 text-[12.5px] transition-colors ${
              valor === o.valor
                ? 'border-transparent bg-brand text-brand-contrast'
                : 'border-border-subtle text-text-secondary'
            }`}
          >
            {o.rotulo}
          </button>
        ))}
      </div>
    </div>
  )
}
```

- [ ] **Step 2: Escrever a mesa**

Crie `src/features/feedback/MesaFeedback.tsx`:

```tsx
import { useEffect, useState } from 'react'
import { EmptyState, Skeleton, Toast, useToast } from '../../components/ui'
import { CardAlunoFeedback } from './CardAlunoFeedback'
import { feedbackMesa, type FeedbackMesa as Mesa } from '../../lib/api'

/**
 * A mesa do mês.
 *
 * Dois blocos de propósito: quem o professor viu no mês e quem ele NÃO viu.
 * Esconder quem sumiu esconderia justamente o aluno que mais importa — dias
 * desde a última aula é o sinal mais forte do modelo de evasão.
 */
export function MesaFeedback() {
  const { message, visible, show } = useToast()
  const [mesa, setMesa] = useState<Mesa | null>(null)
  const [erro, setErro] = useState(false)
  const [progresso, setProgresso] = useState({ total: 0, respondidos: 0 })

  useEffect(() => {
    feedbackMesa()
      .then((m) => {
        setMesa(m)
        setProgresso({ total: m.total, respondidos: m.respondidos })
      })
      .catch(() => setErro(true))
  }, [])

  if (erro) {
    return (
      <EmptyState
        icon="fa-solid fa-triangle-exclamation"
        title="Não consegui abrir o feedback"
        description="Recarrega a página e tenta de novo."
      />
    )
  }

  if (!mesa) {
    return (
      <div className="space-y-2">
        <Skeleton className="h-6 w-full rounded-lg" />
        <Skeleton className="h-[120px] w-full rounded-lg" />
        <Skeleton className="h-[120px] w-full rounded-lg" />
      </div>
    )
  }

  const viu = mesa.alunos.filter((a) => a.teve_aula_no_mes)
  const naoViu = mesa.alunos.filter((a) => !a.teve_aula_no_mes)
  const pct = progresso.total > 0 ? Math.round((progresso.respondidos / progresso.total) * 100) : 0

  return (
    <>
      {/* A barrinha. Conta aluno COMPLETO — coração e as três perguntas. */}
      <div className="sticky top-0 z-10 -mx-5 mb-4 bg-bg-base px-5 pb-3 pt-1">
        <div className="flex items-center gap-3">
          <div className="h-2 flex-1 overflow-hidden rounded-full bg-bg-inset">
            <div className="h-full bg-brand transition-all" style={{ width: `${pct}%` }} />
          </div>
          <span className="whitespace-nowrap text-[11.5px] text-text-muted">
            {progresso.respondidos}/{progresso.total}
          </span>
        </div>
      </div>

      {mesa.alunos.length === 0 ? (
        <EmptyState
          icon="fa-solid fa-user-group"
          title="Sua carteira está vazia"
          description="Quando você tiver alunos, eles aparecem aqui."
        />
      ) : (
        <>
          {viu.length > 0 ? (
            <Bloco titulo="Você deu aula pra esses" icone="fa-solid fa-chalkboard-user">
              {viu.map((a) => (
                <CardAlunoFeedback
                  key={a.aluno_id}
                  aluno={a}
                  aoSalvar={setProgresso}
                  aoFalhar={show}
                />
              ))}
            </Bloco>
          ) : null}

          {naoViu.length > 0 ? (
            <Bloco titulo="Esses você não viu este mês" icone="fa-solid fa-user-clock">
              {naoViu.map((a) => (
                <CardAlunoFeedback
                  key={a.aluno_id}
                  aluno={a}
                  aoSalvar={setProgresso}
                  aoFalhar={show}
                />
              ))}
            </Bloco>
          ) : null}
        </>
      )}

      <Toast message={message} visible={visible} />
    </>
  )
}

function Bloco({
  titulo,
  icone,
  children,
}: {
  titulo: string
  icone: string
  children: React.ReactNode
}) {
  return (
    <section className="mb-6">
      <span className="mb-3 flex items-center gap-2 text-[13px] font-bold uppercase tracking-[.5px] text-text-secondary">
        <i className={`${icone} text-xs text-brand-text`} aria-hidden />
        {titulo}
      </span>
      {children}
    </section>
  )
}
```

- [ ] **Step 3: Barrel, página e rota**

Crie `src/features/feedback/index.ts`:
```ts
export { MesaFeedback } from './MesaFeedback'
export { CardAlunoFeedback } from './CardAlunoFeedback'
```

Crie `src/pages/app/Feedback.tsx`:
```tsx
import { AppFrame } from './AppFrame'
import { MesaFeedback } from '../../features/feedback'

/** Página que só compõe — estilo mora no componente. */
export default function FeedbackPage() {
  return (
    <AppFrame titulo="Feedback do mês" icone="fa-solid fa-heart-pulse">
      <div className="px-5 pb-5 pt-3">
        <MesaFeedback />
      </div>
    </AppFrame>
  )
}
```

Se `AppFrame` tiver outra assinatura de props, use exatamente a mesma chamada
que `src/pages/app/Alunos.tsx` faz — não invente props novas.

Em `src/routes.tsx`, dentro do bloco `RequireProfessor` (junto de
`{ path: '/app/alunos', … }`), adicione:
```tsx
{ path: '/app/feedback', element: <FeedbackPage /> },
```
com o import no mesmo estilo lazy/estático dos vizinhos.

- [ ] **Step 4: Entrada permanente em Alunos**

Em `src/pages/app/Alunos.tsx`, acima da lista, adicione um link para a mesa
usando o `Card` e a receita de título do DS:

```tsx
<Link to="/app/feedback" className="mb-4 block">
  <Card className="flex items-center gap-3 p-3.5">
    <i className="fa-solid fa-heart-pulse text-brand-text" aria-hidden />
    <span className="flex-1 text-[13px] font-bold uppercase tracking-[.5px] text-text-secondary">
      Feedback do mês
    </span>
    <i className="fa-solid fa-chevron-right text-xs text-text-muted" aria-hidden />
  </Card>
</Link>
```

- [ ] **Step 5: Verificar no navegador**

```bash
npm run build
```
Depois abra o preview e navegue até `/app/feedback` autenticado como professor.
Confira: os dois blocos aparecem; tocar num coração abre as perguntas; o ✓ só
aparece com as três respondidas; a barrinha sobe ao completar um aluno; e
recarregar a página mantém o que foi respondido.

- [ ] **Step 6: Commit**

```bash
git add src/features/feedback src/pages/app/Feedback.tsx src/routes.tsx src/pages/app/Alunos.tsx && git commit -m "feat(feedback): a mesa do semaforo no app do professor" && git push origin main
```

---

### Task 5: Microfone na observação (edge function + campo)

**Files:**
- Create: `supabase/functions/transcrever-audio/index.ts`
- Create: `src/features/feedback/CampoObservacao.tsx`
- Modify: `src/features/feedback/CardAlunoFeedback.tsx` (troca o `<textarea>`)
- Modify: `src/lib/api.ts` (wrapper `transcreverAudio`)

**Interfaces:**
- Consumes: `useRecorder` de `src/features/registro/useRecorder.ts`.
- Produces: `transcreverAudio(blob: Blob): Promise<string>`;
  `<CampoObservacao valor aoMudar />`.

- [ ] **Step 1: Escrever a edge function**

Crie `supabase/functions/transcrever-audio/index.ts`:

```ts
// Áudio → texto, e nada mais.
//
// NÃO PERSISTE NADA de propósito: o dado só nasce quando o professor salva o
// texto que ele revisou. Guardar o áudio criaria uma segunda cópia da
// observação, fora da fronteira que a 074 fechou.

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const LIMITE_BYTES = 8 * 1024 * 1024 // ~2 minutos de webm/opus

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  const auth = req.headers.get('Authorization')
  if (!auth) {
    return new Response(JSON.stringify({ erro: 'sem_token' }), {
      status: 401, headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }

  const form = await req.formData()
  const arquivo = form.get('audio')
  if (!(arquivo instanceof File)) {
    return new Response(JSON.stringify({ erro: 'sem_audio' }), {
      status: 400, headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }
  if (arquivo.size > LIMITE_BYTES) {
    return new Response(JSON.stringify({ erro: 'audio_longo_demais' }), {
      status: 413, headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }

  const envio = new FormData()
  envio.append('file', arquivo, 'observacao.webm')
  envio.append('model', 'whisper-1')
  envio.append('language', 'pt')

  const r = await fetch('https://api.openai.com/v1/audio/transcriptions', {
    method: 'POST',
    headers: { Authorization: `Bearer ${Deno.env.get('OPENAI_API_KEY')}` },
    body: envio,
  })

  if (!r.ok) {
    return new Response(JSON.stringify({ erro: 'transcricao_falhou' }), {
      status: 502, headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }

  const dados = await r.json()
  return new Response(JSON.stringify({ texto: dados.text ?? '' }), {
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })
})
```

- [ ] **Step 2: Publicar a edge function e conferir o segredo**

```bash
npx supabase functions deploy transcrever-audio --project-ref ouqwbbermlzqqvtqwlul
```

Confira que `OPENAI_API_KEY` está nos segredos do projeto:
```bash
npx supabase secrets list --project-ref ouqwbbermlzqqvtqwlul
```
Se não estiver, **pare e avise** — não invente chave nem troque de provedor sem
decisão do Alf.

- [ ] **Step 3: Wrapper no `api.ts`**

```ts
/**
 * Transcreve um áudio curto e devolve o texto pro professor revisar.
 * Nada é guardado: o dado só nasce quando ele salvar o texto.
 */
export async function transcreverAudio(blob: Blob): Promise<string> {
  const form = new FormData()
  form.append('audio', blob, 'observacao.webm')
  const { data, error } = await supabase.functions.invoke('transcrever-audio', {
    body: form,
  })
  if (error) throw error
  return (data as { texto?: string })?.texto ?? ''
}
```

- [ ] **Step 4: Escrever o campo com microfone**

Crie `src/features/feedback/CampoObservacao.tsx`:

```tsx
import { useState } from 'react'
import { useRecorder } from '../registro/useRecorder'
import { transcreverAudio } from '../../lib/api'

/**
 * Observação escrita ou falada.
 *
 * O texto transcrito cai no campo EDITÁVEL — o professor revisa antes de virar
 * dado. Se a transcrição falhar, o campo continua digitável: o microfone é
 * atalho, nunca a única porta.
 */
export function CampoObservacao({
  valor,
  aoConfirmar,
}: {
  valor: string
  aoConfirmar: (texto: string) => void
}) {
  const [texto, setTexto] = useState(valor)
  const [transcrevendo, setTranscrevendo] = useState(false)
  const [aviso, setAviso] = useState<string | null>(null)
  const gravador = useRecorder()

  async function pararEGravar() {
    const blob = await gravador.stop()
    if (!blob) return
    setTranscrevendo(true)
    setAviso(null)
    try {
      const t = await transcreverAudio(blob)
      const novo = texto ? `${texto} ${t}` : t
      setTexto(novo)
      aoConfirmar(novo)
    } catch {
      setAviso('Não consegui transcrever. Pode escrever aí.')
    } finally {
      setTranscrevendo(false)
    }
  }

  return (
    <div>
      <span className="mb-1 block text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">
        Observação
      </span>
      <div className="relative">
        <textarea
          rows={2}
          value={texto}
          onChange={(e) => setTexto(e.target.value)}
          onBlur={() => aoConfirmar(texto)}
          placeholder="Algo que vale a coordenação saber — um elogio, um ponto de melhoria, uma mudança que você notou."
          className="w-full resize-none rounded-lg border border-border-subtle bg-bg-inset px-3 py-2 pr-10 text-[13px] text-text-primary placeholder:text-text-muted"
        />
        <button
          type="button"
          aria-label={gravador.recording ? 'Parar gravação' : 'Gravar observação'}
          onClick={() => (gravador.recording ? void pararEGravar() : void gravador.start())}
          disabled={transcrevendo}
          className="absolute right-2 top-2 rounded-lg p-1.5 text-text-muted"
        >
          <i
            className={
              transcrevendo
                ? 'fa-solid fa-circle-notch fa-spin'
                : gravador.recording
                  ? 'fa-solid fa-stop text-danger-text'
                  : 'fa-solid fa-microphone'
            }
            aria-hidden
          />
        </button>
      </div>
      {transcrevendo ? (
        <p className="mt-1 text-[11.5px] text-text-muted">transcrevendo…</p>
      ) : null}
      {aviso ? <p className="mt-1 text-[11.5px] text-atencao-text">{aviso}</p> : null}
    </div>
  )
}
```

Se a API real de `useRecorder` tiver outros nomes (`iniciar`/`parar`/
`gravando`), use os nomes reais — **leia o arquivo antes**, não adapte de
memória.

- [ ] **Step 5: Trocar o textarea no card**

Em `CardAlunoFeedback.tsx`, substitua o bloco `<div>` da observação por:

```tsx
<CampoObservacao
  valor={estado.observacao ?? ''}
  aoConfirmar={(t) => void salvar({ observacao: t })}
/>
```
e adicione `import { CampoObservacao } from './CampoObservacao'`.

- [ ] **Step 6: Provar com áudio real**

No preview, abra um aluno, grave uma frase curta ("o Pedro está praticando mais
desde que mudou de música") e confira: aparece "transcrevendo…", o texto cai no
campo, dá pra editar, e ao sair do campo o card salva. Depois recarregue a
página e confirme que o texto continua lá.

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/transcrever-audio src/features/feedback/CampoObservacao.tsx src/features/feedback/CardAlunoFeedback.tsx src/lib/api.ts && git commit -m "feat(feedback): microfone na observacao com transcricao editavel" && git push origin main
```

---

### Task 6: O card na Home na última semana

**Files:**
- Create: `src/features/feedback/CardFeedbackHome.tsx`
- Modify: `src/features/feedback/index.ts`
- Modify: `src/pages/app/Home.tsx`

**Interfaces:**
- Consumes: `feedbackProgresso()`, `FeedbackProgresso` (Task 3).
- Produces: `<CardFeedbackHome />` — não recebe props e **não renderiza nada**
  fora da janela ou com o mês fechado.

- [ ] **Step 1: Escrever o card**

Crie `src/features/feedback/CardFeedbackHome.tsx`:

```tsx
import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { Card } from '../../components/ui'
import { feedbackProgresso, type FeedbackProgresso } from '../../lib/api'

/**
 * O card que sobe na Home na última semana do mês.
 *
 * Some sozinho quando o professor fecha 100% — tarefa terminada não fica
 * ocupando a tela inicial. Fora da janela ele não existe; a entrada
 * permanente é dentro de Alunos.
 */
export function CardFeedbackHome() {
  const [p, setP] = useState<FeedbackProgresso | null>(null)

  useEffect(() => {
    feedbackProgresso().then(setP).catch(() => setP(null))
  }, [])

  if (!p || !p.janela_aberta || p.total === 0 || p.respondidos >= p.total) return null

  const pct = Math.round((p.respondidos / p.total) * 100)

  return (
    <Link to="/app/feedback" className="mb-4 block">
      <Card className="p-4">
        <span className="mb-2 flex items-center gap-2 text-[13px] font-bold uppercase tracking-[.5px] text-text-secondary">
          <i className="fa-solid fa-heart-pulse text-xs text-brand-text" aria-hidden />
          Feedback do mês
        </span>
        <p className="mb-3 text-[13px] text-text-secondary">
          Como estão seus alunos? É o que a coordenação usa pra chegar antes da
          evasão — e tem gente perto da renovação.
        </p>
        <div className="flex items-center gap-3">
          <div className="h-2 flex-1 overflow-hidden rounded-full bg-bg-inset">
            <div className="h-full bg-brand transition-all" style={{ width: `${pct}%` }} />
          </div>
          <span className="whitespace-nowrap text-[11.5px] text-text-muted">
            {p.respondidos}/{p.total}
          </span>
        </div>
      </Card>
    </Link>
  )
}
```

- [ ] **Step 2: Montar na Home**

Em `src/features/feedback/index.ts` acrescente:
```ts
export { CardFeedbackHome } from './CardFeedbackHome'
```

Em `src/pages/app/Home.tsx`, importe e monte o card **no topo da coluna de
conteúdo**, antes dos cards existentes. Ele se esconde sozinho, então não
precisa de condicional na página.

- [ ] **Step 3: Provar os dois estados**

O card só aparece dentro da janela. Para ver os dois estados sem esperar o fim
do mês, rode no banco (leitura, sem alterar nada):

```sql
select public.fn_janela_feedback_aberta(public.fn_hoje_brt()) as hoje,
       public.fn_janela_feedback_aberta(date_trunc('month', public.fn_hoje_brt())::date
                                        + interval '1 month - 1 day') as ultimo_dia;
```

Se `hoje` for `false`, confirme no preview que **o card não aparece** — esse é o
comportamento certo. Depois confira o outro estado respondendo todos os alunos
de um professor de teste e vendo o card sumir.

- [ ] **Step 4: Commit**

```bash
git add src/features/feedback/CardFeedbackHome.tsx src/features/feedback/index.ts src/pages/app/Home.tsx && git commit -m "feat(feedback): card na Home na ultima semana do mes" && git push origin main
```

---

### Task 7: Migration 075 — o Fábio cobra o semáforo

**Files:**
- Create: `supabase/migrations/075-o-fabio-cobra-o-semaforo.sql`
- Create: `supabase/migrations/075-o-fabio-cobra-o-semaforo.test.sql`
- Create: `scripts/mutantes-075.mjs`
- Modify: `package.json`

**Interfaces:**
- Consumes: `fn_janela_feedback_aberta(date)`, `fn_competencia_feedback(date)`,
  `fn_hoje_brt()` (Task 1); tabela `public.fabio_notificacoes` (já existe, usada
  pela 066).
- Produces: `public.fn_enfileirar_cobranca_feedback(p_dia date default null)
  returns jsonb`.

**Antes de escrever:** leia `supabase/migrations/066-*.sql` e copie a forma real
do `insert into public.fabio_notificacoes` — colunas, valores de `tipo`, e como
a 066 evita duplicata. **Não invente colunas.** O bloco abaixo usa
`(professor_id, tipo, dia_referencia, mensagem)`; se os nomes reais forem
outros, use os reais e ajuste o teste junto.

- [ ] **Step 1: Escrever a migration**

```sql
-- 075 — o Fábio cobra o semáforo
--
-- POR QUE: coleta sem cobrança já foi testada na prática e deu ZERO resposta.
-- O Alf: "falta de tempo, falta de hábito, falta de governança e cobrança".
-- A escada é a mesma da cobrança de presença (066): lembrete, reforço, e a
-- coordenação no fim.
--
-- Qualquer janela de 7 dias tem exatamente uma segunda e uma quinta, então os
-- dois disparos são não-ambíguos em todo mês, inclusive fevereiro.

create or replace function public.fn_enfileirar_cobranca_feedback(
  p_dia date default null
) returns jsonb
language plpgsql security definer set search_path to 'public'
as $$
declare
  v_dia   date := coalesce(p_dia, public.fn_hoje_brt());
  v_comp  date := public.fn_competencia_feedback(v_dia);
  v_dow   int  := extract(isodow from v_dia);
  v_fase  text;
  v_n     int  := 0;
begin
  -- Dia 1º: a competência que interessa é a do mês que ACABOU.
  if extract(day from v_dia) = 1 then
    v_fase := 'coordenacao';
    v_comp := (date_trunc('month', v_dia) - interval '1 month')::date;
  elsif public.fn_janela_feedback_aberta(v_dia) and v_dow = 1 then
    v_fase := 'lembrete';
  elsif public.fn_janela_feedback_aberta(v_dia) and v_dow = 4 then
    v_fase := 'reforco';
  else
    return jsonb_build_object('fase', 'nenhuma', 'enfileirados', 0);
  end if;

  with alvo as (
    select p.id as professor_id,
           count(distinct v.aluno_id) as total,
           count(distinct f.aluno_id) filter (
             where f.feedback is not null and f.pratica_em_casa is not null
               and f.evolucao is not null and f.animo is not null) as ok
      from public.professores p
      join public.vw_jornada_professor_atual v on v.professor_id = p.id
      join public.alunos a on a.id = v.aluno_id and a.arquivado_em is null
      left join public.aluno_feedback_professor f
             on f.professor_id = p.id and f.aluno_id = v.aluno_id
            and f.competencia  = v_comp
     group by p.id
    having count(distinct v.aluno_id) > 0
  ),
  pendentes as (
    -- 'lembrete' vai pra todo mundo; 'reforco' e 'coordenacao' só pra quem
    -- não fechou. Cobrar quem já fez é o jeito mais rápido de ensinar o
    -- professor a ignorar o Fábio.
    select * from alvo
     where v_fase = 'lembrete' or ok < total
  ),
  gravados as (
    insert into public.fabio_notificacoes
      (professor_id, tipo, dia_referencia, mensagem)
    select pe.professor_id,
           'feedback_' || v_fase,
           v_dia,
           case v_fase
             when 'lembrete' then
               'Semana de feedback dos alunos. Você já respondeu ' || pe.ok ||
               ' de ' || pe.total || '. É com isso que a coordenação chega antes ' ||
               'da evasão — e tem aluno perto da renovação.'
             when 'reforco' then
               'Faltam ' || (pe.total - pe.ok) || ' alunos no seu feedback do mês. ' ||
               'Dá pra fechar em poucos minutos pelo app.'
             else
               'Fechou o mês com ' || pe.ok || ' de ' || pe.total || ' alunos ' ||
               'respondidos no feedback.'
           end
      from pendentes pe
    on conflict do nothing
    returning 1
  )
  select count(*) into v_n from gravados;

  return jsonb_build_object('fase', v_fase, 'competencia', v_comp, 'enfileirados', v_n);
end $$;

revoke all on function public.fn_enfileirar_cobranca_feedback(date) from public, anon, authenticated;

-- Índice único que sustenta o `on conflict do nothing`. Índice e ON CONFLICT
-- são UM contrato: quem mexe num mexe no outro.
create unique index if not exists fabio_notificacoes_feedback_dia_unico
  on public.fabio_notificacoes (professor_id, tipo, dia_referencia)
  where tipo like 'feedback_%';
```

- [ ] **Step 2: Aplicar em produção e só então agendar no cron**

O `cron.schedule` chama `public.fn_enfileirar_cobranca_feedback`, que só existe no
banco depois que a migration for aplicada — agendar antes cria um job que falha
toda madrugada em silêncio.

Aplique `supabase/migrations/075-o-fabio-cobra-o-semaforo.sql` no projeto
`ouqwbbermlzqqvtqwlul` com a ferramenta MCP `apply_migration` (nome:
`075-o-fabio-cobra-o-semaforo`) **depois** de teste e mutantes verdes. Confirme
com:

```sql
select has_function_privilege('anon','public.fn_enfileirar_cobranca_feedback(date)','execute') as anon,
       has_function_privilege('authenticated','public.fn_enfileirar_cobranca_feedback(date)','execute') as autenticado;
```
Esperado: os dois `false`. Só então:

```sql
select cron.schedule(
  'cobranca-feedback-diaria',
  '0 12 * * *',   -- 12:00 UTC = 09:00 BRT
  $$select public.fn_enfileirar_cobranca_feedback(null)$$
);
```

Rode isso **separado**, depois que os testes passarem — não dentro do arquivo de
migration, para a suíte não criar job a cada reaplicação.

- [ ] **Step 3: Escrever o teste**

Crie `supabase/migrations/075-o-fabio-cobra-o-semaforo.test.sql`:

```sql
-- 075 (teste) — o Fábio cobra o semáforo
--
-- O passo que dá nome à migration é a ESCADA: lembrete pra todo mundo, reforço
-- só pra quem não fechou, coordenação no dia 1º olhando o mês que acabou.
-- Fora desses três dias, nada é enfileirado.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

-- Uma segunda, uma quinta e um dia comum DENTRO da janela de agosto/2026
-- (25 a 31). 31/08 é segunda; 27/08 é quinta; 26/08 é quarta.
insert into _res values ('segunda da janela dispara lembrete', 'lembrete',
  public.fn_enfileirar_cobranca_feedback(date '2026-08-31')->>'fase');
insert into _res values ('quinta da janela dispara reforco', 'reforco',
  public.fn_enfileirar_cobranca_feedback(date '2026-08-27')->>'fase');
insert into _res values ('quarta da janela NAO dispara', 'nenhuma',
  public.fn_enfileirar_cobranca_feedback(date '2026-08-26')->>'fase');
insert into _res values ('segunda FORA da janela NAO dispara', 'nenhuma',
  public.fn_enfileirar_cobranca_feedback(date '2026-08-17')->>'fase');
insert into _res values ('dia 1 dispara coordenacao', 'coordenacao',
  public.fn_enfileirar_cobranca_feedback(date '2026-09-01')->>'fase');
insert into _res values ('dia 1 olha a competencia que ACABOU', '2026-08-01',
  public.fn_enfileirar_cobranca_feedback(date '2026-09-01')->>'competencia');

-- ─── O lembrete alcança gente ───────────────────────────────────────────────
insert into _res
select 'ancora: ha professor com carteira', 'sim',
  case when count(*) > 0 then 'sim' else 'NAO' end
from (select v.professor_id from public.vw_jornada_professor_atual v
       group by v.professor_id limit 1) x;

insert into _res values ('lembrete enfileira pelo menos um professor', 'sim',
  case when (public.fn_enfileirar_cobranca_feedback(date '2026-08-31')->>'enfileirados')::int > 0
            or exists (select 1 from public.fabio_notificacoes
                        where tipo = 'feedback_lembrete' and dia_referencia = date '2026-08-31')
       then 'sim' else 'NAO' end);

-- ─── Idempotência: rodar duas vezes não duplica ─────────────────────────────
do $$
declare v_antes int; v_depois int;
begin
  select count(*) into v_antes from public.fabio_notificacoes
   where tipo = 'feedback_lembrete' and dia_referencia = date '2026-08-31';
  perform public.fn_enfileirar_cobranca_feedback(date '2026-08-31');
  select count(*) into v_depois from public.fabio_notificacoes
   where tipo = 'feedback_lembrete' and dia_referencia = date '2026-08-31';
  insert into _res values ('rodar de novo no mesmo dia NAO duplica',
    v_antes::text, v_depois::text);
end $$;

-- ─── A porta ────────────────────────────────────────────────────────────────
insert into _res
select 'anon NAO executa a cobranca', 'sim',
  case when has_function_privilege('anon',
        'public.fn_enfileirar_cobranca_feedback(date)', 'execute')
       then 'NAO — anon executa' else 'sim' end;

insert into _res
select 'authenticated NAO executa a cobranca', 'sim',
  case when has_function_privilege('authenticated',
        'public.fn_enfileirar_cobranca_feedback(date)', 'execute')
       then 'NAO — authenticated executa' else 'sim' end;

-- Alias `resumo` com `falhas` NUMÉRICO: é o contrato que
-- `scripts/rodar-teste-sql.mjs` exige (`typeof resumo.falhas !== 'number'`) e
-- que os 54 `.test.sql` do repo usam. Um alias diferente faz o harness dizer
-- "não veio resumo estruturado" e reprovar sem explicar.
select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
```

- [ ] **Step 4: Rodar o teste**

Adicione ao `package.json`:
```json
"teste:075": "node scripts/rodar-teste-sql.mjs supabase/migrations/075-o-fabio-cobra-o-semaforo.sql supabase/migrations/075-o-fabio-cobra-o-semaforo.test.sql",
"mutantes:075": "node scripts/mutantes-075.mjs"
```

```bash
npm run teste:075
```

- [ ] **Step 5: Escrever os mutantes**

Crie `scripts/mutantes-075.mjs` com o mesmo runner das tasks anteriores
(`ORIGINAL`/`TESTE`/`TEMP` apontando pra 075) e:

```js
const MUTANTES = [
  {
    nome: 'V1 — o reforco volta a cobrar quem JA fechou',
    pega: 'passo do reforco (quem esta completo nao pode receber)',
    de: `     where v_fase = 'lembrete' or ok < total`,
    para: `     where true`,
  },
  {
    nome: 'V2 — o dia 1 olha a competencia ERRADA (o mes que comecou)',
    pega: 'passo "dia 1 olha a competencia que ACABOU"',
    de: `    v_comp := (date_trunc('month', v_dia) - interval '1 month')::date;`,
    para: `    v_comp := date_trunc('month', v_dia)::date;`,
  },
  {
    nome: 'V3 — dispara em qualquer dia da janela, nao so seg e qui',
    pega: 'passo "quarta da janela NAO dispara"',
    de: `  elsif public.fn_janela_feedback_aberta(v_dia) and v_dow = 1 then`,
    para: `  elsif public.fn_janela_feedback_aberta(v_dia) then`,
  },
  {
    nome: 'V4 — dispara fora da janela',
    pega: 'passo "segunda FORA da janela NAO dispara"',
    de: `  elsif public.fn_janela_feedback_aberta(v_dia) and v_dow = 4 then
    v_fase := 'reforco';`,
    para: `  elsif v_dow = 4 then
    v_fase := 'reforco';`,
  },
  {
    nome: 'V5 — some o indice unico e o ON CONFLICT vira decoracao',
    pega: 'passo "rodar de novo no mesmo dia NAO duplica"',
    de: `create unique index if not exists fabio_notificacoes_feedback_dia_unico
  on public.fabio_notificacoes (professor_id, tipo, dia_referencia)
  where tipo like 'feedback_%';`,
    para: `create index if not exists fabio_notificacoes_feedback_dia_unico
  on public.fabio_notificacoes (professor_id, tipo, dia_referencia)
  where tipo like 'feedback_%';`,
  },
  {
    nome: 'V6 — a cobranca fica aberta pro authenticated',
    pega: 'passo "authenticated NAO executa a cobranca"',
    de: `revoke all on function public.fn_enfileirar_cobranca_feedback(date) from public, anon, authenticated;`,
    para: `grant execute on function public.fn_enfileirar_cobranca_feedback(date) to authenticated;`,
  },
]
```

- [ ] **Step 6: Rodar os mutantes e a suíte inteira**

```bash
npm run mutantes:075
```
Esperado: `6/6 mortos`, zero âncoras podres.

```bash
npm run teste:tudo
```
Esperado: verde. Se algum teste antigo quebrar, **não** é ruído — a 074 mexeu na
RLS de uma tabela compartilhada.

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/075-o-fabio-cobra-o-semaforo.sql supabase/migrations/075-o-fabio-cobra-o-semaforo.test.sql scripts/mutantes-075.mjs package.json && git commit -m "feat(075): o Fabio cobra o semaforo na ultima semana do mes" && git push origin main
```

- [ ] **Step 8: Perguntar pro Fábio antes de dizer que está pronto**

Regra da casa: mexeu no Fábio, conversa com ele.

```bash
ssh -i ~/.ssh/id_ed25519_lahq_fabio_claude_code fabio@89.116.73.186 \
  'cd ~/fabio-chat-bridge && set -a && . ~/.hermes/.env && set +a && \
   python3 falar_com_fabio.py "o que voce sabe sobre o feedback mensal dos alunos?" --sem-historico'
```

Confira três coisas: que ele não inventa; que uma pergunta comum continua sendo
respondida sem ruído; e que ele não passa observação crua de professor pra quem
não é coordenação.

---

## Self-review

**Cobertura da spec:** as colunas e os checks estão na Task 1; as três RPCs, o
dedupe, o "respondido" e a fronteira na Task 2; os contratos do cliente na
Task 3; a mesa, os dois blocos, o salvar-a-cada-toque e a entrada permanente em
Alunos na Task 4; o microfone com transcrição editável e o não-persistir na
Task 5; o card da Home na Task 6; a escada do Fábio e o cron na Task 7. As dez
provas obrigatórias da spec viraram mutantes: V1/V4 (carteira alheia e salvar em
nome de outro) e V11 (RLS) na 074; V5 (arquivado) e V3 (respondido) na 074; V1
(janela) na 073; V1 (dedupe) e V6 (`teve_aula_no_mes`) na 074; V1 (reforço em
quem fechou) na 075; V9/V10 (`anon`) na 074.

**Onde o plano é mais frágil, e o implementador precisa ler antes de escrever:**
a forma real de `public.fabio_notificacoes` (Task 7, Step 1) e a API real de
`useRecorder` (Task 5, Step 4). Ambas estão marcadas no corpo da task com
instrução de ler o arquivo em vez de adaptar de memória.

**Consistência de tipos:** `Coracao`/`Pratica`/`Evolucao`/`Animo` da Task 3 são
os mesmos valores dos checks da Task 1 e das colunas gravadas na Task 2;
`FeedbackProgresso` tem as quatro chaves que `salvar` e `progresso` devolvem; o
`CardAlunoFeedback` chama `feedbackSalvar` com exatamente os nomes da Task 3.
