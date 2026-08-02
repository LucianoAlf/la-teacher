# Volta às aulas (03/ago) + próximos passos — organização

_2026-08-02 · Alf → Claude Code · organização dos 4 frentes conversados_

## 0. Achados de véspera (verificados no banco hoje, 02/08)

### 0.1 "Gravar o conteúdo já dá presença" — ainda NÃO está provado

| Evidência (banco vivo) | Número |
|---|---|
| Presenças com fonte `fabio_audio` | **0** |
| Registros do Fábio com `campos.presenca` (tronco ou fatia) | **0** |
| Último áudio processado com sucesso | **17/07** (antes do patch) |
| Áudios nos últimos 7 dias | 0 (férias) |

**O que isso significa:** o caminho está **construído e testado em simulação** (migration 009 + patch `ba1ca01` do Alfredo no `_normalizar_shape_com_roster`), mas **nunca rodou com áudio real depois do patch** — o último áudio real é de 17/07 e o patch entrou em 18/07. A guarda `sem_sinal_de_presenca_no_registro` garante um no-op seguro: se o Hermes não mandar `campos.presenca`, **não marca ninguém e não trava a chamada** — mas também **não dá a presença**.

→ **O primeiro áudio do Matheus amanhã é o teste real.** Plano de verificação em §1.

### 0.2 A mensagem de amanhã de manhã NÃO vai sair sozinha

Varri os 48 crons do projeto: **não existe nenhum agendamento de digest matinal do professor**. O que existe é de outro escopo (`alertas-diarios` 11h = projetos; `notificar-primeira-aula-fabi-diario` 11h = primeira aula do aluno novo). O lado do Fábio ficou **preview-first com schedule desligado** — decisão nossa, correta na época, mas significa que **amanhã de manhã ninguém recebe nada automaticamente**.

→ **Ação do Alfredo, hoje/amanhã cedo** (§3).

### 0.3 Fila de áudios: saudável (falso alarme afastado)

12 áudios em `normalizado` = **status final de sucesso**, não travamento. Só 1 item preso em `transcrevendo` desde 17/07 (`80b79f72`, aula 1922178, 22 tentativas) — item órfão, sem impacto no fluxo novo. O cron `fabio-retry-fila` (5 em 5 min) só cobre `pendente`/`erro` dos últimos 3 dias, por isso não o repesca.

---

## 1. Frente A — Véspera: o que precisa estar de pé amanhã

**O que já está pronto e no ar** (nada a fazer): app em produção, chamada do professor funcionando (a promoção conserta a corrida com o Emusys), agenda/carteira/ficha do aluno com a presença semântica nova, chat do Fábio, gravação de áudio.

**Roteiro de validação do 1º áudio real** (assim que o Matheus gravar):
1. `fabio_fila_audios` → o áudio sai de `pendente` e chega em `normalizado`.
2. `fabio_registros_aula` → nasce tronco + fatias, **e o tronco/fatia carrega `campos.presenca`** ← *o ponto que nunca foi provado*.
3. Ao confirmar o registro → `campos.presenca_emitida=true` e `presenca_aplicado=true`.
4. `aluno_presenca` → linha com `respondido_por='fabio_audio'` ← **a prova final**.
5. No app: o selo da agenda vira "chamada feita" e a ficha do aluno mostra verde.

Se parar no passo 2 (sem `campos.presenca`), o diagnóstico é do lado do Hermes (Alfredo) — e o efeito é benigno: professor segue podendo fazer a chamada manual normalmente.

---

## 2. Frente B — Agenda do professor no LA Report (Codex)

**Decisão do Alf:** antes do painel de presença, o LA Report ganha a **agenda do professor** (como no Emusys). É nela que moram os 4 estados: **presença, falta, aula cancelada, falta justificada**.

Isso **encaixa perfeitamente** no que já está desenhado — e não invalida nada:
- A **grade** já existe no banco (`aulas_emusys` + `aula_alunos_emusys`, sincronizada, inclui hoje e futuro). Não precisa construir agendamento.
- Os 4 estados dele são exatamente os estados semânticos (`presente`, `falta_confirmada`, `aula_cancelada`, `aula_justificada`) + o derivado `nao_marcado`.
- A **migration 015** (draft, não aplicada) já entrega as 3 RPCs que essa agenda precisa: `adm_chamada_do_dia` (grade + roster + estado por aluno), `adm_registrar_chamada` (lote), `adm_justificar_falta`.

→ **A agenda do professor no LA Report é a casca; a 015 é o motor.** Continua valendo o gate: review do Alfredo → shape-ack do Codex → OK do Alf → aplico.

---

## 3. Frente C — Fábio: o digest matinal (Alfredo)

