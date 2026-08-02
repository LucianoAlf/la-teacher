# Roteiro — vídeo de onboarding do professor (LA Teacher)

_02/08/2026 · 9:16 (1080×1920) · 30fps · alvo 4–5 min · **aguardando aprovação do Alf antes de renderizar**_

## Regras da casa (herdadas do estúdio do TOM + decisões do Alf)

1. **Sem legenda na tela.** A voz conduz, a tela mostra.
2. **O áudio dita a duração** de cada cena (+0,8s de respiro). Nada de tempo chutado.
3. **Nada de pular etapa.** O dedo percorre o caminho exato que o professor vai fazer — se pular, ele não reproduz.
4. **Telas montadas com os componentes reais**, medidas auditadas do código (não print, não "parecido").
5. **Som em cada toque**: `ui-tap` no dedo, `pop-in` no que materializa, `swoosh` na transição, `chime` na conquista.
6. **Trilha** do estúdio (`tom-theme.mp3`) em volume 0.09, com fade.
7. **Os dois Fábios**: o **personagem colorido** (`/brand/fabio-avatar.svg`) no login, header e chat; o **robozinho teal** (`FabioIcon`) no botão central e no "digitando". Nunca emoji.
8. **Dados reais** do Matheus (prof 25) — agenda de 03/08 e conteúdo vindo do banco.

---

## Cena 1 · Abertura da marca — ~5s

**Tela:** fundo `#05080A`, halo teal radial. O **Fábio colorido** entra com `spring` (escala 0.6→1) e ganha o glow rosa (`drop-shadow 24px rgb(233 20 81/.28)`) — igual ao login. Abaixo, "**LA** Teacher" em Prompt 900/58px ("LA" em `#E91451`, "Teacher" em `#F5F5F5`) e o subtítulo teal.

**Dedo:** —
**Som:** `intro-whoosh` (0.5)
**Narração:** *"E aí, professor! Aqui é o Fábio. Bora afinar essa parada do registro de aula?"*

---

## Cena 2 · Login — ~14s

**Tela:** réplica de `Login.tsx` — moldura 430px, pontinhos rosa nos 60% do topo, marca d'água "LA" a −6°, Fábio 120px com glow, título Prompt 900/32px, labels `E-MAIL`/`SENHA` (11px, uppercase, tracking .5px), inputs raio 12px sobre `#1A2421`.

**Dedo (passo a passo):**
1. Toca no campo **E-mail** → anel de foco teal duplo + `ui-tap`
2. Digita `matheus.felipe@lamusic.com.br` — caractere a caractere, com `key-tick` alternado a cada ~2 letras
3. Toca no campo **Senha** → foco muda
4. Digita 8 bolinhas (`••••••••`)
5. Toca em **Entrar** → botão encolhe pra 97%, vira spinner + "Entrando…"

**Som:** `ui-tap` nos 3 toques · `key-tick-a/b` na digitação · `swoosh` na transição
**Narração:** *"Primeiro acesso é rapidinho: teu e-mail da LA e a senha que a coordenação te passou. Só isso."*

---

## Cena 3 · Home — ~16s

**Tela:** `AppHeader` (Fábio colorido 44px + "**E aí, Matheus! 👋**" 17px extrabold + "Segunda, 3 de agosto" 12.5px) · botão de tema · avatar do professor. Abaixo: **FabioCard** ("Briefing do Fábio", gradiente 150° teal, robozinho teal na bolota de 30px). Depois o card **HOJE** com as 4 aulas. Rodapé: TabBar 5 colunas + **bolota teal de 64px com o robozinho** + FAB do microfone.

**Dedo:** desce a tela devagar (scroll suave), pousa sobre o card do Fábio.
**Som:** `pop-in` na entrada dos cards (stagger 4 frames)
**Narração:** *"Essa é tua casa. Eu te recebo com o resumo do dia, tuas aulas e o que ficou pendente."*

---

## Cena 4 · Agenda — ~14s

**Tela:** `SemanaStrip` (os 7 dias, hoje destacado em teal) · `DateNav` ("Segunda, 3 de agosto de 2026 / HOJE") · as 4 aulas reais: **11:00 Canto — Valentina · Palavra Cantada**, **15:00 Canto — Amanda**, **17:00 Musicalização — Gustavo e Maria Isabel**, **18:00 Musicalização — Arthur · Balão Mágico**.

