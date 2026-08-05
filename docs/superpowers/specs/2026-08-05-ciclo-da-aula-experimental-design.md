# Ciclo da aula experimental — design

**Data:** 05/08/2026
**Decisão do Alf:** *"isso daqui é ouro"* (registro) e *"acho que isso aqui cabe
junto, trata tudo da questão de experimental"* (agenda). Um assunto só.

## O problema

A aula experimental é a aula que decide se existe um aluno. Hoje ela acontece e
**some**: não está na agenda do professor, ninguém registra como foi, e não vira
nem devolutiva nem dado. A escola não aprende o que converte.

Metade do ciclo já foi construída em 05/08/2026 (migrations 027*, 028, 029): o
contexto do que a família contou para a Mila chega ao professor **antes** da
aula. Esta spec fecha a outra metade.

```
contexto antes  →  aparece na agenda  →  conduz  →  registra  →  converteu ou não
   ✅ no ar          ← esta spec →                                    ↑
                                                            alimenta o próximo
```

## O que o levantamento mostrou

Quatro medições que mudaram o desenho. Todas de 05/08/2026, em produção.

**1. O motor de registro já existe e é genérico.** `fabio_registros_aula` tem
`molde`, `campos` (jsonb livre), `origem`, `audio_id`, `parent_id` e fluxo de
confirmação (`status`, `confirmado_em`, `confirmado_por`). Hoje roda com **um
único molde** (`C`) e uma única origem (`app`), com 41 registros. Não é preciso
construir motor: é preciso um molde novo.

**2. A experimental não está "faltando" na agenda — ela não existe como aula.**
`aulas_emusys.tipo` tem `ensaio`, `individual` e `turma`. **Zero** experimentais.

**3. O `emusys_aula_id` é melhor do que estava registrado.** A tarefa #57 dizia
"é id de evento, não da aula". Medindo: 445 preenchidos, **119 casam** com
`aulas_emusys.emusys_id`, e dessas **117 batem professor E data** (98%). As 328
que não casam **não são fora de janela** — `aulas_emusys` cobre 02/03 a 09/09 e
as experimentais vão de 17/06 a 15/08. Ou seja: o id não é lixo, é
*inconsistente* — parece haver dois tipos de identificador na mesma coluna.

→ **Consequência de projeto:** não dependemos de resolver o Emusys para fechar o
ciclo. Onde o id casa, reconciliamos; onde não casa, criamos.

**4. Aluno sem cadastro já é um caso suportado.** `aula_alunos_emusys.aluno_id` é
nullable e **942 linhas já estão assim**, identificadas por `aluno_nome`. É
exatamente a situação do lead pré-matrícula.

**5. O sync não apaga o que não veio dele.** `sync-grade-futura-emusys` faz
`upsert` com `onConflict: 'emusys_id,unidade_id'` e o próprio código documenta
"sem delete-cego". Uma linha nossa, com chave fora da faixa do Emusys, sobrevive.

## Arquitetura

**A experimental vira uma aula de verdade** (decisão do Alf, entre as duas
opções apresentadas). Ela entra na agenda como as outras, e o registro, a
presença e a devolutiva reusam o que já existe.

### Como a aula nasce

Quando uma experimental é agendada (`lead_experimentais` com status
`experimental_agendada` ou `experimental_reagendada`), uma rotina garante:

- uma linha em `aulas_emusys` com `tipo = 'experimental'`
- `emusys_id` **negativo**, derivado do `lead_experimental_id`
- uma linha em `aula_alunos_emusys` com `aluno_nome` do lead e `aluno_id` NULL

O `emusys_id` negativo é o ponto de maior cuidado do desenho: é o que impede a
colisão com o Emusys. O Emusys usa inteiros positivos; nada nosso pode entrar
nessa faixa. A regra é `emusys_id = -lead_experimental_id`, que é única por
construção e reversível (dá para voltar do id da aula ao lead sem tabela extra).

