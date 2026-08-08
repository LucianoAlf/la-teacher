# Painel da coordenação — design

**Data:** 08/08/2026 · **Decidido com:** Alf · **Estado:** aprovado no desenho,
falta plano de implementação.

Todo número citado aqui foi **medido no banco em 08/08/2026**, não estimado.

---

## 1. O problema

A coordenação (Juliana, Quintela, Hugo, Alf) não tem tela no LA Teacher. Hoje
elas olham a "Gestão de Professores" do LA Report, que é **mensal e analítica**:
health score, ranking, ciclo, premiação. Nada ali responde *"o que está em aberto
agora"*.

E o app do professor acabou de entrar no ar com gente de verdade. Sem alguém
olhando o que chega, o registro do professor não vira nada.

## 2. A fronteira com o LA Report — decidida

> **Aqui é diário e ação. Lá é mensal e analítico.** — Alf, 08/08

- **Agora:** ranking, premiação e mês fechado ficam no LA Report.
- **Destino:** um painel só, aqui. Palavras dele: *"senão a coordenação vai ficar
  acessando dois sistemas. O ideal é elas terem o painel delas aqui, com o que
  realmente importa lá do LA Report."*
- O painel daqui é **curadoria, não espelho**.

**Regra de ouro:** o banco é o mesmo projeto (`ouqwbbermlzqqvtqwlul`), então
chamar a RPC do LA Report é **consulta, não integração**. O LA Teacher **nunca
recalcula** o que o LA Report já calcula — é assim que nascem dois números para a
mesma pergunta.

O que o LA Report já entrega e deve ser consumido como está:

| O que | Onde |
|---|---|
| 50 colunas por professor/período | `get_kpis_professor_periodo_canonico_v3` |
| Health Score V3 (5 pilares de nota + 1 diagnóstico), já honesto | `src/lib/healthScoreProfessorV3.ts` |
| Relatório de coordenação (ranking, carteira, presença, retenção) | `get_relatorio_coordenacao_canonico_v3` |
| 360° do professor (8 critérios) | `professor_360_*` |
| Carteira, agenda do dia, jornada, saídas | `get_carteira_professores`, `get_agenda_dia`, `get_jornada_professor` |

⚠️ A pilha do relatório de coordenação tem **5 camadas**
(`v3 → payload_v3 → v2 → payload_v2 → kpis_v3 → kpis_v2`). Consumir **o contrato
de saída**, nunca replicar a pilha.

## 3. Quem vê

Todos os quatro veem **tudo**. A divisão LA Music School × LA Music Kids é
interna e **não é recorte de permissão** (Alf, 08/08). Unidade (Barra, Campo
Grande, Recreio) é **filtro na tela**, não fronteira de acesso.

A porta já existe: `public.fn_e_coordenacao_la_teacher()` (migration 062), sem
argumento, lendo `la_teacher_coordenacao` — que hoje tem 4 pessoas. Ela **não** é
`perfil='admin'` do LA Report de propósito: aquele conjunto tem 11 pessoas,
incluindo Marketing e Comercial.

## 4. Arquitetura

**Rota:** `/app/coordenacao`, sob um guard próprio — o mesmo padrão que
`/app/equipe` já usa em `src/routes.tsx:108`.

Isso importa: `RequireProfessor` manda quem não tem vínculo de professor para
"Vínculo pendente". A Juliana **não é professora**. Se o painel entrar sob o
guard do professor, a dona do painel bate na tela de quem não tem acesso — foi
exatamente esse defeito que apareceu no login da coordenação em 08/08.

**Shell:** um app só, dois desenhos por breakpoint — o `AppFrame` atual no
celular, e um shell de sidebar no desktop, copiado do LA Organizer (ele já pagou
esse pedágio).

**Desktop e mobile não são a mesma tela redimensionada** (ver §7).

## 5. Bloco 1 — "quem está em aberto"

O que a coordenação cobra. **Professor é a linha**, não o número solto.

**Fonte:** `public.vw_presenca_pendencia` — a view canônica de "sem presença
forte" (migration 013), agregada por professor.

**Faixa de quatro números no topo:** sem lançamento em 7 dias · professores
afetados · só de ontem · experimentais da semana.

