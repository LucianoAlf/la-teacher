# Cobrança da devolutiva da aula experimental — design

**Data:** 22/08/2026 · **Brainstorm com:** Alf · **Status:** aprovado, aguardando plano

## O problema

A devolutiva da aula experimental é o insumo que o comercial usa para converter o
lead. A máquina que a produz **está inteira e funciona** — o que falta é o
professor ser cobrado quando não a entrega.

Medido em 22/08/2026, janela de 30 dias, grão = aula:

| | |
|---|---|
| experimentais encerradas sem conteúdo | **169** |
| aparecem na cobrança (`vw_registro_pendencia`) | **23** |
| **invisíveis à cobrança** | **146** |
| dessas, com professor que tinha o app | **49** |
| devolutivas experimentais no sistema inteiro | **5** |

**Causa raiz:** `vw_registro_pendencia` faz `JOIN alunos al ON al.id = r.aluno_id`.
No roster de uma experimental o lead entra com **`aluno_id` NULO** (165 linhas
assim em 30 dias, contra 28 com `aluno_id`), e o INNER JOIN derruba a aula
inteira. O Fábio nunca cobrou uma experimental.

**O que NÃO é o problema** (verificado, para ninguém reabrir):

- A regra "professor lança → presença automática + aviso ao comercial" já existe
  e está correta (migration 038). Provado em ROLLBACK confirmando o registro do
  Antônio: `presenca_gravada: true`, `aviso_claimed: true`, notificação para o
  comercial `5521968060404`, corpo "Experimental registrada — Antônio Soares ·
  segunda 10/08 13:30 · presente".
- O canal está em produção: 2 avisos `experimental_registrada` **enviados** em
  18/08 (Noah Mondego 15:05, Malu Rodrigues 23:50).
- O carimbo que separa lead de aluno **já existe** em três camadas:
  `aulas_emusys.categoria` igual a experimental; no roster, `emusys_lead_id`
  preenchido com `aluno_id` nulo; e tabelas de registro separadas
  (`lead_experimental_registros` x `fabio_registros_aula`).

## Decisões do brainstorm

| # | Decisão | Escolha do Alf |
|---|---|---|
| 1 | Quando nasce a obrigação | Quando a equipe marca o lead como `experimental_realizada` — e o combinado passa a ser marcar presença **na chegada do lead à escola** |
| 2 | Cadência | Lembrete **ao fim da aula**, recobra no **fim do dia** e na **manhã seguinte**, escala à coordenação em **3 dias** |
| 3 | Professor sem o app | **Fica fora** até ser liberado (coerente com a régua de 22/08: não se cobra quem não tem a ferramenta) |
| 4 | Como o professor vê | **Uma** mensagem na recobrança, com **seção carimbada** para experimental; no app, badge **LEAD** na mesma lista |
| 5 | Onde a pendência mora | **View nova**, a régua de aluno fica intocada |

## Arquitetura

### `vw_experimental_pendencia` (nova)

Uma linha é pendência quando **todas** valem:

| Condição | Fonte |
|---|---|
| lead em `experimental_realizada` ou `convertido` | `lead_experimentais.status` |
| aula encerrada, não cancelada, canônica | `aulas_emusys` + `fn_aula_operacional_id()` |
| vínculo vigente e não cancelado | `lead_experimental_aulas` |
| **sem devolutiva CONFIRMADA** (nenhum registro em `confirmado`) | `lead_experimental_registros` |
| professor **com o app** | `fn_professor_usa_app()` |
| aula **a partir da data de corte** | `fn_data_corte_experimental()` |

Colunas de saída incluem `tipo_alvo` fixo em experimental, `nome_aluno` (o lead),
`vinculo_id`, `aula_id`, `professor_id`, `unidade_id`, `data_hora_fim` e
`horas_em_atraso` — o suficiente para a mensagem e o app renderizarem a seção e o
badge sem adivinhar nada.

### Funções novas

- `fn_data_corte_experimental()` devolve a data 2026-08-22.
  Espelha `fn_data_corte_cobranca()` (hoje em 21/07). **É a peça que evita a
  enxurrada:** sem ela, o dia 1 despeja **27 escalonamentos** de backlog na
  coordenação; com ela, o dia 1 nasce com **2 pendências**.
- `fn_janela_experimental_dias()` devolve 3.
  Separada de `fn_janela_registro_dias()` (7 dias) — mexer naquela mudaria a
  cobrança de todos os professores.

### Peça nova de execução (só uma)

`fabio_notification_worker.py --event experimental_lembrete --channel whatsapp`,
disparado por `fabio-experimental-lembrete.timer` com `OnUnitActiveSec=5min` e
`flock` (mesmo padrão de `fabio-devolutiva.timer`).

Pega aula experimental encerrada nos **últimos 20 minutos** — janela folgada de
propósito: se um tick falhar, o próximo ainda alcança, em vez de perder o
lembrete para sempre.

### Reaproveitado (nada novo)

| Momento | Unidade existente |
|---|---|
| Recobrança fim do dia (20:50 BRT) | `fabio-pendencia-noite` com `--event pendencia` |
| Recobrança manhã (8:30 BRT) | `fabio-pendencia-manha` com `--event pendencia` |
| Escalonamento (9:00 BRT) | `fabio-escalonamento` com `--event escalonamento` |

O evento `pendencia` passa a montar **uma seção adicional** com as experimentais
do professor. O evento `escalonamento` usa `fn_janela_experimental_dias()` para a
trilha experimental.

### Notificação

