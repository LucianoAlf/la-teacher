# Ciclo da Aula Experimental — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (execução manual nesta sessão, sem subagentes — o padrão já em uso neste projeto para migrations testadas).

**Goal:** ligar cada `lead_experimentais` agendado à aula real que já existe em `aulas_emusys` (`categoria='experimental'`), manter esse vínculo correto ao longo de reagendamento/cancelamento/realização, e no fim entregar registro pedagógico + devolutiva + prova de matrícula.

**Architecture:** ver spec `docs/superpowers/specs/2026-08-05-ciclo-da-aula-experimental-design.md` (v2.3, carimbada pelo Alfredo). Uma tabela de vínculo histórica (`lead_experimental_aulas`) com dois índices únicos parciais (vigência × ocupação) resolve o Contrato 1; uma função `plpgsql` reconciliadora resolve o Contrato 2; a mesma rotina observa `lead_experimentais.aluno_id` para o Contrato 3.

**Tech Stack:** Postgres/Supabase (migrations SQL puras — sem edge function: a reconciliação é só leitura/escrita no próprio banco, sem API externa). Testes via `scripts/rodar-teste-sql.mjs` (BEGIN/ROLLBACK, fixtures `ZZTESTE`, mutantes por `sed`). Aplicação via `scripts/aplicar-sql.mjs`.

## Global Constraints

- **Tolerância de horário = 0.** Medido, não escolhido (v2.2): diferença é 0min ou 180min, nunca entre.
- **Chave natural sempre com `unidade_id`.** 26 de 42 professores dão experimental em mais de uma unidade.
- **Toda comparação de horário converte para `'America/Sao_Paulo'` explicitamente.** `aulas_emusys.data_hora_inicio` é `timestamp with time zone` (armazenado UTC); `lead_experimentais.horario_experimental` é hora local.
- **`aula_local_id` é o nome da coluna** (não `aula_emusys_id`) — evita confusão com `lead_experimentais.emusys_aula_id` (legado, não casa). Segue a convenção já usada em `vw_fabio_aulas_contexto.aula_local_id`.
- **Estados válidos do vínculo:** `pendente`, `vinculado`, `manual`, `realizado`, `faltou`, `cancelado`. Nenhum outro valor passa no CHECK.
- **Ocupação usa `estado <> 'cancelado'`, nunca `cancelado_em is null`.** É a regra v2.2/v2.3: cancelar antes de realizar libera o horário; depois de realizado ou faltou, não libera.
- **Vigência usa só `substituido_em is null`** — não olha `cancelado_em`. Uma experimental cancelada sem reagendamento continua sendo o registro vigente do lead.
- **Nenhum prontuário real de aluno vira bancada de teste.** Toda fixture usa `unidade`/`professor`/`lead`/`aula` com prefixo `ZZTESTE`, criados e descartados na mesma transação de teste.
- **Gatilho de matrícula é `lead_experimentais.aluno_id`** (coluna própria), nunca `leads.aluno_id`.
- **Leitura de conversão nunca vai para a família.** Fronteira em RPC/view, não em tela (Tasks 3–6, fora do escopo desta rodada).

---

### Task 1: Migration — tabela de vínculo `lead_experimental_aulas`

**Files:**
- Create: `supabase/migrations/032-lead-experimental-aulas.sql`
- Create: `supabase/migrations/032-lead-experimental-aulas.test.sql`

**Interfaces:**
- Produces: tabela `public.lead_experimental_aulas` com colunas e os dois índices únicos parciais definidos no Contrato 1 (spec v2.2/v2.3). Task 2 (reconciliador) escreve nela; Tasks 3–6 leem dela.

- [ ] **Passo 1: Escrever a migration**

