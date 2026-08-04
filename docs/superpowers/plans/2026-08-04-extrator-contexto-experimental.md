# Extrator de contexto da aula experimental — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** O professor abre a aula experimental sabendo quem vai receber — nome do responsável, nível, gosto musical e motivação, extraídos da conversa da Mila.

**Architecture:** `pg_cron` de hora em hora chama uma edge function que lê a conversa inteira no Chatwoot (paginando até o começo) mais o campo `observacoes`, trata com `gemini-3.6-flash` e grava JSON em `lead_experimentais.contexto_ia`. Uma view aplica a fronteira e `fabio_prontuario_aluno` compõe o bloco. O extrator roda em modo sombra até a qualidade ser conferida.

**Tech Stack:** Postgres/Supabase (projeto `ouqwbbermlzqqvtqwlul`), Deno edge functions, Gemini 3.6 Flash, Chatwoot API v1, harness de teste `scripts/rodar-teste-sql.mjs`.

**Spec:** `docs/superpowers/specs/2026-08-04-extrator-contexto-experimental-design.md`

## Global Constraints

- **Nunca escrever em `lead_experimentais.observacoes`** — aquele campo é do Emusys.
- **Vínculo com aluno é por `leads.aluno_id`** (319 preenchidos), nunca `lead_experimentais.aluno_id` (81).
- **`data_nascimento` no JSON, nunca `idade`** — idade é sempre `age(data_nascimento)` calculada na leitura.
- **Campos de dinheiro, negociação e recado interno não existem no schema de saída.** A estrutura é a fronteira, não o prompt.
- **A conversa é lida inteira, paginando com `before=<menor_id>`** até a API devolver vazio.
- **Extração vazia ou com erro nunca sobrescreve extração boa.**
- **Segredos vão para os secrets do Supabase**, nunca para o código.
- Toda função `security definer` nasce com EXECUTE para PUBLIC — **sempre `revoke` explícito**.
- Vocabulário fechado: `nivel_declarado` ∈ {`iniciante`,`ja_tocava`,`nao_informado`}; `de_quem_partiu` ∈ {`do aluno`,`dos pais`,`de terceiro`,`nao_informado`}; `atencao_conversao` ∈ {`alta`,`normal`,`nao_informado`}; `alertas[].tipo` ∈ {`agenda`,`saude_agenda`,`acessibilidade`}.

---

## File Structure

| Arquivo | Responsabilidade |
|---|---|
| `supabase/migrations/027-contexto-experimental.sql` | colunas + RPC de seleção + RPC de gravação com guarda |
| `supabase/migrations/027-contexto-experimental.test.sql` | teste das RPCs sobre dados reais |
| `scripts/mutantes-027.mjs` | mutantes da 027 |
| `supabase/functions/extrair-contexto-experimental/index.ts` | lê Chatwoot, chama Gemini, grava |
| `supabase/migrations/028-fabio-le-contexto-experimental.sql` | view com fronteira + composição no prontuário |
| `supabase/migrations/028-fabio-le-contexto-experimental.test.sql` | teste da fronteira e da composição |
| `scripts/mutantes-028.mjs` | mutantes da 028 |
| `package.json` | scripts `teste:027`, `teste:028`, `mutantes:027`, `mutantes:028` |

---

## Task 1: Colunas e RPCs de seleção e gravação

**Files:**
- Create: `supabase/migrations/027-contexto-experimental.sql`
- Create: `supabase/migrations/027-contexto-experimental.test.sql`
- Create: `scripts/mutantes-027.mjs`
- Modify: `package.json` (adicionar `teste:027` e `mutantes:027`)

**Interfaces:**
- Produces: `fn_experimentais_a_extrair(p_dias integer, p_limite integer)` → tabela com `lead_experimental_id integer, nome_aluno text, telefone text, data_experimental date, curso text, observacoes text, ultima_mensagem_id bigint`
- Produces: `fabio_gravar_contexto_experimental(p_lead_experimental_id integer, p_contexto jsonb)` → `boolean` (true = gravou)

- [ ] **Step 1: Escrever a migration**

Criar `supabase/migrations/027-contexto-experimental.sql`:

```sql
-- 027 — a experimental passa a carregar o contexto extraído da conversa
--
-- POR QUE ISSO EXISTE
-- A conversa da Mila com a família tem 35 a 56 mensagens e cobre nome do
-- responsável, idade, nível, gosto musical e motivação. O que sobrevive disso
-- é o campo `observacoes` do Emusys: no melhor caso oito palavras digitadas com
-- pressa. Nos irmãos Andrade o campo está vazio, e a conversa dizia que os dois
-- já tocavam piano em Portugal e pediram para voltar.
--
-- `contexto_ia` é VIZINHO de `observacoes`, não substituto. O Emusys é dono do
-- `observacoes` e reescreve a cada webhook; se o extrator gravasse lá, a
-- extração sumiria no próximo evento e ninguém saberia quem escreveu o quê.

alter table public.lead_experimentais
  add column if not exists contexto_ia    jsonb,
  add column if not exists contexto_ia_em timestamptz;

comment on column public.lead_experimentais.contexto_ia is
'Contexto pedagogico extraido da conversa da Mila + observacoes, por IA. Escrito SO pelo extrator. Nunca confundir com observacoes, que e do Emusys.';

-- ─────────────────────────────────────────────────────────────────────────
-- Quem precisa de extração agora
--
-- Releitura é por ID de mensagem, não por data: a conversa continua depois do
-- agendamento (os Andrade cancelaram na manhã do dia da aula) e mensagens do
-- mesmo dia fariam o extrator se considerar atualizado.
--
-- `p_ultima_mensagem_id` chega da edge function, que é quem fala com o
-- Chatwoot. O banco não sai para a rede.

create or replace function public.fn_experimentais_a_extrair(
  p_dias   integer default 7,
  p_limite integer default 50
)
returns table (
  lead_experimental_id integer,
  nome_aluno           text,
  telefone             text,
  data_experimental    date,
  curso                text,
  observacoes          text,
  extraido_ate_id      bigint
)
language sql
stable
security definer
set search_path to 'public'
as $function$
  select le.id,
         le.nome_aluno::text,
         coalesce(nullif(btrim(l.whatsapp), ''), nullif(btrim(l.telefone), ''))::text,
         le.data_experimental,
         c.nome::text,
         nullif(btrim(le.observacoes), '')::text,
         nullif(le.contexto_ia -> 'procedencia' ->> 'ultima_mensagem_id', '')::bigint
    from lead_experimentais le
    left join leads  l on l.id = le.lead_id
    left join cursos c on c.id = le.curso_interesse_id
   where le.data_experimental between current_date and current_date + p_dias
     and coalesce(nullif(btrim(l.whatsapp), ''), nullif(btrim(l.telefone), '')) is not null
   order by le.data_experimental, le.horario_experimental
   limit p_limite;
$function$;

revoke all on function public.fn_experimentais_a_extrair(integer, integer) from public;
grant execute on function public.fn_experimentais_a_extrair(integer, integer) to service_role;

comment on function public.fn_experimentais_a_extrair(integer, integer) is
'Experimentais dos proximos p_dias com telefone. Devolve extraido_ate_id para a edge function decidir se relê a conversa.';

-- ─────────────────────────────────────────────────────────────────────────
-- Gravação com guarda
--
-- Falha do Gemini, JSON quebrado ou conversa sem conteúdo NÃO podem apagar uma
-- extração boa. A regra é: só grava se vier conteúdo E se a leitura for mais
-- nova que a que já está lá.

create or replace function public.fabio_gravar_contexto_experimental(
  p_lead_experimental_id integer,
  p_contexto             jsonb
)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_novo_id  bigint;
  v_atual_id bigint;
  v_tem_algo boolean;
begin
  if p_contexto is null or jsonb_typeof(p_contexto) <> 'object' then
    return false;
  end if;

  -- conteúdo de verdade: pelo menos um dos blocos úteis preenchido.
  -- `procedencia` sozinha não conta -- senão uma extração que não achou nada
  -- passaria por cima de uma que achou.
  v_tem_algo := (p_contexto -> 'recepcao'          is not null and p_contexto -> 'recepcao' <> 'null'::jsonb)
             or (p_contexto -> 'quem_e_esse_aluno' is not null and p_contexto -> 'quem_e_esse_aluno' <> 'null'::jsonb)
             or (jsonb_typeof(p_contexto -> 'ganchos_de_conexao') = 'array'
                 and jsonb_array_length(p_contexto -> 'ganchos_de_conexao') > 0)
             or (jsonb_typeof(p_contexto -> 'alertas') = 'array'
                 and jsonb_array_length(p_contexto -> 'alertas') > 0);

  if not v_tem_algo then
    return false;
  end if;

  v_novo_id := nullif(p_contexto -> 'procedencia' ->> 'ultima_mensagem_id', '')::bigint;
  if v_novo_id is null then
    return false;
  end if;

  select nullif(contexto_ia -> 'procedencia' ->> 'ultima_mensagem_id', '')::bigint
    into v_atual_id
    from lead_experimentais
   where id = p_lead_experimental_id;

  if v_atual_id is not null and v_novo_id <= v_atual_id then
    return false;
  end if;

  update lead_experimentais
     set contexto_ia    = p_contexto,
         contexto_ia_em = now()
   where id = p_lead_experimental_id;

  return found;
end
$function$;

revoke all on function public.fabio_gravar_contexto_experimental(integer, jsonb) from public;
grant execute on function public.fabio_gravar_contexto_experimental(integer, jsonb) to service_role;

comment on function public.fabio_gravar_contexto_experimental(integer, jsonb) is
'Grava contexto_ia. Recusa payload vazio, sem procedencia.ultima_mensagem_id, ou mais velho que o ja gravado. Extracao ruim nunca apaga extracao boa.';
```