Tipo novo `pendencia_experimental` (o `pendencia_registro` do aluno fica
intocado). O lembrete sai **uma vez por vínculo, para sempre** — não uma por dia:
a chave do índice único é (`tipo`, `vinculo_id`), sem a data. Isso é
deliberado. O lembrete imediato existe para criar o hábito no calor da aula; se
o professor não gravou, quem insiste é a recobrança (noite e manhã) e depois o
escalonamento, cada um com sua própria trava. Repetir o lembrete imediato todo
dia seria uma quarta cobrança competindo com as outras três.

Sem a trava, rodar de 5 em 5 minutos mandaria a mesma cobrança 12 vezes por hora
— é a mesma proteção que já cobre o briefing, e o invariante 4 abaixo a mede.

## O que fecha a pendência

A devolutiva **confirmada** — não a gravada.

Gravar deixa o registro em `aguardando_confirmacao`, e **o comercial não recebe
nada nesse estado**: o aviso só dispara em `app_confirmar_registro_experimental`.
Evidência viva: as 3 devolutivas recuperadas em 22/08 (Antônio `6cb10906`, Raquel
`10bf797a`, Davi `ec77c23a`) estão aguardando confirmação e o comercial não as
recebeu. Se a pendência fechasse ao gravar, o Fábio pararia de cobrar exatamente
quando o comercial ainda está sem nada.

Confirmar dispara, na mesma transação que já existe: presença de fonte forte +
aviso ao comercial + pendência fecha.

⚠️ **A régua é allowlist (`status = 'confirmado'`), não denylist.** Descoberto na
execução da Task 1: `lead_experimental_registros.status` tem **DEFAULT
`'rascunho'`** e o CHECK aceita `rascunho | aguardando_confirmacao | confirmado |
descartado`. Um denylist do tipo `not in ('descartado','aguardando_confirmacao')`
trataria `rascunho` — o estado mais provável de qualquer caminho de escrita novo,
por ser o default — como "tem devolutiva", fechando a pendência **sem o comercial
receber nada**. A allowlist também erra do lado seguro: estado novo no futuro
mantém a pendência aberta (cobra demais, alguém vê) em vez de fechá-la (cobra de
menos, ninguém vê).

## Mensagens

**1) Lembrete imediato (~5 min após a aula)** — vende a ferramenta, cria o hábito:

> Experimental agora há pouco — Davi Nakashima, 18h
> Manda a devolutiva enquanto está fresco: o comercial usa ela pra falar com a
> família ainda hoje. É rápido — grava o áudio e confirma.

**2 e 3) Recobrança** — seção dentro da mensagem que ele já recebe (inventário,
não pitch):

> *Aulas* — 3 sem registro
> *Experimentais* — 1 sem devolutiva (Davi, ontem 18h) · o comercial está esperando

**4) Escalonamento (3 dias, para a coordenação):**

> Experimental sem devolutiva há 3 dias — Davi Nakashima (Barra, 13/08 18h), professor Isaque
> O comercial não recebeu o retorno dessa experimental.

## Corrida conhecida e aceita

Às 10:51 a equipe pode ainda não ter marcado a presença. Nesse caso **nada dispara
naquele momento**, e a pendência é pega no fim do dia. O desenho prefere perder o
lembrete imediato a cobrar o professor por uma aula que o sistema ainda não sabe
que aconteceu.

## Invariantes, testes e mutantes

Cada invariante tem teste e mutante; mutante vivo é trava sem teste.

| # | Invariante | Mutante que tem que morrer |
|---|---|---|
| 1 | A régua de aluno não muda — contagem de `vw_registro_pendencia` idêntica antes/depois | qualquer alteração na view antiga |
| 2 | Professor sem app nunca entra | remover `fn_professor_usa_app()` |
| 3 | Aula anterior a 22/08 nunca gera mensagem | remover a data de corte |
| 4 | Lembrete sai uma vez por vínculo | remover a trava de duplicata |
| 5 | Registro gravado e não confirmado **continua** pendente | fechar a pendência ao gravar |

Os invariantes 2 e 3 exigem **cenário sintético em transação com ROLLBACK**: com
os dados de hoje não existe professor inativo com login nem aula posterior ao
corte, então sem cenário montado esses mutantes sobrevivem e o teste vira
decoração. Antes de montar cenário por UPDATE temporário, conferir que os
triggers da tabela não chamam `net.http` — rollback não desfaz efeito externo.

## Rollout

1. **View + funções + testes.** Nada envia. Conferir o volume real com o corte
   valendo (esperado: 2 pendências, não 27).
2. **Primeiro envio real endereçado ao Alf.** A máquina roda inteira — detecta,
   monta, grava na fila, envia de verdade — com o destinatário sobrescrito para o
   WhatsApp do Alf. Existe porque ensaio que monta a mensagem e para antes de
   gravar passa verde e não prova nada: CHECK, índice único e resposta da UAZAPI
   só aparecem na execução real (aconteceu duas vezes em 22/08, com `erro_tipo` e
   com `casado_por`).
3. **Vira a chave.** Destinatário passa a ser o professor; acompanhar o primeiro
   dia e reportar o que saiu.

## Fora de escopo (YAGNI)

- Relatório das 96 experimentais de professor sem app — decisão (3) foi deixar
  fora.
- Promoção automática de faltou para realizado.
- Mexer no reconciliador (`fn_reconciliar_experimental_por_lead`): testado em
  22/08, moveria 2 linhas e 8 de 10 candidatos ficam bloqueados pelo índice único
  `uq_lead_exp_aula_ocupada`. Não é o gargalo.
