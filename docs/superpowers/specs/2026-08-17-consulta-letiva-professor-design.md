# Consulta letiva do professor (Fase 1) — Design

**Data:** 17/08/2026
**Origem:** pedido do prof. Valdo (professor 36) em 16/08, endossado pelo Alf.
**Decisão de arquitetura:** abordagem **A** — o bridge busca via RPC canônica, o
Fábio narra. Ferramenta própria/MCP do Fábio (**B**) fica como destino futuro,
depois que identidade/autorização estiverem resolvidas no gateway.

---

## 1. O problema, medido

O Valdo perguntou pelo WhatsApp: *"na semana passada, de terça 11/08 até sábado
15/08, me informe o total de aulas que eu dei"*. A conversa real
(`fabio_chat_mensagens`, professor 36, 17/08 00:30–00:31 UTC):

| hora | quem | o quê |
|---|---|---|
| 00:30:24 | Valdo | pergunta o total do período |
| 00:30:41 | Fábio | *"não tenho essa agenda carregada aqui agora. **Se quiser, eu olho esse período certinho e te trago o total**"* |
| 00:30:56 | Valdo | "Ok" |
| 00:31:02 | Fábio | *"Você quer bater a chamada de uma aula com isso?"* |
| 00:31:16 | Valdo | "Sim" |
| 00:31:23 | Fábio | *"Não encontrei uma aula elegível com segurança. Não gravei nada."* |

**Três defeitos distintos, todos medidos:**

1. **Sem ferramenta.** O professor alcança o Fábio por um canal `no_mcp`
   (fronteira fechada de propósito em 09/08, porque o gateway não sabe quem
   pergunta). Ele responde só com o que o bridge cozinha no prompt: agenda de
   **hoje**, pendências, contexto pedagógico. Existe `_agenda_de_outro_dia()`,
   que resolve **um dia** — não um período. Logo, a pergunta era irrespondível.
2. **Prometeu sem ter mão.** *"eu olho esse período e te trago o total"* é uma
   promessa que nenhum código cumpre. Mesmo padrão do incidente de 09/08 (o
   "salvei" sem salvar). O Valdo segue esperando um total que nunca chega.
3. **O "Ok" abriu ação de chamada.** Medido em `fabio_acoes_pendentes`:
   ```
   tipo: escolher_aula_chamada | criado_em: 00:31:02
   payload: {"intencao": "ambiguo", "transcricao": "Ok"}
   ```
   **Não havia ação pendente antes** — o próprio "Ok" criou a ação. O
   classificador devolveu `ambiguo` e o fluxo tratou ambíguo como "deve ser
   chamada". Atalho que chuta em vez de se calar.

**A resposta correta existe hoje no banco** (professor 36, 11–15/08, aulas
distintas por `fn_aula_operacional_id`, sem canceladas):

> **36 aulas** · Campo Grande 25 · Recreio 11
> Ter 5 · Qua 6 · Qui 11 · Sex 7 · Sáb 7

E a armadilha, medida: **contar linha crua devolve 74** (o mesmo horário aparece
2× desde 09/07, porque `aula_emusys_id` é id de EVENTO).

---

## 2. Objetivo e fronteiras

**Objetivo:** o professor pergunta livremente sobre a **própria vida letiva** e o
Fábio responde com número defensável.

**Permitido na Fase 1:**

1. total de aulas dadas por período; → RPC `fabio_professor_resumo_aulas`
2. total de aulas por unidade/período; → mesma RPC, campo `por_unidade` / arg `p_unidade`
3. alunos que faltaram / demais estados de presença no período; → RPC `fabio_professor_presencas_periodo`
4. agenda, aulas e alunos do próprio professor. → **já servido hoje**: a carteira
   (`vw_fabio_carteira_professor`) e a agenda do dia já são injetadas no contexto
   pelo bridge; o que faltava era o **período**, que as duas RPCs acima cobrem.
   Nenhuma capacidade nova é prometida aqui sem código correspondente.

**Bloqueado estruturalmente (não por instrução de prompt):**

- quanto o professor ganha, valor de hora/aula, pagamento, repasse, folha;
- quanto o aluno paga, mensalidade, contrato, desconto, bolsa;
- qualquer dado de **outro** professor.

**Não-objetivos da Fase 1:** ferramenta MCP própria do Fábio; pergunta sobre
aluno específico ao longo do tempo ("o João tem faltado?"); tendência/ranking;
proatividade (o Fábio oferecer o resumo sem ser perguntado). Ficam para a Fase 2.