- [ ] **Step 2: Escrever o teste**

Criar `supabase/migrations/027-contexto-experimental.test.sql`:

```sql
-- Teste da 027 — colunas e guardas do contexto da experimental.
-- Rodar com: npm run teste:027
--
-- O runner abre a transação e dá ROLLBACK: nada do que este teste escreve
-- sobrevive.

create temp table _falhas(passo text, esperado text, obtido text) on commit drop;
create function pg_temp.checar(p text, e text, o text) returns void language plpgsql as $c$
begin if e is distinct from o then insert into _falhas values (p, coalesce(e,'(null)'), coalesce(o,'(null)')); end if; end $c$;

do $t$
declare
  v_id integer;
  v_ok boolean;
  v_lido jsonb;
  v_base jsonb := jsonb_build_object(
    'recepcao', jsonb_build_object('responsavel','Melissa','aluno','Daniela',
                                   'data_nascimento','2013-07-25'),
    'quem_e_esse_aluno', jsonb_build_object('nivel_declarado','ja_tocava'),
    'ganchos_de_conexao', jsonb_build_array('ja se interessou por canto'),
    'procedencia', jsonb_build_object('ultima_mensagem_id','1000','modelo','gemini-3.6-flash')
  );
begin
  -- ===== 1. as colunas existem =====
  perform pg_temp.checar('1. coluna contexto_ia existe','true',
    (select exists(select 1 from information_schema.columns
       where table_schema='public' and table_name='lead_experimentais'
         and column_name='contexto_ia' and data_type='jsonb')::text));
  perform pg_temp.checar('2. coluna contexto_ia_em existe','true',
    (select exists(select 1 from information_schema.columns
       where table_schema='public' and table_name='lead_experimentais'
         and column_name='contexto_ia_em')::text));

  -- ===== 3. um caso real para trabalhar =====
  select id into v_id from lead_experimentais
   where data_experimental >= current_date order by id limit 1;
  if v_id is null then
    insert into _falhas values ('3. setup','uma experimental futura','nenhuma');
    return;
  end if;

  -- ===== 4. grava o que tem conteúdo =====
  v_ok := public.fabio_gravar_contexto_experimental(v_id, v_base);
  perform pg_temp.checar('4. grava contexto com conteudo','true', v_ok::text);
  select contexto_ia into v_lido from lead_experimentais where id = v_id;
  perform pg_temp.checar('5. e o conteudo esta la','ja_tocava',
    v_lido -> 'quem_e_esse_aluno' ->> 'nivel_declarado');
  perform pg_temp.checar('6. carimba contexto_ia_em','true',
    (select (contexto_ia_em is not null)::text from lead_experimentais where id=v_id));

  -- ===== 7. vazio NAO apaga o que ja existe =====
  -- O caso real: o Gemini falha ou a conversa nao tem nada. A extracao ruim
  -- nao pode passar por cima da boa.
  v_ok := public.fabio_gravar_contexto_experimental(v_id,
            jsonb_build_object('procedencia', jsonb_build_object('ultima_mensagem_id','9999')));
  perform pg_temp.checar('7. payload so com procedencia e recusado','false', v_ok::text);
  select contexto_ia into v_lido from lead_experimentais where id = v_id;
  perform pg_temp.checar('8. e o conteudo bom continua la','ja_tocava',
    v_lido -> 'quem_e_esse_aluno' ->> 'nivel_declarado');

  -- ===== 9. null e nao-objeto sao recusados =====
  perform pg_temp.checar('9. null e recusado','false',
    public.fabio_gravar_contexto_experimental(v_id, null)::text);
  perform pg_temp.checar('10. array e recusado','false',
    public.fabio_gravar_contexto_experimental(v_id, '[]'::jsonb)::text);

  -- ===== 11. leitura mais VELHA nao sobrescreve =====
  v_ok := public.fabio_gravar_contexto_experimental(v_id,
            jsonb_set(v_base, '{procedencia,ultima_mensagem_id}', '"500"'));
  perform pg_temp.checar('11. mensagem mais velha e recusada','false', v_ok::text);

  -- ===== 12. leitura mais NOVA sobrescreve =====
  v_ok := public.fabio_gravar_contexto_experimental(v_id,
            jsonb_set(jsonb_set(v_base, '{procedencia,ultima_mensagem_id}', '"2000"'),
                      '{quem_e_esse_aluno,nivel_declarado}', '"iniciante"'));
  perform pg_temp.checar('12. mensagem mais nova grava','true', v_ok::text);
  select contexto_ia into v_lido from lead_experimentais where id = v_id;
  perform pg_temp.checar('13. e o valor foi atualizado','iniciante',
    v_lido -> 'quem_e_esse_aluno' ->> 'nivel_declarado');

  -- ===== 14. sem procedencia.ultima_mensagem_id e recusado =====
  perform pg_temp.checar('14. sem ultima_mensagem_id e recusado','false',
    public.fabio_gravar_contexto_experimental(v_id, v_base - 'procedencia')::text);

  -- ===== 15. o campo do Emusys NAO foi tocado =====
  -- A regra que nao pode ser afrouxada: observacoes tem dono.
  perform pg_temp.checar('15. observacoes intacto','true',
    (select (observacoes is not distinct from
       (select observacoes from lead_experimentais where id=v_id)))::text);

exception when others then
  insert into _falhas values ('excecao','sem excecao', sqlerrm);
end $t$;

-- ===== a selecao de quem extrair =====
do $t2$
declare v_n integer; v_sem_tel integer;
begin
  select count(*) into v_n from public.fn_experimentais_a_extrair(7, 50);
  perform pg_temp.checar('16. a selecao devolve linhas','true', (v_n > 0)::text);

  -- ninguem sem telefone: a edge function nao teria como buscar a conversa
  select count(*) into v_sem_tel from public.fn_experimentais_a_extrair(7, 50)
   where telefone is null or btrim(telefone) = '';
  perform pg_temp.checar('17. ninguem sem telefone','0', v_sem_tel::text);

  -- janela respeitada
  select count(*) into v_sem_tel from public.fn_experimentais_a_extrair(7, 50)
   where data_experimental < current_date or data_experimental > current_date + 7;
  perform pg_temp.checar('18. janela de 7 dias respeitada','0', v_sem_tel::text);

  -- p_dias=0 traz so hoje
  select count(*) into v_sem_tel from public.fn_experimentais_a_extrair(0, 50)
   where data_experimental <> current_date;
  perform pg_temp.checar('19. p_dias=0 traz so hoje','0', v_sem_tel::text);

  -- anon nao executa nenhuma das duas
  perform pg_temp.checar('20. anon nao executa a selecao','false',
    has_function_privilege('anon','public.fn_experimentais_a_extrair(integer,integer)','EXECUTE')::text);
  perform pg_temp.checar('21. anon nao executa a gravacao','false',
    has_function_privilege('anon','public.fabio_gravar_contexto_experimental(integer,jsonb)','EXECUTE')::text);

exception when others then
  insert into _falhas values ('excecao selecao','sem excecao', sqlerrm);
end $t2$;

select json_build_object('teste','027-contexto-experimental',
  'falhas',(select count(*) from _falhas),
  'detalhe', coalesce((select json_agg(json_build_object('passo',passo,'esperado',esperado,'obtido',obtido)) from _falhas),'[]'::json)) as resumo;
```

