# Registro da Aula Experimental — design

**Data:** 2026-08-05
**Status:** aguardando review
**Antecede:** plano de implementação (Tasks 3–6 do ciclo da experimental)
**Depende de:** migrations 032 (vínculo lead↔aula) e 033 (reconciliador), no ar e carimbadas

---

## 1. O problema, medido

O professor dá a aula experimental e **nada disso vira dado**. Três medições em produção
(05/08/2026) mostram o tamanho do buraco:

| Medição | Valor |
|---|---|
| Aulas experimentais não canceladas | 813 |
| **Sem nenhuma presença registrada** | **599 (74%)** |
| Com presença | 214 |
| Dessas, de **fonte forte** (`fn_presenca_e_forte`) | **1** |
| Vínculos criados pelo reconciliador (033) com presença | 0 de 23 |

Uma única presença confiável de aula experimental em toda a base — e é uma que alguém
marcou na mão. As outras 222 vêm do Emusys devolvendo `presente` sem marcação real: é o
mesmo fantasma que a Fase 2 (migration 012) já matou para a aula regular.

O caminho do Emusys não vai resolver isso: a API **não aceita escrita de presença**, e na
prática o campo chega vazio em 222 de 223 casos. Não é falta de vontade do professor; é um
caminho que não produz dado.

### O que se perde junto

Sem registro, quatro coisas não acontecem:

1. **Presença** — ninguém sabe se a experimental aconteceu.
2. **Continuidade** — quem matricula chega sem primeiro capítulo pedagógico.
3. **Conversão** — o comercial negocia sem saber como a criança se saiu.
4. **Retorno ao professor** — ele nunca fica sabendo que aquela aula virou matrícula.

Este design cobre 1, 2 e 3. O item 4 (retorno + gamificação) é projeto próprio — ver §9.

---

## 2. Decisões tomadas, e por quem

| # | Decisão | Quem decidiu |
|---|---|---|
| D1 | **A família nunca recebe mensagem do Fábio na fase experimental.** A devolutiva é insumo interno do consultor, que fala com a família do jeito dele. | Alf |
| D2 | **A entrega ao comercial é pelo Fábio**, não pelo n8n. | Alf |
| D3 | O registro mora em **tabela própria**, não em `fabio_registros_aula`. | medição (§4.1) |
| D4 | A presença segue **o mesmo padrão do aluno** — fonte marcada e precedência na escrita. | Alf |
| D5 | `faltou` + matrícula grava recibo, mas com `aluno_origem='conversao_sem_aula'`. | Alf (já implementado na 033) |
| D6 | Destinatário do aviso é **resolvido por unidade a partir do banco**; a pessoa é configuração, não código. | ver §4.3 |

### Por que D1 simplifica muito

Sem envio à família, somem da arquitetura: fila de envio ao responsável, resolução de
destinatário por idade, token de acesso, worker de entrega. E some o problema estrutural
de `fabio_devolutivas`, que exige `aluno_id` **e** `registro_fatia_id` ambos `NOT NULL` —
inviável quando o lead ainda não é aluno.

A fronteira não desaparece, muda de lugar: o texto que o consultor pode mostrar à família
não pode carregar a leitura de conversão junto. Vira separação de campos no mesmo
registro, verificável por teste (§7).

### Por que D2, apesar de o n8n já funcionar

O caminho do n8n (`Aviso Diario de Visitas`) entrega hoje, mas seu dedup é `staticData`
na memória do workflow: reimportar ou duplicar o fluxo apaga o histórico e as mensagens
repetem. Não há retry, não há recibo, e o rastro fica no `executionData`, que expira.

A fila do Fábio (`fabio_notificacoes`) tem `lease_token`, `tentativas`,
`proxima_tentativa_em` e `envio_recibo` — a máquina que a devolutiva de aula já usa e que
provou reenviar sem duplicar. Devolutiva de experimental é mensagem que não pode se perder
nem chegar duas vezes.

