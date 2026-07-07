---
name: emusys-api
description: Referência completa da API Emusys para o projeto emusys-agent. Use sempre que o usuário estiver falando sobre Emusys, a edge function agent-chat, parâmetros de tools, endpoints da API, schema de aula, limitações do sistema, ou qualquer dúvida sobre o que a API consegue ou não fazer. Também use ao revisar eval results, discutir bugs do agente, ou planejar novas features que dependam da API.
---

# API Emusys — Referência

**Base URL:** `https://api.emusys.com.br/v1`  
**Auth:** Header `token: <token_da_escola>`  
**Versão atual:** 1.2.2  
**Rate limit:** 60 req/min por IP  
**⚠️ IDs são POR UNIDADE/ESCOLA:** `aluno_id`, `matricula_id`, `disciplina_id`, `id_professor` são namespaced por token. O mesmo número = pessoas/cursos diferentes em escolas diferentes (ex: `aluno_id=1082` → Samara/CG, Sofia/Recreio, Alice/Barra). **Sempre cruzar com a unidade.** `/matriculas` expõe a DISCIPLINA atual, não o "Nome do Curso" da tela (que congela no original quando o aluno troca de instrumento).  
**Docs:** https://emusys.gitbook.io/emusys/api-emusys  
**Changelog:** https://emusys.gitbook.io/emusys/api-emusys/historico-de-alteracoes-changelog

Para buscar detalhes de um endpoint, use `mcp__emusys__searchDocumentation` ou `mcp__emusys__getPage`.

---

## Endpoints disponíveis

### Aulas

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| GET | `/aulas` | Listar aulas por período |
| POST | `/aulas/cancelar` | Cancelar uma aula |
| PATCH | `/aulas/reagendar` | Reagendar uma aula |

#### GET /aulas — Parâmetros

| Parâmetro | Tipo | Obrigatório | Descrição |
|-----------|------|-------------|-----------|
| `data_hora_inicial` | datetime | Não | Início do período (ISO 8601). Se omitido, sem limite inferior |
| `data_hora_final` | datetime | Não | Fim do período. Se omitido, sem limite superior |
| `pessoa_id` | integer | Não | Filtra por ID da pessoa (aluno ou professor) |
| `lead_id` | integer | Não | Filtra por ID do lead |
| `cursor` | string | Não | Cursor de paginação (base64) |
| `limite` | integer | Não | Itens por página (default: 20) |

> ⚠️ **Não existe** filtro `apenas_canceladas`, `apenas_reagendadas`, `professor`, `sala` ou `curso` na API raw. Esses filtros são implementados pela edge function `agent-chat` (tools.ts) via pós-processamento do resultado.

#### Schema — objeto `Aula`

```
{
  id: integer,
  tipo: "individual" | "turma" | "ensaio",
  categoria: "normal" | "extra" | "reposicao" | "experimental" | "avulsa",
  turma_nome: string | null,
  curso_id: integer,
  curso_nome: string,
  cancelada: boolean,
  justificada: boolean,        // adicionado em 04/05/2026
  matricula_disciplina_id: integer | null,  // adicionado 21/06/2026; null em aulas de turma
  data_hora_inicio: datetime,
  data_hora_fim: datetime,
  duracao_minutos: integer,
  sala_id: integer | null,
  sala_nome: string | null,
  professores: ProfessorNaAula[],
  alunos: AlunoNaAula[],
  anotacoes: string | null
}

ProfessorNaAula: { id, nome, telefone, email, presenca: "presente"|"ausente", horario_presenca }
                 // id (ID da pessoa do professor) adicionado 21/06/2026
AlunoNaAula:    { id_aluno, id_lead, nome_aluno, email_aluno, telefone_aluno, presenca: "presente"|"ausente", horario_presenca, ... }
                 // id_aluno = ID da pessoa (null se ainda não tem matrícula); id_lead = ID do lead (0 se já cadastrado). Ambos adicionados 21/06/2026
```

> 💡 **`id_aluno`/`id_lead` em `AlunoNaAula` (21/06/2026)** eliminam o matching frágil por nome/telefone na reconciliação de presença/experimentais. Antes `/aulas` não trazia ID de aluno nem de lead.