**Colunas:** professor (com unidade embaixo) · em aberto · alunos · pior atraso ·
ação.

**Ordenação: por urgência, nunca alfabética.** Esse erro já aconteceu no painel
de equipe — eu escrevi que a fila era por urgência e ela era alfabética.

**Duas ações na própria linha:** recado pelo Fábio, e seta para o detalhe do
professor. A coordenação age de onde está olhando.

**Estado medido em 08/08:** 847 linhas de aluno-aula em 7 dias, 38 dos 44
professores, 31 só de ontem.

## 6. Bloco 2 — "o que os professores registraram"

Escolha do Alf, e é o bloco que **dá motivo de abrir o painel**: o bloco 1 é a
tarefa chata, este é a realidade pedagógica.

**Estado medido em 08/08 — este é hoje o bloco mais magro:**

| | |
|---|---|
| Registros de aula | 63 (52 `gravado_emusys`, 4 `confirmado`, 1 aguardando, 6 descartados) |
| Professores que registraram | **1** (o Matheus) |
| Nos últimos 7 dias | 32 |
| Registros de experimental | **0** — o ciclo está no ar e ninguém usou |

Ele enche na medida em que os 15 voluntários entrarem. É o **retrato da adoção**.

### 6.1 A armadilha de escala

Com 44 professores registrando, o volume vai para **850+ por semana** (a
pendência de hoje já são 847 linhas em 7 dias). Um feed cronológico de 850 itens
não é painel, é mural que ninguém lê.

**Portanto este bloco nunca é "todos os registros". É curadoria do Fábio** — ele
já lê o texto inteiro, é ele quem sabe separar.

### 6.2 O selo não pode ser `gravado_emusys`

Esse status **mente**: o texto do Fábio não chega ao campo `anotacoes` do Emusys
(documentado em
[spec da devolutiva §78](2026-08-03-devolutiva-aula-design.md)). Um painel que
mostra "registrado" apoiado nele repete a mentira.

**O selo honesto é "o professor confirmou e havia conteúdo"** — disso o status é
prova, independente do nome errado.

## 7. O que faz um registro subir

Critérios do Alf (08/08), medidos campo a campo em `fabio_registros_aula.campos`:

| Critério | Entra na v1? | Por quê |
|---|---|---|
| Aluno em risco | ✅ | o Fábio marca lendo o texto |
| Aluno se destacou | ✅ | idem — não só problema sobe |
| Silêncio do professor | ✅ | é ausência de registro, não registro (ver §7.2) |
| **Estagnação por `eixos`** | ✅ | `eixos` é **array estruturado e já preenchido**: `["TecnicaVocal","Repertorio"]`, `["IdentidadeMusical"]`. Comparável hoje, sem construir nada. **Limiar: 60 dias** sem nenhum eixo novo aparecer, com no mínimo 4 registros no período (senão um aluno que faltou muito vira falso positivo) |
| Muito tempo no mesmo **repertório** | ❌ adiado | é o campo **mais preenchido** (57/63) mas **texto livre**: `Asa Branca`, `Altar Particular — Maria Gadú`. `group by` não serve |
| Desalinhamento com a **Jornada Pedagógica** | ❌ adiado | **não existe o lado do "deveria"** |

### 7.1 Por que os dois últimos ficaram de fora

**Repertório.** A primeira consulta que eu rodei devolveu quatro alunos
"repetindo o mesmo repertório" — e os quatro tinham `repertorio` **null**. O null
agrupou junto e fabricou o achado. O único caso real foi um aluno com "Fica com
Deus", 2 aulas em 23 dias. **O `group by` ingênuo mentiu antes de virar tela.**
Para entrar: ou o Fábio compara (ele entende que é a mesma música), ou o campo
vira canônico (lista/autocomplete).

