# Registro da Aula Experimental — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (execução manual nesta sessão, sem subagentes — é o padrão já em uso neste projeto para migrations testadas).

**Goal:** dar ao professor um jeito de registrar como foi a aula experimental, gerando de uma vez presença de fonte forte, primeiro capítulo pedagógico e leitura de conversão para o comercial.

**Architecture:** ver `docs/superpowers/specs/2026-08-05-registro-aula-experimental-design.md` (v3, carimbada pelo Alfredo em `8f376cd`). Quatro migrations independentes: 034 põe presença no vínculo da 032 e ensina o reconciliador a respeitar fonte forte; 035 cria a tabela de registro isolada e a RPC canônica que é o único caminho de escrita; 036 resolve destinatário comercial e generaliza a fila de avisos; 037 publica as duas views.

**Tech Stack:** Postgres/Supabase, SQL puro. Teste via `scripts/rodar-teste-sql.mjs` (BEGIN/ROLLBACK contra produção, com impressão digital antes/depois). Aplicação via `scripts/aplicar-sql.mjs`. Mutantes gerados por script Python a partir do arquivo real.

## Global Constraints

- **Vocabulário de fonte de presença é o do `aluno_presenca`, verbatim, sem inventar valor.** Os únicos válidos: `professor_whatsapp`, `professor_la_teacher`, `manual`, `sistema`, `emusys`, `fabio_audio`. App grava `professor_la_teacher`; áudio grava `fabio_audio`. **`professor_app` não existe** e deve ser rejeitado na escrita.
- **Fonte forte é a que passa em `public.fn_presenca_e_forte(text)`.** Nunca reimplementar essa regra — chamar a função.
- **Emusys nunca sobrescreve professor; professor sobrescreve Emusys.** Precedência decidida na escrita, uma vez, como na migration 009.
- **`emusys_presenca_bruta` é preservado** mesmo quando o professor ganha.
- **Toda comparação de horário converte para `'America/Sao_Paulo'` explicitamente.**
- **Nenhum prontuário real de aluno vira bancada de teste.** Toda fixture usa prefixo `ZZTESTE`, criada e descartada na mesma transação.
- **Todo teste tem mutante que o mata.** Verde não-falsificado é decoração. O mutante certo é o que as checagens antigas deixam passar.
- **Asserções medem a rodada sob teste.** Guardar o retorno da chamada em temp table e assertar nele; nunca chamar de novo para conferir (a segunda rodada acha tudo resolvido e devolve zero).
- **`\gset` é meta-comando do psql e NÃO funciona** no runner deste projeto. Usar `create temp table ... as select ...`.
- **`leitura_de_conversao` nunca aparece em view family-safe.**
- **A tabela de registro só é escrita por RPC**; escrita direta fica sem `GRANT`.
- **`unidade_id`/`professor_id` do registro são derivados do vínculo**, e a RPC ignora o que o chamador mandar nesses campos.
- **Migrations 032 e 033 estão aplicadas e carimbadas** — alterá-las exige migration nova e declarada, nunca edição do arquivo antigo.

---

## Estrutura de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `supabase/migrations/034-presenca-no-vinculo-experimental.sql` | 4 colunas de presença em `lead_experimental_aulas` + `create or replace` da `fn_reconciliar_experimental_aulas` respeitando fonte forte |
| `supabase/migrations/034-presenca-no-vinculo-experimental.test.sql` | CHECK de fonte, precedência nos dois sentidos, preservação do bruto, regressão comercial |
| `supabase/migrations/035-lead-experimental-registros.sql` | tabela do registro + índice único parcial + RPC `app_registrar_experimental` + grants |
| `supabase/migrations/035-lead-experimental-registros.test.sql` | travas de estado, 2ª chamada edita, derivação de unidade/professor, negação de escrita direta |
| `supabase/migrations/036-aviso-comercial-experimental.sql` | `unidade_contato_comercial` + generalização de `fabio_notificacoes` + `fabio_claim_notificacao_comercial` |
| `supabase/migrations/036-aviso-comercial-experimental.test.sql` | destinatário resolvido por unidade, ausência vira pulada visível, idempotência por referência |
| `supabase/migrations/037-views-registro-experimental.sql` | `vw_experimental_registro_comercial` + `vw_experimental_registro_family_safe` |
| `supabase/migrations/037-views-registro-experimental.test.sql` | a view family-safe não expõe `leitura_de_conversao` |

---

### Task 1: Migration 034 — presença no vínculo

**Files:**
- Create: `supabase/migrations/034-presenca-no-vinculo-experimental.sql`
- Create: `supabase/migrations/034-presenca-no-vinculo-experimental.test.sql`

**Interfaces:**
- Consumes: `public.lead_experimental_aulas` (032), `public.fn_reconciliar_experimental_aulas(integer,integer)` (033), `public.fn_presenca_e_forte(text)` (012).
- Produces: colunas `presenca_status`, `presenca_respondido_por`, `presenca_respondido_em`, `presenca_bruta_emusys` em `lead_experimental_aulas`; função `public.fn_registrar_presenca_experimental(p_vinculo_id bigint, p_status text, p_respondido_por text, p_bruta_emusys text default null) returns boolean` (devolve `true` se gravou, `false` se foi barrada pela precedência).

- [ ] **Passo 1: Escrever a migration**

```sql
-- 034 — presenca da experimental mora no vinculo, no padrao do aluno
--
-- A presenca da experimental JA TEM CASA: o vinculo da 032 e uma linha por par
-- lead x aula, exatamente o papel que aluno_presenca faz para o aluno. Nao se
-- cria tabela de presenca nova.
--
-- Vocabulario de fonte copiado VERBATIM do aluno_presenca_respondido_por_check.
-- A primeira versao da spec escreveu 'professor_app', que NAO EXISTE: a funcao
-- fn_presenca_e_forte devolve false pra ele, e a presenca nasceria fraca em
-- silencio. O CHECK abaixo rejeita isso na ESCRITA (achado do Alfredo).

alter table public.lead_experimental_aulas
  add column presenca_status text
    check (presenca_status is null or presenca_status in ('presente','falta')),
  add column presenca_respondido_por text
    check (presenca_respondido_por is null or presenca_respondido_por in
      ('professor_whatsapp','professor_la_teacher','manual','sistema','emusys','fabio_audio')),
  add column presenca_respondido_em timestamptz,
  add column presenca_bruta_emusys text;

comment on column public.lead_experimental_aulas.presenca_respondido_por is
'Fonte da presenca, mesmo vocabulario de aluno_presenca.respondido_por. Forte = passa em fn_presenca_e_forte. NUNCA usar professor_app (nao existe).';

-- Escrita de presenca com precedencia decidida UMA VEZ, aqui (padrao da 009):
-- fonte forte sobrescreve fraca; fraca NAO sobrescreve forte; o bruto do
-- Emusys e sempre preservado, inclusive quando o professor ganha.
create or replace function public.fn_registrar_presenca_experimental(
  p_vinculo_id     bigint,
  p_status         text,
  p_respondido_por text,
  p_bruta_emusys   text default null
)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_atual_por text;
  v_gravou    boolean := false;
begin
  select presenca_respondido_por into v_atual_por
    from lead_experimental_aulas where id = p_vinculo_id
     for update;

  if not found then
    raise exception 'vinculo_inexistente: %', p_vinculo_id;
  end if;

  -- O bruto do Emusys e memoria, nao decisao: grava sempre que vier.
  if p_bruta_emusys is not null then
    update lead_experimental_aulas
       set presenca_bruta_emusys = p_bruta_emusys
     where id = p_vinculo_id;
  end if;

  -- Precedencia: so nao grava quando o que ja esta la e FORTE e o que chega
  -- e FRACO. Forte sobre forte grava (correcao humana posterior e legitima).
  if v_atual_por is not null
     and public.fn_presenca_e_forte(v_atual_por)
     and not public.fn_presenca_e_forte(p_respondido_por) then
    return false;
  end if;

  update lead_experimental_aulas
     set presenca_status        = p_status,
         presenca_respondido_por = p_respondido_por,
         presenca_respondido_em  = now()
   where id = p_vinculo_id;

  -- Presenca FORTE tambem move o ciclo de vida do vinculo. Fonte fraca nao
  -- promove estado — senao o fantasma do Emusys voltaria pela porta dos fundos.
  if public.fn_presenca_e_forte(p_respondido_por) then
    update lead_experimental_aulas
       set estado = case when p_status = 'presente' then 'realizado' else 'faltou' end
     where id = p_vinculo_id
       and estado not in ('cancelado');
  end if;

  return true;
end
$function$;

revoke all on function public.fn_registrar_presenca_experimental(bigint,text,text,text) from public, anon, authenticated;
grant execute on function public.fn_registrar_presenca_experimental(bigint,text,text,text) to service_role;
```

