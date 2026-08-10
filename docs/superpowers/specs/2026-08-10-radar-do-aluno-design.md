# Radar do aluno — bloco 2 do painel da coordenação

**Data:** 10/08/2026 · **Estado:** spec escrita, aguardando revisão do Alf
**Direção aprovada em:** 08/08/2026 (Alf) — *"painel estratégico de gestão
pedagógica; se coloca no lugar dos coordenadores"*

---

## O que é

Uma seção do painel da coordenação com **cartões de sinal**: contagem, os casos
mais urgentes, e a **ação que o sinal pede**. Não é lista de alunos — é
curadoria. A régua: se o cartão não diz a quem ligar hoje, ele não é cartão.

## O que ele NUNCA faz

**Não fabrica score composto.** A regra de ouro do time de Sucesso do Aluno:
peso não se chuta. O score manual antigo deles provou o custo — os "Atenção"
evadiam *mais* que os "Crítico". Quem aprende peso é modelo, não spec. O Radar
mostra dimensões lado a lado e aponta a conversa humana; somar duas delas num
número novo está proibido nesta spec.

**Não mostra inadimplência.** Fronteira dura do Alf. Inadimplência é do módulo
Sucesso do Aluno, não da coordenação pedagógica.

**Não publica número que não sabe explicar.** Vale para todo cartão: se a fonte
tem artefato conhecido, ou o cartão trata o artefato ou o cartão não sai.

---

## O que eu medi antes de desenhar (10/08/2026)

Cinco medições mudaram o desenho. Três derrubaram coisas que a direção
aprovada dava como certas.

### 1. As duas réguas de "dias sem presença" nunca discordaram

A anotação de 08/08 dizia que `vw_absenteismo_aluno` e `vw_aluno_sucesso_lista`
discordavam (≥14 dias: 693 × 403). Medido:

```
absenteismo: 1.509 linhas   base ativa: 1.113 linhas
mesma coluna, valores diferentes entre as duas: 0
```

`vw_aluno_sucesso_lista` **faz join na própria** `vw_absenteismo_aluno`. É a
mesma medida sobre **populações diferentes**: a primeira inclui quem já saiu e
segundo curso; a segunda filtra pela base ativa. Não era divergência de régua,
era divergência de pergunta.

→ **Decisão:** a base do Radar é `vw_aluno_sucesso_lista`. Radar que lista quem
já evadiu como "sumiu da escola" é ruído com cara de urgência.

### 2. Desde 09/07 cada aula real vira DUAS linhas de presença

```
(aluno, dia, hora) com 1 linha:  1.298
(aluno, dia, hora) com 2 linhas: 1.840   ← 58% dos horários
com 3 ou 4 linhas:                  10
das 1.850 duplicadas, diferem no aula_emusys_id: 1.850 (100%)
diferem no curso: 9 · diferem no status: 10
```

Mesmo aluno, mesmo dia, mesma hora, mesmo curso, **`aula_emusys_id` diferente**.
É o id de EVENTO, não da aula — o mesmo achado que já está anotado para a
agenda da experimental.

→ **Decisão:** a unidade de contagem é `(aluno_id, data_aula, horario_aula)`,
nunca a linha. E dentro do grupo, **presença é afirmação**: se qualquer linha
diz `presente`, o aluno veio. Contar linha crua dobra qualquer número de falta.

### 3. "Sumiu da escola" não pode sair agora — e o motivo tem nome

Com a duplicata desfeita, faltas seguidas na base ativa:

| Faltas seguidas | Alunos | Destes, já marcados presentes alguma vez na janela |
|---|---|---|
| 0 | 801 | — |
| 1 | 148 | 122 |
| 2 | 123 | **4** |
| 3 | 7 | **0** |

126 alunos acumulam 2+ faltas seguidas e **nunca** foram marcados presentes na
janela honesta. Fui atrás: 124 deles vieram, sim, antes de 09/07 (2.516
presenças), e 97 tiveram aula na semana de 03/08 — **99 aulas, zero presenças**
— enquanto a escola inteira rodou a **68% de presença** naquela semana.

