# 🎼 LA TEACHER — PRD & Handoff para o Alfredo
### Documento de contexto completo · 07/07/2026
### De: Claude (arquitetura de dados/banco do LA Teacher) · Para: Alfredo (OpenClaw · VPS, GitHub, agentes)

> Alfredo, este documento te apresenta o projeto LA Teacher por inteiro — o que é, como estamos trabalhando, onde chegamos, e exatamente o que preciso de você pra fechar o círculo. Você já tem o Dossiê Central e a Skill do Emusys; este PRD amarra tudo e foca no que é seu.

---

## 1 · O QUE É O LA TEACHER

Um app (PWA) para os ~46 professores da LA Music **registrarem aulas por voz**. O professor grava um áudio ao fim da aula, e o agente pedagógico **Fábio** transforma essa fala em relatório estruturado, gravado na aula de cada aluno no sistema.

- **Problema que resolve:** hoje só **45,9%** das aulas têm relatório. Registrar na mão é chato, então os professores não fazem. Meta: **>90%** de aulas com relatório em ≤24h.
- **Meta de lançamento:** **21/07/2026**, com o Matheus + professores selecionados.
- **A tese:** "Os humanos cuidam de gente; os agentes cuidam do operacional difícil de operar." O professor fala do jeito natural dele; o Fábio organiza.

---

## 2 · A METODOLOGIA DE TRABALHO (como estamos construindo)

Este é um projeto **agent-first**, orquestrado pelo Alf (CEO), com frentes paralelas que não se travam. É o mesmo modelo que o outro chat usou pra construir a Maria (Financeiro) — você já está acostumado com esse jeito.

| Frente | Quem | O que faz |
|---|---|---|
| **Banco / Arquitetura de dados** | **Claude** (este) | Migrações, RPCs, RLS, contratos de dados. Executo direto no Supabase via MCP e verifico ao vivo. |
| **App (frontend)** | **Claude Code** (guiado pelo Alf) | Constrói o PWA (React/TS/Vite). Trabalha no repo `la-teacher`. |
| **VPS / Agentes / Infra** | **VOCÊ, Alfredo** | Acessa a VPS, configura o Hermes/Fábio, mexe no `fabio-backup`, expõe portas. |
| **Sync Emusys↔banco** | **Hugo** (sessão própria) | Edge functions de sync, webhooks, crons. Já entregou a grade das 3 unidades. |
| **Pedagógico** | **Quintela** | Define o formato canônico de relatório (a Tese). |

**Regra de ouro do Alf:** quando ele questiona um design, explica-se o racional e ele decide — nunca alterar sem aprovação. Passos incrementais, um de cada vez, sempre dizendo quem faz o quê.

**Divisão clara entre mim e você, Alfredo:** eu cuido do **banco** (não tenho acesso à VPS). Você cuida da **VPS e dos agentes** (backup no `fabio-backup`, análise das skills, config do Fábio pra ele funcionar). Onde eu paro, você começa. Este handoff é exatamente essa fronteira.

---

## 3 · A ARQUITETURA DO FÁBIO (a decisão central)

**O Fábio NÃO tem uma IA nova.** Ele é o mesmo Fábio que já roda no Hermes (na VPS), com a assinatura GPT-5.5 via Codex, a alma dele, e STT nativo. O app só bate nele por uma porta HTTP nova. **"Uma alma, dois canais": WhatsApp e app no mesmo cérebro.**

### O fluxo completo (assíncrono via banco — sem timeout)
```
1. App: professor grava áudio → sobe pro Supabase Storage (bucket fabio-audios)
        → chama a RPC app_enfileirar_audio → áudio entra na fila
2. Edge Function "CARTEIRO" (a ÚLTIMA peça a escrever): faz POST assinado (HMAC-SHA256)
        → http://<vps-lahq>:8644/webhooks/registro-aula
3. FÁBIO (no Hermes): baixa o áudio → transcreve (STT nativo) → normaliza (alma:
        separa turma em conteúdo comum vs. nominal por aluno) →
        GRAVA o resultado chamando a RPC fabio_criar_registro (que já criei e testei)
4. App: ouve o banco via Realtime → mostra a tela de Confirmação →
        professor confere/ajusta → confirma → grava por aluno no diário (Emusys)
```