- [ ] **Passo 2: Ajustar a 033 para não rebaixar fonte forte**

No mesmo arquivo, acrescentar o `create or replace` da `fn_reconciliar_experimental_aulas`. Copiar o corpo atual (`supabase/migrations/033-fn-reconciliar-experimental-aulas.sql`) e trocar **apenas** o primeiro `if` do laço, que hoje é:

```sql
      if v_vinculo.id is not null and v_vinculo.estado = 'manual' then
        null;  -- de proposito: nada a fazer, nem cancelado_em
```

por:

```sql
      -- 'manual' e presenca FORTE sao ambos decisao de quem estava presente.
      -- Precisa ser o PRIMEIRO if, nao um ramo do meio: a 033 ja teve bug
      -- exatamente assim (commit f42203e), quando o ramo de sync de
      -- 'experimental_realizada'/'convertido' promovia 'faltou' pra
      -- 'realizado' porque so excluia 'realizado' do alvo.
      if v_vinculo.id is not null
         and (v_vinculo.estado = 'manual'
              or public.fn_presenca_e_forte(v_vinculo.presenca_respondido_por)) then
        null;  -- de proposito: status comercial nao mexe em nada disso
```

- [ ] **Passo 3: Escrever o teste**

```sql
-- Teste da 034 — presenca no vinculo respeita fonte, e o comercial nao rebaixa
create temp table _res(passo text, esperado text, obtido text) on commit drop;

insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000000340', 'ZZTESTE unidade 034', 'ZZTESTE034')
on conflict (id) do nothing;

insert into public.professores (id, nome) values (-34001, 'ZZTESTE Professor 034');

insert into public.leads (id, unidade_id, whatsapp, status) values
  (-34001, '00000000-0000-4000-8000-000000000340', '5521999340001', 'novo'),
  (-34002, '00000000-0000-4000-8000-000000000340', '5521999340002', 'novo'),
  (-34003, '00000000-0000-4000-8000-000000000340', '5521999340003', 'novo'),
  (-34004, '00000000-0000-4000-8000-000000000340', '5521999340004', 'novo');

insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id)
values
  (-34001, -34001, 'ZZTESTE Forte vence fraca', '00000000-0000-4000-8000-000000000340', current_date+1, '10:00', 'experimental_agendada', -34001),
  (-34002, -34002, 'ZZTESTE Fraca nao vence',   '00000000-0000-4000-8000-000000000340', current_date+1, '11:00', 'experimental_agendada', -34001),
  (-34003, -34003, 'ZZTESTE Regressao comercial','00000000-0000-4000-8000-000000000340', current_date+1, '12:00', 'experimental_agendada', -34001),
  (-34004, -34004, 'ZZTESTE Bruto preservado',  '00000000-0000-4000-8000-000000000340', current_date+1, '13:00', 'experimental_agendada', -34001);

insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, categoria, professor_id, cancelada)
values
  (-34001, -934001, '00000000-0000-4000-8000-000000000340', current_date+1,
   (current_date+1 + time '10:00') at time zone 'America/Sao_Paulo', 'experimental', -34001, false),
  (-34002, -934002, '00000000-0000-4000-8000-000000000340', current_date+1,
   (current_date+1 + time '11:00') at time zone 'America/Sao_Paulo', 'experimental', -34001, false),
  (-34003, -934003, '00000000-0000-4000-8000-000000000340', current_date+1,
   (current_date+1 + time '12:00') at time zone 'America/Sao_Paulo', 'experimental', -34001, false),
  (-34004, -934004, '00000000-0000-4000-8000-000000000340', current_date+1,
   (current_date+1 + time '13:00') at time zone 'America/Sao_Paulo', 'experimental', -34001, false);

insert into public.lead_experimental_aulas (lead_experimental_id, aula_local_id, estado, casado_por)
values (-34001, -34001, 'vinculado', 'chave_natural'),
       (-34002, -34002, 'vinculado', 'chave_natural'),
       (-34003, -34003, 'vinculado', 'chave_natural'),
       (-34004, -34004, 'vinculado', 'chave_natural');

-- ── CHECK rejeita fonte inventada (o professor_app da spec v1) ─────────────
do $$
declare v_id bigint;
begin
  select id into v_id from lead_experimental_aulas where lead_experimental_id=-34001;
  begin
    update lead_experimental_aulas set presenca_respondido_por='professor_app' where id=v_id;
    insert into _res values ('fonte inventada rejeitada', 'rejeitado', 'ACEITOU — nasceria fraca em silencio');
  exception when check_violation then
    insert into _res values ('fonte inventada rejeitada', 'rejeitado', 'rejeitado');
  end;
end $$;

-- ── Forte sobrescreve fraca ────────────────────────────────────────────────
do $$
declare v_id bigint;
begin
  select id into v_id from lead_experimental_aulas where lead_experimental_id=-34001;
  perform public.fn_registrar_presenca_experimental(v_id, 'presente', 'emusys', 'presente');
  perform public.fn_registrar_presenca_experimental(v_id, 'falta', 'professor_la_teacher');
  insert into _res select 'forte sobrescreve fraca', 'falta/professor_la_teacher',
    presenca_status||'/'||presenca_respondido_por from lead_experimental_aulas where id=v_id;
  insert into _res select 'bruto do emusys preservado apos professor ganhar', 'presente',
    coalesce(presenca_bruta_emusys,'(nulo)') from lead_experimental_aulas where id=v_id;
end $$;

-- ── Fraca NAO sobrescreve forte, e a funcao devolve false ──────────────────
do $$
declare v_id bigint; v_ok boolean;
begin
  select id into v_id from lead_experimental_aulas where lead_experimental_id=-34002;
  perform public.fn_registrar_presenca_experimental(v_id, 'presente', 'fabio_audio');
  select public.fn_registrar_presenca_experimental(v_id, 'falta', 'emusys', 'ausente') into v_ok;
  insert into _res values ('fraca nao sobrescreve forte (retorno)', 'false', v_ok::text);
  insert into _res select 'fraca nao sobrescreve forte (valor)', 'presente/fabio_audio',
    presenca_status||'/'||presenca_respondido_por from lead_experimental_aulas where id=v_id;
  insert into _res select 'bruto gravado mesmo com escrita barrada', 'ausente',
    coalesce(presenca_bruta_emusys,'(nulo)') from lead_experimental_aulas where id=v_id;
end $$;

-- ── Presenca forte promove estado ──────────────────────────────────────────
insert into _res
select 'presenca forte promove estado', 'faltou',
       (select estado from lead_experimental_aulas where lead_experimental_id=-34001);

-- ── Fonte fraca NAO promove estado (fantasma nao entra pela porta dos fundos)
do $$
declare v_id bigint;
begin
  select id into v_id from lead_experimental_aulas where lead_experimental_id=-34004;
  perform public.fn_registrar_presenca_experimental(v_id, 'presente', 'emusys', 'presente');
  insert into _res select 'fonte fraca NAO promove estado', 'vinculado', estado
    from lead_experimental_aulas where id=v_id;
end $$;

-- ── REGRESSAO COMERCIAL: status do lead nao rebaixa presenca forte ─────────
do $$
declare v_id bigint;
begin
  select id into v_id from lead_experimental_aulas where lead_experimental_id=-34003;
  perform public.fn_registrar_presenca_experimental(v_id, 'presente', 'professor_la_teacher');
end $$;
update public.lead_experimentais set status='experimental_faltou' where id=-34003;

create temp table _rodada_034 on commit drop as
select public.fn_reconciliar_experimental_aulas(30, 500) as resumo;

insert into _res
select 'comercial nao rebaixa presenca forte (estado)', 'realizado',
       (select estado from lead_experimental_aulas where lead_experimental_id=-34003);
insert into _res
select 'comercial nao rebaixa presenca forte (fonte intacta)', 'professor_la_teacher',
       (select presenca_respondido_por from lead_experimental_aulas where lead_experimental_id=-34003);
insert into _res
select 'rodada da reconciliacao sem erro', '0',
       (select resumo->>'erros' from _rodada_034);

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
```

- [ ] **Passo 4: Rodar o teste e ver falhar**

