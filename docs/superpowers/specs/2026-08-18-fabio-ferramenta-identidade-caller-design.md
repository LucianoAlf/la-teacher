# Ferramenta com identidade do caller — design

**Data:** 18/08/2026 · **Aprovado por:** Alf (17/08, desenho de 4 camadas)
**Fatia 1 de:** arquitetura de inteligência do Fábio (sair do regex)

## O problema, medido — não suposto

| fato | medida (17/08) |
|---|---|
| o papel do MCP existente lê tudo | `fabio_agent`: `rolbypassrls = true`, **SELECT em 412 tabelas** do `public`; zero INSERT/UPDATE/DELETE |
| o `postgres-mcp` roda destravado | `--access-mode=unrestricted`, URI com senha em texto no `config.yaml` |
| a ferramenta da casa aceita identidade do modelo | `fabio_presence_mcp.py`: `def fabio_buscar_presencas_pendentes_professor(professor_id: int)` — **o modelo escolhe de quem falar** |
| a fronteira de hoje é o canal | `platform_toolsets.api_server` tem o sentinela `no_mcp` (decisão de 09/08) |
| **mas o canal é compartilhado** | professor e admin chegam pelo MESMO endpoint: `127.0.0.1:8644/v1/chat/completions` |
| a consulta letiva é injeção, não ferramenta | `parece_consulta_letiva` + `resolver_periodo` (regex) montam um bloco no prompt |

**Conclusão que orienta o desenho:** identidade não pode ser argumento do modelo,
e canal não pode ser fronteira. Sobra a única coisa que o chamador sabe e o
modelo não: **quem mandou a mensagem**.

## O que já é viável (lido no fonte, não na doc)

`hermes_cli/tools_config.py:1587`:

> *"If the platform explicitly lists one or more MCP server names, treat that as
> an allowlist. Otherwise include every globally enabled MCP server."*

Listar o nome do nosso MCP no canal faz dele uma **allowlist**: o `lareport`
destravado não entra. É camada extra — não é a fronteira.

`hermes_cli/mcp_startup.py`: a descoberta de MCP é **global e em background**,
sem contexto de sessão. Então o MCP não tem como saber sozinho com quem o
Fábio está falando: **a identidade precisa viajar como capacidade** (token).

## Arquitetura — 4 camadas, nenhuma delas prompt

```
professor manda mensagem
        │
   bridge  ── sabe o professor_id pela LINHA do banco (não pelo texto)
        │      cunha token opaco (TTL curto, nº de usos limitado)
        │      grava só o HASH; injeta o token cru no prompt daquela conversa
        ▼
   Fábio (Hermes) ── decide QUAL ferramenta usar e passa o token adiante
        │
        ▼
   MCP nosso ── expõe SÓ ferramentas letivas; nenhuma aceita professor_id
        │
        ▼
   RPC escopada ── resolve token→professor_id, valida TTL/uso, filtra por ele
        │
        ▼
   papel restrito ── sem bypassrls, ZERO select em tabela, só EXECUTE nas RPCs
```

**Camada 1 — papel `fabio_professor_agente`.** Sem `bypassrls`. **Nenhum**
`SELECT` em tabela. Só `EXECUTE` num punhado de RPCs. É o chão: mesmo que as
camadas 2–4 falhem todas juntas, essa credencial não lê uma linha de
financeiro — por falta de permissão, não por regra.

**Camada 2 — a RPC recebe token, não `professor_id`.** O modelo escolhe
argumentos; ele não escolhe identidade. Token inventado não resolve; token de
outro professor ele não tem como descobrir.

**Camada 3 — MCP próprio.** Conecta com o papel restrito e expõe só o
conjunto letivo. **O que não existe como ferramenta não existe como resposta:**
financeiro, repasse, mensalidade, contrato, folha, valor de aula e dados de
outro professor não têm função — não é instrução de prompt.

**Camada 4 — allowlist no canal.** Cinto, não fronteira, porque o canal é
compartilhado com o admin.

## Contrato do token

| propriedade | decisão | por quê |
|---|---|---|
| formato | opaco, 32 bytes aleatórios, base64url | nada derivável do professor |
| armazenado | **só o hash** (sha256) | vazamento do banco não vira capacidade |
| log | **só os 8 primeiros do hash** | exigência do Alf; token inteiro nunca em log |
| TTL | 10 minutos | curto o bastante pra um repasse acidental morrer sozinho |
| usos | limitado (8) | "uso único" inviabilizaria 2 ferramentas na mesma resposta; o limite baixo dá o mesmo efeito prático |
| vínculo | professor + conversa | um token não atravessa professores |
| no prompt | apresentado como **handle opaco**, com instrução explícita de nunca exibir | mitigação, não fronteira — a fronteira é o escopo da RPC |

⚠️ **Risco declarado:** o token trafega no prompt, então o modelo *pode* ecoá-lo.
Isso não é elevação de privilégio (é a capacidade do próprio professor sobre os
próprios dados), e o TTL curto limita a janela. A alternativa — identidade por
sessão do MCP — **não existe hoje no Hermes** (medido acima).

## Fatia 1 — as duas primeiras ferramentas

Migram a capacidade que JÁ está em produção e que a gente sabe conferir:

- `fabio_prof_aulas_periodo(p_token, p_inicio, p_fim)` → delega para
  `fabio_professor_resumo_aulas`
- `fabio_prof_presencas_periodo(p_token, p_inicio, p_fim)` → delega para
  `fabio_professor_presencas_periodo`

As duas RPCs de baixo já existem, já são escopadas por `professor_id` e já
tratam a armadilha da aula-gêmea (dedup por balde). O que nasce aqui é a
**porta com identidade**, não o cálculo.

## Como isto será falsificado (senão é decoração)

1. **O número não pode mudar:** Valdo (36), 11–15/08 → **36 aulas**, 25 em
   Campo Grande e 11 no Recreio. É o mesmo número provado em 17/08.
2. **Pedido de financeiro** → o Fábio não tem ferramenta; a resposta certa é
   mandar pro financeiro, sem número.
3. **Pedido sobre outro professor** → a ferramenta **não aceita** esse
   argumento; o dado retornado é sempre do dono do token.
4. **Token expirado / inventado / de outro professor** → recusa explícita.
5. **Mutantes** em cada guarda (TTL, usos, revogação, vínculo), mortos por
   asserção — e o baseline re-rodado por mim, não relatado por terceiro.
6. **Medir o que o agente ENXERGA**, não o que o config diz: os medidores do
   Hermes já mentiram antes (`plugins.enabled`, `/v1/toolsets`).

## Erro e degradação

- Token inválido/expirado → a RPC devolve recusa estruturada; o Fábio **pergunta
  de novo** em vez de inventar, e nunca promete "vou conferir e te trago".
- MCP fora do ar → o Fábio segue conversando sem a ferramenta; o bloco injetado
  de hoje **permanece** durante a transição, como rede.
- Nada é removido do caminho atual nesta fatia: a consulta letiva por injeção só
  sai depois da ferramenta provada em uso real.

## Fora de escopo (fatias seguintes)

Registro por WhatsApp saindo do regex; ferramentas de aluno/carteira/agenda;
aposentar o bloco injetado; skills por faixa etária.
