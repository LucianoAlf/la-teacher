# RETOMADA — LA Teacher

> ## 🔬 AUDITORIA — 15/08/2026 · onde o vínculo da experimental REALMENTE mora
>
> O Alf mandou parar de assumir e auditar: *"eles existem, você está buscando
> num lugar errado."* Estava certo.
>
> ### O erro da minha medição anterior
>
> Eu medi cobertura contra `lead_experimental_aulas` (**102 linhas**) — que é a
> tabela de **saída** da conciliação, não a fonte. A fonte é
> **`lead_experimentais`: 928 linhas**. Medi o resultado e chamei de universo.
>
> ### A cadeia real
>
> ```
> leads (9.188) → lead_experimentais (928) → lead_experimental_aulas (102) → aulas_emusys
> ```
>
> ### Por que 6 em 10 não casam
>
> **1. O conciliador casa por CHAVE NATURAL, não por id.** `casado_por =
> 'chave_natural'` em 82 de 104 vínculos — unidade + data + horário + professor.
> Qualquer divergência de horário ou troca de professor quebra o casamento.
>
> **2. Os ids do Emusys guardados não servem.** Medido:
>
> | | |
> |---|---|
> | experimentais com `emusys_aula_id` | 300 |
> | que casam com `aulas_emusys.id` | **1** (0,3%) |
> | com `emusys_agendamento_id` | 50 |
> | que casam | 5 |
>
> Confirma a pendência antiga: **`emusys_aula_id` é id de EVENTO, não da aula.**
>
> **3. A janela do conciliador é `data_experimental between hoje-1 e hoje+7`.**
> Quem passou de ontem **nunca mais é conciliado** — fica órfão para sempre.
>
> ### 🔑 O ELO CERTO JÁ EXISTE E ESTÁ GUARDADO
>
> `GET /v1/aulas` do Emusys devolve, na aula experimental:
>
> ```json
> { "id": 747974, "categoria": "experimental",
>   "alunos": [{ "id_aluno": null, "id_lead": 14560,
>                "nome_aluno": "Arthur Abílio Greco" }] }
> ```
>
> E o espelho **já captura isso**: `aula_alunos_emusys.emusys_lead_id`.
> Do outro lado, `lead_experimentais.emusys_lead_id`. **A junção direta existe e
> ninguém usa.** (`GET /v1/matriculas` fecha o ciclo com `aluno.lead_id` quando
> o lead vira aluno — não há endpoint de LISTAGEM de leads, então `/aulas` é a
> fonte do elo.)
>
> ### A medição que decide (30 dias, 153 experimentais)
>
> | régua | cobertura |
> |---|---|
> | vínculo hoje (chave natural) | 59 = **39%** |
> | a aula traz `emusys_lead_id` | 123 = 80% |
> | **casa por `emusys_lead_id`** | **121 = 79%** |
>
> **Dobra a cobertura.** E as 30 restantes se explicam: 8 são aluno já
> matriculado (não precisam de vínculo de lead) e 23 vêm sem lead e sem aluno —
> essas são o resíduo real a investigar. Zero aula sem linha de roster.
>
> ### Como ajustar (recomendação, NÃO aplicada)
>
> 1. `fn_reconciliar_experimental_aulas` passa a casar **primeiro** por
>    `aula_alunos_emusys.emusys_lead_id = lead_experimentais.emusys_lead_id`,
>    carimbando `casado_por = 'emusys_lead_id'`. Chave natural vira **fallback**,
>    não régua principal.
> 2. **Alargar a janela** (`hoje-1`) ou criar uma varredura de recuperação: hoje
>    o passado é irrecuperável por desenho.
> 3. Não apagar `emusys_aula_id`/`emusys_agendamento_id`, mas **parar de tratar
>    como chave de aula** — documentar que são de outro namespace.
>
> ⚠️ Achado colateral: os **tokens do Emusys estão hardcoded** em
> `supabase/functions/sync-grade-futura-emusys/index.ts` (3 unidades). Merece
> cofre — assunto separado, não mexi.
>
> **PRÓXIMO PASSO (combinado com o Alf): provar o trilho da experimental com
> ÁUDIO REAL, fim a fim.** Só depois disso o ciclo se considera fechado. O
> conserto do casamento por `emusys_lead_id` vem em seguida, com teste e
> mutante como o resto.

> ## 🟢 CHECKPOINT ATIVO — 15/08/2026 fim de tarde · a porta errada, fechada
>
> Assumi o conserto que a sessão paralela diagnosticou (ela parou por decisão
> minha e do Alf: rotear o microfone mandaria professores pra uma tela nunca
> exercitada). Diagnóstico dela trazido pra `main` no `82b00a8`.
>
> ### O defeito, em uma frase
>
> **Duas portas na mesma linha da agenda com réguas diferentes.** Clicar na
> LINHA ramificava certo; clicar no MICROFONE (e no "preencher") caía no trilho
> do ALUNO — onde a experimental não tem aluno, o roster sai vazio e o contrato
> recusa. Cinco áudios de professor morreram assim, de 10/08 a 14/08.
>
> **O contrato estava CERTO.** Ele se nega a inventar um `aluno_id`. Consertar o
> contrato teria sido consertar a coisa errada.
>
> ### Três camadas (commit `0ae4961`)
>
> | # | onde | o quê |
> |---|---|---|
> | 1 | `Agenda.tsx` | a régua virou **uma função** aplicada nas **três** portas — linha, microfone e preencher. O manual tinha o mesmo defeito e ninguém tinha notado |
> | 2 | `fn_enfileirar_audio_core` (`20260815070000`) | rede embaixo do cliente (é PWA, bundle em cache manda errado por dias): recusa com `aula_experimental_usa_porta_propria` em vez de aceitar pra perder depois |
> | 3 | `fabio_registro_aula_tool.py` | para de achatar toda falha num `normalizacao_invalida` mudo; o motivo real viaja em `codigo` |
>
> **A guarda tem DUAS pernas de propósito** — `experimental` **E** sem aluno no
> roster. Medido contra o histórico inteiro da fila: existe experimental cujo
> lead já virou aluno que **funciona**, e guardar só por `categoria` a
> quebraria. Zero falso positivo. Tem mutante provando exatamente isso.
>
> ### Provas
>
> 5/5 mutantes · contrato de catálogo verde · 148/148 unit · typecheck limpo ·
> e a guarda exercitada **contra dado real de produção**: a aula do Isaque
> (`34334742`, experimental com lead) agora **recusa**; a do Valdo (`253631`,
> normal) **segue aceita**.
>
> ### ⚠️ O que NÃO fiz — e por quê
>
> - **Não provei o trilho da experimental fim a fim.** Ele está de pé desde
>   07/08 e `lead_experimental_registros` tem **0 linhas** — nunca processou
>   nada em produção. Fechar a porta errada é seguro sozinho; **abrir a certa
>   com confiança exige um áudio real passando inteiro**. Esse é o próximo passo.
> - **Não reenfileirei os 5 áudios perdidos.** Vários já tiveram os bytes
>   apagados do Storage. Precisa conferir quem sobrou antes de tentar.
> - **Aula NORMAL com roster vazio continua aberta.** São 413 em 30 dias.
>   Existe uma que gera registro assim (pelo fallback da carteira), então NÃO é
>   o mesmo defeito. Investigação separada, de propósito.
> - **Cobertura de vínculo da experimental é baixa:** 59 de 160 em 30 dias
>   (37%). Mesmo com o roteamento certo, 6 em 10 experimentais caem no
>   "ainda não casou com a agenda". Isso é produto, não bug — mas é o teto real
>   do trilho hoje.
>
> **PRÓXIMO PASSO:** provar o trilho da experimental com um áudio real, fim a
> fim, antes de considerar o ciclo fechado.

> ## 🔴 CHECKPOINT ATIVO — 15/08/2026 tarde BRT · o registro por WhatsApp
>
> **Relato do Alf:** o prof. **Valdo** mandou áudio de aula pelo WhatsApp às
> 11:04. O Fábio respondeu *"Áudio recebido, vou processar"* e nunca mais
> falou. Pedido: auditar os logs, achar onde quebrou, consertar na raiz, e
> provar fim a fim.
>
> ### O que a auditoria achou: QUATRO defeitos independentes, em série
>
> O canal WhatsApp→registro **nunca funcionou com professor real**. Dos 6
> áudios `origem='whatsapp'` que já existiram, o único "sucesso" era um
> **fixture E2E que eu mesmo criei** (`e2e-isaque-*`) — o resto morreu.
>
> | # | defeito | onde | migration |
> |---|---|---|---|
> | 1 | `wa_message_id` do UAZAPI é `telefone:hash`; o **dois-pontos** ia cru pro nome do objeto. Upload 200, assinar 200, **baixar 400 InvalidSignature** | `fabio_whatsapp_actions.py` | — (Python) |
> | 2 | `fn_fabio_retry_fila` só via `pendente`/`erro`. Quem morria **em voo** (`transcrevendo`/`transcrito`) ficava órfão pra sempre | banco | `20260815040000` |
> | 3 | a limpeza **apagava o áudio em 98s** sem perguntar se a fila ainda ia usar — tornava o conserto 2 inerte | banco | `20260815050000` |
> | 4 | a edge só aceita `pendente`/`erro`; o retry redespachava no estado morto e ela respondia `{"status":"ignorado"}` | banco | `20260815060000` |
>
> **Não era só o Valdo:** havia **2 áudios do APP** travados desde 13/08 —
> professores 10 (Isaque) e 32 (Akeem) perderam registro e ninguém soube.
>
> ### Provas
>
> - dois-pontos: dois objetos idênticos, um com `:` (400) e outro sem (200)
> - 27/27 unit · **5/5 + 5/5 + 6/6 mutantes** · contrato de catálogo verde nos 3
> - **E2E com o código deployado, bytes reais (588 KB) e o id exato que
>   falhou**: path sem dois-pontos, assinar 200, **baixar 200**, bytes idênticos
>
> ### A lição (vale mais que o conserto)
>
> **Consertar uma camada não conserta a tubulação.** Os defeitos 3 e 4 só
> apareceram porque eu **medi o efeito do conserto anterior em produção** em vez
> de declarar pronto. Se eu tivesse parado no 2 — verde em teste e em mutante —
> teria dito "resolvido" com o professor ainda no silêncio.
>
> ### ⚠️ Impossível recuperar
>
> **O áudio do Valdo foi destruído** pelo defeito 3 às 14:07:19, antes de o
> conserto existir. Ele **precisa regravar** — não há como reprocessar.
>
> ### ✅ RECUPERAÇÃO PROVADA EM PRODUÇÃO (cron real das 14:45:01)
>
> A tubulação consertada ressuscitou órfãos reais sozinha:
>
> | professor | antes | depois |
> |---|---|---|
> | **32 (Akeem)** | `transcrito` morto desde 14/08 | **`normalizado` + 2 registros gravados** ✅ |
> | 10 (Isaque) | `transcrito` morto desde 13/08 | transcreveu, mas **`normalizacao_invalida`** ⚠️ |
> | 36 (Valdo) | `transcrevendo` mudo | **`erro: falha ao gerar signed url`** |
>
> O do Valdo virar **erro** é o resultado certo: o áudio dele não existe mais
> (defeito 3 apagou). O ganho é que o silêncio virou **erro diagnosticável**.
>
> ### 🔎 QUINTO problema — DIAGNOSTICADO 15/08 tarde: não é o contrato, é ROTEAMENTO
>
> **O contrato está certo. O microfone é que abre a porta errada.**
>
> O áudio do Isaque transcreveu bem e `fabio_criar_registro_aula` recusou com
> `normalizacao_invalida`. A pista do "nome divergente" era **falsa**: o tool
> devolve só a string genérica, e foi o **agente que inventou** a explicação e
> gravou no campo `erro` da fila. Medido — a razão real é outra.
>
> **Os três casos são a mesma coisa, e são cinco, não três.** Reproduzido
> chamando `_buscar_roster_aula` no código vivo da VPS:
>
> | audio | prof | aula | categoria | `qtd_contexto` | `qtd_roster` |
> |---|---|---|---|---|---|
> | `3c47cf22` | 10 (Isaque) | 34334742 | experimental | 1 | **0** |
> | `292f9739` | 3 | 29640958 | experimental | 1 | **0** |
> | `be63b8c6` | 46 | 18393249 | experimental | 1 | **0** |
> | `d7a86ca7` | 46 | 18393265 | experimental | — | **0** (49 tentativas) |
> | `88b89551` | 35 | 16157255 | **normal** | — | **0** (46 tentativas) |
>
> Roster **vazio**, não divergente. Em `aula_alunos_emusys` a linha existe com o
> **nome** ("Davi Nakashima") e `aluno_id` **NULL** — porque **lead não é
> aluno**, a mesma fronteira de [[contexto-experimental-antes-da-matricula]].
> `_dedupe_roster` descarta quem não tem id, o fallback na
> `vw_fabio_carteira_professor` também não acha (lead não está na carteira, e o
> curso é "Aula Experimental"), e `fabio_criar_registro_aula:765` levanta
> `roster_invalido` — que o catch-all da linha 796 achata em
> `normalizacao_invalida`. **Recusar é o comportamento certo:** o contrato se
> nega a inventar um `aluno_id`.
>
> ### A raiz: o trilho da experimental existe, está de pé, e nunca recebeu nada
>
> Desde **07/08** a fila tem duas rotas (`vinculo_id` nulo → Hermes/roster de
> alunos; preenchido → `fabio_audio_experimental_worker.py`), construídas
> exatamente porque "a experimental tem lead, não aluno". Medido hoje:
>
> - **139 linhas na `fabio_fila_audios`, ZERO com `vinculo_id`.**
> - `lead_experimental_registros`: **0 linhas** desde que nasceu.
> - `fabio-audio-experimental.timer`: **ativo, rodando a cada 20s.**
>
> O trilho está vivo esperando trabalho que nunca chega. Por quê:
>
> | camada | o que faz |
> |---|---|
> | [`SessaoRow.tsx:40`](src/features/agenda/SessaoRow.tsx:40) | `mostrarGravar` **não** considera `ehExperimental` → o microfone aparece na linha da experimental |
> | [`Agenda.tsx:52`](src/pages/app/Agenda.tsx:52) | `gravarAula` **não** ramifica — enquanto `abrirSessao` (linha 39) ramifica certo e leva pra `/app/experimental/:vinculo_id` |
> | `app_enfileirar_audio` / `fn_enfileirar_audio_core` | **não mencionam `experimental` nem `vinculo`** — aceitam a experimental sem guarda e gravam `vinculo_id = NULL` |
>
> **Clicar na LINHA leva à porta certa; clicar no MICROFONE da mesma linha leva
> à porta errada e o áudio morre.** Dois botões no mesmo lugar, um deles perde o
> trabalho do professor em silêncio.
>
> ### Tamanho da classe (30 dias, medido)
>
> Aulas com roster vazio — qualquer áudio delas seria recusado igual:
> **149 experimentais** (de 177, ou seja **84%**) e **1.193 normais** (780 no
> futuro, **413 já passadas**). Registros de aula experimental que existem em
> `fabio_registros_aula`: **2**, ambos de hoje, e só porque aquela aula tinha
> aluno matriculado.
>
> ### O que consertar (não aplicado ainda)
>
> 1. **Cliente (a raiz):** esconder o microfone na linha da experimental e
>    mandar `gravarAula` seguir a mesma régua que `abrirSessao` já usa —
>    incluindo o caso `vinculo_id == null`, que hoje já tem mensagem própria.
> 2. **Banco (defesa em profundidade):** `fn_enfileirar_audio_core` deve
>    **recusar** aula experimental, pra cliente velho não perder áudio de novo.
> 3. **Diagnosticabilidade:** `fabio_criar_registro_aula` devolver o código real
>    do contrato em vez de achatar tudo em `normalizacao_invalida` — foi esse
>    achatamento, mais a explicação inventada pelo agente, que mandou a
>    investigação pro lado errado por dias.
> 4. **Recuperação:** ver quais dos 5 áudios ainda têm bytes no Storage e
>    reenfileirar pelo trilho do `vinculo_id`.
>
> Evidência bruta em `~/claude-diag-normalizacao/` na VPS.
>
> ### ✅ Login por e-mail — FEITO (4 professores)
>
> Descoberto: `<whatsapp>@la.internal` é **placeholder por desenho** (o próprio
> comentário do `professor-entrar` diz isso), e `signInWithPassword` já estava
> ligado. Trocar pelo e-mail real **não quebra** o WhatsApp+código — é o caminho
> previsto (`fn_pedir_codigo_de_acesso` lê `usuarios.email`).
>
> | professor | id | e-mail |
> |---|---|---|
> | Daiana Pacifico | 3 | daiana@lamusic.com.br |
> | Isaque Mendes | 10 | isaque@lamusic.com.br |
> | Leonardo Castro | 19 | leo@lamusic.com.br |
> | Valdo Delfino | 36 | valdo@lamusic.com.br |
>
> Auth e `usuarios.email` conferidos consistentes nos 4. **Senha não definida
> por mim** — o Alf define pelo "Esqueci minha senha" ou pelo painel.
>
> **PRÓXIMO PASSO:** pedir ao Valdo que **regrave** o áudio — é o único jeito de
> fechar o fim a fim com áudio de professor pelo WhatsApp, já que o original foi
> destruído antes do conserto existir.
>
> Commits: `b2af90b` (4 consertos) + `921d94c` (checkpoint). Árvore limpa.