```bash
node scripts/rodar-teste-sql.mjs supabase/migrations/034-presenca-no-vinculo-experimental.sql supabase/migrations/034-presenca-no-vinculo-experimental.test.sql
```

Esperado no primeiro rascunho: divergências (ou erro de sintaxe). Corrigir até `nenhuma divergência`.

- [ ] **Passo 5: Matar os mutantes**

```bash
python3 - <<'PY'
src = open('supabase/migrations/034-presenca-no-vinculo-experimental.sql', encoding='utf-8').read()

# M1 — precedencia invertida: fraca passa a sobrescrever forte
m1 = src.replace(
  "and public.fn_presenca_e_forte(v_atual_por)\n     and not public.fn_presenca_e_forte(p_respondido_por) then",
  "and not public.fn_presenca_e_forte(v_atual_por)\n     and public.fn_presenca_e_forte(p_respondido_por) then", 1)
assert m1 != src; open('supabase/migrations/034-m1.sql','w',encoding='utf-8').write(m1)

# M2 — CHECK de fonte afrouxado: professor_app passaria
m2 = src.replace(
  "check (presenca_respondido_por is null or presenca_respondido_por in\n      ('professor_whatsapp','professor_la_teacher','manual','sistema','emusys','fabio_audio')),",
  "check (presenca_respondido_por is null or length(presenca_respondido_por) > 0),", 1)
assert m2 != src; open('supabase/migrations/034-m2.sql','w',encoding='utf-8').write(m2)

# M3 — bruto do Emusys deixa de ser preservado
m3 = src.replace(
  "  if p_bruta_emusys is not null then\n    update lead_experimental_aulas\n       set presenca_bruta_emusys = p_bruta_emusys\n     where id = p_vinculo_id;\n  end if;",
  "  -- M3: bruto descartado", 1)
assert m3 != src; open('supabase/migrations/034-m3.sql','w',encoding='utf-8').write(m3)

# M4 — guarda de fonte forte sai do primeiro if do reconciliador
m4 = src.replace(
  "or public.fn_presenca_e_forte(v_vinculo.presenca_respondido_por)) then",
  "or false) then", 1)
assert m4 != src; open('supabase/migrations/034-m4.sql','w',encoding='utf-8').write(m4)

# M5 — fonte fraca passa a promover estado (fantasma pela porta dos fundos)
m5 = src.replace(
  "  if public.fn_presenca_e_forte(p_respondido_por) then\n    update lead_experimental_aulas\n       set estado = case",
  "  if true then\n    update lead_experimental_aulas\n       set estado = case", 1)
assert m5 != src; open('supabase/migrations/034-m5.sql','w',encoding='utf-8').write(m5)
print('5 mutantes gerados')
PY

for m in m1 m2 m3 m4 m5; do
  echo "--- $m ---"
  node scripts/rodar-teste-sql.mjs supabase/migrations/034-$m.sql supabase/migrations/034-presenca-no-vinculo-experimental.test.sql | head -4
done
rm -f supabase/migrations/034-m?.sql
```

Esperado: os cinco reprovam. **Se algum passar, o teste é fraco — corrigir o teste, não o mutante.** Cada mutante tem de morrer no passo que existe pra pegá-lo: M1 nos dois passos de precedência, M2 no "fonte inventada rejeitada", M3 nos passos de bruto, M4 na regressão comercial, M5 em "fonte fraca NÃO promove estado".

- [ ] **Passo 6: Aplicar e commitar**

```bash
node scripts/aplicar-sql.mjs supabase/migrations/034-presenca-no-vinculo-experimental.sql
git add supabase/migrations/034-presenca-no-vinculo-experimental.sql supabase/migrations/034-presenca-no-vinculo-experimental.test.sql
git commit -m "feat(034): presenca da experimental no vinculo, no padrao do aluno"
git push origin main
git log --oneline origin/main..HEAD | wc -l   # tem que dar 0
```

---

### Task 2: Migration 035 — tabela de registro + RPC canônica

**Files:**
- Create: `supabase/migrations/035-lead-experimental-registros.sql`
- Create: `supabase/migrations/035-lead-experimental-registros.test.sql`

**Interfaces:**
- Consumes: `public.lead_experimental_aulas` com as colunas da Task 1; `public.fn_registrar_presenca_experimental(bigint,text,text,text)`.
- Produces: tabela `public.lead_experimental_registros`; RPC `public.app_registrar_experimental(p_vinculo_id bigint, p_anotacao_pedagogica text, p_devolutiva_familia text, p_proximos_passos text, p_leitura_de_conversao text, p_origem text default 'app') returns uuid` (devolve o id do registro, criando ou editando o vigente).

- [ ] **Passo 1: Escrever a migration**

```sql
-- 035 — registro da experimental: tabela propria + RPC canonica
--
-- TABELA PROPRIA, e nao molde novo em fabio_registros_aula: das 13 RPCs que
-- leem aquela tabela, 12 NAO filtram por molde (medido em 05/08/2026). Duas
-- causariam dano real: fabio_enfileirar_devolutivas mandaria devolutiva pra
-- FAMILIA de um lead (viola D1 da spec), e fabio_emitir_presenca_por_registro
-- escreveria em aluno_presenca, que exige aluno_id NOT NULL. Tabela separada
-- torna o vazamento impossivel por construcao, em vez de depender de cada RPC
-- futura lembrar de filtrar.

create table public.lead_experimental_registros (
  id                    uuid primary key default gen_random_uuid(),
  vinculo_id            bigint not null references public.lead_experimental_aulas(id),
  unidade_id            uuid not null references public.unidades(id),
  professor_id          integer references public.professores(id),

  -- BLOCO FAMILY-SAFE: o consultor pode mostrar/adaptar para a familia
  anotacao_pedagogica   text,
  devolutiva_familia    text,
  proximos_passos       text,

  -- BLOCO INTERNO: nunca sai para a familia
  leitura_de_conversao  text,

  origem                text not null default 'app'
                        check (origem in ('app','whatsapp')),
  audio_id              uuid references public.fabio_fila_audios(id),
  status                text not null default 'rascunho'
                        check (status in ('rascunho','aguardando_confirmacao','confirmado','descartado')),
  confirmado_em         timestamptz,
  confirmado_por        integer references public.usuarios(id),
  criado_em             timestamptz not null default now(),
  atualizado_em         timestamptz not null default now()
);

create unique index uq_lead_exp_registro_vigente
    on public.lead_experimental_registros (vinculo_id)
 where status <> 'descartado';

comment on column public.lead_experimental_registros.leitura_de_conversao is
'INTERNO. Nunca sai em view family-safe. Ver spec 2026-08-05-registro-aula-experimental-design.md §3.';

-- ESCRITA SO POR AQUI. O indice unico REJEITA (unique_violation); ele nao
-- transforma a segunda tentativa em edicao — quem faz isso e codigo. E
-- unidade_id/professor_id sao DERIVADOS do vinculo: se viessem do cliente,
-- nasceria registro de aula de uma unidade carimbado em outra. (Achado do
-- Alfredo na revisao do 3aed455.)
create or replace function public.app_registrar_experimental(
  p_vinculo_id            bigint,
  p_anotacao_pedagogica   text,
  p_devolutiva_familia    text,
  p_proximos_passos       text,
  p_leitura_de_conversao  text,
  p_origem                text default 'app'
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_estado      text;
  v_unidade_id  uuid;
  v_professor_id integer;
  v_registro_id uuid;
begin
  -- Deriva do vinculo. Nao existe parametro de unidade/professor de proposito.
  select v.estado, ae.unidade_id, ae.professor_id
    into v_estado, v_unidade_id, v_professor_id
    from lead_experimental_aulas v
    join aulas_emusys ae on ae.id = v.aula_local_id
   where v.id = p_vinculo_id and v.substituido_em is null
     for update of v;

  if not found then
    raise exception 'vinculo_inexistente_ou_sem_aula: %', p_vinculo_id;
  end if;

  -- Travas de estado (spec §6): sem aula nao ha o que registrar, e aula que
  -- nao aconteceu nao tem capitulo pedagogico.
  if v_estado = 'pendente' then
    raise exception 'experimental_sem_aula_vinculada';
  elsif v_estado = 'faltou' then
    raise exception 'experimental_faltou_nao_tem_registro';
  elsif v_estado = 'cancelado' then
    raise exception 'experimental_cancelada';
  end if;

  select id into v_registro_id
    from lead_experimental_registros
   where vinculo_id = p_vinculo_id and status <> 'descartado';

  if found then
    update lead_experimental_registros
       set anotacao_pedagogica  = p_anotacao_pedagogica,
           devolutiva_familia   = p_devolutiva_familia,
           proximos_passos      = p_proximos_passos,
           leitura_de_conversao = p_leitura_de_conversao,
           origem               = p_origem,
           atualizado_em        = now()
     where id = v_registro_id;
  else
    insert into lead_experimental_registros
      (vinculo_id, unidade_id, professor_id, anotacao_pedagogica, devolutiva_familia,
       proximos_passos, leitura_de_conversao, origem, status)
    values
      (p_vinculo_id, v_unidade_id, v_professor_id, p_anotacao_pedagogica, p_devolutiva_familia,
       p_proximos_passos, p_leitura_de_conversao, p_origem, 'aguardando_confirmacao')
    returning id into v_registro_id;
  end if;

  return v_registro_id;
end
$function$;

-- A garantia e de PERMISSAO, nao de convencao.
revoke all on table public.lead_experimental_registros from public, anon, authenticated;
grant select on table public.lead_experimental_registros to service_role;
revoke all on function public.app_registrar_experimental(bigint,text,text,text,text,text) from public, anon;
grant execute on function public.app_registrar_experimental(bigint,text,text,text,text,text) to service_role, authenticated;
```

