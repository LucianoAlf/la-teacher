# Arquitetura da Jornada do Aluno — LA Teacher

**Versão:** 1.12
**Data:** 10/07/2026
**Status:** **MVP no ar — 5 telas do professor + backend validado.** Bug de ponto corrigido (11h10→4h20, provado). 1º teste real de chamada: seg 13/07 11h. Merge pendente (credenciais CI).
**Autor:** Alf + Claude (projeto LA Teacher)

---

## 0. Por que este documento existe

O LA Teacher já tem o básico de pé: alunos no app, professor grava áudio, Fábio
transforma em relatório. Mas o app estava nascendo **sobre a camada de dados**,
sem um modelo do **ciclo de vida do aluno**. Sem esse modelo, cada feature nova
vira tela solta e o app vira gambiarra.

Este documento é a espinha. Cada tela e cada RPC futura tem um lugar aqui: em que
fase da jornada entra, de onde vem o dado, quem age, e o que o professor vê ou faz.
**O app nasce sobre este modelo, usando a camada de dados.**

É a fonte de verdade da regra de negócio da jornada. Fica ao lado do Dossiê
Central (infra/estado do build).

---

## 1. Os dois eixos

- **Eixo do aluno** — a vida dele na escola. Existe independente de professor:
  lead → experimental → matrícula → 40 aulas → renovação → saída.
- **Eixo do professor** — o LA Teacher é a **lente do professor sobre a jornada
  do aluno**. Em algumas fases ele age; em outras só herda contexto.

Para cada fase: **"o que o professor vê e o que ele faz aqui"** define tela e RPC.

---

## 2. Conceito central: os TRÊS planos da jornada

### PLANO 1 — POSIÇÃO — *onde o aluno está*
Aula 36/40, marcos, renovação. Vem do Emusys, muda a cada aula.
**JÁ EXISTE:** `aluno_jornada_matricula_disciplina` + `vw_jornada_*` +
`get_jornada_professor/aluno`. Jornada é por **matrícula/disciplina**.

### PLANO 2 — CONTEXTO (PRONTUÁRIO) — *quem o aluno é e o que quer*
Objetivo, sonho, gosto, temperamento, expectativa, evolução. Nasce no lead e
**acumula pela vida inteira. Só cresce.** A CONSTRUIR (em parte). Metáfora:
prontuário médico.

### PLANO 3 — HEALTH SCORE — *quão saudável está a jornada*
Leitura preditiva de evasão por cima dos planos 1 e 2 + eventos (14 sinais).
**O LA Teacher ALIMENTA sinais; NÃO calcula o score.** Encaixa com `risco_evasao`.

### As 4 regras invioláveis do Prontuário
1. **Pendurado no ALUNO** (antes, no lead). Nunca no professor. Sobrevive à troca.
2. **Append, não overwrite.**
3. **Push estruturado, não pull.** Cada fase materializa; o Fábio lê pronto.
4. **Fábio é o roteador** (inclusive handoff A→B).

---

## 3. Ecossistema — três apps conectados

```
LA Teacher  ──►  LA Report (LAHQ)  ──►  LA Journey
(lente do          (verdade dos dados:     (material didático:
 professor)         posição, prontuário,     repertório, backing
                    sinais, health score)    tracks, exercícios)
```

LA Teacher captura e mostra. LA Report é a verdade (lê/escreve aqui, nunca
direto no Emusys). LA Journey (fase 2) gera material — o **Fábio orquestra**.
**Princípio:** o LA Teacher não gera material e não calcula score. Captura e
orquestra. Isso o mantém enxuto.

---

## 4. As fases do ciclo de vida (macro) — MAPA COMPLETO

| # | Fase | Professor age? | Status |
|---|------|----------------|--------|
| 1 | Lead → Experimental | Não (recebe handoff / dá a experimental) | **Fechada** |
| 2 | Matrícula + Anamnese | Não (consome ficha) | **Fechada** |
| 3 | Ciclo de 40 aulas | Sim (ministra, presença, dever, devolutiva, semáforo) | **Fechada** |
| 4 | Movimentação + passagem de bastão | Não opera; é notificado | **Fechada** |
| 5 | Renovação (+40, novo ciclo) | Ativo (relatório de ciclo, engajamento) | **Fechada** |
| 6 | Saída (aviso prévio, não-renovação, evasão) | Ativo só no reversível | **Fechada** |

---

## 5. ETAPA 1 — Lead → Experimental  *(FECHADA)*

**Quem age:** Mila (capta) + comercial (encaixa). Professor recebe o handoff.
**Professor vê a partir de:** experimental **agendada**.
**App mostra:** dossiê pedagógico **estruturado** (de `crm_mensagens` + `leads`),
não o campo Observações raso da Mila.
**Captura (MVP):** pós-experimental, o professor registra como foi (via Fábio/áudio).
**Vira permanente:** dossiê da Mila + registro da experimental.
**Alerta:** registro da experimental é de LEAD → mora em `lead_experimentais`,
nunca em `aulas_emusys`.

---

## 6. ETAPA 2 — Matrícula + Anamnese  *(FECHADA)*

Lead converte em aluno (`leads.converteu`, `leads.aluno_id`). O dossiê **migra**
pela ponte `leads.aluno_id` ↔ `alunos.lead_origem_id` — não se perde.

