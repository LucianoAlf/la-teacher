# Ciclo da aula experimental — design

**Data:** 05/08/2026 · **v2** (reescrita depois da revisão do Alfredo)
**Decisão do Alf:** *"isso daqui é ouro"* (registro) e *"cabe junto, trata tudo
da questão de experimental"* (agenda). Um assunto só.

> **v1 → v2:** a v1 desenhava criar uma "aula sintética" com `emusys_id`
> negativo. **Estava errada.** A aula experimental já existe em `aulas_emusys`
> há meses — 846 delas — porque o Emusys já a envia com
> `categoria = 'experimental'`. Eu tinha olhado a coluna `tipo` (ensaio,
> individual, turma) e concluído que não existia.
>
> O erro foi achado indo verificar o item 5 da revisão do Alfredo ("valide o
> `emusys_id` negativo em todos os consumers"). Ao varrer os consumers, apareceu
> `emusys-aulas.test.ts` com `categoria: "experimental"` num payload do Emusys.
>
> **Tudo que a v1 chamava de risco maior — id negativo, colisão com o sync,
> poluir o espelho — desaparece.** Não se cria aula nenhuma.

## O problema

A aula experimental é a aula que decide se existe um aluno. Hoje ela acontece e
**some**: não aparece para o professor, ninguém registra como foi, e não vira
nem devolutiva nem dado. A escola não aprende o que converte.

Metade do ciclo já está no ar (migrations 027*, 028, 029): o contexto do que a
família contou à Mila chega ao professor **antes** da aula. Esta spec fecha o
resto.

```
contexto antes  →  o professor vê  →  conduz  →  registra  →  converteu ou não
   ✅ no ar         ←──────────── esta spec ────────────→          ↑
                                                          alimenta o próximo
```

## O que o levantamento mostrou

Todas as medições são de 05/08/2026, em produção.

**1. A aula experimental já existe.** `aulas_emusys.categoria` tem
`normal` (50.977), **`experimental` (846)** e `extra` (36). Vêm do Emusys pelo
sync. Não há nada a criar.

**2. O `emusys_aula_id` do lead não aponta para ela.** Das 17 experimentais da
janela do extrator, **17 têm o campo preenchido e 0 casam** com
`aulas_emusys.emusys_id`. Confirma a suspeita da tarefa #57: é id de evento.
(No histórico completo 119 de 445 casam, e desses 117 batem professor e data —
o campo teve significados diferentes ao longo do tempo.)

**3. A ligação por chave natural funciona — no fuso certo.** Casando por
`professor + categoria='experimental' + data/hora`:

| critério | casam | ambíguos |
|---|---|---|
| hora crua (UTC) | **1** de 17 | 0 |
| hora convertida para São Paulo | **16** de 17 | **0** |

`data_hora_inicio` é UTC; `horario_experimental` é hora local. É a terceira vez
que o fuso morde neste projeto — na 027c cortou o dia às 21h, e aqui derrubaria
15 de 16 casamentos.

O 1 que não casa (Felipe Salgado Portella, 08/08) não tem **nenhuma** aula
experimental daquele professor naquele dia. É o caso real de "lead marcado, aula
não criada no Emusys" — e é ele que define o que a máquina de estados faz quando
não há par.

**4. Aluno sem cadastro já é suportado.** `aula_alunos_emusys.aluno_id` é
nullable, com **942 linhas** já assim, identificadas por `aluno_nome`.

**5. O motor de registro já existe e é genérico.** `fabio_registros_aula` tem
`molde`, `campos` (jsonb), `origem`, `audio_id`, `parent_id` e fluxo de
confirmação. Roda hoje com **um** molde (`C`), 41 registros, origem `app`.

**6. Nenhum consumidor valida sinal de `emusys_id`** e o menor valor hoje é
43.582 — a informação que motivou a v1. Fica registrada como irrelevante para o
desenho atual, e útil se um dia precisarmos mesmo de aula sintética.

## Arquitetura

**A experimental já é uma aula. O trabalho é ligá-la ao lead e usar o que existe.**

### Contrato 1 — Vínculo lead ↔ aula (idempotente)

Uma tabela de vínculo explícita, `lead_experimental_aulas`:

| coluna | papel |
|---|---|
| `lead_experimental_id` | **UNIQUE** — um lead tem no máximo uma aula vigente |
| `aula_emusys_id` | FK para `aulas_emusys(id)` |
| `casado_por` | `chave_natural` \| `manual` \| `emusys_id` — como o par foi feito |
| `confianca` | `exato` \| `ambiguo` \| `sem_par` |
| `vinculado_em`, `vinculado_por` | recibo |

**Por que tabela e não coluna:** o Alfredo pediu "chave/índice único
`lead_experimental_id` na aula local". Uma coluna em `aulas_emusys` seria
escrever no espelho do Emusys — o sync não apaga, mas passamos a depender disso.
A tabela de vínculo é nossa, o espelho continua sendo espelho, e o UNIQUE mora
onde deve.

**Idempotência (roda 20 vezes, mesmo resultado):**

```
para cada experimental agendada/reagendada da janela:
  1. já existe vínculo vigente?  → não faz nada
  2. procura aula: categoria='experimental' + professor + data/hora EM SÃO PAULO
  3. exatamente uma  → vincula (casado_por='chave_natural', confianca='exato')
     nenhuma         → registra confianca='sem_par' e SEGUE (não inventa aula)
     mais de uma     → registra confianca='ambiguo' e NÃO escolhe
  4. o insert usa ON CONFLICT (lead_experimental_id) DO NOTHING
```

**Nunca apaga no escuro.** Se o Emusys criar a aula depois, o vínculo
`sem_par` é preenchido pela mesma rotina, sem tocar em registro nem em presença.
Se a aula vinculada sumir do Emusys, o vínculo é **marcado**, não removido — a
prova de que houve aula fica.

`sem_par` e `ambiguo` não são erro: são **fila de trabalho**. A coordenação vê e
resolve com `casado_por='manual'`. Silenciar isso seria repetir o cron que rodou
onze vezes sem fazer nada.

### Contrato 2 — Máquina de estados

Transições de `lead_experimentais.status` e o efeito em cada peça:

| de → para | vínculo | registro | presença | devolutiva |
|---|---|---|---|---|
| — → **agendada** | cria (ou `sem_par`) | — | — | — |
| agendada → **reagendada** | **revincula**: solta o antigo (marcado `substituido_em`), procura no novo horário | intocado | intocado | — |
| agendada → **cancelada** | marca `cancelado_em`, **não apaga** | intocado | intocado | bloqueada |
| agendada → **realizada** | congela: revínculo automático **desligado** | **habilita** | habilita | habilita após registro |
| realizada → **cancelada** | marca, mas **mantém tudo** | preservado | preservado | preservada |
| realizada → **matriculada** | mantém | preservado | preservado | — |

Duas regras que o Alfredo nomeou, escritas como invariantes testáveis:

- **Reagendar não deixa aula fantasma.** Depois de reagendar, o lead tem
  exatamente um vínculo vigente. O antigo fica com `substituido_em` preenchido —
  visível no histórico, invisível na agenda.
- **Cancelar não apaga histórico de aula realizada.** Se existe registro de aula
  confirmado, o cancelamento é anotação, nunca remoção. Aula que aconteceu
  aconteceu.

### Contrato 3 — Matrícula com recibo

Preencher `aluno_id` não basta. A conversão é um **evento com prova**:

| coluna (em `lead_experimental_aulas`) | o quê |
|---|---|
| `aluno_id` | o aluno criado |
| `vinculado_aluno_em` | quando |
| `vinculado_aluno_por` | quem/o quê (`emusys_sync`, `coordenacao:<usuario_id>`, `fabio`) |
| `vinculado_aluno_origem` | como a experimental foi encontrada |

**Quem dispara:** a matrícula nasce no Emusys. A rotina que descobre
`leads.aluno_id` preenchido é a mesma que fecha o ciclo aqui — não há passo
manual obrigatório, mas há registro manual possível.

**Como encontra a experimental certa:** pelo `lead_id`, a experimental
`realizada` mais recente. Se houver mais de uma, é `ambiguo` e vai para a fila,
não para o chute.

Sem essas quatro colunas, "primeiro capítulo do histórico" é promessa. Com elas,
dá para responder *"quantos alunos deste professor vieram de experimental que
ele mesmo deu?"* — que é a pergunta que a escola quer.

### Contrato 4 — A fronteira do registro, na estrutura

O registro tem quatro blocos (escolha do Alf):

| bloco | quem pode ver |
|---|---|
| **Como foi a aula** (pedagógico, nível real observado) | professor, coordenação, próximo professor |
| **Devolutiva pra família** | professor, coordenação, **família** |
| **Leitura de conversão** (interesse, dúvida, resistência) | professor, coordenação — **nunca a família** |
| **Encaminhamento sugerido** (curso, nível, professor) | professor, coordenação |

**A separação vive na RPC/view, não na tela.** Do mesmo jeito que
`fn_experimental_contexto_seguro` (migration 029) filtra dinheiro campo a campo:
a função que monta o texto para a família **não lê** `leitura_de_conversao`. Não
é "escondido no front" — é inacessível por construção. E, como em toda fronteira
deste projeto, com mutante no teste provando que a remoção é detectada.

**A devolutiva nunca sai sozinha:** prévia antes de enviar, humano aprova.

### O que o professor vê

A agenda já lê de `aulas_emusys`, então a experimental **já pode aparecer** — o
trabalho é destacar `categoria='experimental'` e trazer junto o contexto da 029.
Sem inventar tela nova.

## Escopo e ordem

Ordem sugerida pelo Alfredo, ajustada ao achado (a etapa de aula sintética
morreu):

1. **Migration**: `lead_experimental_aulas` + índices + constraints
2. **Reconciliador** + testes das transições de estado (lead QA sintético)
3. **Agenda/UI**: destaque de experimental + contexto na mesma tela
4. **Molde do registro** + prévia da devolutiva + fronteira em RPC
5. **Vínculo de matrícula** com recibo
6. **E2E com lead QA**

**Nenhum prontuário real de aluno vira bancada de teste** (lição do Alfredo). Os
testes usam lead/professor/unidade sintéticos com prefixo `ZZTESTE`, criados e
descartados na mesma transação — como já é feito nas migrations 027d e 029.

## O que fica de fora

- **Registro por áudio no WhatsApp** — no radar do Alf; o motor já tem
  `audio_id` e `origem`, então o molde nasce pronto para receber
- **Consertar o `emusys_aula_id` na origem** — reconciliamos por chave natural;
  investigar por que o campo guarda id de evento é trabalho do lado do Emusys
- **Relatórios do Fábio** (#47–49), que o Alf quer retomar depois desta

## Riscos

**O fuso.** Já derrubou 15 de 16 casamentos no teste. Toda comparação de horário
converte para São Paulo, explicitamente, e o teste tem um caso em horário que só
passa no fuso certo.

**Aula que não existe no Emusys.** 1 em 17 hoje. Vira `sem_par` visível, não
erro silencioso — e é a razão de a rotina não inventar aula.

**Ambiguidade.** Zero nos dados atuais com hora em São Paulo, mas dois
professores com duas experimentais no mesmo horário quebrariam. Vai para a fila
de decisão humana, nunca para o chute.

**Divergência de professor.** O vínculo usa
`coalesce(le.professor_experimental_id, l.professor_experimental_id)` — os dois
divergem em produção (lead 1351: 55 na experimental, 15 no lead). Quem manda é o
da experimental.