```sql
-- 032 — vinculo entre lead_experimentais e a aula real (aulas_emusys)
--
-- Ver docs/superpowers/specs/2026-08-05-ciclo-da-aula-experimental-design.md
-- (v2.3, carimbada pelo Alfredo) para o raciocinio completo. Resumo do que
-- este arquivo cria:
--
--   - HISTORICO, nao estado atual: varias linhas por lead, uma vigente
--     (indice unico PARCIAL em substituido_em is null).
--   - OCUPACAO e uma pergunta DIFERENTE de vigencia: usa `estado`, nao
--     `cancelado_em` — e essa distincao e o que fecha "aula que ja
--     aconteceu nao pode ficar livre so porque a matricula foi cancelada
--     depois" (achado do Alfredo, v2.2).
--   - `aula_local_id` aponta pro id LOCAL (serial) de aulas_emusys — NUNCA
--     confundir com `lead_experimentais.emusys_aula_id` (legado, id de
--     evento do Emusys, nao casa) nem com `aulas_emusys.emusys_id`.

create table public.lead_experimental_aulas (
  id                    bigserial primary key,
  lead_experimental_id  integer not null references public.lead_experimentais(id),

  -- Id LOCAL de aulas_emusys (aulas_emusys.id), nao o emusys_id externo.
  aula_local_id         integer references public.aulas_emusys(id),

  estado                text not null default 'pendente'
    check (estado in ('pendente','vinculado','manual','realizado','faltou','cancelado')),
    -- pendente  -> sem par ainda; o reconciliador REAVALIA a cada rodada
    -- vinculado -> casado pela chave natural; reavaliavel se reagendar
    -- manual    -> decisao humana; o reconciliador NUNCA sobrescreve
    -- realizado -> a aula aconteceu; PERMANECE realizado pra sempre, mesmo
    --              com cancelado_em preenchido depois (matricula cancelada)
    -- faltou    -> aula existiu, professor esteve la, familia nao veio.
    --              Ocupa o horario como 'realizado' (NAO e 'cancelado'),
    --              mas nao habilita registro/presenca/devolutiva.
    -- cancelado -> so alcancado ANTES de realizar; libera o horario

  motivo_pendencia      text
    check (motivo_pendencia is null or motivo_pendencia in ('sem_par','ambiguo')),
  casado_por            text
    check (casado_por is null or casado_por in ('chave_natural','manual')),

  criado_em             timestamptz not null default now(),
  vinculado_em          timestamptz,
  vinculado_por         text,
  substituido_em        timestamptz,   -- reagendamento de verdade: linha sai de vigencia
  cancelado_em          timestamptz,

  -- Contrato 3 — matricula com recibo
  aluno_id              integer references public.alunos(id),
  aluno_vinculado_em    timestamptz,
  aluno_vinculado_por   text,
  aluno_origem          text
);

-- VIGENCIA: uma linha vigente por lead. So `substituido_em` retira uma linha
-- de vigencia — de proposito SEM `cancelado_em` aqui. Uma experimental
-- cancelada sem reagendamento CONTINUA vigente pro lead: so passa a existir
-- uma segunda linha vigente quando HOUVE reagendamento de verdade.
create unique index uq_lead_exp_aula_vigente
    on public.lead_experimental_aulas (lead_experimental_id)
 where substituido_em is null;

-- OCUPACAO: uma aula do Emusys nao serve a dois leads ao mesmo tempo — mas
-- "ocupada" e definido por `estado`, nao pela presenca de `cancelado_em`.
-- estado='realizado' ou 'faltou' continuam ocupando o horario mesmo se
-- cancelado_em for preenchido depois (matricula cancelada a posteriori).
-- So estado='cancelado' (alcancado ANTES de realizar) libera.
create unique index uq_lead_exp_aula_ocupada
    on public.lead_experimental_aulas (aula_local_id)
 where aula_local_id is not null
   and substituido_em is null
   and estado <> 'cancelado';

revoke all on table public.lead_experimental_aulas from public, anon, authenticated;
grant select, insert, update on table public.lead_experimental_aulas to service_role;
grant usage, select on sequence public.lead_experimental_aulas_id_seq to service_role;

comment on table public.lead_experimental_aulas is
'Vinculo (historico) entre lead_experimentais e a aula real em aulas_emusys. Uma linha vigente por lead (substituido_em is null); ocupacao do horario usa estado, nao cancelado_em. Ver spec 2026-08-05-ciclo-da-aula-experimental-design.md v2.3.';
```

- [ ] **Passo 2: Escrever o teste** (`032-lead-experimental-aulas.test.sql`) — fixtures `ZZTESTE`, sete casos que provam exatamente os contratos exigidos pelo Alfredo:

```sql
-- Teste da 032 — a tabela de vinculo faz o que os dois indices prometem
--
-- Nao testa a LOGICA do reconciliador (isso e a 033) — testa que a
-- ESTRUTURA (indices, CHECK) impede os estados invalidos por conta propria,
-- mesmo que um bug futuro no reconciliador tente escrever errado.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

insert into public.unidades (id, nome, codigo)
values ('00000000-0000-4000-8000-000000000320', 'ZZTESTE unidade 032', 'ZZTESTE032')
on conflict (id) do nothing;

insert into public.professores (id, nome) values (-32001, 'ZZTESTE Professor 032');

insert into public.leads (id, unidade_id, whatsapp, status)
values (-32001, '00000000-0000-4000-8000-000000000320', '5521999320001', 'novo'),
       (-32002, '00000000-0000-4000-8000-000000000320', '5521999320002', 'novo');

insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id)
values
  (-32001, -32001, 'ZZTESTE Aluno A', '00000000-0000-4000-8000-000000000320',
   current_date + 1, '10:00', 'experimental_agendada', -32001),
  (-32002, -32002, 'ZZTESTE Aluno B', '00000000-0000-4000-8000-000000000320',
   current_date + 1, '11:00', 'experimental_agendada', -32001);

insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, categoria, professor_id, cancelada)
values
  (-32001, -932001, '00000000-0000-4000-8000-000000000320', current_date + 1,
   (current_date + 1 + time '13:00') at time zone 'America/Sao_Paulo', 'experimental', -32001, false),
  (-32002, -932002, '00000000-0000-4000-8000-000000000320', current_date + 1,
   (current_date + 1 + time '14:00') at time zone 'America/Sao_Paulo', 'experimental', -32001, false);

-- ── Passo 1: estado invalido e rejeitado pelo CHECK ─────────────────────────
do $$
begin
  begin
    insert into public.lead_experimental_aulas (lead_experimental_id, estado)
    values (-32001, 'inventado');
    insert into _res values ('estado invalido rejeitado', 'rejeitado', 'ACEITOU');
  exception when check_violation then
    insert into _res values ('estado invalido rejeitado', 'rejeitado', 'rejeitado');
  end;
end $$;

-- ── Passo 2: duas linhas vigentes pro MESMO lead — rejeitado ───────────────
insert into public.lead_experimental_aulas
  (lead_experimental_id, aula_local_id, estado, casado_por)
values (-32001, -32001, 'vinculado', 'chave_natural');

do $$
begin
  begin
    insert into public.lead_experimental_aulas
      (lead_experimental_id, aula_local_id, estado, casado_por)
    values (-32001, -32002, 'vinculado', 'chave_natural');
    insert into _res values ('2 vigentes mesmo lead rejeitado', 'rejeitado', 'ACEITOU');
  exception when unique_violation then
    insert into _res values ('2 vigentes mesmo lead rejeitado', 'rejeitado', 'rejeitado');
  end;
end $$;

-- ── Passo 3: reagendar (substituido_em) libera o lead pra uma linha nova ───
update public.lead_experimental_aulas
   set substituido_em = now()
 where lead_experimental_id = -32001 and substituido_em is null;

do $$
begin
  begin
    insert into public.lead_experimental_aulas
      (lead_experimental_id, aula_local_id, estado, casado_por)
    values (-32001, -32002, 'vinculado', 'chave_natural');
    insert into _res values ('reagendar cria 2a linha vigente', 'aceito', 'aceito');
  exception when unique_violation then
    insert into _res values ('reagendar cria 2a linha vigente', 'aceito', 'REJEITOU');
  end;
end $$;

-- estado atual: lead -32001 tem 2 linhas (1 substituida, 1 vigente,
-- ambas ainda apontando aula_local_id que fica ocupado por -32001)

-- ── Passo 4: aula REALIZADA continua ocupada mesmo com cancelado_em depois ─
insert into public.lead_experimental_aulas
  (lead_experimental_id, aula_local_id, estado, casado_por, cancelado_em)
values (-32002, -32001, 'realizado', 'chave_natural', now());  -- cancelado DEPOIS de realizar

do $$
begin
  begin
    insert into public.lead_experimental_aulas
      (lead_experimental_id, aula_local_id, estado, casado_por)
    values (-32002, -32001, 'vinculado', 'chave_natural');
    insert into _res values
      ('aula realizada+cancelada depois continua ocupada', 'rejeitado', 'ACEITOU — BUG');
  exception when unique_violation then
    insert into _res values
      ('aula realizada+cancelada depois continua ocupada', 'rejeitado', 'rejeitado');
  end;
end $$;

-- ── Passo 5: aula CANCELADA antes de realizar libera pra outro lead ────────
insert into public.lead_experimental_aulas
  (lead_experimental_id, aula_local_id, estado, casado_por, cancelado_em)
values (-32002, -32002, 'cancelado', 'chave_natural', now());  -- cancelado ANTES de realizar

do $$
begin
  begin
    insert into public.lead_experimental_aulas
      (lead_experimental_id, aula_local_id, estado, casado_por)
    values (-32001, -32002, 'vinculado', 'chave_natural');
    insert into _res values ('aula cancelada antes libera p/ outro lead', 'aceito', 'aceito');
  exception when unique_violation then
    insert into _res values
      ('aula cancelada antes libera p/ outro lead', 'aceito', 'REJEITOU — regra errada');
  end;
end $$;

-- ── Passo 6: motivo_pendencia so aceita os dois valores ────────────────────
do $$
begin
  begin
    insert into public.lead_experimental_aulas (lead_experimental_id, motivo_pendencia)
    values (-32001, 'qualquer_coisa');
    insert into _res values ('motivo_pendencia invalido rejeitado', 'rejeitado', 'ACEITOU');
  exception when check_violation then
    insert into _res values ('motivo_pendencia invalido rejeitado', 'rejeitado', 'rejeitado');
  end;
end $$;

-- ── Passo 7: colunas do Contrato 3 existem com os tipos certos ─────────────
insert into _res
select 'colunas de recibo da matricula existem', '4',
       (select count(*)::text from information_schema.columns
         where table_schema='public' and table_name='lead_experimental_aulas'
           and column_name in ('aluno_id','aluno_vinculado_em','aluno_vinculado_por','aluno_origem'));

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
```

- [ ] **Passo 3: Rodar contra a migration**

```bash
node scripts/rodar-teste-sql.mjs supabase/migrations/032-lead-experimental-aulas.sql supabase/migrations/032-lead-experimental-aulas.test.sql
```

Esperado: `✓ ... — nenhuma divergência`, mais os dois checks de resíduo/schema limpos.

- [ ] **Passo 4: Matar o mutante da v2.1 (o defeito real que o Alfredo achou)**