**Anamnese:** preenchida pelo aluno/responsável no **tablet**, na matrícula. No
LA Teacher é **leitura**, não captura. Camada mais profunda do prontuário. Já
madura (`anamneses` + `anamnese_respostas_perfil`, com insights e disparo WhatsApp).
**Insights: Fábio REAPROVEITA** e complementa — não regenera.

**6.2 Handoff A→B (na matrícula):** Fábio detecta troca (professor da experimental
≠ `alunos.professor_atual_id`) e entrega ao B: dossiê Mila + registro do A + anamnese.

---

## 7. ETAPA 3 — Ciclo das 40 aulas  *(FECHADA)*

**Núcleo (já de pé):** áudio → relatório por aluno (tronco+slices), confirmação
com nudges, gravação na linha individual.

### A) Por aula
**ANTES — resumo do prontuário à vista:** objetivo/sonho + posição (X/40) + onde
parou. Fecha o loop "não deixar o professor esquecer o objetivo inicial".
**DEPOIS — o registro alimenta:**
1. **Relatório** *(✓)* — registro interno; sinal #14 (eletrocardiograma).
2. **Presença** — o professor **registra presença/falta no LA Teacher** (grava em
   `aluno_presenca`, no LA Report), **em lote por voz** ("vieram todos menos o Fulano").
   Coexiste com a recepção (que segue marcando no Emusys → sync). **Dupla fonte sem
   sobrescrita:** `uq_presenca_aluno_aula (aluno_id, aula_emusys_id)` + `ON CONFLICT DO
   NOTHING` = **first-write-wins**. Alimenta #6 e #9.
   **Pré-requisito — ROSTER (8.2):** `aulas_emusys` guarda só a *quantidade* de alunos, não *quais*.
   Pro professor marcar em lote, precisa saber quem está na aula **antes** de o Emusys escrever presença
   → criar `aula_alunos_emusys` (roster: identificadores, sem contato/financeiro), populado antes da aula
   por sync dedicado. Aula com aluno não conciliado → bloqueio operacional explícito no app (não inventa
   aluno, não grava lote parcial). Match por `(unidade_id, emusys_student_id)`.
   **Semântica de `ausente` (8.1 — CONFIRMADA pelo Emusys/Mateus):** presença é boolean; a regra do
   Emusys é **"aula passada sem registro = falta; aula futura = nem falta nem presença"**. Ou seja, o
   Emusys reporta `ausente` para toda aula passada não-marcada (por ausência de registro, não por falta
   confirmada). **Consequência obrigatória — regra de maturidade:** o sync só materializa a falta **após
   uma janela** (≥ a janela dada ao professor; ~24–48h). Dentro dela, o professor escreve primeiro
   (first-write-wins a favor dele); passada, o Emusys assume. Sem isso, o `ausente`-por-ausência
   bloquearia o professor. **Aula CANCELADA** (webhook do Emusys) é **terceiro estado**: não credita
   falta a ninguém, não conta pro ponto — separa "não aconteceu" de "aconteceu e o aluno faltou".
   **Correção (8.3 / D6):** first-write-wins não tem desfazer. O professor **nunca edita após enviar**
   (protege contra manipulação de PJ); a **coordenação** corrige por RPC administrativa com motivo +
   trilha append-only. Versão mínima no MVP.
   **Status é máquina de estados, não binário:** o professor grava `presente`/`falta`; a camada
   **justificativa/reposição** é **decisão administrativa** da gerência+relacionamento **no Emusys** —
   chega **read-only** pelo sync, e mora em **tabela SEPARADA** (D3), não misturada com a presença (planos
   e donos diferentes). A reposição **nasce** de uma falta justificada → conecta com "aulas a repor".
   **Ponto do professor = DERIVADO da presença, com regra de prova:** aluno presente é prova dura; falta
   isolada não prova nada. **O ponto do dia = intervalo entre a 1ª e a última presença de aluno**, usando
   `aulas_emusys.data_hora_inicio/fim` (não `horario_aula`, que pode ser nulo). **Crédito por HORÁRIO
   DISTINTO (slot), NÃO por linha:** o Emusys manda turma + individuais paralelas no mesmo horário (várias
   linhas de `aulas_emusys` no mesmo slot); creditar por linha multiplicaria as horas (medido: 15 linhas
   para 6h reais). Deduplicar por `(professor, data_hora_inicio, data_hora_fim)`. Faltas **cercadas** contam;
   faltas nas **pontas** não creditam. **Uma única aula presente credita a duração dela** (não zero). Ponta
   ambígua → **um toque do Fábio**; sem resposta, default conservador. Zero "bater ponto" no dia a dia.
   **Chamada vai na ÂNCORA (turma), conteúdo na INDIVIDUAL:** presença (presente/falta, não sensível) é
   lançada na aula de turma, uma vez pro roster inteiro; o relatório do Fábio (sensível, não pode vazar
   entre alunos) vai na linha individual de cada aluno (`aula_id_alvo`). Eixos diferentes, não se contradizem.
3. **Dever de casa** — nasce no LA Teacher; Fábio cutuca. Alimenta #4. Material via
   **LA Journey (fase 2)**.
4. **Devolutiva aos pais** — **entra no MVP**; peça em linguagem de pai, **disparada
   pelo canal instrumentado** (ver 11.8), não pelo WhatsApp pessoal do professor. Conecta #13.

