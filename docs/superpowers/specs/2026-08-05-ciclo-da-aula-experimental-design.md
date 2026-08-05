# Ciclo da aula experimental — design

**Data:** 05/08/2026 · **v2.1** (v2 = achado da aula existente; v2.1 = 3 correções do Contrato 1)
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

### Contrato 1 — Vínculo lead ↔ aula (histórico e reavaliável)

> **v2.1 — três correções do Alfredo, todas certas.** A primeira versão deste
> contrato tinha `UNIQUE(lead_experimental_id)` + `ON CONFLICT DO NOTHING` e uma
> chave natural sem unidade. Cada uma dessas três se contradizia com outra parte
> da própria spec. Corrigidas abaixo, com o dado que fundamenta cada escolha.

A tabela `lead_experimental_aulas` é **histórico**, não estado atual:

```sql
create table public.lead_experimental_aulas (
  id                   bigserial primary key,
  lead_experimental_id integer not null references lead_experimentais(id),
  aula_emusys_id       integer references aulas_emusys(id),  -- NULL enquanto pendente

  -- ESTADO EXPLICITO: e ele que decide o que a rotina pode tocar
  estado               text not null default 'pendente',
    -- pendente  → sem par ainda; a rotina REAVALIA a cada rodada
    -- vinculado → casado pela chave natural; a rotina pode revincular se reagendar
    -- manual    → decisao humana; a rotina NUNCA sobrescreve
    -- realizado → a aula aconteceu; congelado
    -- cancelado → anotado; congelado
  motivo_pendencia     text,     -- sem_par | ambiguo   (so quando estado='pendente')
  casado_por           text,     -- chave_natural | manual

  criado_em            timestamptz not null default now(),
  vinculado_em         timestamptz,
  vinculado_por        text,
  substituido_em       timestamptz,   -- reagendamento: a linha sai de vigencia, NAO some
  cancelado_em         timestamptz,

  -- Contrato 3 (matricula com recibo)
  aluno_id             integer references alunos(id),
  aluno_vinculado_em   timestamptz,
  aluno_vinculado_por  text,
  aluno_origem         text
);

-- UNICIDADE PARCIAL: varias linhas por lead (o historico), UMA vigente.
-- `UNIQUE(lead_experimental_id)` cru — como estava na v2 — tornaria impossivel
-- guardar o vinculo antigo depois de reagendar, que a propria spec exige.
create unique index uq_lead_exp_aula_vigente
    on public.lead_experimental_aulas (lead_experimental_id)
 where substituido_em is null and cancelado_em is null;

-- Uma aula do Emusys nao pode servir a dois leads ao mesmo tempo.
create unique index uq_lead_exp_aula_ocupada
    on public.lead_experimental_aulas (aula_emusys_id)
 where aula_emusys_id is not null and substituido_em is null and cancelado_em is null;
```

**Por que tabela e não coluna em `aulas_emusys`:** aquilo é espelho do Emusys.
O sync não apaga (verificado), mas escrever lá nos faria depender disso para
sempre. A tabela é nossa, o espelho continua espelho.

#### A chave natural, fechada em SQL

```sql
select ae.id
  from public.aulas_emusys ae
 where ae.categoria    = 'experimental'
   and not ae.cancelada
   and ae.unidade_id   = le.unidade_id                    -- ← CORRECAO 3
   and ae.professor_id = coalesce(le.professor_experimental_id,
                                  l.professor_experimental_id)
   and (ae.data_hora_inicio at time zone 'America/Sao_Paulo')
       = (le.data_experimental + le.horario_experimental) -- tolerancia ZERO
```

**A unidade não é zelo, é necessidade medida.** Das 42 pessoas que dão
experimental, **26 dão em mais de uma unidade** e uma delas em três. Colisão real
(mesmo professor, mesmo horário, unidades diferentes) é zero hoje — com esse
número, é questão de tempo.

**A tolerância é zero, e isso é resultado, não preferência.** Medindo a diferença
entre `data_hora_inicio` (em São Paulo) e o horário do lead, sobre todos os pares
candidatos: **ou é 0 minuto (17 casos), ou é 180 (2 casos)**. E os de 180 não são
o mesmo evento deslocado — são **outra aula** do mesmo professor no mesmo dia.

> Qualquer tolerância entre 1 e 179 minutos seria número inventado: não existe
> caso nessa faixa. E ≥180 casaria com a aula errada. Zero é o único valor que o
> dado sustenta.
>
> Se um dia o Emusys deslocar um horário em 5 minutos, o par vira `sem_par`
> **visível** em vez de casar errado em silêncio — que é o lado certo para errar.

#### A rotina (idempotente e reavaliadora)