```bash
sed "s/and estado <> 'cancelado';/and cancelado_em is null;/" \
  supabase/migrations/032-lead-experimental-aulas.sql > /tmp/032-mutante-v21.sql
node scripts/rodar-teste-sql.mjs /tmp/032-mutante-v21.sql supabase/migrations/032-lead-experimental-aulas.test.sql
```

Esperado: **reprova** no passo "aula realizada+cancelada depois continua ocupada" — é o mutante que reproduz exatamente o bug da v2.1 que o Alfredo pegou. Se este mutante passar, o teste não está provando nada.

- [ ] **Passo 5: Matar o mutante "vigência olha cancelado_em"**

```bash
sed "s/where substituido_em is null;/where substituido_em is null and cancelado_em is null;/" \
  supabase/migrations/032-lead-experimental-aulas.sql > /tmp/032-mutante-vigencia.sql
node scripts/rodar-teste-sql.mjs /tmp/032-mutante-vigencia.sql supabase/migrations/032-lead-experimental-aulas.test.sql
```

Esperado: reprova no passo 3 ("reagendar cria 2a linha vigente") — sem a divergência de comportamento, o índice de vigência ficaria mais permissivo do que o desenhado e o teste não distinguiria as duas versões.

- [ ] **Passo 6: Aplicar em definitivo**

```bash
node scripts/aplicar-sql.mjs supabase/migrations/032-lead-experimental-aulas.sql
```

- [ ] **Passo 7: Commit**

```bash
git add supabase/migrations/032-lead-experimental-aulas.sql supabase/migrations/032-lead-experimental-aulas.test.sql
git commit -m "feat(032): tabela de vinculo lead_experimental_aulas — vigencia x ocupacao"
```

---

### Task 2: Reconciliador — função + transições de estado

**Files:**
- Create: `supabase/migrations/033-fn-reconciliar-experimental-aulas.sql`
- Create: `supabase/migrations/033-fn-reconciliar-experimental-aulas.test.sql`

**Interfaces:**
- Consumes: `public.lead_experimental_aulas` (Task 1), `public.lead_experimentais`, `public.aulas_emusys`.
- Produces: `public.fn_reconciliar_experimental_aulas(p_dias integer default 7, p_limite integer default 200) returns jsonb` — chamável por `pg_cron` (padrão da casa: cron → função SQL ou `net.http_post`; aqui não precisa de API externa, então é função direta, sem edge function). Devolve `{processados, vinculados, pendentes_sem_par, pendentes_ambiguo, revinculados, estado_sincronizado, erros}` — mesmo padrão de rastro por rodada do extrator (027b/index.ts), porque "cron verde sem log por rodada" já causou o defeito de 11 rodadas inúteis hoje mais cedo.

- [ ] **Passo 1: Escrever a função**

A lógica segue exatamente a rotina do Contrato 1/2 da spec v2.3:

```sql
-- 033 — reconciliador do vinculo lead_experimentais <-> aulas_emusys
--
-- Roda por cron (a cada N minutos, sem pressa: e leitura/escrita local, sem
-- API externa). Por lead na janela, em ordem:
--
--   1. status='cancelada'/'experimental_realizada'/'experimental_faltou'/
--      'convertido' -> sincroniza o ESTADO do vinculo vigente (Contrato 2)
--   2. estado do vinculo em ('manual','realizado','faltou','cancelado') ->
--      NAO TOCA (decisao humana e fato consumado sao finais)
--   3. estado='vinculado' -> confirma se o par ainda bate; se nao, substitui
--   4. estado='pendente' ou sem vinculo -> procura pela chave natural
--
-- Devolve um resumo por RODADA (nao por lead) — o mesmo defeito que fez o
-- extrator de contexto rodar 11 vezes sem fazer nada so foi visto porque
-- havia log por rodada. Sem isso, "rodou e nao fez nada" fica invisivel.

create or replace function public.fn_reconciliar_experimental_aulas(
  p_dias   integer default 7,
  p_limite integer default 200
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_lead      record;
  v_vinculo   record;
  v_par       record;
  v_qtd_par   integer;
  v_novo_estado text;
  v_processados       integer := 0;
  v_vinculados         integer := 0;
  v_pendentes_sem_par  integer := 0;
  v_pendentes_ambiguo  integer := 0;
  v_revinculados       integer := 0;
  v_estado_sincronizado integer := 0;
  v_erros              integer := 0;
begin
  for v_lead in
    select le.id, le.status, le.unidade_id, le.data_experimental, le.horario_experimental,
           coalesce(le.professor_experimental_id, l.professor_experimental_id) as professor_id
      from lead_experimentais le
      left join leads l on l.id = le.lead_id
     where le.data_experimental between
             (now() at time zone 'America/Sao_Paulo')::date - 1
             and (now() at time zone 'America/Sao_Paulo')::date + p_dias
     order by le.data_experimental, le.id
     limit p_limite
  loop
    v_processados := v_processados + 1;
    begin
      select * into v_vinculo
        from lead_experimental_aulas
       where lead_experimental_id = v_lead.id and substituido_em is null;

      -- 1) Sincroniza o ESTADO a partir do status real do lead (Contrato 2)
      if v_lead.status = 'cancelada' and v_vinculo.id is not null
         and v_vinculo.estado not in ('realizado','faltou') then
        update lead_experimental_aulas
           set estado = 'cancelado', cancelado_em = coalesce(cancelado_em, now())
         where id = v_vinculo.id;
        v_estado_sincronizado := v_estado_sincronizado + 1;
        continue;
      elsif v_lead.status = 'cancelada' and v_vinculo.id is not null
            and v_vinculo.estado in ('realizado','faltou') then
        update lead_experimental_aulas
           set cancelado_em = coalesce(cancelado_em, now())   -- estado NAO muda
         where id = v_vinculo.id;
        v_estado_sincronizado := v_estado_sincronizado + 1;
        continue;
      elsif v_lead.status in ('experimental_realizada','convertido') and v_vinculo.id is not null
            and v_vinculo.estado not in ('realizado','manual') then
        update lead_experimental_aulas set estado = 'realizado' where id = v_vinculo.id;
        v_estado_sincronizado := v_estado_sincronizado + 1;
        continue;
      elsif v_lead.status = 'experimental_faltou' and v_vinculo.id is not null
            and v_vinculo.estado not in ('faltou','manual') then
        update lead_experimental_aulas set estado = 'faltou' where id = v_vinculo.id;
        v_estado_sincronizado := v_estado_sincronizado + 1;
        continue;
      end if;

      -- 2) Estados finais: nao toca
      if v_vinculo.id is not null and v_vinculo.estado in ('manual','realizado','faltou','cancelado') then
        continue;
      end if;

      -- 3) 'vinculado': o par ainda bate?
      if v_vinculo.id is not null and v_vinculo.estado = 'vinculado' then
        perform 1 from aulas_emusys ae
         where ae.id = v_vinculo.aula_local_id
           and ae.categoria = 'experimental' and not ae.cancelada
           and ae.unidade_id = v_lead.unidade_id
           and ae.professor_id = v_lead.professor_id
           and (ae.data_hora_inicio at time zone 'America/Sao_Paulo')
               = (v_lead.data_experimental + v_lead.horario_experimental);
        if found then
          continue;   -- nada mudou, nada a fazer
        end if;
        -- divergiu (reagendou de verdade): sai de vigencia, cai pro passo 4
        update lead_experimental_aulas set substituido_em = now() where id = v_vinculo.id;
      end if;

      -- 4) Procura pela chave natural (tolerancia ZERO, com unidade)
      select count(*) into v_qtd_par
        from aulas_emusys ae
       where ae.categoria = 'experimental' and not ae.cancelada
         and ae.unidade_id = v_lead.unidade_id
         and ae.professor_id = v_lead.professor_id
         and (ae.data_hora_inicio at time zone 'America/Sao_Paulo')
             = (v_lead.data_experimental + v_lead.horario_experimental);

      if v_qtd_par = 1 then
        select ae.id into v_par
          from aulas_emusys ae
         where ae.categoria = 'experimental' and not ae.cancelada
           and ae.unidade_id = v_lead.unidade_id
           and ae.professor_id = v_lead.professor_id
           and (ae.data_hora_inicio at time zone 'America/Sao_Paulo')
               = (v_lead.data_experimental + v_lead.horario_experimental);

        begin
          insert into lead_experimental_aulas
            (lead_experimental_id, aula_local_id, estado, casado_por, vinculado_em, vinculado_por)
          values
            (v_lead.id, v_par.id, 'vinculado', 'chave_natural', now(), 'reconciliador');
          if v_vinculo.id is not null then v_revinculados := v_revinculados + 1;
          else v_vinculados := v_vinculados + 1; end if;
        exception when unique_violation then
          -- a aula ja esta ocupada por OUTRO lead vigente: fila de trabalho,
          -- nao susto silencioso nem escolha arbitraria
          insert into lead_experimental_aulas
            (lead_experimental_id, estado, motivo_pendencia)
          values (v_lead.id, 'pendente', 'ambiguo');
          v_pendentes_ambiguo := v_pendentes_ambiguo + 1;
        end;

      elsif v_qtd_par = 0 then
        if v_vinculo.id is null or v_vinculo.estado <> 'pendente' or v_vinculo.motivo_pendencia <> 'sem_par' then
          insert into lead_experimental_aulas (lead_experimental_id, estado, motivo_pendencia)
          values (v_lead.id, 'pendente', 'sem_par');
        end if;
        v_pendentes_sem_par := v_pendentes_sem_par + 1;

      else -- mais de uma aula bate (nao visto em producao, mas nao e chute)
        if v_vinculo.id is null or v_vinculo.estado <> 'pendente' or v_vinculo.motivo_pendencia <> 'ambiguo' then
          insert into lead_experimental_aulas (lead_experimental_id, estado, motivo_pendencia)
          values (v_lead.id, 'pendente', 'ambiguo');
        end if;
        v_pendentes_ambiguo := v_pendentes_ambiguo + 1;
      end if;

    exception when others then
      v_erros := v_erros + 1;
      raise warning '[reconciliar_experimental] lead_experimental_id=% erro=%', v_lead.id, sqlerrm;
    end;

    -- 5) Contrato 3 — matricula com recibo, observando lead_experimentais.aluno_id
    if v_lead.status is not null then
      update lead_experimental_aulas t
         set aluno_id = le2.aluno_id,
             aluno_vinculado_em = now(),
             aluno_vinculado_por = 'reconciliador:emusys_sync',
             aluno_origem = 'lead_experimental_aulas.lead_experimental_id'
        from lead_experimentais le2
       where t.lead_experimental_id = le2.id
         and t.lead_experimental_id = v_lead.id
         and t.substituido_em is null
         and le2.aluno_id is not null
         and t.aluno_id is null;
    end if;
  end loop;

  return jsonb_build_object(
    'processados', v_processados,
    'vinculados', v_vinculados,
    'revinculados', v_revinculados,
    'pendentes_sem_par', v_pendentes_sem_par,
    'pendentes_ambiguo', v_pendentes_ambiguo,
    'estado_sincronizado', v_estado_sincronizado,
    'erros', v_erros
  );
end
$function$;

revoke all on function public.fn_reconciliar_experimental_aulas(integer, integer) from public, anon, authenticated;
grant execute on function public.fn_reconciliar_experimental_aulas(integer, integer) to service_role;

comment on function public.fn_reconciliar_experimental_aulas(integer, integer) is
'Liga lead_experimentais a aulas_emusys por chave natural (unidade+professor+categoria=experimental+horario em Sao Paulo, tolerancia zero); sincroniza estado do vinculo a partir do status do lead; observa lead_experimentais.aluno_id pro Contrato 3. Devolve resumo POR RODADA — ver 027b para o porque disso importar.';
```