- [ ] **Step 3: Adicionar os scripts ao package.json**

Em `package.json`, dentro de `"scripts"`, adicionar após a linha do `teste:026`:

```json
"teste:027": "node scripts/rodar-teste-sql.mjs supabase/migrations/027-contexto-experimental.sql supabase/migrations/027-contexto-experimental.test.sql",
"mutantes:027": "node scripts/mutantes-027.mjs",
```

- [ ] **Step 4: Rodar o teste e verificar que passa**

Run: `npm run teste:027`
Expected: `falhas: 0` no resumo, com 21 verificações.

- [ ] **Step 5: Escrever os mutantes**

Criar `scripts/mutantes-027.mjs`:

```js
import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/027-contexto-experimental.sql'
const TESTE = 'supabase/migrations/027-contexto-experimental.test.sql'
const TEMP = 'supabase/migrations/_mutante-027.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'extracao vazia sobrescreve extracao boa (fail open)',
    pega: 'passos 7 e 8',
    de: '  if not v_tem_algo then\n    return false;\n  end if;\n',
    para: '',
  },
  {
    nome: 'leitura mais velha sobrescreve a mais nova',
    pega: 'passo 11',
    de: '  if v_atual_id is not null and v_novo_id <= v_atual_id then\n    return false;\n  end if;\n',
    para: '',
  },
  {
    nome: 'aceita payload sem procedencia (perde a rastreabilidade)',
    pega: 'passo 14',
    de: '  if v_novo_id is null then\n    return false;\n  end if;\n',
    para: '',
  },
  {
    nome: 'so procedencia ja conta como conteudo',
    pega: 'passo 7',
    de: "  v_tem_algo := (p_contexto -> 'recepcao'",
    para: "  v_tem_algo := true or (p_contexto -> 'recepcao'",
  },
  {
    nome: 'selecao traz quem nao tem telefone',
    pega: 'passo 17',
    de: "     and coalesce(nullif(btrim(l.whatsapp), ''), nullif(btrim(l.telefone), '')) is not null\n",
    para: '',
  },
  {
    nome: 'janela ignora a data (varredura cega)',
    pega: 'passos 18 e 19',
    de: '   where le.data_experimental between current_date and current_date + p_dias',
    para: '   where le.data_experimental >= current_date - 3650',
  },
  {
    nome: 'a gravacao fica exposta ao anon',
    pega: 'passo 21',
    de: 'revoke all on function public.fabio_gravar_contexto_experimental(integer, jsonb) from public;',
    para: '',
  },
  {
    // O campo `observacoes` e do Emusys, que o reescreve a cada webhook.
    // Escrever la faz a extracao sumir no proximo evento.
    nome: 'grava em observacoes (colide com o Emusys)',
    pega: 'passo 15',
    de: '     set contexto_ia    = p_contexto,\n         contexto_ia_em = now()',
    para: "     set observacoes    = p_contexto::text,\n         contexto_ia_em = now()",
  },
]

let previstos = 0
for (const m of MUTANTES) {
  if (!fonte.includes(m.de)) {
    console.log(`AVISO  "${m.nome}" — ancora nao encontrada, mutante NAO aplicado`)
    continue
  }
  writeFileSync(TEMP, fonte.replace(m.de, m.para))
  let passou = true
  try { execFileSync('node', ['scripts/rodar-teste-sql.mjs', TEMP, TESTE], { stdio: 'pipe' }) } catch { passou = false }
  if (!passou) { previstos++; console.log(`OK   morto: ${m.nome}  (${m.pega})`) }
  else console.log(`FALHA  SOBREVIVEU: ${m.nome}  (${m.pega})`)
}
try { unlinkSync(TEMP) } catch {}
console.log(`\n${previstos}/${MUTANTES.length} mutantes mortos`)
process.exitCode = previstos === MUTANTES.length ? 0 : 1
```

- [ ] **Step 6: Rodar os mutantes**

Run: `npm run mutantes:027`
Expected: `7/7 mutantes mortos`

Se algum sobreviver, o teste é decoração naquele ponto — **corrigir o teste, não o mutante**. Verificação sobre conjunto vazio passa sempre: conferir se o passo que deveria pegar o mutante tem dado de verdade.

- [ ] **Step 7: Aplicar em produção**

Aplicar `027-contexto-experimental.sql` no projeto `ouqwbbermlzqqvtqwlul` via `apply_migration`.

Verificar depois:
```sql
select count(*) from public.fn_experimentais_a_extrair(7, 50);
```
Expected: número maior que zero (hoje são 17 experimentais futuras).

- [ ] **Step 8: Commit**

```bash
git add supabase/migrations/027-contexto-experimental.sql supabase/migrations/027-contexto-experimental.test.sql scripts/mutantes-027.mjs package.json
git commit -m "feat(027): colunas e guardas do contexto da experimental

contexto_ia e vizinho de observacoes, nao substituto: o Emusys reescreve
observacoes a cada webhook e a extracao sumiria no proximo evento.

fabio_gravar_contexto_experimental recusa payload vazio, sem
procedencia.ultima_mensagem_id, ou mais velho que o gravado -- extracao
ruim nunca apaga extracao boa. Releitura por ID de mensagem e nao por data:
os Andrade cancelaram na manha do dia da aula.

21 verificacoes, 7/7 mutantes mortos."
```

---

## Task 2: Edge function em modo sombra

**Files:**
- Create: `supabase/functions/extrair-contexto-experimental/index.ts`

**Interfaces:**
- Consumes: `fn_experimentais_a_extrair(integer, integer)`, `fabio_gravar_contexto_experimental(integer, jsonb)` (Task 1)
- Produces: endpoint `POST /functions/v1/extrair-contexto-experimental`, body `{"dias": 7, "limite": 50}` (ambos opcionais), resposta `{"processados": N, "gravados": N, "pulados": N, "erros": N}`

- [ ] **Step 1: Escrever a edge function**

Criar `supabase/functions/extrair-contexto-experimental/index.ts`:

```ts
// Edge Function: extrair-contexto-experimental
//
// Lê a conversa da Mila no Chatwoot, trata com Gemini e grava o contexto
// pedagógico em lead_experimentais.contexto_ia.
//
// EXTRATOR_DRY_RUN=true (default) => extrai e LOGA, mas não grava.
//
// ⚠️ A paginação até o começo da conversa NÃO é detalhe. A API do Chatwoot
// devolve as ~20 mensagens mais recentes, e a qualificação da Mila está sempre
// nas PRIMEIRAS. Quem ler só a última página captura "pode ser quarta?" e perde
// idade, nível, gosto musical e motivação — que é o produto inteiro.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const CHATWOOT_URL = Deno.env.get("CHATWOOT_URL") ?? "https://crmchat.agenticflowio.com.br";
const CHATWOOT_ACCOUNT = Deno.env.get("CHATWOOT_ACCOUNT_ID") ?? "5";
const CHATWOOT_TOKEN = Deno.env.get("CHATWOOT_TOKEN") ?? "";
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const GEMINI_MODEL = "gemini-3.6-flash";
const DRY_RUN = (Deno.env.get("EXTRATOR_DRY_RUN") ?? "true") === "true";

// O Cloudflare na frente do Chatwoot devolve 1010 para User-Agent de script.
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
           "(KHTML, like Gecko) Chrome/126.0 Safari/537.36";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

async function chatwoot(path: string): Promise<any> {
  const r = await fetch(`${CHATWOOT_URL}/api/v1/accounts/${CHATWOOT_ACCOUNT}${path}`, {
    headers: { api_access_token: CHATWOOT_TOKEN, "User-Agent": UA },
  });
  if (!r.ok) throw new Error(`chatwoot ${path} -> HTTP ${r.status}`);
  return await r.json();
}

/** Só os dígitos finais: o Chatwoot guarda +5521..., o lead guarda 5521... */
function digitos(tel: string): string {
  return (tel || "").replace(/\D/g, "").slice(-8);
}

async function conversaInteira(telefone: string) {
  const busca = await chatwoot(`/contacts/search?q=${encodeURIComponent(digitos(telefone))}`);
  const contato = (busca?.payload ?? [])[0];
  if (!contato) return null;

  const convs = await chatwoot(`/contacts/${contato.id}/conversations`);
  const conversa = (convs?.payload ?? [])[0];
  if (!conversa) return null;

  const tudo: any[] = [];
  let antes: number | null = null;
  for (let i = 0; i < 15; i++) {
    const q = antes ? `?before=${antes}` : "";
    const pagina = await chatwoot(`/conversations/${conversa.id}/messages${q}`);
    const arr: any[] = pagina?.payload ?? [];
    if (!arr.length) break;
    const vistos = new Set(tudo.map((m) => m.id));
    const novos = arr.filter((m) => !vistos.has(m.id));
    if (!novos.length) break;
    tudo.unshift(...novos);
    antes = Math.min(...arr.map((m) => m.id));
  }
  return { contato, conversa, mensagens: tudo };
}

function transcrever(mensagens: any[]): string {
  const linhas: string[] = [];
  for (const m of mensagens) {
    if (m.message_type === 2) continue; // atividade do sistema
    const texto = String(m.content ?? "").replace(/\s+/g, " ").trim();
    if (!texto) continue;
    const bot = String(m.sender?.type ?? "").toLowerCase().includes("bot");
    const quem = m.message_type === 0 ? "FAMILIA" : (bot ? "MILA" : "ESCOLA");
    linhas.push(`${quem}: ${texto.slice(0, 500)}`);
  }
  return linhas.join("\n").slice(0, 24000);
}

const SCHEMA_SAIDA = {
  type: "object",
  properties: {
    recepcao: {
      type: "object",
      properties: {
        responsavel: { type: "string", nullable: true },
        aluno: { type: "string", nullable: true },
        data_nascimento: { type: "string", nullable: true },
        junto_com: { type: "string", nullable: true },
      },
    },
    quem_e_esse_aluno: {
      type: "object",
      properties: {
        nivel_declarado: { type: "string", enum: ["iniciante", "ja_tocava", "nao_informado"] },
        historia: { type: "string", nullable: true },
        de_quem_partiu: { type: "string", enum: ["do aluno", "dos pais", "de terceiro", "nao_informado"] },
      },
    },
    ganchos_de_conexao: { type: "array", items: { type: "string" } },
    para_a_devolutiva: {
      type: "object",
      properties: {
        o_que_a_familia_espera: { type: "string", nullable: true },
        atencao_conversao: { type: "string", enum: ["alta", "normal", "nao_informado"] },
        porque: { type: "string", nullable: true },
      },
    },
    apoio_declarado: { type: "string", nullable: true },
    alertas: {
      type: "array",
      items: {
        type: "object",
        properties: {
          tipo: { type: "string", enum: ["agenda", "saude_agenda", "acessibilidade"] },
          texto: { type: "string" },
        },
        required: ["tipo", "texto"],
      },
    },
  },
  required: ["recepcao", "quem_e_esse_aluno", "ganchos_de_conexao", "para_a_devolutiva", "alertas"],
};

function prompt(transcricao: string, observacoes: string | null, curso: string | null): string {
  return `Você lê a conversa de agendamento de uma aula experimental na LA Music
e prepara o professor que vai dar essa aula.

O professor conduz a aula em cinco momentos: recebe o aluno e o responsável pelo
primeiro nome, faz um aquecimento, cria conexão com o aluno, encerra elogiando, e
dá uma devolutiva ao responsável. Sua saída alimenta esses momentos.

REGRAS QUE NÃO SE NEGOCIAM

1. NUNCA escreva valor de mensalidade, forma de pagamento, desconto, negociação
   ou qualquer menção a dinheiro. Se a família falou de preço, isso só pode
   aparecer como atencao_conversao="alta" com o porquê em UMA frase sem cifra.
