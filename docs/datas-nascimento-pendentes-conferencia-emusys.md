# Datas de nascimento — o que foi corrigido e o que a equipe precisa conferir

**03/08/2026** · levantado a pedido do Alf, depois da correção da data do Tiago.

## Por que isso importa

A devolutiva de aula do Fábio decide **para quem falar** pela idade do aluno:
abaixo de 15 anos ela vai para o responsável, acima vai para o próprio aluno.
Data errada não é dado feio — é a devolutiva sobre uma criança de 9 anos indo
para a criança em vez da mãe.

A idade também alimenta a classificação **LAMK / EMLA** (corte em 12 anos), que
aparece em todo relatório da escola.

---

## ✅ Já corrigido — 11 alunos (migration 021)

Comparei `alunos.data_nascimento` com o payload bruto do Emusys guardado no
próprio banco. Onde divergia, alinhei ao Emusys. **Zero divergência restante.**

Os quatro que mudavam de lado na fronteira dos 15 anos:

| Aluno | Estava | É | O que estava errado |
|---|---|---|---|
| Milena Americo Paiva | 49 anos | **9 anos** | data de um responsável |
| Heitor Muniz Martis Da Silva | 43 anos | **7 anos** | data da mãe, Renata Muniz — batia **exata** |
| Laiane Marins Lazaro | 45 anos | **11 anos** | data da mãe, Aline Marins — batia **exata** |
| Tiago Dos Santos Manoel | 5 meses | **37 anos** | data próxima da matrícula |

Os outros sete erravam a idade sem mudar de lado: Matheus Lopes de Medeiros
(dois cadastros), Giselle Gomes Marques, Claudio Mascarenhas Neto, Beatriz
Dolavale Assed, Bruno Ricardo da Silva, Dante Custódio Marques.

> **O alerta do Alf se confirmou**: em dois casos o nosso banco tinha
> literalmente a data de nascimento da mãe no campo do aluno. O Emusys separa
> `aluno` e `responsavel` no cadastro, e a correção usou o campo do aluno.

---

## 🔴 Prioridade 1 — 7 alunos entre 15 e 17 anos

Estes estão **em cima da fronteira** que decide o destinatário da devolutiva, e
não têm registro no payload do Emusys para eu conferir. Se a data estiver
errada para menos, a devolutiva vai para o adolescente em vez do responsável.

| Unidade | Aluno | Curso | Data no sistema | Idade | Responsável |
|---|---|---|---|---|---|
| Barra | Hugo Côvre Guimarães da Silva | Guitarra | 29/12/2009 | 16 | Mauro Guimarães |
| Barra | Sofia Martins Guerreiro | Canto | 24/06/2009 | 17 | Fernanda Martins Guerreiro |
| Campo Grande | Fernanda Gonçalves Freire | Canto | 27/10/2008 | 17 | Daniele Gonçalves da Gama Freire |
| Campo Grande | Pedro Henrique Celestino | Bateria | 18/02/2009 | 17 | Márcio Rosa de Oliveira |
| Recreio | Beatriz Affonso de Araujo Ferraz | Canto | 07/04/2010 | 16 | Marisa Affonso de Araújo |
| Recreio | Catarina Westin | Violino | 12/07/2009 | 17 | Caroline Hofstaetter Westin Lara Camelo |
| Recreio | Mateus Plácido Coimbra | Contrabaixo | 03/07/2011 | 15 | Marta Helena Placido Coimbra |

**Além de conferir a data, tem uma decisão de produto aqui, Alf:** todos os
sete têm responsável cadastrado. Hoje a regra manda o Fábio falar direto com
eles por terem 15+. É isso que você quer para um aluno de 15 anos, ou o corte
deveria ser mais alto?

---

## 🟡 Prioridade 2 — 8 alunos com a data da criança no cadastro do responsável

Nesses, o Emusys tem **a mesma data** em `aluno` e em `responsavel`. Olhando os
cursos, a data é claramente a **da criança** (a Marina tem 2,8 anos e está em
Musicalização para Bebês — a mãe não tem 2,8 anos).

**O campo que a gente usa está correto.** O que está errado é o cadastro do
responsável no Emusys, que herdou a data do filho. Não afeta o Fábio, mas
polui o cadastro.

| Unidade | Aluno | Curso | Responsável com a data errada |
|---|---|---|---|
| Barra | Isadora Florenzano Carvalho | Canto / Power Kids | Sheila Florenzano Carvalho |
| Barra | João Gabriel Candido | Guitarra | Leandro Amaral Teixeira |
| Barra | Luísa Schlinz Paz | Bateria | Júlia Rezende Schlinz |
| Barra | Marina Holanda Cardoso | Musicalização para Bebês | Monica Holanda Ribeiro |
| Barra | Lucas Cardoso Neiva | Violão | Maria da Glória Neiva |
| Campo Grande | Emmanuel de Oliveira Carrari | Guitarra | Patricia Araujo de Oliveira Carrari |
| Campo Grande | Rafael Ferreira Gusmão | Canto | Márcia Ferreira |

---

## 🟢 Prioridade 3 — adultos com responsável de outro nome

Confirmei que **a maioria não é erro**: são adultos cadastrados como o próprio
responsável (nome igual). Sobraram estes, onde o responsável tem nome
diferente. O padrão sugere **responsável financeiro de família** — a Roberta
Alanna aparece como responsável de três adultos distintos — mas vale a
conferida.

| Unidade | Aluno | Idade | Responsável |
|---|---|---|---|
| Barra | Ana Paula dos Santos Lima de Oliveira | 55 | Roberta Alanna dos Santos Lima de Oliveira |
| Barra | Carlos Roberto de Oliveira | 72 | Roberta Alanna dos Santos Lima de Oliveira |
| Barra | Renan Hozumi Barbieri | 34 | Roberta Alanna dos Santos Lima de Oliveira |
| Barra | RAFAEL DA SILVA SANTOS | 52 | Flavia Azevedo Dias |
| Recreio | Christiano Lopes Silva | 44 | Lúcia Lai Fon Dang Silva |

Os de 18–19 anos com responsável (Lucas Lassance, Davi Manaia, Maria Eduarda
Bomfim, Carlos Eduardo Ferreira, Enzo Baptista) são plausíveis — recém-maiores
com responsável financeiro. Não listei como pendência.

---

## O limite do que eu consegui verificar

**116 alunos não têm payload do Emusys no banco para comparar** — 99 deles
ativos. Para esses, a data no nosso sistema pode estar errada e eu não tenho
como saber daqui. As Prioridades 1 e 3 saíram desse grupo, filtradas pelos
sinais que dava para medir (idade perto do corte, responsável com outro nome).

**Os outros ~85 são crianças com idade coerente com o curso** — não há sinal de
erro, mas também não há confirmação. Se a equipe for conferir tudo, esse é o
universo.

Para fechar isso sem depender de olho humano, o caminho é puxar os cadastros
direto da API do Emusys (é GET, só leitura) e comparar — preciso do token.