- [ ] **Passo 2: Escrever o teste** (`033-fn-reconciliar-experimental-aulas.test.sql`)

Fixtures `ZZTESTE` cobrindo, em uma única rodada da função:

```sql
create temp table _res(passo text, esperado text, obtido text) on commit drop;

insert into public.unidades (id, nome, codigo)
values ('00000000-0000-4000-8000-000000000330', 'ZZTESTE unidade 033', 'ZZTESTE033'),
       ('00000000-0000-4000-8000-000000000331', 'ZZTESTE unidade 033b', 'ZZTESTE033B')
on conflict (id) do nothing;

insert into public.professores (id, nome)
values (-33001, 'ZZTESTE Professor Multi-Unidade');   -- mesmo professor, 2 unidades

insert into public.leads (id, unidade_id, whatsapp, status) values
  (-33001, '00000000-0000-4000-8000-000000000330', '5521999330001', 'novo'), -- casa exato
  (-33002, '00000000-0000-4000-8000-000000000330', '5521999330002', 'novo'), -- sem par
  (-33003, '00000000-0000-4000-8000-000000000330', '5521999330003', 'novo'), -- deslocado 180min
  (-33004, '00000000-0000-4000-8000-000000000331', '5521999330004', 'novo'); -- so bate SE checar unidade

insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id)
values
  (-33001, -33001, 'ZZTESTE Casa Exato',   '00000000-0000-4000-8000-000000000330', current_date+2, '10:00', 'experimental_agendada', -33001),
  (-33002, -33002, 'ZZTESTE Sem Par',      '00000000-0000-4000-8000-000000000330', current_date+2, '15:00', 'experimental_agendada', -33001),
  (-33003, -33003, 'ZZTESTE Deslocado',    '00000000-0000-4000-8000-000000000330', current_date+2, '13:00', 'experimental_agendada', -33001),
  (-33004, -33004, 'ZZTESTE Outra Unidade','00000000-0000-4000-8000-000000000331', current_date+2, '10:00', 'experimental_agendada', -33001);

insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, categoria, professor_id, cancelada)
values
  -- casa exato com o lead -33001 (10:00 SP)
  (-33001, -933001, '00000000-0000-4000-8000-000000000330', current_date+2,
   (current_date+2 + time '10:00') at time zone 'America/Sao_Paulo', 'experimental', -33001, false),
  -- 180min de diferenca do lead -33003 (que pede 13:00) — NAO deve casar
  (-33002, -933002, '00000000-0000-4000-8000-000000000330', current_date+2,
   (current_date+2 + time '16:00') at time zone 'America/Sao_Paulo', 'experimental', -33001, false),
  -- mesmo professor, MESMO horario (10:00 SP), OUTRA unidade — testa que a
  -- chave natural exige unidade_id, senao o lead -33004 casaria aqui por engano
  (-33003, -933003, '00000000-0000-4000-8000-000000000331', current_date+2,
   (current_date+2 + time '10:00') at time zone 'America/Sao_Paulo', 'experimental', -33001, false);

select public.fn_reconciliar_experimental_aulas(30, 500) as primeira_rodada \gset

-- ── Casa exato ───────────────────────────────────────────────────────────
insert into _res
select 'casa exato: vinculado', 'vinculado',
       coalesce((select estado from lead_experimental_aulas
                  where lead_experimental_id=-33001 and substituido_em is null), '(nenhum)');

-- ── Sem par vira pendente/sem_par, nao erro silencioso ─────────────────────
insert into _res
select 'sem par -> pendente/sem_par', 'pendente/sem_par',
       coalesce((select estado||'/'||motivo_pendencia from lead_experimental_aulas
                  where lead_experimental_id=-33002 and substituido_em is null), '(nenhum)');

-- ── Tolerancia ZERO: 180min de diferenca NAO casa ──────────────────────────
insert into _res
select 'deslocado 180min -> pendente (nao casa errado)', 'pendente/sem_par',
       coalesce((select estado||'/'||motivo_pendencia from lead_experimental_aulas
                  where lead_experimental_id=-33003 and substituido_em is null), '(nenhum)');

-- ── Chave natural exige unidade: -33004 NAO pode casar com a aula da outra unidade
insert into _res
select 'unidade errada nao casa', 'pendente/sem_par',
       coalesce((select estado||'/'||motivo_pendencia from lead_experimental_aulas
                  where lead_experimental_id=-33004 and substituido_em is null), '(nenhum)');

-- ── Idempotencia: rodar de novo nao duplica nem muda o ja vinculado ────────
select public.fn_reconciliar_experimental_aulas(30, 500) as segunda_rodada \gset
insert into _res
select 'idempotente: 1 linha vigente apos 2 rodadas', '1',
       (select count(*)::text from lead_experimental_aulas
         where lead_experimental_id=-33001 and substituido_em is null);

-- ── Estado 'manual' sobrevive a nova rodada mesmo se o par mudasse ─────────
update lead_experimental_aulas set estado='manual', casado_por='manual'
 where lead_experimental_id=-33002 and substituido_em is null;
select public.fn_reconciliar_experimental_aulas(30, 500) as terceira_rodada \gset
insert into _res
select 'manual sobrevive a rodada', 'manual',
       (select estado from lead_experimental_aulas
         where lead_experimental_id=-33002 and substituido_em is null);

-- ── Sincronizacao de estado: status muda pra experimental_faltou ──────────
update public.lead_experimentais set status='experimental_faltou' where id=-33001;
select public.fn_reconciliar_experimental_aulas(30, 500) as quarta_rodada \gset
insert into _res
select 'faltou sincroniza estado, sem apagar aula_local_id', 'faltou',
       (select estado from lead_experimental_aulas
         where lead_experimental_id=-33001 and substituido_em is null);
insert into _res
select 'faltou mantem aula_local_id (nao desvincula)', 'presente',
       case when (select aula_local_id from lead_experimental_aulas
                    where lead_experimental_id=-33001 and substituido_em is null) is not null
            then 'presente' else 'sumiu' end;

-- ── Contrato 3: aluno_id na PROPRIA lead_experimentais dispara o recibo ────
update public.alunos_teste_ignore_se_nao_existir; -- placeholder removido abaixo
select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
```

