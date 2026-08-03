# Prompt para o Codex — datas de nascimento no LA Report

> Cole este texto no Codex junto com o documento
> `datas-nascimento-pendentes-conferencia-emusys.md`.
>
> **Versão 2.** A primeira pedia ao Codex que conferisse 116 alunos contra a
> API do Emusys. Isso já foi feito daqui — sobraram 17, e a conferência mudou o
> quadro. O que resta pedir é menor e mais importante: a causa raiz.

---

Preciso da tua ajuda com um problema de cadastro no LA Report. O documento
anexo é o estado atual; este prompt é o que falta fazer.

## O que já está feito — não repita

No projeto Supabase `ouqwbbermlzqqvtqwlul`, a tabela `public.alunos` tinha datas
de nascimento divergentes da fonte Emusys. Já foram corrigidas:

- **migration 021** — 11 datas, comparadas contra o payload guardado em
  `emusys_api_payload`
- **migration 022** — a última, achada puxando as 4.825 matrículas das três
  unidades direto da API

Estado atual: **1.601 dos 1.618 alunos conferidos contra o Emusys ao vivo, zero
divergência.** Os 17 restantes não têm registro na API (só 5 ativos) e estão
listados no documento. Ambas as migrations estão versionadas no repo
`la-teacher` e guardam o valor antigo de cada linha.

## O que eu preciso de você: a causa raiz

Eu corrigi sintomas. **Não descobri por que o dado entrou errado**, e enquanto
isso não for resolvido, volta no próximo sync. Essa parte é do LA Report, não
minha — por isso está com você.

Apareceram dois padrões distintos, provavelmente dois bugs diferentes:

**Padrão A — a data do responsável foi gravada no campo do aluno.** Prova exata
em dois casos: o Heitor Muniz (id 1466) tinha `1983-04-21`, que é literalmente a
`data_nascimento` da mãe dele, Renata Muniz, no cadastro do Emusys. A Laiane
Marins (id 1469) tinha `1980-12-16`, a data da mãe Aline Marins. Dia, mês e ano
batendo. Resultado: três crianças (9, 7 e 11 anos) estavam gravadas como
adultas de 40+.

**Padrão B — a data ficou alguns dias antes do `created_at` do registro.** O
Tiago (id 1457) foi criado em 27/02/2026 com nascimento em 18/02/2026. O Matheus
Lopes (id 1585) foi criado em 31/03/2026 com nascimento em 24/03/2026. Cheira a
preenchimento por proximidade quando o sync não trouxe a data.

Onde procurar: `sync-matriculas-emusys`, `processar-matricula-emusys`,
`sync-students-studio`, e qualquer rotina de importação ou cadastro manual que
escreva `alunos.data_nascimento`. A pergunta a responder é: **em que caminho a
data do responsável acaba no campo do aluno, e em que caminho a data vira "hoje
menos alguns dias"?**

Se achar, corrija e me diga qual era. Se não achar, me diga onde procurou —
isso vale mais que um palpite.

## Armadilhas que já paguei para descobrir

### Na API do Emusys

- **O header `token` precisa chegar em minúsculo literal.** `urllib` e
  `requests` capitalizam para `Token` e a API responde
  `{"status":"erro","msg":"token invalido!"}` — parece credencial errada e não
  é. Em Python, `http.client` com `putheader("token", ...)` preserva o case.

- **A paginação é por cursor e os parâmetros de página são ignorados em
  silêncio.** O certo é `?cursor=<paginacao.proximo_cursor>` (um base64 de
  `{"id":N}`), com `limite=50` no máximo. `pagina`, `page`, `offset`, `skip` e
  `inicio` são aceitos com HTTP 200 e devolvem sempre o começo da lista. Minha
  primeira coleta "trouxe 30.000 matrículas" que eram 101 alunos repetidos 200
  vezes. **Ponha uma trava que aborte se uma página não trouxer id novo.**

- **O `id` do aluno é por unidade, não global.** 1.003 dos 2.732 ids aparecem
  com nomes diferentes entre Barra, Campo Grande e Recreio — o id 38 é "Augusto
  Ramalho Tratch" na Barra e "Leonardo de Oliveira Gonçalves da Silva" no
  Recreio. **Casar só por `emusys_student_id` junta pessoas diferentes.** Foi
  o que produziu 367 divergências falsas numa das minhas passadas. A chave é
  **(unidade, id)**. Vale para o `emusys_api_payload` também, que por isso tem
  a coluna `unidade_codigo`.

- **1.160 de 1.502 alunos não têm CPF** — criança não tem documento próprio.
  Não use CPF como chave nem como sinal de "é adulto".

- A API é **GET, sem escrita**. O endpoint é `/matriculas`; `/alunos` não
  existe. O payload traz `aluno` e `responsavel` como objetos separados, cada
  um com seu `data_nascimento`.

### No banco

- **`alunos.idade_atual` e `alunos.classificacao` não são fonte de nada.** O
  trigger `trg_alunos_calcular_campos` deriva as duas de `data_nascimento`
  (LAMK < 12, EMLA >= 12). Nunca divergem da data, então não servem para
  detectar erro — só propagam. E se ajustam sozinhas quando a data é corrigida:
  **não escreva nesses campos**.

- **Escrever em `data_nascimento` dispara chamada externa.** O trigger
  `trg_enqueue_sync_student_studio` faz `net.http_post` para a edge function
  `sync-students-studio` a cada alteração — uma por linha. Em teste com
  `BEGIN … ROLLBACK` isso não vaza, porque o `pg_net` enfileira dentro da
  transação.

- **O mesmo aluno tem vários registros em `alunos`**, um por curso — a Maria
  Clara Monteiro de Carvalho tem três, a Beatriz von Glehn tem dois. Corrigir
  um só deixa os outros errados.

## O que não fazer

- Não mexa em `alunos.data_nascimento` sem guardar o valor antigo explícito na
  própria migration, e sem uma guarda que só aja se o valor atual bater com o
  esperado. É o que torna reversível e o que impede sobrescrever correção
  manual de outra pessoa.
- Não confie em "o update não deu erro" — meça o resultado depois e aborte se
  não bater.
- Não apague nem consolide cadastro duplicado sem falar com o Alf. Existe pelo
  menos um caso conhecido (Matheus Lopes de Medeiros, ids 1551 e 1585, mesmo
  `emusys_student_id` 2093 em Campo Grande).

## O que me devolver

1. A causa raiz dos padrões A e B, ou onde você procurou sem achar.
2. Se mexeu no código de sync, o que mudou e como testou.
3. Se os 5 alunos ativos sem registro na API têm explicação do lado do Emusys.