- [ ] **Passo 2: Escrever o teste**

```sql
-- Teste da 035 — a RPC e o unico caminho, e ela deriva o que nao se digita
create temp table _res(passo text, esperado text, obtido text) on commit drop;

insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000000350', 'ZZTESTE unidade 035',  'ZZTESTE035'),
  ('00000000-0000-4000-8000-000000000351', 'ZZTESTE unidade 035b', 'ZZTESTE035B')
on conflict (id) do nothing;

insert into public.professores (id, nome) values (-35001, 'ZZTESTE Professor 035');

insert into public.leads (id, unidade_id, whatsapp, status) values
  (-35001, '00000000-0000-4000-8000-000000000350', '5521999350001', 'novo'),
  (-35002, '00000000-0000-4000-8000-000000000350', '5521999350002', 'novo'),
  (-35003, '00000000-0000-4000-8000-000000000350', '5521999350003', 'novo');

insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id)
values
  (-35001, -35001, 'ZZTESTE Registra ok',  '00000000-0000-4000-8000-000000000350', current_date+1, '10:00', 'experimental_agendada', -35001),
  (-35002, -35002, 'ZZTESTE Faltou',       '00000000-0000-4000-8000-000000000350', current_date+1, '11:00', 'experimental_faltou',    -35001),
  (-35003, -35003, 'ZZTESTE Pendente',     '00000000-0000-4000-8000-000000000350', current_date+1, '12:00', 'experimental_agendada', -35001);

insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, categoria, professor_id, cancelada)
values
  (-35001, -935001, '00000000-0000-4000-8000-000000000350', current_date+1,
   (current_date+1 + time '10:00') at time zone 'America/Sao_Paulo', 'experimental', -35001, false),
  (-35002, -935002, '00000000-0000-4000-8000-000000000350', current_date+1,
   (current_date+1 + time '11:00') at time zone 'America/Sao_Paulo', 'experimental', -35001, false);

insert into public.lead_experimental_aulas (lead_experimental_id, aula_local_id, estado, casado_por)
values (-35001, -35001, 'vinculado', 'chave_natural'),
       (-35002, -35002, 'faltou',    'chave_natural'),
       (-35003, null,   'pendente',  null);

-- ── Registra e deriva unidade/professor do vinculo ─────────────────────────
do $$
declare v_vinc bigint; v_reg uuid;
begin
  select id into v_vinc from lead_experimental_aulas where lead_experimental_id=-35001;
  select public.app_registrar_experimental(
           v_vinc, 'Trabalhou acordes basicos', 'Ele pegou rapido, se divertiu',
           'Comecar por musica que ele gosta', 'Mae perguntou preco 2x — quente')
    into v_reg;
  insert into _res select 'unidade derivada do vinculo', '00000000-0000-4000-8000-000000000350',
    unidade_id::text from lead_experimental_registros where id=v_reg;
  insert into _res select 'professor derivado do vinculo', '-35001',
    professor_id::text from lead_experimental_registros where id=v_reg;
  insert into _res select 'nasce aguardando confirmacao', 'aguardando_confirmacao',
    status from lead_experimental_registros where id=v_reg;
end $$;

-- ── Segunda chamada EDITA o vigente, nao estoura nem duplica ───────────────
do $$
declare v_vinc bigint; v_reg uuid;
begin
  select id into v_vinc from lead_experimental_aulas where lead_experimental_id=-35001;
  begin
    select public.app_registrar_experimental(
             v_vinc, 'TEXTO EDITADO', 'idem', 'idem', 'idem') into v_reg;
    insert into _res values ('2a chamada nao estoura', 'ok', 'ok');
  exception when unique_violation then
    insert into _res values ('2a chamada nao estoura', 'ok', 'ESTOUROU unique_violation');
  end;
end $$;

insert into _res
select '2a chamada mantem 1 registro vigente', '1',
       (select count(*)::text from lead_experimental_registros r
          join lead_experimental_aulas v on v.id=r.vinculo_id
         where v.lead_experimental_id=-35001 and r.status <> 'descartado');
insert into _res
select '2a chamada gravou o texto novo', 'TEXTO EDITADO',
       (select r.anotacao_pedagogica from lead_experimental_registros r
          join lead_experimental_aulas v on v.id=r.vinculo_id
         where v.lead_experimental_id=-35001 and r.status <> 'descartado');

-- ── Travas de estado ───────────────────────────────────────────────────────
do $$
declare v_vinc bigint;
begin
  select id into v_vinc from lead_experimental_aulas where lead_experimental_id=-35002;
  begin
    perform public.app_registrar_experimental(v_vinc, 'a','b','c','d');
    insert into _res values ('faltou nao aceita registro', 'bloqueado', 'ACEITOU');
  exception when others then
    insert into _res values ('faltou nao aceita registro', 'bloqueado', 'bloqueado');
  end;

  select id into v_vinc from lead_experimental_aulas where lead_experimental_id=-35003;
  begin
    perform public.app_registrar_experimental(v_vinc, 'a','b','c','d');
    insert into _res values ('pendente nao aceita registro', 'bloqueado', 'ACEITOU');
  exception when others then
    insert into _res values ('pendente nao aceita registro', 'bloqueado', 'bloqueado');
  end;
end $$;

-- ── Escrita direta na tabela e negada por PERMISSAO ────────────────────────
do $$
begin
  begin
    set local role authenticated;
    insert into public.lead_experimental_registros (vinculo_id, unidade_id)
    values ((select id from lead_experimental_aulas where lead_experimental_id=-35001),
            '00000000-0000-4000-8000-000000000351');
    reset role;
    insert into _res values ('escrita direta negada', 'negado', 'PERMITIU — fronteira e convencao, nao permissao');
  exception when insufficient_privilege then
    reset role;
    insert into _res values ('escrita direta negada', 'negado', 'negado');
  end;
end $$;

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
```

- [ ] **Passo 3: Rodar o teste até verde**

```bash
node scripts/rodar-teste-sql.mjs supabase/migrations/035-lead-experimental-registros.sql supabase/migrations/035-lead-experimental-registros.test.sql
```

- [ ] **Passo 4: Matar os mutantes**

```bash
python3 - <<'PY'
src = open('supabase/migrations/035-lead-experimental-registros.sql', encoding='utf-8').read()

# M1 — RPC sempre insere: a 2a chamada volta a estourar unique_violation
m1 = src.replace("  if found then\n    update lead_experimental_registros", "  if false then\n    update lead_experimental_registros", 1)
assert m1 != src; open('supabase/migrations/035-m1.sql','w',encoding='utf-8').write(m1)

# M2 — trava de 'faltou' removida
m2 = src.replace("  elsif v_estado = 'faltou' then\n    raise exception 'experimental_faltou_nao_tem_registro';", "", 1)
assert m2 != src; open('supabase/migrations/035-m2.sql','w',encoding='utf-8').write(m2)

# M3 — trava de 'pendente' removida
m3 = src.replace("  if v_estado = 'pendente' then\n    raise exception 'experimental_sem_aula_vinculada';\n  elsif", "  if false then\n    null;\n  elsif", 1)
assert m3 != src; open('supabase/migrations/035-m3.sql','w',encoding='utf-8').write(m3)

# M4 — escrita direta liberada: a fronteira volta a ser convencao
m4 = src.replace("grant select on table public.lead_experimental_registros to service_role;",
                 "grant select, insert, update on table public.lead_experimental_registros to service_role, authenticated;", 1)
assert m4 != src; open('supabase/migrations/035-m4.sql','w',encoding='utf-8').write(m4)
print('4 mutantes gerados')
PY

for m in m1 m2 m3 m4; do
  echo "--- $m ---"
  node scripts/rodar-teste-sql.mjs supabase/migrations/035-$m.sql supabase/migrations/035-lead-experimental-registros.test.sql | head -4
done
rm -f supabase/migrations/035-m?.sql
```