**Reconciliação, para não duplicar.** Se `lead_experimentais.emusys_aula_id`
aponta para uma aula que existe em `aulas_emusys` (os 27% que casam), usamos
**aquela** aula em vez de criar. Se o Emusys criar a aula depois de nós, a
rotina precisa detectar e consolidar — este é o ponto que exige teste
explícito, não confiança.

### Como o professor vê

A agenda já lê de `aulas_emusys`, então a experimental aparece de graça. O que
muda no cliente:

- destaque visual de `tipo = 'experimental'` — é uma aula diferente e o
  professor precisa saber disso antes de entrar na sala
- o contexto da migration 029 (o que a família contou à Mila) na mesma tela

### Como o professor registra

Um molde novo em `fabio_registros_aula`, com `aula_id` apontando para a aula
criada acima. Os quatro blocos que o Alf escolheu:

| bloco | para quê |
|---|---|
| **Como foi a aula** | o que trabalhou, como respondeu, **nível real observado** — que pode divergir do declarado pela família |
| **Devolutiva pra família** | o texto que a escola manda ao responsável; é o que costuma converter |
| **Leitura de conversão** | interesse, dúvida ou resistência percebidos — o comercial sabe onde apertar, e a escola aprende o que converte |
| **Encaminhamento sugerido** | curso, nível e professor recomendados se matricular; encurta a matrícula e evita começar errado |

O molde `C` atual guarda `{presenca, progresso, observacao, repertorio,
proximo_passo, aula_alvo_resolvida}` e gera um `texto_consolidado`. O molde da
experimental segue a mesma forma: campos estruturados + texto consolidado.

**A devolutiva nunca sai sozinha.** Prévia antes de enviar, como em todo o resto
do sistema — é mensagem para a família, e o padrão da casa é o humano aprovar.

### O que acontece na matrícula

Quando o lead vira aluno, `aula_alunos_emusys.aluno_id` é preenchido e a
experimental passa a ser o **primeiro capítulo do histórico** daquele aluno. O
professor que pegar esse aluno vê o que aconteceu na experimental sem que
ninguém precise recontar.

## Fronteiras

O contexto da experimental já tem uma fronteira estabelecida (migration 029,
`fn_experimental_contexto_seguro`): dinheiro e negociação não atravessam para o
professor. O **registro** anda no sentido oposto — nasce com o professor — mas
a "leitura de conversão" é para uso interno e **não** vai na devolutiva à
família. A separação vive na estrutura do molde, não em instrução de prompt.

## O que fica de fora

- **Registro por áudio no WhatsApp.** O Alf deixou no radar: *"espelhar esse
  mesmo motor que a gente já tem pronto, só levar para o WhatsApp"*. O motor já
  tem `audio_id` e `origem`, então o molde nasce pronto para receber áudio — mas
  o caminho do WhatsApp é outro trabalho.
- **Consertar a inconsistência do `emusys_aula_id` na origem.** Reconciliamos o
  que casa; investigar por que 73% não casam é trabalho do lado do Emusys.
- **Relatórios do Fábio** (#47–49), que o Alf quer retomar depois desta.

## Riscos

**Duplicata com o Emusys.** Se o Emusys criar a mesma aula, ficam duas. A
reconciliação por `emusys_aula_id` cobre o caso conhecido; o caso "Emusys criou
depois" precisa de teste próprio.

**Experimental cancelada ou remarcada.** O status muda em `lead_experimentais`,
e a aula criada precisa acompanhar — senão o professor vê na agenda uma aula que
não vai acontecer. A migration 027c já ensinou essa lição no extrator.

**Poluir o espelho.** `aulas_emusys` passa a ter linhas que não vieram do Emusys.
É o preço de reusar toda a máquina existente. O `emusys_id` negativo é o que
torna a origem óbvia em qualquer consulta — quem vê `-1337` sabe na hora que
aquilo não é do Emusys.