O que o Alf quer: **amanhã de manhã, o professor recebe no WhatsApp** os alunos do dia e o que foi ensinado nas últimas aulas.

Peças que **já existem** (não precisa construir do zero):
- MCP `fabio_presence_governance` no Hermes, com as tools de pendência e preview (feito pelo Alfredo, inerte).
- RPC `fabio_presencas_pendentes_professor` (presença pendente por professor).
- `fabio_pendencias_professor` (registro pendente).
- Grupo da coordenação allowlistado (`governanca.agente_grupos`).

O que **falta** (pedido pro Alfredo):
1. **Ligar o schedule matinal** (~7h30–8h, antes da primeira aula) — hoje não há cron nenhum.
2. **Compor o digest do dia**: agenda do professor (aulas + alunos do dia) + o que foi ensinado nas últimas aulas de cada aluno (vem dos registros) + CTA de conteúdo ("grava o áudio que eu já dou a presença").
3. **Começar só com o Matheus** (piloto de 1), validar o texto, depois abrir pros outros professores.

---

## 4. Frente D — Vídeo de apresentação (2–3 min, narrado)

**Objetivo:** mostrar a tela real do app, com narração, pra liberar novos professores.

### A matemática dos créditos (verificada hoje)

O MCP de mídia está conectado: **606 créditos disponíveis, sem refill agendado**. Sora 2 custa **20 créditos/segundo**.

| Cenário | Custo | Cabe? |
|---|---|---|
| Vídeo 2–3 min **todo generativo** (Sora 2) | 2.400–3.600 créditos | ❌ **4–6× o saldo** |
| Vinheta + b-roll (~25–30 s generativos) | ~500–600 créditos | ✅ cabe justo |

### A recomendação técnica (importante)

**Modelo generativo não serve pra mostrar a tela do app** — ele *imagina* uma interface, inventa textos e ícones. Pra um vídeo de treinamento onde o professor precisa reconhecer o botão que vai apertar, isso é fatal.

**A arquitetura certa é híbrida:**

| Camada | Ferramenta | Por quê |
|---|---|---|
| **Corpo do vídeo (a tela real)** | **Remotion** | Renderiza os **componentes React de verdade** do LA Teacher — mesmo design system, mesmos tokens, texto nítido. Determinístico, sem custo de crédito, e **regenera sozinho quando o app mudar**. Não está instalado ainda (React 18 + Vite 6 = compatível). |
| **Vinheta de abertura/fecho + b-roll** | **Higgsfield (MCP)** | Professor guardando o violão, ambiente da escola, textura de marca — 4–8 s cada, cabe no saldo. |
| **Narração PT-BR** | TTS (definir provedor) | Precisa de voz limpa e ritmo controlado; áudio nativo de modelo generativo não serve pra locução longa. |
| **Trilha/efeitos + montagem final** | ffmpeg (já instalado) | Junta tudo, sem custo. |

### Roteiro proposto (~2min40)

1. **0:00–0:15** — Vinheta + promessa: *"Seu registro de aula em 30 segundos."*
2. **0:15–0:50** — **Gravar a aula**: abre a agenda, escolhe a aula, segura pra gravar, fala naturalmente.
3. **0:50–1:25** — **O Fábio organiza**: o áudio vira prontuário por aluno; o professor confere e confirma. *"E a presença sai automática."*
4. **1:25–2:00** — **A ficha do aluno**: histórico, o que foi dado, presença honesta.
5. **2:00–2:25** — **Chamada manual** (quando não gravar) + Meu Ponto.
6. **2:25–2:40** — Fecho: *"Grava o conteúdo. O resto o Fábio faz."*

---

## 5. Ordem sugerida (o que é urgente × o que é importante)

| Prioridade | O quê | Quem |
|---|---|---|
| 🔴 **Hoje/amanhã cedo** | Ligar o digest matinal do Fábio (§3) | **Alfredo** |
| 🔴 **Amanhã** | Validar o 1º áudio real → presença (§1) | Eu (verifico no banco) |
| 🟡 Esta semana | Agenda do professor + 015 (review → ack → aplicar) | Alfredo/Codex/eu |
| 🟢 Em paralelo | Vídeo: instalar Remotion, montar o corpo, gerar assets | Eu |

## 6. Decisões que dependem do Alf

1. **Digest matinal:** horário (7h30? 8h?) e piloto só com o Matheus ou já abre pros outros?
2. **Vídeo:** aprovar o roteiro do §4 e o caminho híbrido (Remotion + Higgsfield)?
3. **Narração:** voz sintética (qual provedor?) ou você grava a locução?
4. **Créditos:** 606 sem refill — usar tudo em vinheta/b-roll agora, ou economizar?