**Falta de propósito um mutante aqui:** não há como mutar "unidade derivada" trocando por parâmetro, porque a RPC não tem esse parâmetro — a derivação é garantida pela *ausência da porta*, não por checagem. O teste ainda assere o valor derivado, para pegar erro de join.

- [ ] **Passo 5: Aplicar e commitar**

```bash
node scripts/aplicar-sql.mjs supabase/migrations/035-lead-experimental-registros.sql
git add supabase/migrations/035-lead-experimental-registros.sql supabase/migrations/035-lead-experimental-registros.test.sql
git commit -m "feat(035): registro da experimental em tabela propria, escrita so por RPC"
git push origin main
git log --oneline origin/main..HEAD | wc -l   # tem que dar 0
```

---

### Task 3: Migration 036 — contato comercial e fila generalizada

**Files:**
- Create: `supabase/migrations/036-aviso-comercial-experimental.sql`
- Create: `supabase/migrations/036-aviso-comercial-experimental.test.sql`

**Interfaces:**
- Consumes: `public.fabio_notificacoes` (018), `public.lead_experimental_registros` (Task 2).
- Produces: tabela `public.unidade_contato_comercial`; colunas `destinatario_tipo` e `destinatario_whatsapp` em `fabio_notificacoes`; função `public.fabio_enfileirar_aviso_comercial(p_registro_id uuid) returns uuid` (devolve o id da notificação, ou `null` se pulada).

- [ ] **Passo 1: Escrever a migration**

```sql
-- 036 — o aviso ao comercial e do Fabio, com destinatario resolvido no BANCO
--
-- Nao pelo n8n: o dedup de la e staticData na memoria do workflow (reimportar
-- apaga o historico e repete mensagem), sem retry, sem recibo, e o rastro fica
-- em executionData que expira. A fila do Fabio tem lease, tentativas e recibo.
--
-- E o contato mora em TABELA, nao dentro do fluxo: em um mes a pessoa do
-- Recreio mudou (Cleiton virou gerente, entrou a Daiana) e o no do n8n
-- continua chamado "Clayton". Contato em tabela se corrige com um update.

create table public.unidade_contato_comercial (
  unidade_id    uuid primary key references public.unidades(id),
  nome          text not null,
  whatsapp      text not null,
  ativo         boolean not null default true,
  atualizado_em timestamptz not null default now()
);

revoke all on table public.unidade_contato_comercial from public, anon, authenticated;
grant select on table public.unidade_contato_comercial to service_role;

-- A fila aprende a falar com quem nao e professor. professor_id vira opcional,
-- e um CHECK garante que todo aviso tenha EXATAMENTE um destinatario resolvido
-- — destinatario ausente tem que ser impossivel, nao improvavel.
alter table public.fabio_notificacoes alter column professor_id drop not null;
alter table public.fabio_notificacoes
  add column destinatario_tipo text not null default 'professor'
    check (destinatario_tipo in ('professor','comercial')),
  add column destinatario_whatsapp text;

alter table public.fabio_notificacoes
  add constraint chk_notificacao_destinatario check (
    (destinatario_tipo = 'professor' and professor_id is not null)
    or
    (destinatario_tipo = 'comercial' and destinatario_whatsapp is not null)
  );

-- Vocabulario existente estendido, nao substituido: o CHECK de tipo hoje aceita
-- briefing_matinal, pendencia_registro, experimental_nova, reagendamento, outro,
-- devolutiva_pronta, devolutiva_destinatario.
alter table public.fabio_notificacoes drop constraint if exists fabio_notificacoes_tipo_check;
alter table public.fabio_notificacoes add constraint fabio_notificacoes_tipo_check
  check (tipo in ('briefing_matinal','pendencia_registro','experimental_nova','reagendamento',
                  'outro','devolutiva_pronta','devolutiva_destinatario','experimental_registrada'));

-- 'pulada_preferencia' e sobre preferencia do professor. Falta de destinatario
-- e outra coisa, e precisa ser VISIVEL — nao pode se disfarcar de preferencia.
alter table public.fabio_notificacoes drop constraint if exists fabio_notificacoes_status_check;
alter table public.fabio_notificacoes add constraint fabio_notificacoes_status_check
  check (status in ('processando','enviada','falhou','pulada_preferencia','pulada_sem_destinatario'));

create or replace function public.fabio_enfileirar_aviso_comercial(p_registro_id uuid)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_reg      record;
  v_contato  record;
  v_corpo    text;
  v_id       uuid;
begin
  select r.*, le.nome_aluno, ae.data_hora_inicio, v.presenca_status
    into v_reg
    from lead_experimental_registros r
    join lead_experimental_aulas v on v.id = r.vinculo_id
    join lead_experimentais le on le.id = v.lead_experimental_id
    join aulas_emusys ae on ae.id = v.aula_local_id
   where r.id = p_registro_id;

  if not found then
    raise exception 'registro_inexistente: %', p_registro_id;
  end if;

  select * into v_contato
    from unidade_contato_comercial
   where unidade_id = v_reg.unidade_id and ativo;

  -- NAO usar `found` daqui pra baixo: qualquer select que alguem insira no meio
  -- o sobrescreve em silencio. A pergunta "achou contato?" fica presa a uma
  -- variavel propria.
  -- Este e o UNICO lugar do sistema onde o bloco family-safe e a leitura de
  -- conversao aparecem juntos — porque aqui o destinatario E o circulo interno.
  v_corpo := format(
    E'Experimental registrada — %s\n\nQuando: %s\nPresenca: %s\n\nComo foi: %s\n\nProximos passos: %s\n\n[interno] Leitura: %s',
    v_reg.nome_aluno,
    to_char(v_reg.data_hora_inicio at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI'),
    coalesce(v_reg.presenca_status, 'nao informada'),
    coalesce(v_reg.devolutiva_familia, '(nao preenchido)'),
    coalesce(v_reg.proximos_passos, '(nao preenchido)'),
    coalesce(v_reg.leitura_de_conversao, '(nao preenchido)'));

  if v_contato.unidade_id is null then
    -- Sem destinatario: fica VISIVEL na fila, nao some.
    insert into fabio_notificacoes
      (professor_id, destinatario_tipo, tipo, categoria, corpo, canal, status,
       motivo_pulada, referencia_tipo, referencia_id, destinatario_whatsapp)
    values
      (null, 'comercial', 'experimental_registrada', 'informativa', v_corpo, 'whatsapp',
       'pulada_sem_destinatario', 'sem_contato_comercial_na_unidade',
       'lead_experimental_registro', p_registro_id::text, null)
    on conflict do nothing;
    return null;
  end if;

  insert into fabio_notificacoes
    (professor_id, destinatario_tipo, destinatario_whatsapp, tipo, categoria, corpo,
     canal, status, referencia_tipo, referencia_id)
  values
    (null, 'comercial', v_contato.whatsapp, 'experimental_registrada', 'informativa', v_corpo,
     'whatsapp', 'processando', 'lead_experimental_registro', p_registro_id::text)
  returning id into v_id;

  return v_id;
end
$function$;

revoke all on function public.fabio_enfileirar_aviso_comercial(uuid) from public, anon, authenticated;
grant execute on function public.fabio_enfileirar_aviso_comercial(uuid) to service_role;

-- Contatos vigentes, conferidos com o n8n em 05/08/2026 (os tres batem).
-- Vitoria tem DDD 31 porque e de Minas — esta correto.
insert into public.unidade_contato_comercial (unidade_id, nome, whatsapp)
select id, 'Vitória', '553171422022'  from public.unidades where codigo = 'CG'
on conflict (unidade_id) do nothing;
insert into public.unidade_contato_comercial (unidade_id, nome, whatsapp)
select id, 'Kailane', '5521984690143' from public.unidades where codigo = 'BARRA'
on conflict (unidade_id) do nothing;
insert into public.unidade_contato_comercial (unidade_id, nome, whatsapp)
select id, 'Daiana',  '5521968060404' from public.unidades where codigo = 'REC'
on conflict (unidade_id) do nothing;
```