> ⚠️ `presenca` só tem dois valores: `"presente"` ou `"ausente"`. Não existe `"nao_registrada"` na API. O campo `ja_iniciou` é **calculado** pela edge function comparando `data_hora_inicio` com o horário atual BRT.

#### POST /aulas/cancelar

```json
{ "aula_id": 123, "motivo": "...", "status_reposicao": "pendente"|"autorizada"|"negada" }
```

#### PATCH /aulas/reagendar

```json
{ "aula_id": 123, "nova_data": "YYYY-MM-DD", "novo_horario": "HH:MM", "sala_id?": 1, "professor_id?": 2 }
```

---

### Matrículas (adicionado 21/06/2026 — v1.2.0)

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| GET | `/matriculas` | Listar matrículas com dados do aluno, responsável, contrato atual e cobrança automática |

> 💡 **Único endpoint de PULL de contrato.** Antes, contrato só chegava por webhook (push). Agora dá pra puxar o estado atual sob demanda — viabiliza backfill de `data_fim_contrato`, contagem de renovações (`qtd_contratos`) e histórico de contratos.

#### GET /matriculas — Parâmetros

| Parâmetro | Tipo | Obrigatório | Descrição |
|-----------|------|-------------|-----------|
| `status` | string | Não | `ativa`, `trancada`, `finalizada` ou `todas` (default: `todas`) |
| `aluno_id` | integer | Não | Filtra pelo ID do aluno |
| `data_inicial` | date | Não | Matrículas **realizadas** a partir da data (`YYYY-MM-DD`) — filtra por data da matrícula |
| `data_final` | date | Não | Matrículas **realizadas** até a data (`YYYY-MM-DD`) |
| `limite` | integer | Não | 1 a 50 (default: 20) |
| `cursor` | string | Não | Cursor opaco de `paginacao.proximo_cursor` |

> ⚠️ `data_inicial`/`data_final` filtram pela **data da matrícula** (matrículas novas no período), **não** "matrículas ativas durante o mês". Para a foto de ativos use `status=ativa` (estado atual). Retorna o `contrato_atual`, **não** o histórico de contratos passados.

#### Schema — objeto da matrícula (resumo)

```
{
  id: integer,
  data_matricula: date,
  status: "ativa" | "trancada" | "finalizada",
  qtd_contratos: integer,              // nº de contratos da matrícula (proxy de renovações)
  aluno: { id, lead_id, foto_url,  // foto_url: URL da foto do aluno — NÃO documentado na spec, confirmado na API real 25/06/2026
           nome, data_nascimento, cpf, email, telefone, observacoes,
           endereco: {...}, campos_personalizados: [...] },
  responsavel: { id, nome, data_nascimento, cpf, email, telefone },
  contrato_atual: {
    id, data_original_primeira_aula, data_original_ultima_aula,
    plano, valor_mensalidade, valor_total, desconto_fixo, desconto_condicional,
    bolsa: boolean, nr_faturas, data_primeira_fatura, dia_vencimento, forma_pagamento,
    nr_aulas_contratadas, nr_aulas_passadas,
    inadimplente: boolean,           // NÃO documentado na spec, confirmado na API real 25/06/2026
    disciplinas: DisciplinaDeMatricula[]
  },
  cobranca_automatica: { id, forma_pagamento, status } | null   // null se não há cobrança ativa
}
```

#### Schema `DisciplinaDeMatricula` (enriquecido 21/06/2026)

Retornado em `contrato_atual.disciplinas` **e nos webhooks de matrícula**.

```
{
  matricula_disciplina_id: integer,    // ANTES era `id` — renomeado; é o vínculo matrícula-disciplina
  disciplina_id: integer,              // NOVO — ID da disciplina/curso em si
  nome: string,
  nome_professor: string,
  nr_aulas_contratadas: integer,       // NOVO
  nr_aulas_passadas: integer,          // NOVO — aulas que já ocorreram (independe de presença/falta)
  nr_aulas_futuras: integer,           // NOVO — aulas ainda agendadas
  agendamentos: [ { ..., sala_id, nome_sala } ]   // sala_id e nome_sala estavam TROCADOS — corrigido 21/06/2026
}
```