2. NUNCA repasse recado operacional interno da escola (ex.: "ajustar data de
   nascimento", "lançamento fictício para concluir cadastro").
3. Motivo de saúde entra APENAS como alerta tipo "saude_agenda" descrevendo o
   efeito na agenda (ex.: "pediu remarcar por motivo de saúde"). Nunca nomeie
   doença nem diagnóstico da criança.
4. apoio_declarado é escrito em linguagem de CONDUÇÃO, não de rótulo. Certo:
   "responde melhor a instrução curta, uma de cada vez; os pais relataram
   suporte nível 1". Errado: "autista nível 1".
5. NÃO calcule nem escreva idade. Devolva data_nascimento no formato AAAA-MM-DD
   quando a família tiver informado. A idade é calculada depois, porque o texto
   envelhece e a data não.
6. O que não foi dito fica null ou "nao_informado". Não invente, não deduza
   personalidade, não preencha por simpatia. Vazio honesto é resposta.

O QUE PROCURAR
- recepcao: primeiro nome do responsável e do aluno, como serão chamados.
- quem_e_esse_aluno: se já tocou antes, a história em uma frase, e de quem
  partiu a vontade (do aluno, dos pais, de terceiro).
- ganchos_de_conexao: 1 a 3 coisas CONCRETAS para o professor puxar na aula —
  o que a criança gosta de ouvir ou cantar, o que já tentou, o que a encanta.
- para_a_devolutiva: o que a família espera ouvir no fim.
- alertas: mudanças de agenda, cancelamentos, restrição de horário.

Curso da experimental: ${curso ?? "não informado"}

Observação que a recepção digitou (pode estar vazia ou desatualizada):
${observacoes ?? "(vazia)"}

Conversa completa:
${transcricao}`;
}

async function extrair(transcricao: string, observacoes: string | null, curso: string | null) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`;
  const r = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt(transcricao, observacoes, curso) }] }],
      generationConfig: {
        temperature: 0.2,
        maxOutputTokens: 1200,
        responseMimeType: "application/json",
        responseSchema: SCHEMA_SAIDA,
      },
    }),
  });
  if (!r.ok) throw new Error(`gemini HTTP ${r.status}: ${(await r.text()).slice(0, 300)}`);
  const j = await r.json();
  const partes: any[] = j?.candidates?.[0]?.content?.parts ?? [];
  const texto = partes.map((p) => (typeof p?.text === "string" ? p.text : "")).join("").trim();
  if (!texto) throw new Error("gemini devolveu vazio");
  return JSON.parse(texto);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const sb = createClient(SUPABASE_URL, SERVICE_KEY);
  let dias = 7, limite = 50;
  try {
    const body = await req.json();
    if (typeof body?.dias === "number") dias = body.dias;
    if (typeof body?.limite === "number") limite = body.limite;
  } catch (_e) { /* body vazio é válido */ }

  const { data: alvos, error } = await sb.rpc("fn_experimentais_a_extrair",
    { p_dias: dias, p_limite: limite });
  if (error) {
    return new Response(JSON.stringify({ erro: error.message }), {
      status: 500, headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  let gravados = 0, pulados = 0, erros = 0;
  const detalhes: any[] = [];

  for (const alvo of alvos ?? []) {
    try {
      const conv = await conversaInteira(alvo.telefone);
      if (!conv || !conv.mensagens.length) {
        pulados++;
        detalhes.push({ id: alvo.lead_experimental_id, acao: "sem_conversa" });
        continue;
      }
      const ultimaId = Math.max(...conv.mensagens.map((m: any) => m.id));
      if (alvo.extraido_ate_id && Number(alvo.extraido_ate_id) >= ultimaId) {
        pulados++;
        detalhes.push({ id: alvo.lead_experimental_id, acao: "sem_mensagem_nova" });
        continue;
      }

      const bruto = await extrair(transcrever(conv.mensagens), alvo.observacoes, alvo.curso);
      const contexto = {
        ...bruto,
        procedencia: {
          fonte: "conversa Mila + recepcao",
          contato_id: conv.contato.id,
          conversa_id: conv.conversa.id,
          ultima_mensagem_id: String(ultimaId),
          mensagens_lidas: conv.mensagens.length,
          modelo: GEMINI_MODEL,
          extraido_em: new Date().toISOString(),
        },
      };

      if (DRY_RUN) {
        pulados++;
        detalhes.push({ id: alvo.lead_experimental_id, acao: "sombra", contexto });
      } else {
        const { data: ok } = await sb.rpc("fabio_gravar_contexto_experimental", {
          p_lead_experimental_id: alvo.lead_experimental_id,
          p_contexto: contexto,
        });
        if (ok) { gravados++; detalhes.push({ id: alvo.lead_experimental_id, acao: "gravado" }); }
        else { pulados++; detalhes.push({ id: alvo.lead_experimental_id, acao: "recusado_pela_guarda" }); }
      }
    } catch (e: any) {
      erros++;
      detalhes.push({ id: alvo.lead_experimental_id, acao: "erro", erro: String(e?.message ?? e).slice(0, 300) });
    }
  }

  // Falha silenciosa com HTTP 200 já custou caro duas vezes neste projeto
  // (o Fábio surdo a áudio e a notificar-anamnese com o canal morto desde
  // 11/07). Toda rodada deixa rastro.
  await sb.from("automacao_log").insert({
    evento: "contexto_experimental",
    acao: DRY_RUN ? "extraido_sombra" : "extraido",
    detalhes: { processados: (alvos ?? []).length, gravados, pulados, erros, itens: detalhes },
    workflow_id: "extrair-contexto-experimental",
    execution_id: new Date().toISOString(),
  });

  return new Response(
    JSON.stringify({ dry_run: DRY_RUN, processados: (alvos ?? []).length, gravados, pulados, erros, detalhes }),
    { headers: { ...cors, "Content-Type": "application/json" } },
  );
});
```

- [ ] **Step 2: Configurar os secrets**

Pedir ao Hugo um usuário do Chatwoot com papel **apenas de leitura** e usar o token dele. Configurar no projeto `ouqwbbermlzqqvtqwlul`:

- `CHATWOOT_TOKEN` — token do usuário de leitura
- `CHATWOOT_URL` — `https://crmchat.agenticflowio.com.br`
- `CHATWOOT_ACCOUNT_ID` — `5`
- `EXTRATOR_DRY_RUN` — `true`

`GEMINI_API_KEY` já existe no projeto (usada pela `notificar-anamnese`).

Nunca colocar valor de token no arquivo `index.ts`.

- [ ] **Step 3: Deploy da função**

Fazer deploy de `extrair-contexto-experimental` com `verify_jwt: true`.

- [ ] **Step 4: Rodar em sombra e conferir a saída**

Invocar a função com `{"dias": 7, "limite": 5}` e ler a resposta.

Expected: `"dry_run": true`, e em `detalhes` os itens com `acao: "sombra"` trazendo o `contexto` montado.

Conferir manualmente nos 5 primeiros:
1. Nenhum campo com valor, mensalidade, desconto ou negociação.
2. Nenhum recado interno da recepção.
3. `recepcao.data_nascimento` no formato AAAA-MM-DD, e **nenhum campo de idade**.
4. `ganchos_de_conexao` com coisas concretas, não genéricas ("gosta de música" não serve).
5. Quem não tem conversa aparece como `sem_conversa`, não com contexto inventado.

Se algum dos cinco falhar, ajustar o prompt e repetir antes de seguir.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/extrair-contexto-experimental/index.ts
git commit -m "feat: extrator de contexto da experimental (modo sombra)

Le a conversa INTEIRA no Chatwoot paginando com before=<menor_id> ate o
comeco -- a qualificacao da Mila esta sempre nas primeiras mensagens, e
quem le so a ultima pagina captura logistica e perde o produto inteiro.

Saida com responseSchema do Gemini: campo de dinheiro nao existe no schema,
entao nao ha onde escreve-lo. A estrutura e a fronteira, nao o prompt -- a
notificar-anamnese tem a regra no prompt e vaza diagnostico pela parte que
nao passa por IA.

EXTRATOR_DRY_RUN=true por padrao. Toda rodada registra em automacao_log."
```

---

## Task 3: Cron e primeira rodada real

**Files:**
- Create: `supabase/migrations/027b-cron-extrator-contexto.sql`
- Modify: `package.json` (adicionar `teste:027b` não é necessário — ver Step 3)

**Interfaces:**
- Consumes: edge function `extrair-contexto-experimental` (Task 2)
- Produces: job `pg_cron` chamado `extrair-contexto-experimental-hora`

- [ ] **Step 1: Escrever a migration do cron**

Criar `supabase/migrations/027b-cron-extrator-contexto.sql`:

```sql
-- 027b — o extrator ganha quem o chame
--
-- ⚠️ O defeito que apareceu SEIS vezes neste projeto é "função pronta, chamador
-- nenhum": a 020, a ceifar_travadas, o fabio-notification-worker.timer que
-- existia disabled, a tela sem porta de entrada na Home e as RPCs de manutenção
-- da 025. Esta migration existe para o extrator não virar a sétima.

select cron.schedule(
  'extrair-contexto-experimental-hora',
  '7 * * * *',   -- 7 minutos depois da hora, longe do topo onde tudo dispara
  $$
  select net.http_post(
    url     := 'https://ouqwbbermlzqqvtqwlul.supabase.co/functions/v1/extrair-contexto-experimental',
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'Authorization', 'Bearer ' || current_setting('app.service_role_key', true)),
    body    := jsonb_build_object('dias', 7, 'limite', 50),
    timeout_milliseconds := 120000
  );
  $$
);
```

- [ ] **Step 2: Verificar como os outros jobs passam a chave**

Antes de aplicar, ler como o job existente `processar-conversa-evasao-cada-minuto` monta o header — é o padrão da casa e a chave pode vir de outro lugar que não `app.service_role_key`.

Run:
```sql
select jobname, schedule, left(command, 600) from cron.job
 where command ilike '%functions/v1%' limit 3;
```

Ajustar a migration para usar o mesmo mecanismo que os jobs existentes usam. **Não inventar um mecanismo novo de credencial.**

- [ ] **Step 3: Aplicar e confirmar que o job existe e roda**

Aplicar a migration. Depois confirmar:

```sql
select jobname, schedule, active from cron.job
 where jobname = 'extrair-contexto-experimental-hora';
```
Expected: uma linha, `active = true`.

Esperar a próxima execução e conferir que ela aconteceu de verdade:

```sql
select status, return_message, start_time
  from cron.job_run_details
 where jobid = (select jobid from cron.job where jobname='extrair-contexto-experimental-hora')
 order by start_time desc limit 3;
```
Expected: `status = 'succeeded'`.

**Job agendado não é job que rodou.** Confirmar em `job_run_details` antes de considerar a tarefa feita.

- [ ] **Step 4: Conferir a qualidade sobre as 17 futuras**

```sql
select le.nome_aluno, le.data_experimental,
       a.detalhes -> 'itens' as itens
  from automacao_log a
  join lead_experimentais le on true
 where a.evento = 'contexto_experimental'
 order by a.created_at desc limit 1;