- [ ] **Passo 2: Escrever o teste**

```sql
-- Teste da 036 — destinatario resolvido por unidade; ausencia fica VISIVEL
create temp table _res(passo text, esperado text, obtido text) on commit drop;

insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000000360', 'ZZTESTE unidade 036 com contato', 'ZZTESTE036'),
  ('00000000-0000-4000-8000-000000000361', 'ZZTESTE unidade 036 SEM contato', 'ZZTESTE036B')
on conflict (id) do nothing;

insert into public.unidade_contato_comercial (unidade_id, nome, whatsapp)
values ('00000000-0000-4000-8000-000000000360', 'ZZTESTE Comercial', '5521900000036');

insert into public.professores (id, nome) values (-36001, 'ZZTESTE Professor 036');

insert into public.leads (id, unidade_id, whatsapp, status) values
  (-36001, '00000000-0000-4000-8000-000000000360', '5521999360001', 'novo'),
  (-36002, '00000000-0000-4000-8000-000000000361', '5521999360002', 'novo');

insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id)
values
  (-36001, -36001, 'ZZTESTE Com Contato', '00000000-0000-4000-8000-000000000360', current_date+1, '10:00', 'experimental_agendada', -36001),
  (-36002, -36002, 'ZZTESTE Sem Contato', '00000000-0000-4000-8000-000000000361', current_date+1, '11:00', 'experimental_agendada', -36001);

insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, categoria, professor_id, cancelada)
values
  (-36001, -936001, '00000000-0000-4000-8000-000000000360', current_date+1,
   (current_date+1 + time '10:00') at time zone 'America/Sao_Paulo', 'experimental', -36001, false),
  (-36002, -936002, '00000000-0000-4000-8000-000000000361', current_date+1,
   (current_date+1 + time '11:00') at time zone 'America/Sao_Paulo', 'experimental', -36001, false);

insert into public.lead_experimental_aulas (lead_experimental_id, aula_local_id, estado, casado_por)
values (-36001, -36001, 'vinculado', 'chave_natural'),
       (-36002, -36002, 'vinculado', 'chave_natural');

-- ── Com contato: aviso enfileirado pro numero da unidade ───────────────────
do $$
declare v_vinc bigint; v_reg uuid; v_not uuid;
begin
  select id into v_vinc from lead_experimental_aulas where lead_experimental_id=-36001;
  select public.app_registrar_experimental(v_vinc, 'aula boa', 'foi muito bem',
           'seguir no violao', 'SEGREDO COMERCIAL') into v_reg;
  select public.fabio_enfileirar_aviso_comercial(v_reg) into v_not;

  insert into _res select 'destinatario resolvido pela unidade', '5521900000036',
    coalesce(destinatario_whatsapp,'(nulo)') from fabio_notificacoes where id=v_not;
  insert into _res select 'destinatario_tipo comercial', 'comercial',
    destinatario_tipo from fabio_notificacoes where id=v_not;
  insert into _res select 'professor_id nulo em aviso comercial', 'nulo',
    case when professor_id is null then 'nulo' else 'PREENCHIDO' end
    from fabio_notificacoes where id=v_not;
  -- aqui a leitura de conversao DEVE aparecer: o destinatario e o circulo interno
  insert into _res select 'aviso ao comercial carrega a leitura', 'sim',
    case when corpo like '%SEGREDO COMERCIAL%' then 'sim' else 'nao' end
    from fabio_notificacoes where id=v_not;
end $$;

-- ── Sem contato: fica VISIVEL como pulada_sem_destinatario ─────────────────
do $$
declare v_vinc bigint; v_reg uuid; v_not uuid;
begin
  select id into v_vinc from lead_experimental_aulas where lead_experimental_id=-36002;
  select public.app_registrar_experimental(v_vinc, 'a','b','c','d') into v_reg;
  select public.fabio_enfileirar_aviso_comercial(v_reg) into v_not;

  insert into _res values ('sem contato devolve null', 'null',
    coalesce(v_not::text, 'null'));
  insert into _res select 'sem contato deixa RASTRO na fila', 'pulada_sem_destinatario',
    coalesce((select status from fabio_notificacoes
               where referencia_tipo='lead_experimental_registro'
                 and referencia_id=v_reg::text), '(nenhum)');
end $$;

-- ── CHECK impede aviso sem destinatario nenhum ─────────────────────────────
do $$
begin
  begin
    insert into fabio_notificacoes
      (professor_id, destinatario_tipo, tipo, categoria, corpo, canal, status)
    values (null, 'comercial', 'outro', 'informativa', 'x', 'whatsapp', 'processando');
    insert into _res values ('aviso sem destinatario rejeitado', 'rejeitado', 'ACEITOU');
  exception when check_violation then
    insert into _res values ('aviso sem destinatario rejeitado', 'rejeitado', 'rejeitado');
  end;
end $$;

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
```

- [ ] **Passo 3: Rodar até verde, matar os mutantes**

```bash
node scripts/rodar-teste-sql.mjs supabase/migrations/036-aviso-comercial-experimental.sql supabase/migrations/036-aviso-comercial-experimental.test.sql

python3 - <<'PY'
src = open('supabase/migrations/036-aviso-comercial-experimental.sql', encoding='utf-8').read()

# M1 — sem contato passa a sumir em silencio (o defeito classico)
m1 = src.replace("""    insert into fabio_notificacoes
      (professor_id, destinatario_tipo, tipo, categoria, corpo, canal, status,
       motivo_pulada, referencia_tipo, referencia_id, destinatario_whatsapp)
    values
      (null, 'comercial', 'experimental_registrada', 'informativa', v_corpo, 'whatsapp',
       'pulada_sem_destinatario', 'sem_contato_comercial_na_unidade',
       'lead_experimental_registro', p_registro_id::text, null)
    on conflict do nothing;
    return null;""", "    return null;", 1)
assert m1 != src; open('supabase/migrations/036-m1.sql','w',encoding='utf-8').write(m1)

# M2 — CHECK de destinatario removido: aviso sem ninguem passa a ser aceito
m2 = src.replace("""  add constraint chk_notificacao_destinatario check (
    (destinatario_tipo = 'professor' and professor_id is not null)
    or
    (destinatario_tipo = 'comercial' and destinatario_whatsapp is not null)
  );""", "  add constraint chk_notificacao_destinatario check (true);", 1)
assert m2 != src; open('supabase/migrations/036-m2.sql','w',encoding='utf-8').write(m2)

# M3 — destinatario deixa de vir da unidade (volta o hardcode do n8n)
m3 = src.replace("v_contato.whatsapp,", "'5521999999999',", 1)
assert m3 != src; open('supabase/migrations/036-m3.sql','w',encoding='utf-8').write(m3)
print('3 mutantes gerados')
PY

for m in m1 m2 m3; do
  echo "--- $m ---"
  node scripts/rodar-teste-sql.mjs supabase/migrations/036-$m.sql supabase/migrations/036-aviso-comercial-experimental.test.sql | head -4
done
rm -f supabase/migrations/036-m?.sql
```

- [ ] **Passo 4: Aplicar e commitar**

```bash
node scripts/aplicar-sql.mjs supabase/migrations/036-aviso-comercial-experimental.sql
git add supabase/migrations/036-aviso-comercial-experimental.sql supabase/migrations/036-aviso-comercial-experimental.test.sql
git commit -m "feat(036): aviso ao comercial pelo Fabio, contato resolvido no banco"
git push origin main
git log --oneline origin/main..HEAD | wc -l   # tem que dar 0
```

---

### Task 4: Migration 037 — as duas views

**Files:**
- Create: `supabase/migrations/037-views-registro-experimental.sql`
- Create: `supabase/migrations/037-views-registro-experimental.test.sql`

**Interfaces:**
- Consumes: `public.lead_experimental_registros` (Task 2), `public.lead_experimental_aulas` (Tasks 1 e 032).
- Produces: `public.vw_experimental_registro_comercial` (com `leitura_de_conversao`) e `public.vw_experimental_registro_family_safe` (sem).

- [ ] **Passo 1: Escrever a migration**