> ⚠️ **Breaking change:** quem lê `disciplina.id` nos webhooks de matrícula deve migrar para `matricula_disciplina_id` (vínculo) ou `disciplina_id` (curso), conforme o uso.

---

### Configuração (lookup)

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| GET | `/disciplinas` | Listar disciplinas ativas (`?tipo=individual\|turma`) |
| GET | `/professores` | Listar professores ativos (`?curso_id=N`) |
| GET | `/salas` | Listar salas ativas |
| GET | `/usuarios` | Listar usuários ativos do sistema |
| GET | `/instrumentos` | Listar instrumentos (usado no interesse do lead) |
| GET | `/crm/campos` | Listar campos personalizados configurados na escola (id, nome, tipo, opções válidas) |

---

### Faturas (adicionado v1.2.2 — testado via GET real em 07/07/2026)

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| GET | `/faturas` | Listar faturas/parcelas com valores, vencimento, status e desconto/juros aplicados |

#### GET /faturas — Parâmetros

| Parâmetro | Tipo | Obrigatório | Descrição |
|-----------|------|-------------|-----------|
| `status` | string | Não | `aberta`, `paga` ou `todas` (default: `todas`) |
| `matricula_id` | integer | Não | Filtra pela matrícula |
| `aluno_id` | integer | Não | Filtra pelo ID da pessoa (aluno) |
| `contrato_id` | integer | Não | Filtra pelo contrato (uma matrícula pode ter vários contratos ao longo do tempo — renovações) |
| `data_vencimento_inicial` | date | Não | Faturas com vencimento >= data (`YYYY-MM-DD`) |
| `data_vencimento_final` | date | Não | Faturas com vencimento <= data |
| `limite` | integer | Não | 1 a 50 (default: 20) |
| `cursor` | string | Não | Cursor opaco de `paginacao.proximo_cursor` |

#### Schema — item de `/faturas`

```
{
  id: integer,
  matricula_id: integer,      // visto = 0 em pelo menos 1 caso real (fatura "órfã", sem matrícula/contrato vinculado)
  contrato_id: integer,       // idem, pode ser 0
  aluno_id: integer,
  descricao: string,
  status: "aberta" | "paga",
  data_vencimento: date,
  data_pagamento: date | null,  // registros antigos podem vir "0000-00-00" em vez de null — tratar como não-pago
  valor_original: number,
  valor_pago: number | null,
  juros_e_multa: number,        // dinâmico antes de pago (0 se não venceu); fixo (valor cobrado) depois de pago
  desconto_aplicado: number,    // dinâmico antes de pago (desconto por antecipação vigente); fixo depois de pago
  desconto_fixo: number,        // configurado no contrato, não varia
  desconto_condicional: number  // regra configurada (não indica se foi de fato aplicado — ver desconto_aplicado)
}
```

> 💡 **`status=aberta` + `data_vencimento_inicial/final`** é a via direta pra inadimplência real por período (valor devido, não só o flag `contrato_atual.inadimplente` de `/matriculas`). Não existe filtro por `data_pagamento`, só por vencimento. Não existe filtro por unidade — a unidade é definida pelo `token` do header.

---

### Pessoas

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| GET | `/pessoas/buscar` | Buscar pessoa por `email`, `cpf` ou `telefone` (adicionado 03/06/2026) |

---

### CRM / Leads

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| POST | `/crm/leads` | Criar lead (`nome` e `numero` obrigatórios) |
| PATCH | `/crm/leads` | Atualizar lead por ID (`id` no corpo) |
| PATCH | `/crm/leads/por_telefone` | Atualizar lead por telefone (`numero` no corpo; telefone em si não é atualizado) |
| POST | `/crm/leads/anotacao` | Adicionar anotação por `id` (append-only) |
| POST | `/crm/leads/anotacao/por_telefone` | Adicionar anotação por `telefone` (append-only) |
| GET | `/crm/opcoes_como_conheceu` | Listar opções configuradas de "como conheceu a escola" |
| GET | `/crm/metricas` | Métricas do funil CRM por ano (`?ano=2026`, obrigatório) — mesmas métricas do painel, agrupadas por seção/mês |

---