**Por que assíncrono:** se a Edge esperasse a resposta do Fábio, daria timeout (transcrever + normalizar leva segundos). No modelo assíncrono, o Fábio grava no banco quando termina, e o app percebe via Realtime. Robusto.

---

## 4 · ONDE ESTAMOS (estado real, verificado ao vivo hoje)

### 🟢 PRONTO
- **Banco (fundação + motor):** migrações 001→007 aplicadas e verificadas. 11 RPCs no ar (ver seção 6). A porta que o Fábio usa pra gravar (`fabio_criar_registro`) está pronta e testada.
- **Sync (Hugo):** grade futura das **3 unidades** (6.568 aulas futuras no total) + cron diário ligado.
- **App — Captura de áudio (P5):** professor grava → sobe pro Storage → enfileira. Offline-first (IndexedDB). Provado ponta a ponta.
- **App — Tela de Confirmação (P7):** a tela-estrela. **A PRIMEIRA AULA DA HISTÓRIA FOI GRAVADA POR VOZ HOJE** — turma de canto, 3 alunos, cada um recebeu comum+individual na sua aula. A regra de separação de turma funcionando em produção.

### ⚪ O QUE FALTA (e onde VOCÊ entra)
- **P6 — o Fábio real via Hermes** ← **ESTE É O SEU BLOCO.** Hoje testamos com um registro que eu inseri no banco. Falta o Fábio criar esses registros a partir de áudio real. Isso depende da config do webhook na VPS (você).
- **A Edge Function carteiro** — a última peça de código (POST assinado pro Hermes). Escrevo depois que você me der o endereço da VPS + confirmar a rota.
- **P8/P9 (polimento):** teste do aluno ausente, loop completo da correção por voz. O Claude Code faz, não depende de você.

---

## 5 · O QUE PRECISO DE VOCÊ, ALFREDO (o pedido concreto)

Você tem acesso à VPS onde o Fábio roda. Preciso que você configure o Fábio pra receber os áudios do app. São quatro coisas:

### 5.1 · Confirmar/atualizar a alma do Fábio para a v1.1
A alma de normalização evoluiu pra **v1.1** — ganhou a regra explícita de **separar turma** (conteúdo comum vs. conteúdo nominal por aluno), com o exemplo canônico da aula de canto. 
- **Ação:** verifique qual versão da alma está ativa no Fábio hoje (no `fabio-backup` e na VPS). Se for anterior à v1.1, atualize. O arquivo v1.1 está sendo entregue junto (`fabio-alma-normalizacao-v1-1.md`) — ou o Alf te passa. **Faça backup da versão atual antes de trocar.**
- **Por que importa:** se o Fábio usar a alma antiga, ele separa turma errado (pode atribuir a um aluno o que era de outro). A v1.1 blinda isso.

### 5.2 · Habilitar o webhook adapter do Hermes
- Ativar o webhook adapter (via `hermes gateway setup` ou env `WEBHOOK_ENABLED=true` — você conhece a config do Fábio melhor que eu).
- Porta padrão **8644** (ou a que você preferir — me diga qual).
- Definir um `WEBHOOK_SECRET` forte (para HMAC).

### 5.3 · Criar a rota dedicada `registro-aula`
- `hermes webhook subscribe registro-aula` (hot-reload, sem reiniciar o gateway).
- A rota recebe o áudio, aciona o Fábio com a alma de normalização, e ao final ele grava via `fabio_criar_registro` (detalhes na seção 6).
- **Segurança (crítico — o Fábio tem escrita no banco):**
  - HMAC-SHA256 obrigatório (recusa POST sem assinatura válida).
  - **Toolset MÍNIMO nessa rota:** só transcrever + normalizar + gravar no Supabase. Nada de terminal ou ferramentas amplas expostas nessa rota específica.
  - Rate limiting.