```sql
-- 037 — duas views, nao um parametro booleano
--
-- Um flag errado vira vazamento; uma view que NAO TEM a coluna nao pode
-- vaza-la. O nome family_safe descreve a GARANTIA (e seguro se chegar a
-- familia), nao o destinatario — nao existe caminho Fabio->familia nesta fase
-- (D1 da spec), e um nome como "_familia" convidaria alguem a criar um depois
-- achando que estava previsto. (Achado do Alfredo na revisao do 4f00e94.)

create or replace view public.vw_experimental_registro_comercial as
select r.id                     as registro_id,
       r.vinculo_id,
       le.id                    as lead_experimental_id,
       le.nome_aluno,
       r.unidade_id,
       r.professor_id,
       ae.data_hora_inicio,
       v.estado                 as estado_vinculo,
       v.presenca_status,
       v.presenca_respondido_por,
       public.fn_presenca_e_forte(v.presenca_respondido_por) as presenca_e_forte,
       r.anotacao_pedagogica,
       r.devolutiva_familia,
       r.proximos_passos,
       r.leitura_de_conversao,   -- INTERNO
       r.status,
       r.criado_em
  from public.lead_experimental_registros r
  join public.lead_experimental_aulas v on v.id = r.vinculo_id
  join public.lead_experimentais le on le.id = v.lead_experimental_id
  left join public.aulas_emusys ae on ae.id = v.aula_local_id
 where r.status <> 'descartado';

create or replace view public.vw_experimental_registro_family_safe as
select r.id                     as registro_id,
       r.vinculo_id,
       le.nome_aluno,
       r.unidade_id,
       ae.data_hora_inicio,
       r.anotacao_pedagogica,
       r.devolutiva_familia,
       r.proximos_passos,
       r.status,
       r.criado_em
       -- leitura_de_conversao NAO entra aqui. Nunca.
  from public.lead_experimental_registros r
  join public.lead_experimental_aulas v on v.id = r.vinculo_id
  join public.lead_experimentais le on le.id = v.lead_experimental_id
  left join public.aulas_emusys ae on ae.id = v.aula_local_id
 where r.status <> 'descartado';

revoke all on public.vw_experimental_registro_comercial from public, anon, authenticated;
grant select on public.vw_experimental_registro_comercial to service_role;
revoke all on public.vw_experimental_registro_family_safe from public, anon;
grant select on public.vw_experimental_registro_family_safe to service_role, authenticated;
```

- [ ] **Passo 2: Escrever o teste**

O teste não olha conteúdo: olha o **catálogo**. Uma view que não tem a coluna não pode vazá-la, e é isso que se assere.

```sql
-- Teste da 037 — a fronteira e estrutural, verificavel no catalogo
create temp table _res(passo text, esperado text, obtido text) on commit drop;

insert into _res
select 'view comercial TEM leitura_de_conversao', 'sim',
       case when exists (select 1 from information_schema.columns
                          where table_schema='public'
                            and table_name='vw_experimental_registro_comercial'
                            and column_name='leitura_de_conversao')
            then 'sim' else 'nao' end;

insert into _res
select 'view family_safe NAO TEM leitura_de_conversao', 'nao',
       case when exists (select 1 from information_schema.columns
                          where table_schema='public'
                            and table_name='vw_experimental_registro_family_safe'
                            and column_name='leitura_de_conversao')
            then 'sim — VAZOU' else 'nao' end;

insert into _res
select 'family_safe nao tem NENHUMA coluna de conversao', '0',
       (select count(*)::text from information_schema.columns
         where table_schema='public'
           and table_name='vw_experimental_registro_family_safe'
           and column_name ilike '%conversao%');

insert into _res
select 'anon nao le a view comercial', 'sem privilegio',
       case when has_table_privilege('anon','public.vw_experimental_registro_comercial','select')
            then 'LE — vazou' else 'sem privilegio' end;

insert into _res
select 'family_safe expoe os 3 blocos family-safe', '3',
       (select count(*)::text from information_schema.columns
         where table_schema='public'
           and table_name='vw_experimental_registro_family_safe'
           and column_name in ('anotacao_pedagogica','devolutiva_familia','proximos_passos'));

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
```

- [ ] **Passo 3: Rodar até verde, matar o mutante**

```bash
node scripts/rodar-teste-sql.mjs supabase/migrations/037-views-registro-experimental.sql supabase/migrations/037-views-registro-experimental.test.sql

python3 - <<'PY'
src = open('supabase/migrations/037-views-registro-experimental.sql', encoding='utf-8').read()
# M1 — a coluna interna entra na view family-safe (o vazamento que a spec proibe)
m1 = src.replace("       r.status,\n       r.criado_em\n       -- leitura_de_conversao NAO entra aqui. Nunca.",
                 "       r.status,\n       r.criado_em,\n       r.leitura_de_conversao", 1)
assert m1 != src; open('supabase/migrations/037-m1.sql','w',encoding='utf-8').write(m1)
# M2 — anon ganha leitura da view comercial
m2 = src.replace("revoke all on public.vw_experimental_registro_comercial from public, anon, authenticated;",
                 "grant select on public.vw_experimental_registro_comercial to anon;", 1)
assert m2 != src; open('supabase/migrations/037-m2.sql','w',encoding='utf-8').write(m2)
print('2 mutantes gerados')
PY

for m in m1 m2; do
  echo "--- $m ---"
  node scripts/rodar-teste-sql.mjs supabase/migrations/037-$m.sql supabase/migrations/037-views-registro-experimental.test.sql | head -4
done
rm -f supabase/migrations/037-m?.sql
```

- [ ] **Passo 4: Aplicar e commitar**

```bash
node scripts/aplicar-sql.mjs supabase/migrations/037-views-registro-experimental.sql
git add supabase/migrations/037-views-registro-experimental.sql supabase/migrations/037-views-registro-experimental.test.sql
git commit -m "feat(037): duas views — family_safe nao TEM a coluna de conversao"
git push origin main
git log --oneline origin/main..HEAD | wc -l   # tem que dar 0
```

---

### Task 5: Migration 038 — confirmação amarra tudo numa transação

**Files:**
- Create: `supabase/migrations/038-confirmar-registro-experimental.sql`
- Create: `supabase/migrations/038-confirmar-registro-experimental.test.sql`

**Interfaces:**
- Consumes: `app_registrar_experimental` (Task 2), `fn_registrar_presenca_experimental` (Task 1), `fabio_enfileirar_aviso_comercial` (Task 3).
- Produces: `public.app_confirmar_registro_experimental(p_registro_id uuid, p_confirmado_por integer) returns jsonb` — devolve `{registro_id, presenca_gravada, notificacao_id, aviso_pulado}`.

Sem esta task, as três peças anteriores existem soltas: o registro nasce
`aguardando_confirmacao` e nada o move dali, a presença depende de alguém chamar a função
à mão, e o aviso nunca é enfileirado. A spec §5.1 exige que presença e aviso saiam **na
mesma transação** da confirmação — meia confirmação (presença sim, aviso não) é pior que
nenhuma, porque o comercial nunca fica sabendo e ninguém percebe.

- [ ] **Passo 1: Escrever a migration**

```sql
-- 038 — confirmar o registro: presenca + aviso na MESMA transacao
--
-- Meia confirmacao e o pior estado possivel: presenca gravada e comercial sem
-- saber, sem nada sinalizando. Por isso as duas escritas vivem numa funcao so
-- — se o aviso falhar, a confirmacao inteira volta atras.

create or replace function public.app_confirmar_registro_experimental(
  p_registro_id    uuid,
  p_confirmado_por integer
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_vinculo_id  bigint;
  v_status      text;
  v_origem      text;
  v_presenca_ok boolean;
  v_not_id      uuid;
begin
  select vinculo_id, status, origem
    into v_vinculo_id, v_status, v_origem
    from lead_experimental_registros
   where id = p_registro_id
     for update;

  if not found then
    raise exception 'registro_inexistente: %', p_registro_id;
  end if;

  if v_status = 'confirmado' then
    -- Idempotente: confirmar duas vezes nao duplica aviso nem regrava presenca.
    return jsonb_build_object('registro_id', p_registro_id, 'ja_confirmado', true);
  end if;

  if v_status = 'descartado' then
    raise exception 'registro_descartado: %', p_registro_id;
  end if;

  update lead_experimental_registros
     set status = 'confirmado', confirmado_em = now(), confirmado_por = p_confirmado_por,
         atualizado_em = now()
   where id = p_registro_id;

  -- Presenca com a fonte certa: registro pelo app e professor_la_teacher;
  -- por audio e fabio_audio. Ambos passam em fn_presenca_e_forte — e NENHUM
  -- deles e 'professor_app', que nao existe.
  select public.fn_registrar_presenca_experimental(
           v_vinculo_id, 'presente',
           case when v_origem = 'whatsapp' then 'fabio_audio' else 'professor_la_teacher' end)
    into v_presenca_ok;

  select public.fabio_enfileirar_aviso_comercial(p_registro_id) into v_not_id;

  return jsonb_build_object(
    'registro_id',    p_registro_id,
    'presenca_gravada', v_presenca_ok,
    'notificacao_id',  v_not_id,
    'aviso_pulado',    (v_not_id is null)
  );
end
$function$;

revoke all on function public.app_confirmar_registro_experimental(uuid,integer) from public, anon;
grant execute on function public.app_confirmar_registro_experimental(uuid,integer) to service_role, authenticated;
```