**Dedo:** toca na aba **Agenda** da TabBar → desliza a semana → toca no card das **11:00**.
**Som:** `ui-tap` (2×) · `swoosh` no deslize
**Narração:** *"Tua agenda do dia. Aluno, horário, sala — tudo no lugar quando você chega."*

---

## Cena 5 · Abrir a aula e gravar — ~22s

**Tela A (2s):** toca no **mic da SessaoRow** (32px, teal-soft) → tela **`Registrar aula`** com o contexto (quadrado 38px teal + `Canto · turma de 4` + `Canto · 11h`).

**Tela B (repouso):** mic teal **88px** ao centro, acima o texto *"Fala pra mim como foi a aula 🎧 — pode ser natural, do seu jeito. Eu organizo."*, abaixo `TOQUE PRA COMEÇAR · MÁX. 5 MIN` (11px uppercase).

**Tela C (gravando):** as **18 barras `animate-wave`** ondulando (altura 10→56px, delays `(i%5)*0.15s`), **timer mono 38px** correndo `0:01… 0:38`, e o **stop vermelho 74px**.

**Dedo:** toca no mic 88px → *"Pedindo acesso ao microfone…"* → grava → toca no stop.
**Som:** `ui-tap` nos dois toques
**Narração:** *"Acabou a aula? Toca aqui e fala, do teu jeito. É tipo contar pro colega como foi. Trinta segundos e tá feito."*

---

## Cena 6 · Ouvir antes de mandar — ~10s

**Tela:** fone em círculo teal 56px, **`Gravado — 0:38`**, o **AudioPlayer** (32 barras; as tocadas acendem em teal da esquerda pra direita, tempo mono `0:12 / 0:38`), e os botões `Enviar pro Fábio` / `Re-gravar`.

**Dedo:** toca no **play** (barras acendem) → toca em **Enviar pro Fábio** → `Subindo seu áudio…` com a nuvem quicando.
**Som:** `ui-tap` (2×) · `swoosh` no envio
**Narração:** *"Quer conferir antes? Escuta aqui. Tá bom? Manda pra mim."*

---

## Cena 7 · O Fábio trabalhando — ~12s

**Tela:** **Fábio colorido 112px flutuando** (bob 2.2s) + *"O Fábio está montando seu relatório… 🎼"* + a trilha de 3 passos acendendo em sequência: **Na fila do Fábio** → **Transcrevendo seu áudio** → **Organizando por aluno — tronco + fatias**. Cada marcador (26px) troca o spinner teal por um **✓ verde**.

**Dedo:** — (a tela avança sozinha, como no app)
**Som:** `pop-in` a cada passo que fecha
**Narração:** *"Aí eu escuto, entendo e separo aluno por aluno. Leva menos de um minuto — e você pode sair da tela, não perde nada."*

---

## Cena 8 · Conferir e confirmar — ~24s

**Tela:** o selo teal do Fábio no topo (*"Eu nunca invento: campo vazio é convite ✋"*), o bloco **`O QUE A TURMA TRABALHOU`** (tronco) com Atividades/Objetivo/Observações e o **Dever de casa em âmbar** com a casinha, e abaixo as **fatias por aluno** (accordion — presente já nasce aberto, avatar 34px).

**Dedo:** rola devagar → toca num campo com **cutucada em itálico** → o campo ganha o **halo teal duplo** e o texto é digitado → toca fora (Toast `Campo atualizado ✓`) → toca em **`Confirmar e gravar`** (vira `⟳ Gravando…`).
**Som:** `ui-tap` · `key-tick` na digitação · `pop-in` no toast
**Narração:** *"Antes de ir pro diário, você confere. Se faltou alguma coisa, é só tocar e completar. Nada entra sem o teu OK — eu nunca invento."*

---

## Cena 9 · A comemoração — ~10s

**Tela:** **16 confetes caindo** (2.6s, teal/laranja/coral/amarelo/azul) + o **check verde 92px** com o pop elástico + **`Registro gravado! 🎉`** + os badges (`1 tronco`, `4 fatias`, `1 dever de casa`).