Onde eles estão:

| Professor | Unidade | Suspeitos / carteira |
|---|---|---|
| Gabriel Barbosa Rufino Otávio | CG | 11 / 24 (46%) |
| Daiana Pacifico da Silva dos Anjos | CG | 6 / 12 (50%) |
| Marcos Delfino Serafim | CG | 4 / 8 (50%) |
| Israel Rocha da Silva | CG | 5 / 12 (42%) |
| Caio Tenório de Araújo | CG | 12 / 43 (28%) |

Dez das doze primeiras linhas são **Campo Grande**. Um sinal de evasão não se
concentra numa unidade e em metade da carteira de um professor. Isso é
**registro**, não aluno — e já está anotado nesta casa que CG tem problema de
registro.

→ **Decisão: o cartão "Sumiu da escola" NÃO entra na Fatia 1.** Publicado hoje,
ele mandaria a coordenação ligar para 126 famílias por causa de chamada não
lançada em CG. Ele volta quando o registro de CG estiver medido — e o dono
disso é a frente de presença, não o Radar.

Duas coisas ficam **decididas** para quando ele voltar:
- conta **aula perdida** (aula que existiu e foi marcada), nunca dia de
  calendário — o recesso de duas semanas de 20/07 dá ~15 dias de "sumiço" de
  graça para a escola inteira;
- exige **pelo menos uma presença afirmada** na janela, senão "nunca foi
  marcado" entra disfarçado de "parou de vir".

### 4. O aviso prévio está vivo, e o join até o aluno é que é frágil

```
aviso_previo total: 128 · com mês de saída à frente: 33
33/33 têm professor · 32/33 têm aluno_id
mas só 17/33 acham par na base ativa
```

→ **Decisão:** o cartão vive da **linha ADM** (nome, professor, unidade,
motivo), que está completa. O link para a ficha do aluno é *enfeite*: aparece
nos 17 que casam, some nos outros. Cartão que depende de join frágil mostra 17
e finge que são 33.

### 5. Os números dos outros cartões, hoje

```
risco crítico (base ativa): 33      perto de renovação (base ativa): 88
cruzamento crítico × renovação: 2
coração crítico (health_score, base ativa): 42
semáforo do professor respondido em agosto: 0   ← eles começam amanhã
```

O cruzamento de ouro dá **2 alunos**. Isso não é defeito: é exatamente o que
"curadoria" significa. Dois nomes para ligar esta semana é um cartão que se
cumpre; 300 nomes é uma parede.

---

## Fatia 1 — três cartões

### Cartão 1 · "Ligar essa semana"
**Sinal:** risco de evasão `critico` **e** marco `perto_renovacao`, na base ativa.
**Hoje:** 2 alunos.
**Mostra:** nome, unidade, professor, probabilidade, quando renova.
**Ação:** *"Liga antes da renovação — depois de renovar, a conversa muda de assunto."*
**Vazio:** *"Ninguém no cruzamento esta semana."* — vazio aqui é boa notícia e a
tela diz isso, em vez de parecer quebrada.

### Cartão 2 · "Avisou que sai — e ainda está em aula"
**Sinal:** `movimentacoes_admin.tipo = 'aviso_previo'` com `mes_saida` no mês
corrente ou à frente.
**Hoje:** 33.
**Mostra:** nome, professor, unidade, motivo, mês de saída. Link para a ficha
só quando o `aluno_id` casa na base ativa (17 dos 33).
**Ação:** *"Última janela pedagógica: ele ainda vem às aulas."*
**Por que é o cartão de primeira:** é o único sinal em que a escola já sabe o
desfecho e ainda tem o aluno na sala.

### Cartão 3 · "Coração vermelho"
**Sinal:** duas fontes, **lado a lado, nunca somadas**:
- semáforo do professor no mês (`aluno_feedback_professor.feedback = 'vermelho'`),
  com as três respostas e a observação — a fonte humana e fresca;