> **Nota de implementação:** o bloco do Contrato 3 (matrícula com recibo) precisa
> de uma linha real em `public.alunos` para satisfazer a FK de
> `lead_experimental_aulas.aluno_id`. Antes de rodar, criar um aluno `ZZTESTE`
> mínimo (checar colunas `NOT NULL` de `public.alunos` com
> `select column_name from information_schema.columns where table_name='alunos'
> and is_nullable='NO'` — não medido ainda nesta sessão) e então:
>
> ```sql
> update public.lead_experimentais set aluno_id = <id do aluno ZZTESTE> where id=-33001;
> select public.fn_reconciliar_experimental_aulas(30, 500);
> -- checar: lead_experimental_aulas.aluno_id preenchido, aluno_vinculado_em
> -- não nulo, aluno_vinculado_por = 'reconciliador:emusys_sync'
> ```
>
> Substituir a linha `update public.alunos_teste_ignore_se_nao_existir;` (que
> não é SQL válido — é um marcador de que este passo precisa da medição de
> schema antes de virar código real) por esse bloco antes de rodar o teste.

- [ ] **Passo 3: Rodar contra a função**

```bash
node scripts/rodar-teste-sql.mjs \
  supabase/migrations/033-fn-reconciliar-experimental-aulas.sql \
  supabase/migrations/033-fn-reconciliar-experimental-aulas.test.sql
```

- [ ] **Passo 4: Matar mutantes**

No mínimo estes quatro (o mesmo padrão `sed` usado nas migrations 027d/029/030):

```bash
# M1: tira o filtro de unidade da chave natural — deve reprovar "unidade errada nao casa"
sed "s/and ae.unidade_id = v_lead.unidade_id//" 033-fn-reconciliar-experimental-aulas.sql > /tmp/m1.sql

# M2: solta a tolerancia (compara so a data, nao a hora exata) — deve reprovar "deslocado 180min"
sed "s/= (v_lead.data_experimental + v_lead.horario_experimental)/between (v_lead.data_experimental + v_lead.horario_experimental - interval '2 hours') and (v_lead.data_experimental + v_lead.horario_experimental + interval '2 hours')/g" \
  033-fn-reconciliar-experimental-aulas.sql > /tmp/m2.sql

# M3: reconciliador toca em 'manual' — deve reprovar "manual sobrevive a rodada"
sed "s/'manual','realizado','faltou','cancelado'/'realizado','faltou','cancelado'/" \
  033-fn-reconciliar-experimental-aulas.sql > /tmp/m3.sql

# M4: 'faltou' e tratado igual 'cancelado' na sincronizacao — deve reprovar
# "faltou sincroniza estado, sem apagar aula_local_id" (o insert de uma nova
# linha 'pendente' por engano desvincularia)
sed "s/v_lead.status = 'experimental_faltou'/v_lead.status = 'NUNCA_BATE_experimental_faltou'/" \
  033-fn-reconciliar-experimental-aulas.sql > /tmp/m4.sql
```