**Custo aceito:** `fabio_notificacoes.professor_id` é `NOT NULL`. Generalizar o
destinatário é trabalho real, já registrado como tarefa #58.

---

## 3. Fronteiras — o que nunca pode vazar

**A leitura de conversão nunca sai do círculo interno.** É a avaliação comercial que o
professor faz ("a mãe perguntou preço três vezes", "a criança não engajou, mas o pai
insistiu"). Serve ao consultor; destrói a relação se chegar à família.

A fronteira é **estrutural, não disciplinar**: campos family-safe e campo de conversão
ficam em colunas distintas, e a view que serve texto para a família **não seleciona** a
coluna de conversão. Não existe "lembrar de filtrar".

Isto segue a lição da devolutiva de aula (a fronteira mora no banco, o worker não vê campo
cru) e a da anamnese (omitir demais também causa dano — ver §5.2).

---

## 4. Arquitetura

Quatro componentes, cada um com uma responsabilidade e uma fronteira clara.

### 4.1 Componente 1 — `lead_experimental_registros` (tabela própria)

**Por que não reusar `fabio_registros_aula`:** medi os consumidores. Das 13 RPCs que leem
aquela tabela, **12 não filtram por `molde`** e 8 usam `aluno_id`. Duas são perigosas:

- `fabio_enfileirar_devolutivas` — enfileiraria devolutiva **para a família de um lead**,
  violando D1 diretamente;
- `fabio_emitir_presenca_por_registro` — tentaria escrever em `aluno_presenca`, que exige
  `aluno_id NOT NULL`.

Pôr a experimental na mesma tabela não é adicionar um molde: é abrir 12 pontos onde um
esquecimento vira vazamento, hoje e em cada RPC futura. Tabela própria torna o vazamento
**impossível por construção** — `fabio_enfileirar_devolutivas` literalmente não enxerga
essas linhas.

```sql
create table public.lead_experimental_registros (
  id                    uuid primary key default gen_random_uuid(),
  vinculo_id            bigint not null references public.lead_experimental_aulas(id),
  unidade_id            uuid not null references public.unidades(id),
  professor_id          integer references public.professores(id),

  -- BLOCO FAMILY-SAFE: o consultor pode mostrar/adaptar para a família
  anotacao_pedagogica   text,   -- o que foi trabalhado na aula
  devolutiva_familia    text,   -- como a criança se saiu, em linguagem de família
  proximos_passos       text,   -- o que faria sentido estudar em seguida

  -- BLOCO INTERNO: nunca sai para a família (fronteira em §3)
  leitura_de_conversao  text,   -- sinais comerciais, objeções, temperatura

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

-- Um registro vigente por vínculo (descartado não conta)
create unique index uq_lead_exp_registro_vigente
    on public.lead_experimental_registros (vinculo_id)
 where status <> 'descartado';
```

**Por que `vinculo_id` e não `aula_local_id`:** o vínculo já carrega o par
lead×aula com unicidade garantida pelos dois índices da 032. Apontar para ele evita
reabrir a pergunta "qual lead era esse mesmo?" e herda de graça a correção da 033.

**Sem `parent_id`/fatias:** o índice de ocupação da 032 garante um lead por aula. A
experimental é sempre individual — não existe turma para fatiar.

### 4.2 Componente 2 — presença no vínculo, padrão do aluno

A presença da experimental **já tem casa**: o vínculo da 032 é uma linha por par
lead×aula, exatamente o papel que `aluno_presenca` faz para o aluno. Não se cria tabela de
presença nova.

O padrão do aluno (migration 009) resolve sobrescrita **na escrita, uma vez**:

```sql
on conflict ... do update set respondido_por = excluded.respondido_por, ...
where aluno_presenca.respondido_por is null
   or aluno_presenca.respondido_por in ('emusys','sistema')
```

O professor sobrescreve o Emusys; o Emusys **nunca** sobrescreve o professor. E
`emusys_presenca_bruta` preserva o que o Emusys disse, cru, mesmo quando o professor
ganha. As duas fontes convivem sem se atropelar — que era a preocupação levantada.

Colunas novas em `lead_experimental_aulas`:

| coluna | papel |
|---|---|
| `presenca_status` | `presente` / `falta` |
| `presenca_respondido_por` | `professor_la_teacher`, `fabio_audio`, `professor_whatsapp`, `manual`, `emusys`, `sistema` |
| `presenca_respondido_em` | quando |
| `presenca_bruta_emusys` | o que o Emusys disse, preservado |

**O vocabulário de fonte é o mesmo do aluno, sem inventar valor novo.** A primeira versão
deste spec escreveu `professor_app` — valor que **não existe** na casa. Medido em
05/08/2026: `fn_presenca_e_forte('professor_app')` devolve `false`, e o CHECK de
`aluno_presenca.respondido_por` sequer o aceita. Presença vinda do app nasceria **fraca em
silêncio** — o fantasma que este spec existe para matar. Achado do Alfredo na revisão do
`4f00e94`.

Os valores válidos são exatamente os do CHECK existente:
`professor_whatsapp`, `professor_la_teacher`, `manual`, `sistema`, `emusys`, `fabio_audio`.
Registro pelo app grava `professor_la_teacher`; registro por áudio grava `fabio_audio`.
Ambos passam em `fn_presenca_e_forte`.

O CHECK da coluna nova **copia essa lista verbatim** — assim, um valor inventado é
rejeitado na escrita, em vez de virar presença fraca silenciosa.

Mesma `fn_presenca_e_forte`, mesma semântica de selo honesto. Quem sabe ler presença de
aluno lê esta igual.

**Duas fontes coexistem por tempo indeterminado** — o comercial marca no Emusys, o
professor manda áudio pro Fábio, e a transição dos professores para o LA Teacher é
gradual. A precedência resolve isso sem ninguém precisar combinar nada.

**Relação com `estado`:** `estado` é o ciclo de vida do vínculo (`vinculado`, `realizado`,
`faltou`, `cancelado`); `presenca_*` é a afirmação de comparecimento com fonte e hora.
Quando o professor registra presença forte, o reconciliador (033) passa a respeitá-la:
`presenca_status='presente'` promove `estado` para `realizado`, e o status do lead vindo
do comercial não regride isso — mesma regra que já protege `manual`.

#### Isto é migration própria, não efeito colateral

As 032 e 033 estão **aplicadas e carimbadas**. Mexer nelas exige migration nova e
declarada — o plano de implementação terá uma task só para isto, e ela não pode ficar
embutida em outra:

**Migration 034 — presença no vínculo.** Escopo fechado:

1. `alter table lead_experimental_aulas add column` para as quatro colunas
   (`presenca_status`, `presenca_respondido_por`, `presenca_respondido_em`,
   `presenca_bruta_emusys`), com o CHECK de fonte copiado verbatim do
   `aluno_presenca_respondido_por_check`.
2. `create or replace` da `fn_reconciliar_experimental_aulas` para respeitar fonte forte:
   presença forte do professor promove `estado` e **não é rebaixada** pelo status
   comercial — a mesma posição de guarda que hoje protege `manual` (primeiro `if` do laço,
   não um ramo do meio; ver o achado do commit `f42203e`).
3. Teste com fixtures `ZZTESTE` e os mutantes de §7 — obrigatoriamente incluindo o de
   **regressão comercial**: lead vira `cancelada`/`experimental_faltou` depois de o
   professor ter afirmado presença forte, e o `estado` **não** pode regredir.

A 033 já tem histórico de bug exatamente nessa área: o ramo de sync de
`experimental_realizada`/`convertido` promovia `faltou` para `realizado` porque só excluía
`realizado` do alvo. Toda alteração ali entra com mutante próprio.

### 4.3 Componente 3 — aviso ao comercial pelo Fábio

**Destinatário resolvido por unidade, a partir do banco.** A lição do n8n é direta: número
de pessoa escrito dentro do fluxo envelhece calado — o nó do Recreio ainda se chama
"Clayton" enquanto grava "Daiana", e ninguém viu.

```sql
create table public.unidade_contato_comercial (
  unidade_id   uuid primary key references public.unidades(id),
  nome         text not null,
  whatsapp     text not null,
  ativo        boolean not null default true,
  atualizado_em timestamptz not null default now()
);
```

Contatos vigentes (conferidos com o n8n em 05/08/2026, os três batem):

| Unidade | Pessoa | WhatsApp |
|---|---|---|
| Campo Grande | Vitória | `553171422022` (DDD 31 — ela é de Minas; está correto) |
| Barra | Kailane | `5521984690143` |
| Recreio | Daiana | `5521968060404` |

Confirmado pelo Alf em 05/08/2026: **Daiana é a comercial vigente do Recreio** — o Cleiton
era comercial e passou a gerente há cerca de um mês. É transição de equipe em andamento,
conhecida. Isto é exatamente o motivo de D6: em um mês a pessoa mudou, e o nó do n8n
continua chamado "Clayton". Contato em tabela se corrige com um `update`; contato dentro
de fluxo exige alguém lembrar que ele existe.

**Generalização da fila (#58):** `fabio_notificacoes.professor_id` passa a ser nullable,
com `destinatario_tipo` (`professor` \| `comercial`) e `destinatario_whatsapp`. Uma CHECK
garante que todo aviso tenha exatamente um destinatário resolvido. O worker existente,
com lease e retry, não muda de forma — só passa a saber para quem mandar.

O corpo do aviso monta-se **apenas** dos campos family-safe **mais** a leitura de
conversão — porque aqui o destinatário É o círculo interno. É o único lugar do sistema
onde os dois blocos aparecem juntos, e por isso está explicitamente marcado.

### 4.4 Componente 4 — view canônica

Uma única view serve LA Report e qualquer consumidor futuro, evitando a RPC duplicada que
já mordeu este projeto:

```sql
create view public.vw_experimental_registro_comercial as
select ...   -- inclui leitura_de_conversao (consumidor interno)
```

E uma view irmã, **sem** a coluna de conversão:

```sql
create view public.vw_experimental_registro_family_safe as
select ...   -- NUNCA seleciona leitura_de_conversao
```

**O nome descreve a garantia, não o destinatário** — e isso é deliberado. A primeira
versão chamava `..._familia`, o que sugeria que existe um caminho do Fábio para a família
nesta fase; não existe (D1), e um nome assim convida alguém a criar um depois, achando que
estava previsto. `family_safe` afirma a propriedade do conteúdo — *é seguro se chegar à
família* — sem prometer entrega. O destinatário operacional continua sendo o consultor.
Achado do Alfredo na revisão do `4f00e94`.

Duas views, não um parâmetro booleano: um flag errado vira vazamento; uma view que não
tem a coluna não pode vazá-la.

### 4.5 Escrita só por RPC canônica

**A tabela não é escrita direto.** Duas razões, ambas apontadas pelo Alfredo na revisão do
`3aed455`:

1. **O índice único rejeita, não reconcilia.** Ele garante que não existam dois registros
   vigentes, mas quem decide "isto é edição do que já existe" tem de ser código. Sem a
   RPC, a segunda gravação do professor vira `unique_violation` na cara dele em vez de
   edição.
2. **`unidade_id` e `professor_id` são derivados do vínculo, nunca digitados.** Se vierem
   do cliente, nasce registro incoerente — aula de uma unidade com registro carimbado em
   outra. A RPC lê os dois seguindo `lead_experimental_aulas` → `aulas_emusys` e **ignora**
   o que o chamador mandar nesses campos.

A RPC concentra também as travas de §6 (estado `pendente`/`faltou`/`cancelado`) e a
gravação de presença com a fonte correta (§4.2). `GRANT` apenas para os papéis que
precisam; escrita direta na tabela fica sem permissão — a garantia é de **permissão**, não
de convenção.

Mutantes correspondentes em §7.

---

## 5. Fluxo

### 5.1 Caminho feliz

1. Professor termina a experimental e grava áudio (app; WhatsApp em fase posterior).
2. Áudio entra em `fabio_fila_audios`, worker transcreve e monta os quatro blocos.
3. Registro nasce `aguardando_confirmacao` — o Fábio **nunca** inventa campo ausente;
   campo vazio vira cutucada na confirmação.
4. Professor confirma → `confirmado`.
5. Na confirmação, em transação: presença gravada no vínculo (fonte `fabio_audio`) e
   aviso enfileirado para o comercial da unidade.
6. Worker entrega por WhatsApp, com recibo.
7. Se converter, a 033 já grava o recibo de matrícula no vínculo (Contrato 3).

### 5.2 Declarar falta é ação separada de registrar aula

O caso mais comum hoje é a experimental que ninguém sabe se aconteceu (599 de 813). O
professor precisa conseguir dizer "não veio" **sem** que isso seja um registro pedagógico:

- **Declarar falta** — grava `presenca_status='falta'` com fonte forte e promove `estado`
  para `faltou`. Não cria registro. É um toque, não um formulário.
- **Registrar a aula** — pressupõe presença; cria o registro com os quatro blocos.

São dois caminhos distintos na mesma tela, e é por isso que §6 bloqueia registro em
vínculo `faltou`: quando se chega ali, a pergunta já foi respondida. O aviso ao comercial
também sai na falta — o consultor precisa saber que o lead não apareceu, e rápido. Nesse
caso o aviso não tem blocos pedagógicos, só o fato e o horário.

### 5.3 O que o professor escreve vs. o que o consultor recebe

A anotação pedagógica e a devolutiva vão inteiras — inclusive observações sobre
dificuldade, ritmo ou necessidade de apoio. A lição da anamnese vale aqui: **omitir também
causa dano**. O que se separa é a *leitura comercial*, não a verdade pedagógica.

---

## 6. Erros e casos de borda

| Situação | Comportamento |
|---|---|
| Vínculo `pendente` (aula ainda não casou) | Registro **bloqueado** — sem aula, não há o que registrar. Mensagem: "essa experimental ainda não está ligada a uma aula". |
| Vínculo `faltou` | Registro **bloqueado** (D5): aula não aconteceu, não há capítulo pedagógico. Declarar a falta é caminho próprio (§5.2), e gera aviso ao comercial sem blocos pedagógicos. |
| Vínculo `cancelado` | Registro bloqueado. |
| Unidade sem contato comercial cadastrado | Registro grava normalmente; aviso fica `pulada` com `motivo_pulada='sem_destinatario'` — visível, não silencioso. |
| Emusys marca presença depois do professor | Ignorado para `presenca_status`; preservado em `presenca_bruta_emusys`. |
| Professor registra duas vezes | O índice único **rejeita** (`unique_violation`) — ele não converte a segunda tentativa em edição. Quem transforma "já existe" em edição do vigente é a RPC canônica (§4.5); escrita direta na tabela não é caminho suportado. |
| Áudio inaudível / transcrição vazia | Registro fica `aguardando_confirmacao` com campos vazios e cutucada explícita — nunca texto inventado. |

---

## 7. Testes exigidos

Todo teste usa fixtures `ZZTESTE` em transação descartável (`scripts/rodar-teste-sql.mjs`),
e **cada defesa tem um mutante que a mata** — verde não-falsificado é decoração.

| Caso | Mutante que precisa morrer |
|---|---|
| `leitura_de_conversao` ausente da view da família | Adicionar a coluna à view família |
| Emusys não sobrescreve presença do professor | Remover o `where respondido_por in ('emusys','sistema')` |
| Professor sobrescreve presença do Emusys | Inverter a precedência |
| `presenca_bruta_emusys` preservada quando professor ganha | Fazer o update limpar a coluna bruta |
| Registro bloqueado em vínculo `faltou` | Remover a checagem de estado |
| Registro bloqueado em vínculo `pendente` | Remover a checagem de estado |
| Um registro vigente por vínculo | Remover o índice único parcial |
| Aviso sem destinatário vira `pulada`, não erro mudo | Trocar por `raise`/descarte silencioso |
| Presença forte do professor promove `estado` p/ `realizado` | Remover a promoção |
| Status comercial não regride presença forte | Remover a exclusão no ramo de sync da 033 |
| Declarar falta grava fonte forte e promove `estado` | Fazer a declaração gravar sem fonte (viraria fantasma) |
| Fonte inventada é rejeitada na escrita | Afrouxar o CHECK de `presenca_respondido_por` — o teste tenta gravar `professor_app` e exige rejeição |
| Segunda chamada da RPC **edita** o vigente, não estoura | Fazer a RPC sempre `insert` — o teste chama duas vezes e exige 1 linha vigente + conteúdo da 2ª |
| `unidade_id`/`professor_id` vêm do vínculo, não do chamador | Fazer a RPC aceitar os valores do parâmetro — o teste manda unidade errada e exige que o gravado seja o do vínculo |
| Escrita direta na tabela é negada por permissão | Conceder `insert`/`update` ao papel do app — o teste tenta escrever direto e exige erro de permissão |
| Toda fonte aceita pelo CHECK que representa professor passa em `fn_presenca_e_forte` | Trocar o valor gravado pelo app por um fora da lista forte |
| Falta gera aviso **sem** blocos pedagógicos | Fazer o aviso da falta montar o corpo completo |

**Asserções medem a rodada certa.** Onde houver função que devolve resumo, o teste guarda
o retorno da chamada sob teste (temp table) e asserta nele — nunca chama de novo para
conferir, porque a segunda rodada acha tudo resolvido e devolve zero naturalmente.

---

## 8. O que este design NÃO faz

- **Não manda nada para a família** (D1).
- **Não cria tabela de presença nova** — usa o vínculo da 032.
- **Não altera `fabio_registros_aula`** nem as 12 RPCs que a leem.
- **Não constrói tela** — LA Report consome a view; a tela é trabalho no outro repo.
- **Não mexe no n8n.** Decisão do Alf em 05/08/2026: o `Aviso Diario de Visitas` continua
  chamando como está, e o que houver para arrumar lá é do Hugo. O rótulo do nó do Recreio
  e a Daiana inativa em `staff_unidade` ficam registrados aqui só como contexto — não são
  trabalho deste spec nem dependência dele.

---

## 9. Próximos, fora deste spec

1. **Retorno ao professor + gamificação** — "aquele aluno que você atendeu se matriculou".
   Adiado pelo Alf ("depois vinha as gamificações"). O dado necessário já existe: a 033
   grava o recibo de matrícula no vínculo.
2. **Entrada por WhatsApp** — o professor mandando o registro por áudio no zap do Fábio.
   Adiado pelo Alf ("a gente vai plugar depois"). O `origem='whatsapp'` já está previsto
   no CHECK.
3. **Cron do reconciliador** — segue desligado até a etapa própria de agendamento e
   observabilidade.
4. **Tarefa #69** — filtro morto `'experimental_reagendada'` nas migrations 027c/027d/029.

---

## 10. Medições que sustentam este design

Todas verificadas em produção (`ouqwbbermlzqqvtqwlul`) em 05/08/2026:

- 813 experimentais não canceladas; 599 sem presença; 1 presença de fonte forte.
- 12 de 13 RPCs de `fabio_registros_aula` não filtram `molde`; 8 usam `aluno_id`.
- `fabio_devolutivas`: `aluno_id` e `registro_fatia_id` ambos `NOT NULL`.
- `leads.consultor_id`: 0 preenchidos em 1038 leads experimentais; `crm_conversas` vazia.
- `colaboradores.whatsapp`: 0 preenchidos em 13 colaboradores.
- Contatos do comercial vivem no n8n (`Aviso Diario de Visitas`), hardcoded por nó.
- 116 de 223 alunos com presença em experimental foram criados **depois** da aula.