```

Ler a saída de todas as experimentais processadas e conferir os cinco pontos do Step 4 da Task 2. Casos que devem ser olhados nominalmente:

- **Andrade** — deve trazer `nivel_declarado: "ja_tocava"`, história de Portugal, e alerta de agenda do cancelamento de 04/08.
- **Isadora** — deve trazer `data_nascimento: "2025-05-14"` (e **não** "6 meses"), e a indicação da pediatra em `para_a_devolutiva` ou nos ganchos.
- **Davi Caetano** — conversa com 2 mensagens e o cliente nunca respondeu. Deve vir vazio honesto, não inventado.

> ⚠️ **Esta conferência é a única rede contra o erro da paginação.** Os mutantes
> das tasks 1 e 4 são SQL e não alcançam a edge function: se ela ler só a última
> página, todos os testes continuam verdes e a saída fica plausível — só pobre.
> O sinal é `procedencia.mensagens_lidas`: a conversa dos Andrade tem **51**
> mensagens e a da Isadora **56**. Se vier algo perto de 20, a paginação quebrou.
> Conferir esse número em todos os itens antes de ligar a escrita.

- [ ] **Step 5: Ligar a escrita**

Só depois da conferência: mudar o secret `EXTRATOR_DRY_RUN` para `false`. Não precisa redeploy.

Rodar de novo e confirmar:
```sql
select count(*) from lead_experimentais
 where contexto_ia is not null and data_experimental >= current_date;
```
Expected: número próximo de 17 (menos os que não têm conversa).

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/027b-cron-extrator-contexto.sql
git commit -m "feat(027b): cron horario do extrator de contexto

Funcao pronta sem chamador e o defeito que apareceu seis vezes neste
projeto. Confirmado em cron.job_run_details que o job roda, nao so que
esta agendado."
```

---

## Task 4: A fronteira e a leitura pelo Fábio

**Files:**
- Create: `supabase/migrations/028-fabio-le-contexto-experimental.sql`
- Create: `supabase/migrations/028-fabio-le-contexto-experimental.test.sql`
- Create: `scripts/mutantes-028.mjs`
- Modify: `package.json` (adicionar `teste:028` e `mutantes:028`)

**Interfaces:**
- Consumes: coluna `contexto_ia` (Task 1)
- Produces: `vw_fabio_contexto_experimental` com colunas `aluno_id integer, lead_experimental_id integer, data_experimental date, curso text, idade integer, contexto jsonb`
- Produces: `fabio_prontuario_aluno` passa a devolver a chave `experimental`

- [ ] **Step 1: Escrever a migration**

Criar `supabase/migrations/028-fabio-le-contexto-experimental.sql`:

```sql
-- 028 — o Fábio passa a saber como o aluno chegou
--
-- A view é a FRONTEIRA: ela devolve chave por chave, da lista de permissão. Se
-- um dia o extrator gravar valor de mensalidade no JSON por engano, o campo não
-- atravessa — porque não está listado aqui.
--
-- Instrução em prompt não é fronteira. A notificar-anamnese tem "foque em
-- adaptação, não em rótulos de diagnóstico" escrito no prompt do Gemini e mesmo
-- assim manda diagnóstico cru para o WhatsApp do professor, porque a parte fixa
-- da mensagem não passa por IA nenhuma.

create or replace view public.vw_fabio_contexto_experimental as
 select l.aluno_id,
        le.id                     as lead_experimental_id,
        le.data_experimental,
        c.nome::text              as curso,
        -- idade SEMPRE calculada, nunca lida do texto. A observação da Isadora
        -- diz "6 meses" porque foi escrita em nov/2025; a aula é 15/08/2026 e
        -- ela tem 1 ano e 3 meses.
        case when (le.contexto_ia -> 'recepcao' ->> 'data_nascimento') ~ '^\d{4}-\d{2}-\d{2}$'
             then extract(year from age(current_date,
                    (le.contexto_ia -> 'recepcao' ->> 'data_nascimento')::date))::integer
        end                       as idade,
        jsonb_strip_nulls(jsonb_build_object(
          'recepcao', jsonb_build_object(
            'responsavel', le.contexto_ia -> 'recepcao' ->> 'responsavel',
            'aluno',       le.contexto_ia -> 'recepcao' ->> 'aluno',
            'junto_com',   le.contexto_ia -> 'recepcao' ->> 'junto_com'),
          'quem_e_esse_aluno', jsonb_build_object(
            'nivel_declarado', le.contexto_ia -> 'quem_e_esse_aluno' ->> 'nivel_declarado',
            'historia',        le.contexto_ia -> 'quem_e_esse_aluno' ->> 'historia',
            'de_quem_partiu',  le.contexto_ia -> 'quem_e_esse_aluno' ->> 'de_quem_partiu'),
          'ganchos_de_conexao', le.contexto_ia -> 'ganchos_de_conexao',
          'para_a_devolutiva', jsonb_build_object(
            'o_que_a_familia_espera', le.contexto_ia -> 'para_a_devolutiva' ->> 'o_que_a_familia_espera',
            'atencao_conversao',      le.contexto_ia -> 'para_a_devolutiva' ->> 'atencao_conversao'),
            -- `porque` fica de fora de propósito: é onde mora a frase sobre
            -- preço. O professor recebe o sinal, não o motivo financeiro.
          'apoio_declarado', le.contexto_ia ->> 'apoio_declarado',
          'alertas',         le.contexto_ia -> 'alertas',
          'extraido_em',     le.contexto_ia -> 'procedencia' ->> 'extraido_em'
        ))                        as contexto
   from lead_experimentais le
   join leads l on l.id = le.lead_id      -- leads.aluno_id (319), NAO
                                          -- lead_experimentais.aluno_id (81)
   left join cursos c on c.id = le.curso_interesse_id
  where le.contexto_ia is not null
    and l.aluno_id is not null;

comment on view public.vw_fabio_contexto_experimental is
'Contexto da experimental que o Fabio pode ver. Lista de permissao: dinheiro, negociacao e recado interno nao atravessam. Idade sempre calculada de data_nascimento.';

-- ─────────────────────────────────────────────────────────────────────────
-- O prontuário ganha o bloco `experimental`
--
-- A porta continua sendo a função, que recebe quem está perguntando e faz o
-- guard uma vez. View não recebe parâmetro: confiar no chamador filtrar foi
-- como o selo verde de presença mentiu por meses, e RLS não vale aqui porque o
-- bridge conecta com service_role.

create or replace function public.fabio_prontuario_aluno(
  p_aluno_id integer,
  p_professor_id integer,
  p_limite integer default 40
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_base jsonb;
  v_cadastro jsonb;
  v_experimental jsonb;
begin
  if p_professor_id is null then
    raise exception 'professor_id_obrigatorio: o Fabio fala com professor e so pode ler os cursos DELE com este aluno.'
      using errcode = '42501';
  end if;

  v_base := public.fn_prontuario_aluno_interno(p_aluno_id, p_professor_id, p_limite);

  select jsonb_build_object(
           'nome',                 k.aluno_nome,
           'primeiro_nome',        split_part(btrim(k.aluno_nome), ' ', 1),
           'curso',                k.curso_nome,
           'dia_aula',             k.dia_aula,
           'horario_aula',         k.horario_aula,
           'idade',                a.idade_atual,
           'responsavel_nome',     k.responsavel_nome,
           'data_matricula',       k.data_matricula,
           'dias_desde_matricula', k.dias_desde_matricula,
           'e_aluno_novo',         k.e_aluno_novo,
           'aulas_registradas',    k.aulas_registradas
         )
    into v_cadastro
    from vw_fabio_carteira_professor k
    join alunos a on a.id = k.aluno_id
   where k.aluno_id = p_aluno_id
     and k.professor_id = p_professor_id
   limit 1;

  -- Só entra se o aluno for da carteira DESTE professor. O guard de cima já
  -- garante isso, mas a checagem aqui evita que uma mudança futura no
  -- fn_prontuario_aluno_interno abra a porta sem ninguém notar.
  if v_cadastro is not null then
    select e.contexto || jsonb_build_object('data_experimental', e.data_experimental,
                                            'curso_experimental', e.curso)
      into v_experimental
      from vw_fabio_contexto_experimental e
     where e.aluno_id = p_aluno_id
     order by e.data_experimental desc
     limit 1;
  end if;

  return v_base
      || jsonb_build_object('cadastro',     coalesce(v_cadastro, '{}'::jsonb))
      || jsonb_build_object('experimental', coalesce(v_experimental, '{}'::jsonb));
end
$function$;

comment on function public.fabio_prontuario_aluno(integer, integer, integer) is
'Prontuario do aluno para o professor. Blocos: cadastro (026), experimental (028) e linha do tempo.';
```

