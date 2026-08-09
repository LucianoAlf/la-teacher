---
name: consultar-prontuario-aluno
description: Ler e narrar a vida pedagógica de um aluno da LA Music — o que ele já estudou, como evoluiu, o que foi registrado sobre ele ao longo do tempo. Usar SEMPRE que a tarefa envolver histórico do aluno, prontuário, "o que ele já viu", evolução, relatório de vida na escola, resumo pedagógico, preparação de aula com base no passado, passagem de bastão entre professores, ou qualquer pergunta que comece com "me conta sobre o aluno X". NÃO usar para registrar uma aula nova (isso é o fluxo normal do Fábio) nem para dados financeiros (proibidos).
---

# Consultar o prontuário do aluno

## O que é o prontuário

A vida pedagógica de um aluno da LA Music é contada por **duas fontes que convivem**:

| Fonte | Quem escreve | O que é |
|---|---|---|
| `aulas_emusys.anotacoes` | o professor, digitando **no Emusys** | o registro histórico (18k+ aulas desde sempre) |
| `aulas_emusys.anotacoes_fabio` | **você (Fábio)**, via `registrar_aula_fabio` | o registro novo, gerado do áudio do professor |

**Elas não competem — elas se somam.** A escola está em transição: os professores estão migrando do Emusys para o app, um a um. Um aluno pode ter anos de anotações do Emusys e, a partir de julho/2026, anotações suas. **As duas são o prontuário dele.**

**Nunca trate a anotação do Emusys como "legado descartável".** Ela é o passado real do aluno — o que ele estudou, o que o professor observou, como ele evoluiu. Um relatório de vida que ignore isso está mentindo por omissão.

## Porta correta de leitura: RPC `fabio_prontuario_aluno`

A porta de entrada do Fábio é a RPC:

```sql
select *
from public.fabio_prontuario_aluno(
  p_aluno_id     := $1,
  p_professor_id := $2,
  p_limite       := $3
);
```

**Não faça `select` direto em `vw_prontuario_aluno`.** A view é camada interna/bruta; ela pode duplicar linha e não é escopada por professor. A RPC deduplica, resolve a pessoa e aplica escopo em SQL.

Parâmetros:

- `p_aluno_id`: qualquer `alunos.id` da pessoa.
- `p_professor_id`: **obrigatório**. Passe sempre o ID do professor autenticado/identificado.
- `p_limite`: limite de registros a retornar; use o suficiente para o caso, sem carregar histórico gigante à toa.

Não passe `null` em `p_professor_id`. Se a solicitação vier de coordenação/admin, esta skill não é a porta correta: escale para a ferramenta/fluxo de coordenação autorizado.

A RPC retorna **um objeto JSON**. Leia principalmente:

- `linha_do_tempo`: array de registros pedagógicos deduplicados;
- `outros_cursos`: cursos/professores fora do escopo, sem conteúdo pedagógico;
- `cursos_no_escopo`: cursos que vieram com conteúdo;
- `aluno_ids_da_pessoa`: linhas locais resolvidas para a pessoa;
- `escopo`: `professor` ou `coordenacao`.

A RPC entrega a timeline já segura:

- resolve a pessoa por `(unidade_id, emusys_student_id)`;
- não consolida por nome quando não há chave segura;
- deduplica registros reais por data + curso canônico;
- exige professor em SQL;
- retorna só conteúdo dos cursos daquele professor;
- informa `outros_cursos` apenas com nome do curso/professor, sem conteúdo;
- mantém `origem` explícita: `emusys` ou `fabio`.

## Identidade: o aluno não é uma linha

**`alunos.id` é uma linha de matrícula, não uma pessoa.** A mesma criança com 3 cursos tem **3 linhas** em `alunos`.

Exemplo real corrigido: a Valentina tem `697` (Canto), `1542` e `1099` (Teclado/Power Kids). São a mesma menina. Pela RPC, a coordenação vê **19 registros reais**, não as 62 linhas infladas da view bruta.

Regra:

- a RPC resolve por `(unidade_id, emusys_student_id)`;
- se não houver `emusys_student_id`, não invente consolidação por nome;
- não reduza dois cursos a uma história só;
- cursos canonicamente equivalentes, como `Canto` e `Canto T`, são deduplicados pela camada SQL.

## Regras de ouro

1. **Nunca invente.** Se não há anotação, diga "sem registro nessa aula". Não preencha buraco com inferência.

2. **Sempre diga a origem.** "Segundo o registro do professor no Emusys (mar/2026)..." é diferente de "No relatório que gerei da aula de segunda...".

3. **Separe os cursos.** Um aluno com Canto e Teclado tem histórias pedagógicas diferentes, com professores diferentes.

4. **Escopo é SQL, não promessa.** Chame a RPC sempre com `p_professor_id`. Nunca busque tudo para depois filtrar no prompt.

5. **Coordenação/admin não usa esta porta do Fábio.** Se pedirem visão completa da pessoa, escale para o fluxo autorizado de coordenação; não tente passar `null`.

6. **Outros cursos sem vazamento.** Se a RPC informar outros cursos, você pode mencionar que existem, mas não revelar conteúdo pedagógico desses cursos.

7. **Zero financeiro.** Nunca. Não existe no prontuário e não pode aparecer.

8. **Nada de anamnese em resposta casual.** É dado sensível (saúde, família, desenvolvimento). Só em tela/autorização específica.

## Escrita: você só escreve numa coluna

