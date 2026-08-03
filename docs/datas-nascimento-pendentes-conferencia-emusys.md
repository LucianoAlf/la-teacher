# Datas de nascimento — conferência contra o Emusys

**03/08/2026** · levantado a pedido do Alf, depois da correção da data do Tiago.

> **Esta é a segunda versão.** A primeira foi escrita comparando com o payload
> guardado em `emusys_api_payload` e apontava 116 alunos sem como conferir.
> Depois o Alf lembrou que as credenciais do Emusys estão no `.env`, puxei as
> **4.825 matrículas das três unidades ao vivo** e o quadro mudou: **17 sem
> fonte, não 116**, e a maior parte das pendências que eu tinha listado já
> estava correta. O que vale é o que está abaixo.

## Por que isso importa

A devolutiva de aula do Fábio decide **para quem falar** pela idade do aluno:
abaixo de 15 anos vai para o responsável, acima vai para o próprio aluno. A
idade também alimenta a classificação **LAMK / EMLA** (corte em 12 anos), que
aparece em todo relatório da escola.

## Onde a base está agora

| | |
|---|---|
| Alunos no banco | 1.618 |
| Conferidos contra o Emusys ao vivo | **1.601** (1.521 por id+unidade, 80 por nome) |
| Divergências restantes | **0** |
| Sem fonte para conferir | 17 (só **5 ativos**) |

Corrigidas em duas migrations: a **021** alinhou 11 datas (incluindo três
crianças gravadas como adultos de 40+), a **022** pegou a última, achada só
com a fonte viva — Ana Julia de Oliveira Gomes, evadida, que não muda
destinatário de devolutiva.

**Os sete alunos de 15 a 17 anos que a primeira versão deste documento mandava
conferir já foram conferidos** — seis estão corretos. Sobra um, o Pedro
Henrique Celestino, na lista abaixo.

---

## 🔴 O que ainda precisa de olho humano

### 5 alunos ativos sem registro na API do Emusys

Não aparecem na coleta das três unidades. Podem ser cadastro só no nosso lado,
matrícula em unidade não coberta pelos três tokens, ou registro removido lá.

| id | Aluno | Nascimento | Idade | Unidade | Tem responsável |
|---|---|---|---|---|---|
| 1399 | **Pedro Henrique Celestino** | 18/02/2009 | 17 | Campo Grande | sim |
| 1398 | Maria Eduarda Pery Natividade | 31/03/2003 | 23 | Campo Grande | não |
| 1807 | Fátima Santa Cruz | 21/05/1980 | 46 | Barra | sim |
| 1876 | Lúcia Lai Fon Dang Silva | 21/02/1983 | 43 | Recreio | sim |
| 1886 | Marina Bessa | 01/11/2019 | 6 | Barra | sim |

O **Pedro Henrique** é o único que importa para a devolutiva: 17 anos, com
responsável cadastrado, e a regra atual manda o Fábio falar direto com ele.

Os outros 12 sem fonte estão inativos ou evadidos: Marcela Formaggini, Luciano
da Silva Bernardino, Sophia Alves, Álvaro Andrade Pinheiro, Anna Clara de Souza
Iorio Sales, Bruna Pereira Monteiro Carregosa, Lucas Keyne Pereira, Maite de
Oliveira Gomes, Davi Guedes Queiroz de Souza, Alexandre Dos Santos, Pablo
Dupret, Pietro Bittencourt Damasceno.

### A decisão de produto que sobra pra você, Alf

Todo aluno de 15 a 17 anos com responsável cadastrado recebe a devolutiva
**direto**, sem passar pela mãe. Isso é o que você quer, ou o corte deveria ser
mais alto?

Não é um caso isolado: é regra ativa para toda essa faixa. E não dá para
resolver com dado — é escolha.

---

## 🟡 46 alunos com a mesma data de nascimento do responsável

Confirmado na fonte viva. Em **38 deles a data é claramente da criança** (menor
de 18) — ou seja, foi o **cadastro do responsável** que herdou a data do filho.
O campo do aluno está certo e o Fábio não é afetado; é higiene de cadastro.

Os **8 restantes são ambíguos** — o aluno é maior de idade, então não dá para
dizer pelo número qual dos dois cadastros está errado:

| Unidade | Aluno | Nascimento | Idade | Responsável |
|---|---|---|---|---|
| Campo Grande | Ashlley Christiny de Oliveira | 06/02/2006 | 20 | Munyk Assis de Oliveira |
| Recreio | Davi Nunes Correia | 30/05/2006 | 20 | Eric Castro Correia |
| Campo Grande | Eduarda da Costa Barandin | 01/07/2008 | 18 | Claudio Barandin da Silva |
| Campo Grande | Fabiana de Oliveira Costa | 12/02/1980 | 46 | *ela mesma* |
| Barra | Guilherme Grigório Marcondes | 21/07/2002 | 24 | Alexandre Góis Villela Marcondes |
| Recreio | Juliana Akemi Takeda | 26/05/1983 | 43 | Hissayuki Takenawa Junior |
| Barra | Karinne Oliveira Bank | 01/10/2000 | 25 | Carmen N O da Silva Bank |
| Campo Grande | Lana De Aguiar Figueiredo | 23/05/2005 | 21 | Mirian Estevam de Aguiar |

A Fabiana é o próprio responsável, então está certa. Os outros sete valem uma
conferida na secretaria.

Nenhum deles afeta a devolutiva: todos são maiores de 15 pelas duas leituras.

---

## Duas armadilhas da API do Emusys que custaram caro aqui

Valem para qualquer um que for consultar o Emusys — inclusive o Codex.

**1. O header `token` precisa chegar em minúsculo literal.** `urllib` e
`requests` capitalizam para `Token`, e a API responde
`{"status":"erro","msg":"token invalido!"}` — parece credencial errada e não é.
Em Python, `http.client` preserva o case.

**2. A paginação é por cursor, e os parâmetros de página são ignorados em
silêncio.** `?cursor=<paginacao.proximo_cursor>` é o certo. `pagina`, `page`,
`offset`, `skip` e `inicio` são aceitos com HTTP 200 e devolvem sempre o começo
da lista. Uma coleta que confie neles roda até o limite lendo a mesma página —
foi o que aconteceu na minha primeira tentativa, que "coletou 30.000
matrículas" que eram 101 alunos repetidos.

**3. O `id` do aluno no Emusys é por unidade, não global.** 1.003 dos 2.732 ids
aparecem com nomes diferentes entre as unidades — o id 38 é "Augusto Ramalho
Tratch" na Barra e "Leonardo de Oliveira Gonçalves da Silva" no Recreio. Casar
só por `emusys_student_id` junta pessoas diferentes. A chave é **(unidade, id)**.
