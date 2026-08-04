# Auditoria ao vivo — 04/08/2026

Feita a pedido do Alf depois da conversa do Matheus com o Fábio sobre a aluna
Fernanda. Três frentes: regressão do que subiu ontem, o caso da Fernanda, e
aulas experimentais.

---

## ✅ Sem regressão. O que o Matheus registrou ontem está íntegro

Quatro fatias confirmadas e gravadas (`gravado_emusys`) em 03/08: Arthur,
Gustavo, Maria Isabel e Amanda. **Todas com presença `presente` e forte** —
`aluno_presenca.status_presenca = 'presente'` para as quatro. As devolutivas
saíram dessas mesmas fatias e a oferta chegou nele às 18:55.

### Duas coisas menores, reais

**1. Um par de registro ficou pela metade.** Às 16:11 o Matheus gravou a aula
da Amanda; a raiz ficou `confirmado` e a fatia dela ficou
`aguardando_confirmacao` — porque **não havia `presenca` nos campos**. Às 18:09
ele refez, dessa vez com presença, e aí completou.

Isso é a migration 019 **funcionando como projetada**: ela não deixa passar
registro sem presença declarada. O que sobra é lixo — um par órfão que nunca
vai fechar sozinho. É 1 caso em toda a base, mas vai acontecer de novo.

**2. Presença duplicada.** Cada aluno tem **duas** linhas em `aluno_presenca`
para a mesma data e curso: uma com `emusys_presenca_bruta` nulo (a do
professor, pelo app) e outra com `'presente'` (a que veio do Emusys). As duas
concordam, então não há conflito — mas infla qualquer contagem que não
deduplique.

---

## ⚠️ A Fernanda: o Fábio tinha o dado e não usou

**Fernanda Gonçalves Freire (id 1897)** — 17 anos, Canto, Campo Grande,
professora responsável Daniele. E o dado que responde a pergunta do Matheus
estava ali:

| campo | valor |
|---|---|
| `data_matricula` | **2026-08-03** (ontem) |
| `emusys_student_id` | **null** (não veio do Emusys) |
| registros de aula | 0 |
| presenças | 0 |

**Ela é aluna nova, matriculada ontem.** O Fábio respondeu *"não consigo
afirmar isso só pelo histórico"* quando bastava olhar a data de matrícula.

Ele não errou por inventar — errou por **não ter a carteira na mão**. O
contexto que ele recebe traz histórico de aula, não o cadastro do aluno.

> Vale registrar: quando o Matheus disse *"eu vi que ela tem registro de outras
> aulas"*, o que existe são **dois vínculos de aula** (agenda), não conteúdo
> registrado. O Fábio estava certo sobre isso.

### Ela aparece DUAS vezes na agenda de hoje

Mesma turma `C_Ter_17`, dois ids: `204645` e `16125902`. São duas faixas de id
diferentes na `aulas_emusys` — as normais (até 22/08) e as ">1 milhão", que vão
até 08/09 e vêm do `sync-grade-futura-emusys`. **As duas grades se sobrepõem**,
e por isso a mesma aula conta duas vezes. É a mesma raiz da presença duplicada.

---

## 🔴 O achado grande: a aula experimental é invisível pro professor

`aulas_emusys.tipo` só conhece três valores: **`ensaio`, `individual`,
`turma`**. Não existe `experimental`.

E as experimentais existem, em volume:

| | |
|---|---|
| `lead_experimentais` | 1.016 registros, **88 nos últimos 7 dias** |
| Agendadas de hoje em diante | 16 |
| **Dessas, quantas existem em `aulas_emusys`** | **2 de 16** |

**14 das 16 aulas experimentais agendadas não estão na agenda.** O professor
abre o app e elas não estão lá. Duas são hoje:

- 17:00 — Daniela Andrade, Piano, Recreio — prof. Isaque
- 17:30 — Pedro Andrade, Piano, Recreio — prof. Isaque

Nenhuma do Matheus hoje, por isso não apareceu no piloto.

### O que isso significa na prática

1. **O professor não é avisado** de que vai receber uma experimental.
2. **O Fábio não sabe preparar** uma experimental — pra ele é aula normal, e
   ele nem a enxerga.
3. **Uma experimental dentro de uma turma** (o caso mais comum) não se
   distingue dos alunos matriculados. A abordagem é outra: é uma pessoa
   decidindo se fica na escola.
4. Se o registro de aula rodar em cima disso, a criança experimental entra na
   mesma vala dos matriculados — inclusive na devolutiva.

O dado está no LA Report (`lead_experimentais` tem professor, curso, unidade,
horário e `emusys_aula_id`). **A ponte para o LA Teacher é que não existe.**

---

## Para a spec

O que o Alf levantou e esta auditoria confirma:

- A **carteira** precisa chegar no contexto do Fábio: quem é o aluno, desde
  quando, se é novo, se é experimental. Hoje ele só recebe histórico de aula.
- **Aula experimental precisa ser um tipo de primeira classe** — na agenda, no
  registro e no que o Fábio prepara.
- **Alerta ao professor** quando uma experimental cai na agenda dele (o padrão
  da Mila, que já dispara no comercial).
- Dentro de uma turma, o aluno experimental precisa ser **visualmente
  distinto**, e a devolutiva dele — se existir — é outra conversa.

### Correções menores, independentes da spec

- Fechar o par órfão de registro (1 caso hoje) e decidir o que faz com
  `confirmado` + `aguardando_confirmacao` que não fecham.
- Deduplicar `aluno_presenca` e a agenda quando as duas grades se sobrepõem.