```
para cada experimental agendada/reagendada da janela:

  vinculo = vigente daquele lead

  se vinculo.estado in ('manual','realizado','cancelado'):
      NAO TOCA                        -- decisao humana e fato consumado sao finais

  se vinculo.estado == 'vinculado':
      se a aula ainda casa pela chave natural  → nada a fazer
      senao (reagendou)                        → substituido_em = now()
                                                 cria linha nova, volta ao topo

  se vinculo.estado == 'pendente' OU nao existe vinculo:
      procura pela chave natural acima
        exatamente uma → estado='vinculado', casado_por='chave_natural'
        nenhuma        → estado='pendente', motivo='sem_par'
        mais de uma    → estado='pendente', motivo='ambiguo'   (NAO escolhe)
```

**`ON CONFLICT DO NOTHING` foi removido — era a correção 2 do Alfredo.** Com ele,
um vínculo `sem_par` congelava: a rotina veria "já existe linha" e não faria
nada, e a aula que o Emusys criasse depois nunca seria ligada. O `estado` é o que
permite reavaliar o pendente **sem** correr risco de sobrescrever o que é final.

A unicidade parcial continua sendo a rede: mesmo com dois processos simultâneos,
o índice impede dois vínculos vigentes para o mesmo lead.

**Nunca apaga no escuro.** Reagendar marca `substituido_em`; cancelar marca
`cancelado_em`; aula que sumiu do Emusys **marca**, não remove. A prova de que
houve aula fica.

**`sem_par` e `ambiguo` não são erro — são fila de trabalho.** A coordenação vê e
resolve com `estado='manual'`, que a rotina passa a respeitar para sempre.
Silenciar isso seria repetir o cron que rodou onze vezes sem fazer nada.

### Contrato 2 — Máquina de estados

Transições de `lead_experimentais.status` e o efeito em cada peça:

| de → para | vínculo (`estado`) | registro | presença | devolutiva |
|---|---|---|---|---|
| — → **agendada** | cria: `vinculado`, ou `pendente` se não achou par | — | — | — |
| agendada → **reagendada** | linha atual ganha `substituido_em`; **linha nova** procura no horário novo | intocado | intocado | — |
| agendada → **cancelada** | `cancelado_em` + `estado='cancelado'`; **não apaga** | intocado | intocado | bloqueada |
| agendada → **realizada** | `estado='realizado'` — a rotina para de reavaliar | **habilita** | habilita | habilita após registro |
| realizada → **cancelada** | `cancelado_em`, mas `estado` continua `realizado` | preservado | preservado | preservada |
| realizada → **matriculada** | mantém; preenche as 4 colunas de recibo | preservado | preservado | — |

O `estado` é o que a rotina consulta antes de tocar em qualquer coisa:
`pendente` e `vinculado` são reavaliáveis; `manual`, `realizado` e `cancelado`
são finais. Sem essa distinção, ou a rotina congela pendências (o defeito que o
Alfredo apontou) ou atropela decisão humana.

Note a linha **realizada → cancelada**: marca `cancelado_em` mas o `estado`
continua `realizado`. Cancelamento posterior é anotação administrativa; a aula
aconteceu e o registro dela é fato.

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

**Ambiguidade.** Zero nos dados atuais com unidade + hora em São Paulo. Vai para
a fila de decisão humana, nunca para o chute.

**Professor em várias unidades.** 26 dos 42 que dão experimental, um deles em
três. Por isso a unidade entra na chave natural — sem ela, é só esperar duas
experimentais coincidirem em horário.

## Testes de fronteira exigidos

O que precisa falhar quando a defesa é removida (mutante entre parênteses):

| teste | mutante que ele mata |
|---|---|
| casa a aula certa de professor multi-unidade | remover `ae.unidade_id = le.unidade_id` |
| **não** casa aula 3h deslocada | trocar tolerância 0 por janela ≥180min |
| casa quando a hora está em São Paulo | comparar `data_hora_inicio` cru |
| reagendar deixa 1 vigente + 1 histórico | `UNIQUE(lead_experimental_id)` sem o `WHERE` parcial |
| `pendente` é preenchido quando a aula chega depois | voltar `ON CONFLICT DO NOTHING` |
| `manual` sobrevive a 20 rodadas | rotina reavaliar estados finais |
| cancelar aula realizada preserva registro | deletar em vez de marcar |
| a mesma aula não serve a dois leads | remover `uq_lead_exp_aula_ocupada` |
| devolutiva da família não contém leitura de conversão | a RPC ler o campo |

Todos com lead/professor/unidade `ZZTESTE` criados e descartados na transação —
**nenhum prontuário real vira bancada** (lição do Alfredo).

**Divergência de professor.** O vínculo usa
`coalesce(le.professor_experimental_id, l.professor_experimental_id)` — os dois
divergem em produção (lead 1351: 55 na experimental, 15 no lead). Quem manda é o
da experimental.
