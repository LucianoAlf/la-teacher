# Radar do aluno — o Health Score v2 fatiado pra coordenação

**Data:** 10/08/2026 · **Estado:** spec escrita, aguardando revisão do Alf
**Revisão 2** — a v1 (mesma data, de manhã) desenhava três cartões consumindo
o modelo do LA Report. O Alf virou a mesa: *"prefiro que a gente construa o
nosso aqui de uma maneira correta"*. Esta versão é o modelo próprio.

---

## 1. O que é

Uma página na coordenação do LA Teacher que responde uma pergunta por manhã:
**"quem eu procuro esta semana, e por quê?"**

Não é mais uma tela de sinais — o LA Report já tem a mesa de 1.100 alunos com
colunas coloridas. O que falta é uma leitura **pedagógica**, construída sobre
dado que a gente confia, com a nota mostrando de onde veio.

**Por que aqui e não lá.** O LA Teacher não re-deriva sinal: ele **origina**
sinal. O semáforo do professor, o `pratica_em_casa`, o `evolucao`, o `animo`, o
registro de aula — isso nasce escrito por quem deu a aula, não existe no LA
Report e não tem como existir. É canônico por origem.

**Dois olhares, dois donos.** A coordenação olha o pedagógico (este Radar). O
time de Sucesso do Aluno olha conversas ADM, NPS, inadimplência, responsável,
perfil de matrícula. O que a gente provar aqui pode ser levado pra lá.

## 2. Fronteiras duras

| Nunca entra | Por quê |
|---|---|
| Pagamento, inadimplência, valor de parcela | Fronteira do Alf: é do Sucesso do Aluno. E é por isso que o `health_score` do LA Report **não serve**: 30% dele é pagamento (medido em 10/08), então usá-lo põe boleto na tela da coordenação lavado em cor |
| Observação crua do professor fora do LA Teacher | A `observacao` é escrita pra coordenação, não pra família |
| Sinal cujo dado ninguém confirmou | "Não lançado" nunca vira falta. Vale enquanto durar a transição (~6 meses) |

## 3. O que eu medi antes de desenhar (tudo em 10/08/2026)

### 3.1 A view semântica canônica já existe — e implementa os 4 estados

O Alf descreveu o modelo certo: presença, falta, cancelamento, falta
justificada com reposição. Fui procurar onde a presença do professor cruza com
a da secretaria e achei **`vw_aluno_presenca_semantica_v1`**, que já faz isso:

```
resultado_pedagogico   situacao_chamada        confianca      denominador   n
presente               registrada              confirmada     SIM        32.975
falta_confirmada       registrada_atestada     confirmada     SIM         6.803
falta_provavel         registrada_inferida     provavel       não         2.581
indeterminado          indeterminada           desconhecida   não         7.941
aula_justificada       nao_aplicavel           confirmada     não           587
aula_cancelada         nao_aplicavel           confirmada     não             5
```

A coluna **`considera_frequencia_denominador`** é a peça: ela tira da conta o
que ninguém confirmou. **Esta é a fonte do Radar** — não se escreve view nova
de presença.

⚠️ **Correção do que eu tinha dito.** Na v1 desta spec eu li a tabela crua
`aluno_presenca` e concluí que 126 alunos de Campo Grande tinham sumido da
escola. Errado: eu tratei como falta o que a view já classificava como não
confirmado. Pela view, no grão de aula, "faltou todas as últimas 10" são **5
alunos**.

### 3.2 O grão: cada aula real vira ~1,7 linha

A view **não** desduplica: **1,69 linha por aula**. Na tabela crua são 1.840 de
3.148 horários com 2+ linhas, e **1.850 de 1.850** duplicatas diferem no
`aula_emusys_id` — que é id de **EVENTO**, não da aula.

**Isso já está visível na tela do LA Report hoje:** o modal do aluno Daniel
Victor lista `03/08 Ausente` duas vezes e `13/07 Ausente` duas vezes. O "21% de
presença" dele está calculado sobre linhas dobradas.

→ **Regra:** a unidade de contagem é **`(aluno_id, data_aula, horario_aula)`**.
Dentro do grupo, presença é afirmação: `bool_or(considera_presenca)`.

### 3.3 A régua da falta, tirada da distribuição

Faltas nas últimas 10 aulas medidas, 717 alunos com base ≥8:

| Faltou | Alunos | Acumulado |
|---:|---:|---:|
| 8 de 10 | 9 | 1,3% |
| 7 de 10 | 22 | 4,3% |
| 6 de 10 | 75 | 14,8% |
| **5 de 10** | 87 | **26,9%** |
| 4 de 10 | 153 | 48,3% |
| 3 de 10 | 157 | 70,2% |

**Alerta em 5 ou mais de 10** (decisão do Alf). A referência de mercado para
escolas de música (10–15%) **não serve aqui**: o absenteísmo geral da casa é
**38,6%**, então um corte de 15% acenderia quase todo mundo. A régua está
calibrada pela realidade da casa e vai apertar sozinha conforme o lançamento
melhora — o número se corrige pelo dado, não por decisão nova.

