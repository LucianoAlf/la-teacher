# Prompt para o Codex — datas de nascimento no LA Report

> Cole este texto no Codex junto com o documento
> `datas-nascimento-pendentes-conferencia-emusys.md`.

---

Preciso da tua ajuda com um problema de cadastro no LA Report. O documento
anexo é o levantamento; este prompt é o que falta fazer, e a parte principal é
justamente a que **não** está no documento.

## O que já aconteceu

No projeto Supabase `ouqwbbermlzqqvtqwlul` (o mesmo que o LA Report usa), a
tabela `public.alunos` tinha **11 datas de nascimento divergentes** da fonte
Emusys. Já foram corrigidas pela migration `021-corrige-data-nascimento-divergente-do-emusys.sql`,
aplicada em 03/08/2026, versionada no repo `la-teacher`. Cada linha guarda o
valor antigo explícito, então é reversível.

A comparação foi contra o payload bruto já guardado no banco:

```sql
emusys_api_payload.payload->'aluno'->>'data_nascimento'        -- a criança
emusys_api_payload.payload->'responsavel'->>'data_nascimento'  -- quem paga
```

**Não repita esse trabalho.** Hoje há zero divergência entre `alunos` e o
payload, para os 1.502 alunos que têm payload.

## O que eu preciso de você — em ordem de importância

### 1. A causa raiz, que eu não consegui alcançar

Eu corrigi sintomas. **Não descobri por que o dado entrou errado**, e enquanto
isso não for resolvido, volta a acontecer no próximo sync.

Dois padrões distintos apareceram nos 11 casos:

**Padrão A — a data do responsável foi gravada no aluno.** Prova exata em dois
casos: o Heitor Muniz tinha `1983-04-21`, que é literalmente a
`data_nascimento` da mãe dele, Renata Muniz, no cadastro do Emusys. A Laiane
Marins tinha `1980-12-16`, a data da mãe Aline Marins. Batendo dia, mês e ano.

**Padrão B — a data ficou ~1 semana antes do `created_at` do registro.** O
Tiago (id 1457) foi criado em 27/02/2026 com nascimento em 18/02/2026. O
Matheus Lopes (id 1585) foi criado em 31/03/2026 com nascimento em 24/03/2026.
Cheira a preenchimento por proximidade quando o sync não trouxe a data.

Onde procurar: as edge functions `sync-matriculas-emusys`,
`processar-matricula-emusys`, `sync-students-studio`, e qualquer rotina de
importação/cadastro manual que grave `alunos.data_nascimento`. A pergunta a
responder é: **em que caminho a data do responsável acaba no campo do aluno, e
em que caminho a data vira "hoje menos alguns dias"?**

Se achar, corrija e me diga qual era. Se não achar, me diga onde procurou —
isso vale mais do que um palpite.

### 2. Fechar os 116 que eu não consegui verificar

**116 alunos não têm payload no `emusys_api_payload`** (99 deles ativos), então
não tive como conferir a data. Você tem acesso à API do Emusys; eu não tenho o
token nesta sessão.

Puxe o cadastro desses 116 direto da API e compare com `alunos.data_nascimento`.
A query que isola exatamente esse grupo:

```sql
with fonte as (
  select distinct on (p.emusys_student_id, p.aluno_nome)
         p.emusys_student_id, p.aluno_nome
    from emusys_api_payload p
   where p.payload->'aluno'->>'data_nascimento' ~ '^\d{4}-\d{2}-\d{2}$'
   order by p.emusys_student_id, p.aluno_nome, p.synced_at desc
)
select a.id, a.nome, a.emusys_student_id, a.data_nascimento, a.status,
       a.responsavel_nome
  from alunos a
  left join fonte f
    on f.emusys_student_id::text = a.emusys_student_id
   and f.aluno_nome = a.nome
 where f.aluno_nome is null
   and a.status in ('ativo','trancado')
 order by a.nome;
```

**Comece pelos 7 alunos entre 15 e 17 anos** listados na Prioridade 1 do
documento. Eles estão em cima da fronteira que decide para quem o Fábio manda a
devolutiva da aula: abaixo de 15 vai para o responsável, acima vai para o
próprio aluno. Data errada ali significa mandar conteúdo pedagógico de um
menor para o menor em vez de para a mãe.

### 3. O cadastro do responsável no Emusys (Prioridade 2 do documento)

Oito responsáveis estão com a data de nascimento **do filho** no próprio
cadastro. O campo do aluno está certo, então isso não afeta o Fábio — é
higiene de cadastro. Se a API do Emusys for só leitura para você também, essa
parte é da equipe, na mão.

## Armadilhas que eu já paguei para descobrir

- **`alunos.idade_atual` e `alunos.classificacao` não são fonte de nada.** O
  trigger `trg_alunos_calcular_campos` deriva as duas de `data_nascimento`
  (LAMK < 12, EMLA >= 12). Elas nunca divergem da data, então não servem para
  detectar erro — só propagam. E ao corrigir a data, elas se ajustam sozinhas:
  **não escreva nesses campos**.

- **Escrever em `data_nascimento` dispara chamada externa.** O trigger
  `trg_enqueue_sync_student_studio` faz `net.http_post` para a edge function
  `sync-students-studio` a cada alteração. Se for corrigir em lote, saiba que
  vai disparar uma chamada por linha. Em teste com `BEGIN … ROLLBACK` isso não
  vaza, porque o `pg_net` enfileira dentro da transação.

- **`emusys_student_id` colide.** O id `2093` aparece no
  `emusys_api_payload` para dois nomes diferentes ("Matheus Lopes de Medeiros"
  e "Luiza Silva de Abreu"). Faça o join por `emusys_student_id` **e** nome,
  nunca só pelo id.

- **1.160 dos 1.502 alunos não têm CPF** no cadastro do Emusys — criança não
  tem documento próprio. Não use CPF como chave nem como sinal de "é adulto".

- **O mesmo aluno pode ter vários registros em `alunos`**, um por curso
  (Maria Clara Monteiro de Carvalho tem três, Beatriz von Glehn tem dois). Ao
  corrigir, corrija todos os registros da pessoa, não o primeiro que aparecer.

- **A API do Emusys é GET, sem escrita.** Header `token` em minúsculo. As
  listagens vêm na chave `items`, a primeira página costuma vir vazia com
  `tem_mais: true`, e o limite máximo por página é 50.

## O que não fazer

- Não mexa em `alunos.data_nascimento` sem guardar o valor antigo explícito na
  própria migration. Foi assim na 021 e é o que torna reversível.
- Não confie em "o update não deu erro" — meça o resultado depois. Na 021 a
  verificação conta as divergências restantes e aborta se não for zero.
- Não apague nem consolide cadastro duplicado sem falar com o Alf.

## O que me devolver

1. A causa raiz dos padrões A e B, ou onde você procurou sem achar.
2. Quantos dos 116 estavam errados, e a lista corrigida.
3. Se mexeu no código de sync, o que mudou e como testou.
