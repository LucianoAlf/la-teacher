# Pendências detalhadas no chat do Fábio — design

**Status:** aprovado pelo Alf em 12/08/2026 para implementação e liberação no teste geral.

## Relação com as SPECs existentes

As SPECs de 10/08 e 11/08 continuam autoritativas para o motor único, os dois
pools, a identidade por telefone, o preview, a confirmação e a escrita. Este
recorte não cria uma terceira porta e não altera nenhuma RPC de escrita. Ele
fecha somente o contexto de leitura usado quando o próprio professor pergunta
quais pendências ainda possui.

## Problema medido

`fabio_contexto_professor` informa a quantidade de pendências cobraveis, mas não
leva a lista de aulas e alunos ao prompt. As RPCs canônicas já devolvem o detalhe:

- `fabio_pendencias_professor(professor_id)` para conteúdo sem registro;
- `fabio_presencas_pendentes_professor(professor_id)` para presença sem fonte
  forte.

O canal do professor não possui MCP ou SQL, por segurança. Portanto, o modelo
recebe hoje a contagem, mas não tem como montar a relação pedida sem inventar.

## Contrato

Quando uma mensagem de professor tiver intenção explícita de consultar
pendências, o bridge faz pré-busca server-side das duas RPCs, sempre com o
`professor_id` resolvido pelo telefone. O resultado entra no prompt em um bloco
separado e rotulado:

- `conteudo`: aulas cobraveis sem relato, agrupadas por aula e com alunos;
- `presenca`: somente `dentro_janela`, com aulas e alunos que ainda dependem de
  presença forte;
- `escalar_coordenacao`: apenas contagem; o professor não recebe o passivo
  detalhado que já saiu da janela de ação dele.

A busca é acionada somente por frases inequívocas como “quais são minhas
pendências”, “o que falta lançar”, “quem está sem chamada” ou “quais aulas estão
sem registro”. Cumprimento e conversa comum não pagam esse custo nem recebem o
bloco.

## Resposta esperada

O Fábio separa conteúdo e chamada, apresenta no máximo cinco aulas em cada
bloco, e propõe começar por uma aula concreta. Ele nunca afirma que conteúdo
pendente também está sem chamada: os pools permanecem independentes.

Se houver conteúdo pendente, oferece receber um áudio por aula/turma/horário e
explica que mostrará o preview antes de gravar. Se houver presença pendente,
pergunta quem esteve e quem faltou. A mensagem não escreve nada no banco.

## Falha e segurança

Se uma RPC falhar, o bloco marca a fonte como indisponível e o Fábio informa a
limitação sem transformar ausência de dado em “tudo certo”. Nenhuma ferramenta
SQL ou MCP é adicionada ao `api_server`; nenhuma consulta aceita
`professor_id` vindo do texto; nenhuma devolutiva é enviada à família.

## Aceite

1. Pergunta explícita injeta os dois pools canônicos no prompt.
2. Pergunta comum não chama as RPCs de pendência.
3. O `professor_id` consultado é o da identidade resolvida.
4. Falha parcial fica explícita e não apaga a outra fonte.
5. A resposta orienta uma aula por vez, com preview antes de qualquer escrita.
6. O canal do professor continua sem SQL, arquivos, terminal ou MCP.
