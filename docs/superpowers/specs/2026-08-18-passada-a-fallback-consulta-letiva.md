# Passada A — rede de segurança da consulta letiva

**Decidido pelo Alf em 18/08/2026.** Contrato dele, na íntegra, na seção
"Contrato obrigatório". Este documento acrescenta só o que eu medi.

## O que é

Quando o professor pergunta sobre a própria vida letiva e o **extrator
determinístico** não consegue montar a consulta, uma segunda passada no modelo
extrai `{consulta, inicio, fim, unidade}` — e **o bridge executa**, com o
`professor_id` que ele já tem da linha. O modelo diz *o quê*, nunca *de quem*.

Não é substituto: o determinístico continua sendo o caminho rápido.

## Contrato obrigatório (palavra do Alf)

1. O determinístico roda primeiro.
2. Se o determinístico extrair com confiança, **não** chama A.
3. A só roda quando o determinístico voltar vazio ou ambíguo.
4. A usa prompt próprio, curto e schema fechado.
5. A **nunca** pode devolver ou escolher `professor_id`.
6. `professor_id` continua vindo exclusivamente do bridge/linha/sessão.
7. A só pode extrair: intenção (consulta letiva ou não), métrica
   (aulas/presenças), período (início/fim) e unidade, se citada.
8. Se A falhar, o Fábio **pergunta**. Não chuta.
9. Teste obrigatório: prompt tentando induzir `professor_id` precisa morrer —
   retorno válido não pode conter esse campo.
10. Teste obrigatório: schema exato; campo extra é rejeitado.

Fora de escopo, por decisão: MCP, financeiro, `professor_id` no modelo, e a
camada 1 de sábado.

## Os dois fatos medidos que moldam o desenho

**1. A passada extra custa ~7s, e o prompt curto não é economia — é a trava.**

| | mediana |
|---|---|
| hoje, uma passada | 8,3s |
| passada A sozinha | ~7s |
| duas passadas | ~15–16s |

Encolhi o prompt de A de **12.024 → 424 chars** (28×) e economizei só **0,6s**:
o custo é overhead fixo do gateway, não prefill. Mas com o prompt **cheio** a
passada A **derivou** — inventou nome de campo (`aulas_ministradas`) e incluiu
`professor_id` na resposta. Com o prompt curto saiu o schema exato, 4/4. Por
isso o item 4 do contrato não é estilo: é o que mantém o modelo longe de
escolher identidade.

**2. O gate largo é o gate errado.** Varri as **165 mensagens de professor dos
últimos 60 dias**:

| | mensagens |
|---|---|
| o gate de hoje (`parece_consulta_letiva`) pega | 12 |
| um gate largo pegaria | 37 |
| **só o largo pega** | **30** |

Olhando as 30, a maioria **não é consulta**: são *registro de aula* ("quero
registrar a aula de piano T, turma P_QUI_19, do dia 6 de agosto") — caminho da
máquina, onde rodar A é custo puro — e *carteira* ("quantos alunos eu tenho no
total e por unidade?"), que está fora da métrica de A por contrato.

⚠️ **Consequência honesta:** no corpus de 60 dias, depois do conserto do parser
(`ce46ad7`), **não sobrou uma consulta letiva que A resgataria**. A razão para
construir A não é o que o corpus mostra — é a cauda que ele não enumera, e o
canal só está com `CONSULTA_LETIVA_MODO=todos` desde 17/08. Por isso A nasce em
**shadow**: calcula, loga e **não injeta**, até a medição dizer que vale ligar.
É o mesmo caminho que a consulta letiva já percorreu.

## Desenho

```
mensagem do professor
  └─ máquina de registro já recusou?   (se não, nem chega aqui)
       └─ montar_chamada_consulta()  ── achou? ──> RPC + injeta   [caminho rápido]
            │ None
            └─ deve_tentar_fallback(texto)? ── não ──> pergunta o período
                 │ sim
                 └─ run_hermes_api(prompt curto)
                      └─ validar_pedido()  ── inválido ──> pergunta o período
                           │ válido
                           └─ mesma RPC do caminho rápido, professor_id DA LINHA
```

`validar_pedido` é onde a fronteira vive, e é pura — dá para atacá-la em teste
sem subir o bridge, igual `montar_chamada_consulta`.

### Regras de validação (schema fechado)

- Campos permitidos: **exatamente** `consulta`, `inicio`, `fim`, `unidade`.
  Qualquer chave fora disso **rejeita o payload inteiro** — não "limpa e segue".
- `professor_id` (ou qualquer chave contendo `professor`) rejeita e **loga**:
  é sinal de que o modelo saiu do schema, não um campo a ignorar.
- `consulta` ∈ {`aulas_periodo`, `presencas_periodo`, `nenhuma`}.
  `nenhuma` → não injeta nada (não é falha: é A dizendo que não era consulta).
- `inicio`/`fim`: ISO, `inicio <= fim`, janela ≤ 92 dias, dentro de ±2 anos de
  hoje. Fora disso, rejeita.
- `unidade`: só passa se casar com a lista de unidades reais; texto livre nunca
  chega na RPC.
- Rejeitar sempre cai no mesmo lugar: **o Fábio pergunta o período**.

### Por que rejeitar o payload inteiro, e não só tirar o campo

Tirar o campo faz o sistema funcionar e **esconde** que o modelo desobedeceu.
O item 9 do contrato pede o oposto: que morra. Rejeitar transforma desvio de
schema em evento visível no log, e o custo do falso negativo é baixo — o
professor é perguntado, que é o comportamento honesto de sempre.