### Aula Experimental

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| GET | `/crm/aula_experimental/disponibilidade` | Buscar horários disponíveis (`data` e `disciplina_id` obrigatórios; `professor_id?`, `sala_id?`) |
| POST | `/crm/aula_experimental` | Agendar aula experimental (`data`, `disciplina_id`, `horario` obrigatórios; localiza/cria lead por email ou telefone) |
| PATCH | `/crm/aula_experimental/reagendar` | Reagendar aula experimental (`aula_id`, `nova_data`, `novo_horario` obrigatórios; `sala_id?`, `professor_id?`) |

---

## Limitações conhecidas (gaps da API)

| Pergunta | Disponível? |
|----------|-------------|
| Filtrar aulas canceladas | ✅ via pós-processamento (campo `cancelada: true`) |
| Filtrar aulas justificadas | ✅ via campo `justificada: true` |
| Filtrar aulas reagendadas | ❌ **Não existe** — nem campo de status nem endpoint de listagem |
| Filtrar aulas por professor | ✅ via pós-processamento (campo `professores[].nome`) |
| Filtrar aulas por sala | ✅ via pós-processamento (campo `sala_nome`) |
| Filtrar aulas por curso | ✅ via pós-processamento (campo `curso_nome`) |
| Cancelar aula via API | ✅ `POST /aulas/cancelar` |
| Reagendar aula via API | ✅ `PATCH /aulas/reagendar` |
| Listar/puxar matrículas e contrato | ✅ `GET /matriculas` (desde 21/06/2026 — antes só via webhook push) |
| Vincular aluno/lead a uma aula por ID | ✅ `id_aluno`/`id_lead` em `AlunoNaAula` (desde 21/06/2026) |
| Consultar pagamentos/faturas | ✅ `GET /faturas` (desde v1.2.2, 07/07/2026) — detalhe fatura-a-fatura (valor, vencimento, status, desconto/juros). `/matriculas` continua trazendo `inadimplente: boolean` (não documentado) como flag agregado por contrato |
| Foto do aluno | ✅ `aluno.foto_url` em `/matriculas` (não documentado na spec oficial) |
| Listar leads existentes (funil) | ❌ Não existe endpoint de listagem |

---

## Aulas de turma — comportamento da API

A API retorna **um objeto por aluno** em aulas de turma, não um objeto por aula. Uma turma com 3 alunos retorna 3 registros com o mesmo `data_hora_inicio`, `curso_nome` e `professores`. O campo `turma_nome` identifica que é turma.

Implicação: ao listar aulas de uma sala/professor, aulas de turma aparecem N vezes. A edge function (tools.ts) deve agrupar ou o agente deve lidar com isso.

> ✅ **`professores[]` em aulas `turma` (corrigido, confirmado 07/07/2026).** Até 22/06/2026, aulas tipo `turma` retornavam `professores: []` vazio (só `individual` trazia o professor) — bug reportado ao Emusys. Reverificado ao vivo em 07/07/2026 nas 3 unidades da LA Music (CG, Barra, Recreio): 100% das turmas do dia vieram com `professores[]` preenchido (`id`, `nome`, `telefone`, `email`, `presenca`). Resolvido, provavelmente na mesma leva da v1.2.2 que trouxe `/faturas`.

---

## Webhooks disponíveis

`lead_criado`, `lead_editado`, `lead_arquivado`, `aula_experimental_criada`, `aula_experimental_reagendada`, `aula_experimental_cancelada`, `aula_cancelada`, `matricula_nova`, `matricula_renovacao`, `matricula_trancamento`, `matricula_finalizacao`, `matricula_alterada`

> ⚠️ **Nomes de evento corrigidos em 07/07/2026** — a versão anterior desta doc listava `matricula_renovada`/`matricula_trancada`/`matricula_finalizada`, que **não existem na API**. Os nomes reais (campo `evento` no payload) são `matricula_renovacao`, `matricula_trancamento`, `matricula_finalizacao`.
>
> **`matricula_alterada`** (novo, ainda não visto em produção em nenhum projeto até 07/07/2026): disparado em troca de curso/módulo/turma/disciplina/data. Payload traz `alteracao.descricao` (string HTML pronta, ex: `"Curso alterado de <b>Piano (Módulo 1)</b> para <b>Piano (Módulo 2)</b>"`) além do objeto `matricula` completo (mesmo schema de `matricula_nova`).