- [ ] **Step 2: Escrever o teste**

Criar `supabase/migrations/028-fabio-le-contexto-experimental.test.sql`:

```sql
-- Teste da 028 — a fronteira do contexto da experimental.
-- Rodar com: npm run teste:028

create temp table _falhas(passo text, esperado text, obtido text) on commit drop;
create function pg_temp.checar(p text, e text, o text) returns void language plpgsql as $c$
begin if e is distinct from o then insert into _falhas values (p, coalesce(e,'(null)'), coalesce(o,'(null)')); end if; end $c$;

do $t$
declare
  v_le integer; v_lead integer; v_aluno integer; v_prof integer;
  v_ctx jsonb; v_idade integer;
begin
  -- ===== setup: um aluno de verdade, da carteira de um professor de verdade =====
  select k.aluno_id, k.professor_id into v_aluno, v_prof
    from vw_fabio_carteira_professor k limit 1;
  if v_aluno is null then
    insert into _falhas values ('setup','um aluno na carteira','nenhum'); return;
  end if;

  -- amarra esse aluno a um lead e a uma experimental (a transacao vai ser
  -- descartada pelo runner)
  select id into v_lead from leads order by id desc limit 1;
  update leads set aluno_id = v_aluno where id = v_lead;
  select id into v_le from lead_experimentais where lead_id = v_lead limit 1;
  if v_le is null then
    insert into lead_experimentais (lead_id, nome_aluno, data_experimental, status)
    values (v_lead, 'Teste Fronteira', current_date, 'experimental_agendada')
    returning id into v_le;
  end if;

  -- contexto COM lixo que nao pode atravessar
  update lead_experimentais
     set contexto_ia = jsonb_build_object(
       'recepcao', jsonb_build_object('responsavel','Melissa','aluno','Daniela',
                                      'data_nascimento','2013-07-25'),
       'quem_e_esse_aluno', jsonb_build_object('nivel_declarado','ja_tocava',
                                               'historia','Tocava piano em Portugal'),
       'ganchos_de_conexao', jsonb_build_array('gosta de canto'),
       'para_a_devolutiva', jsonb_build_object('atencao_conversao','alta',
                                               'porque','perguntou o preco tres vezes'),
       'alertas', jsonb_build_array(jsonb_build_object('tipo','agenda','texto','cancelou 04/08')),
       'valor_mensalidade', 'R$ 450',
       'observacao_interna', 'ajustar data de nascimento, lancamento ficticio',
       'procedencia', jsonb_build_object('ultima_mensagem_id','1','extraido_em','2026-08-04T20:00:00Z'))
   where id = v_le;

  select contexto, idade into v_ctx, v_idade
    from vw_fabio_contexto_experimental where lead_experimental_id = v_le;

  -- ===== 1. o util atravessa =====
  perform pg_temp.checar('1. traz o nivel','ja_tocava',
    v_ctx -> 'quem_e_esse_aluno' ->> 'nivel_declarado');
  perform pg_temp.checar('2. traz o responsavel','Melissa',
    v_ctx -> 'recepcao' ->> 'responsavel');
  perform pg_temp.checar('3. traz o gancho','true',
    (jsonb_array_length(v_ctx -> 'ganchos_de_conexao') = 1)::text);
  perform pg_temp.checar('4. traz o alerta de agenda','agenda',
    v_ctx -> 'alertas' -> 0 ->> 'tipo');
  perform pg_temp.checar('5. traz o sinal de conversao','alta',
    v_ctx -> 'para_a_devolutiva' ->> 'atencao_conversao');

  -- ===== 6. o que NAO pode atravessar =====
  perform pg_temp.checar('6. valor de mensalidade NAO atravessa','false',
    (v_ctx ? 'valor_mensalidade')::text);
  perform pg_temp.checar('7. observacao interna NAO atravessa','false',
    (v_ctx ? 'observacao_interna')::text);
  perform pg_temp.checar('8. o PORQUE do sinal de conversao NAO atravessa','false',
    (v_ctx -> 'para_a_devolutiva' ? 'porque')::text);
  perform pg_temp.checar('9. data_nascimento crua NAO atravessa','false',
    (v_ctx -> 'recepcao' ? 'data_nascimento')::text);

  -- ===== 10. a idade e CALCULADA =====
  perform pg_temp.checar('10. idade calculada da data',
    extract(year from age(current_date, date '2013-07-25'))::integer::text, v_idade::text);

  -- ===== 11. data invalida nao quebra a view =====
  update lead_experimentais
     set contexto_ia = jsonb_set(contexto_ia, '{recepcao,data_nascimento}', '"6 meses"')
   where id = v_le;
  select idade into v_idade from vw_fabio_contexto_experimental where lead_experimental_id = v_le;
  perform pg_temp.checar('11. texto no lugar da data vira null, nao explode','(null)',
    coalesce(v_idade::text,'(null)'));

exception when others then
  insert into _falhas values ('excecao','sem excecao', sqlerrm);
end $t$;

select json_build_object('teste','028-fronteira',
  'falhas',(select count(*) from _falhas),
  'detalhe', coalesce((select json_agg(json_build_object('passo',passo,'esperado',esperado,'obtido',obtido)) from _falhas),'[]'::json)) as resumo;

-- ===== o prontuario compoe o bloco =====
do $t2$
declare
  v_aluno integer; v_prof integer; v_outro integer; v_p jsonb;
begin
  select k.aluno_id, k.professor_id into v_aluno, v_prof
    from vw_fabio_carteira_professor k limit 1;

  v_p := public.fabio_prontuario_aluno(v_aluno, v_prof, 5);
  perform pg_temp.checar('12. prontuario traz a chave experimental','true', (v_p ? 'experimental')::text);
  perform pg_temp.checar('13. e continua trazendo cadastro','true', (v_p ? 'cadastro')::text);
  perform pg_temp.checar('14. e a linha do tempo','true', (v_p ? 'linha_do_tempo')::text);

  -- aluno de OUTRO professor continua barrado
  select professor_id into v_outro from vw_fabio_carteira_professor
   where professor_id <> v_prof limit 1;
  if v_outro is not null then
    begin
      perform public.fabio_prontuario_aluno(v_aluno, v_outro, 5);
      insert into _falhas values ('15. aluno de outro professor barrado','excecao','passou');
    exception when others then null;
    end;
  end if;

exception when others then
  insert into _falhas values ('excecao prontuario','sem excecao', sqlerrm);
end $t2$;

select json_build_object('teste','028-prontuario-com-experimental',
  'falhas',(select count(*) from _falhas),
  'detalhe', coalesce((select json_agg(json_build_object('passo',passo,'esperado',esperado,'obtido',obtido)) from _falhas),'[]'::json)) as resumo;
```

- [ ] **Step 3: Adicionar os scripts ao package.json**

```json
"teste:028": "node scripts/rodar-teste-sql.mjs supabase/migrations/028-fabio-le-contexto-experimental.sql supabase/migrations/028-fabio-le-contexto-experimental.test.sql",
"mutantes:028": "node scripts/mutantes-028.mjs",
```