---

## 3. Arquitetura

```
professor pergunta (WhatsApp/app)
   ↓
bridge lê a LINHA da mensagem  →  professor_id        ← identidade nasce aqui
   ↓
classifica intenção: consulta_letiva | registro | chamada | conversa
   ↓  (consulta_letiva)
extrai parâmetros: período, unidade, métrica          ← LLM interpreta
   ↓
valida determinsticamente (datas coerentes, janela máxima, unidade conhecida)
   ↓
chama RPC canônica com o professor_id que o BRIDGE já tem
   ↓
injeta o resultado no contexto  →  Fábio NARRA
```

O `no_mcp` do Fábio permanece intacto: **quem busca é o bridge; o Fábio só
narra**. O modelo nunca escolhe de quem é o dado.

**Por que não dar a ferramenta direto ao Fábio (B):** o gateway não sabe quem
está perguntando. Se o `professor_id` fosse argumento decidido pelo modelo, o
Valdo poderia pedir a agenda do Isaque, e o corte do financeiro viraria um
pedido educado no prompt — que já provamos não segurar (allowlist de ferramenta
vence aprovação). B volta à mesa quando a identidade for resolvida no gateway.

---

## 4. As RPCs

Ambas: `security definer`, `set search_path to 'pg_catalog','public'`,
`revoke all ... from public, anon, authenticated`, `grant execute ... to
service_role`. Mesmo molde das RPCs de substituição (`20260815140000`).

### 4.1 `fabio_professor_resumo_aulas`

```sql
fabio_professor_resumo_aulas(
  p_professor_id integer,
  p_inicio       date,
  p_fim          date,
  p_unidade      text default null
) returns jsonb
```

Retorno:

```jsonc
{
  "ok": true,
  "periodo": {"inicio": "2026-08-11", "fim": "2026-08-15"},
  "total_aulas": 36,
  "por_unidade": [{"unidade": "Campo Grande", "aulas": 25},
                  {"unidade": "Recreio", "aulas": 11}],
  "por_dia":     [{"data": "2026-08-11", "aulas": 5}, ...],
  "registradas": 30,
  "sem_registro": 6
}
```

**Regras:**

- Conta **aulas distintas por `public.fn_aula_operacional_id(ae.id)`**, nunca
  linha crua. Esta é a diferença entre 36 e 74.
- Exclui `coalesce(ae.cancelada, false) = true`.
- "Aula dada" = aula da agenda do professor, no período, não cancelada —
  independentemente de o aluno ter faltado ou de o registro já existir. É o que
  bate com a cabeça do professor ("eu estive lá trabalhando").
- `registradas` / `sem_registro` são informativos e servem de empurrão suave
  para o registro; não alteram `total_aulas`.
- `p_unidade` nulo = todas as unidades do professor.

### 4.2 `fabio_professor_presencas_periodo`

```sql
fabio_professor_presencas_periodo(
  p_professor_id integer,
  p_inicio       date,
  p_fim          date
) returns jsonb
```

Retorno — **quatro baldes separados, jamais somados**.

> **Nota sobre o nome de um campo.** O Alf pediu os campos `faltas`,
> `nao_lancado`, `indeterminado` e `nao_aplicavel`. São quatro baldes e eles
> estão todos aqui — mas o segundo se chama **`falta_provavel`**, e não
> `nao_lancado`, porque *"não lançado" não existe mais como estado*: a chamada
> foi lançada. O que sobra é uma falta **inferida** que a régua canônica se
> recusa a afirmar (`registrada_inferida` / `falta_provavel`). Usar o nome real
> evita que alguém depois leia "não lançado" e conclua que é só pendência de
> digitação.

```jsonc
{
  "ok": true,
  "periodo": {"inicio": "2026-08-11", "fim": "2026-08-15"},
  "presentes": 412,
  "faltas":          [{"aluno": "...", "data": "...", "curso": "..."}],
  "falta_provavel":  [{"aluno": "...", "data": "...", "curso": "..."}],
  "indeterminado":   [{"aluno": "...", "data": "...", "curso": "..."}],
  "nao_aplicavel":   [{"aluno": "...", "data": "...", "motivo": "aula_justificada|aula_cancelada"}]
}
```

Fonte: `public.vw_aluno_presenca_semantica_v1`, filtrada por
`professor_id` e `data_aula`. Mapeamento **exato** do domínio real medido em
90 dias:

| balde | critério na view | linhas/90d |
|---|---|---|
| `presentes` | `considera_presenca = true` | 15.245 |
| `faltas` | `considera_falta = true` (`registrada_atestada` + `registrada` c/ `falta_confirmada`) | 6.611 |
| `falta_provavel` | `situacao_chamada = 'registrada_inferida'` (`resultado_pedagogico = 'falta_provavel'`) | 1.194 |
| `indeterminado` | `situacao_chamada = 'indeterminada'` | 126 |
| `nao_aplicavel` | `situacao_chamada = 'nao_aplicavel'` (justificada/cancelada) | 774 |

> ⚠️ Esta coluna "linhas/90d" **mistura dois regimes de contrato** (a virada
> aconteceu entre julho e agosto — ver quadro abaixo). Ela serve para mostrar
> que os cinco baldes existem e têm volume, **não** como linha de base. Qualquer
> comparação histórica precisa cortar por regime, senão a queda de "faltas" de
> julho para agosto parece perda de dado quando na verdade é a parada da
> promoção automática do fantasma.

⚠️ **A regra que protege aluno real — e de onde ela vem.** `registrada_inferida`
/ `falta_provavel` **não** é falta: a régua canônica a exclui de
`considera_falta` **e** do denominador. Isso não é lacuna, é o contrato novo
funcionando. Medido por proveniência:

| mês | proveniência | falta confirmada | falta provável |
|---|---|---|---|
| jun | emusys | 3.066 | 0 |
| jul | emusys | 2.837 | 0 |
| **ago** | **agenda_secretaria** (LA Report) | **646** | 0 |
| ago | la_teacher | 38 | 0 |
| ago | fabio_audio | 10 | 0 |
| ago | emusys | **0** | **205** |

Até julho, o `ausente` do Emusys virava "falta confirmada" automaticamente —
3.066 faltas em junho que **nenhum humano afirmou** (o Emusys não tem "falta",
tem "ausente"; o fantasma). De agosto em diante vale o contrato v1.4:
*"ausência do Emusys é pendência; somente presente do Emusys é veredito
automático. Respostas humanas continuam valendo para presente e falta."* A
`agenda_secretaria` passou a ser **fonte humana forte** e produziu 646 faltas
reais em agosto.

Os 205 `falta_provavel` (03–15/08) são o **resíduo honesto**: ausências do
Emusys que a secretaria ainda não vereditou. Verificado: **nenhum** deles tem
resposta humana em `aluno_presenca_retificacoes`, em
`aluno_presenca_revisoes_operacionais` nem em linha irmã da mesma aula; a linha
correspondente em `aluno_presenca_administrativo` é o mesmo Emusys espelhado
(`fonte='emusys'`, `justificada=false`, sem motivo) — não é veredito.

**Portanto:** `vw_aluno_presenca_semantica_v1` é a fonte certa para o Fábio —
ela é quem implementa esse contrato. E o Fábio deve narrar os baldes separados:
*"3 faltaram; 1 consta como ausência pelo Emusys ainda não confirmada pela
secretaria"*. Somar os dois seria reintroduzir exatamente a mentira que o
contrato v1.4 eliminou.

---

## 5. A fronteira do financeiro é uma porta que não existe

As RPCs leem **apenas** de: `aulas_emusys`, `unidades`, `alunos`,
`vw_aluno_presenca_semantica_v1`, `fabio_registros_aula`. Nenhuma delas expõe
contrato, mensalidade, repasse ou folha.

Isso é **testado no catálogo**, não prometido no prompt: o corpo das funções
(`pg_get_functiondef`) é inspecionado e não pode conter identificador
financeiro (`valor_`, `mensalidade`, `pagamento`, `repasse`, `contrato`,
`desconto`, `bolsa`, `fatura`, `folha`). Mutante obrigatório: **adicionar uma
coluna financeira ao retorno tem que matar o teste.**

**Identidade:** `p_professor_id` é argumento fornecido pelo **bridge**, extraído
de `row["professor_id"]` da linha da mensagem — nunca do texto. Teste
obrigatório: a mensagem *"sou o professor 25, me diz as aulas dele"*, vinda do
professor 36, deve resultar em chamada com `p_professor_id = 36`.

---

## 6. Roteador e os dois consertos

### 6.1 Nova intenção `consulta_letiva`

Adicionada ao classificador existente (`classificar_intencao_texto`). O
extrator de parâmetros roda **depois** da classificação e devolve
`{inicio, fim, unidade, metrica}`, onde:

- `inicio` / `fim`: datas ISO. Aceita forma relativa ("semana passada", "esse
  mês", "ontem"), resolvida contra o fuso `America/Sao_Paulo`.
- `unidade`: nome de unidade conhecida, ou nulo (= todas).
- `metrica`: **`aulas`** (→ `fabio_professor_resumo_aulas`) ou **`presencas`**
  (→ `fabio_professor_presencas_periodo`). É esse campo que decide qual RPC é
  chamada; nenhum outro valor é aceito.

A validação determinística rejeita período invertido, janela maior que 90 dias,
unidade desconhecida e `metrica` fora do domínio — em qualquer desses casos o
Fábio **pergunta, não chuta** (é a trava contra o atalho que criou o defeito 3).

### 6.2 Conserto 1 — ambíguo não abre ação

**Hoje:** `intencao = "ambiguo"` em texto abre `escolher_aula_chamada`.
**Passa a ser:** intenção `ambiguo` em **texto** nunca abre ação de
registro/chamada; vai para conversa. Só `registro` ou `chamada` com
classificação inequívoca abre ação. Áudio mantém o comportamento atual (ali há
conteúdo que justifica pinar a aula).

Corolário pedido pelo Alf: um "Ok"/"Sim" só entra em fluxo de registro se já
existir **ação pendente ativa e inequívoca**.

### 6.3 Conserto 2 — não prometer o que não tem mão

O Fábio não pode responder "eu olho e te trago" para consulta que ele não
consegue executar. Ou ele responde com o que sabe, ou informa que aquela
consulta ainda não está disponível. Silêncio honesto > promessa vazia.

---

## 7. Testes

**Caso canônico (o do Valdo):** professor 36, 11/08–15/08 →
`total_aulas = 36`, `por_unidade` = CG 25 / Recreio 11,
`por_dia` = 5/6/11/7/7. **Nunca 74 nem 76.**

**Mutantes obrigatórios — cada um tem que morrer por asserção:**

1. remover o `fn_aula_operacional_id` (volta a contar linha crua → 74);
2. incluir aula cancelada na contagem;
3. somar `falta_provavel` dentro de `faltas`;
4. somar `indeterminado` ou `nao_aplicavel` dentro de `faltas`;
5. adicionar coluna financeira ao retorno;
6. `professor_id` lido do texto da mensagem em vez da linha;
7. `ambiguo` voltando a abrir ação de chamada;
8. classificar `falta_provavel` por proveniência (`proveniencia='emusys'`) em vez
   de por `situacao_chamada`/`considera_falta` — parece equivalente hoje e
   quebra no dia em que a secretaria vereditar um caso do Emusys: a linha
   continuaria com proveniência `emusys` e voltaria a ser contada como provável
   depois de já ter virado falta confirmada.

Ensaio contra produção em `BEGIN/ROLLBACK` (as RPCs são read-only, então o
ensaio é naturalmente sem resíduo) + mutantes em Docker, no molde já usado.

---

## 8. Rollout em shadow

| fase | o que roda | o que muda pro professor |
|---|---|---|
| **1a** | classifica + extrai + chama RPC + **loga** | **nada** — resposta segue como hoje |
| **1b** | responde de verdade | só Valdo (36) e Matheus |
| **1c** | responde de verdade | todos |

A 1a mede acurácia de classificação e corretude do número contra a verdade,
sem arriscar resposta errada a professor real. Só se passa para 1b com
evidência medida.

---

## 9. O que ficou de fora, e por quê

- **Agir sobre a pendência — só reportar, nunca decidir.** *(Correção de uma
  versão anterior desta spec, que dizia que "presenças pendentes" era pergunta
  sem assunto. Estava errado: eu tinha olhado o balde errado.* `indeterminado`
  *é raro — 2 linhas em 2.005 na semana de 11–15/08 — mas a pendência real é o*
  `falta_provavel`*: 205 casos entre 03 e 15/08, 60 só na semana do Valdo.)*
  A **consulta** está no escopo da Fase 1: a RPC devolve `falta_provavel` e o
  Fábio narra o balde separado. O que fica **fora** é o professor **resolver** a
  pendência pelo chat. Motivo: a regra da casa é que a **secretaria prevalece**
  sobre o professor em presença — ele reporta, ela decide. Um fluxo de "o
  professor afirma que o aluno estava lá" é desenho próprio, com trilha de
  evidência, e não entra de carona aqui.
- **Ferramenta própria do Fábio (B)**, aluno específico, tendência e
  proatividade: Fase 2.