### 5.4 · Expor a porta 8644
- Abrir no firewall da VPS pra a Edge Function do Supabase alcançar (ou túnel, se preferir — me diga o que for mais seguro no seu setup).
- **Configurar a service_role_key do Supabase** no Fábio (é como ele autentica pra gravar no banco — ver 6).

### O que me devolver
1. O **endereço (IP/domínio) da VPS + a porta**.
2. Confirmação de que a rota `registro-aula` está **ativa e exigindo HMAC**.
3. Confirmação de que a alma ativa é a **v1.1**.

Com isso, escrevo a Edge Function carteiro e fechamos o círculo.

---

## 6 · CONTRATO TÉCNICO — como o Fábio grava no banco (JÁ PRONTO)

Quando o Fábio terminar de transcrever+normalizar, ele grava o resultado chamando esta RPC (via REST do Supabase). Ela cria o tronco (conteúdo comum) + as fatias (uma por aluno) de uma vez, em `aguardando_confirmacao`.

```
POST https://ouqwbbermlzqqvtqwlul.supabase.co/rest/v1/rpc/fabio_criar_registro
Headers:
  apikey: <service_role_key>
  Authorization: Bearer <service_role_key>
  Content-Type: application/json
```
```json
{
  "p_payload": {
    "audio_id": "<uuid da fila, se veio no payload do app>",
    "aula_id": 202899,
    "professor_id": 25,
    "origem": "app",
    "molde": "C",
    "tronco": {
      "campos": { "objetivo": "...", "atividades": "...", "dever_casa": "..." },
      "texto": "texto do conteúdo COMUM da turma"
    },
    "fatias": [
      { "aula_id": 202899, "aluno_id": 1319,
        "campos": { "aluno_nome": "Davi", "presenca": "presente", "progresso": "...", "proximo_passo": null, "observacao": null },
        "texto": "texto individual do aluno" }
    ]
  }
}
```

**Regras (que são a alma do Fábio):**
- `tronco` = trabalhado com TODA a turma (aluno_id null). `fatias` = um por aluno nomeado; cada fatia traz sua própria `aula_id` (turma = 1 aula por aluno no sistema).
- Aula individual: só o tronco com o aluno, `fatias: []`.
- **Campo não dito = null. O Fábio NUNCA inventa** — o app cutuca o professor pra completar. Aluno citado mas ausente: `presenca: "ausente"`.
- Idempotente por `audio_id` (reprocessar não duplica).
- **Testado ao vivo hoje:** a RPC criou tronco + 2 fatias com sucesso.

### O payload que a Edge carteiro vai MANDAR pro webhook (pra você configurar o template da rota)
```json
{
  "aula_id": 202899,          // PK da aula no banco
  "unidade_id": "<uuid>",
  "professor_id": 25,         // ID INTERNO do professor (professores.id) — NÃO o emusys_id
  "audio_url": "<signed url do áudio no Storage>",
  "registro_id": null         // null = novo; uuid = correção de rascunho
}
```

---

## 7 · COORDENADAS

- **Banco LA Report (Supabase):** `ouqwbbermlzqqvtqwlul`
- **Unidades:** Campo Grande `2ec861f6-023f-4d7b-9927-3960ad8c2a92` · Recreio `95553e96-971b-4590-a6eb-0201d013c14d` · Barra `368d47f5-2d88-4475-bc14-ba084a9a348e`
- **Professor-piloto:** Matheus Felipe Lourenço · professor_id **25** · Recreio (emusys 182) + Campo Grande (emusys 897)
- **Repos:** `LucianoAlf/la-teacher` (app) · `LucianoAlf/fabio-backup` (alma/Hermes) · `LucianoAlf/LAperformanceReport` (LA Report)
- **Hermes:** VPS LAHQ · webhook adapter porta 8644 · roda GPT-5.5 via Codex · STT nativo
- **As 11 RPCs no banco:** app_minha_agenda, app_minha_agenda_mes, app_minha_carteira, app_meus_registros, app_enfileirar_audio, app_confirmar_registro, app_registro_completo, app_registros_pendentes, app_atualizar_fatia, **fabio_criar_registro** (a que você usa), registrar_aula_fabio (a porta única de escrita pedagógica).