Você escreve **exclusivamente** via `registrar_aula_fabio`, e **só** na `anotacoes_fabio`.

**Você NUNCA toca a `anotacoes` do Emusys.** Aquilo é do professor/sync. Existe proteção no banco para preservar o lado do Fábio, e o sync do Emusys foi auditado para não tocar o seu campo. As duas fontes são invioláveis uma pra outra.

## Playbook: "me conta a história do aluno X"

1. Identificar `aluno_id` inicial.
2. Identificar o professor solicitante e obter/passar o `professor_id`.
3. Chamar `fabio_prontuario_aluno(p_aluno_id, p_professor_id, p_limite)`. Se não houver professor_id, parar e escalar; não usar `null`.
4. Ler o array `linha_do_tempo` do JSON retornado.
5. Agrupar por curso conforme retorno da RPC.
6. Narrar a evolução: o que aparece cedo, o que aparece depois, o que se repete, o que foi superado — sempre com evidência textual.
7. Marcar buracos: períodos/aulas sem anotação não são ausência de aula nem ausência de evolução.
8. Fechar com estado atual quando a RPC/dados retornarem isso; se não retornar, não invente.

## Playbook: "prepara minha aula com o aluno X"

1. Se quem pergunta é professor, chamar a RPC com `p_professor_id` dele.
2. Ler as **últimas 3-5 entradas** do curso escopado.
3. Extrair: o que foi trabalhado, próximo passo, dever de casa e qualquer alerta pedagógico com evidência.
4. Entregar curto:
   - última aula registrada;
   - continuidade sugerida;
   - pergunta útil pro professor completar se houver buraco.
5. Se não houver registro recente, diga: "Sem registro desde X. Não sei o que vocês fizeram depois disso."

## O que NÃO fazer

- ❌ Fazer `select` direto em `vw_prontuario_aluno` como porta do Fábio.
- ❌ Filtrar escopo de professor só no prompt.
- ❌ Passar `p_professor_id = null` na RPC do Fábio.
- ❌ Tentar usar `coord_prontuario_aluno` ou função interna pelo Fábio.
- ❌ Copiar anotação do Emusys para `anotacoes_fabio` ("migrar o histórico").
- ❌ Consolidar por nome quando não existe chave segura.
- ❌ Narrar a mesma aula várias vezes por duplicata da view bruta.
- ❌ Reduzir dois cursos a um contador ou a uma história só.
- ❌ Apresentar inferência de IA como se fosse registro do professor.
- ❌ Tratar cobertura zero como "o aluno não evoluiu".

## Estado atual (jul/2026)

- 18.729 aulas com anotação do Emusys.
- A Valentina, caso de validação, retorna pela RPC do Fábio:
  - Matheus → 13 registros, só Canto;
  - Alexandre → 5 registros, só Teclado.
- A visão completa de coordenação existe em porta separada, sem grant para `fabio_agent`.
- As primeiras anotações do Fábio começam a nascer com o professor-piloto (Matheus, prof. 25).
- Espere `origem: 'emusys'` na maioria por enquanto. Isso é normal, não erro.

## O semáforo do mês (`semaforo`) — desde 09/08/2026

A mesma RPC devolve a chave **`semaforo`**: o que **este professor** respondeu
sobre **esta pessoa** no Feedback do mês, nas até 3 competências mais recentes.

Cada item tem: `competencia`, `coracao` (`verde`/`amarelo`/`vermelho`),
`pratica_em_casa`, `evolucao`, `animo`, `observacao` e `respondido_em`.

**Isto é a percepção do professor, não medição.** É o que ele SENTE sobre o
aluno — vale como sinal e como abertura de conversa, nunca como fato provado.
"Você marcou ela em amarelo mês passado" é legítimo; "ela está em queda" não é.

Quando usar:

- o professor pergunta sobre o aluno → se houver semáforo, cite o mais recente
  junto do prontuário. É o dado mais atual que existe sobre a percepção dele;
- ele vai dar aula → um `vermelho` ou um `desanimado` do mês muda o tom da
  preparação;
- ele já escreveu observação → **é a fala dele**. Devolva como fala dele
  ("você anotou que…"), sem reescrever nem suavizar.

O que NÃO fazer:

- ❌ **Nunca** falar do semáforo de OUTRO professor. A RPC já filtra por
  `professor_id`, e essa fronteira não se abre por pedido — se ele perguntar
  "o que o fulano achou dela?", a resposta é que isso é conversa da coordenação.
- ❌ Nunca mandar o coração nem a observação pro aluno, pro responsável ou pra
  devolutiva. O convite escrito na tela é "algo que vale a COORDENAÇÃO saber".
- ❌ `semaforo: []` significa **não respondido ainda** — não significa
  "está tudo bem". Nesse caso diga que ainda não há feedback do mês.
- ❌ Não inventar tendência com uma competência só. Duas ou três, sim: "de
  amarelo pra verde" é uma leitura honesta; com uma linha só não existe "de".

**Quem responde o feedback é o PRÓPRIO professor**, no app (Alunos → Feedback do
mês) — não é devolutiva da família, não é pesquisa com o responsável. Medido em
09/08/2026: com `semaforo: []` o Fábio perguntou "você chegou a receber alguma
devolutiva dela ou da mãe?", confundindo as duas coisas. Com a lista vazia, a
frase certa é do tipo: "você ainda não marcou o coração dela este mês — dá pra
fazer em Alunos → Feedback do mês, leva um minuto".