> ## 🔎 CHECKPOINT ATIVO — 15/08/2026 manhã BRT · três relatos de professor, na raiz
>
> **✅ TELA CONFERIDA NOS DOIS TAMANHOS (15/08, com o Alf logado como Matheus).**
> Registro `fdd74d8b-11e9-40e0-a7e5-0b619fc304e4` — turma Julia + Marina (Canto,
> qui 13/08 16h), **2 fatias** (eu tinha dito 4: a contagem inflou porque o
> `join` com `aluno_presenca` traz o gêmeo — a mesma armadilha de contar linha
> crua). As duas alunas aparecem `presente` com o carimbo **"Lançada no
> Emusys"** e cadeado.
>
> | medido | 1382×918 | 390×844 |
> |---|---|---|
> | carimbos visíveis | 2 | 2 (não truncados) |
> | cadeados | 2 | 2 |
> | botões "Marcar/Desfazer falta" | **0** | **0** |
> | estouro horizontal | não | não |
> | "Confirmar e gravar" sob a TabBar | — | **não** (clicável, 830/844) |
>
> **Limite honesto:** vi o ramo **presente travado**. O ramo **falta travada**
> (o texto "fala com a secretaria") **não foi visto renderizado** — não existe
> hoje registro aberto com falta travada, e fabricar dado em produção pra ver
> pixel não vale. Ele está provado por **teste unitário** (caso da secretaria
> com falta) e pelo **SQL contra o dado real do Valdo** (devolveu `falta` +
> `agenda_secretaria` + `travada=true`).
>
> **Conferido por FOTO, além da medição** (o Alf cobrou, com razão, que eu
> usasse o browser em vez de desistir): o screenshot do Simple Browser voltou a
> funcionar assim que o painel ficou visível — o erro anterior dizia
> literalmente *"the Browser pane is not displayed"* e eu tinha lido como
> impossibilidade do ambiente. Nas duas alunas aparece o badge verde `presente`
> + 🔒 **"Lançada no Emusys"**, e os campos de CONTEÚDO (Progresso, Repertório
> individual, Próximo passo, Observação) seguem **editáveis com o lápis** — que
> é exatamente o desenho: presença travada, conteúdo livre.
>
> ## 🎵 Relato novo (15/08, mesma sessão): repertório fica preso dentro de `atividades`
>
> O Alf trouxe print do WhatsApp de uma professora ("Ele colocou a música no
> campo errado. Já editei") — Jingle Bells apareceu dentro do texto corrido de
> `atividades` em vez de em `repertorio`. Não pediu conserto imediato, pediu
> "ver a arquitetura" — mas medido (não só plausível) o defeito é sistêmico:
> nos últimos 14 dias, **56/120 troncos** ficaram sem `repertorio`; pelo menos
> dois são erro confirmado, não aula sem música — Jingle Bells (já editado
> pelo professor) e um "O Sol" **do mesmo dia, ainda não editado no banco**,
> enquanto a mesma música saiu certa em 3 outras aulas no mesmo dia. Não é
> falha total (a maioria das extrações recentes está correta, com "Música, de
> Artista"), é inconsistência de recall do modelo.
>
> **Causa raiz:** a skill `registro-aula-audio-la-music` já tem a regra
> ("repertório é campo próprio"), mas o checklist de auto-conferência antes de
> devolver o JSON não tinha item cobrando isso — só cobria `objetivo`/`eixos`
> e tronco-vazio-com-fatia-rica.
>
> **Conserto aplicado (v1.4, SHA-256 `6e597f17...`):** item 4 novo no
> checklist + exemplo de regressão embutido no prompt com o caso real de hoje
> (O Sol, aula individual). Editado primeiro no espelho do repo, depois `scp`
> pra VPS com hash conferido dos dois lados (antes e depois — sem deriva).
> Invalidação do `.skills_prompt_snapshot.json` é automática por
> mtime/tamanho (`prompt_builder.py:_load_skills_snapshot`), não precisa
> comando manual.
>
> **PRÓXIMO PASSO — verificação pendente, não fabricada:** este é um prompt de
> LLM, não código determinístico; não existe harness pra ensaiar essa skill
> sem tocar dado real de aula (`falar_com_fabio.py` só cobre o chat
> `chat-fabio-la-music`, rota diferente). Verificação real vem da próxima
> leva de registros de aula com música mencionada solta na fala — reconsultar
> `fabio_registros_aula` daqui a alguns dias, ou assim que o Alf reportar o
> padrão de novo.
>
> Árvore limpa, `main` = `origin/main`, nada pendente de push.
>
> ## ⛔ O ERRO MAIS CARO DESTA SESSÃO: eu inverti uma REGRA DE NEGÓCIO
>
> Achei que era defeito técnico e **mudei em produção sem perguntar**. Não era.
>
> **A regra (Alf, 15/08):** quem dá presença é a **SECRETARIA** — lança no
> Emusys / LA Report — e é a resposta dela que **PREVALECE**. O professor lança
> **CONTEÚDO**. Ele pode dar presença dentro da janela dele, mas **não
> sobrescreve** a secretaria; se discorda, **reporta** e elas corrigem na fonte.
> Ou seja: o `first write wins` entre fontes fortes é **intencional**.
>
> Eu li o relato do Valdo ("um aluno ficou como ausente e não consigo mudar"),
> medi o mecanismo certo (a secretaria tinha respondido antes), e concluí
> **errado**: inventei uma `fn_presenca_precedencia` pondo o professor acima da
> secretaria, apliquei (`7e98652`) e ainda alterei o dado real do aluno.
>
> **Revertido por completo em `02b2fd5` + migration `20260815020000`:** as três
> funções (`fn_registrar_presencas_core`, `app_registrar_presencas_aula`,
> `fabio_registrar_presencas_aula`) voltaram **byte a byte** ao corpo anterior
> (capturado de `pg_get_functiondef` **antes** de eu mexer), a régua inventada
> saiu do catálogo, e o dado do Valdo foi restaurado **exatamente** — aula
> 221905 de volta a `presente`/`falta` com `agenda_secretaria` e os
> `respondido_em` originais. Os gêmeos não foram tocados (conferido nas duas
> pontas). **Prova de que voltou ao estado original: o digest de schema do
> runner voltou a `9d91cd89958a`**, o mesmo de antes da minha mudança.
>
> A `20260815010000` fica no repo (chegou a ser aplicada) **com aviso no topo**;
> o teste e os mutantes dela foram **removidos** porque afirmavam a regra
> errada. O teste novo (`20260815020000`) **trava a regra certa**, pra ninguém
> "consertar" isso de novo lendo só o código.
>
> **O sinal que eu ignorei, e que vale como régua:** a regra estava escrita em
> **três** lugares independentes e **concordando**, e havia migration recente e
> deliberada sobre exatamente isso (`20260813220000`) dizendo *"não há defeito
> vivo"*. **Três fontes concordando + migration recente explicando = desenho,
> não descuido.** Se o conserto muda **quem vence** entre duas fontes humanas,
> ou **o que um papel pode fazer**, isso é decisão do Alf — eu subo a pergunta.
>
> ## ✅ O PROBLEMA REAL DO VALDO ERA OUTRO — e esse foi consertado (95cd68c)
>
> Não era precedência: era **exibição**. Medido, e o Alf estava certo que "já
> tínhamos feito isso" — **em parte**:
>
> | tela | lê a presença que a secretaria lançou? |
> |---|---|
> | Agenda (`app_minha_agenda_sessao`) | ✅ **sim**, desde sempre |
> | Registro (`app_registro_completo`) | ❌ **não** |
> | Ficha manual (`app_abrir_rascunho_manual`) | ❌ **não** (delega pra de cima) |
>
> A tela de registro montava a fatia só com `to_jsonb(r)` — a presença que o
> **Fábio inferiu do áudio** —, sem nunca perguntar o que já tinha sido lançado.
> Daí o *"tô tendo que dar presença de novo"*: ele mexia numa presença que já
> existia, e o que ele mexia **não valia nada** (o banco, corretamente,
> preservava a secretaria).
>
> **Migration `20260815030000` (aplicada):** a RPC passou a devolver por fatia
> `presenca_lancada`, `presenca_fonte` e `presenca_travada`. A tela mostra o
> carimbo ("Lançada pela secretaria" / "Lançada no Emusys"), **esconde**
> *Marcar falta* e *Desfazer falta*, e diz o caminho certo (falar com a
> secretaria). Como `app_abrir_rascunho_manual` **delega**, a ficha manual
> ganhou junto — uma função consertada, duas telas.
>
> **Usei a régua que JÁ existia**, em vez de inventar outra (a lição do erro
> acima, aplicada no mesmo dia): `fn_presenca_fecha_chamada` — fonte humana
> forte **OU** `emusys='presente'`. O `ausente` do Emusys **não** trava, de
> propósito: é a falta fantasma da migração, ambígua.
>
> Provado: teste SQL **contra o dado real do caso** (registro do Valdo, aula
> 221905, presença da secretaria) verde no runner de produção; helper puro
> `lerPresencaLancada` com **6 testes**; **74/74** unit; `tsc` e `build` limpos.
>
> ## ✅ O ÁUDIO DA TURMA ERA ENGOLIDO PELA FICHA MANUAL VAZIA (cb2c39b)
>
> Relato do Matheus: numa turma específica (Canto, Julia + Marina, 16h) o
> "Enviar pro Fábio" **não ia** pra tela de "subindo o áudio" — pulava direto
> pro formulário de conferência, 3ª tentativa seguida.
>
> **Raiz medida:** `app_abrir_rascunho_manual` cria o esqueleto manual (tronco +
> fatias, `campos={}`) **assim que a tela de escrever abre**. A guarda
> `rascunho_existente` de `fn_enfileirar_audio_core` pegava **qualquer** tronco
> em rascunho — inclusive esse esqueleto vazio — e devolvia "vai confirmar"
> **sem criar linha na fila**. O blob subia pro Storage e morria lá. Bastou
> abrir a ficha manual da turma uma vez e abandonar.
>
> Reproduzido antes de tocar em nada: a chamada devolvia
> `{"rascunho_existente": true, registro_id: <o esqueleto>}` e zero fila; depois
> do fix, `{"audio_id": …, "status": "pendente"}`.
>
> **Fix (`20260814230000`):** a guarda passou a exigir `modo_entrada = 'audio'`
> — manual e áudio são trilhas **separadas e coexistentes** (o próprio
> `app_abrir_rascunho_manual` já devolve `audio_aberto_registro_id` em vez de
> bloquear). Dois troncos na mesma aula já conviviam em produção (aulas 205412,
> 232193), então não havia unicidade a violar. **3/3 mutantes**, contrato verde,
> 68/68 unit à época.
>
> **Resíduo limpo:** 5 esqueletos manuais provadamente vazios apagados (tronco +
> 9 fatias, profs 10/25/35). **Poupei 1** que parecia vazio mas tinha
> `campos.audio_complemento_id` — complemento de áudio em voo; apagar teria
> quebrado a ligação. Por isso o critério foi estrito e o delete foi **por id
> explícito**, não por predicado solto.
>
> ## ✅ O CONFERE AÍ PERDIA O TEXTO EM CONEXÃO RUIM (c99c6ea)
>
> Relato do Isaque (que **escreve**, não grava áudio — a ficha manual foi feita
> pra ele): *"os registros de ontem sumiram todos, tava tudo preenchido"*.
>
> **Nada de presença foi apagado** — intacto, zero conflito. A ficha manual
> **funciona** em conexão boa (testado ao vivo, passo a passo, com login de
> professor). **O buraco era resiliência:** o celular dele estava em **modo
> avião** (o aviãozinho aparece no print), o app abre lendo do cache do PWA mas
> **escrever precisa de internet** — e a tela "Confere aí" era a **única** que
> não guardava a edição no aparelho (o Caderno já guardava). O texto ficava só
> na tela e sumia ao sair.
>
> Conserto: a tela de confirmação passou a guardar cada edição no **mesmo cache
> local (IndexedDB)** do Caderno, recuperar o que não sincronizou ao reabrir,
> **reenviar sozinho** no evento `online`, e limpar o cache **só** quando o
> servidor confirma. Provado ao vivo no app de produção: com o save bloqueado, o
> texto foi pro IndexedDB; ao reconectar, sincronizou e o cache limpou.
>
> **Errei duas conclusões antes de chegar aqui**, as duas por não medir no lugar
> certo: *"a ficha nunca salva conteúdo"* (li o RESULTADO como MECANISMO) e
> quase consertei a linha errada (o "clobber" do `res.fatias`) por leitura de
> código. O que destravou foi **reproduzir no app real**.
>
> ## ℹ️ LETÍCIA: trocar o WhatsApp já é possível hoje, sem construir nada
>
> O "Reenviar" do painel de Equipe lê `professores.telefone_whatsapp`. Basta
> editar a professora no **LA Report → Professores → campo WhatsApp** e clicar
> Reenviar aqui. **Conferido:** o `sync-professores-emusys` **não toca** nessa
> coluna — ela só é escrita por edição manual no LA Report, então a troca não é
> sobrescrita no próximo sync. Não faz sentido criar isso no LA Teacher: ele não
> tem tela de admin editando dado de professor, e o autoatendimento
> (`app_confirmar_meu_whatsapp`) não serve pra quem **ainda não entrou**.
>
> ## 🔎 Checkpoint anterior — 13/08/2026 noite BRT · auditoria ao vivo + plano de correção
>
> **PRÓXIMO PASSO: as 97 marcações invisíveis de agosto** (bloco abaixo). É
> handoff pro Kodex/Windsurf, que está mexendo em presença agora — eu **não
> escrevi nada** de propósito. Sprints 0 a 3 fechados.
>
> ## 🚨 A EQUIPE MARCOU E O SISTEMA NÃO VÊ — 97 casos em agosto (13/08 noite)
>
> O Alf avisou que a equipe passou a dar presença em ~100% e pediu pra
> conferir o número. **Medido, e o número não fecha por um motivo concreto.**
>
> **Cobertura de agosto (par aluno×aula, aula operacional, já encerrada):**
> `1.812 pares · 695 com presença forte · **38,4%**`.
> Por unidade: CG 43,4% · Barra 36,4% · Recreio 32,5%.
>
> **Mas a curva virou, e é isso que importa:**
> 05/08 = 23,2% · 08/08 = 31,9% · 11/08 = 38,5% · **12/08 = 71,0%**
> (13/08 marca 53,8% com o dia ainda correndo). A média do mês está sendo
> puxada pra baixo pelos dias ANTERIORES ao motor. O motor funciona.
>
> **A junção com o Emusys está OK — conferido, não suposto:** das 1.227 marcas
> de `agenda_secretaria` em agosto, **zero invisíveis** na
> `vw_aluno_presenca_semantica_v1` (1.070 viram "chamada feita", o resto é
> `aula_justificada`, que é estado legítimo). E **zero conflitos**: não existe
> um único par com marca da secretaria E do Emusys ao mesmo tempo — a
> precedência resolve na escrita.
>
> **O BURACO REAL: 752 das 1.461 marcas fortes de agosto (51%) estão gravadas
> no GÊMEO, não na aula operacional.** Isso por si só não seria problema — o
> trigger espelha. Mas **97 delas não têm espelho**: a equipe marcou, e a
> cobrança, o painel e o Fábio não enxergam. Trabalho feito que some.
>
> **O motor de conserto existe e NÃO resolve.** Simulado em transação
> descartada, `fn_sincronizar_gemeos_presenca` nas 97 âncoras:
> * reporta `gemeos_sincronizados = 0` — **e mexeu em 21**. O contador mente,
>   e é exatamente o passo que deixa a `086` vermelha. Agora tem número.
> * sobram **76 órfãs** depois de rodar. Rodar em produção não limparia.
>
> **Por que eu parei aqui:** backfill de presença é escrita em massa, na mesma
> tabela em que o Kodex está trabalhando neste momento. O Alf pediu
> explicitamente para não conflitar nem sobrescrever o trabalho deles. Medir e
> entregar o diagnóstico vale mais do que consertar por cima.
>
> ## 📊 BATERIA: 15 VERMELHOS → 2 (13/08 noite)
>
> `69 passaram · 3 FALHARAM · 16 superadas · 7 não reaplicáveis` — e o `052`
> dessa lista já foi consertado depois do run (verde + 6/6 mutantes), então o
> saldo real é **2**: `026` e `086`.
>
> **NENHUM dos 13 que fecharam era defeito vivo do que eles testam.** Mas
> chegar a essa frase custou achar **dois defeitos vivos** no caminho (o 42P10
> do comercial e os 12,3s da pendência), e mais dois **defeitos nos próprios
> testes/harness**. A conclusão que eu tirei cedo demais — *"são todos
> expectativa podre"* — estava errada, e o preço de tratá-la como verdade seria
> ter deixado os dois defeitos dormindo.
>
> **O que fechou, por classe:**
> * SUPERADA (o arquivo carrega contrato antigo): `041`→`083` (plano do Emusys
>   deixou de valer como relato), `042`/`044`/`048`→`20260813250000`,
>   `053`→`075` e `075`→`095` (CHECK com 9 e 12 tipos; produção tem 13),
>   `064`→`20260813260000`, `077`→`079` (assinatura de 3 params que a 079
>   dropou).
> * NÃO REAPLICÁVEL: `088` (`cannot drop columns from view`) — agora
>   classificado sozinho.
> * BUG DO TESTE: `080` (lia `v_r` sobrescrito; **sem coração = 30 =
>   referência**, a função sempre acertou) e `20260813220000` (fixture refém do
>   sorteio, quebrava quando a aula tinha gêmea).
> * DÍVIDA REAL DESCOBERTA: `052` — seed sem `on conflict`, escondido **há
>   meses** atrás do classificador frouxo.
>
> ## 🔧 O CLASSIFICADOR DA BATERIA MENTIA (13/08 noite)
>
> Ele decidia "reprovou" × "não serve de harness" com uma regex solta dentro do
> laço. `duplicate` casava com `duplicate key` de DADO — e foi ele que mandou
> um teste MEU pra coluna de dívida em vez da de reprovados.
>
> Virou `scripts/lib-veredito.mjs`, com nome e com teste
> (`scripts/teste-veredito.mjs`, 9 casos com strings reais). **O teste pegou a
> minha primeira correção na primeira rodada:** apertar o termo não bastava,
> porque a mensagem de unique violation termina com `already exists.` no
> DETAIL. Agora classifica por **SQLSTATE**, e **sem código legível o default é
> REPROVAÇÃO** — falha que ninguém sabe classificar tem que aparecer.
>
> No primeiro run já pagou: desenterrou a `052`.
>
> ## ⏭️ OS DOIS QUE SOBRARAM
>
> * **`026`** — fixture procura aluno com `aulas_registradas = 0` na carteira
>   do professor 25 e hoje não existe nenhum. Classe "fixture que procura em
>   vez de construir", a mesma que já mordeu duas vezes hoje. Conserto
>   mecânico.
> * **`086`** — **este guarda uma pergunta de desenho, e por isso eu parei
>   nele.** Os passos de comportamento PASSAM (os gêmeos sincronizam), mas o
>   contador do core devolve `0` e o par é tocado mesmo fora do escopo pedido.
>   Leitura provável: o trabalho migrou para o trigger
>   `trg_sincronizar_gemeos_presenca`, que sincroniza SEMPRE — o que talvez
>   seja mais correto, mas faz o parâmetro de escopo deixar de escopar.
>   **Já estava vermelho antes de eu encostar em qualquer coisa hoje.**
>
> ## ⚡ A PENDÊNCIA DE PRESENÇA: 12,3s → 735ms (13/08 noite)
>
> **Eu tinha dito que os 15 vermelhos eram "uma classe só" de expectativa
> podre. Estava errado — tinha defeito vivo no meio, e mais de um.**
>
> O `064` reclamava de plano e de buffers. Fui medir a view de verdade:
> **12,3 segundos, 3.999.329 buffers — e 97,6% deles num filtro só**,
> `Filter: (id = fn_aula_operacional_id(id))`.
>
> **A causa:** existe um índice desenhado exatamente para essa busca
> (`idx_aulas_emusys_slot_operacional`, 3 MB) e ele **não podia ser usado** —
> quatro das cinco comparações eram `is not distinct from`, que **não é
> indexável**. Não é um `=` mais cuidadoso: é outro operador, e o btree não
> casa com ele. O índice certo existia e estava inalcançável.
>
> **O conserto** (`20260813260000`, aplicada e registrada) dá duas portas com a
> MESMA semântica: campos preenchidos → `=` puro e o índice entra; algum nulo →
> o caminho null-safe de sempre, byte por byte. Nenhuma linha muda de resposta.
> **Medido depois: 735ms e 252.710 buffers — 16,7× mais rápido.**
>
> Isso é a fonte única da cobrança da noite, da manhã e do escalonamento.
>
> **O teste é de EQUIVALÊNCIA, não de opinião:** reconstrói a função antiga em
> `pg_temp` e compara linha a linha num lote real. **5/5 mutantes** — e dois
> deles só morreram depois de eu consertar o próprio teste:
> * a amostra de linhas órfãs era `limit 1000` sobre um `OR`, e pegava só o
>   nulo abundante (9.089 sem professor) — as **17** sem curso nunca entravam;
> * mesmo estratificada, ainda faltava: as 17 sem curso estão **todas** também
>   sem professor, então a guarda do curso é inalcançável com o dado de hoje.
>   Só morreu com fixture própria, criada e desfeita dentro da transação.
>   **Passo que nunca alcança o caso que vigia é decoração.**
>
> **4 migrations marcadas `SUPERADA POR`:** `042`, `044`, `048` (recriam o
> `ON CONFLICT` de dois predicados → replayar reintroduz o 42P10) e `064`
> (afirma um formato de plano que a view não tem mais; o orçamento de buffers
> que ela inaugurou agora é vigiado pelo teste da `20260813260000`).
>
> **`038` e `043` ficaram verdes sozinhos** — eram sintoma do 42P10.
>
> ## 🚨 DEFEITO VIVO ACHADO E CONSERTADO — o aviso ao comercial (13/08 noite)
>
> A bateria completa deu **60 passaram · 15 FALHARAM**. Fui conferir três
> reprovados achando que eram testes podres. **Um era defeito vivo.**
>
> `fabio_claim_aviso_comercial` e `fabio_claim_aviso_falta_experimental`
> carregavam um `ON CONFLICT` que **não infere mais o índice**: o
> `uq_fabio_notif_por_referencia` ganhou uma terceira condição
> (`tipo <> 'registro_recibo'`, quando o recibo virou índice próprio) e as duas
> funções ficaram com duas. Dois predicados não implicam três → **42P10 no
> PLANEJAMENTO**, antes de olhar uma linha.
>
> **Provado contra a PRODUÇÃO com `EXPLAIN`**, não contra o texto do repo — a
> distinção que já me fez errar esta semana. `fabio_claim_notificacao_por_
> referencia` **já estava certa** (por isso a devolutiva funciona: 39
> entregues, a última hoje 20:20). É a MESMA falha do incidente de 12/08,
> consertada num lugar e não nos outros.
>
> **Custo hoje: zero — e é esse o problema.** A fila está vazia
> (`na_fila: 0`, medido no worker da VPS), então nunca disparou. Esperava a
> próxima experimental registrada para o comercial não ficar sabendo, sem erro
> na tela de ninguém: quem morre é um worker num timer de 3 minutos.
>
> Migration `20260813250000` aplicada e registrada (RED nomeou as duas funções
> → GREEN → **4/4 mutantes**). Ela **lê a definição viva e troca só a
> cláusula**, em vez de eu transcrever ~150 linhas do bloco family-safe da
> devolutiva à mão — e aborta se a proporção âncora × `on conflict` não for a
> medida (2 para 2 em cada). O teste prova PLANEJANDO, e tem passo garantindo
> que a hierarquia family-safe sobreviveu ao patch.
>
> **Sobraram 13 vermelhos, e eles são outra classe:** expectativa cravada
> contra dado vivo (`esperado 3, obtido 4`) e fixture que não acha mais o caso
> (`aluno sem registro + aula do prof 25` → `faltou`). Bateria que fica
> vermelha pelo calendário ensina todo mundo a ignorar vermelho — é isso que
> vale atacar como classe, não um a um.
>
> ## ✅ A BANDA VEM SEPARADA — NO AR (13/08 noite)
>
> Decisão do Alf, corrigindo a minha proposta de somar tudo:
> *"tem que vir separado: bandas, qualquer outra coisa tem que vir numa lista
> separada."* Somar escondia, excluir mentia.
>
> Migration `20260813240000_a_banda_vem_separada` aplicada e registrada
> (RED → GREEN → **6/6 mutantes**). `fn_carteira_fatiada` é a régua única; a
> RPC do agente e o `fabio_contexto_professor` **perguntam pra ela** em vez de
> repetir critério — a lição do F-C, aplicada no mesmo dia.
>
> **A régua não é minha:** `cursos.is_projeto_banda`, a marca canônica do LA
> Report (`regras-negocio-canonicas.md` §1.3). Conferido: dá exatamente os
> mesmos 13 regulares do Ramon que a régua de lá produz. O doc marca
> `nome ILIKE '%banda%'` como legado a ser morto — não recriei.
>
> **Provado CONVERSANDO com o Fábio,** não só no banco:
> Ramon (33) → *"47 alunos. São 13 regulares e, nas atividades extras: 15 no
> GarageBand, 14 no Power Kids e 10 no Minha Banda Para Sempre."*
> Matheus (25), que não tem extra → *"20 alunos regulares"*, sem lista vazia.
>
> **⚠️ Frente própria aberta: contar TURMAS ("você tem 3 bandas").** O número
> de turmas mora em `aulas_emusys.turma_nome`, e o caminho de lá até o curso
> (`curso_emusys_id` → `cursos.emusys_ids`) **está quebrado**: medido em
> 13/08, ele faz o Ramon "dar aula de Violino" e infla Violão de 2 para 34
> alunos. Contar turma por cima disso seria número errado com cara de número.
>
> ## ✅ LAÇO DE `bloqueadas`: FECHADO (13/08 noite)
>
> Migration `20260813230000_bloqueio_permanente_sai_da_fila` **aplicada e
> registrada** (RED → GREEN → **4/4 mutantes**), e o reconciler na VPS
> patchado (backup `.bak-laco-*`, `py_compile` ok, rodado à mão).
>
> **Eu decidi, não subi pro Alf** — os dois bloqueios têm vidas opostas e isso
> é desenho, não negócio:
> `acao_ativa_referencia_storage` é **temporário** (a outra ação vai fechar →
> reentrar na fila é o certo, e continua reentrando);
> `registro_confirmado_referencia_storage` é **permanente** (o áudio é a
> evidência do registro confirmado; nunca vai poder ser apagado). O permanente
> vira **carimbo com o motivo escrito** e sai da fila — não vira pendência,
> porque não há nada pra alguém resolver, e pendência fantasma essa casa já
> paga caro.
>
> A porta nova é separada da `fabio_concluir_limpeza` **de propósito**: aquela
> re-prova e recusa quando `pode_remover` é falso, e essa recusa é a defesa que
> impede um worker com bug de apagar evidência. Não afrouxei.
>
> **Limite honesto da prova:** o lado do banco foi provado contra a produção
> (claim real, tabelas reais, transação descartada). O ramo novo do worker
> **não pôde disparar** — hoje há 0 candidatos bloqueados, e fabricar um seria
> dado sintético em produção. O que está provado do worker: compila, roda, e o
> contador `arquivadas` aparece na saída. Timer de 30s ativo.
>
> ## ✅ O NÚMERO DA CARTEIRA JÁ CHEGA CALCULADO (13/08 noite)
>
> Eu tinha registrado que o Fábio "acerta por conta própria, não por contrato".
> **Medido hoje: está errado.** `fabio_contexto_professor(25)` já devolve
> `total_alunos_carteira: 20` e `fonte_carteira:
> vw_professor_carteira_pessoa_canonica_sombra` — contado com `count(*)` em
> cima da **mesma view canônica** que a minha RPC lê. O número que entra no
> prompt é calculado no banco, não pelo modelo.
>
> O que a `app_professor_carteira_contagem` acrescenta e o contexto não tem é o
> **detalhe**: pessoas × matrículas × linhas juntos. Fica, porque lê a mesma
> canônica — é outra granularidade da mesma verdade, não uma segunda verdade.
>
> ## ✅ SENHA NO `config.yaml`: NÃO É DECISÃO DO ALF (13/08 noite)
>
> Medido: `~/.hermes/config.yaml` é `600 fabio:fabio`, dentro de `~/.hermes`
> que é `700`. A senha do `fabio_agent` só é legível por `root` ou por quem já
> tem a conta `fabio` — que é exatamente quem já tem SSH pra tudo. **Não
> acrescenta superfície de ataque nenhuma.** Não sobe pro Alf.
>
> **CP-4.3 CONSTRUÍDO em 13/08.** Duas migrations aplicadas e registradas:
> `20260813190000_a_pessoa_ganha_nome` (view `vw_aluno_pessoa` + RPC
> `app_professor_carteira_contagem`, **5/5 mutantes**) e
> `20260813200000_a_porta_do_agente` (o grant que faltava, RED→GREEN).
>
> **A pedra que eu pisei, e que vale guardar:** publiquei a RPC só para
> `service_role`. O consumidor real é o `postgres-mcp` do Hermes, que conecta
> com papel **próprio, `fabio_agent`** — ele não conseguia executar.
> **Contrato publicado sem conferir QUEM vai chamar é contrato não publicado.**
> O grant não alargou nada: `fabio_agent` já tinha SELECT na carteira, na view
> e em `alunos`.
>
> **⚠️ O Fábio responde 20 e explica o multi-curso em português claro — mas NÃO
> chama a RPC, e isso está provado.** Cobrado dos números exatos, respondeu:
> *"são 20 pessoas. O total exato de matrículas não veio neste recorte."* Se
> tivesse chamado, os três viriam juntos. O número está certo **por conta
> própria**, não por contrato.
>
> **Causa medida:** a instrução está viva no `SKILL.md`, mas o
> `.skills_prompt_snapshot.json` carrega **só o manifesto** (nome, categoria,
> descrição) — nenhuma frase do corpo aparece nele. O corpo é aberto **sob
> demanda**, e para "quantos alunos" o agente responde sem abrir a skill. Isso
> é frente própria: **como o Hermes decide abrir uma skill**.
>
> **🔐 Para o Alf:** o `~/.hermes/config.yaml` guarda a **senha do papel
> `fabio_agent` em texto claro** no `DATABASE_URI`. Não toquei — é decisão de
> infra dele se vira variável de ambiente / arquivo restrito.
>
> ## ✅ F-C AUDITADO — as duas portas estão certas; o risco era outro (13/08)
>
> O Alf avisou que o motor do WhatsApp passou a gravar aula com **baixa
> automática de presença**, igual ao app, e perguntou se a régua de precedência
> valia para as duas. **Vale.** As duas convergem no mesmo core:
>
> - app do professor → `app_registrar_presencas_aula` → `fn_registrar_presencas_core`
> - WhatsApp/áudio → `fabio_emitir_presenca_por_registro` → `fn_registrar_presencas_core`
>
> E o core só sobrescreve fonte fraca — **nunca pisa em decisão humana**.
> Provado por teste comportamental, não por leitura: gravei presença de
> `agenda_secretaria` e mandei o core tentar por cima com `fabio_audio`;
> não pisou. Depois rebaixei para `emusys` e ele promoveu, como deve.
>
> **A terceira porta existe e é a maior surpresa:**
> `app_registrar_chamada_agenda` (a da secretaria — **889 linhas, segunda maior
> fonte, ativa hoje**) **não** passa pelo core: insere direto e tem régua
> própria (`v_humanos`). Conferido: a lista dela é **idêntica** à de
> `fn_presenca_e_forte`. **Não havia defeito vivo.**
>
> **O que foi consertado (`20260813220000_uma_regua_so_de_precedencia`):** a
> mesma regra estava escrita em TRÊS lugares e de duas formas incompatíveis —
> `fn_presenca_e_forte` e a agenda com lista **positiva** (5 fontes fortes), e
> o core com lista **negativa** (`not in ('emusys','sistema')`). Concordavam só
> porque o `CHECK` de `respondido_por` fecha o vocabulário em 7 valores, e
> 5 + 2 são complementares. **No dia em que alguém acrescentar uma fonte ao
> CHECK, o core passaria a tratá-la como forte em silêncio.** O core agora
> **pergunta pra régua** em vez de repetir a lista. 3/3 mutantes, e o RED
> falhou só nos passos de contrato — os comportamentais já passavam, que é a
> prova de que não havia bug vivo.
>
> **Cheiro anotado, não consertado:** 5 linhas com `respondido_por = 'sistema'`
> criadas em 13/08 15:16 são **pendências** (`status pendente`, presença nula)
> de aulas reais de 12/08. Não mentem presença. Mas "respondido por sistema"
> numa linha que ninguém respondeu é semântica torta.
>
> ## ⛔ ERRO MEU, ACHADO AO LER AS REGRAS DE NEGÓCIO DO LA REPORT (13/08)
>
> **Eu construí o que já existia.** O `D:/la-performance-report` (que eu só
> puxei DEPOIS — estava **244 commits atrás**) tem `docs/REGRAS-DE-NEGOCIO.md`,
> e o banco já tinha:
>
> - **`vw_aluno_identidade_unidade_canonica`** — já tem coluna chamada
>   **`pessoa_chave`**, o MESMO nome que escolhi, e ainda `aluno_id_canonico`,
>   `aluno_ids_locais`, `identidade_fonte`, `identidade_confianca`.
> - **`vw_professor_carteira_pessoa_canonica_sombra`** — a carteira por pessoa,
>   por professor.
>
> Os números batem exatamente: minha RPC dá **20** (prof 25) e **47** (Ramon);
> a canônica-sombra dá **20** e **47**. Minha `vw_aluno_pessoa` é redundante e
> mais pobre. O CLAUDE.md avisa disso ("a canônica já existe") e eu fiz mesmo
> assim, porque procurei função que ESCREVE em `alunos` e índice único, e nunca
> perguntei "já existe view canônica de pessoa?".
>
> **Conserto proposto:** aposentar `vw_aluno_pessoa` e repontar
> `app_professor_carteira_contagem` para a canônica. **Não executado** — ver a
> decisão pendente abaixo, que muda o desenho.
>
> ## ⚠️ DECISÃO PENDENTE: banda conta na carteira do professor?
>
> `docs/REGRAS-DE-NEGOCIO.md` §3.5 diz que banda/coral são **atividade extra** e
> ficam *"Excluída de: alunos ativos, alunos pagantes, ticket médio, MRR, LTV,
> churn, médias de turma, **carteira do professor**, score do professor"*.
>
> Mas o Alf descreveu o caso operacional: o aluno **aparece na grade** do
> professor de banda — "com o Willer na guitarra e com o Ramon na prática de
> banda". Operacionalmente o Ramon **dá aula** para essa gente.
>
> São dois números legítimos, e a diferença é enorme:
>
> | professor | hoje | sem banda | cai |
> |---|---|---|---|
> | Ramon Pina Morais | 47 | **13** | 34 |
> | Lucas da Silva Guimarães | 37 | 23 | 14 |
> | Willian De Andrade | 41 | 31 | 10 |
> | **Alan Samico** | 5 | **0** | 5 |
>
> O Alan só dá banda: pela régua do KPI, a carteira dele é **zero**. Dizer isso
> pro Fábio seria absurdo operacionalmente.
>
> **Leitura que eu proponho (falta o Alf confirmar):** são DUAS perguntas
> diferentes. *"Quem eu ensino"* (operacional, o Fábio, inclui banda) ≠
> *"tamanho da carteira pra KPI"* (exclui banda). O erro seria ter um número só
> respondendo as duas. Enquanto não confirmado, **a RPC segue incluindo banda** e
> está marcada aqui como não-conforme ao doc.
>
> **✅ Caso multi-professor conferido (Alf, 13/08):** uma pessoa pode aparecer
> na grade de vários professores — guitarra com um, banda com outro. Medido:
> **127 pessoas** estão em mais de uma carteira, e uma está em **5**
> (Vinícius Lopa: Contrabaixo com o Marquinhos, "Minha Banda Para Sempre" com
> o Ramon, Power Kids com Kaio, Renan e Rodrigo). **Cada carteira conta ela uma
> vez** — o desenho aguenta.
>
> **⚠️ ARMADILHA PRO PAINEL DA COORDENAÇÃO:** somar as carteiras **não** dá o
> total da escola. Medido: **999 pessoas** na escola × **1.144** somando as
> carteiras = **145 a mais (14,5% de inflação)**. Total da escola tem que ser
> `count(distinct pessoa_chave)` sobre todas as carteiras, nunca soma.
>
> **A ORIGEM DA DUPLICATA: é o contrato da tabela, não falha de sincronismo.**
> A única chave única de `public.alunos` além da PK é
> `UNIQUE (telefone, unidade_id, nome, curso_id)` — **com `curso_id` dentro**.
> `alunos` não é tabela de pessoas: é tabela de **pessoa × curso**. Quem tem
> dois cursos *tem* que virar duas linhas. E `emusys_student_id` **não tem
> índice único nenhum**. A view não inventa nada — reflete esse grão.
>
> **Cruzado com a API do Emusys ao vivo:** `3183` @ CG é **uma** Luiza com 2
> matrículas (nosso banco: 2 cadastros). `1001` @ BARRA é o Pietro e `1001` @
> RECREIO é a Júlia — **pessoas diferentes com o mesmo número**, porque os IDs
> do Emusys são **por unidade** (a skill da API avisa isso).
>
> **✅ DECISÃO 1 — a chave é `(unidade_id, emusys_student_id)`.** Sobre 1.616
> cadastros ativos: o par dá **1.400 pessoas**; o id **sozinho** dá 1.311, ou
> seja **fundiria 89 pessoas diferentes**; e acrescentar `data_nascimento` dá
> **1.400 também** — não muda nada, serve como asserção de sanidade, não como
> parte da chave. Dos 224 grupos: **137** são duplicata real (mesma unidade) e
> **87** são colisão de namespace; **zero** grupos de mesma unidade apontam
> para pessoas diferentes.
>
> **✅ DECISÃO 2 — aditivo, e o alvo NÃO é a view.** A raiz está em `alunos`. A
> view é `security_definer` e lida por outros sistemas; mexer nela não ataca a
> causa e pode quebrar o LA Report. Caminho: **RPC nova de contagem por
> pessoa**, deduplicando pelo par, sem tocar nas linhas existentes.
>
> **Validação:** na carteira do professor 25,
> `count(distinct (unidade_id, emusys_student_id))` = **20** — o número que o
> Alf decidiu e o que o Fábio responde.
>
> **⚠️ Correção de um número meu:** reportei **305** cadastros excedentes; aquilo
> misturava colisão de namespace com duplicata real. O excedente verdadeiro é
> **216** (1.616 − 1.400).
>
> **Pergunta de arquitetura que fica pro Alf (não bloqueia o CP-4.3):** `alunos`
> continua **pessoa × curso** e a gente só conta certo por cima, ou vira
> **pessoa** com as matrículas numa tabela ao lado? Contar pelo par funciona
> nos dois cenários.
>
> **Sprint 4: a premissa se inverteu. O Fábio estava CERTO e a view é que
> infla.** Decisão do Alf em 13/08: **carteira conta ALUNO**, não matrícula.
>
> Os três números da carteira do professor 25: **23** linhas da view
> (matrícula × grão) · **21** `aluno_id` distintos · **20** pessoas de verdade.
> O 21 vira 20 por causa de um cadastro duplicado achado ali:
> `aluno_id 265` e `aluno_id 1465` são **a mesma criança** — mesmo nome, mesma
> data de nascimento (2017-05-18), **mesmo `emusys_student_id` (3183)**, mesma
> unidade, as duas ativas e nenhuma arquivada.
>
> **⚠️ Tamanho real, medido na base inteira: 224 grupos de `emusys_student_id`
> duplicado, 305 cadastros excedentes, 60 grupos com 3 ou mais.** Não é o caso
> da Luiza — é sistêmico, e mexe em presença, relatório e tudo que conta aluno.
>
> **Mas o 20 do Fábio não é contrato, é aritmética de modelo.** O
> `_fetch_professor_roster` **não deduplica** — manda as 23 linhas e o modelo
> conta. Perguntei três vezes com frases diferentes: 20, 20, 20 — estável e
> certo, mas nada garante isso numa carteira maior nem com duplicata de grafia
> diferente. Resposta certa, mecanismo frágil.
>
> **As duas decisões que travam o CP-4.3:**
>
> 1. **Chave de identidade:** `emusys_student_id` provou a duplicidade aqui, mas
>    a memória da casa diz que esse campo **já colidiu entre pessoas
>    diferentes**. Casar com `data_nascimento` junto?
> 2. **Onde mora o número honesto:** `vw_fabio_carteira_professor` é
>    `security_definer` e lida por outros sistemas do banco compartilhado —
>    mexer nela pode quebrar o LA Report. O caminho seguro é **aditivo** (RPC
>    nova), sem tocar nas linhas existentes.
>
> E fica dito: deduplicar na contagem **esconde** os 305 excedentes. A limpeza
> dos cadastros é frente própria, e é do Alf.
>
> **Sprint 3 FECHADO em 13/08 — os dois sobreviventes caíram e tinham a MESMA
> raiz.** `094` foi de 6/7 para **7/7** e `20260813004713` de 4/5 para **5/5**.
>
> A raiz: os dois mutantes mexiam em DDL com `if not exists`, que **não executa
> no replay** contra a produção — a mutação não chegava a agir. Eram
> impossíveis de morrer, não difíceis. O conserto foi o mesmo: o mutante passou
> a **derrubar o objeto de verdade** (`drop constraint` / `drop index`, dentro
> da transação descartável) e o teste ganhou o passo de catálogo que o pega.
> Os dois objetos foram medidos em produção antes e **existem** — era cobertura
> fantasma, não defeito. De quebra, a afirmação da `20260813004713` de que o
> índice é "segunda barreira independente do lock" agora é **provada**.
>
> **⚠️ Nove runners mexem em DDL `if not exists` e podem ter a mesma cobertura
> fantasma:** `062`, `064`, `066`, `075`, `076`, `094`✅, `095`,
> `20260812163000`, `20260813004713`✅. Dois consertados; os outros sete são
> dívida **conhecida**.
>
> **A trava de baseline está em 60 dos 64 runners** (4 já tinham; `059`, `095`
> e `20260812163000` ficaram fora por não seguirem o padrão `ORIGINAL`/`TESTE`).
> `node --check` em todos: zero erro. E ela morde: `mutantes-090` agora devolve
> `BASELINE VERMELHO` em vez do 10/10 falso.
>
> **Laço de `bloqueadas`: documentado, não consertado — de propósito.** Medido:
> elegíveis hoje = 0, bloqueio permanente = 0, temporário = 0 — **não pode
> disparar**. E há bifurcação de desenho que é decisão do Alf:
> `acao_ativa_referencia_storage` é bloqueio **temporário** (reentrar na fila é
> certo) e `registro_confirmado_referencia_storage` é **permanente** (reentrar a
> cada 120s é laço). **Pergunta pro Alf:** o permanente vira carimbo que tira da
> fila com o motivo escrito, ou vira pendência visível pra alguém resolver?
>
> **Sprint 3 EM ANDAMENTO — a bateria `09` saiu de 2 FALHARAM para 0
> FALHARAM** (3 passam · 3 superadas · 1 não reaplicável).
>
> Os três baselines vermelhos foram diagnosticados: `090` não é replayável por
> construção (`create table` sem `if not exists`); `091` virou
> `SUPERADA POR: 092` (a 092 mudou a assinatura de `fabio_status_audio_fila` de
> propósito); `095` virou `SUPERADA POR: 20260812004430`.
>
> **O incidente que estava escondido atrás da `095`:** em **12/08 00:40 UTC** o
> log registrou `registro_recibo_entregue_mas_nao_fechado`, status
> `delivered_unclosed` — o recibo **foi entregue** ao professor 10 e a função
> que fecha quebrou com `42P10` (`ON CONFLICT` sem o predicado do índice
> parcial). Não virou duplicata porque um caminho de recuperação fechou a linha
> com o marcador sintético `recovered-delivered-unclosed` (1 notificação,
> `tentativas=1`). O Codex corrigiu **quatro minutos depois**, na
> `20260812004430`, que é o que a produção usa hoje.
>
> **Os órfãos e o incidente eram a MESMA história.** O teste daquela correção
> era o `097-...test.sql`, órfão por dois motivos somados: nome que não pareia
> com o da migration **e** `begin;/rollback;` próprios, que o runner recusa.
> Os três órfãos foram pareados e convertidos ao formato da casa —
> **não há mais teste órfão no repo**.
>
> **Um mutante pagou por si:** o M1 de `mutantes-20260812004430` (que
> reintroduz literalmente o defeito de 12/08) **sobreviveu**, porque o teste
> original reproduzia o upsert *inline* e nunca tocava na função. Virou passo
> novo no teste; agora 2/2.
>
> **Nove guardas de ACL estavam apagadas** (090/091/095). Medidas antes: as
> nove portas **estavam corretas** — não havia vazamento, mas ninguém olhava.
> Resgatadas em `20260813180000_guardas_resgatadas_do_whatsapp.sql`, aplicada e
> registrada, **5/5 mutantes**.
>
> **⚠️ Erro meu, registrado pra não voltar:** eu afirmei defeito **vivo** no
> `ON CONFLICT` depois de rodar `EXPLAIN` contra a produção. O `EXPLAIN` usava
> o texto **do arquivo 095** (versão velha) — a função viva já tem o predicado.
> Testar o texto do repo e concluir sobre a produção é o erro de sempre com
> roupa nova.
>
> **Falta no Sprint 3:** `094/M4` (unicidade da ação no ledger);
> `20260813004713/M4` (remover o índice único não mata, e a migration *afirma*
> que ele é "segunda barreira independente do lock"); estender
> `exigirBaselineVerde()` aos 62 runners restantes; e o laço latente do caminho
> `bloqueadas` herdado do Sprint 1.
>
> **Sprint 2 FECHADO em 13/08 — a rede de mutantes voltou a enxergar, e o
> sprint achou coisa pior que o CRLF.**
>
> A causa foi **medida**: template literal em JavaScript normaliza `\r\n` para
> `\n` por especificação, então o fim de linha do `.mjs` é irrelevante e
> **100% das âncoras casam com a versão LF** do `.sql`. `.gitattributes` criado
> e 61 arquivos normalizados, com `git diff --numstat` = **zero arquivos**
> (nenhuma mudança de conteúdo).
>
> **⚠️ ATENÇÃO ao ler placar de mutante desta casa.** Recuperado o CRLF, `090`
> e `091` passaram a dizer **10/10 — e os baselines das duas FALHAM**. Vinte
> "mortos" que não provam nada. O que a normalização recuperou de verdade:
> `20260812163000` 17/28 → **28/28**, `094` 0/7 → **6/7**, `20260813004713`
> 1/5 → **4/5** — essas três com baseline verde.
>
> Criado `scripts/lib-baseline.mjs` (`exigirBaselineVerde()`), **testado nos
> dois sentidos**: passa no verde, **barra** no vermelho da `091`. Ligado nos
> dois runners novos; falta estender aos outros 62.
>
> **`093` e `20260812135033` agora são `-- SUPERADA POR:`** — mas só depois de
> as guardas de ACL delas serem resgatadas para
> `20260813170000_guardas_resgatadas_da_presenca.sql`, aplicada, registrada e
> com **4/4 mutantes**. Marcar SUPERADA sem isso teria desarmado guarda viva.
>
> **Lista do Sprint 3, tudo medido:** baseline vermelho em `090`/`091`/`095`;
> **`094/M4` sobrevive de verdade** (unicidade da ação no ledger);
> **`20260813004713/M4` sobrevive de verdade** — remover o índice único não
> mata, e a migration *afirma* que ele é "segunda barreira independente do
> lock" sem nada provar; `mutantes-095` exige alvo local e nunca verificou nada
> aqui; **3 testes órfãos** (`097`, `098`, `099`) que nunca entram na bateria
> porque o runner pareia por nome; e estender a trava de baseline aos 62
> runners restantes.
>
> **Sprint 1 FECHADO em 13/08 — o laço do reconciler acabou.** Migration
> `20260813160000_limpeza_nao_se_repete.sql` aplicada e registrada. O `claim`
> passou a exigir que a linha ainda não tenha o carimbo `payload.limpeza` —
> carimbo que já era gravado e que ninguém lia. Provas: RED com exatamente um
> passo divergindo; GREEN; **5/5 mutantes sobre baseline verde**; e no
> `journalctl` ao vivo `claimed:5` → **`claimed:0` e fica**. A prova inversa
> também foi feita: fixture controlado com objeto real no bucket foi limpo
> **exatamente uma vez** e o resíduo conferido em zero. As 5 linhas velhas
> ficam como trilha.
>
> **Lição cara deste sprint, guardar:** o primeiro placar de mutante deu
> **5/5 e era falso** — o teste base tinha quebrado num fixture inválido e os
> cinco morreram de erro, não de asserção. **Conferir o baseline VERDE antes de
> ler placar de mutante** é passo obrigatório agora.
>
> **Achado lateral não consertado:** a mesma família de laço mora no caminho
> `bloqueadas` do worker — quando a prova recusa, ele faz `continue` sem
> concluir, o lease expira em 120s e a linha volta. Hoje não dispara
> (`bloqueadas: 0` em tudo que foi medido). Está anotado pro Sprint 3.
>
> **Sprint 0 FECHADO em 13/08.** O registro que ia evaporar foi salvo: a
> professora é **Daiana (professor 3)**, o prazo da ação foi estendido para
> **16/08** e o Fábio **reenviou a pergunta**, com envio provado no log
> (`whatsapp_sent`, `phone_tail 9985`, msg `...3EB001F81EEADBA1B8D446`). A ação
> segue `aberta`, transcrição intacta, e a trilha ficou gravada em
> `fabio_acao_eventos` como `shortlist_reenviada_manual`. Nada foi para família
> nem comercial. **O Alf também vai falar com ela direto.**
>
> **Dois achados novos, que viraram backlog no plano (F-A e F-B):** a shortlist
> **não usa o nome do aluno citado na transcrição** para desambiguar — o roster
> já respondia (aula 217860 tem a Beatriz Ohana como aluna única; a outra
> candidata tem 6 alunos e nenhuma Beatriz), e o Fábio foi perguntar mesmo
> assim. E **nenhum worker olha ação aberta**: só o handler reativo toca
> `fabio_acoes_pendentes`, então ação não respondida não é lembrada, não alerta
> ninguém e expira em silêncio.
>
> **F-C, informado pelo Alf em 13/08 e ainda NÃO auditado:** o motor do WhatsApp
> passou a gravar conteúdo de aula **com baixa automática de presença, igual ao
> app**. Agora são **duas portas** escrevendo registro e presença — a régua de
> precedência tem que valer para as duas.
>
> **Alarme falso meu, registrado para não voltar:** suspendi o envio achando
> que havia troca de identidade, porque `professor_phone(3)` termina em `9985`
> e o `wa_message_id` começa com `5521998250178` (que dá
> `numero_nao_cadastrado`). **Não é troca:** esse prefixo aparece em 92
> mensagens de 6 professores nos dois papéis — é a **linha do próprio Fábio**.
> O envio proativo está correto.
>
> O trabalho voltou do Codex (PRs #4–#12) e foi **auditado ao vivo** aqui:
> VPS, banco `ouqwbbermlzqqvtqwlul`, logs do systemd e bridge do Fábio.
>
> **Funcionando, medido:** VPS com 121 dias de uptime e disco em 28%; 3
> serviços `running` e 14 timers armados, com **os 12 serviços de timer saindo
> `exit=0`** na última execução. O **Fábio responde ponta a ponta** — pergunta
> feita ao vivo por `falar_com_fabio.py --sem-historico` foi respondida em ~10s
> com dado real (`hermes_api_ok`, professor 25). A migration da PR #11
> (`audio_experimental_duravel`) está **mesmo aplicada** em produção, registrada
> como `20260813101644`, e o teste SQL dela passa verde sem resíduo. Fila de
> áudio com 108 itens, 98 normalizados e **zero pendente travado**.
>
> **Quebrado — 1, laço vivo:** o `fabio-whatsapp-reconciler` repetiu
> **1493 de 1499 execuções idênticas** hoje (`claimed:5, limpas:5`), sempre nas
> mesmas 5 linhas — artefatos do E2E `e2e-isaque-*`, cujo objeto no Storage
> **já não existe** e cujo `payload` já carrega `limpeza.removido=true`. Causa:
> `fabio_concluir_limpeza` não muda nenhuma coluna do predicado de
> `fabio_claim_acoes_limpeza`, então a linha requalifica pra sempre. Custo
> ~7.500 ciclos/dia (~22 mil chamadas inúteis), e `atualizado_em` reescrito a
> cada 35s destrói a auditoria da coluna. Provável origem dos `522` de 12/08.
>
> **Quebrado — 2, a rede de mutantes está cega:** o Codex reportou **5/5**
> mutantes na fila experimental; medido aqui, **1/5 com 4 STALE**. Causa provada:
> os `.sql` vindos das PRs chegam em **CRLF** (`core.autocrlf=true`, repo **sem
> `.gitattributes`**) e as âncoras dos mutantes são `\n` — âncora de uma linha
> casa, **âncora multilinha nunca casa**. Não é mentira do Codex: no Linux dele,
> LF, as 5 casavam. **47 arquivos `.sql` em CRLF**, e são exatamente `090`–`096`
> e todos os datados de 12–13/08 — o trabalho inteiro das PRs #4–#11. Placar real:
> 090 8/10 · 091 7/10 · **094 0/7** · 095 falha de âncora · 20260812163000 17/28 ·
> 20260813004713 1/5.
>
> **Alarme falso descartado — NÃO reabrir:** a 093 acusa *"rascunho emite
> presença antes da confirmação"* (`presencas_antes=1`), e a 099 acusa recibo
> faltando. **Nenhum dos dois é defeito vivo.** O `fabio_criar_registro` em
> produção **não referencia `aluno_presenca`**, não há trigger de presença em
> `fabio_registros_aula`, e **nenhuma das 8 funções que dão `INSERT` em
> `aluno_presenca` é chamada por ele**. E a 099 cobra recibo de `origem='app'`,
> mas a resposta atual é `{"motivo":"origem_app","skipped":true}` — o
> comportamento **novo e correto**. Os dois foram superados de propósito pela
> `20260812163000_recibo_so_whatsapp_e_fila_ativa`; viram `-- SUPERADA POR:`,
> não conserto.
>
> **Com prazo, hoje:** ação `8593cf8d-4e73-4bb4-b4ba-b8d98c418580` do professor
> 3, `aberta` desde 12/08 19:12 UTC e **expirando 13/08 19:12 UTC (16:12 BRT)**.
> É um áudio real e detalhado sobre a aluna Beatriz Ohana, com contexto de saúde
> relatado por ela. O Fábio mandou shortlist com 2 aulas candidatas (`217860`,
> `205008`) e o professor não respondeu. A transcrição está **inteira no
> payload** — o texto não se perde, mas o registro não nasce.
>
> **Aberto, sem ser fogo:** o Fábio diz **20** alunos na carteira do Matheus, a
> view canônica diz **23 linhas / 21 alunos distintos** — três números pra mesma
> carteira. `node_modules` está pela metade com `esbuild.exe` travado, então os
> **65/65 unitários do Codex não foram reproduzidos aqui**. O gateway sai com
> `status=1/FAILURE` em todo stop (cosmético, mas mascara falha real no log).
> Três branches remotas com 1 commit próprio e 420–493 commits de atraso.
> Advisors: 650 no projeto compartilhado, com 5 `rls_disabled_in_public` e 9
> `security_definer_view` — **banco compartilhado, não mexer sozinho**.

> **Checkpoint canônico — 13/08/2026 07h49 BRT · consolidado após as PRs #1–#11.**
> `origin/main` e o clone local apontam para `f3ccb5980a77584dcb614e5a76607cd42a484b93`
> (PR #11, [fix: persist experimental audio retries](https://github.com/LucianoAlf/la-teacher/pull/11)). A produção Vercel
> `dpl_9BoZUitZfiAHKDeoANYKj7x28aZP` está `Ready` e atende
> `https://la-teacher.vercel.app/`; a rota `/app/login` abriu como **LA Teacher**,
> com tela de login e sem erro de console. A árvore `main` está limpa neste
> checkpoint. Não tomar os checklists antigos deste arquivo nem
> `docs/ROADMAP.md` como estado de entrega: são histórico e não foram reescritos
> neste trabalho.
>
> **Trabalho do outro chat integrado e publicado (PRs #6–#10):** presença
> canônica e resolução de aula operacional; recuperação segura de áudio ligado a
> aula sem roster; card de briefing estático oculto; ficha manual individual;
> transcrição contextual/normalização conservadora; e teto de três tentativas
> para falha transitória. A ficha manual continua usando
> `fabio_registros_aula`/`aluno_presenca`, origem `texto`, presença confirmada
> pelo professor e nenhuma fonte paralela. A validação autenticada anterior do
> Matheus mostrou os caminhos **Áudio** e **Ficha** sem erro de console. As
> referências de integração são as PRs #6, #7, #8, #9 e #10; não há branch de
> código desse conjunto pendente de merge.
>
> **Correção integrada nesta conversa (PR #11):** o áudio experimental agora
> entra pela mesma fila persistente do registro normal. A intenção e o Blob são
> guardados antes do Storage; o retry reutiliza o mesmo `storage_path`, faz
> `upsert` e volta à tela experimental correta. A migration
> `20260813004713_audio_experimental_duravel.sql` está aplicada no projeto
> Supabase `ouqwbbermlzqqvtqwlul`: a política
> `storage.objects.fabio_audios_update_own` limita o `UPDATE` ao dono
> autenticado, o índice parcial `uq_fabio_fila_audio_experimental_path` impede
> duplicidade física e `app_enfileirar_audio_experimental(bigint,text,integer)`
> está liberada para `authenticated`, não para `anon`.
>
> **Prova real da PR #11:** no vínculo experimental do Matheus Reis foi copiado
> um áudio técnico já existente, sem enviar mensagem a professor, família ou
> comercial. A VPS, pelo `fabio-audio-experimental.service`, reivindicou a fila,
> transcreveu e produziu um rascunho `aguardando_confirmacao`, com uma tentativa
> e transcrição não vazia; nenhuma notificação nasceu e nada foi confirmado. Ao
> final, o rascunho, a fila e o objeto de Storage de teste foram removidos, com
> verificação de zero resíduo. Este E2E prova Storage → fila → VPS → rascunho;
> ele não substitui um professor autenticado gravando no navegador, que segue
> sendo a próxima observação humana de uso.
>
> **Verificações recentes:** PR #11 ficou `CLEAN`, Vercel Preview aprovou;
> `npm run test:unit` = **65/65**, `npm run build` e `git diff --check` verdes;
> testes SQL remotos e **5/5 mutantes** da migration da fila experimental
> morreram. O linter de segurança do Supabase continua apontando avisos legados
> em outros objetos do projeto; a mudança desta frente foi verificada
> pontualmente por política, grants, índice e `search_path` fixo.
>
> **Estado para continuar:** a produção está liberada para o piloto prático.
> Observar professor autenticado enviando áudio experimental e repetir o mesmo
> arquivo após uma falha transitória para provar a UX do retry no dispositivo.
> Não enviar automaticamente nada a família. As três branches remotas ainda não
> integradas (`claude/compassionate-heisenberg-e778a8`,
> `fabio/atualiza-docs-estado-real` e `fabio/edge-carteiro-registro-aula`) não
> fazem parte deste checkpoint; revisar diff e finalidade antes de qualquer
> merge.

> **Checkpoint ativo — 12/08/2026 20h38 BRT · registro manual e correção do
> áudio publicados e provados em produção.** A entrega final entrou na `main`
> pela PR #9, merge `f164c247acfe1e55d2b6fd28bb3afe214ed5e661`, com os
> commits `291dfb5` (transcrição contextual) e `ceee8ef` (fila recuperável da
> UI). O Vercel Production `dpl_EmtdWPJTSpjfHU9dwqto21sUNUuG` foi construído
> desse merge e serve `https://la-teacher.vercel.app/` com o bundle
> `index-BKtGM9x9.js`. A sessão autenticada de Matheus foi recarregada no
> artefato novo: 11/08 mostra os botões de áudio + ficha em todas as seis aulas,
> sem erro de console; 17/08 mostra cinco chamadas, turma de dois alunos às 17h
> e Arthur na individual das 18h. O card estático “Briefing do Fábio — em
> breve” continua oculto.
>
> A ficha manual permanece canônica: tronco opcional, ficha por aluno, copiar
> campo, duplicar ficha, autosave versionado, cache local e conflito explícito.
> Edição, presença e confirmação são serializadas; uma falha transitória não
> envenena a fila seguinte. A migration
> `20260812220500_registro_manual_ficha_individual.sql` está no projeto
> principal `ouqwbbermlzqqvtqwlul`, registrada como `20260812222331`, sem
> branch Supabase. Reutiliza `fabio_registros_aula` e `aluno_presenca`;
> conteúdo manual termina com origem `texto` e presença confirmada pelo
> professor com origem `professor_la_teacher`, sem fonte paralela. A simulação
> controlada na turma real de três alunos de 11/08 não confirmou presença nem
> registro; o rascunho `c4efe283-beb7-4503-9897-8bb4d97b96d3`, suas três
> fatias, o texto de teste e o cache do navegador foram removidos e a
> pós-verificação encontrou zero resíduo.
>
> O áudio agora usa Whisper `large-v3-turbo`, contexto server-side limitado e
> sanitizado da turma/repertório e correção conservadora apenas contra títulos
> conhecidos. Nos áudios reais auditados, Arthur passou a produzir “Meu
> Lanchinho” e “Astro Bot até a metade”; Lucas passou a produzir “quarto
> sistema”. O normalizador remove a fala metalinguística “mencionado na
> transcrição”, rejeita `quadro/quarto` ambíguo, deduplica objetivo/atividade e
> repertório comum/individual, e o preview ordena Repertório → Atividades →
> Objetivo. Falha semântica usa `fabio_marcar_audio_erro_terminal`; retry
> automático ficou restrito a erro transitório, menos de três tentativas, pela
> migration `20260812232000_fila_audio_teto_retry.sql`, registrada diretamente
> no projeto principal como `20260812231751 / fila_audio_teto_retry`. ACL ao
> retry: `anon=false`, `authenticated=false`, `service_role=true`; elegíveis no
> pós-check: zero.
>
> O motor vivo na VPS está em
> `/home/fabio/.hermes/hermes-agent/tools/fabio_registro_aula_tool.py`
> (`sha256 607ea2ae06024cb3051696176e7b40dd48e94d84e3b786a1ae57f19c3d0f0d13`)
> e o webhook em `/home/fabio/.hermes/webhook_subscriptions.json`
> (`sha256 62ff634832d08bdabb851dbd9f8297acecc3c55f95b06f9331877414d9fece4f`).
> Backup anterior:
> `/home/fabio/fabio-chat-bridge/backups/20260812-audio-contextual-stt/`.
> O serviço correto é o **user unit** `fabio-hermes-gateway.service`: ativo,
> PID `1447626`, `NRestarts=0`, desde `23:22:28 UTC`; os logs não receberam
> novo erro após essa subida. Quatro candidatos temporários de deploy foram
> removidos do diretório do bridge depois da validação.
>
> Provas: 57/57 unitários web; 33 contratos Python de normalização; contrato do
> webhook; 25 contratos de auditoria; SQL transacional de 018, 094, registro
> manual e teto de retry; build; `git diff --check`; revisão independente final
> = GO. A suíte histórica total ainda reporta 18 migrations antigas não
> replayáveis e 5 substituídas: isso é dívida do harness, não foi reclassificado
> como verde. Na fila real, um rascunho de Sophia foi recuperado, um áudio sem
> conteúdo confiável foi encerrado com segurança e o áudio `292f…` permanece
> para revisão humana porque a identidade Raquel/Luna não pode ser decidida no
> escuro. Não reescrever dados históricos ambíguos automaticamente.

> **Checkpoint de rollout — 12/08/2026.** A frente de recibos e fila de áudio foi concluída e integrada pela PR #4 (merge `1d5e3c2`), após os commits `66d509b`, `074dbed`, `ea51cfd`, `193859a` e `197b1bb`. A migration `20260812163000` está aplicada e registrada; rollback preservou schema e 35 linhas, 28/28 mutantes SQL, 43 testes unitários e build passaram. Recibos originados no aplicativo não são enviados ao WhatsApp; ações originadas no WhatsApp continuam salvando no aplicativo e usam o retorno do canal. VPS e timer de recibo seguem ativos, sem jobs ativos/claims pendentes; Vercel Production está publicada e o login responde HTTP 200 sem erro de console. Não houve áudio real de professor, presença/falta, mensagem WhatsApp de saída, mensagem a responsável ou E2E com professor. Evidência: `docs/superpowers/evidence/2026-08-12-recibos-e-fila-audio.md`.

> **Este arquivo existe pra sobreviver ao `/compact`.** O resumo automático guarda
> o que eu lembro; este arquivo guarda o que é **verdade**. Depois de compactar,
> a primeira coisa que eu faço é ler ele — e sigo daqui, sem perguntar de novo o
> que já foi decidido.
>
> **Última atualização: 12/08/2026 — presença canônica, ficha manual e
> correção semântica/retry do áudio publicados.** G8 publicado com recibo desligado; E2E
> funcional ainda pendente.** Radar telas no ar
> (Tasks 5–9 mergeadas) + foto (`bcf995c`, 089) + tooltip do score organizado
> (`f00c96d`, aprovado). Deploy do Radar = **Vercel + Supabase** — a frente do
> Fábio usa a VPS própria. Frente “Fábio escreve no WhatsApp” = SPEC aprovada + plano
> em gates; 10/08-G0/G1 concluídos, schema 090/091/092 publicado no Supabase e
> 10/08-G4 publicado em `shadow` na VPS. O 10/08-G5 passou a piloto restrito;
> a fonte do callback foi correlacionada e espelhada e o G6 operacional aplicou
> somente os flags de recibo desligados, sem restart. O G8 posterior publicou o
> contrato e o timer com barreira `off`; E2E funcional continua pendente. Quem mais lê: o
> Alf, o Hugo, o Alfredo. Escrever pra eles, não pra mim.

## 🧭 12/08 — presença canônica e entrada manual: checkpoint ativo

**Pedido aprovado pelo Alf:** Emusys, LA Report, LA Teacher e Fábio/WhatsApp
precisam usar `public.aluno_presenca` como mesma decisão local, mostrando a
origem. O Emusys é válido quando marca **presente**; `ausente` vindo dele segue
como pendência operacional até decisão humana. A equipe pode resolver no LA
Report, o professor no app ou WhatsApp/Fábio. Nenhuma dessas portas pode apagar
evidência bruta do Emusys ou abrir escrita direta por RLS. A auditoria reutiliza
retificações humanas e ações WhatsApp; só uma estrutura focada em conflitos
abertos é admitida, se não existir equivalente no schema.

**Fonte de verdade do desenho:**
`docs/superpowers/specs/2026-08-12-presenca-canonica-e-entrada-manual-design.md`.
Ela também preserva a segunda frente aprovada: agenda com microfone **e**
caderno; formulário manual completo, rascunho automático e campos individuais
por aluno; copiar campo + duplicar ficha inteira com confirmação de
sobrescrita. A revisão técnica acrescentou contrato obrigatório de rascunho por
professor+aula+aluno, versão/conflito áudio-manual, recuperação de conexão e
progresso explicitamente individual.

**Branch isolada criada:**
`D:\la-teacher-worktrees\presenca-canonica`, branch
`codex/presenca-canonica`, baseada em `origin/main` no commit `57e70be`.
Esse commit já contém a migration produtiva `20260812135033` (presença JSON
nula). Ela é apenas pré-requisito de histórico e **não** resolve a convergência
de fontes.

**Worktree complementar criado (somente Git):**
`D:\2026\LA-performance-report\.worktrees\presenca-canonica`, branch
`codex/presenca-canonica-report`, baseado em `origin/main` no commit
`3f850cc5`. Nenhuma branch Supabase foi criada.

**Dono da migration compartilhada:** o LA Report. O snapshot remoto contém a
migration `20260812135824`, que ainda não existe neste worktree do LA Teacher;
por isso, uma migration em cada repo criaria duas histórias concorrentes para o
mesmo banco. O LA Teacher recebe o contrato/RPC e os badges, sem SQL novo.

**Fatos auditados antes do desenho:**

- `fn_presenca_e_forte(respondido_por)` é a régua humana histórica; **não
  alterar** para incluir Emusys, pois isso fecharia `ausente` bruto como se fosse
  decisão.
- O próximo contrato é uma função status-aware, usada por
  `app_minha_agenda_sessao` e pelas portas de escrita, por exemplo
  `fn_presenca_fecha_chamada(status_presenca, respondido_por)`: só fecha com
  status terminal e fonte humana forte, ou Emusys/presente.
- A matriz de consumidores é parte do contrato: `fn_presenca_e_forte` continua
  para autoria/evidência humana; pendências, sessão, Fábio e guards de chamada
  usam o novo resolvedor. Não trocar uma pela outra por grep genérico.
- O snapshot remoto confirmou as trilhas existentes: `aluno_presenca_retificacoes`
  para retificação humana, `fabio_acoes_pendentes` para a ação WhatsApp e
  `fabio_acao_eventos` para idempotência por `wa_message_id`. Não criar ledger
  universal; criar somente conflito aberto/resolvido se não houver equivalente.
- `upsert_presenca_emusys_bruta` hoje descarta `presente → ausente`, e
  `app_registrar_chamada_agenda(...indeterminado)` pode apagar a linha. Ambos
  são comportamentos a corrigir no projeto principal: atualização automática
  reabre pendência; só divergência contra humano abre conflito revisável.
- Espelhos precisam carregar a referência da decisão que os originou, mas nunca
  copiar raw Emusys entre aulas. Devolvem/registram sincronizados, mantidos por
  precedência e conflitos. Conflitos humanos nunca são decididos silenciosamente.
- `sync-presenca-emusys` conhecido é pull-only. LA Teacher/Report convergem já
  pelo banco compartilhado; escrita de volta na API Emusys fica bloqueada até
  endpoint externo, autenticação e idempotência verificáveis.
- Fábio continua por RPC server-side com `professor_whatsapp`; não receberá
  grant direto de tabela nem acesso SQL no chat. Ação pendente, shortlist,
  expiração e idempotência já existem em `fabio_acoes_pendentes` e
  `fabio_acao_eventos`; a correção deve reaproveitá-las, não inventar nonce
  paralelo. A identidade telefone→professor é prova do bridge, não algo que
  `service_role` sozinho possa provar dentro do Postgres.

**Plano versionado:**
`docs/superpowers/plans/2026-08-12-presenca-canonica.md`. Ele separa o contrato
de presença do formulário manual e fixa a propriedade: LA Teacher mantém
leitura/badges; LA Report mantém a migration canônica, RPC, resolvedor,
conflitos, gêmeos, Fábio e UX da chamada.
A auditoria remota confirmou que `fn_sincronizar_gemeos_presenca(integer)` ainda é
`SECURITY DEFINER` executável por `PUBLIC`/`anon`/`authenticated`; a migration
planejada revoga essas ACLs sem abrir outra porta de escrita. A porta do Fábio
`fabio_registrar_presencas_aula` permanece exclusiva de `service_role`, mas a
autorização contextual WhatsApp ainda precisa ser implementada/testada.

**Alvo de banco decidido pelo Alf:** aplicar as migrations diretamente no projeto
Supabase principal `ouqwbbermlzqqvtqwlul`; não criar branch Supabase e não pedir
custo. O isolamento desta frente é somente de Git. O runner SQL atual abre uma
transação contra produção; não usá-lo aqui, mesmo com rollback, pois esta frente
não cria dados sintéticos na produção.

**Implantação efetiva (12/08/2026):** a única migration de schema desta frente
foi aplicada no projeto Supabase principal `ouqwbbermlzqqvtqwlul`, pelo worktree
do LA Report, sem branch Supabase e sem fixture produtiva:

- `20260812175508_presenca_canonica_confirmacao_respeita_falta_humana`:
  preserva falta humana canonica na confirmacao final do registro. Rascunho,
  autosave e copia nao escrevem chamada; apenas confirmar/gravar pode promover
  presenca, e nao grava conteudo para aluno que secretaria/professor/Fabio ja
  marcou como falta ou falta justificada.
- `20260812172432_presenca_canonica_resolvedor_conflitos`: resolvedor
  status-aware, preservação do raw Emusys, conflito revisável, origem de
  espelho, consumidores de pendência/sessão/Fábio e confirmação WhatsApp
  atômica;
- `20260812172556_presenca_canonica_conflitos_acl`: revoga a leitura direta de
  `anon`/`authenticated` sobre `aluno_presenca_conflitos`; RLS continua ativo e
  a tabela não tem policy de navegador.

Provas pós-aplicação, sem escrever dados: `Emusys/presente` fecha,
`Emusys/ausente` não fecha, falta humana fecha; `anon` e `authenticated` não
possuem `SELECT` na trilha de conflitos e `service_role` possui. O Report teve
testes e build verdes; o banco local não iniciou por uma migration histórica
anterior (`20260109_fase1_seed_dados.sql` referencia `professores` inexistente),
portanto não se deve usar esse startup como prova nem tentar contorná-lo.

**Migração concorrente a reconciliar:** o histórico remoto também registra
`20260812171943_20260812150000_chamada_retroativa_fallback_emusys`, aplicada
antes da canônica e ainda não presente no Git remoto. Não foi recriada nem
reaplicada aqui. Antes de nova migration compartilhada, localizar o arquivo e
o autor, compará-lo ao histórico remoto e registrá-lo no Git sem alterar seu
conteúdo.

**Bridge do Fábio publicado (12/08/2026):** a VPS
`/home/fabio/fabio-chat-bridge/fabio_whatsapp_actions.py` foi comparada antes
do deploy; o único diff eram as dez linhas desta correção. A versão anterior
foi preservada em
`/home/fabio/fabio-chat-bridge/backups/20260812-presenca-canonica-atomic-confirm/`.
A cópia candidata compilou, foi movida atomicamente e o unit
`fabio-chat-bridge` reiniciou `active` com PID `1384707`; o SHA-256 vivo é
`c9d712947037a3ec2f9e68771da5a3a052af3c39c74b1ce4f296af84eec0a46b`.
Nenhuma presença sintética, mensagem WhatsApp nem E2E foi disparado neste
rollout. A confirmação de chamada agora chama
`fabio_confirmar_chamada_acao`, que valida a ação, professor, expiração,
shortlist e `wa_message_id` antes da escrita atômica.

**Próximos gates desta frente:** consumir no LA Teacher os campos
`origem_presenca` e `tem_conflito_presenca` como badges. Depois voltar ao
formulário manual, em uma frente própria: microfone + caderno, rascunho por
professor+aula+aluno, autosave/versionamento e cópias exclusivamente dentro do
roster, jamais presença. Não tocar nas branches paralelas `fabio-whatsapp`,
`fabio-pendencias-whatsapp` ou áudio.

### Validação real posterior — conta Matheus Felipe / Recreio (12/08/2026)

Foi feita leitura da conta autorizada do professor na prévia local ligada ao
Supabase de produção, sem criar, editar, apagar ou “limpar” dado pedagógico. A
unidade da conta é **Recreio** e, na segunda-feira 10/08/2026, a interface mostra
cinco de cinco chamadas concluídas e cinco registros concluídos (Valentina,
Amanda, Luiz, a turma Gustavo/Maria e Arthur). Portanto não havia uma pendência
real, segura e reversível para uma simulação de presença: reabrir ou trocar uma
dessas chamadas para depois apagar por SQL seria falsear uma ocorrência e
contornaria a trilha auditável.

O banco confirma que essas decisões já existem em `public.aluno_presenca` com
origem `professor_la_teacher`; onde o pull chegou, a evidência bruta
`emusys_presenca_bruta='presente'` permanece junto. LA Teacher e LA Report leem a
mesma tabela canônica, portanto a decisão de um aparece no outro ao recarregar —
não existe uma segunda replicação entre os dois sistemas. Isto **não** prova
propagação instantânea do Emusys: `sync-presenca-emusys` continua sendo pull
agendado. Também não existe, neste checkpoint, escrita de volta do LA Teacher
para a API Emusys.

O que ainda não pode ser anunciado como entregue: a interface publicada mostra
somente “Registrar por voz” e “Regravar aula”. O segundo caminho, por ficha
manual/caderno, continua apenas no design
`docs/superpowers/specs/2026-08-12-registro-manual-ficha-individual-design.md`;
não há botão, autosave, cópia ou persistência manual publicados.

Achado aberto da mesma conferência: a fonte de agenda contém múltiplos eventos
brutos para uma mesma faixa/mesma turma de 10/08 em Recreio, enquanto a tela os
agrupa em cinco cards. Algumas linhas canônicas antigas associadas a esses eventos
não trazem `espelhado_de_presenca_id`. Antes de usar um desses pares para teste
de escrita, auditar a chave natural da aula e a relação entre eventos Emusys,
agenda agrupada e presenças; não deduplicar nem corrigir dados históricos no
escuro.

> ⚠️ **HANDOFF PRA OUTRA FERRAMENTA (10/08, noite):** o Alf bateu ~99% da cota
> do Claude Code, só volta quinta-feira (13/08). Ele vai abrir este repo no
> **Cursor** pra continuar. Este arquivo é o prompt de retomada — quem abrir aí
> (Claude ou outro modelo) lê isto primeiro e segue do PRÓXIMO PASSO da seção
> logo abaixo, sem reabrir o que já foi decidido nem repetir trabalho.

> ⚠️ **10/08, tarde: outra sessão minha está rodando em paralelo, no MESMO
> checkout** (não é worktree — ver `CLAUDE.md`, "Duas sessões, o mesmo
> checkout"). Ela já commitou `19528fa` (buraco do relato do Emusys + gêmeo
> com falta escondendo aula, achado no caso da Daiana) e seguiu pra outra
> migration. Se aparecer arquivo novo em `supabase/migrations/` que eu não
> reconheço — **não é lixo, não apago, não commito por cima.** É dela.
>
> _(Nota da outra sessão, 10/08 tarde: sou eu, a da Daiana. O `19528fa` é meu,
> e a frente inteira está na seção logo abaixo. Confirmo o combinado: não toco
> na 081/082 nem no plano do Radar.)_

## ESTADO AUTORITATIVO ATUAL — G7 local concluído; G8 ainda não executado

Em 11/08/2026, a implementação local do recibo canônico foi concluída em
`D:\la-teacher-worktrees\fabio-whatsapp`, branch `codex/fabio-whatsapp`:

- `095-recibo-de-registro-no-whatsapp.sql` e seu teste estático fecham outbox,
  claim filtrável, read-back, lease, replay, contexto outbound e ACLs.
- O worker é o único emissor do carimbo; o bridge não duplica o texto e a
  revisão de devolutiva passa pela RPC auditada.
- O timer foi apenas versionado. `off` é o padrão e bloqueia o claim antes de
  qualquer chamada de transporte; `pilot` exige allowlist explícita.
- Commits locais de G7: `8ea5fa2`, `aa19113`, `93bb675`; o artefato e a
  documentação de G8 local estão no mesmo branch, sem efeito operacional.

O preflight confirmou o projeto correto e saudável. As migrations 093, 094 e
095 foram aplicadas em sequência pelo script definitivo do repositório e
verificadas por consultas de assinatura/ACL; o runner SQL descartável não foi
usado porque aponta para o banco remoto. O backup remoto foi criado em
`/home/fabio/fabio-chat-bridge/backups/20260811-registro-recibo-g8-20260811230107/`.
Os arquivos versionados foram publicados, compilados na VPS e o bridge foi
reiniciado ativo. O timer `fabio-registro-recibo.timer` está habilitado e
executou com `status=disabled`, `claimed=0`, `sent=0`; o banco permanece com
zero recibos pendentes/enviados. Não houve envio WhatsApp nem E2E funcional.
O próximo gate é o piloto E2E restrito, não a expansão.

---

## ✅ Histórico — 10/08-G3 local fechado; 10/08-G4 shadow publicado

No worktree `D:\la-teacher-worktrees\fabio-whatsapp`, branch
`codex/fabio-whatsapp`, a frente local avançou até o fim do 10/08-G3:

- 092 fecha o contrato do reconciliador: `registro_id` no read-back, validação
  do rascunho por professor/áudio, tentativas persistidas e prova de limpeza do
  Storage; a migration 092 foi aplicada em definitivo pelo runner do repositório.
- Reconciliador one-shot com claim/lease, retry limitado, stale-token,
  read-back, expiração e limpeza protegida; unidade/timer systemd versionado.
- Bridge com inbox durável antes do ACK, hidratação depois do claim, modos
  `off|shadow|pilot|on`, allowlist de piloto, interceptação depois do batching e
  antes do Hermes, e CAPACIDADE_PROFESSOR honesta.
- Evidência local fresca: `teste:092`, 5 testes de intenções, 11 de ações, 7 do
  reconciliador, 10 do bridge, 10/10 mutantes mortos, 25 casos de carimbo,
  `py_compile` e `diff --check` verdes.

Commits locais desta sequência: `b4fd73c` (reconciliador/092) e `001c4ef`
(bridge/10/08-G3). O 10/08-G4 foi autorizado e publicado em shadow; o
10/08-G5 (piloto real) e o **10/08-G6 rollout geral** eram os gates seguintes
daquele plano e estão históricos/superados como instrução operacional.

## ✅ Histórico — 10/08-G4 shadow publicado na VPS

O preflight confirmou acesso SSH, Python 3.12.3, bridge antigo ativo e ausência
dos quatro módulos novos. Foi criado backup recuperável em
`/home/fabio/fabio-chat-bridge/backups/20260811-fabio-whatsapp-g4/` contendo o
bridge anterior e o `.env` protegido. A 092 foi aplicada antes do deploy e a
releitura confirmou `registro_id` no retorno de `fabio_status_audio_fila`, prova
de limpeza presente e ACLs apenas para `service_role` nas novas portas.

Na VPS foram publicados `fabio_chat_bridge.py`, os três módulos do fluxo e a
unidade/timer do reconciliador. O modo efetivo ficou
`FABIO_WHATSAPP_REGISTRO_MODE=shadow`; o bridge reiniciou ativo e o timer ficou
habilitado/ativo. O primeiro ciclo do reconciliador terminou com
`claimed=0`, `falhas=0`; não houve erro recente no log do bridge. Os quatro
hashes SHA-256 vivos coincidem com o worktree local.

Snapshot read-only pós-deploy: `fabio_acoes_pendentes=0`, ações ativas `0` e
`fabio_fila_audios.origem='whatsapp'=0`. Portanto: **código e worker publicados;
entrada de escrita continua em shadow; nenhum piloto ou fluxo real foi
executado**. Rollback preservado pelo backup datado e pelo modo `off`.

## ✅ Histórico — 10/08-G5 preparado para teste real, Isaque em pilot

O Alf escolheu Isaque Mendes da Silva (`professor_id=10`) e confirmou dois casos
reais. O primeiro caso sugerido (`202774`) foi rejeitado no preflight porque já
tinha 2 registros e 1 áudio pendente do app. O caso de registro foi substituído
por `202679` (Teclado T, T_Sáb_14, 08/08 14h); o caso de chamada é `202702`
(Violão T, V_Sáb_15, 08/08 15h).

Snapshot imediatamente antes da ativação: as duas aulas continuavam elegíveis;
ambas tinham 0 registros, 0 filas, 0 logs e 0 devolutivas; Isaque tinha 0 ações
ativas. Depois da ativação, a releitura continuou em 0 ações, 0 filas WhatsApp,
0 registros no caso de conteúdo, 0 logs no caso de chamada e 0 devolutivas.

O bridge foi configurado com `FABIO_WHATSAPP_REGISTRO_MODE=pilot` e
`FABIO_WHATSAPP_REGISTRO_PILOT_IDS=10`, reiniciado e confirmado ativo. O timer
do reconciliador continua ativo; o último ciclo terminou com `claimed=0` e
`falhas=0`; não há erro recente no log do bridge. **Nenhuma mensagem real foi
enviada ainda; G5 E2E continua pendente do áudio/texto do professor.**

## ✅ 11/08-G6 — paridade da fonte e configuração mínima do piloto concluídas

Evidência completa: `docs/superpowers/evidence/2026-08-11-registro-aula-source-parity.md`.

- O worktree `D:\la-teacher-worktrees\fabio-whatsapp` começou limpo. A Edge
  ativa `fabio-registro-aula` foi baixada somente para auditoria: versão 17,
  SHA-256 `B3B062BDD86EEF3AA04081A1C7E0DDE3ADCD79F987600BF26E0C90558DE7BF81`.
- A Edge recebe `audio_id`, repassa os identificadores já resolvidos e uma URL
  temporária, e assina o corpo em HMAC. Ela não contém a implementação que
  recebe o callback ou normaliza o registro.
- O callback foi correlacionado com o gateway Hermes de usuário na porta 8644:
  o adaptador Webhook upstream valida o HMAC e entrega a rota dinâmica
  `registro-aula`. O listener não é Nginx nem o bridge de conversa.
- A skill viva foi espelhada em
  `vps/fabio/hermes-skills/registro-aula-audio-la-music/SKILL.md`
  (SHA-256 `145bb5f6cff2bfd3aec753c7a20ddee93481aaff9e0c51e8ea47a82b170427a3`).
  A ferramenta Python viva, que é untracked no checkout Hermes, foi espelhada
  em `vps/fabio/hermes-tools/fabio_registro_aula_tool.py`
  (SHA-256 `c76a3600df7a368c2d9b9a6766e7559dfdaddb035e2c98e79cb167b35efa5e8a`).
- O runtime segue VPS-owned; os espelhos são trilha de auditoria, não origem
  automática de deploy. Em seguida, o G6 operacional alterou somente
  `/home/fabio/.hermes/.env` por substituição atômica: criou backup privado em
  `~/fabio-chat-bridge/backups/20260811-registro-unificado/` e gravou os dois
  flags de recibo. Arquivo e backup foram verificados em `0600`; as chaves de
  recibo ocorrem exatamente uma vez, `recibo_mode=off` e a contagem da
  allowlist copiada é `1`, igual à origem. Valores foram omitidos.
- O bridge permaneceu ativo com o mesmo `MainPID` e timestamp de início. Não
  houve restart, reload ou sinal; os flags só terão efeito em futuro restart
  explicitamente aprovado. A allowlist do piloto não mudou e não houve
  Supabase, Edge, WhatsApp, E2E, dado pedagógico ou mudança de fonte.
- Os comandos `teste:090`, `teste:091` e `teste:092` não rodaram: o runner abre
  transação no banco produtivo e executa DDL/DML antes do rollback, contrariando
  o escopo somente leitura desta tarefa.

**ÚNICO PRÓXIMO PASSO ATIVO DA FRENTE WHATSAPP:** nenhuma nova task está
autorizada. O `11/08-G6 operacional` terminou com o recibo desligado e sem
restart. **G7 continua proibido** até uma nova autorização explícita; o piloto
não expande e não há novo E2E.

## 🧭 DUAS FRENTES ABERTAS AGORA (10/08 noite) — leia as duas antes de escolher

> **Nota somente da frente WhatsApp:** os próximos passos de 10/08-G0/G3 e
> posteriores são históricos/superados. A paridade e o G6 operacional do 11/08
> foram concluídos; G7 segue bloqueado até autorização própria. Esta nota não
> altera o estado da frente do Radar.

1. **Radar do aluno** — backend no ar + telas no ar. Tooltip do score
   organizado (aprovado). **Próximo com calma (combinado com o Alf):** cabeçalho
   único da mesa no desktop (hoje os rótulos FALTAS/ABSENTEÍSMO/… repetem em
   cada linha) — tentativa anterior saiu feia e foi **revertida**; não reabrir
   sem ele. Fechamento do plano (menores do backend) não bloqueia.
2. **Fábio escreve no WhatsApp** — SPEC **aprovada pelo Alf** e plano escrito em
   `docs/superpowers/plans/2026-08-10-fabio-escreve-no-whatsapp.md`.
   10/08-G0/G1 foram concluídos no worktree
   `D:\la-teacher-worktrees\fabio-whatsapp`; 10/08-G2 publicou as migrations
   090/091. A indicação original de seguir para 10/08-G3 e depois 10/08-G4/G5/
   **10/08-G6 rollout geral** é histórica/superada; vale somente o G6
   operacional separado do 11/08, após a revisão de paridade.

---

## ✅ 11/08, ~01h BRT — G2 publicado, WhatsApp novo ainda desligado

**Aplicação definitiva, em ordem, pelo runner do repositório:**

```text
supabase/migrations/090-fabio-whatsapp-acoes.sql       ok
supabase/migrations/091-as-cinco-portas-do-whatsapp.sql ok
```

O preflight imediatamente anterior confirmou o projeto correto, ausência de
drift nos 17 hashes capturados no G0, ausência dos objetos novos e ausência de
conflito com o histórico remoto timestamped. O snapshot pós-aplicação registrou
`2026-08-11 04:02:28 UTC` (`01:02:28 BRT`): as duas tabelas novas estão vazias e
com RLS habilitado; não há grant de tabela para `anon` ou `authenticated`; as
portas `fabio_*` ficaram executáveis só por `service_role`; e as assinaturas
`app_*` permaneceram inalteradas. O `fn_registrar_presencas_core` live contém
`professor_whatsapp` e preserva o sincronizador de gêmeos.

**Hashes live principais (MD5 de `pg_get_functiondef`):**

```text
fabio_aulas_candidatas       2b1b361225e546f936ac2e4e221126a4
fabio_shortlist_valida       583d8d9450c13b9039ff96a356ceb653
fabio_iniciar_acao           95cc0e293c6d89f754de8d1957b757c5
fabio_aplicar_evento_acao    d7068bd8fc6865246fe8e9ff85113696
fn_enfileirar_audio_core     2d2f2a2bd1efd649ebd84e6006f5d005 / 06c2cb7bbabc500696e3b7b5bf3f83c8
fn_atualizar_fatia_core      2035017ce5b98426880703966880034f
fn_responder_presenca_core   0859c37f0f94634abd59dd15a923b61e
fn_confirmar_registro_core   641f9cee39bf5b222a119ef03396610f
fn_registrar_presencas_core  8633fdf54cfe647bf8881dac659d1172
```

**Verificação funcional sem escrita:** chamada ao RPC de candidatas via
`service_role` para um professor existente retornou 21 candidatas, todas com
`aula_id` pertencente ao professor. Não foram criadas ação, evento, blob,
fila, registro, presença ou devolutiva.

**Advisors:** o Security Advisor apontou somente os dois avisos INFO esperados
para tabelas RPC-only com RLS sem policies; como não há grants a `anon`/
`authenticated`, isso não abre leitura direta. O Performance Advisor apontou
índices/FKs novos ainda não usados; fica registrado para revisão antes de carga
real, sem bloquear este gate. O bridge novo não foi publicado: na VPS o serviço
antigo está ativo, mas `fabio_whatsapp_intents.py`,
`fabio_whatsapp_reconciler.py`, `fabio_whatsapp_state.py` e referências às novas
ações estão ausentes. Portanto: **schema published; WhatsApp ingress still off;
no real flow enabled.**

**Histórico: 10/08-G2 fechado.** A indicação de seguir para 10/08-G3 local e
depois para shadow, piloto ou **10/08-G6 rollout geral** está superada; não é
autorização operacional. Vale o G6 operacional do 11/08, separado e pendente
de revisão.

---

## ✅ 10/08 NOITE (Cursor) — tooltip do score organizado (sem tirar informação)

Pedido do Alf: o tooltip do score estava bagunçado (`flex justify-between` com
rótulo+detalhe numa linha e "contribuiu X de Y" na outra, dentro de `max-w-xs`
— quebrava no meio de "aulas"). **Regra explícita:** organizar, mas **não
tirar** nenhuma informação que já estava lá.

Uma tentativa anterior tirou contribuição / agrupou "fora da conta" / mexeu na
mesa inteira — o Alf mandou cancelar e voltar ao `bcf995c`. Esta rodada mexeu
**só** no tooltip.

**O que ficou** (`DecomposicaoNotaTooltip.tsx` + uso em `LinhaRadar`):

- Cabeçalho: `13 · Crítico` (cor do status)
- Cada sinal em **dois andares**: nome | `contribuiu X de Y` (ou `fora da conta`);
  detalhe embaixo (`100% · 2 de 2 aulas` / `professor ainda não respondeu` / …)
- Rodapé: `apurada em 3 de 5 sinais` (+ `· insuficiente` quando couber)
- Largura fixa 300px — acabou a quebra no meio da palavra

**Conferido no preview (sessão de coordenação):** as 5 linhas da decomposição +
cabeçalho + rodapé, todos os textos da versão bagunçada presentes. Alf: _"Ficou
bom."_

**Ainda NÃO feito (deixar pra ele com calma):** cabeçalho único da mesa no
desktop. Combinado que fica melhor; não reabrir sem pedido.

---

## ✅ 10/08 NOITE (Cursor) — o desktop do Radar virou o cartão do celular, com foto

Pedido do Alf depois de aprovar o celular: _"esse componente que você colocou no
celular eu gostei; pode copiar pro desktop? ... tem esses pontinhos embaixo dos
números, não tá legal ... o nome do professor não precisa ser o nome todo ... tem
que trazer a foto dos alunos"_.

**Migration 089 — `a foto do aluno no radar`** (aplicada, `npm run teste:089`
verde, `npm run mutantes:089` **5/5 mortos**):

- `vw_radar_aluno_sinais` ganhou `aluno_foto_url` **no fim da lista** (mesma
  regra que a 088 mediu: `create or replace view` só ACRESCENTA no fim), vindo de
  `vw_aluno_sucesso_lista.foto_url` — a fonte de identidade que a view já usava.
- A RPC manda `foto` em `linhas`. **Medido:** 290 das 311 linhas da coorte têm
  foto; `alunos.photo_url` (a coluna gêmea) está **zerada** e ler ela daria uma
  tela inteira de iniciais sem ninguém notar — é o mutante V1.
- Foto ausente vem **NULA**, nunca `''`: string vazia faz o `<img>` desenhar
  quadrado quebrado em vez de o `Avatar` cair nas iniciais (mutante V3).

**Front (uma árvore de JSX, dois arranjos)** — `LinhaRadar.tsx` deixou de ter um
layout de celular e outro de desktop. As peças são as mesmas (foto, selo da nota,
identidade, células, status) e só a POSIÇÃO no grid muda por breakpoint. Era
assim que o celular ganhava cuidado que o desktop não recebia.

| O que o Alf apontou | O que foi feito |
|---|---|
| "pontinhos embaixo dos números" | `TooltipRadar` perdeu o `underline decoration-dotted`. Podia sair porque a base do número passou a viver no texto ("1 de 2", "100% · 2/2", "enchendo 0/4") — o tooltip virou extra de quem tem mouse, não o único caminho. Confirmado no navegador: `text-decoration-line: none`, `cursor: help`, tooltip ainda abre |
| Nome do professor inteiro | `nomeCurto()` em `src/lib/nomes.ts` — primeiro nome + o sobrenome seguinte, **partícula grudada no que vem depois** (`Letícia de Almeida`, não `Letícia de`), apelido entre parênteses fora (`Rafael Alves Souza (Akeem)` → `Rafael Alves`). Rodado nos 10 professores reais. Vale na linha, no card e no **filtro** |
| Foto dos alunos | `Avatar` do DS na linha e no cabeçalho do card |
| "melhorar essa tabelinha" | selo da nota + foto + pílula de status (`Badge` do DS, não chip novo); números com `tabular-nums`; `avisou que sai · setembro` em vez de `2026-09-01` (`mesDoAno()` em `lib/datas.ts`) |

**Achado no meio do caminho (medido, não previsto):** 11 das 188 fotos da
primeira tela dão **404** no S3 do Emusys — a URL existe no banco, o arquivo não.
O navegador desenhava o ícone de imagem quebrada. `Avatar` agora cai nas iniciais
no `onError` (guarda a URL que falhou, não um booleano, pra se corrigir quando a
prop muda). Depois: **0 quebradas**, 177 fotos + 23 iniciais.

**Conferido ao vivo** (sessão de coordenação, 5183), nos dois temas: **390×844**
(nome numa linha só, status desceu pra baixo do nome, 0 vazamento), **1100**
(faixa `lg`: 3 células — Prática sai entre 1024 e 1279 em vez de espremer as
outras) e **1400×900** (`xl`: 4 células; colunas medidas em 46/54/333/534/67px,
0 vazamento). Clicar no número agora abre o card (o `stopPropagation` das células
saiu junto com os tooltips de faltas).

---

## ✅ 10/08 NOITE (Cursor) — o Radar no celular, e o card do aluno em português

**Regra nova na metodologia** (está em `CLAUDE.md`, seção "Toda tela é desktop E
celular"): tela só é dada como pronta depois de **vista medida em 390×844 e
1400×900**, redimensionando durante a conferência. Esta rodada nasceu de eu ter
entregado o Radar olhando só a janela larga.

**O que estava errado, medido no navegador (sessão de coordenação, 5183):**

| Defeito | Causa | Prova depois do conserto |
|---|---|---|
| Rodapé do card do aluno **debaixo da TabBar** no celular ("ver o mês inteiro" não existia lá) | modal em `z-40`, **o mesmo** da TabBar; empate decide por ordem no DOM | portal pro `<body>` + `z-50`; `elementFromPoint` no link devolve o próprio link, dialog encosta em `y=844` |
| Linha do aluno quebrando em três faixas de rótulo no celular | as 7 colunas da spec em `flex-wrap` | layout de cartão até `lg`, mesa só em `lg+`; dois cards medem 122px iguais |
| A mesa **vazava 235px** pra fora do `<main>` a 820px | sidebar aparece no `md` e come 228px; colunas em px não cabem | corte movido pro `lg` + colunas em `fr` com `min-w-0`; vazamento 0 em 390 / 820 / 1024 / 1298 |
| Texto de banco na tela: `absenteismo`, `pratica`, `2 falta(s) seguida(s)`, `verde`, `Absenteísmo desde 2026-08-01` | a decomposição da nota vem com chave e valor formatados em SQL | `src/features/coordenacao/sinaisRadar.ts` (vocabulário único) + `dataDoDia()` em `lib/datas.ts` |
| Sinal fora da conta mostrando número: "Faltas seguidas · fora da conta" **e** "0 faltas seguidas" | valor era montado sempre, ignorando `sem_dado` | `motivoSemDado()` — "ainda sem aula medida" pro que é medição, "professor ainda não respondeu" pro que é resposta |

**O card virou a nota aberta de verdade:** número grande no selo da faixa, e cada
sinal com **barra de contribuição** (quanto podia valer × quanto trouxe). Sinal
sem dado **não** ganha barra — barra vazia lê como zero, e zero é o que ele não
é (o peso dele foi redistribuído, migration 085). No celular é folha de baixo com
rodapé fixo e `safe-area`; no desktop, diálogo centrado.

Conferido nos **dois temas** (checklist 4 do `frontend-tokens.md`) e o grep de
hex/cor arbitrária em `src/features/coordenacao` volta **vazio**.

---

## ✅ 10/08 NOITE (Cursor) — Radar telas verificadas + shell sem tarja preta

**HISTÓRICO/SUPERADO (10/08):** (1) Na frente do Fábio, a SPEC já tinha sido
aprovada e o plano em gates mandava começar pelo 10/08-G0. Essa instrução foi
superada pelo G6 operacional do 11/08, separado e pendente de revisão. (2) No
Radar, só com pedido dele:
cabeçalho único da mesa no desktop (rótulos hoje repetem por linha; tentativa
anterior revertida). Menores do backend ficam pro fechamento do plano e **não
bloqueiam**. Deploy do que já entrou: Vercel (`f00c96d` em Production) +
migration 089 no Supabase — **nada pra subir na VPS do Fábio** nesta entrega.

**Verificação ao vivo (medido, sessão coordenação = Alf):** preview
`http://localhost:5183` a partir de `D:\la-teacher`. Sidebar desktop Painel ·
Radar · Equipe; KPIs Crítico 62 / Atenção 35 / Avisaram 4 / Absenteísmo 32%;
311 alunos; `—` em Prática/Feedback sem nota; modal com decomposição (3/5
sinais); Réguas com grupo `faltas_consecutivas`; mesa do professor com copy
do escudo.

**Bug de responsividade (tarja preta embaixo ao redimensionar):** causa =
`h-svh` no shell não acompanhava o container do `#root`. Conserto: `#root`
vira coluna flex; `CoordenacaoFrame` e `AppFrame` usam `h-full`/`flex-1`/
`items-stretch`. Medido depois: `gap=0` em 1400×900 e 1000×560; aside preenche
a moldura.

**Clone nested:** apagado (`Test-Path D:\la-teacher\la-teacher` → False).
Workspace canônico = `D:\la-teacher`.

**Commits na branch `feat/radar-telas`:**

| Task | Commit | O quê |
|---|---|---|
| 5 | `67d76e2` | tipos/wrappers em `api.ts` (+ `faltas_consecutivas` da 088) |
| 6 | `6c9fb1d` | mesa, tooltip, filtros, sidebar Radar, rota |
| 7 | `348ddfe` | modal do aluno |
| 8 | `42c4d66` | aba Réguas (grupos dinâmicos, incl. `consecutivas`) |
| 9 | `b6f7233` | copy "isto não é avaliação sua" na `MesaFeedback` |
| docs | `ffeeded`+ | checkpoints RETOMADA / nested |
| fix | (este) | shell `h-full` — some a tarja preta ao redimensionar |

---

## ✅ 10/08 NOITE — Radar do aluno: backend completo (Tasks 1-4 + 10)

**Telas (5–9):** feitas na Cursor — ver seção acima.

**Backend no ar, testado e revisado, commits em `main`:**

| Migration | O quê | Commits |
|---|---|---|
| 081 | View `vw_radar_aluno_sinais` (1 linha/aluno, 5 sinais + base de cada) | `b79aa26`+`107d4e6`, ampliada pela 088 |
| 082 | Tabela `radar_config` (pesos/faixas, editável) + RPCs de config | `e709135` |
| 085 | `fn_radar_nota(sinais, config)` — função pura, pontua + decompõe | `b473259`+`442edb0` |
| 087 | `app_coordenacao_radar(...)` — RPC da tela (guard, filtros, resumo) | `ffc43ad`. **Não é 086** — esse número foi tomado por outra sessão no mesmo checkout (`086-o-gemeo-para-de-divergir-na-escrita.sql`), renumerado |
| 088 | 5º sinal: **faltas consecutivas** (ponderado, não atropelo) | `42d713a`+`a0b3c96` (fix round) |

**Por que virou 5 sinais em vez de 4 (decisão do Alf, no meio do trabalho):**
rodar a Task 4 contra os 311 alunos reais mostrou 242 já com nota, mas só 13
professores tinham respondido o semáforo — dois dos quatro sinais originais
(absenteísmo da janela, faltas do mês) nascem da MESMA tabela de presença e
cobrem quase a mesma janela em agosto, então acendiam juntos com 1 aula
medida, sem entrada nenhuma do professor. Decisão dele: não travar a nota até
o professor participar — trocar por um sinal mais robusto pra dado escasso:
**contagem bruta de faltas seguidas**. Mapeamento: até 1 falta seguida pontua
saudável (100), 2 pontua atenção (50), 3+ pontua crítico (0) — é sinal
PONDERADO (peso próprio, entra na mesma redistribuição dos outros 4), não um
`if` que atropela a conta.

**Fase B, explicitamente adiada** (não é bug, é escopo cortado por decisão
dele): Fábio avisar o professor proativamente com 2 faltas seguidas ("fala
com ele, manda um exercício"), e escalar pro grupo da coordenação com 3+.
Fica pra depois, provavelmente junto da tarefa já pendente "generalizar o
worker da devolutiva em máquina de avisos ao professor".

**Rigor aplicado em cada tarefa** (documentado pra quem for confiar nisso):
TDD (teste antes do código), mutantes obrigatórios (todos morrendo), revisão
de código dedicada por tarefa (`superpowers:code-reviewer`), e — depois de
achar bug em 5 pedaços de SQL que eu mesmo escrevi nesta sessão sem testar
antes (`greatest(0,NULL)` que devolve 0 não NULL, `#>` que não detecta jsonb
null onde `#>>` detecta, agregado aninhado que o Postgres recusa) — toda SQL
nova nas tarefas mais recentes foi testada por `SELECT` direto em produção
ANTES de entrar em qualquer arquivo de migration.

**Achado sério na Task 10 que quase passou batido:** o fix round da revisão
corrigiu o arquivo certo, mas a função corrigida nunca tinha sido REAPLICADA
no banco — `rodar-teste-sql.mjs` só faz BEGIN/ROLLBACK, nunca commita de
verdade, e ninguém tinha rodado o passo de aplicar depois do fix. Descobri
comparando `pg_get_functiondef` (o que está rodando) contra o arquivo (o que
deveria estar rodando) — divergiam. Apliquei manualmente
(`088_a_falta_seguida_e_o_quinto_sinal_fix_revisao`) e reconferi. **Lição pra
quem continuar:** depois de QUALQUER correção em SQL de migration, confirmar
que ela foi de fato reaplicada em produção — não basta o arquivo estar certo
nem o teste passar (teste roda em transação descartável).

**Menores registrados pra revisão de branch inteira** (não bloqueiam; Tasks
5–9 das telas **já estão no ar** — ficam pro Fechamento do plano):
- `faltas_consecutivas` na view não é limitado pela janela de 10 aulas
  (diferente de `aulas_medidas`) — aluno com 15 faltas seguidas mostraria
  "15" ao lado de "10 aulas medidas". Só o texto fica incoerente, o score não.
- Sem validação que `faltas_consecutivas_atencao < faltas_consecutivas_critico`
  na config (mesmo buraco pré-existente em `faixa_critico`/`faixa_saudavel`).
- Sinal com peso=0 na config ainda conta pro piso de sinais apurados —
  "desligar" um sinal pela régua ainda empurra alunos pra cima do mínimo.
- A migration 081 não roda mais numa bateria automática "limpa" (só via
  mutantes) — consequência de `create or replace view` recusar tirar coluna,
  marcada com `-- SUPERADA POR: 088-...` no próprio arquivo.

**Checkout compartilhado, ainda vale:** duas sessões Claude Code trabalharam
no MESMO checkout esta tarde/noite (não worktrees separadas — ver `CLAUDE.md`,
seção "Duas sessões, o mesmo checkout"). A outra tratava do incidente da
Daiana (seção logo abaixo). Regra pra quem continuar, mesmo sozinho agora:
`git status`/`git fetch` antes de mexer, `ls` no disco antes de numerar
arquivo novo (não confiar só em `git log`), nunca `git add -A`/`.`/`-a`.

---

## ✅ 10/08 TARDE — a professora Daiana usou o Fábio de verdade, e ele mentiu

O Alf mandou ela ser intensa no WhatsApp pra ver o que quebra. Quebrou muito, e
todo o conserto está no ar: `19528fa`, `d6a603e`, `9a957ab`, `fe89f2c`, `36c05ab`.

**O incidente, medido linha a linha contra o banco.** Em 08 e 10/08 ela mandou
**8 áudios** de conteúdo pedagógico. O Fábio respondeu *"deixei o registro
organizado e salvo"*, *"confirmado: o Eduardo compareceu"*, *"vou considerar a
ausência do Anderson"*. **Escritas de verdade: 1 de 8** (a da Beatriz, em 08/08,
`aula_registros_fabio_log` id 71). Sete relatos perdidos com ela achando que
estavam salvos.

⚠️ **A causa fui eu.** Em 09/08 fechei a fronteira (`api_server` =
`skills_leitura, memory, todo, vision, no_mcp`). **Tirei as mãos dele e não
tirei a boca.** Antes disso o `api_server` não tinha restrição nenhuma — por
isso a Beatriz de 08/08 gravou de verdade e a de 10/08 não gravou nada.

| # | Defeito | Conserto | Prova |
|---|---|---|---|
| 1 | Carimbava escrita que não existia, mandava pro "suporte do app" (não existe) e prometia "fila de validação de presença" (não existe) | bloco `CAPACIDADE_PROFESSOR` no `build_prompt`, **só** no canal do professor | 5 casos conversando: recusa + caminho no app + **texto pronto pra colar**; "quem é a Lara?" segue completo; agenda em 1,0s sem ruído |
| 2 | Janela de 3 dias trancava e o cadeado só dizia "Encerrada" | **7 dias**, com `fn_janela_registro_dias()` como dono único (eram **5 cópias** do número) | 084: 10 passos, **8/8 mutantes** |
| 3 | A cobrança aceitava o **plano do Emusys** como relato (1.609 aulas) e perdia aula quando o gêmeo-âncora dizia falta (572 pares discordam) | 083: só `anotacoes_fabio` conta; presença resolvida entre os gêmeos | 11 passos, **8/8 mutantes**; 502 → **704** aulas cobráveis |
| 4 | A auditoria das 7h disse *"✅ Tudo certo"* no dia disso tudo | `check_promessa_vs_banco` (novo), governança de 1 → **43** professores, e "nenhum registro em 24h" virou alerta | pegou o caso: *"🤥 professor 3 (2 carimbos, 0 escritas)"* |

**Efeito prático da 083+084:** a escalação usa a **mesma régua da janela** — até
7 dias é do professor, depois é da coordenação. Primeira leitura honesta:
**20 professores, 98 aulas** passadas do prazo.

⚠️ **Armadilha que me pegou de novo** (a mesma da 076): `v_erro = '...'` com
`v_erro` nulo devolve NULL, e `count(*) where not ok` **não conta a linha** —
três mutantes sobreviveram imprimindo verde. Consertado na raiz: `is not
distinct from` nas asserções e `not coalesce(ok,false)` no contador da 083 **e**
da 084. Asserção que não sabe responder agora é FALHA, nunca aprovação.

### ▶ O material dela foi RECUPERADO pelo motor do app (`36c05ab`)

Os **áudios originais ainda estavam na UAZAPI**. Nada foi recriado: baixei os
mesmos bytes, subi pro bucket `fabio-audios` na convenção do app e enfileirei —
daí em diante foi o motor de sempre (trigger `trg_fabio_fila_novo` → Hermes →
`aguardando_confirmacao` → `app_confirmar_registro`).

**6 registros gravados nos alvos certos, 2 ausentes pulados, presença nas 4
aulas, 6 devolutivas enfileiradas. Pendência da Daiana: 4 → 0.**

⚠️ **O motor errou onde o Emusys já estava contaminado.** Na aula de 05/08 16h
marcou **Júlia e Clara como ausentes** — as duas estiveram lá. O Whisper do
Hermes saiu bem pior que o do WhatsApp no MESMO áudio ("Vileardo"; "vogais
C,S,X,J" por consoantes Z,S,X,J; "aquecimento B,B,A,O" por bilabial; "das
Sicilinas" por CeCe Winans). Corrigi antes de confirmar — que é o que a tela de
confirmação oferece ao professor —, cada edição com fonte na fala dela.

✅ **RESOLVIDO na raiz, mesma tarde (`40d0814`, migration 086).** O buraco
acima não era só da Sofia e do Eduardo — era estrutural: `fn_registrar_presencas_core`
sempre escreveu só na aula-âncora, e o gêmeo individual ficava com o que o
Emusys mandou por último. Medido antes de mexer: **59 das 61** respostas
fortes já existentes tinham o gêmeo divergindo ou vazio. Não era exceção, era
a regra — e ia **multiplicar a cada professor novo**, exatamente o alerta do
Alf: *"resolver na raiz, antes de partir pra SPEC."*

Conserto: `fn_sincronizar_gemeos_presenca(aula_id default null)` — propaga
resposta forte pro gêmeo, com a MESMA trava que já protegia a âncora (nunca
apaga resposta humana forte já existente). Chamada **escopada** ao final de
toda `fn_registrar_presencas_core` (o defeito não nasce mais) e **sem escopo**
uma vez na migration, como backfill. 11 passos, **5/5 mutantes** (um mutante de
propósito NÃO escrito — apagar a linha de backfill é intestável neste harness,
mesma limitação já documentada na migration 068; prova é medição direta:
**59 pares divergentes → 0**, 61 → 120 escritas fortes).

### ▶ A Beatriz também precisou de reprocesso (`4f9fbfe`)

Medido depois do 086: o registro dela (a ÚNICA das 8 que tinha "escrito de
verdade" em 08/08) **nunca passou pelo motor**. Era de quando o Fábio ainda
tinha o MCP de banco — ele chamou `registrar_aula_fabio` **direto**, texto
corrido, sem `fabio_registros_aula`, sem campos estruturados, sem devolutiva.
"Ele escreveu" e "ele escreveu do jeito certo" são checagens diferentes; eu só
tinha feito a primeira.

Reprocessado pelo mesmo áudio original, mesma via, com
`app_confirmar_registro(id, 'substituir')` — a aula já tinha `anotacoes_fabio`
(o texto bruto), então `'novo'` seria recusado. `aula_registros_fabio_log`
guarda as duas entradas (não apaga, acumula): `novo/texto` em 08/08,
`substituir/áudio` agora. Duas correções antes de confirmar, mesmo critério das
outras 4 (a "dificuldade no controle do fluxo de ar" tinha virado "Objetivo"
genérico; a fatia veio sem `presenca` — o áudio só descreve conteúdo).

**Presença aplicada nos DOIS gêmeos na MESMA escrita** (`gemeos_sincronizados:
1`) — a 086 funcionando ao vivo pela primeira vez em produção. Pendência da
Daiana: **0**.

### ▶ Brainstorming e SPEC aprovados; plano em gates escrito

`docs/superpowers/specs/2026-08-10-fabio-escreve-no-whatsapp-design.md`.
Escopo: registro de aula por áudio + chamada avulsa, sempre com leitura-e-
confirmação antes de gravar (o professor confirma ou corrige, nunca grava
sozinho), miolo único com duas portas nas RPCs (`app_*` continua em
`auth.uid()`, `fabio_*` nova recebe `professor_id` explícito resolvido pelo
telefone). **Decisão que fica registrada pra quem revisar:** o LLM não ganha
NENHUMA ferramenta de escrita nova — toda a orquestração (gatilho, qual aula,
chamar a RPC) é código determinístico no bridge, mesma lógica que já protege o
`CAPACIDADE_PROFESSOR` de virar promessa vazia (ver memória
`allowlist-de-ferramenta-vence-aprovacao`). Fora do escopo, anotado no spec:
pedido de liberação de prazo à coordenação e correção pós-confirmação.

**HISTÓRICO/SUPERADO desta frente (10/08):** executar o 10/08-G0 do plano para
consolidar estes docs, criar worktree próprio e congelar o contrato vivo antes
de extrair qualquer miolo. As passagens produtivas 10/08-G2 (banco),
10/08-G4 (shadow na VPS), 10/08-G5 (piloto) e **10/08-G6 rollout geral** não
são próximos passos ativos; o único é o G6 operacional do 11/08, separado e
pendente de revisão.

---

## ✅ 10/08 MADRUGADA — a parede das 9h caiu, e o Radar ganhou spec

**O deploy entrou.** O `062bc96` tinha ficado sem build; o commit vazio `2fd58ed`
destravou. Produção agora é `index-TsNOqwLF.js` e tem os filtros da 079, o
`total_lista` da 080 e o `end` da sidebar — conferido no bundle servido, não no
painel da Vercel.

**Escalonamento (`146a593`, no ar na VPS).** Medido antes de mexer: a mensagem
única tinha **20.951 caracteres e 1.032 linhas** (os 51 KB anotados eram o JSON,
não o texto), e ela é entregue mesmo — `escalonamento_enviado`, 33 professores
em 09/08. Agora são 4 mensagens: índice de **421 chars** + uma por unidade
(CG 7.252 · Recreio 7.585 · Barra 3.496). Duas decisões que o dado forçou:

- **o professor vai inteiro pra uma unidade** (a que tem mais aula parada), não
  fatiado — 13 dos 36 dão aula em mais de uma, e como a RPC corta em
  `p_max_aulas=12`, fatiar deixaria o rodapé "+N aulas" sem dono;
- **o detalhe é racionado, não cortado** — bloco inteiro pros 8 mais atrasados
  de cada unidade, uma linha pros demais. Ninguém some.

37 asserções, **9/9 mutantes mortos**. Verificado em dry-run contra os 36 reais;
nada foi ao grupo.

**`Description=` das units:** corrigido nas três (manhã, noite, briefing) — não
dizem mais "piloto Matheus, professor 25". ⚠️ O **nome** da unit do briefing
segue `fabio-briefing-matheus.service` e ela atende 6 professores, não 1;
renomear mexe em timer vivo e não valia a madrugada.

### ▶ RADAR: spec escrita em `docs/superpowers/specs/2026-08-10-radar-do-aluno-design.md`

Três medições derrubaram coisas que a direção aprovada dava como certas:

1. **As duas réguas de "dias sem presença" nunca discordaram.** A
   `vw_aluno_sucesso_lista` faz join na própria `vw_absenteismo_aluno`: mesma
   coluna, **0 divergências**. O que diferia era a população (1.509 × 1.113). A
   anotação de 08/08 estava errada nisso.
2. **Desde 09/07 cada aula real vira 2 linhas** em `aluno_presenca` — 1.840 de
   3.148 horários, e as 1.850 duplicatas diferem **100% no `aula_emusys_id`**
   (id de EVENTO, não da aula). Contar linha crua dobra qualquer falta.
3. **"Sumiu da escola" não sai na Fatia 1.** Sem duplicata, 126 alunos têm 2+
   faltas seguidas e **nunca** foram marcados presentes na janela; 97 tiveram
   aula na semana de 03/08 com **zero presenças**, enquanto a escola rodou a
   **68%**. Estão concentrados em **CG** (10 das 12 primeiras linhas, 28–50% da
   carteira do professor). É registro, não aluno.

Fatia 1 vira: **"Ligar essa semana"** (crítico × renovação = **2** hoje),
**"Avisou que sai e ainda está em aula"** (**33**, vive da linha ADM porque só
17 acham par na base ativa) e **"Coração vermelho"** (semáforo + health_score
lado a lado, nunca somados). As três perguntas do semáforo viram a *frase do
porquê* dentro do cartão — é ali que elas ganham leitor.

**Decidido pelo Alf em 10/08 (navegação):** o Radar é **página própria** e vira
a **porta do aluno**. A sidebar segue com **três** itens — `Painel · Radar ·
Equipe`. A tela de Feedback não muda em nada: só deixa de ser item de menu e
passa a ser o "ver o mês inteiro" do cartão *Coração vermelho*. Não virou bloco
2 do Painel (ideia original de 08/08) porque o Painel é da equipe e o Radar é do
aluno — empilhar num scroll só é a mesma mistura da parede das 9h.

**Decidido pelo Alf em 10/08 (risco de evasão):** *"esconde até o modelo estar
seguro"*. Fui medir o que isso exclui — **as 1.157 linhas de
`vw_risco_evasao_atual` estão em `confianca_dado = 'baixa'`**, nenhuma exceção,
e o motivo escrito na própria view é *"Modelo em auditoria: as features de
presenca ainda misturam falta com chamada nao registrada"*. É o mesmo defeito
que eu medi. A regra tira a fonte inteira do ar, e com ela o cartão "Ligar essa
semana".

**Achado no mesmo puxão:** o `health_score` é **30% pagamento** (+ 20% tempo de
casa, 20% fase, 20% feedback, 10% presença). Usar ele como "coração vermelho"
põe situação de pagamento na tela da coordenação, lavada em cor — fura a
fronteira da inadimplência pela porta dos fundos. **Saiu do Radar.**

**Fatia 1 virou DOIS cartões:** "Avisou que sai e ainda está em aula" (33) e
"Coração vermelho" só com o semáforo do professor (0 hoje; enche a partir de
hoje). Os dois **não dependem de presença nem de pagamento** — de propósito.

⚠️ **A alavanca mudou de lugar.** Os três sinais que caíram (Sumiu da escola,
Ligar essa semana, health_score) caem na MESMA raiz: **registro de presença**.
Não são três problemas, é um aparecendo em três telas. Consertar o registro de
CG deixou de ser a pendência nº 3 e virou a tarefa de maior alavanca aberta.

**PRÓXIMO PASSO:** o Alf revisa a spec inteira. Depois dela, plano e execução.

---

## ✅ 09/08 NOITE — o Fábio perguntava "amanhã" e respondia "hoje" (CONSERTADO)

Achado conversando, não lendo código: `"como esta minha agenda de amanha?"` →
**"Matheus, não encontrei aulas na sua agenda de hoje."** Era domingo (0 aulas);
na segunda ele tinha **5**. Quem se planeja com isso chega achando que não tem
aula — e "não encontrei aulas" é **negativa afirmada**, o pior formato pra estar
errado.

A causa não foi o parser errar o dia: **parser não existia.** No `try_fast_response`,
`asks_today` aceitava `"minhas aulas"` e `"minha agenda"` — frases que não falam
de dia nenhum — como prova de que a pergunta era sobre hoje. Todo dia pedido caía
em hoje, e ainda saía rotulado "de hoje".

O `fabio_contexto_professor` **sempre soube servir outro dia** (`p_data`, e devolve
o dia servido em `hoje.data`). A capacidade existia; o atalho é que não usava.

**Contrato agora: ou o atalho sabe QUAL dia foi pedido, ou ele se cala** e a
pergunta segue pro Hermes. Resolve hoje/amanhã/depois de amanhã/ontem/anteontem,
dia da semana, "dia 12", dd/mm. Se cala em: período ("da semana", "do mês"), dois
dias na mesma frase, dia da semana igual ao de hoje (ambíguo), data impossível.

Três travas que o caso pediu:
- o rótulo carrega a data resolvida (`"terça (11/08)"`) — leitura errada fica
  **visível** pro professor em vez de silenciosa;
- se o RPC devolver dia ≠ pedido, o atalho se cala e loga `fast_path_dia_divergente`;
- `"quantos alunos eu tenho"` sem dia voltou a ser **carteira** (20), não contagem
  da agenda de hoje — número certo pra pergunta errada.

Conferido contra o banco, não contra a minha leitura: 09/08=0 ✓, 10/08=5 ✓,
11/08=6 ✓, 12/08=0 ✓. Teste `vps/fabio/teste_agenda_dia_pedido.py` (16 asserções)
com **4 mutantes mortos** — inclusive o bug original reintroduzido. Commit `168aff8`,
no ar (md5 repo = VPS, serviço `active`).

⚠️ **Buraco que fica aberto (não é este bug, é vizinho):** o `build_prompt` chama
`professor_context(professor_id)` **sem data** — o Hermes só recebe a agenda de
HOJE. Então o caminho normal também é cego pra outro dia: perguntado sobre "dia 12"
ele respondeu, com honestidade, *"ainda não tenho a agenda do dia 12 aqui"*. O
atalho agora cobre os dias que sabe ler; o que cai pro Hermes cai cego. Passar o dia
resolvido pro prompt é o próximo passo natural dessa frente.

---

## ✅ 09/08 NOITE — a observação do professor ganhou leitor

Ordem do Alf, depois de eu propor deixar pra depois: *"Nada! Os professores já
vão começar a vir amanhã e vão começar a já responder! Tem que fazer agora!"*

**O buraco:** o campo da mesa convida com *"Algo que vale a coordenação saber"*
e, medido por grep no `src` daqui **e** no do LA Report, a coluna `observacao`
não era lida por **ninguém**. A coordenação via só cumprimento (quem respondeu,
no Painel Farmer e na cobrança da 076) e o coração diluído em 20% do
`health_score`. As três perguntas não iam a lugar nenhum.

**No ar** (`f13485f`, migrations 077 e 078 aplicadas em produção):

| O quê | Onde | Prova |
|---|---|---|
| `app_coordenacao_feedback_mes` — resumo + quem precisa de olho | 077 | 11 passos verdes, **8/8 mutantes**; em prod: 1.160 alunos, 43 professores, Barra 260 · CG 487 · Recreio 413 |
| Tela `/app/coordenacao/feedback` (3º item da sidebar) | `CoordenacaoFeedback.tsx` + `LinhaSemaforo.tsx` | **falta screenshot ao vivo** — preciso de sessão de admin no preview |
| O Fábio LÊ o semáforo (3 competências, só as do próprio professor) | 078 | 7 passos verdes, **5/5 mutantes**; o V2 guarda a fronteira |
| Gatilho `estado_aluno` no prefetch do bridge | `vps/fabio/fabio_chat_bridge.py` | conversando: citou o desânimo e propôs "ir com leveza"; sem a linha, não inventou |

**Quem entra na lista:** vermelho, amarelo, **ou qualquer coração com recado
escrito**. Verde calado fica fora — lista que devolve a escola inteira é a mesma
parede de texto do escalonamento diário. Corte em 200 que sempre se anuncia.

**Três coisas que só apareceram porque eu abri e conversei, não porque o teste
estava verde:**

1. O mutante **V7 sobreviveu** (filtro de unidade). O código estava certo; o
   TESTE é que tinha os 3 alunos na mesma unidade — ignorar o filtro não mudava
   nada. Consertei o teste com uma isca de outra unidade.
2. `[prefetch] nao acionado`: **"como está a Amanda?" não casava com gatilho
   nenhum**. A pergunta mais natural do professor sobre o dado mais fresco que
   existe. O gatilho novo é FRACO de propósito — quando só ele acende e ninguém
   é resolvido pelo nome, o prefetch devolve `None`, senão "como está minha
   agenda" injetaria bloco de aluno em toda conversa (provado: `nao acionado`).
3. O dict do prefetch **escolhe chaves a dedo**, e o comentário dele avisa isso
   em voz alta — *"TODO bloco novo precisa ser adicionado aqui à mão, senão é
   silenciosamente descartado"*. Eu li o aviso e caí nele: a RPC devolvia
   `semaforo`, com teste e mutante provando, e o dado morria antes do prompt.

### Segunda rodada, com o Alf olhando a tela (`062bc96`, migrations 079 e 080)

*"Achei animal, tá aprovado"* — e três ajustes na sequência:

- **Sidebar grifava dois itens ao mesmo tempo.** `NavLink` sem `end` acende por
  PREFIXO, e `/app/coordenacao` é prefixo de `/app/coordenacao/feedback`.
- **079 — filtros de coração e professor.** Escolher um coração TROCA a regra da
  lista (grupo inteiro, verde calado incluído), não só o recorte; `sem_resposta`
  é um coração de verdade; cada faceta ignora o próprio filtro e respeita as
  outras. 9 passos, **8/8 mutantes**.
- **080 — um número só.** O KPI dizia `0 de 1155` e a lista, na mesma tela,
  `1161`. O grão aqui é **(aluno, professor)** — quem faz aula com dois
  professores é respondido por cada um. Quem estava certo era o 1161: somar as
  43 mesas dá pares. **É o mesmo defeito das duas contagens de manhã, voltando
  pela porta dos fundos.** 5 passos, **4/4 mutantes**.

Pilotado ao vivo como admin, com 5 respostas de teste (apagadas, tabela em 0):
`Saudável` → mostra o verde calado · `Sem resposta` → 1161 nos três lugares ·
`professor Matheus` → "4 de 21", e **21 é exatamente o que a mesa dele mostra**.

**Aberto:** o LA Report continua sem ler a observação (lá o semáforo é só o
coração no health score).

---

## 🔴 09/08 MADRUGADA — VÉSPERA DE AULA: o que foi consertado e o que falta

O Alf, no domingo à noite: *"a gente tem que corrigir tudo que tiver quebrado.
Amanhã já tem aula. A gente tem que fechar esse buraco inteiro."*

**Consertado e no ar** (`e08bfc9`, `043ab52`, `2693d21`, tudo em `origin/main`):

| # | Defeito | Estado |
|---|---|---|
| 1 | **Áudio da observação aceitava qualquer coisa que o cliente dissesse** (ver a correção logo abaixo — a explicação da "extensão" que eu vinha dando estava ERRADA) | função lê os BYTES e reembrulha; `transcrever-observacao` **v4** no ar, 6/6 casos verdes |
| 2 | **✓ verde mentia** — `setEstado` antes da RPC, `catch` não desfazia | `confirmado` separado de `estado`; alerta clicável que reenvia e **vence** o ✓ |
| 3 | **Dois números da mesma carteira** — 5 dos 6 professores com login viam contagens diferentes (Rafael 57 × 51) | chips contam aluno; a causa NÃO era arquivamento (a view já exclui: 0 em 1.221) **nem aluno em dois cursos** (só 1 na escola inteira) — é **renovação de contrato**, 54 linhas a mais em 26 professores. Ver "onde eu estava errado" abaixo |
| 4 | **O Fábio não sabia o que é o Feedback do mês** e inventava "pesquisa sobre sua rotina" | seção nova na skill; provado conversando (6,3s, correto), sem ruído e com a fronteira de pé |
| 5 | **A cobrança nunca parou de cobrar o que já subiu pra coordenação** | `dias_atraso`/`atraso_dias` × chave real `dias_em_atraso` — filtro morto desde sempre |

**O defeito 5 é a resposta ao medo do Alf** ("amanhã não sai todo esse monte de
coisa atrasada deles"). Não sai mais:

| Professor | Cobrança de antes | Depois |
|---|---|---|
| Rafael | 29 aulas / 11 dias | **10 / 3** |
| Lohana | 27 / 12 | **9 / 3** |
| Leonardo | 11 / 11 | **1 / 3** |
| Daiana | 3 / 5 | **1 / 2** |
| Rodrigo | 1 / 5 | **nada** |

### ❌ ONDE EU ESTAVA ERRADO (medido pilotando o app, não deduzido)

**1. O microfone do iPhone provavelmente nunca esteve quebrado.** Eu vinha
afirmando em duas sessões que *"o Whisper decide pela extensão do arquivo"*.
Nunca medi. Mandando um AAC/MP4 real pra função em produção:

| bytes | Content-Type | nome | resultado |
|---|---|---|---|
| mp4 | ausente | `.webm` | **502** |
| mp4 | ausente | `.m4a` | **502** |
| mp4 | `audio/mp4` | `.webm` | **200, transcreveu** |
| mp4 | `audio/webm` (mentindo) | `.webm` | **502** |

Quem manda é o **Content-Type da parte multipart**. O cliente já mandava
`audio/mp4` no `blob.type`, então o iPhone caía na linha que dá 200. O
conserto do nome foi higiene, não conserto de defeito vivo.

**O que ERA defeito:** a função acreditava no que o cliente dizia. Blob sem
`type` chega como `application/octet-stream` (então `if (arquivo.type)` nunca
vê "vazio"), e um `type` pode mentir. Agora ela lê os **bytes** (magic number)
e reembrulha. Os 4 casos que davam 502 dão 200. **v4 no ar.**

**2. "Aluno em mais de um curso" estava errado.** São **54 linhas duplicadas
em 26 professores**, e só **1** aluno na escola está em dois cursos com o
mesmo professor. É **renovação de contrato**: a matrícula encerrada e a nova
convivem. Pilotando, a Amanda aparecia duas vezes em Canto — "40/40 concluída"
e "Aula 2/40" — e a linha velha, sem `emusys_aluno_id`, ganhava selo "cadastro
incompleto" num cadastro completo. Corrigido em `agruparPorCurso`.

**A lição das duas:** eu escrevi mecanismo plausível em vez de medir, e o
plausível entrou no commit, no RETOMADA e no que eu disse pro Alf. Um teste
que só confirma o resultado esperado não falsifica nada — o que achou os dois
erros foi **abrir o app e olhar**.

### ⚠️ O que foi MEDIDO e desarma dois sustos

- **Ligar o timer do feedback hoje não manda nada.** `fn_feedback_cobranca_do_dia`
  devolve fase `nenhuma` para 09/08 e 10/08; a primeira cobrança existe só em
  **25/08**, com os 6 elegíveis. A janela (`fn_janela_feedback_aberta`) está
  **fechada**.
- **A cobrança de registro JÁ roda** — não começa amanhã. Os 5 receberam hoje
  08:30 e ontem 20:50 (`fabio_notificacoes`, status `enviada`). As units
  `fabio-pendencia-manha/noite` **não** restringem mais ao professor 25; só a
  `Description=` do systemd é que ficou dizendo "piloto Matheus".

### ✅ PILOTADO AO VIVO como o Matheus (o Alf logou; eu não digito senha)

Percorrido no navegador, com dado de produção:

- **Home** — o card "Feedback do mês" NÃO aparece, correto: a janela só abre na
  última semana.
- **Alunos** — chips `Todas 21 · Campo Grande 15 · Recreio 6` (15+6=21, fecham),
  Canto 15→14 depois do dedupe, Amanda uma vez só e sem o selo falso.
- **Mesa** — 21 alunos, blocos "você deu aula" / "não viu", 0/21.
- **Coração vermelho** → as 3 perguntas abriram → respondidas → **✓ verde e
  barra 1/21**. Conferido no banco: `vermelho / nao / parado / desanimado`.
- **Observação** digitada → gravou junto.
- **Limpo depois:** a linha era invenção minha num aluno real, numa tabela que
  a coordenação lê. `delete` feito, tabela de volta a **0 linhas**.

**O que não deu pra fazer:** gravar áudio pela interface — o navegador do
preview não tem microfone. Em vez disso testei o caminho de verdade: gerei uma
fala, converti pro formato do iPhone (AAC/MP4) e mandei pela sessão do Matheus
direto na função. Foi assim que os dois erros acima apareceram.

### Ainda aberto

- **Fila offline no feedback.** O registro de aula tem; o semáforo não. Hoje a
  falha é **honesta** (alerta + reenviar), mas o trabalho se perde se o
  professor fechar o app. Não é urgente pra amanhã — a janela só abre em 25/08.
- ~~**O escalonamento manda 36 professores numa mensagem só**~~ — **RESOLVIDO em
  10/08** (`146a593`): virou índice + uma mensagem por unidade. Ver a seção do
  topo.
  ⚠️ Cuidado ao remedir: `fn_pendencias_escalonadas()` devolve **UM jsonb**, não
  uma linha por professor. `select count(*) from fn_pendencias_escalonadas()` dá
  **1** — eu caí nisso. O número está em `jsonb_array_length(→'linhas')`. E o
  tamanho da MENSAGEM não é o do JSON: 20.951 chars contra 51.327.
- ~~**`Description=` das units de pendência mentem**~~ — **RESOLVIDO em 10/08**
  nas três units. Fica só o **nome** da unit do briefing
  (`fabio-briefing-matheus.service`), que atende 6 professores e não 1.
- **O LA Report não lê a observação.** Lá o semáforo entra só como o coração,
  valendo 20% do `health_score` (`calcular_health_score_aluno`); as três
  perguntas e o texto do professor só têm leitor no LA Teacher (077).
- ~~**A tela nova só foi vista no preview local.**~~ — **NO AR em 10/08**:
  bundle `index-TsNOqwLF.js` com os marcadores da 079/080 e o `end` da sidebar,
  conferidos no bundle servido. ⚠️ Tem service worker registrado: quem já abriu
  o app pode ver a versão velha até atualizar. Se um professor jurar que não vê
  o "Feedback do mês", a primeira coisa é fechar e reabrir, não caçar bug.

---

## 🧭 POR ONDE COMEÇAR (duas frentes abertas — atualizado 10/08 ~22h)

Este arquivo tem seções de datas diferentes e mais de uma diz "próximo passo".
A ordem verdadeira, **hoje**, é esta (a tabela antiga que dizia “faltam Tasks
5–9” estava errada — as telas já entraram):

| # | Frente | Onde parou | Seção |
|---|---|---|---|
| ~~1~~ | ~~Semáforo do professor~~ | **FECHADO em 09/08 à noite.** Banco (073–080), mesa do professor, tela da coordenação, cobrança no timer, e o Fábio lendo. O texto abaixo desta tabela é HISTÓRIA — não reabrir | ✅ |
| **1** | **Radar do aluno** | **Backend + telas no ar** (Tasks 1–10). Foto na linha (089, `bcf995c`); tooltip do score organizado (`f00c96d`, Alf aprovou). Deploy = **Vercel Production + Supabase** — **VPS do Fábio não entra** nesta frente. Próximo só com pedido do Alf: cabeçalho único da mesa no desktop (não reabrir sozinho). Menores do backend não bloqueiam | topo deste arquivo + seções ✅ da noite 10/08 |
| **2** | **Fábio escreve no WhatsApp** | **Histórico/superado:** plano de 10/08 (`10/08-G0` até `10/08-G6 rollout geral`) já avançou até piloto restrito. A paridade de fonte do 11/08-G6 foi registrada; o único passo ativo é o **G6 operacional**, separado e pendente de revisão. Não retomar G0/G3 antigos | topo deste arquivo + evidência 11/08-G6 |
| 3 | **Fila offline no feedback** | O ✓ é honesto (alerta + reenviar), mas o toque se perde se o app fechar. Janela abre 25/08 | "Ainda aberto" |
| ~~4~~ | ~~Parede de texto do escalonamento~~ | **FECHADO em 10/08** (`146a593`): índice + uma mensagem por unidade, 9/9 mutantes | seção do topo |
| 4 | **Registro de presença em Campo Grande** | **NOVO, medido em 10/08:** 126 alunos com 2+ faltas seguidas e zero presença afirmada, concentrados em CG (28–50% da carteira de alguns professores). É o que segura o cartão "Sumiu da escola" do Radar | spec do Radar, §3 |

**Fechado em 09/08 e que NÃO deve ser reaberto:** a fronteira do Fábio (o
professor não alcança dado de colega nem SQL — virou canal, não prompt), o
`skill_manage` fora do canal do professor, o incidente da edge function do LA
Report, e os dois "achados abertos" que eram decisão técnica minha
(DEFAULT PRIVILEGES e a porta 8644 — os dois avaliados e encerrados).

---

## ▶ FRENTE 1 — SEMÁFORO DO PROFESSOR (os 2 bloqueadores caíram; falta o carteiro)

> O título antigo era *"revisão final NÃO aprovou"*. Continua valendo como
> história — o relato dos dois bloqueadores está logo abaixo, palavra por
> palavra, porque a lição de *como* eles passaram por 7 revisões é o que
> importa. **Mas os dois já foram resolvidos pela 076**; o estado medido está
> no fim desta seção.

**DECISÃO DO ALF, 09/08:** sobre o B2 — *"Precisamos incluir isso na spec e no
plano de implementação, porque tem que ter, senão a sua governança fica pela
metade."* A coordenação **entra**. Não é escopo deferido.

Spec e plano reabertos em `c6b8c95`:
- **Task 8 — migration `076-o-carteiro-da-cobranca.sql`** (mata B1 e B2 no
  banco): `fn_feedback_cobranca_do_dia` (leitura pura, diz a fase e quem cobrar),
  `fn_reservar_cobranca_feedback` (professor) e
  `fn_reservar_cobranca_feedback_coordenacao` (grupo); quarto ramo no
  `chk_notificacao_destinatario` para `destinatario_tipo='coordenacao'`
  (`professor_id` nulo + JID em `destinatario_whatsapp`); dois índices de dedupe
  — **o da coordenação NÃO pode incluir `professor_id`**, que é nulo ali e em
  índice único do Postgres nulos não colidem; e a
  `fn_enfileirar_cobranca_feedback` **cai** (era o depósito sem coletor).
  Commit `9ae8da0`, aplicada em produção, verificada ao vivo.
- **Task 9 — o worker leva**: evento `feedback` no
  `fabio_notification_worker.py`, no mesmo desenho do `escalonamento` (unit
  systemd própria + `--force`). **O gatilho nasce DESLIGADO** — ligar o timer é
  o momento em que os professores passam a receber WhatsApp, e é palavra do Alf.
  Commits `357717f`, `ea33269`, `8c864b1`.

### ⚠️ O alcance real é 6 professores, não 43 (medido em 09/08)

Eu venho repetindo "43 professores" — inclusive na frase que o Alf leria pra
decidir se liga o timer. Está errado, e o erro é grande:

| Corte | Quantos |
|---|---|
| Professores com carteira | **43** |
| …ativos | 43 |
| …**com `usuario_id`** (login liberado no painel) | **6** |
| …e com WhatsApp | 6 |

A cobrança filtra `p.ativo and p.usuario_id is not null` **de propósito** —
cobrar quem não consegue abrir a tela é o jeito mais rápido de ensinar o
professor a ignorar o Fábio. Consequências práticas:

- A primeira mensagem à coordenação vai dizer *"X de 6 professores fecharam"*,
  e a coordenação tem 43 na cabeça. Ou avisa antes, ou o denominador vira a
  primeira coisa que eles descobrem sozinhos.
- Os Importantes de tela abaixo (contagem dupla, ✓ verde que mente, microfone
  no iPhone) valem pra quem abre o app — **6 hoje**, 43 quando o painel liberar
  o resto.
- Liberar mais professores no painel de equipe **aumenta o alcance da cobrança
  automaticamente**. Não tem lista paralela pra manter.

**Decisão de arquitetura que ficou:** **não existe `pg_cron` nesta entrega.** O
banco só responde *quem cobrar hoje* e *reserve esta linha pra mim*; quem decide
a hora é o timer e quem manda é o worker. Enfileirar pra alguém buscar depois
briga com a própria tabela — `status` não tem estado de entrada.

**Régua ancorada no FIM DO MÊS, nunca em dia da semana** (isto também estava
errado na spec): lembrete em `último−6`, reforço em `último−3`, coordenação no
dia 1º. Em agosto/2026 a janela é 25/08 (ter) a 31/08 (seg), então "a quinta"
cai no 27 e "a segunda" no 31 — o reforço chegaria **antes** do lembrete.

### O que a revisão da Task 8 pegou (rodada de correção em andamento)

- **Mutante V4 morria de erro de sintaxe, não da asserção.** Duas causas
  independentes: `String.replace` trata `$$` no texto de substituição como
  escape para um `$` literal (o corpo `$$…$$` vira `$…$`, delimitador inválido),
  e o Postgres recusa renomear parâmetro nomeado. A cerca do `lease_token`
  estava **sem medição** e o mutante imprimia "morto".
- **Asserção NULL contava como PASS.** Subquery escalar sobre `pg_constraint`:
  se a constraint sumir, retorna NULL, `not NULL` é NULL, e a linha não entra
  no `count(*) where not ok`. A garantia da tabela compartilhada passava
  justamente quando a constraint não existia.
- **`on conflict do nothing` sem recuperação** — decisão minha, corrigida para a
  forma da 018: worker que morre entre reservar e enviar deixava a linha presa
  em `processando` e a cobrança do mês não acontecia. A 066 podia usar
  `do nothing` porque é disparo humano, refazível; aqui são 3 dias por mês.

**A régua que fica:** *o que a spec promete tem que ter uma task com o **verbo**
da spec.* "Entrega à coordenação" não vira "insere na fila". Revisão contra o
plano nunca acharia — o plano estava sendo cumprido.

---

### O diagnóstico original (histórico)

**B1 — a fila da 075 é depósito sem coletor.** A 075 insere em
`fabio_notificacoes` com `status='processando'` + lease, esperando que alguém
reivindique depois. **Ninguém varre essa tabela.** O `fabio_notification_worker.py`
tem 3 tipos fixos (`briefing_matinal`, `pendencia_registro`,
`pendencia_escalonada`), decide pelo relógio e chama `fabio_claim_notificacao`,
que **cria** a linha já reivindicada. O `on conflict` dessa função é restrito a
`tipo in ('briefing_matinal','pendencia_registro')` — um `feedback_lembrete`
não casa, então quem for plugar o envio toma **23505** contra o índice novo da
075. E o cabeçalho da própria 066 já dizia: *"não há caixa onde o painel
deposite um recado pra alguém levar depois"* — o padrão da casa é
RESERVA → envia → CONCLUI na mesma chamada. A 075 faz só a primeira.

**B2 — a coordenação não recebe nada.** A spec diz *"Dia 1º: entrega à
coordenação a lista de quem não fechou"*. O código insere
`destinatario_tipo='professor'` com um texto **para o professor**. A coordenação
não aparece em lugar nenhum da 075. O erro nasceu no plano e por isso atravessou
as sete revisões.

**Importantes, antes de os professores abrirem** (6 hoje, ver o corte acima)**:**
- **Dois números da mesma carteira**: `Alunos.tsx` mostra o array cru de
  `app_minha_carteira` (grão matrícula, sem filtrar arquivado); a mesa colapsa
  por aluno e tira arquivado. **26 dos 43 professores veem contagens
  diferentes**, diferença de até 6. O card leva de uma tela pra outra.
- **O ✓ verde mente**: `setEstado` acontece antes da RPC e o `catch` não desfaz.
  Rede ruim = 52 ✓ verdes, barrinha em 0/52, nada salvo. E o registro de aula
  tem fila offline; este não tem.
- **O microfone falha em todo iPhone**: o cliente manda nome fixo
  `observacao.webm`, mas o `useRecorder` grava `audio/mp4` no iOS — e o helper
  `extensaoDoMime()` já existe no repo e não foi usado. O Whisper decide pela
  extensão.

**Maior carteira real: 52 alunos** (professor 33), e são **43** professores com
carteira — não 38/44 como o plano supunha.

**Das duas decisões humanas pendentes, uma caiu:** a `transcrever-observacao`
foi publicada (v1, commit `140807e`, outra sessão) e o incidente da edge
function do LA Report está fechado. **Resta uma:** ligar o timer da cobrança —
`systemctl --user enable --now fabio-feedback.timer` na VPS. É o instante em
que os professores passam a receber WhatsApp (6 hoje).

### ✅ ESTADO REAL, medido em 09/08 à noite (o que mudou depois do texto acima)

Os dois bloqueadores **foram resolvidos** — não reabrir:

- **B1 e B2 → migration 076** (`076-o-carteiro-da-cobranca.sql`), e ela está
  **aplicada em produção**. Conferido consultando o banco, não o `git log`:
  `fn_feedback_cobranca_do_dia`, `fn_reservar_cobranca_feedback` e
  `fn_reservar_cobranca_feedback_coordenacao` existem; a
  `fn_enfileirar_cobranca_feedback` (a que enfileirava sem coletor) **foi
  derrubada**; e o CHECK já é
  `['professor','comercial','coordenacao']`.
- **`transcrever-observacao` PUBLICADA** (v1, `verify_jwt: true`) em 09/08.
  Era uma das "duas decisões humanas" e não é mais. O Codex do LA Report já
  tinha restaurado a `transcrever-audio` na v34, então os deploys não se
  cruzaram. Detalhe no bloco do incidente, mais abaixo.

**O que sobrou de verdade — e é o clássico "banco pronto, ninguém entrega":**
o `fabio_notification_worker.py` **não sabe cobrar feedback**. Os tipos dele
são `briefing_matinal`, `pendencia_registro` e `pendencia_escalonada` — não
existe `feedback`. E **não há timer nem cron** pra isso (conferido em
`systemctl --user list-timers` e em `cron.job`). Ou seja: a 076 fez o banco
responder *"quem cobrar hoje"* e *"reserve esta linha"*, mas ninguém pergunta.
**Esse é o próximo passo desta frente**, e não "agendar o cron" — o cabeçalho
da própria 076 explica por que um cron enfileirando seria errado.

## ▶ FRENTE 2 — RADAR DO ALUNO (bloco 2 do painel — decidido 08/08, noite)

> Era o "PRÓXIMO PASSO" em 08/08. Em 09/08 o semáforo voltou pra frente da fila
> (ver "POR ONDE COMEÇAR" no topo). Isto aqui segue **decidido em direção e sem
> spec escrita** — nada aqui foi invalidado, só não é o primeiro da fila.

O Alf escolheu o Radar e deu o tom: *"painel estratégico de gestão pedagógica —
se coloca no lugar dos coordenadores"*. Antes de tela: **brainstorm + spec**
(regra da casa). As FONTES já foram medidas, todas vivas:

| Sinal | Fonte | Medido 08/08 |
|---|---|---|
| Coração do aluno (❤️ que existe e ninguém usa) | `alunos.health_score` | saudável 684 · atenção 637 · **crítico 106** · sem 199; **1.181 atualizados em 30d** |
| Risco de evasão | `vw_risco_evasao_atual` | baixo 969 · atenção 143 · **crítico 45** |
| Renovação chegando | `vw_jornada_marcos` (`perto_renovacao`) | **102 alunos** |
| Inadimplência | `aluno_jornada_matricula_disciplina.inadimplente_emusys` | 44 — **NUNCA aparece pro professor** (fronteira dura do Alf) |
| Aviso prévio | `movimentacoes_admin` **`tipo = 'aviso_previo'`** | **CONFIRMADO 08/08**: 128 no total, **33 com `mes_saida` ainda à frente** (a janela em que dá pra salvar), 30 avisos em 60d. Tem professor, unidade, nome e motivo em 33/33 |
| Faltas seguidas | `aluno_presenca` fonte forte | régua a definir no spec — **mas a base forte é de 24 alunos** (ver abaixo) |

Desenho aprovado em direção (não em tela): seção "Radar do aluno" com CARTÕES
DE SINAL — contagem + os casos mais urgentes + a AÇÃO que o sinal pede ("liga
essa semana": risco crítico × renovação próxima é o cruzamento de ouro). Não é
lista de alunos; é curadoria.

**Trilho paralelo que ele também pediu:** o Emusys NÃO é legado — normalizar as
anotações pro formato canônico e alimentar o histórico do aluno (o app do
professor já puxa histórico; o Fábio consome). A 072 provou que a anotação é
legível; o trilho é a normalização.

### O MAPA COMPLETO (Alf, 08/08 madrugada): Health Score v2, 14 sinais

Ele mostrou o módulo Sucesso do Aluno do LA Report (Fabiola + Jéssica; a agente
Lia coleta o semáforo do professor por link WhatsApp; mesa com Health/Risco/
Fase/Presença/Pagamento) e o doc "Health Score v2 — 14 sinais". O que NÃO pode
se perder:

- **Regra de ouro deles: peso não se chuta** — o score manual antigo provou
  (os "Atenção" evadiam MAIS que os "Crítico"). Quem aprende peso é o modelo.
  → O Radar **NUNCA fabrica score composto**: mostra dimensões e aponta a
  conversa humana. Restrição de spec.
- **"Cada um no seu quadrado"** (anti-over-engineering por dono, não por corte):
  Sucesso do Aluno fica com conversas ADM (1), NPS (3), inadimplência (7),
  responsável (13), perfil de matrícula (12). A COORDENAÇÃO fica com o
  pedagógico: semáforo do professor (2), jornada/estagnação (5), absenteísmo
  (6), **dias desde a última aula (9 — o sinal mais forte do modelo deles:
  ativo ~6d, evadido ~34d)**, anamnese × expectativa (10), pratica em casa (4),
  sinal contínuo do Fábio (14). Ciclo contratual (11) é o "quando" dos dois.
- **Proatividade usa o trilho que JÁ existe** (fila do Fábio + edge, provados
  na 066): sinal → painel / Fábio no professor / grupo. Não nasce sistema novo.
- **Fatia 1 proposta ao Alf**: 3 cartões — "Ligar essa semana" (risco ×
  renovação), "Coração vermelho" (106 críticos do semáforo, com a observação
  do professor), "Sumiu da escola" (dias sem aula). Inadimplência FORA do
  Radar da coordenação.
- Ponte futura anotada: a coleta do semáforo (hoje link avulso da Lia que
  expira) pode virar nativa no app do professor / Fábio. É fatia, não agora.

### MEDIDO DEPOIS (08/08, madrugada): o que muda no cartão "Sumiu da escola"

Fui confirmar as fontes que faltavam antes do spec. Três achados que mudam o
desenho — todos medidos, nenhum de memória:

1. **Aviso prévio existe e está vivo.** O campo certo é `tipo`, não a coluna
   `emusys_aviso_previo_id` (essa é 0/1700 — nunca foi preenchida; foi ela que
   me fez escrever "0" ontem). São **33 avisos com saída ainda à frente**, e a
   linha já traz professor + unidade + motivo. É cartão de primeira: o aluno
   avisou que sai e **ainda está em aula** — é a última janela pedagógica.
2. **Costurar esse aviso ao aluno do LA Teacher é frágil.** Dos 33 abertos,
   **21 não acham par** por `alunos.emusys_student_id` e **5 caem em ID
   ambíguo** (o mesmo `emusys_student_id` em pessoas diferentes — a colisão que
   já está registrada). O cartão tem que viver do nome/professor da própria
   linha ADM, não de um join que finge precisão.
3. **"Dias desde a última aula" NÃO pode sair da presença forte do LA Teacher:**
   a base forte inteira é **40 registros, 24 alunos** (piloto). Existe pronto
   no LA Report: `vw_absenteismo_aluno` (`dias_sem_presenca`, 1.509 linhas) e
   `vw_aluno_sucesso_lista` (1.122). **As duas discordam** — ≥14 dias dá 693 ×
   403; ≥30 dá 456 × 187. Escolher uma é decisão de spec, e a divergência
   precisa de explicação antes de virar cartão.

**A armadilha do recesso (a mais importante).** O histograma de
`dias_sem_presenca` tem um buraco exato entre 13 e 22 dias. Não é dado sujo, é
o calendário: `aulas_emusys` mostra a semana de **20/07 sem NENHUMA aula** e a
de 27/07 com 185 (contra ~2.100 das semanas normais). Teve **recesso de duas
semanas**. Ou seja: em agosto **todo mundo ganha ~15 dias de "sumiço" de
graça**, e os 693 "há 14 dias sem presença" são, em maioria, férias.

→ Regra pro spec: o cartão conta **aula perdida** (aula que existiu na agenda e
o aluno não veio), não dia de calendário. É a mesma lição da 072 — número que
parece acusação e é artefato. Um cartão "sumiu há 22 dias" publicado agora
mandaria a coordenação ligar pra escola inteira.

## ✅ INCIDENTE 09/08 ENCERRADO: a edge function do LA Report que eu sobrescrevi

Um subagente meu publicou `transcrever-audio` no projeto compartilhado e
**sobrescreveu a função homônima do LA Report** — a que transcreve áudio do
WhatsApp via UAZAPI e grava em `crm_mensagens.transcricao`, usada no chat de
pré-atendimento (`ChatPanel.tsx:502`). Ela existia desde 13/02, na versão 33.

- ✅ **Restauração CONFIRMADA:** o Codex do LA Report republicou. `transcrever-audio`
  está na **v34**, `ACTIVE`, com o corpo deles (UAZAPI `/message/download` →
  `crm_mensagens.transcricao`) e entrypoint `/2026/LA-performance-report/…`.
  O pré-atendimento voltou.
- ✅ **Nosso lado NO AR (09/08, noite):** `transcrever-observacao` **v1**,
  `verify_jwt: true`. Estava pendente esperando a restauração acima, e nesse
  meio-tempo o cliente já apontava pro nome novo (`api.ts:1421`) — ou seja, a
  gravação por voz da observação estava **quebrada**, não só "não publicada".
  - Portões antes de publicar: `git grep` do nome nos 3 clones (só o LA Report
    tem `transcrever-audio`/`transcrever-mensagem-evasao`, nenhum tem o nome
    novo) + `list_edge_functions` no projeto **compartilhado**, que é o passo
    que faltou da primeira vez.
  - Prova depois: **114 → 115 funções, exatamente 1 nova, 0 alteradas, 0
    removidas** (diff das listas antes/depois), e a do LA Report parada na v34.
    Sem token → **401**; `Bearer` inventado → **401**.
  - ⚠️ A primeira versão dessa checagem deu "NENHUMA alterada" a partir de
    **conjunto vazio** — a raiz do JSON é `{"functions": […]}` e eu li `data`.
    Comparação que não acha nada nunca acusa diferença: `assert` na lista antes
    de comparar.
- **Causa raiz:** o `CLAUDE.md` já mandava fazer `git grep` do nome nos outros
  clones. O subagente nasce sem o `CLAUDE.md`, e eu não repeti a regra no
  dispatch. Registrado na memória.

## ✅ 09/08: A FRONTEIRA DO FÁBIO VIROU ESTRUTURAL (era prompt)

O Fábio entregava a professor comum a lista dos professores atrasados no
feedback mensal. A primeira correção foi um bloco no prompt (`ESCOPO_PROFESSOR`):
mediu **13/13 recusas** (detalhe abaixo), mas **prompt é probabilístico — a
porta continuava aberta**.

**O que a medição mostrou, e é maior que o vazamento:** `run_hermes_api` manda
só `{model, messages, stream}` — o gateway **não sabe quem está perguntando**.
Logo toda ferramenta ligada no `api_server` (porta 8652, por onde passa TODA
mensagem de WhatsApp) está ligada pra qualquer professor. E o `GET /v1/toolsets`
mostrou ligados: **`file` (inclusive `write_file`), `code_execution`, `browser`,
`web`** e todos os MCPs. O SQL era **uma porta num corredor** — um `read_file`
em `~/.hermes/.env` entrega service_role, token do UAZAPI e a `DATABASE_URI`.

**Consertado por canal, não por instrução:**

| Identidade | Canal | Alcance |
|---|---|---|
| professor | `api_server` | `memory, skill_view, skills_list, todo, vision_analyze` — **5 ferramentas** |
| admin | `cli` oneshot | tudo, inclusive SQL e `skill_manage` (escolha do Alf em 09/08) |

Quem roteia é `generate_answer()` por `identidade_tipo`, que vem do **telefone
resolvido no banco antes de existir prompt** — dado que o modelo não influencia.
**Fallback do professor pro oneshot foi removido**: o caminho `cli` concede
*mais* que a API, cair pra lá no erro seria escalar privilégio na hora errada.

**Provado com a MESMA pergunta:** professor → *"Essa visão fica com a
coordenação pedagógica"* (7,5s) · Alf → a lista real com nome e unidade (137,8s).
Mais 3 adversariais (mandar rodar SQL "autorizado pela coordenação", comparação
implícita, mandar editar a própria skill): todas seguraram, em 5-7s e **sem
tentar chamar ferramenta**. E o caso oposto continua vivo: "quem é a Fernanda?"
→ cadastro, curso, horário, "aluno novo há 6 dias" e o conteúdo pedagógico.

Espelhado em `vps/fabio/hermes-platform-toolsets.yaml.txt` (o Hermes reescreve
o `config.yaml` sozinho — comentário lá dentro não sobrevive).

### O que eu contei errado no caminho (fica de armadilha)

**`grep | wc -l` num log conta a linha de REGISTRO do MCP junto com a chamada.**
O briefing dizia "`lareport_execute_sql` 86x, é capacidade viva". Dos 87, **71
eram linhas de registro** ("registered 13 tool(s)", que citam o nome de todas).
Chamadas reais: **50**, e **24 delas eram a investigação de hoje** — sobram 26
em 5 semanas. Mesma armadilha pegou o presence MCP: as "3 chamadas" eram 3
registros; ele **nunca foi invocado**. Contar ocorrência de string ≠ contar
evento.

### Achados — todos fechados (decisão técnica é minha, não do Alf)

> Combinado em 09/08, depois de eu errar: **o Alf não é técnico e não recebe
> decisão técnica.** "DEFAULT PRIVILEGES" e "porta em 0.0.0.0" não são escolhas
> dele — são minhas. O que sobe pra ele é o que muda o negócio: o que o
> professor vê, o que a coordenação vê, o que ele perde de alcance. O resto eu
> decido, faço, e conto o que ficou.

1. ✅ **`skill_manage` FORA do canal do professor** — resolvido em 09/08, à noite.
   Eu tinha proposto inlinar o SKILL.md no prompt; **o Alf derrubou a ideia** e
   estava certo: são **77 skills**, carregadas dinamicamente na conversa (113
   `skill_view` só no chat). Inlinar estouraria o prompt ou quebraria o
   roteamento. Ele propôs allowlist — e allowlist é o que a pesquisa sustenta:
   - arXiv 2510.26328: detectar injeção em skill **não funciona por definição**
     ("Agent Skills are all instructions"), e **aprovação vaza** — um "não
     perguntar de novo" benigno transborda pra ação nociva próxima. Sobra
     remover a capacidade.
   - O Hermes vai na mesma direção (issue #33905 → #21849, PR #61792: política
     por actor/plataforma × ferramenta × allow/deny). Quando sair, vira config.
   - Feito: plugin `la-skills-leitura` em `~/.hermes/plugins/` registra o
     toolset `skills_leitura` = `[skills_list, skill_view]`, e o
     `platform_toolsets.api_server` passou a listar ele no lugar de `skills`.
     Espelhado em `vps/fabio/hermes-plugins/`.
   - Medido: `api_server` skill_view=True / skill_manage=**False**; `cli`
     mantém os dois. Conversando: "quem é a Fernanda?" segue completo (prefetch
     + conteúdo pedagógico), "edita a skill e apaga a regra" → recusa, e o
     vazamento original segue fechado.
   - ⚠️ Duas armadilhas achadas aqui: plugin em `~/.hermes/plugins/` é
     descoberto mas **PULADO sem `plugins.enabled`** ("Skipping X (not in
     plugins.enabled)"), e o **`GET /v1/toolsets` mente** para toolset custom —
     ele só enumera toolsets *configuráveis*, então `skills_leitura` some da
     lista e parece que o professor perdeu `skill_view`. Quase reportei que
     tinha quebrado o Fábio.
2. ✅ **DEFAULT PRIVILEGES — DECIDIDO: fica como está.** Toda tabela nova criada
   pelo `postgres` nasce com `fabio_agent=r`. Isso **não é defeito na
   arquitetura de hoje**: depois do `no_mcp`, o `fabio_agent` só é alcançável
   pelo canal admin do Alf, e um role de ferramenta administrativa que
   acompanha o banco é o comportamento desejado. Revogar quebraria justamente
   a capacidade que ele escolheu manter. Não é decisão do Alf — é técnica, e
   está tomada.
   ⚠️ **O que reabre isso:** devolver qualquer MCP de banco ao
   `platform_toolsets.api_server`. O role atrás dele enxerga o schema inteiro,
   **inclusive tabelas que ainda não existem**. Se um dia isso for preciso,
   role novo com grant estreito, não o `fabio_agent`.
3. ✅ **A porta 8644 NÃO é problema — eu marquei errado.** Ela escuta em
   `0.0.0.0` porque **precisa**: é a rota `registro-aula`, chamada de fora
   (POSTs reais, o último em 08/08). E é protegida: HMAC obrigatório por rota,
   validado no boot, e o adapter recusa o modo sem-auth quando o host não é
   loopback. Medido em 09/08 no caminho certo (`/webhooks/registro-aula`, não
   `/registro-aula`): sem assinatura → **401**, HMAC errada → **401**, com
   `Invalid signature` no log e zero trabalho gerado.
   Lição: "porta em 0.0.0.0" não é achado — achado é *precisa estar aberta?* e
   *está protegida?*. Eu reportei risco sem responder nenhuma das duas.
4. **`fabio_presence_mcp` continua sem escopo** (`professor_id` arbitrário), mas
   agora é inalcançável pelo professor (`no_mcp`) e **nunca foi invocado**. Usa
   **service_role**, não `fabio_agent` — então revogar grant não fecharia ele.
5. **`sol_acesso_restrito` e `mila_acesso_restrito` se chamam "restrito" e veem
   375 objetos** — o nome mente. Só `lia_acesso_restrito` (103) é de fato
   estreito. Não é do Fábio, mas é do mesmo banco.
### DE ONDE VEIO — o incidente, e o que a mitigação de prompt mediu

Achado testando ao vivo depois da Task 7 (regra do CLAUDE.md). Perguntado por
um **professor comum** (id 25, Matheus), o Fábio respondia quem estava atrasado
no feedback mensal — **nome, mês, unidade e nº de alunos** de colegas. Ramon
(31) e Peterson (33) são reais: não era alucinação. **É anterior à 075** — a
migration só me fez olhar.

- **Causa raiz:** `~/.hermes/config.yaml` → `mcp_servers.lareport` é um
  `postgres-mcp --access-mode=unrestricted` com o role `fabio_agent`, que tem
  `SELECT` em **374 objetos** e **`rolbypassrls = t`**. SQL arbitrário na escola
  inteira, sem nenhum filtro por quem perguntou. O role só existe nesse MCP (os
  workers usam service role), então os grants dele governam exatamente uma
  superfície: o SQL ad-hoc do agente.
- **Não havia regra em lugar nenhum** — nem `SOUL.md`, nem `PERMISSOES.md`, nem
  nas 6 skills. O freio era o humor do modelo: **2 em 5** respostas vazavam
  nome+número pra mesma pergunta, com `--sem-historico`.
- **Mitigado (commit `0b1d561`, no ar):** bloco `ESCOPO_PROFESSOR` condicional
  no `build_prompt` (só `identidade_tipo=professor`; admin intocado) + bullets
  na skill `chat-fabio-la-music`. Medido depois: **13/13 recusas** — 6/6 na
  pergunta original, 3/3 em variantes de contorno, 4/4 perguntando por colega
  **pelo nome** (o vetor que a outra sessão achou). Carteira, feedback próprio,
  prontuário e check-in seguem respondendo: não virou muro.
- ~~**A fronteira continua ABERTA.**~~ **RESOLVIDO na mesma noite** — ver a
  seção acima. Duas coisas que estavam escritas aqui eram falsas e vale saber
  por quê: **(1)** "toolset por identidade exige mexer no Hermes" —
  `platform_toolsets.api_server` já era suportado e testado upstream, era chave
  de config; **(2)** "`lareport_execute_sql` 86x, é capacidade viva" — 71
  daquelas linhas eram registro do MCP, não chamada. O custo estimado da opção
  mais simples estava inflado por `grep | wc -l`.
- **Buraco irmão:** `fabio_presence_mcp.py:34` expõe
  `fabio_buscar_presencas_pendentes_professor(professor_id)` com `professor_id`
  **arbitrário**, sem checar quem chamou. Hoje inalcançável pelo professor
  (`no_mcp`) e nunca invocado. Correção ao que estava escrito: ele usa
  **service_role**, não `fabio_agent` — revogar grant nunca teria fechado.
- ⚠️ **A edição da skill não tem espelho no repo** (só o bridge tem, em
  `vps/fabio/`) — vive só na VPS. E o `.skills_prompt_snapshot.json` carrega
  descrições, não o corpo: quem segura de fato é o bloco do `build_prompt`.
  Continua valendo, e agora o `config.yaml` também tem espelho
  (`vps/fabio/hermes-platform-toolsets.yaml.txt`) — a skill não.

## ▶ DECIDIDO 08/08 (noite): O SEMÁFORO NASCE NO APP DO PROFESSOR

O Alf tirou isso de "ponte futura" e botou no radar, com pedido explícito de
salvar aqui pra não perder. **A percepção do professor passa a ser coletada
DENTRO do app dele** — não mais pelo link avulso da Lia que expira.

O que ele pediu, na letra:

- **Mora no app do professor.** "Não fica o link, já fica ali dentro, já vai
  aparecer ali." O link que expira sai de cena.
- **O componente já existe no LA Report** — a barrinha, "exatamente igual a
  gente já tem". **Trazer e ADAPTAR**: a estrutura vem de lá, os tokens são os
  nossos. Copiar o CSS de lá é criar Design System paralelo (erro já cometido
  duas vezes nesta sessão).
- **Coração vermelho / amarelo / verde por aluno**, e **justificativa
  obrigatória em QUALQUER cor** — inclusive no verde. O porquê é o dado; a cor
  sozinha é só uma bolinha.
- **Perguntas do feedback**: estuda em casa, e as demais do formulário atual do
  LA Report (levantar quais na spec).
- **Pode responder por ÁUDIO.** Trilho já provado na casa: fila de áudio +
  worker (050/051) e o registro por voz da experimental. Não nasce sistema novo.
- **Governança: a última semana do mês é a semana de feedback do aluno.** O
  Fábio lembra o professor — mesmo trilho de cobrança da 066.
- **É um mapa de sinais**: o que o professor responde aqui é a fonte nativa do
  cartão "Coração vermelho" do Radar da coordenação. Fecha o laço — hoje a
  coordenação olharia um semáforo coletado por fora.

Ordem que ele deu: **primeiro o professor preencher dentro do app**, depois a
governança da semana com o Fábio lembrando.

### O QUE EU MEDI ANTES DE DESENHAR (e corrige o que eu tinha dito)

- **`aluno_feedback_professor` está VAZIA.** Zero linhas. O formulário do link
  da Lia existe, tem 3 sessões criadas, e nenhum professor respondeu um aluno.
  `alunos_health_score_historico` também: zero.
- Os **107 "críticos"** que eu te mostrei **não são o coração do professor** —
  são `calcular_health_score_alunos_batch`, score calculado por máquina, com
  vocabulário próprio (saudavel/atencao/critico) e `health_score_updated_by`
  nulo em 100% dos alunos.
- **`calcular_health_score_aluno` LÊ `aluno_feedback_professor`**, com peso em
  `config_health_score_aluno`. Como a tabela é vazia, **o pilar pedagógico do
  score sempre valeu zero.** O score que "falhou" (os Atenção evadindo mais que
  os Crítico) rodava com pagamento, tempo, fase e a presença que a 012 provou
  ser 4.254 verdes falsos — sem a única coisa que só o professor sabe.
- Existe `calcular_health_score_aluno_v2_sombra` com `confianca`, `cobertura` e
  `modelo_pronto` — alguém já começou a versão honesta. Descobrir de quem é.
- O link da Lia **nunca rodou de verdade**: era manual (mandar no WhatsApp na
  mão) e hoje não se manda mais. Está de enfeite. Não é trabalho de desligar.

### DECIDIDO NO BRAINSTORM (Alf, 08/08 madrugada — modal a modal)

| Decisão | O que ficou |
|---|---|
| Áudio | **Complemento**, não substituto. Coração + justificativa por aluno; áudio opcional pra detalhar um caso. (Eu vou desenhar a obrigatoriedade como cumprível por texto **ou** áudio.) |
| Onde mora | **Permanente dentro de Alunos** + **card na Home na última semana do mês** + lembrete do Fábio no WhatsApp com percentual e o porquê ("tá chegando a renovação", "pra evitar evasão") |
| Quem entra na mesa | **Toda a carteira, separada em dois blocos**: "você deu aula pra esses" × "esses você não viu" (com dias). Quem sumiu é justamente quem mais importa |
| Fronteira do texto cru | Coordenação e Fábio leem **cru**. **NUNCA** sai pro aluno/responsável nem pra devolutiva. **Trava no BANCO**, não na tela |
| Escopo v1 por aluno | Coração + justificativa + **3 perguntas**: pratica em casa · está evoluindo · ânimo. (Expectativa × anamnese fica pra depois) |
| Onde grava | **`aluno_feedback_professor`** — a tabela que o score já lê. *"Não cria duas verdades."* As 3 perguntas novas viram colunas nela. Peso chutado é **dívida a pagar no LA Report**, não motivo pra tabela paralela |
| Governança | **Salva a cada toque** (38 alunos × 4 campos: botão Salvar no fim é convite a perder trabalho). Fábio lembra segunda da última semana, de novo quinta, e dia 1º quem não fechou aparece pra coordenação — escada da 066 |

### REQUISITO NOVO: MAPA DE ADERÊNCIA (pedido do Alf no meio do brainstorm)

*"A gente vai plantar uma cultura, e isso vai demorar."* Ele quer **medir a
adesão** dos professores às coisas que alimentam o mapa de sinais — semáforo
preenchido, **aluno sem anamnese**, registro de aula — **com evolução no
tempo**: *"começou com 50%, agora 60%, agora 70%"*. E disse que **os
coordenadores gostam muito disso**.

É **fatia própria** (painel), não entra na spec da coleta. Mas a coleta tem que
**deixar o número calculável** desde o dia 1: respondidos / carteira, por
professor, por competência.

## ▶ PASSO ANTERIOR (concluído em 08/08 — não é "esta sessão")

**UI v2 do painel da coordenação** — pedido do Alf em 08/08, à noite, olhando o
painel no ar e o de Professores do LA Report lado a lado: *"esse formato
tabelona, assim um negócio meio tabela, meio Excel... essa parte dos professores
aí, pensa que eles são os nossos ouros"*.

O que ele apontou — **os cinco foram feitos** (`1ae83f4`):

1. ✅ **Hierarquia invertida** — o nome estava em 12,5px regular, o mesmo peso
   dos números ao lado. *"O nome do professor tá muito pequeno. Não é igual
   aluno, é o professor."* Agora: foto 40px + nome 15px bold + segunda linha
   com unidades e cursos (3 + "+N", como o LA Report).
2. ✅ **Foto do professor na linha.** Medido antes: **43 dos 44 ativos têm
   `foto_url`**, e **os 38 da fila têm — 847/847**. Fallback de iniciais existe
   mas não é o caso comum.
3. ✅ **Expandir/colapsar** — decisão dele entre expandir e modal: **expandir na
   linha**. Lista as aulas por DIA, mais antigo primeiro, com hora, curso, turma
   e quem está esperando. Carrega só ao abrir (são 38 na fila).
4. ✅ **"Em aberto 50 / alunos 49 — o quê?"** Era defeito de DADO. Ver abaixo.
5. ✅ **A tabelona** virou card por professor. Cada métrica é um selo com a
   unidade dentro ("21 aulas"), então a linha 12 se lê sem o cabeçalho — que era
   de onde vinha a sensação de Excel.

### ⚠️ ACHADO (RESOLVIDO na 070): o painel contava a unidade errada

Medido em 08/08 na `vw_presenca_pendencia`, janela de 7 dias:

| | |
|---|---|
| Linhas aluno-aula (o que o painel mostra) | **847** |
| **Aulas** de verdade (o que o professor lança) | **624** |
| Alunos distintos | 809 |
| Média de alunos por aula | **1,36** |

O `count(*)` da 067 conta **pares aluno-aula**, não aulas. Como a maioria das
turmas tem 1 aluno, "em aberto" e "alunos" saem quase iguais em toda linha — foi
exatamente isso que o Alf estranhou. Os dois números juntos não informam nada.

Exemplo do Ramon Pina Morais, que o painel mostra como "50 em aberto / 49
alunos": são **21 aulas em 3 dias** (6 no dia 03, 9 no dia 04, 6 no dia 05).
Vinte e uma aulas é o trabalho real; cinquenta é um artefato do formato da view.

**A consequência mais séria era a ORDEM.** A fila mandava cobrar quem tinha
menos trabalho:

| Professor | Pares (antes) | Aulas (real) | Posição |
|---|---|---|---|
| Ramon Pina Morais | 50 | 21 | 1º → **11º** |
| Rodrigo Pinheiro Gomes | 37 | 18 | 4º → **20º** |
| Valdo Delfino | 27 | 25 | 13º → **4º** |
| Larissa Bheattriz | 33 | 27 | 7º → **3º** |

E vazava pro WhatsApp: `textoDaCobranca` dizia "50 lançamentos em aberto" pra
quem tinha 21 aulas pra lançar. **Corrigido junto na 070.**

`em_aberto` virou `aulas` — campo que muda de significado muda de nome, mesma
disciplina do `unidade_nome` → `unidades` da 067.

**Por que passou por 065 e 067 inteiras** (10 + 12 passos, 5 + 7 mutantes): todo
passo comparava o número da RPC com o mesmo `count(*)` da view. Teste que confere
a conta contra ela mesma nunca discorda dela. Quem discordou foi o Alf, olhando
a tela. O par de passos "conta AULAS" + "NAO e mais o total de linhas" da 070
existe pra que da próxima vez seja o teste.

### ✅ 072 NO AR — a pendência aprende o Emusys (o achado da noite)

O Alf, olhando o painel: *"a gente não pode colocar como em aberto, porque de
repente está na tabela onde chega o conteúdo de aula do Emusys"*. Medido:

| | |
|---|---|
| Pendência (janela 7d, 21h) | 744 aulas |
| Com **anotação digitada** no Emusys | **125 (17%)** |
| Caso extremo | **Isaque Mendes: 25 de 29** |

A anotação é conteúdo real (média 255 chars, "Objetivo… Conteúdo…"). A presença
do sync continua NÃO limpando pendência (régua da 012 de pé — os verdes fake);
`professor_presenca` está preenchido em 744/744, é default, não distingue nada.
**Só a anotação digitada distingue trabalho.**

O modelo virou TRÊS estados: registrada (forte) / **no Emusys** (anotação —
informa, não acusa) / **sem nada** (o único cobrável). A fila ordena por
sem_nada (o Isaque caiu de topo pra 36º), o atraso é o da aula mais antiga SEM
NADA, a cobrança do WhatsApp conta só sem_nada, e quem está com tudo no Emusys
nem tem botão Cobrar — vira selo "tudo no Emusys". 21 passos, 10/10 mutantes,
aplicada e conferida ao vivo (Isaque: "4 sem registro · 25 no Emusys", expandir
com 25 aulas marcadas).

✅ **teste:018 RESOLVIDO — e a sessão /loop da devolutiva era INOCENTE.**
Auditado em 08/08 ~21h30: as 4 funções da 018 em produção **idênticas** ao repo
(diff por `pg_get_functiondef`), zero worktree sujo, zero commit perdido. O
vermelho era o TESTE: `dia_referencia` é coluna **gerada em BRT** e o banco
roda em **UTC** — todo dia entre **21h e meia-noite BRT** o `current_date` já
é o dia seguinte, o delete de limpeza procura um dia que ainda não existe e
vira no-op, e as partes do teste se contaminam (a linha `enviada` que a PARTE
2 deixa trava o claim das PARTES 3A/3B: 11 passos vermelhos, não 2 — o "37B/
39B" do chip era só o fim visível da lista). Por isso 19h passava e 21h20
reprovava: hora, não código. Consertado nos testes (018: os 3 deletes; 066: o
probe de "cobrável", que divergia da dedupe do ON CONFLICT), verde DENTRO da
janela de falha. Armadilha registrada abaixo.

### ⚠️ BLOCO 2 ("o que os professores registraram") — MEDIDO EM 08/08, À NOITE

Antes de desenhar, fui olhar se há o que mostrar. **Não há — ainda.**

`fabio_registros_aula`, o banco inteiro:

| | |
|---|---|
| Registros no total | **65** |
| Professores que registraram | **2** |
| Alunos cobertos | 21 |
| Registro mais antigo | 13/07 (26 dias) |
| Registros em **agosto** | **0** |

E a `vw_aderencia_registro_professor` confirma pelo outro lado: em agosto, **todo
professor da casa está com `pct_cobertura` = 0**, Fábio e Emusys.

Isso **não é defeito de pipeline** — é o piloto começando. Os professores estão
sendo liberados esta semana (o Rafael nem entrou ainda). O dado vai aparecer.

**A boa notícia é que o schema aguenta.** As chaves que já existem em
`campos jsonb`: `repertorio` (59×), `eixos` (30×), `marco_ref` (30×),
`progresso`, `proximo_passo`, `objetivo`, `atividades`, `dever_casa`,
`materiais`. Não vai precisar de tabela nova pra estagnação.

Os cinco critérios do Alf, um a um:

| Critério | Fonte | Hoje |
|---|---|---|
| Aluno em risco | `vw_risco_evasao_atual`, `risco_evasao` | ✅ **dá pra fazer agora** — independe de registro |
| Silêncio do professor | `vw_aderencia_registro_professor` | ⚠️ computável, mas **degenerado**: todo mundo em 0%, e é o que o bloco 1 já mostra |
| Estagnação (>2 meses no mesmo repertório/eixo) | `campos->repertorio`/`eixos` | ⏳ schema pronto, **falta HISTÓRICO** — precisa de 2 meses e o mais antigo tem 26 dias |
| Aluno se destacou | `campos->progresso`/`observacao` + leitura do Fábio | ⏳ precisa de registro pra ler |
| Desalinhamento com a Jornada Pedagógica | ❓ | ❌ **a "jornada" do banco é de CONTRATO** (aulas contratadas/passadas/percentual, `vw_jornada_aluno_atual` e `vw_jornada_marcos`). Não achei conteúdo/repertório de referência em lugar nenhum — a jornada PEDAGÓGICA parece não existir como dado |

**Decisão pendente do Alf** (é o que trava o desenho): em 08/08 ele disse *"não
vai ter aluno na visão da coordenação"*, mas quatro dos cinco critérios são
sinais SOBRE alunos. Não é contradição necessariamente — pode ser "não tem
LISTA de alunos, tem sinal curado". Precisa dele pra saber qual dos dois.

**Risco de construir agora:** um painel com 4 de 5 sinais permanentemente
vazios. É a armadilha do "cron verde × trabalho feito" que esta casa já tomou.

### O que já está decidido (não reabrir):

- **Um app só**, não um segundo. O Organizer é a prova: papel por rota
  (`requireRoles`) e shell trocado por breakpoint (`AppShell` no celular,
  `DesktopShell` com sidebar no desktop). O argumento que fecha: a coordenação
  precisa ver **o que o professor registrou**, e isso é a maior parte do app que
  já existe. Dois apps = duplicar isso, que é a cicatriz que esta casa já tem.
- **Desktop E mobile** — pedido explícito do Alf. E são **dois desenhos**: o
  mobile não é o painel espremido.
- **Não vai ter aluno** na visão da coordenação (palavras dele).
- O painel `/app/equipe` já existe e já é da coordenação (migration 062).
- **O desktop é um painel executivo de governança onde o professor é a LINHA**,
  não o número solto — cada professor com seus alunos pendurados (quem faltou, o
  que não foi lançado, o que ficou em aberto). É **ponto de partida, não
  destino**: clicou, sai dali pro detalhe ou pra ação.
- **Mede o REGISTRO, não o julgamento.** Correção do Alf, 08/08: não é "o
  professor deu presença ou não", é **"ele fez o lançamento ou não"**.
- **Divisão com o LA Report (Alf, 08/08):** aqui é **diário + ação** (estado de
  hoje, botão pra cobrar, mandar recado, lançar ocorrência). Ranking, premiação
  e mês fechado ficam no LA Report — **por enquanto**.
- **Destino final: um painel só, aqui.** Palavras dele: *"no futuro a gente vai
  trazer isso pra cá... senão a coordenação vai ficar acessando dois sistemas. O
  ideal é elas terem o painel delas aqui, com o que realmente importa lá do LA
  Report"*. O painel daqui é **curadoria, não espelho**.

### Os blocos do painel (decididos com mockup na mão, 08/08)

**1º bloco — "quem está em aberto".** Aprovado. Professor é a linha, ordenado
**por urgência** (não alfabético — esse erro já aconteceu no painel de equipe),
com duas ações na própria linha: recado pelo Fábio e seta pro detalhe. Faixa de
4 números em cima. **Nota/health/ranking ficam de fora de propósito** — existem e
são bons no LA Report; repetir aqui cria o segundo número.

**2º bloco — "o que os professores registraram"** (escolha do Alf). É o bloco que
dá motivo pra abrir o painel. Hoje ele é o mais magro: **63 registros, de 1
professor só** (o Matheus), 32 nos últimos 7 dias — e `lead_experimental_registros`
está **zerada**. Ele enche na medida em que os 15 voluntários entrarem.

⚠️ **Armadilha de escala:** com 44 professores registrando o volume vai pra
**850+ por semana**. Feed cronológico vira mural que ninguém lê. Esse bloco é
**curadoria do Fábio**, nunca "todos os registros".

⚠️ **O selo desse bloco não pode ser `gravado_emusys`** — esse status mente (o
texto não chega ao campo `anotacoes` do Emusys, documentado na spec da
devolutiva §78). O selo honesto é "o professor confirmou e havia conteúdo".

**O que faz um registro subir** (Alf, 08/08). Medido campo a campo:

| Critério | Dá pra medir hoje? |
|---|---|
| Aluno em risco | ✅ sim |
| Aluno se destacou | ✅ sim |
| Silêncio do professor (registrava e parou) | ✅ sim |
| **Estagnação por `eixos`** | ✅ **sim** — `eixos` é array estruturado e já vem preenchido (`["TecnicaVocal","Repertorio"]`). É o critério do Alf na versão computável |
| Muito tempo no mesmo **repertório** | ⚠️ campo mais preenchido (57/63) mas **texto livre** — `group by` não serve (na 1ª consulta o `null` agrupou e fabricou 4 falsos positivos). Quem compara é o Fábio, ou o campo vira canônico |
| Desalinhamento com a **Jornada Pedagógica** | ❌ **não existe o lado do "deveria"**. `marco_ref` é null em 29/29, e `vw_jornada_marcos` é jornada **contratual** (aulas do contrato), não pedagógica. Isso é o RAG (#61) / LA Journey |

**Recomendação:** o painel nasce com os 4 ✅. Repertório e Jornada entram quando o
Fábio tiver a régua — bloco próprio, não remendo.

**Mobile decidido:** é **plantão, não escritório** — só o que pede decisão agora,
com o botão de resolver ali, chegando por push. Não é o painel espremido.

**3º bloco: cortado de propósito.** Os 4 sinais já cobrem risco, destaque,
silêncio e estagnação. Retenção e experimentais viram **filtro dentro do bloco
2**. Um terceiro bloco nasce de falta sentida, não de espaço vazio na tela.

📄 **Spec e plano escritos e commitados.** Spec:
`docs/superpowers/specs/2026-08-08-painel-coordenacao-design.md`. Plano (parte 1,
6 tarefas): `docs/superpowers/plans/2026-08-08-painel-coordenacao.md`.
**Sidebar ENTRA** (decisão do Alf) — eu tinha proposto adiar por ser "uma página
só" e estava errado: já são duas (`/app/equipe` + `/app/coordenacao`). Copiar de
`web/src/components/DesktopShell.tsx` do repo `LucianoAlf/LA-Organizer` —
**clonar**, nunca usar `D:/la-organizer`, que não é clone.

### Execução da parte 1 — onde parou

- ✅ **Task 1 — migration 065 NO AR** (`c1ebd82`). `app_coordenacao_em_aberto`:
  10 passos verdes, **5/5 mutantes mortos**, conferida em produção (`anon` não
  executa, `authenticated` executa, `stable`, `security definer`). O teste troca
  de identidade com `set_config('request.jwt.claim.sub', …)` — primeiro ramo do
  coalesce de `auth.uid()`; sem isso o guard ficaria sem teste.
- ✅ **Task 2 — migration 066 + edge function NO AR e PROVADA COM WHATSAPP REAL**
  (`a389d16`). 15 passos verdes, **7/7 mutantes mortos**. Foi replanejada durante
  a execução — ver o bloco ⚠️ no plano. Resumo do porquê: **a fila do Fábio não
  tem estado de entrada** (`status` só aceita `processando`, `enviada`, `falhou`,
  `pulada_*`; não existe `pendente`) e
  `fabio_claim_notificacao_por_referencia` é a função do **worker**, não do
  produtor — o painel não tem onde depositar recado. Virou **edge function
  síncrona** (`coordenacao-recado`, v1), no molde do `professor-liberar-acesso`.
  Sequência **reserva → envia → conclui**, com `lease_token` provando que quem
  fecha é quem abriu.
  **Prova ao vivo (08/08, 17:27:56):** recado real chegou no WhatsApp do Matheus,
  linha em `enviada` com recibo, lease devolvido, `solicitado_por` resolvendo
  para **"Luciano Alf"** — e o segundo clique do dia recusado com
  `ja_cobrado_hoje`.
  Cobrança é categoria `governanca`, que por projeto **ignora silêncio e
  domingo** — só férias (`pausa_ate`) barra. Não existe estado "fora de horário".
- ✅ **Tasks 3, 4 e 5 — O PAINEL ESTÁ NO AR** (`/app/coordenacao`), com shell
  próprio, fila por urgência, recado na linha e plantão no celular.
  - **`CoordenacaoFrame` existe porque o `AppFrame` não serve:** ele é
    `max-w-[430px]`, a moldura do celular do professor. No desktop virava coluna
    estreita no meio de 1300px — foi o que aconteceu com o `/app/equipe`. A
    Equipe agora usa a mesma casca e vira **grade de 3 colunas**.
  - Copiado do `DesktopShell` do Organizer: a moldura **não cresce com o
    conteúdo**, só o `<main>` rola. **NÃO** copiada: a coluna de leitura de
    720px — aquelas telas são de ler e responder, esta é de varrer e agir.
  - **⚠️ migration 067 — a fila repetia professor.** A 065 agrupava por
    (professor, unidade) e, como **27 dos 44 dão aula em mais de uma unidade**,
    38 pessoas viravam **60 linhas**. O defeito passou pelos 10 passos e pelos 5
    mutantes da 065 porque **todos perguntavam sobre NÚMEROS e nenhum sobre a
    CHAVE** — somar certo por linha errada continua somando certo. Quem
    denunciou foi a tela ("38 afetados" sobre fila de 60) e o React (chave
    duplicada). O V1 da 067 reintroduz exatamente esse `group by`.
    **Efeito do conserto:** o Ramon aparecia com 37 e tem **50** (37 Recreio +
    13 CG) — a fila mentia pra baixo sobre quem mais precisa de cobrança.
  - Conferido no navegador em 1280 e 375: sidebar 196px, `main` 1084px, Equipe
    em 3 colunas de 342px, zero rolagem lateral, 38 linhas / 38 nomes.
  - De quebra: "2 experimenta**lis**" virou "experimenta**is**".
- ✅ **Task 6 — produção conferida** (08/08, à noite), com o que dá pra provar
  sem a conta dele:
  - o deploy da Vercel **está com o código novo** — o bundle servido contém
    "Aulas sem lançamento", "Todos os cursos" e "Precisa de decisão agora", e
    **não** contém mais o texto velho de cobrança ("lançamentos em aberto");
  - `/app/coordenacao` sem sessão **redireciona pro login** (o guard de rota
    funciona em produção);
  - a RPC chamada com a chave `anon` responde **401 `permission denied for
    function app_coordenacao_em_aberto`**, zero dado no corpo. E o fato de ela
    ter sido RESOLVIDA (permissão negada, não "função não existe" nem "could
    not choose the best candidate") prova que a assinatura de 3 argumentos
    entrou certa e que não sobrou sobrecarga ambígua.
  - ⬜ **O que eu NÃO consigo:** abrir o painel autenticado. Exige o código do
    WhatsApp dele ou a senha — credencial não é coisa que eu digite. Fica pro
    Alf: abrir, conferir que o topo diz **624** (não 847) e que os filtros
    aparecem ao lado da data.

- ✅ **Filtros de unidade e curso NO AR** (migration 071, `1e75770`). O filtro de
  curso agrupa as modalidades: 34 nomes viram 20 cursos, e escolher "Bateria"
  traz as **129** aulas (não as 46 de "Bateria" cru, sem "Bateria T"). As
  facetas ignoram o próprio filtro e respeitam a outra — escolher a Barra mantém
  as 3 unidades e reduz os cursos de 20 pra 10, com as contagens da Barra.
  31 passos, 22/22 mutantes. **Dois achados do próprio harness** estão no corpo
  do commit: um teste meu que nunca podia falhar, e a 071 saindo da suíte em
  silêncio por não ser reaplicável.

- ✅ **Varredura do Design System** (`fa019ba` + `df8d1b5`), depois do Alf
  flagrar duas vezes: *"a gente já tem um Design System pronto que você está
  criando um outro paralelo"*.
  Os **tokens de cor sempre passaram** nos dois greps do `frontend-tokens.md` —
  o desvio estava no que o checklist **não mede**: raio, sombra, tamanho de
  rótulo e componente recriado à mão. Consertado: KPIs viraram `Card`
  (`rounded-md` sem borda e sem `shadow-card` some no tema escuro e achata no
  claro), rótulo virou a receita do DS (11px bold caixa alta `.5px`), vazio
  virou `EmptyState`, e o rodapé do celular virou a `TabBar` do DS — o meu
  `<nav>` não tinha `env(safe-area-inset-bottom)` e no iPhone jogava os rótulos
  embaixo da barra de gestos.
  **Extraído, não copiado** (senão a duplicação só muda de lugar): `BotaoTema`,
  `dataLonga`, `BotaoVoltar`, `LinhaInfo`/`TituloSecao`, `SeloVersao` — e as
  telas do professor passaram a consumir os mesmos.
  De quebra: o token `--scrim` existia desde o P0 **sem utilitário no Tailwind**,
  e o app tinha três véus de modal diferentes (`bg-black/50`, `bg-black/60` e um
  `style` com var). Virou `bg-scrim`.
  **Lição registrada:** checklist que mede só cor dá verde em DS paralelo.

- ✅ **O achado dormindo foi resolvido — migration 068 NO AR.**
  `fabio_notificacoes.status` tinha `DEFAULT 'pendente'`, valor que o próprio
  CHECK da tabela recusa: todo INSERT que omitisse o status morria com uma
  mensagem que mandava investigar a constraint, nunca o default. **Escolhido
  `drop default`, não trocar para 'processando'** — um default válido faria o
  INSERT incompleto PASSAR, fabricando em silêncio uma linha "em voo" sem lease
  e sem ninguém pra concluir; o defeito reapareceria horas depois como mensagem
  que não chega. Agora falha na hora com `null value in column "status"`. O
  **NOT NULL fica**: é ele que transforma a falta do default em erro.
  Auditoria antes de mexer (nenhum caminho dependia do default): **7 INSERTs em
  5 funções**, todos nomeando `status`; zero triggers, zero rules, zero views;
  **56 crons, nenhum cita a tabela**; na VPS o `~/.hermes` não menciona a tabela
  e o worker só fala por RPC; RLS deixa só service_role escrever; e nos dados,
  19 linhas, nenhuma jamais 'pendente'. 9 passos verdes, **6/6 mutantes
  mortos**, conferida em produção e com o worker do Fábio rodando limpo depois
  (`fabio-devolutiva-oferta`, 20:55:04 UTC, exit 0).
  ⚠️ O comentário dentro da **066** ("o DEFAULT da coluna é 'pendente'… omitir
  quebraria") ficou obsoleto na razão, não no conselho: status continua indo
  explícito, só que agora quebra por NOT NULL. Não reescrevi a 066 — migration
  aplicada é registro histórico; a correção mora no cabeçalho da 068.
  ⚠️ **Por que 068 e não 067:** o número 067 já estava tomado por
  `067-a-fila-para-de-repetir-professor` (+ `.test.sql` + `mutantes-067.mjs`),
  escrita às 17h51 no worktree principal e **ainda não commitada** — invisível
  pro `git log`, e por isso eu subi como 067 antes de ver. Renumerei o **meu**,
  que é um `ALTER` solto, e não o dela, que está amarrada em `Coordenacao.tsx`,
  `routes.tsx` e `api.ts` no meio da Task 3. Fica a lição: **número de migration
  livre no `git log` pode estar ocupado no disco de outra sessão** — antes de
  numerar, olhar também o `git status` do worktree principal.

**Antes de escrever tela, invocar `superpowers:brainstorming`.** É a regra da
casa e ela existe porque telas chutadas viram retrabalho.

### O que o LA Report já entrega (auditado em 08/08, com `git pull` antes)

O banco é **o mesmo projeto** (`ouqwbbermlzqqvtqwlul`): chamar a RPC de lá não é
integração, é consulta. **UI aqui, regra de negócio onde ela já está** — o LA
Teacher **não pode RECALCULAR** o que o LA Report calcula, é assim que nascem
dois números pra mesma pergunta.

| O que já existe | Onde |
|---|---|
| **50 colunas por professor/período** (carteira, ticket, MRR, presença, faltas, experimentais, conversão, renovação, evasão, retenção atribuível) | `get_kpis_professor_periodo_canonico_v3` |
| **Health Score V3**: 5 pilares de nota + 1 diagnóstico, já honesto (`score_exibivel`, `comparabilidade_estado`, `pilares_validos/esperados`) — se recusa a dar nota sem base | `src/lib/healthScoreProfessorV3.ts` |
| **Relatório de coordenação** em 4 recortes (ranking, carteira, presença, retenção), com auditoria (fingerprint da regra, data de corte) | `get_relatorio_coordenacao_canonico_v3` |
| **360° do professor**: 8 critérios (6 penalidade + 2 bônus). Peso: Preench. EMUSYS 25, Assiduidade 20, Pontualidade/Salas/Prazos 15, Dresscode 10 | `professor_360_*` |
| Carteira, agenda do dia, jornada com metas e prazo, saídas detalhadas | `get_carteira_professores`, `get_agenda_dia`, `get_jornada_professor` |

⚠️ A pilha do relatório é **5 camadas** (`v3 → payload_v3 → v2 → payload_v2 →
kpis_v3 → kpis_v2`). Trazer **o contrato de saída**, nunca a pilha.

### Enquanto isso, duas coisas pra observar (não são tarefa, são vigília)

1. **Terça 11/08, 18:00 — experimental do Matheus Palma com o Leonardo Castro.**
   Vínculo `vinculado`, ficha abre. É a **primeira experimental registrada por
   alguém que não é o Matheus Felipe**. Se falhar, falha aí.
2. **Rafael Alves Souza (Akeem)** recebeu o convite às 17:50 UTC de 08/08 e
   ainda não pediu código. Ele é o que tem mais aula (10 no sábado, 17 na
   segunda). Se na segunda ainda não tiver entrado, o convite precisa ser
   reenviado — o botão "Reenviar" do painel serve pra isso.

---

## ✅ ONDE ESTAMOS (medido em 08/08/2026, 15h)

| | |
|---|---|
| Professores ativos | **44** |
| Com acesso liberado | **4** (Matheus Felipe + Daiana, Rafael, Leonardo) |
| Já entraram sozinhos | **3** |
| Coordenação do LA Teacher | **4** (Alf, Hugo, Juliana, Quintela) |
| Experimentais na semana | **24 aulas, 22 com ficha** |
| Cron do reconciliador | **ativo**, `12,27,42,57 * * * *` |
| Suíte de migrations | **43 passam, 0 falham** (`npm run teste:tudo`) |

**A corrente do primeiro acesso está PROVADA com gente de verdade.** Não é
teste: o Alf clicou "Liberar" no painel e

- **Daiana Pacifico** — liberada 17:50:01 → entrou **17:52:54** (2min53)
- **Leonardo Castro** — liberado 17:51:48 → entrou **17:56:29** (4min41)

sem ninguém explicar nada. Os três convites saíram no WhatsApp do Fábio
(conferido na instância, não no log).

**Produção sincronizada:** migrations 056→064 aplicadas, edge functions
`professor-entrar` e `professor-liberar-acesso` no ar, app em
`https://la-teacher.vercel.app`, VPS com 11 timers ativos.

---

## 📦 DE ONDE VIEMOS — 08/08/2026, 13 commits

**O acesso do professor nasceu** (`ac632cd`, `7c90976`, `40ce1ef`, `ede708b`,
`a34167e`) — entra com WhatsApp + código de 8 dígitos, sem senha. Painel da
equipe pra liberar, ordenado por urgência (quem tem mais experimental na
semana). Três defeitos meus pegos aqui: a fila que eu **escrevi** que era por
urgência e **era alfabética**; a coordenação caindo em "falta ativar seu
acesso"; e a tela dizendo "6 números" quando o código tem 8.

**O painel parou de mentir** (`012b642`) — `usuarios.ultimo_acesso` está vazia
em 29/29 e **ninguém no banco inteiro escreve nela**. O painel carimbava
"liberado, ainda não entrou" em todo mundo, pra sempre. A verdade é
`auth.users.last_sign_in_at`.

**O reconciliador da experimental nunca teve quem o chamasse** (`8a6aa2d`) — a
função existe desde a 033, tem teste, tem mutante, e **57 crons no banco,
nenhum a chama**. 12 das 23 experimentais da semana sem vínculo; 11 delas com
par perfeito esperando no espelho. Não era o casamento que falhava, era não
haver quem mandasse casar. Mais três defeitos que o `exception when others` do
laço engolia — ver ARMADILHAS.

**A coordenação virou lista** (`3fcfd40`) — era `perfil='admin'` do LA Report:
**11 pessoas**, incluindo Marketing e Comercial, podiam liberar professor e
disparar WhatsApp em nome do Fábio.

**RLS nas duas tabelas do ciclo** (`67ff9f9`) — achado do Alfredo.

**A view da cobrança: 27.951ms → 421ms** (`da4ccf9`) — 99,5% do custo num
SubPlan só, por falta de um índice de três colunas.

**A suíte de testes existia e ninguém podia rodar** (`baec7e1`) — 44 arquivos
`.test.sql`, 11 comandos no `package.json`. Agora tem `npm run teste:tudo`.

**O vídeo** (`cde0466`) — 25 cenas, 4min52. A cena de login **ensinava e-mail e
senha**, que não existe mais. Cinco cenas novas do ciclo da experimental.

---

## 📋 PENDENTE, em ordem

1. **Desenho da coordenação** — ver PRÓXIMO PASSO. A auditoria do LA Report
   (08/08) abriu quatro costuras que fazem parte deste bloco:
   - **a) O ritual está lá, a evidência está aqui, e ninguém ligou os dois.** O
     critério mais pesado do 360° (`Preenchimento EMUSYS`, peso 25) é digitado à
     mão: 18 ocorrências em jun/2026, 1 em jul, **0 em ago**. O LA Teacher mede
     a mesma coisa sozinho — `vw_presenca_pendencia`: 847 aulas sem lançamento
     em 7 dias, 38 dos 44 professores. É a costura mais valiosa do painel.
   - **b) As 192 ocorrências do 360° não têm autor.** `registrado_por` é null em
     **192/192**. Penalidade de 25 pontos e ninguém sabe quem lançou — mesma
     classe do defeito que a migration 054 consertou aqui. Resolver **antes** de
     a coordenação passar a lançar ocorrência pelo app.
   - **c) A avaliação 360° nunca é fechada.** `professor_360_avaliacoes` tem
     **0 linhas** e a tela mostra 75 avaliações, todas "Pendente": a nota é
     calculada na hora e nunca consolidada. Mexeu no peso de um critério, **a
     nota de março muda junto**. Pra ranking e premiação isso é bomba armada.
   - **d) NÃO MEDIDO (não afirmar sem medir).** O LA Report tem régua própria de
     presença honesta (`presenca_publicavel` / `presenca_confianca` /
     `presenca_cobertura`) e o LA Teacher tem a dele (`fn_presenca_e_forte`).
     **Não sei se as duas concordam.** Medir antes de o painel exibir qualquer
     percentual de presença — senão a mesma escola tem dois números e os dois se
     dizem honestos.
2. **Os 15 voluntários.** O Alf mandou o texto no grupo pedindo voluntários. Ele
   libera; eu confiro. Dos 13 com experimental na semana, priorizar quem
   levantar a mão — são os que mais ganham no primeiro dia.
3. **`emusys_aula_id` é id de EVENTO, não da aula** (#57). Confirmado: não bate
   com `aulas_emusys` **nem nos vínculos que casaram**. A coluna é inútil pro
   casamento e ninguém depende dela (o reconciliador usa chave natural). Ou
   passa a guardar o id certo, ou é renomeada pro que ela é.
4. **Leads duplicados da experimental.** Dois leads pro mesmo aluno disputando a
   mesma aula (Joaquim Moura, Théo Marins, irmãos Soares de Moura). O
   reconciliador marca `ambiguo` e faz a coisa certa; o problema nasce no funil
   comercial, no LA Report.
5. **Áudio da experimental não tem fila offline.** A aula normal tem; a
   experimental não. Professor sem sinal perde a gravação.
6. **`sync-presenca-emusys` devolve 502** em algumas rodadas (29s de timeout). O
   cron reporta sucesso porque só enfileira — ponto cego de monitoramento. É
   função do LA Report, não do LA Teacher.
7. **RAG pedagógico do Fábio** (#61), **relatórios do Fábio** (#47-49),
   **anamnese no prontuário** (#55).

---

## ⚠️ ARMADILHAS QUE JÁ CUSTARAM CARO

Isto é o que me impede de repetir erro depois de perder contexto.

**Verde não-falsificado é decoração.** Todo teste de SQL vem com mutante
(`scripts/mutantes-NNN.mjs`). Âncora podre = FALHA, não aviso. E `create or
replace` **preserva privilégios** — mutante de permissão precisa `grant`/`drop`
de propósito, senão sobrevive.

**A armadilha do SELECT-snapshot.** Chamar função que ESCREVE dentro de um
`WHERE` faz a asserção ler o snapshot de ANTES da chamada — o passo passa dos
dois jeitos. Já me mordeu duas vezes (056, 057). Chamar primeiro pra uma temp
table, depois medir.

**`v_vinculo := null` deixa o record NÃO ATRIBUÍDO em plpgsql.** O próximo
`v_vinculo.id` levanta erro. Recarregar com um SELECT que não acha nada.

**`raise warning` não sai pela Management API.** O reconciliador contava erros
num `exception when others` e gritava por warning — ninguém nunca leu. Achei os
três defeitos **clonando a função e trocando o warning por um INSERT**. Se uma
função tem handler de exceção, o contador dela é o que interessa.

**Teste que depende do estado de produção se auto-destrói.** O da 060 media o
buraco da produção e exigia que diminuísse: passou de manhã, ficou vermelho à
tarde quando o job fechou o buraco. O da 026 afirmava que uma aluna real tinha
0 aulas — ela teve aula. **Fixture que é uma pessoa de verdade envelhece junto
com a vida dela.**

**Migration superada continua sendo exercitada.** A 033 instala a versão antiga
no rollback e acusa os defeitos que a 061 corrigiu — isso é o teste
funcionando. Marcador `-- SUPERADA POR:` no topo do arquivo; a suíte lê e
separa do "FALHOU".

**"Desligado de propósito" tem prazo de validade.** O cron do reconciliador
ficou desligado durante o desenvolvimento e ninguém religou. Custo: 12
experimentais sem ficha. Quando desligar algo "por enquanto", o religar entra
na lista de tarefas, não na memória.

**Harness que ignora o que não reconhece assina embaixo.** O
`conferir-video.mjs` dizia "31 toques conferidos" com 5 cenas novas no vídeo —
a regex do registro exigia chave sem aspas e `'exp-agenda'` tem hífen. Agora
tem trava que para se alguma entrada não virar par.

**Não calcular offset de cena do vídeo na mão** — deu 76 frames de erro. Quem
sabe a linha do tempo é o `selectComposition` (`scripts/conferir-video.mjs`).

**`git pull` antes de mexer em outro repo.** O Alf não avisa; checar é
obrigação minha. `D:/la-performance-report` anda muito.

**A suíte dá falso vermelho quando a API do Supabase engasga.** Em 08/08 a
`teste:tudo` acusou `030-anamnese-ficha-exige-login`, e rodando ela sozinha
passou — a Management API estava devolvendo **502 (Cloudflare)** naquela janela,
e o runner reprova quando não consegue tirar a impressão digital inicial. Antes
de acreditar num vermelho da suíte (e principalmente antes de culpar o commit de
outra pessoa), **rodar o `teste:NNN` isolado**. Falha de infra e defeito de
verdade têm a mesma cor na saída.

**`current_date` é UTC; `dia_referencia` é gerada em BRT — entre 21h e
meia-noite BRT os dois discordam.** O teste da 018 passou às 19h e reprovou às
21h20 do MESMO dia com o MESMO código: o delete de limpeza filtrava
`dia_referencia = current_date` (que já era "amanhã") e virava no-op, e as
partes do teste se contaminavam. Vermelho que nasce em horário redondo pede
suspeita de fuso ANTES de suspeita de commit — e a comparação honesta com
produção é `pg_get_functiondef`, não memória. Filtro sobre coluna gerada usa a
MESMA expressão da coluna: `(now() at time zone 'America/Sao_Paulo')::date`.

**Número de migration livre no `git log` pode estar ocupado no disco.** Outra
sessão pode ter escrito `NNN-*.sql` no worktree principal e ainda não ter
commitado — o log não enxerga. Antes de numerar:
`git -C D:/la-teacher status -s | grep migrations`. Aconteceu com a 067/068.

---

## 🔁 O PROTOCOLO (a metodologia, combinada com o Alf em 08/08/2026)

1. **Eu atualizo este arquivo** quando o contexto pesar, quando fechar um bloco,
   ou quando o Alf pedir checkpoint. Sempre com **fato medido**, nunca com
   lembrança da conversa: `git log`, consulta no banco, saída de comando.
2. **O Alf roda `/compact`** — é comando dele, eu não disparo.
3. **A primeira coisa que eu faço depois é ler este arquivo** e seguir do
   PRÓXIMO PASSO, sem reabrir o que está em "já está decidido".
4. **Commitar sempre.** Arquivo não commitado não sobrevive — e é o mesmo erro
   de dizer "aplicado" sem push.

**Onde cada coisa mora:**

| Arquivo | O que guarda |
|---|---|
| `CLAUDE.md` | O que **não muda**: acessos, mapa da VPS, regras da casa |
| `RETOMADA.md` | O que **muda**: onde estamos, o que vem agora, armadilhas frescas |
| `~/.claude/.../memory/` | O que eu aprendi e não pode se perder entre projetos |
| `docs/superpowers/specs/` | Design aprovado, por funcionalidade |
## 12/08/2026 — incidente Daiana/Elisete encerrado

O relato da professora Daiana foi confirmado como bug de confirmação parcial:
`campos.presenca` existia como JSON `null`, então a raiz era confirmada mas a
fatia da Elisete permanecia pendente. A migration
`20260812135033_fix_presence_json_null_confirmation.sql` foi aplicada e
registrada no histórico remoto. A ocorrência foi reconciliada pelo core em
transação guardada: raiz e fatia gravadas no alvo individual, presença da
Elisete criada, duas faltas explícitas preservadas, devolutiva/recibo/log
emitidos e a aula removida das pendências. Backup antes/depois e hashes estão
em `docs/superpowers/evidence/2026-08-12-daiana-elisete-presenca-null.md`.

Validação fresca no worktree da correção: `teste:presenca-null` verde com
resíduos 0/0, `mutantes:presenca-null` matou 2/2 mutantes, Vitest 34/34 e
`npm run build` verde. Próximo passo é publicar o branch/PR; não reabrir este
incidente.

## 12/08/2026 — aula operacional, Leonardo/Matheus e briefing

**Decisão do Alf:** o card estático “Briefing do Fábio — em breve” fica oculto
de todos os professores até existir conteúdo real; o botão/chat do Fábio não
muda. A Home foi ajustada no worktree `codex/presenca-canonica`.

**Causa-raiz medida:** o Emusys devolve eventos concorrentes do mesmo slot. No
caso Leonardo/Guitarra 14h, há turma antiga vazia, turma atual com roster e
individual do aluno. O áudio `58ffbe90-620e-41bd-b0f1-711f7815197e` foi ligado
à vazia e falhou como transitório com `aula sem roster canônico`. No Matheus,
17/08 às 18h, há turma vazia e individual reagendada com Arthur; a RPC escolhia
“turma primeiro” e escondia o aluno. Não é atraso simples do sync.

**Desenho e plano:**
`docs/superpowers/specs/2026-08-12-aula-operacional-e-recuperacao-audio-design.md`
e
`docs/superpowers/plans/2026-08-12-aula-operacional-e-recuperacao-audio.md`.
O raw `aulas_emusys` não é apagado. LA Report é o dono da migration
`20260812210110_aula_operacional_prioriza_roster.sql`, que cria um resolvedor
privado por roster e o liga à agenda, pendências, Fábio e fila de áudio. A
recuperação de fila reutiliza `audit_log`, sem ledger paralelo.

**Migração concorrente reconciliada no Git:** o arquivo já aplicado
`20260812171943_chamada_retroativa_fallback_emusys.sql` foi localizado no
worktree `fix/chamada-retroativa` (SHA-256
`E36857902F327C7037A9EC6918B5D20D8422808594B858892789A0880C8C4339`) e
cherry-picked sem alteração para a branch do LA Report no commit `0c3d1ee0`.
Não reaplicar essa migration.

**Banco aplicado no projeto principal, sem branch Supabase:** versões remotas
`20260812210110_aula_operacional_prioriza_roster` e
`20260812210328_recuperar_fila_aula_operacional_transitoria`. O helper resolve
`217855 → 1373100` (Leonardo) e `300858 → 18092436` (Matheus), o índice
`idx_aulas_emusys_slot_operacional` existe e a ACL é `anon=false`,
`authenticated=false`, `service_role=true`. A segunda migration foi necessária
porque um retry concorrente resumiu a mensagem da fila para
`normalizacao_invalida`; a recuperação final usa a condição estrutural (erro
transitório + destino canônico diferente + roster), não texto de erro.

**Áudio do Leonardo recuperado:** a fila
`58ffbe90-620e-41bd-b0f1-711f7815197e` foi religada de `217855` para `1373100`,
com `audit_log.acao=relink_aula_roster`; o pipeline terminou em `normalizado`
sem erro e gerou a raiz `96a47de5-2595-445a-b426-555a510925d5` mais a fatia do
aluno, ambas `aguardando_confirmacao`. Nada foi confirmado automaticamente.

**Sync corrigido:** `sync-presenca-emusys` v92 está ACTIVE, continua com
`verify_jwt=false` e agora preenche o `aluno_nome` obrigatório ao auditar
conflito de cancelamento humano. Depois da janela de indisponibilidade 522, a
v92 voltou a responder 200 em execuções reais às 21:05 UTC.

**Provas:** React/Vitest 46/46, contrato + fixture real PostgreSQL 17 verdes,
build do LA Teacher e build do LA Report verdes. Na conta real do Matheus,
17/08 mostra 5 chamadas; às 18h aparece Arthur de Carvalho Rodrigues Frota
Almeida como Musicalização Preparatória individual. Abrir a chamada mostra o
roster e a trava honesta de 15 minutos. Nenhum aluno/presença de teste foi
criado, então não existe limpeza de dado produtivo. O briefing estático sumiu;
o botão/chat funcional do Fábio permanece.

Durante a leitura final dos logs apareceu outro contrato quebrado, fora da
agenda mas dentro do mesmo ecossistema Emusys: o sincronizador de matrículas
emitia `data_nascimento_divergente` e o `CHECK` da fila de divergências recusava
o valor. A migration remota
`20260812211712_alunos_atributos_data_nascimento_divergente` passou a aceitar e
validar esse tipo mantendo a enumeração fechada.

**Próximo passo:** publicar o frontend do LA Teacher, manter o preview na prova
do Matheus e continuar a ficha manual aprovada na branch separada
`codex/registro-manual` (microfone + caderno, copiar campo + duplicar ficha).
