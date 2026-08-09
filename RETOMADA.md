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

## ▶ PRÓXIMO PASSO: RADAR DO ALUNO (bloco 2 do painel — decidido 08/08, noite)

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

## ▶ PASSO ANTERIOR (concluído nesta sessão)

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