- [ ] **Step 4: Rodar o teste**

Run: `npm run teste:028`
Expected: `falhas: 0` nos dois resumos, 15 verificações.

- [ ] **Step 5: Escrever os mutantes**

Criar `scripts/mutantes-028.mjs`:

```js
import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'

const ORIGINAL = 'supabase/migrations/028-fabio-le-contexto-experimental.sql'
const TESTE = 'supabase/migrations/028-fabio-le-contexto-experimental.test.sql'
const TEMP = 'supabase/migrations/_mutante-028.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'a view devolve o JSON cru (dinheiro atravessa)',
    pega: 'passos 6, 7 e 8',
    de: '        jsonb_strip_nulls(jsonb_build_object(',
    para: '        le.contexto_ia as contexto_desativado, jsonb_strip_nulls(jsonb_build_object(',
  },
  {
    nome: 'o PORQUE do sinal de conversao passa (expoe o preco)',
    pega: 'passo 8',
    de: "            'atencao_conversao',      le.contexto_ia -> 'para_a_devolutiva' ->> 'atencao_conversao'),",
    para: "            'atencao_conversao',      le.contexto_ia -> 'para_a_devolutiva' ->> 'atencao_conversao',\n            'porque', le.contexto_ia -> 'para_a_devolutiva' ->> 'porque'),",
  },
  {
    nome: 'idade lida do texto em vez de calculada',
    pega: 'passos 10 e 11',
    de: "        case when (le.contexto_ia -> 'recepcao' ->> 'data_nascimento') ~ '^\\d{4}-\\d{2}-\\d{2}$'",
    para: "        case when true",
  },
  {
    nome: 'join por lead_experimentais.aluno_id (perde 238 de 319)',
    pega: 'passos 1 a 5',
    de: '   join leads l on l.id = le.lead_id',
    para: '   join leads l on l.id = le.lead_id and le.aluno_id is not null',
  },
  {
    nome: 'prontuario nao devolve o bloco experimental',
    pega: 'passo 12',
    de: "      || jsonb_build_object('experimental', coalesce(v_experimental, '{}'::jsonb));",
    para: ';',
  },
  {
    nome: 'contexto de aluno alheio entra no prontuario',
    pega: 'passo 15 (defesa em 2 camadas — pode sobreviver)',
    esperaSobreviver: true,
    de: '  if v_cadastro is not null then',
    para: '  if true then',
  },
]

let previstos = 0
for (const m of MUTANTES) {
  if (!fonte.includes(m.de)) {
    console.log(`AVISO  "${m.nome}" — ancora nao encontrada, mutante NAO aplicado`)
    continue
  }
  writeFileSync(TEMP, fonte.replace(m.de, m.para))
  let passou = true
  try { execFileSync('node', ['scripts/rodar-teste-sql.mjs', TEMP, TESTE], { stdio: 'pipe' }) } catch { passou = false }
  const previsto = m.esperaSobreviver ? passou : !passou
  if (previsto) {
    previstos++
    console.log(`OK   ${m.esperaSobreviver ? 'sobreviveu como previsto' : 'morto'}: ${m.nome}  (${m.pega})`)
  } else {
    console.log(`FALHA  ${m.esperaSobreviver ? 'MORREU e devia sobreviver' : 'SOBREVIVEU'}: ${m.nome}  (${m.pega})`)
  }
}
try { unlinkSync(TEMP) } catch {}
console.log(`\n${previstos}/${MUTANTES.length} mutantes com o resultado previsto`)
process.exitCode = previstos === MUTANTES.length ? 0 : 1
```

O último mutante tem `esperaSobreviver: true` porque `fn_prontuario_aluno_interno`
já levanta exceção para aluno de outro professor antes desse trecho rodar — a
checagem é segunda camada. O que importa é o passo 15 afirmar que o aluno alheio
é barrado por **algum** dos dois caminhos.

- [ ] **Step 6: Rodar os mutantes**

Run: `npm run mutantes:028`
Expected: `6/6 mutantes com o resultado previsto`

- [ ] **Step 7: Aplicar em produção e verificar ao vivo**

Aplicar a migration. Depois, com um aluno real que veio de experimental:

```sql
select le.nome_aluno, l.aluno_id, k.professor_id
  from lead_experimentais le
  join leads l on l.id = le.lead_id
  join vw_fabio_carteira_professor k on k.aluno_id = l.aluno_id
 where le.contexto_ia is not null limit 1;
```

E então:
```sql
select public.fabio_prontuario_aluno(<aluno_id>, <professor_id>, 5) -> 'experimental';
```
Expected: o bloco com `recepcao`, `quem_e_esse_aluno`, `ganchos_de_conexao` — e **sem** nenhum campo de dinheiro.

- [ ] **Step 8: Commit**

```bash
git add supabase/migrations/028-fabio-le-contexto-experimental.sql supabase/migrations/028-fabio-le-contexto-experimental.test.sql scripts/mutantes-028.mjs package.json
git commit -m "feat(028): o Fabio passa a saber como o aluno chegou

A view e a fronteira: devolve chave por chave, da lista de permissao. Valor
de mensalidade e recado interno nao atravessam porque nao estao listados --
nao porque o prompt pediu.

O `porque` do sinal de conversao fica de fora de proposito: o professor
recebe atencao_conversao=alta e sabe que precisa mostrar valor na
devolutiva, sem ver o bolso da familia.

Idade sempre calculada de data_nascimento, e data invalida vira null em vez
de explodir -- a observacao da Isadora diz '6 meses' desde nov/2025.

Porta continua sendo a funcao: view nao recebe parametro e o guard morreria.

15 verificacoes, 6/6 mutantes com o resultado previsto."
```

---

## Task 5: Conversar com o Fábio e fechar

**Files:**
- Modify: `docs/superpowers/specs/2026-08-04-extrator-contexto-experimental-design.md` (marcar como implementado)

**Interfaces:**
- Consumes: tudo das tarefas anteriores

- [ ] **Step 1: Perguntar ao Fábio, sem histórico**

Escolher um aluno que veio de experimental e está na carteira do professor 25 (Matheus) — ou, se não houver, o professor do aluno encontrado no Step 7 da Task 4.

Run:
```bash
ssh -i ~/.ssh/id_ed25519_lahq_fabio_claude_code fabio@89.116.73.186 \
  'cd ~/fabio-chat-bridge && set -a && . ~/.hermes/.env && set +a && \
   python3 falar_com_fabio.py "quem e o aluno <NOME>? me fala dele" --sem-historico --professor-id <ID>'
```

Expected: a resposta cita como o aluno chegou (nível, motivação, gancho), **sem** mencionar preço ou negociação.

- [ ] **Step 2: Testar o caso oposto**

Perguntar sobre um aluno que **não** veio de experimental.

Expected: resposta normal, sem inventar contexto de experimental e sem citar bloco vazio.

- [ ] **Step 3: Testar uma pergunta comum**

Run: `python3 falar_com_fabio.py "bom dia Fabio, tudo certo?" --sem-historico`

Expected: conversa normal. Se o Fábio começar a despejar contexto de experimental sem ser perguntado, o bloco está inchando o prompt — reduzir o que entra.

- [ ] **Step 4: Comparar o tamanho do prompt**

Nos logs do gateway (`~/.hermes/logs/agent.log`), comparar o `in=` das chamadas antes e depois.

Expected: aumento pequeno. Hoje o turno roda com ~26 mil tokens; se o bloco `experimental` empurrar isso muito para cima, cortar campos.

**Se a resposta ficou mais comprida sem ficar mais útil, o trabalho não está pronto.** Mais contexto não é mais qualidade.

- [ ] **Step 5: Commit final**

```bash
git add docs/superpowers/specs/2026-08-04-extrator-contexto-experimental-design.md
git commit -m "docs: extrator de contexto da experimental verificado com o Fabio

Testado conversando, --sem-historico, com os tres casos: aluno vindo de
experimental, aluno que nao veio, e pergunta comum. A resposta e o produto;
o contexto e insumo."
```