### B) Periódico (mensal)
**Semáforo + avaliação pedagógica** — **entra no MVP**. Múltipla escolha; o semáforo
nasce das respostas. Alimenta #2 e #5. Base: `aluno_feedback_professor` +
`aluno_feedback_sessoes`.

**Princípio:** LA Teacher **captura sinais, não calcula score**. O painel é o consumidor.

---

## 8. ETAPA 4 — Movimentação + Passagem de bastão  *(FECHADA)*

**Natureza: reativa.** O professor **não opera** movimentação (quem move é a
secretaria no Emusys). O LA Teacher reflete o novo estado, notifica e dispara a
passagem de bastão quando há troca de professor. Sem "tela de mover aluno".

### Princípio: NOTIFICAÇÃO UNIVERSAL
**Toda movimentação notifica o professor, SEMPRE, em dois canais: app + WhatsApp**
(UAZAPI). Nada muda na carteira dele sem ele saber.

### Os casos
| Movimentação | Dado | O que o professor vê |
|--------------|------|----------------------|
| Troca horário/turma (mesmo prof) | Webhook atualiza canônica | Agenda atualiza **+ notificação** |
| Troca de professor (A→B) | Canônica passa pro B | Entra na carteira do B **com histórico + selo "novo aluno" + notificação**; dispara passagem de bastão |
| Trancamento | `movimentacoes_admin` | Vai pra seção **"inativos/trancados"** (não some) **+ notificação com motivo** |
| Retorno | Ponte religa | Histórico **reaparece automático + notificação**; se prof diferente, passagem de bastão |

### Passagem de bastão — CONSTRUÍDA (backend pronto e verificado)
- **Fria — `aluno_professor_transicoes`:** de-para automático por matrícula/disciplina;
  capturado no webhook **antes** do upsert sobrescrever.
- **Quente — `professor_passagem_bastao`:** avaliação humana do professor que sai.
  **Ativa** (Fábio cutuca), **assíncrona** (pendência do A), **não-bloqueante** (B já
  tem o prontuário). Status `pendente`/`respondido`/`dispensado` + `motivo_dispensa`.

Migration `20260709120000`, 4 RPCs, RLS, captura no edge v52. **Verificado no banco.**
Falta: Fábio (cutucada + transcrição + resumo) e UI.
**Padrão de vínculo (RLS de todo o LA Teacher):** o professor é resolvido por
`fn_professor_do_usuario` (`professores.usuario_id → usuarios.auth_user_id`), que já existe
desde a migração 001. Não é correção a fazer — é o padrão a usar em toda RPC guardada.

A camada quente é a **primeira peça ativa do prontuário** — captura o conhecimento
tácito de quem deu aula.

---

## 9. ETAPA 5 — Renovação  *(FECHADA)*

**Ciclo fixo:** 40 aulas para todos. Gatilho real na **aula 32** (~2 meses antes),
não na 36. A 32 **prepara o terreno**; a 36 é a cobrança.

- **Aula 32 → o PROFESSOR envia o relatório de ciclo** pro pai/aluno. Peça
  estimulante, síntese da evolução das 40 aulas. Preparação **emocional**. (Vídeo do
  aluno tocando = fase futura.)
- **Aula 36 → farmers/Sol enviam o pedido de renovação** com reajuste. Cobrança.

**Lógica:** o pai já foi massageado na 32 com algo afetivo e concreto — o reajuste
dói menos. **Separa preparação emocional (professor) de cobrança (Sol/farmers).**

### O relatório de ciclo (peça nova)
Diferente do relatório de aula (pontual). É a **síntese das 40 aulas**, virada pro
pai, tom de celebração. **Capacidade já existe no LA Report** → reaproveitar; muda o
gatilho (aula 32) e o destinatário (pai). **Sai do PROFESSOR, não das farmers** —
material estimulante saindo da cobrança perde força. Disparado **pelo canal
instrumentado** (ver 11.8), no número oficial da escola — não pelo WhatsApp pessoal.

### Lente do professor
- **Aula 32:** Fábio gera o relatório de ciclo, o professor dispara. **ENTRA NO MVP.**
- **Aula 36:** cobrança **não é do professor nem do Fábio** — é Sol/farmers.
- **Fábio na renovação = CONSULTOR do professor:** cruza sinais e aconselha *ele*.
  **Não escala pras farmers** — a ponte entre times é da Lia/Sol.

---

## 10. ETAPA 6 — Saída  *(FECHADA)*

**Saída não é uma coisa — são TRÊS, com DOIS destinos.** Misturar seria erro.

### Os três tipos
1. **Aviso prévio** — 1 mês pra reverter. **O professor é acionado ATIVAMENTE:**
   - Seção **"alunos em aviso prévio no mês"** no app, com alerta.
   - No **relatório diário do WhatsApp**, o aluno vem **marcado**, com sugestão do
     Fábio: feedback no fim da aula, mostrar que continua evoluindo, sugestões pra reverter.
   - **A reversão é EXCLUSIVA do professor.** Não ADM, não gerente — só ele, na sala.
     (Oposto da renovação: lá a cobrança é da Sol; na saída, o poder é do professor.)
   - **Filtro de reversibilidade:** se é irreversível (mudança pros EUA), o Fábio
     **não enche o saco**. Distingue reversível de irreversível; só aciona quando faz sentido.
2. **Não-renovação** e **3. Evasão** — o professor é **notificado da perda**, sem tarefa
   de reversão. Se o motivo for **pedagógico** (travou na jornada, não sentiu evolução),
   vira **histórico que o Fábio lê** e usa pra aconselhar. Aprendizado.