---

## 8 · A REGRA DE OURO DO FÁBIO (a alma, resumida)

Numa aula de turma, o professor grava **um áudio só**, misturando:
- **Sem nome** ("trabalhei respiração") → COMUM → tronco → todos os presentes.
- **Com nome** ("com a Maria o exercício X") → NOMINAL → fatia daquele aluno.
- Cada aluno recebe: comum + o individual dele. Na dúvida, trata como comum.
- **Nunca inventa.** Campo não dito = null (o app cutuca). Aluno ausente não recebe conteúdo.

Detalhe completo na Alma v1.1 (`fabio-alma-normalizacao-v1-1.md`).

---

*PRD & Handoff · LA Teacher · LA Music · Sistema Agent-First · 07/07/2026*
*Alfredo, você é a peça que fecha o círculo do lado da VPS. Onde eu paro (banco), você começa (o Fábio ganhando a porta nova). Qualquer dúvida do desenho, é só perguntar.* 🌉🎼

---

## 12 · Atualização operacional — 08/07/2026

> Esta seção atualiza o estado real depois do handoff original. O desenho acima continua válido, mas alguns itens que estavam como pendentes já foram configurados e testados.

### Estado real do bloco Fábio/Hermes

- **Alma v1.1:** ativa no Fábio/Hermes e versionada no `fabio-backup`.
- **`fabio-backup`:** acesso SSH/GitHub funcionando; push validado.
- **`la-teacher` na LAHQ:** clonado em `/home/fabio/la-teacher`, com acesso SSH ao GitHub.
- **Webhook adapter Hermes:** ativo na porta `8644`.
- **Rota:** `/webhooks/registro-aula` ativa.
- **HMAC:** obrigatório e validado; sem assinatura retorna `401`, com assinatura válida retorna `202`.
- **Edge Function carteiro:** deployada em `https://ouqwbbermlzqqvtqwlul.supabase.co/functions/v1/fabio-registro-aula`.
- **HMAC da Edge → Hermes:** `X-Webhook-Signature` com HMAC-SHA256 em hex puro.
- **Vault operacional:** `fabio_edge_url` e `fabio_edge_token` criados.
- **`fn_fabio_chama_edge`:** validada chamando a Edge via `pg_net`; resposta `200 {"status":"enviado_ao_fabio"}`.
- **Toolset mínimo do Fábio:** configurado para buscar contexto, transcrever áudio, chamar `fabio_criar_registro` e atualizar status da fila.

### Guardrails adicionados depois do handoff

- Transcrição vazia **não cria registro**.
- Fila não pode ficar presa em `transcrevendo` após o webhook terminar.
- `normalizado` só é permitido se existir registro real em `fabio_registros_aula` para o `audio_id`.
- Áudios antigos/sintéticos do Matheus transcrevem vazio; devem ficar em `erro` e não servem como prova de qualidade do P6.

### Próximo teste correto

O próximo teste precisa ser ponta a ponta com **áudio novo e audível gravado pelo app**:

1. professor grava áudio real;
2. app sobe para Storage e enfileira;
3. trigger chama `fn_fabio_chama_edge`;
4. Edge assina e chama Hermes/Fábio;
5. Fábio transcreve, normaliza pela Alma v1.1 e chama `fabio_criar_registro`;
6. app mostra a tela de Confirmação via Realtime.

### Regra operacional para o Fábio no repo

- Feature nova: branch `fabio/<escopo-curto>`.
- `main`: só docs/hotfix pequeno aprovado.
- Alfredo audita infra/repo/VPS; Claude valida banco/contrato quando envolver RPC, Edge Function ou Supabase; Alf aprova decisão sensível de produto/fluxo.