- `health_score = 'critico'` na base ativa (42) — a fonte do modelo.
**Hoje:** 0 do semáforo (os professores começam amanhã) + 42 do health score.
**Mostra:** coração, nome, professor, e — quando vier do semáforo — **a frase que
as três perguntas formam** ("não pratica em casa, evolução travada, desanimado")
e a observação do professor entre aspas.
**Ação:** *"O professor levantou a mão. Fala com ele antes de falar com a família."*

**É aqui que as duas pontas soltas do semáforo se resolvem:**
- as **três perguntas** deixaram de ser dado sem leitor: elas viram a *frase do
  porquê* dentro do cartão. Um coração vermelho sem motivo manda a coordenação
  adivinhar; com motivo, ela chega na conversa sabendo o assunto.
- a **observação do professor** já tem leitor no LA Teacher desde a 077. O que
  falta é o LA Report, onde o semáforo entra só como coração valendo 20% do
  `health_score`. Isso é **fronteira, não tarefa desta spec**: fica anotado como
  item do LA Report, com a fonte pronta (`aluno_feedback_professor.observacao`).

---

## Arquitetura

Uma RPC só, no molde da 077: `app_coordenacao_radar(p_unidade_id, p_limite)`.

- **Guarda:** `fn_e_coordenacao_la_teacher()` → `apenas_admin`. Mesma porta da
  tela de feedback.
- **Devolve um jsonb** com `{resumo, cartoes: {ligar, aviso, coracao}, filtros}`.
  Cada cartão traz `total`, `linhas` (cortadas em `p_limite`) e `truncado`.
- **Filtro por unidade** no padrão facetado da 079: cada faceta é cega ao
  próprio filtro e enxerga os outros. Sem isso, escolher unidade apaga as
  opções e não há volta sem F5.
- **Um número só:** o total do cartão e o comprimento da lista contam a mesma
  coisa, no mesmo grão. É a lição da 080 e ela vale aqui inteira.

**Cliente:** `/app/coordenacao/radar`, quarto item da sidebar, reusando
`PainelNumero` e o cartão do `LinhaSemaforo`. **Não** nasce componente novo de
design: o que faltar se extrai do app do professor.

## Testes

`.test.sql` no molde das 077–080, rodando em `BEGIN/ROLLBACK`, mais um
`scripts/mutantes-NNN.mjs`. Os mutantes que precisam morrer:

1. o cartão de faltas conta **linha** em vez de `(aluno, dia, hora)` → dobra;
2. o cruzamento vira **ou** em vez de **e** → 2 alunos viram 119;
3. o cartão de aviso prévio passa a exigir join com `alunos` → 33 viram 17 em
   silêncio;
4. o guard cai → um professor lê a escola inteira;
5. o total do cartão e a lista passam a contar coisas diferentes;
6. a faceta de unidade passa a se filtrar → a volta some;
7. o `health_score` e o semáforo viram um score só → a regra de ouro cai.

## O que fica fora, e por quê

| Fora | Motivo |
|---|---|
| "Sumiu da escola" | registro de CG contamina; volta com aula perdida + presença afirmada |
| Inadimplência | fronteira do Alf: é do Sucesso do Aluno |
| NPS, conversas ADM, responsável, perfil de matrícula | "cada um no seu quadrado" — donos são outros |
| Normalizar anotação do Emusys | trilho paralelo, já anotado; não é o Radar |
| Coleta do semáforo pela agente Lia virar nativa | fatia futura |

## Riscos

- **O cartão 3 nasce quase vazio.** Os professores respondem a partir de
  11/08. É honesto e esperado; a tela diz "ainda não respondido" em vez de
  fingir número. Se em 15/08 continuar em zero, o problema é adoção, não Radar.
- **O cruzamento de 2 pode virar 0.** O cartão precisa ler bem vazio — vazio ali
  é a escola em dia, e o texto tem que dizer isso.
- **`vw_risco_evasao_atual` tem `confianca_dado`.** Antes de publicar
  probabilidade, conferir se a faixa `critico` de baixa confiança deve aparecer.
  Fica como pergunta aberta da revisão.