### A pesquisa de saída (fronteira delicada)
- Pergunta simples ("se pudesse mudar algo pra sua experiência ter sido melhor, o que
  mudaria?"), áudio permitido. Já existe no LA Report, não automatizada.
- **Canal CONFIDENCIAL — o professor NÃO tem acesso.** É da **Lia** (sucesso), pra
  melhorar serviço e treinar. Encaixa no mapa de fronteira dos agentes.
- **Timing:** na hora o cliente fala "financeiro/tempo"; depois de um período relaxa e
  fala a real. Há um **segundo momento** de pesquisa.

### A ponte da confidencialidade (resolvida)
- **Resposta crua** da pesquisa → **confidencial da Lia**. O professor **nunca vê**.
- **Motivo categorizado** da saída (quando pedagógico) → histórico do aluno; o Fábio lê
  **isso** (não a resposta individual). Aprende os padrões pedagógicos **sem quebrar a
  confidencialidade**.

### Princípio da Etapa 6
A saída tem **dois destinos**: **reversão** (professor, só quando reversível) e
**aprendizado** (confidencial, alimenta o sistema). O professor age só no reversível;
no resto, é notificado da perda.

---

## 11. Camadas transversais (atravessam toda a jornada)

### 11.1 Notificação universal (app + WhatsApp)
Não é só movimentação — é o **canal do Fábio com o professor**. Toda mudança
relevante na carteira chega nos dois canais. Infra: UAZAPI.

### 11.2 Fábio: de assistente a CONSULTOR
Não só registra e organiza — **interpreta o cruzamento de dados** (jornada +
prontuário + sinais) e **aconselha** o professor: manter o aluno engajado e na grade,
quando ligar, o que mandar de lição, como criar comunidade.
**MVP:** alertas. **Evolução:** consultoria plena.

### 11.3 Professor: de executor a GESTOR DE CARTEIRA
O propósito do app é dar ao professor olhar de **gestão + comercial** sobre a própria
carteira. Movimentações → histórico → relatórios → **formação do professor**.

### 11.4 Jornada pedagógica configurável por disciplina (coordenação)
**O ciclo comercial é fixo** (40 aulas). O que é **configurável** são os **pontos de
contato pedagógicos** dentro do ciclo — onboarding do aluno na aula 10, o de bateria
na 20. Hoje `vw_jornada_marcos` tem valores fixos; precisa virar **configurável por
disciplina, pela coordenação**.

### 11.5 Pontos de contato = eventos da jornada
Um **barramento comum** de eventos que várias superfícies consomem. Dois tipos:
- **Por posição** — derivam dos contadores ("aula 20 → reunião com coordenador",
  "ciclo 1→2 → pulseira branca→amarela"). Automáticos, configuráveis.
- **Por habilidade** — não saem de contador ("aprendeu a primeira música"). Nascem do
  **registro do professor**; o Fábio detecta no relatório.

O **LA Teacher é a fonte** dos eventos por habilidade e **consumidor** dos que lhe
cabem. Precisa **nascer emitindo esses eventos estruturados**.

### 11.6 Mapa de fronteira dos agentes (ecossistema AI-first)
Cada agente **só fala com o seu público**; trocam **informação** entre si pelo
barramento, não invadem o canal alheio.
- **Fábio** → o **professor**. (É o LA Teacher.)
- **Lia** → o **sucesso do cliente** (Jéssica, Fabi). Dona da pesquisa de saída.
- **Sol** → o **cliente / cobrança** (renovação; futuro automático).

O Fábio **não avisa farmers/ADM/comercial.** Se um evento precisa escalar, **Lia ou
Sol** pegam do barramento e agem. Fábio cobre o professor e para aí.

### 11.7 Superfícies adjacentes (fora do LA Teacher e do MVP)
- **Dashboard da coordenação** — mapeia a jornada, configura pontos de contato e
  notificações, opera ações da coordenação (pulseira, reunião na aula 20). Consome o
  barramento. **Outro produto, depois.**
- **Ecossistema de agentes pleno** — automações Lia/Sol, troca agente-a-agente. Pós-MVP.

O LA Teacher só garante **emitir os eventos estruturados** para essas superfícies não
precisarem reprocessar tudo lá na frente.

### 11.8 Comunicação instrumentada (professor ↔ aluno/pai)
O professor conversa com aluno/responsável **por dentro do app**, pelo canal oficial da
escola (UAZAPI) — **sem ver o número**. A mensagem do pai entra no app; o professor lê e
responde por lá; pro pai chega como a escola. É o par bidirecional da notificação
universal (11.1): aquela é sistema→professor; esta é professor↔pai/aluno.

**Motivo: fronteira/limite do professor — NÃO retenção de carteira.** A cultura e o código
de conduta da LA blindam a retenção (14 anos, zero casos); esse não é o risco. O risco real
é o **pai mandando mensagem domingo 22h** e o professor sem separação entre vida e trabalho.

**O canal tem horário; o WhatsApp pessoal não.** Fora do horário de atendimento, o sistema
responde **automático** (Fábio: "recebemos sua mensagem, o professor retoma amanhã e responde
por aqui") e a mensagem fica **pendente** no app. O professor entra quando é hora de trabalhar,
lê com calma e responde. **O sistema é o pára-choque, não o professor** — hoje ele é o
pára-choque 24/7; com o canal instrumentado, deixa de ser.

**Substitui o "copiar/colar no WhatsApp pessoal"** das Etapas 3 (devolutiva) e 5 (relatório de
ciclo): essas peças saem pelo canal oficial, **rastreáveis** (alimenta #13 — o pai leu?).
Feature à parte; não depende do professor ter o número. **MVP ou logo depois** (escopo a definir).

### 11.9 Operação do professor — presença, repor, disponibilidade (MVP)
Princípio que corrige a régua: **o professor faz tudo no LA Teacher; não abre o Emusys pra
nada.** Dois apps abertos mata a adoção, e o que se tira agora o professor desaprende. Logo,
estas três entram no **dia 21** — o Emusys vira backend/sync, não uma tela que o professor abre.

- **Presença** (ver 7.A.2) — o professor grava presente/falta no LA Teacher, em lote por voz.
  Dupla fonte com **first-write-wins** (`uq_presenca_aluno_aula` + `ON CONFLICT DO NOTHING`).
  **Status rico:** professor grava `presente`/`falta`; justificativa/reposição são **read-only** do
  Emusys (decisão da gerência+relacionamento). **Ponto do professor = derivado** pela regra do
  intervalo 1ª↔última presença (faltas cercadas contam; pontas não creditam; ambíguo → toque do
  Fábio + default conservador). Infra `aluno_presenca` já existe; falta RPC de escrita em lote,
  ajuste do sync, campos administrativos, e a view do ponto.
- **Aulas a repor** — **read-only** pro professor. As recepcionistas fazem a reposição no
  Emusys; o LA Teacher **exibe**. `GET /aulas` já traz `justificada` (boolean) ✓. A **autorização
  de reposição** ainda não vem na API, mas **DECIDIDO: vem do Emusys** (flag simples) — o Alf
  confirma com o Mateus, mas **não trava**. O schema **deixa previsto** o campo `situacao_reposicao`
  esperando a flag; o sync popula quando ela chegar. Não é gate, é "aguardando flag".
- **Disponibilidade / agenda do professor** — **DECIDIDO e simplificado.** Ela **já existe e é a
  fonte vigente**: `professores_unidades.disponibilidade` (JSON por professor/unidade), já renderizada
  na ficha do professor no LA Report. **Não criar tabela nova, não migrar horários.** A Mila **lê do
  LA Report** (o Emusys não tem escrita de disponibilidade — e a premissa é **sair do Emusys** no
  futuro, então morar aqui é a direção, não gambiarra). **Alvo: ferramenta operacional**, não leitura —
  a tela da coordenação (coordenação + atendimento que fala com professor) precisa cadastrar, editar,
  ver quem está livre quando, cruzar com `aulas_emusys`. Solicitação de mudança pelo professor: tabela
  leve `professor_disponibilidade_solicitacoes` (proposta/status/aprovador); ao aprovar, RPC copia pro
  JSON. **Ajuste crítico (Codex):** a edição atual faz **delete-and-reinsert** de `professores_unidades`
  — trocar por **UPDATE dos campos**, senão cada save pode estourar `emusys_id` e metadados de
  conciliação (mesmo tipo de bug da carteira). Layout: **opção A** (subvisões dentro da aba Agenda).

Infra destas três é construída no LA Report (Codex: migrations + sync + telas da coordenação);
a UI do app é do Claude Code; contrato de banco e validação são desta frente.

---

## 12. Os três artefatos do Prontuário — estado real

| Artefato | Onde mora | Estado | Falta |
|----------|-----------|--------|-------|
| Anamnese | `anamneses` + `anamnese_respostas_perfil` | **Madura** | Plugar no app |
| Dossiê da Mila | `crm_mensagens` + `leads.observacoes_professor` | **Cru** | Materializar (`vw_lead_contexto_professor`) |
| Registro da experimental | — | **Não existe** | Criar em `lead_experimentais` |
| Passagem de bastão | `professor_passagem_bastao` | **Backend pronto** | Fábio + UI |
| Relatório de ciclo | LA Report (capacidade existe) | **Reaproveitável** | Gatilho aula 32 + disparo do professor |

---

## 13. Os 14 sinais do Health Score — quais nascem no LA Teacher

| # | Sinal | LA Teacher? | Ritmo |
|---|-------|-------------|-------|
| 4 | Pratica em casa | **Sim** (dever) | Por aula |
| 2 | Semáforo do professor | **Sim** | Mensal |
| 5 | Evolução na jornada | **Sim** (avaliação) | Mensal |
| 6 | Absenteísmo | Reflete (`aluno_presenca`) | Por aula |
| 9 | Dias desde última aula | Reflete (`aluno_presenca`) | Por aula |
| 14 | Sinal contínuo do Fábio | **Sim** (relatório) | Por aula |
| 10 | Anamnese × Expectativa | Via prontuário | Contínuo |
| 13 | Engajamento do responsável | Toca (devolutiva lida?) | Contínuo |
| 1,3,7,8,11,12 | ADM, NPS, adimplência, projetos, ciclo, cadastro | Outros sistemas | — |

---

## 14. Mapa de fontes de dados (a "despensa")

| Necessidade | Fonte |
|-------------|-------|
| Posição (aula X/40) | `aluno_jornada_matricula_disciplina` / `get_jornada_professor` |
| Marcos / pontos de contato | `vw_jornada_marcos` (a tornar configurável por disciplina) |
| Lead / comercial | `leads` |
| Conversa da Mila | `crm_conversas` + `crm_mensagens` |
| Experimental agendada | `lead_experimentais` |
| Ponte lead → aluno | `leads.aluno_id` ↔ `alunos.lead_origem_id` |
| Anamnese | `anamneses` + `anamnese_respostas_perfil` |
| Presença (oficial) | `aluno_presenca` (`respondido_por=emusys`) |
| Semáforo | `aluno_feedback_professor` + `aluno_feedback_sessoes` |
| Transição de professor (fria) | `aluno_professor_transicoes` |
| Passagem de bastão (quente) | `professor_passagem_bastao` |
| Movimentações / saída (evento) | `movimentacoes_admin` (aviso_previo, nao_renovacao, evasao, trancamento, renovacao) |
| Histórico de saída (motivo, permanência) | `alunos_historico` |
| Pesquisa de saída | LA Report (existe, a automatizar) — confidencial da Lia |
| Risco de evasão | `risco_evasao` |
| Vínculo professor ↔ auth (RLS) | `professores.usuario_id → usuarios.auth_user_id` |

**Regras:** LA Teacher lê do LAHQ, não do Emusys. Presença é read-only. Não usar
`movimentacoes` (legada, vazia). Filtrar por `unidade_id`.

---

## 15. Decisões cravadas

**Modelo:** três planos (posição ✓ / prontuário / health score consumidor).
Prontuário: pendurado no aluno, append, push, Fábio roteia. LA Teacher captura, não
calcula score nem gera material.

**Etapa 1:** vê a partir da experimental agendada; dossiê estruturado; captura
pós-experimental no MVP; registro em `lead_experimentais`.

**Etapa 2:** anamnese é leitura (tablet); Fábio reaproveita insights; handoff A→B.

**Etapa 3:** presença reflete `aluno_presenca`; dever de casa; devolutiva no MVP;
semáforo mensal no MVP; ANTES da aula = resumo do prontuário à vista.

**Etapa 4:** notificação universal (app + WhatsApp) de TODA movimentação; trancado
vai pra inativos; passagem de bastão construída no backend; correção `usuario_id`.

**Etapa 5:** ciclo fixo (40); gatilho aula 32 (preparação) / 36 (cobrança); relatório
de ciclo é peça nova, reaproveita o LA Report, **sai do professor**, entra no MVP;
Fábio = consultor do professor, não escala pras farmers.

**Etapa 6:** aviso prévio aciona o professor (seção + marca no relatório diário + Fábio
consultor), **reversão exclusiva do professor**, filtro de reversibilidade;
não-renovação/evasão = professor notificado da perda, motivo pedagógico vira aprendizado
do Fábio; pesquisa de saída **confidencial da Lia** (professor sem acesso à resposta
crua), motivo pedagógico categorizado alimenta o Fábio.

**Transversais:** Fábio evolui pra consultor; professor como gestor de carteira;
jornada **pedagógica** configurável por disciplina (ciclo é fixo); pontos de contato
= eventos no barramento; **mapa de fronteira dos agentes** (Fábio→professor,
Lia→sucesso, Sol→cliente); dashboard da coordenação é superfície adjacente (fora do MVP);
**comunicação instrumentada** (professor↔pai/aluno pelo canal oficial, sem ver o número) —
motivo é **fronteira/limite do professor**, não retenção; número fora da carteira.

**FONTE ÚNICA (colisão — EXECUTADA E VALIDADA NO BANCO):** a **jornada canônica**
(`aluno_jornada_matricula_disciplina` / `vw_jornada_professor_atual`) é a **única** fonte
de verdade da carteira do professor. A duplicação estava na `vw_fabio_carteira_professor`,
que tinha **lógica própria** (SELECT direto em `alunos.professor_atual_id`, por aluno).
Migration `la_teacher_009_carteira_fonte_unica` (espelho `008-carteira-fonte-unica.sql`).
Recorte executado e validado:
- **`app_minha_carteira` é reescrita** como SELECT **guardado** (via `fn_professor_do_usuario`)
  sobre `vw_jornada_professor_atual`. **Não é wrapper de lógica (puxadinho) — é porta de
  segurança sobre a fonte única.** Necessário porque `get_jornada_professor` **não tem guard**
  (o app não pode chamá-la direto: seria um professor vendo a carteira de outro).
- **NÃO dropar `vw_fabio_carteira_professor`:** a RPC `maria_lareport_professor_carteira`
  (agente Maria) depende dela. Só desplugar o app; aposentar a view é pauta separada do lado
  LAHQ, após checar os consumidores da Maria.
- **`app_minha_agenda_sessao` FICA:** não é duplicação — deriva de `aulas_emusys` +
  `aluno_presenca` (grade + presença da aula), é guardada, não usa `professor_atual_id`.
- **Contato:** `vw_jornada_professor_atual` expõe telefone/whatsapp/responsável. O número
  **não aparece na carteira** → o wrapper **projeta esses campos FORA**. Motivo: a comunicação
  professor↔pai/aluno será **instrumentada pelo app** (11.8), sem o professor ver o número —
  por **fronteira/limite do professor**, não por retenção de carteira. Decisão compatível com
  a refatoração de qualquer forma (sem contato na listagem).
- **Regra:** zero SELECT direto em `alunos` pra montar carteira; zero `professor_atual_id`
  como fonte; guard via `fn_professor_do_usuario` (já existe desde a 001 — **não há "correção
  de RLS" a fazer**).
**Validado no banco (09/07):** `app_minha_carteira` deriva da canônica, guardada, sem contato;
nenhuma RPC `app_*` usa `professor_atual_id` nem a view antiga; a view da Maria intacta (único
consumidor: `maria_lareport_professor_carteira`); `app_minha_agenda` órfã dropada. Falta o
`git push` do front (banco já aplicado).

---

## 16. Pendências e próximos passos

**MAPA FECHADO + infra de operação auditada (Codex, relatório 10/07).** A arquitetura sobreviveu à
auditoria — nenhuma decisão de fundo caiu; só riscos (→ tarefas) e 3 contrapontos novos (roster,
semântica de `ausente`, correção). Antes da Fase 3, **6 decisões (D1–D6) — GATE 0 FECHADO:**
- **D1** (disponibilidade/Mila) → ✅ **Mila continua no Emusys**; LA Report **espelha** (manual agora,
  webhook do professor depois). Fonte de edição = Emusys por ora; tela da coordenação = visualização+operação.
- **D2** (reposição) → ✅ status aprovada/reprovada **fora do MVP** (só exibir a marcada). Codex confirma
  na Fase 1 de onde vem a lista (endpoint ou derivar de `justificada=true`).
- **D3** (administrativo) → ✅ **tabela SEPARADA** (enxuta no MVP: só `justificada` read-only).
- **D4** (`ausente`) → ✅ confirmado: passada sem registro = falta, futuro = nada. **Regra de maturidade
  obrigatória** (sync só materializa falta após janela ~24-48h) + **aula cancelada = 3º estado**.
- **D5** (ponto) → ✅ minutos = soma das durações das aulas entre 1ª e última presença (incl. pontas
  presentes e faltas cercadas); 1 aula presente credita a duração dela (nunca zero); ponta ambígua só
  com confirmação do Fábio.
- **D6** (correção) → ✅ RPC administrativa (coordenação, trilha append-only); professor não edita após enviar.

**Pré-requisito confirmado:** trocar delete-and-reinsert de `professores_unidades` por **UPDATE**
(preservar `emusys_id` + metadados), senão a edição de disponibilidade dessincroniza do Emusys.

**Mini-plano do Codex até 21/07 (6 lotes):** Lote 1 (fundação/segurança: espelhar `fn_professor_do_usuario`,
tokens→vault, criar roster, sync de agenda/roster) → Lote 2 (presença + ponto) → Lote 3 (disponibilidade:
manter JSON vigente, trocar delete-reinsert por UPDATE, solicitações+RLS) → Lote 4 (tela da coordenação,
opção A) → Lote 5 (reposição, **só com fonte**) → Lote 6 (validação + handoff). Presença nos lotes 1–2, com folga.



- **Régua de MVP pelo Emusys** — passar o mapa inteiro contra o app do Emusys que os
  professores já usam, e classificar cada peça: [Emusys já faz → candidato dia 21] /
  [novo mas backend pronto] / [novo, construir] / [pós-MVP]. **Próximo passo.**
- **Refatoração da fonte única (colisão)** — **executada e validada no banco** (09/07). Resta
  só o `git push` do front (2 commits prontos e rebased; banco já aplicado).
- **Conciliação de identidade do aluno** — o prontuário é por **pessoa**, mas há cadastros
  duplicados (ex.: Luiza Pimentel = 2 `aluno_id`, Teclado 265 + Canto 1465). Inofensivo pra
  jornada (por matrícula/disciplina), mas fragmenta o prontuário (anamnese/dossiê/expectativa
  em duas fichas). **Conciliar pessoa↔aluno_id ANTES do prontuário unificado.**
- **Operação do professor no MVP (régua do Emusys) — infra no LA Report:**
  - **Presença:** RPC de escrita em lote (guardada, `presente`/`falta`) + ajustar sync do Emusys
    pra `ON CONFLICT DO NOTHING` (first-write-wins) + **campos administrativos** (justificativa/
    reposição, read-only do Emusys) + **view do ponto do professor** (regra do intervalo, usar
    `aulas_emusys.data_hora_inicio`) + tabela leve pras confirmações de ponta do Fábio.
  - **Riscos técnicos (auditoria Codex) a tratar no build:** apertar RLS de `aluno_presenca` (hoje
    é ALL pra qualquer autenticado — buraco); migração de status compatível (`ausente`→ manter/migrar,
    20 objetos dependem); tirar tokens Emusys hardcoded do sync (→ vault); versionar
    `fn_professor_do_usuario` no repo (existe no banco, não no código).
  - **Aulas a repor:** schema **deixa previsto** `situacao_reposicao` (autorização vem do Emusys
    como flag — confirmar com Mateus, mas não trava) + sync popula quando a flag chegar + RPC read-only.
  - **Disponibilidade:** **fonte é `professores_unidades.disponibilidade` (não criar tabela nova, não
    migrar)** + trocar delete-reinsert por **UPDATE** (preservar `emusys_id`) + tela **operacional** na
    coordenação + `professor_disponibilidade_solicitacoes` (leve, só se o professor propuser mudança) +
    Mila lê do LA Report. Premissa registrada: rumo é sair do Emusys.
- **Comunicação instrumentada (11.8)** — professor↔pai/aluno pelo canal UAZAPI oficial,
  com horário de atendimento + resposta automática do Fábio fora de hora + fila de pendentes.
  Substitui o copiar/colar das Etapas 3 e 5. MVP ou logo depois.
- **Config de jornada pedagógica por disciplina** — build; pré-requisito de marcos.
- **Barramento de eventos da jornada** — o LA Teacher deve nascer emitindo eventos
  (por posição e por habilidade) estruturados.
- **A construir (identificado):** materialização do dossiê da Mila; registro da
  experimental; camada unificadora do prontuário; captura de dever de casa; peça de
  devolutiva; avaliação pedagógica mensal; relatório de ciclo (gatilho aula 32);
  seção de aviso prévio + marca no relatório diário; notificações do Fábio (app + WhatsApp);
  automação da pesquisa de saída (Lia); emissão de eventos da jornada.
- **Passagem de bastão:** conectar Fábio (cutucada + transcrição + resumo) e UI.
- **Fase 2 / evolução:** LA Journey (material via Fábio); automação da renovação (Sol) e
  dos avisos (Lia); Fábio consultor pleno; relatórios de formação do professor; vídeo do
  aluno no relatório de ciclo; dashboard da coordenação.

> Nada vira migração/RPC sem aprovação. Este documento é o modelo; o build vem depois,
> etapa por etapa. Exceção já executada: passagem de bastão (backend). Em andamento:
> refatoração da fonte única (carteira).

---

## 17. Registro de aula (Fábio) — shape do tronco/fatias (decidido 11/07)

**Fatiamento por roster (raiz corrigida):** o Fábio materializa uma **fatia por aluno**
a partir do roster real (`vw_fabio_aulas_contexto`, fallback `vw_fabio_carteira_professor`).
Individual = 1 fatia; turma = N fatias. **Guardrail:** se o roster não resolve ou diverge de
`qtd_alunos`, o Hermes **falha fechado** — nunca cria `tronco null + 0 fatias` (o shape que
gerava sucesso falso na confirmação).

**Defesa em profundidade na confirmação:** `app_confirmar_registro` agora **dá erro explícito**
se for confirmar um tronco de turma e gravar zero (antes retornava `gravadas:0` fingindo
sucesso — conteúdo perdido silenciosamente). Duas camadas: Hermes não gera shape ruim + a
função não deixa passar.

**Decisão de shape:** adotada a **opção (b)** — tronco (aluno_id null) + fatias por roster,
inclusive para aula individual (tronco + 1 fatia). Funciona e está testado (individual
`gravadas:1`, turma `gravadas:2`).

**Melhoria adiada (pós-lançamento):** opção (a) — aula individual gerar tronco **com
`aluno_id`** preenchido (mais direto, sem fatia). Exige alterar `fabio_criar_registro` (hoje
força `aluno_id = null`). **NÃO fazer antes do dia 21** — é elegância de schema, não correção;
mexer na RPC central do pipeline recém-consertado é risco sem prêmio com deadline próximo.

**obs_gerais (corrigido):** o campo era perdido em dobro (não aparecia na tela E não entrava
no texto gravado). Agora é renderizado (editável) e incluído no texto. Regra: a tela renderiza
**todo campo preenchido**, não um subconjunto fixo. **Eixos:** classificação de sistema —
**não exibir** pro professor (fica só no backend).

---

## 18. Contexto do Fábio: roster é a fonte de "quem está na aula" (corrigido 11/07)

**Bug de fluxo real (não artefato de teste):** a `vw_fabio_aulas_contexto` derivava os alunos
de `aluno_presenca` — ou seja, o Fábio só "via" os alunos de uma aula **se já houvesse chamada
lançada**. Isso cria uma **dependência de ordem** indevida: se o professor grava o áudio da aula
**antes** de marcar presença (uso legítimo — grava quente, marca depois), a view devolve 0 alunos,
o roster não resolve, e o Fábio não fatia (o guardrail do Hermes falha fechado — corretamente,
mas esse não deve ser o caminho feliz).

**Princípio:** presença (fato administrativo) e registro pedagógico (Fábio) são **atos
independentes**. A gravação **não depende** da chamada. A fonte de "quem está na aula" é o
**roster** (`aula_alunos_emusys`), não a presença.

**Correção (cirúrgica, no banco):** `vw_fabio_aulas_contexto` reescrita para ler os alunos de
`aula_alunos_emusys` (LEFT JOIN), com `aluno_presenca` como **LEFT JOIN opcional** (só informa o
status quando existe). Validado: aula sem presença devolve o roster (`qualidade: ok`); caso geral
(com presença) intacto — 3819 aulas, status preservado. Nada dependia da view (drop+recreate seguro).

**Nota de nomenclatura (dívida):** a coluna `aula_emusys_id` em `aula_alunos_emusys` e
`aluno_presenca` guarda na verdade o **id LOCAL** (`aulas_emusys.id`), não o `emusys_id`. Nome
enganoso; os joins usam o id local. A view expõe ambos: `aula_local_id` (id) e `aula_emusys_id`
(o emusys_id real). Cuidado ao filtrar.

**Fatiamento validado (tronco + slices):** áudio real de turma (fala cruzada sobre 2 alunos) →
tronco (coletivo, aluno_id null) + 1 fatia por aluno (parent_id → tronco), cada uma no aluno_id
certo, conteúdo separado sem vazamento. Confirmação gravaria `gravadas:2`. **O coração pedagógico
do app funciona de ponta a ponta.**