**Som:** `success-chime` (0.5)
**Narração:** *"Pronto! Cada aluno recebeu a aula no diário dele."*

---

## Cena 10 · Presença automática — ~9s

**Tela:** volta pra agenda/ficha e a tirinha de presença acende: o selo **`Presença lançada automaticamente`** e as bolinhas ficando verdes.

**Som:** `pop-in` nas bolinhas (stagger rápido)
**Narração:** *"E a presença? Já lancei. Você gravou o conteúdo, o resto é comigo."*

---

## Cena 11 · A carteira — ~12s

**Tela:** `Alunos.tsx` — busca ("Buscar aluno pelo nome…"), chips de unidade, cards por curso com título em CAIXA ALTA + ícone de capelo teal, e as linhas de aluno (avatar-inicial teal 36px, nome, "Terça · 15h · Aula 20/40", chevron).

**Dedo:** toca em **Alunos** na TabBar → rola a lista → toca na **Valentina**.
**Som:** `ui-tap` (2×)
**Narração:** *"Aqui é tua carteira inteira, separada por curso e unidade."*

---

## Cena 12 · A ficha do aluno — ~20s

**Tela:** foto/inicial 84px, nome, chips ("9 anos · Kids", unidade, "2 anos e 3 meses de casa"), card de gravar, **Jornada** com a barra de progresso animando, **Presença** com a tirinha honesta (verde/vermelho/âmbar/cinza) + "2 faltas confirmadas · 3 não conferidas", e o **Histórico pedagógico** com o selo "ÚLTIMA AULA".

**Dedo:** rola devagar por cada bloco.
**Som:** `pop-in` nas bolinhas da tirinha (stagger rápido)
**Narração:** *"E a ficha de cada aluno: a jornada, a presença de verdade e tudo que já foi trabalhado — inclusive o que ficou de professores anteriores."*

---

## Cena 13 · O chat do Fábio — ~16s

**Tela:** `ChatFabio` — header com o Fábio colorido 40px e "seu assistente · também no WhatsApp". Bolhas: a do professor à direita (teal translúcido), a do Fábio à esquerda. O indicador "**Fábio está digitando**" com o robozinho teal 18px e os 3 pontinhos pulsando defasados.

**Dedo:** toca na **bolota teal central** → digita "Como foi a aula do Arthur?" → toca em enviar → aparece o "digitando" → a resposta do Fábio entra sozinha.
**Som:** `ui-tap` · `key-tick` na digitação · `msg-pop` quando a bolha do Fábio chega
**Narração:** *"Precisa de alguma coisa? Só me chamar. Eu tô aqui dentro do app…"*

---

## Cena 14 · O Fábio no WhatsApp — ~14s

**Tela:** moldura de WhatsApp (usar `WhatsAppChat` do estúdio do TOM, adaptado) com o **briefing matinal real** chegando: "Bom dia, Matheus! 🎵 Hoje você tem 4 aulas com 5 alunos…"

**Dedo:** —
**Som:** `msg-pop` na chegada da mensagem
**Narração:** *"…e no teu WhatsApp também. Toda manhã eu te mando a agenda do dia, com o que rolou na última aula de cada aluno."*

---

## Cena 15 · Fecho — ~7s

**Tela:** Fábio colorido grande, e o texto: "**Grava o conteúdo.** / **O resto é comigo.**"

**Som:** `swoosh` + a trilha subindo no final
**Narração:** *"É isso aí! Manda o áudio que eu cuido da papelada. Tamo junto!"*

---

## Total estimado

~171s de narração + respiros ≈ **3min10 a 3min40**. Cabe folgado no limite de 5 min, e sobra espaço se você quiser que eu abra mais alguma tela (Meu Ponto, Perfil, Turma).

## O que falta decidir (rápido)

1. **Onboarding pré-login** (as 3 telas do Fábio se apresentando, com a demo que se reorganiza): entra no vídeo ou pula direto pro app? *Minha sugestão: pular — o professor vê isso sozinho no primeiro acesso, e são +25s.*
2. **Meu Ponto e Perfil**: entram? *Sugestão: não neste vídeo — viram um segundo vídeo curto.*
3. Alguma tela que **você quer destacar** que eu não listei?