### 3.4 Campo Grande tem grupo de controle

Alunos em alerta (5+ de 10), por unidade:

| Unidade | Em alerta | Alunos | % | Aulas medidas (média) |
|---|---:|---:|---:|---:|
| **Campo Grande** | 153 | 467 | **32,8%** | 8,8 |
| Barra | 30 | 258 | 11,6% | 9,2 |
| Recreio | 44 | 390 | 11,3% | 8,8 |

Barra e Recreio concordam entre si em 11,5%, com a **mesma cobertura de
medição**. CG está 3× acima. Enquanto a transição não fechar, o Radar mostra o
número de CG **ao lado da régua das outras duas**, pra ninguém ler 153 como
comportamento de aluno.

### 3.5 A coorte e a janela

```
professores liberados no app      6  (5 concluíram onboarding)  de 44 ativos
alunos desses professores       158
aulas medidas em agosto         189   →  1,2 aula por aluno
```

**Coorte:** só alunos de professor que já entrou no app. Sai de graça — os
sinais que o professor produz só existem pra quem está lá. Cresce sozinho:
liberou no painel, entra no Radar.

**Janela:** decisão do Alf — *"vira a página"*. A janela **nasce em 01/08/2026**
e cresce até 10 aulas; nunca busca antes disso. Motivo dele, e é bom: julho teve
duas semanas de recesso e as três unidades vinham sem compromisso com presença.
Aproveitar dado ruim porque é o que tem foi exatamente o erro do §3.1.

Enquanto a janela não enche, a coluna diz **"enchendo: 3 de 10"** — não é tela
vazia, é tela que diz o que está fazendo. Ela fica cheia por volta de meados de
outubro.

### 3.6 Números de hoje, para os outros sinais

```
faltas em agosto            353 em 1.066 aulas  (349 alunos)
aula_justificada            243 aulas, 209 alunos   (o "faltou e repôs")
semáforo respondido em ago    0   ← os professores começam hoje
anamnese                     40 de 1.115 alunos ativos
registro de aula (dever_casa) 8 registros — piloto
```

## 4. As colunas da Fase 1 (definidas pelo Alf)

```
Aluno · Health Score · Faltas · Absenteísmo · Prática · Feedback · Status
```

| Coluna | O que é | Fonte | Régua |
|---|---|---|---|
| **Health Score** | 0–100, nosso, com pesos configuráveis | calculado | ver §5 |
| **Faltas** | quantidade no mês corrente | view semântica, grão de aula | o fato do mês |
| **Absenteísmo (10 aulas)** | % de falta nas últimas 10 aulas medidas | idem, janela de §3.5 | **≥50% = alerta** |
| **Prática** | pratica em casa? | `aluno_feedback_professor.pratica_em_casa` | "não" = alerta |
| **Feedback** | coração do mês + evolução + ânimo | `aluno_feedback_professor` | vermelho = alerta |
| **Status** | Crítico · Atenção · Saudável | derivado da nota | faixas em §5 |

**Por que Faltas E Absenteísmo, os dois.** Respondem perguntas diferentes.
Falta do mês é o fato que a família reconhece e a coordenação cobra; sozinho,
some no dia 3 de cada mês, quando todo mundo tem zero. Absenteísmo é o padrão,
que prevê evasão e não depende de onde o mês está. O rótulo **carrega o
denominador** (`(10 aulas)`) porque foi exatamente isso que faltou no "21%" da
tela do LA Report.

**Falta justificada não conta como falta.** `aula_justificada` fica fora do
denominador (243 aulas, 209 alunos). Quem falta e repõe não é quem falta e
some — é a distinção que o próprio material do Health Score v2 aponta como a
que importa.

**Presenteísmo sai de graça.** Aluno `presente` + `pratica_em_casa = não`, em
dois meses seguidos, é o aluno que vai, paga, frequenta e apagou — o que
nenhuma planilha pega. Não é coluna nova: é um selo na linha, do cruzamento de
duas colunas que já estão lá.

**Fora da Fase 1, e volta quando tiver lastro:** nota do Fábio (sinal contínuo
dos registros), jornada do aluno (não está pronta), anamnese × expectativa
(40 de 1.115 — acenderia 96% da escola, é projeto de coleta e não sinal),
professor que não passa dever de casa (8 registros).

## 5. A nota

**Pesos configuráveis já na Fase 1** (decisão do Alf, contra a minha
recomendação inicial — registrado). Mas com três coisas que impedem a nota de
virar opinião com cara de número:

**5.1 A nota sempre abre.** Nunca aparece sozinha: mostra qual sinal contribuiu
quanto. É a diferença entre um ponteiro em que se acredita e uma nota que se
audita.

```
NOTA 38          apurada em 3 de 4 sinais
├ absenteísmo     5 de 10      peso 40 → 53   contribuiu 21
├ feedback        vermelho     peso 25 → 33   contribuiu 11
├ prática         não          peso 20 → 27   contribuiu  6
└ faltas do mês   —            SEM DADO (fora da conta)
```

