# Arquitetura da Jornada do Aluno — LA Teacher

**Versão:** 1.4
**Data:** 09/07/2026
**Status:** **Mapa completo — 6 etapas fechadas.** Próximo: régua de MVP (Emusys).
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
2. **Presença** — LA Teacher **REFLETE** `aluno_presenca` (`respondido_por=emusys`).
   Alimenta #6 e #9. API do Emusys não grava presença.
3. **Dever de casa** — nasce no LA Teacher; Fábio cutuca. Alimenta #4. Material via
   **LA Journey (fase 2)**.
4. **Devolutiva aos pais** — **entra no MVP**; peça em linguagem de pai. Conecta #13.

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
material estimulante saindo da cobrança perde força. **Botão "enviar como eu".**

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
Lia→sucesso, Sol→cliente); dashboard da coordenação é superfície adjacente (fora do MVP).

**FONTE ÚNICA (colisão — plano fechado, aguardando execução):** a **jornada canônica**
(`aluno_jornada_matricula_disciplina` / `vw_jornada_professor_atual`) é a **única** fonte
de verdade da carteira do professor. A duplicação estava na `vw_fabio_carteira_professor`,
que tinha **lógica própria** (SELECT direto em `alunos.professor_atual_id`, por aluno).
Hoje bate com a canônica (19=19 no prof 25) por coincidência, mas divergiria por (a)
`professor_atual_id` ser espelho que dessincroniza do webhook e (b) grão. Recorte da
refatoração (auditado e validado no banco):
- **`app_minha_carteira` é reescrita** como SELECT **guardado** (via `fn_professor_do_usuario`)
  sobre `vw_jornada_professor_atual`. **Não é wrapper de lógica (puxadinho) — é porta de
  segurança sobre a fonte única.** Necessário porque `get_jornada_professor` **não tem guard**
  (o app não pode chamá-la direto: seria um professor vendo a carteira de outro).
- **NÃO dropar `vw_fabio_carteira_professor`:** a RPC `maria_lareport_professor_carteira`
  (agente Maria) depende dela. Só desplugar o app; aposentar a view é pauta separada do lado
  LAHQ, após checar os consumidores da Maria.
- **`app_minha_agenda_sessao` FICA:** não é duplicação — deriva de `aulas_emusys` +
  `aluno_presenca` (grade + presença da aula), é guardada, não usa `professor_atual_id`.
- **Contato:** `vw_jornada_professor_atual` expõe telefone/whatsapp/responsável. A fundação
  (migração 001) é **zero contato/financeiro no app do professor** → o wrapper **projeta esses
  campos FORA**. Caso de contato (aviso prévio, Etapa 6) é fluxo controlado à parte, depois.
- **Regra:** zero SELECT direto em `alunos` pra montar carteira; zero `professor_atual_id`
  como fonte; guard via `fn_professor_do_usuario` (já existe desde a 001 — **não há "correção
  de RLS" a fazer**).
Execução via Claude Code após OK do Alf; validada no banco por esta frente depois.

---

## 16. Pendências e próximos passos

**MAPA FECHADO.** As 6 etapas estão desenhadas. O que falta é build e priorização.

- **Régua de MVP pelo Emusys** — passar o mapa inteiro contra o app do Emusys que os
  professores já usam, e classificar cada peça: [Emusys já faz → candidato dia 21] /
  [novo mas backend pronto] / [novo, construir] / [pós-MVP]. **Próximo passo.**
- **Refatoração da fonte única (colisão)** — plano fechado; aguardando OK do Alf (decisão de
  contato) → execução Claude Code → validação no banco por esta frente.
- **Conciliação de identidade do aluno** — o prontuário é por **pessoa**, mas há cadastros
  duplicados (ex.: Luiza Pimentel = 2 `aluno_id`, Teclado 265 + Canto 1465). Inofensivo pra
  jornada (por matrícula/disciplina), mas fragmenta o prontuário (anamnese/dossiê/expectativa
  em duas fichas). **Conciliar pessoa↔aluno_id ANTES do prontuário unificado.**
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
