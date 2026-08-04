# Expectativa da aula experimental — o que existe fora do campo `observacoes`

Levantamento de 04/08/2026, a pedido do Alf. Das 17 experimentais agendadas de
hoje em diante, **9 têm expectativa escrita** no campo `observacoes` do webhook
do Emusys (gravado em `automacao_log.payload_bruto` pelo observador do Hugo).
As outras **8 (7 leads — o Rafael tem duas datas)** estavam vazias.

Fui buscar a conversa desses 7 no Chatwoot. **Todos os 7 têm conversa**, com
20-22 mensagens cada.

---

## O que a conversa entrega que o campo não entregava

**3 de 7 têm informação que muda a aula.** As outras 4 são só logística de
agendamento.

| Aluno | Curso / data | O que a conversa revela |
|---|---|---|
| **Rafael Alberigi** | Musicalização p/ Bebês | Nasceu **30/08/2025 (11 meses)**. Fica na creche das 10h às 17h — só depois das 17h. Pegou **doença de mão-pé-boca** e pediu remarcação |
| **Isadora Soares** | Musicalização Infantil, 15/08 | Nasceu **14/05/2025 (1a2m)**. **"Estilos musicais que gosta: músicas infantis e sertanejo"**. Responsáveis: Larissa e Raphael |
| **Alice Cagnin** | Canto, 10/08 | Espera **"1 horinha de aula"** |
| Pedro Andrade | Piano, 04/08 17:30 | Conheceu pelo Instagram. **"Pode agendar os dois — 17h e 17h30"** |
| Samuel | Musicalização Prep., 05/08 | Só logística |
| Maria Luiza | Canto, 08/08 | Só logística. Responsável se chama **Helo** |
| Davi Caetano | Violão, 05/08 | Cliente não escreveu nada — só a escola falou |

O caso da Isadora é o retrato do que se perde: a recepção **pediu** os estilos
musicais, a mãe **respondeu** ("músicas infantis e sertanejo"), e isso morreu no
Chatwoot. O campo `observacoes` do Emusys ficou vazio e a professora Adriana vai
entrar na aula sem saber.

---

## Dois achados operacionais que não eram o objetivo

**1. A experimental do Rafael em 05/08 é fantasma.** Em 03/08 ele foi remarcado
para **12/08 às 18h** (a escola confirmou por escrito). Mas `lead_experimentais`
tem **as duas linhas** — 05/08 e 12/08. A remarcação criou a nova sem encerrar a
antiga. A professora Ana Beatriz vê uma aula que não vai acontecer.

**2. Pedro Andrade não é um aluno, são dois.** A mãe pediu "agenda os dois,
17h e 17h30". Batendo com a agenda: 17:00 Daniela Andrade e 17:30 Pedro Andrade,
mesmo curso, mesma unidade, mesmo professor (Isaque). São da mesma família e o
professor recebe os dois seguidos — informação que muda como ele organiza a hora.

---

## O que isso decide sobre a arquitetura

**A expectativa não está estruturada.** Ela aparece no meio de ~20 mensagens de
"pode ser quarta?", "qual o endereço?", "obrigada ❤️". Não dá para extrair com
SQL nem com regex: exige leitura semântica.

Então o desenho é: **um passo de extração (LLM) lê a conversa + o campo
`observacoes` e grava o resultado tratado numa coluna**. O Fábio lê a coluna,
nunca o JSON bruto nem o Chatwoot ao vivo — que é o que o Alf apontou.

Isso conversa direto com a coluna de observações que o Hugo vai criar: a coluna é
o destino, e o extrator é quem a preenche.

**A fronteira vale aqui também.** O mesmo material traz coisas que não são
assunto do professor: recado interno da recepção ("Ajustar data de nascimento,
lançamento fictício"), e agora dado de saúde ("doença de mão-pé-boca"). O
primeiro não deve passar. O segundo **deve** — mas como aviso de agenda ("pediu
remarcar por motivo de saúde"), não como diagnóstico da criança. Lista de
permissão no banco, mesmo padrão de `fn_devolutiva_fonte`.

---

## Nota de método

A primeira rodada deu **"contato não encontrado" para 7 de 7** — e era erro meu:
o MCP devolve um envelope HTTP `{status, ok, headers, body}` e eu procurei
`payload` um nível acima. Só descobri porque 7/7 falhando é implausível demais
para ser verdade. Antes de concluir "não existe", testar o método contra um caso
que sabidamente existe.