**Jornada Pedagógica.** `marco_ref` é **null em 29 de 29** — o campo está no
molde e ninguém preenche. E a `vw_jornada_marcos` do banco **não é a jornada
pedagógica**: as 41 colunas dela são `nr_aulas_contratadas`, `nr_aulas_passadas`,
`percentual_jornada`, `presencas`, `faltas` — é jornada **contratual**. Não há
trilha esperada contra a qual medir desalinhamento. Isso é o RAG pedagógico (#61)
e o LA Journey, não uma consulta.

### 7.2 O silêncio não cabe na mesma tabela

Três dos quatro sinais **penduram num registro**. "Silêncio do professor" pendura
na **ausência** dele — quem registrava e parou. Ele não pode ser uma linha na
tabela de sinais; é derivado na consulta, comparando o ritmo do professor com o
dele mesmo.

## 8. Mobile — o plantão, não o escritório

> *"Só o que pede decisão agora."* — Alf, 08/08

No celular a coordenação está **longe da mesa**: andando pela escola, entre
salas, ou em casa no domingo. O mobile entrega uma **lista curta do que não pode
esperar, com o botão de resolver ali**. Chega por push.

O painel completo é do desktop. **O mobile não é o painel espremido** — tabela de
cinco colunas no celular vira rolagem lateral, que é a forma mais rápida de
alguém parar de abrir.

## 9. O que fica de fora, de propósito

- **Nota, health score e ranking.** Existem e são bons no LA Report. Repetir aqui
  cria o segundo número. Entram quando a decisão de trazer o mês fechado for
  tomada — e aí saem de lá.
- **Terceiro bloco na home.** Os quatro sinais já cobrem risco, destaque,
  silêncio e estagnação. Retenção e experimentais viram **filtro dentro do bloco
  2**, não bloco novo. Um terceiro bloco nasce de falta sentida, não de espaço
  vazio.
- **Aluno.** A coordenação não navega por aluno (Alf). Chega nele pelo registro.

## 10. Contratos de dados a criar

| Contrato | Entrega |
|---|---|
| `app_coordenacao_em_aberto(p_dias, p_unidade_id)` | bloco 1, agregado por professor |
| `app_coordenacao_sinais(p_dias, p_unidade_id, p_tipo)` | bloco 2 — registros curados + o silêncio derivado |
| `app_coordenacao_plantao()` | mobile — só o que pede decisão agora |
| `fabio_registro_sinais` (tabela) | onde o Fábio grava o que ele destacou: `registro_id`, `tipo`, `motivo`, `skill_versao`, `criado_em`. Separada de `fabio_registros_aula` de propósito — é **opinião do Fábio**, não registro do professor, e pode ser recalculada sem tocar no que o professor escreveu |

Todos sob `fn_e_coordenacao_la_teacher()`, `security definer`, com `revoke` de
`anon`/`authenticated` — o padrão das migrations 062/063.

## 11. Armadilhas já medidas

- **Ordenar por urgência, não por nome.** Já errei isso uma vez.
- **`gravado_emusys` mente.** Não usar como selo.
- **`group by` em texto livre fabrica achado.** O null agrupa e vira falso
  positivo.
- **Guard próprio, fora do `RequireProfessor`.** A coordenação não tem vínculo de
  professor.
- **Não recalcular o que o LA Report calcula.**
- **`create or replace` preserva privilégios** — mutante de permissão precisa
  `grant`/`revoke` de propósito.

## 12. Registrado para depois (fora desta spec)

Achados da auditoria do LA Report que **não** são deste desenho, mas nascem dele:

1. **O ritual está lá, a evidência está aqui.** `Preenchimento EMUSYS` é o
   critério mais pesado do 360° (peso 25) e é digitado à mão: 18 ocorrências em
   jun/2026, 1 em jul, **0 em ago**. A `vw_presenca_pendencia` mede a mesma coisa
   sozinha. Ligar os dois é a costura mais valiosa — e é o que transforma o bloco
   1 de lista em governança.
2. **192 de 192 ocorrências do 360° não têm autor** (`registrado_por` null).
   Resolver **antes** de a coordenação lançar ocorrência pelo app.
3. **`professor_360_avaliacoes` tem 0 linhas** e a tela mostra 75 avaliações
   "Pendente": a nota nunca é consolidada, então mexer no peso de um critério
   muda a nota de meses passados.
4. **Duas réguas de presença honesta, nunca comparadas.** O LA Report tem
   `presenca_publicavel`/`presenca_confianca`/`presenca_cobertura`; o LA Teacher
   tem `fn_presenca_e_forte`. **Medir se concordam antes de o painel exibir
   qualquer percentual de presença.**