- [ ] **Passo 2: Escrever o teste**

```sql
-- Teste da 038 — confirmar grava presenca E avisa, ou nao faz nem uma coisa
create temp table _res(passo text, esperado text, obtido text) on commit drop;

insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000000380', 'ZZTESTE unidade 038', 'ZZTESTE038')
on conflict (id) do nothing;

insert into public.unidade_contato_comercial (unidade_id, nome, whatsapp)
values ('00000000-0000-4000-8000-000000000380', 'ZZTESTE Comercial 038', '5521900000038')
on conflict (unidade_id) do nothing;

insert into public.professores (id, nome) values (-38001, 'ZZTESTE Professor 038');
insert into public.leads (id, unidade_id, whatsapp, status) values
  (-38001, '00000000-0000-4000-8000-000000000380', '5521999380001', 'novo');
insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id)
values (-38001, -38001, 'ZZTESTE Confirma', '00000000-0000-4000-8000-000000000380',
        current_date+1, '10:00', 'experimental_agendada', -38001);
insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, categoria, professor_id, cancelada)
values (-38001, -938001, '00000000-0000-4000-8000-000000000380', current_date+1,
   (current_date+1 + time '10:00') at time zone 'America/Sao_Paulo', 'experimental', -38001, false);
insert into public.lead_experimental_aulas (lead_experimental_id, aula_local_id, estado, casado_por)
values (-38001, -38001, 'vinculado', 'chave_natural');

create temp table _conf(resultado jsonb) on commit drop;

do $$
declare v_vinc bigint; v_reg uuid; v_out jsonb;
begin
  select id into v_vinc from lead_experimental_aulas where lead_experimental_id=-38001;
  select public.app_registrar_experimental(v_vinc, 'trabalhou ritmo', 'foi bem',
           'seguir', 'quente') into v_reg;
  select public.app_confirmar_registro_experimental(v_reg, null) into v_out;
  insert into _conf values (v_out);
end $$;

-- Le o retorno DA CHAMADA QUE CONFIRMOU, nao de uma nova
insert into _res select 'confirmacao gravou presenca', 'true',
  (select resultado->>'presenca_gravada' from _conf);
insert into _res select 'confirmacao enfileirou aviso', 'false',
  (select resultado->>'aviso_pulado' from _conf);

insert into _res
select 'registro ficou confirmado', 'confirmado',
       (select r.status from lead_experimental_registros r
          join lead_experimental_aulas v on v.id=r.vinculo_id
         where v.lead_experimental_id=-38001);
insert into _res
select 'presenca nasceu de fonte FORTE', 'true',
       (select public.fn_presenca_e_forte(presenca_respondido_por)::text
          from lead_experimental_aulas where lead_experimental_id=-38001);
insert into _res
select 'presenca forte promoveu o estado', 'realizado',
       (select estado from lead_experimental_aulas where lead_experimental_id=-38001);

-- ── Idempotencia: confirmar 2x nao duplica aviso ───────────────────────────
do $$
declare v_reg uuid;
begin
  select r.id into v_reg from lead_experimental_registros r
    join lead_experimental_aulas v on v.id=r.vinculo_id
   where v.lead_experimental_id=-38001;
  perform public.app_confirmar_registro_experimental(v_reg, null);
end $$;

insert into _res
select 'confirmar 2x nao duplica aviso', '1',
       (select count(*)::text from fabio_notificacoes
         where referencia_tipo='lead_experimental_registro'
           and referencia_id=(select r.id::text from lead_experimental_registros r
                                join lead_experimental_aulas v on v.id=r.vinculo_id
                               where v.lead_experimental_id=-38001));

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
```

- [ ] **Passo 3: Rodar até verde, matar os mutantes**

```bash
node scripts/rodar-teste-sql.mjs supabase/migrations/038-confirmar-registro-experimental.sql supabase/migrations/038-confirmar-registro-experimental.test.sql

python3 - <<'PY'
src = open('supabase/migrations/038-confirmar-registro-experimental.sql', encoding='utf-8').read()

# M1 — confirma sem avisar o comercial (a meia confirmacao que a task existe pra impedir)
m1 = src.replace("  select public.fabio_enfileirar_aviso_comercial(p_registro_id) into v_not_id;",
                 "  v_not_id := null;", 1)
assert m1 != src; open('supabase/migrations/038-m1.sql','w',encoding='utf-8').write(m1)

# M2 — confirma sem gravar presenca
m2 = src.replace("""  select public.fn_registrar_presenca_experimental(
           v_vinculo_id, 'presente',
           case when v_origem = 'whatsapp' then 'fabio_audio' else 'professor_la_teacher' end)
    into v_presenca_ok;""", "  v_presenca_ok := false;", 1)
assert m2 != src; open('supabase/migrations/038-m2.sql','w',encoding='utf-8').write(m2)

# M3 — fonte fraca na confirmacao: presenca nasceria fantasma
m3 = src.replace("else 'professor_la_teacher' end)", "else 'emusys' end)", 1)
assert m3 != src; open('supabase/migrations/038-m3.sql','w',encoding='utf-8').write(m3)

# M4 — idempotencia quebrada: confirmar 2x duplica o aviso
m4 = src.replace("""  if v_status = 'confirmado' then
    -- Idempotente: confirmar duas vezes nao duplica aviso nem regrava presenca.
    return jsonb_build_object('registro_id', p_registro_id, 'ja_confirmado', true);
  end if;""", "", 1)
assert m4 != src; open('supabase/migrations/038-m4.sql','w',encoding='utf-8').write(m4)
print('4 mutantes gerados')
PY

for m in m1 m2 m3 m4; do
  echo "--- $m ---"
  node scripts/rodar-teste-sql.mjs supabase/migrations/038-$m.sql supabase/migrations/038-confirmar-registro-experimental.test.sql | head -4
done
rm -f supabase/migrations/038-m?.sql
```

- [ ] **Passo 4: Aplicar e commitar**

```bash
node scripts/aplicar-sql.mjs supabase/migrations/038-confirmar-registro-experimental.sql
git add supabase/migrations/038-confirmar-registro-experimental.sql supabase/migrations/038-confirmar-registro-experimental.test.sql
git commit -m "feat(038): confirmar registro grava presenca E avisa, na mesma transacao"
git push origin main
git log --oneline origin/main..HEAD | wc -l   # tem que dar 0
```

---

## Ordem e dependências

As tasks são sequenciais e cada uma depende da anterior estar **aplicada em produção** —
o runner de teste roda a migration da vez contra o banco real, então o que veio antes
precisa existir. Ordem: 034 → 035 → 036 → 037 → 038.

A 038 é a que amarra: sem ela, as quatro anteriores são peças corretas que não se falam.

## Depois destas cinco tasks

Fora do escopo deste plano, na ordem em que fazem sentido:

1. **Declarar falta na UI** — a spec §5.2 separa "declarar falta" (um toque, grava
   presença forte, avisa o comercial) de "registrar a aula" (formulário completo). O
   backend disto já sai pronto na Task 1 (`fn_registrar_presenca_experimental` com
   `p_status='falta'`); falta a tela e o aviso enxuto (sem blocos pedagógicos).
2. **Tela do professor** no LA Teacher, consumindo `app_registrar_experimental`.
3. **Tela do funil** no LA Report lendo `vw_experimental_registro_comercial` —
   **fazer `git pull` antes de tocar naquele repo**, ele anda muito.
4. **Cron do reconciliador** — segue desligado até a etapa própria de agendamento e
   observabilidade.
5. **Retorno ao professor + gamificação** — adiado pelo Alf; o dado já existe (a 033 grava
   o recibo de matrícula no vínculo).
6. **Tarefa #69** — filtro morto `'experimental_reagendada'` em 027c/027d/029.
