# RETOMADA — LA Teacher

> **Este arquivo existe pra sobreviver ao `/compact`.** O resumo automático guarda
> o que eu lembro; este arquivo guarda o que é **verdade**. Depois de compactar,
> a primeira coisa que eu faço é ler ele — e sigo daqui, sem perguntar de novo o
> que já foi decidido.
>
> **Última atualização: 08/08/2026, noite (BRT).** Tudo no remoto — confira com
> `git log --oneline -5`.
> Quem mais lê: o Alf, o Hugo, o Alfredo. Escrever pra eles, não pra mim.

---

## ▶ PRÓXIMO PASSO

**Desenhar o módulo da coordenação** (Alf, 08/08: *"depois de concluir tudo, a
gente entra no desenho dessa versão da coordenação"*).

O que **já está decidido** (não reabrir):

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

O que **falta pra começar**: o layout — quais blocos, em que ordem, e o que o
mobile mostra no lugar do painel. Isso se resolve **mostrando mockup**, não
descrevendo (o próprio Alf disse que descrever fica raso).

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
| Suíte de migrations | **39 passam, 0 falham** (`npm run teste:tudo`) |

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