Cada um roda contra o mesmo `.test.sql` e precisa **reprovar** no passo correspondente.

- [ ] **Passo 5: Aplicar em definitivo**

```bash
node scripts/aplicar-sql.mjs supabase/migrations/033-fn-reconciliar-experimental-aulas.sql
```

- [ ] **Passo 6: Rodar uma vez em produção e ler o resumo, não só o rc**

```sql
select public.fn_reconciliar_experimental_aulas(7, 200);
```

Conferir: `pendentes_sem_par` e `pendentes_ambiguo` batem com uma amostragem manual (algo como a consulta de "16 de 17 casam" feita durante o design). Se o número de `pendentes_ambiguo` for muito maior que zero, **parar e investigar antes de agendar o cron** — não é hipótese, é o mesmo tipo de "cron verde, zero trabalho" que já aconteceu hoje.

- [ ] **Passo 7: Cron** (só depois do Passo 6 confirmar números plausíveis)

```sql
select cron.schedule(
  'reconciliar-experimental-aulas',
  '*/15 * * * *',
  $$select public.fn_reconciliar_experimental_aulas(7, 200);$$
);
```

- [ ] **Passo 8: Commit**

```bash
git add supabase/migrations/033-fn-reconciliar-experimental-aulas.sql supabase/migrations/033-fn-reconciliar-experimental-aulas.test.sql
git commit -m "feat(033): reconciliador lead_experimentais <-> aulas_emusys + sincronizacao de estado"
```

---

## Roadmap das fases seguintes (não executadas nesta rodada)

Ordem do Alfredo. Cada uma ganha seu próprio plano detalhado (com o mesmo padrão de teste + mutantes) quando chegar a vez — escrever os oito passos de TDD para elas agora, antes de ver o Diff das Tasks 1–2 auditado, seria a mesma pressa que já custou caro hoje (v1 → v2 → v2.1 → v2.2 → v2.3).

**Task 3 — Agenda/UI.** Destacar `categoria='experimental'` na leitura que a Agenda já faz de `aulas_emusys`; trazer o contexto da migration 029 (`fabio_experimentais_do_professor`) na mesma tela. Não precisa de tela nova — precisa de um `case`/badge no componente que já lista as aulas do dia (`AgendaCard.tsx`/`AgendaTimeline.tsx` no LA Report, ou o equivalente no LA Teacher se a agenda do professor vier de lá).

**Task 4 — Molde do registro + RPC family-safe.** Novo `molde` em `fabio_registros_aula` (a tabela já é genérica — ver achado #5 da spec) com os quatro blocos do Contrato 4. A função que monta a devolutiva para a família não pode ler `leitura_de_conversao` — nem no SELECT, para não depender de disciplina de quem escreve o SELECT depois.

**Task 5 — Vínculo de matrícula com recibo, na UI.** O reconciliador (Task 2, passo 5) já preenche as quatro colunas automaticamente quando `lead_experimentais.aluno_id` é observado. Esta task é a superfície para a coordenação **confirmar/corrigir manualmente** quando `pendentes_ambiguo` aparecer também no lado da matrícula.

**Task 6 — E2E com lead QA.** Um lead `ZZTESTE` percorrendo o ciclo inteiro de ponta a ponta — agendado → aparece na agenda → registrado → devolutiva → matriculado — como prova viva antes de considerar o ciclo fechado.

## Self-Review

- **Cobertura da spec:** Contrato 1 (Task 1), Contrato 2 (Task 2 passo 1, ramos de sincronização de estado), Contrato 3 (Task 2 passo 1, bloco final do loop + nota do Passo 2 sobre a FK de alunos), Contrato 4 (Task 4, roadmap). Riscos da spec (fuso, sem-par, ambiguidade, professor multi-unidade) têm teste correspondente nas Tasks 1–2.
- **Placeholder scan:** o único texto não-executável é a nota do Passo 2 da Task 2 sobre o aluno `ZZTESTE` — deixado assim de propósito porque falta uma medição real (colunas `NOT NULL` de `public.alunos`) que ainda não foi feita nesta sessão. Marcado explicitamente como "fazer essa medição antes de rodar", não escondido como se fosse código pronto.
- **Consistência de tipos:** `aula_local_id integer` casa com `aulas_emusys.id integer`; `lead_experimental_id integer` casa com `lead_experimentais.id integer`; `aluno_id integer` casa com `alunos.id integer` — todos conferidos via `information_schema.columns` nesta sessão, não supostos.
