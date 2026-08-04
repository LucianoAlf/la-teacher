# A expectativa da aula experimental está na conversa da Mila

Levantamento de 04/08/2026, a pedido do Alf. Das 17 experimentais agendadas de
hoje em diante, 9 tinham expectativa no campo `observacoes` do webhook do Emusys.
As outras 8 (7 leads — o Rafael tem duas datas) estavam vazias.

**Resultado: 6 dos 7 têm qualificação feita pela Mila, e ela é melhor do que o
campo `observacoes`.**

---

## Correção de método (a primeira versão deste documento estava errada)

A primeira leitura pegou só a **última página** de mensagens (~20 por conversa) e
concluiu que *"a conversa acontece na inbox da Mila, mas quem conversa é humano —
a Mila só manda lembrete e confirmação"*.

Errado. As conversas têm **35 a 56 mensagens**, e a Mila é a autora principal em
5 dos 7. **A fase de qualificação dela é no começo** — exatamente o pedaço que
ficou fora da página lida. Foi preciso paginar com `before=<id>` até o início.

O sinal de alerta deveria ter vindo antes: existem inboxes `Mila_Barra`,
`Mila_CG` e `Mila_Recreio` separadas das de secretaria, e os workflows
`Agente SDR Mila CG` e `Agente SDR Mila Recreio` estão **ativos** no n8n. Havia
evidência de que ela atuava; eu li um recorte e afirmei sobre o todo.

---

## O que a Mila pergunta

Nome do responsável → para quem é a aula → **nome e idade do aluno** →
**qual instrumento ou tipo de música chama atenção** → **o que motivou a buscar
aulas** → período e data preferidos.

As duas do meio são o que nenhum outro sistema captura.

## O que ela levantou nestes 7

| Aluno | O que a conversa dá ao professor |
|---|---|
| **Pedro + Daniela Andrade**<br>Piano, 04/08 17h e 17h30 | *"Meus filhos faziam aulas de piano **em Portugal** e gostaram de voltar"*, *"estão pedindo para continuar"*, *"a Daniela também se interessou por canto, mas hoje pede o piano"*. **Não são iniciantes** — e são irmãos, aulas seguidas |
| **Samuel**, 4 anos<br>Musicalização Prep., 05/08 | *"Ele é bem musical, mas não sei se tem um instrumento específico. Ele também **gosta muito de cantar**"* · *"A princípio só para ele ter contato com a música"* |
| **Alice Cagnin**, 9 anos<br>Canto, 10/08 | *"**Não toca nenhum instrumento**, mas adora cantar, **canta todos os tipos de música**"* · nascimento 12/07/2017 · só depois das 18h · espera 1h de aula |
| **Maria Luiza**, 9 anos<br>Canto, 08/08 | *"Ela gosta de cantar"* · *"**canta muito em casa**"* · *"muita gente quando escuta pede pra eu colocar ela na aula de música"* |
| **Rafael**, 11 meses<br>Bebês, remarcado 12/08 | Creche das 10h às 17h — só depois das 17h · nascimento 30/08/2025 · perguntou preço e faixa etária antes de aceitar · remarcou por doença de mão-pé-boca |
| **Isadora**<br>Musicalização, 15/08 | *"**Sugestão da pediatra dela**"* · estilos: **músicas infantis e sertanejo** · responsáveis Larissa e Raphael |
| Davi Caetano<br>Violão, 05/08 | Só 2 mensagens, ambas da Mila — **o cliente nunca respondeu**. Agendou por outro caminho |

---

## O caso Isadora explica por que a observação não pode ser a fonte de idade

A conversa dela **começou em 22/11/2025**:

> **MILA:** *"Essas aulas são pra você ou pra um bebê? Me conta o nome e a idade."*
> **CLIENTE:** *"Isadora, 6 meses"*
> **MILA:** *"o que te motivou a buscar aulas de música pra ela?"*
> **CLIENTE:** *"Sugestão da pediatra dela"*

A observação no Emusys — *"Aulas para bebê, 6 meses, indicação da pediatra"* —
foi escrita dali. A experimental é **15/08/2026**, quase nove meses depois, e a
mesma conversa em julho já tinha o dado atualizado (*"1 ano e 2 meses"*, e
nascimento 14/05/2025 escrito duas vezes).

Hoje ela tem **1 ano, 2 meses e 21 dias**. Em musicalização para bebês, 6 meses é
colo e chocalho; 1a3m já anda e pega o instrumento. A professora ia preparar a
aula errada com um dado que a própria escola tinha corrigido.

**Regra: idade se calcula de `data_nascimento_aluno`. Nunca se lê do texto.**
O texto guarda a intenção (*"sugestão da pediatra"*), que não envelhece. A idade
não é intenção, é fato datado.

---

## O que isso decide

**A Mila é a fonte primária de expectativa.** O campo `observacoes` é um resumo
que alguém digitou a partir dela, com perda e sem atualização. As duas se
complementam, mas a ordem é: conversa primeiro, campo como reforço.

**Extrair exige LLM.** A informação está diluída em 35-56 mensagens de
"pode ser quarta?" e "❤️". Não sai com SQL nem regex.

**O extrator precisa ler a conversa INTEIRA.** Este documento existe porque a
primeira versão leu uma página e concluiu sobre o todo. Um extrator que pegue só
as últimas mensagens vai capturar logística e perder a qualificação — que é
sempre no começo.

**A fronteira vale aqui.** O mesmo material traz recado interno da recepção
(*"Ajustar data de nascimento, lançamento fictício"*) e dado de saúde
(*"doença de mão-pé-boca"*). O primeiro não passa. O segundo passa como aviso de
agenda — *"pediu remarcar por motivo de saúde"* — nunca como diagnóstico da
criança. Lista de permissão no banco, padrão `fn_devolutiva_fonte`.

---

## Pendências operacionais achadas de passagem

- **Rafael 05/08 é fantasma**: remarcado para 12/08 em 03/08 (a escola confirmou
  por escrito), mas a linha antiga ficou em `lead_experimentais`.
- **Beatriz Romero duplicada**: ids 1312 e 1314 — mesmo lead 11585, mesma data,
  mesmo horário, `emusys_aula_id` diferente (70087 e 70162).
- **`emusys_aula_id` é id de evento, não de aula**: o mesmo agendamento da Amelie
  chegou como 73172 no n8n e 73173 no observador. Dois disparos, dois ids, duas
  linhas. O que casou 17/17 foi `emusys_lead_id` + `data_experimental`.