**5.2 Sinal sem dado sai da conta e o peso se redistribui** (decisão do Alf).
Nunca conta como neutro nem como ruim — contar ausência de dado como coisa ruim
é o mesmo defeito de "não-marcado = falta" que a gente acabou de tirar da
presença. Ao lado da nota vai a **cobertura**: *"apurada em 3 de 4 sinais"*.
Duas notas 70 não se confundem.

**5.3 A nota carrega em quanta aula ela foi medida.** Nota calculada sobre 2
aulas e sobre 10 não podem parecer a mesma coisa.

**Faixas:** Crítico < 40 · Atenção 40–69 · Saudável ≥ 70. Configuráveis junto
com os pesos.

**Pesos iniciais** (chute explícito, e é por isso que ficam configuráveis):
absenteísmo 40 · feedback 25 · prática 20 · faltas do mês 15.

**Quem mexe:** coordenação e o Alf, em tela dentro do LA Teacher. Toda alteração
é registrada com quem mudou, quando e os valores de antes — peso que muda sem
histórico vira discussão sem árbitro daqui a três meses.

**O caminho de sair do chute.** O banco tem **758 evasões, 205 não-renovações,
87 trancamentos e 522 renovações**. Quando a janela encher (out/2026), dá pra
medir quais pesos separam quem ficou de quem saiu — em casa, sem esperar o LA
Report. A tela de configuração ganha então um "sugerido pelo modelo" ao lado do
valor manual. **Não é Fase 1**; é o destino, e está anotado aqui pra não virar
"peso é chute pra sempre".

## 6. As telas

Formato adaptado do módulo Sucesso do Aluno do LA Report, que o Alf aprovou —
**mesa + modal**. O esqueleto é parecido de propósito; o conteúdo é outro, e a
ausência das caixas de pagamento é intencional e visível.

**6.1 Mesa** (`/app/coordenacao/radar`) — colunas do §4, ordenáveis, filtros
facetados (unidade, professor, status) no padrão da 079: cada faceta é cega ao
próprio filtro e enxerga as outras. Um número só entre KPI, lista e chip
(lição da 080).

**6.2 Modal do aluno** — a decomposição da nota (§5.1), o semáforo do mês com a
frase das três perguntas e a observação do professor entre aspas, e o
**histórico de presença desduplicado** com os quatro estados por extenso e a
janela declarada ("10 aulas, de 04/ago a 15/out").

**6.3 Configuração de pesos** — dentro da coordenação, com histórico de
alteração.

**Selos na linha:** "avisou que sai" (33 alunos hoje, da `movimentacoes_admin`
com `mes_saida` à frente) e "presenteísmo". São selos, não colunas — não entram
na nota, marcam a linha e filtram.

**Reuso:** `PainelNumero`, `LinhaSemaforo` e os `Select` dos filtros já
existem. Não nasce Design System paralelo; o que faltar se extrai do app do
professor.

## 7. Backend

`app_coordenacao_radar(p_unidade_id, p_professor_id, p_status, p_limite)` —
molde da 077/079: guard `fn_e_coordenacao_la_teacher()` → `apenas_admin`,
devolve um jsonb com `{resumo, linhas, filtros, config_pesos, cobertura}`.

Uma view intermediária, `vw_radar_aluno_sinais`, faz o trabalho pesado: grão de
aula, janela desde 01/08, coorte, e as quatro colunas de sinal. A nota é
calculada em função separada que **recebe os pesos como parâmetro** — assim o
teste consegue variar peso sem tocar em configuração.

Tabela `radar_pesos` (unidade_id nulo = global) + `radar_pesos_historico`.

## 8. Testes — o que os mutantes precisam matar

1. contar **linha** em vez de `(aluno, dia, hora)` → todo número de falta dobra
2. `aula_justificada` entrando no denominador → 209 alunos viram faltosos
3. a janela buscando antes de 01/08 → volta o ruído do recesso
4. a coorte caindo → o Radar mostra aluno de professor que não usa o app
5. sinal sem dado contando como zero em vez de sair → escola inteira em crítico
6. o peso não se redistribuindo → nota de quem tem 2 sinais fica artificialmente baixa
7. a cobertura sumindo da tela → nota de 2 aulas passa por nota de 10
8. o guard caindo → professor lê a escola inteira
9. faceta se filtrando → sem volta depois de escolher unidade
10. total do cartão ≠ tamanho da lista

## 9. Riscos

- **A coluna Feedback nasce vazia.** Os professores começam hoje. Se em 15/08
  seguir em zero, o problema é adoção, não Radar.
- **O absenteísmo de CG vai chamar atenção antes da hora.** Por isso a régua
  das outras duas unidades aparece do lado. Se ainda assim gerar cobrança de
  aluno em vez de conserto de registro, esconder a coluna em CG é preferível a
  publicá-la sem contexto.
- **Pesos configuráveis podem virar disputa.** O histórico de alteração é o que
  transforma discussão em fato — e §5.4 é a saída definitiva.
- **A janela nasce em 01/08 e só enche em outubro.** Até lá o Radar é magro, e
  isso é honesto. Afrouxar a janela pra encher a tela é a tentação a evitar.
