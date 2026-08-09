# Semáforo do aluno no app do professor — design

**Decidido com o Alf em 08–09/08/2026.** Tira a percepção do professor do link
avulso que expira e faz ela nascer dentro do app, com governança do Fábio.

---

## O problema (medido, não suposto)

O LA Report tem uma tela de feedback do professor (`FeedbackProfessorPage`) que
a agente Lia manda por link com validade. Fui ao banco antes de desenhar:

| O que se acreditava | O que o banco diz |
|---|---|
| A coordenação olha o coração do professor | **`aluno_feedback_professor`: 0 linhas.** Nenhum professor respondeu um único aluno |
| Há histórico do semáforo | **`alunos_health_score_historico`: 0 linhas** |
| Os 107 "críticos" são percepção do professor | São `calcular_health_score_alunos_batch` — score de máquina, vocabulário próprio (`saudavel`/`atencao`/`critico`), `health_score_updated_by` nulo em 100% |
| O link da Lia roda | Era disparado **na mão** e hoje não se manda mais. Está de enfeite |

E o achado que amarra tudo: **`calcular_health_score_aluno` já lê
`aluno_feedback_professor`**, com peso vindo de `config_health_score_aluno`.
Como a tabela é vazia, **o pilar pedagógico do score sempre valeu zero**. O
score que o time diz que falhou — os "Atenção" evadindo mais que os "Crítico" —
rodava com pagamento, tempo, fase e a presença que a migration 012 provou ser
~4.254 verdes falsos. Sem a única coisa que só o professor sabe.

Ou seja: **não é portar uma tela. É fazer o sinal existir.**

Por que ninguém preenchia, na palavra do Alf: *"é a mesma coisa de descrever o
conteúdo da aula — falta de tempo, falta de hábito, desorganização, falta de
governança e cobrança."* O desenho abaixo ataca as duas pontas: atrito baixo na
coleta e cobrança com escada.

---

## O que este spec NÃO faz

- **Não cria tabela nova pro feedback.** Decisão do Alf: *"não cria duas
  verdades"*. Aperfeiçoa a que existe.
- **Não mexe nos pesos do score.** Peso chutado é dívida a pagar no LA Report,
  em outro momento e por quem é dono de lá.
- **Não desliga o link da Lia.** Está de enfeite e não atrapalha; ambos escrevem
  na mesma tabela.
- **Não constrói o mapa de aderência.** É fatia própria (ver "Depois disto").
  Mas a RPC de progresso já deixa o número calculável.
- **Não guarda o áudio.** O produto é o texto que o professor revisou.
- **Não faz fila offline.** Sem rede, o aluno fica marcado como não salvo e
  tenta de novo.

---

## Decisões (todas do Alf, modal a modal)

| Assunto | Decisão |
|---|---|
| Áudio | **Complemento**, não substituto. Microfone no campo de observação, transcrição volta editável |
| Onde mora | **Permanente** dentro de Alunos **+ card na Home na última semana do mês** |
| Quem entra na mesa | **Toda a carteira**, em dois blocos: quem ele viu no mês × quem ele não viu (com dias) |
| Obrigatório | Coração **+ as três perguntas**. A observação é convite, não obrigação |
| As três perguntas | pratica em casa · está evoluindo · ânimo (expectativa × anamnese fica pra depois) |
| Fronteira do texto | Coordenação e Fábio leem **cru**. **Nunca** chega em aluno/responsável. Trava no **banco** |
| Onde grava | **`aluno_feedback_professor`** — a tabela que o score já lê |
| Salvamento | **A cada toque.** Não existe botão "Salvar" |
| Governança | Fábio lembra no 1º dia da janela, reforça três dias depois, e no dia 1º **entrega ao grupo da coordenação** a lista de quem não fechou |
| Escopo da entrega | Coleta **e** governança do Fábio na mesma entrega |

---

## Arquitetura

Três camadas, cada uma com uma responsabilidade:

```
  app do professor  ──►  app_professor_feedback_salvar()  ──►  aluno_feedback_professor
  (mesa + card)          app_professor_feedback_mesa()          (a tabela que o score já lê)
                         app_professor_feedback_progresso()
        │                                                              │
        └──► transcrever-observacao (edge) ──► texto editável               │
                                                                        ▼
  timer systemd ──► fabio_notification_worker.py ──► reserva ─► envia ─► conclui
   (fim do mês)     pergunta ao banco quem cobrar        (fabio_notificacoes)
                                                        ├─► WhatsApp do professor
                                                        └─► grupo da coordenação (dia 1º)
```

O que já existe e é **reusado, não recriado**: o gravador
(`src/features/registro/useRecorder.ts`), a carteira canônica
(`app_minha_carteira`), os helpers de auth (`fn_professor_do_usuario()`,
`fn_e_coordenacao_la_teacher()`), a fila `fabio_notificacoes` com o par
reserva/conclusão da 066, o worker de notificação com suas units systemd, e o
`enviar_grupo()` que já fala com o grupo da coordenação no escalonamento.

---

## O dado

### Colunas novas em `aluno_feedback_professor`

A tabela já tem RLS ligada e a chave única `(aluno_id, professor_id,
competencia)`. `sessao_id` é nulável, então o LA Teacher grava sem sessão.
Todas as colunas novas são **nuláveis** — nenhuma tela do LA Report quebra.

| coluna | tipo | valores |
|---|---|---|
| `pratica_em_casa` | text | `sim` · `as_vezes` · `nao` |
| `evolucao` | text | `evoluindo` · `parado` · `regredindo` |
| `animo` | text | `animado` · `neutro` · `desanimado` |
| `teve_aula_no_mes` | boolean | snapshot do bloco em que o aluno estava |
| `origem` | text | default `'la_teacher'` — separa do formulário antigo |
| `atualizado_em` | timestamptz | escrito a cada toque |

Cada uma das três perguntas ganha `check` com os valores acima (aceitando null).

**Por que `teve_aula_no_mes` é gravado e não calculado depois:** a agenda muda.
Sem o snapshot, daqui a três meses ninguém sabe se aquele coração nasceu de
observação recente ou de memória — e essa diferença é justamente o que dá peso
ao sinal.

**Por que `origem`:** sem ela, o dia em que alguém disparar o link antigo mistura
duas coletas com atrito e contexto diferentes no mesmo número de aderência.

### Vocabulário do coração

A coluna `feedback` já existe e usa `verde` / `amarelo` / `vermelho`. **Mantém.**
Traduzir pro vocabulário de `alunos.health_score` (`saudavel`/`atencao`/
`critico`) é trabalho de quem calcula o score, não da coleta.

---

## A fronteira (mora no banco)

`observacao` é texto interno entre profissionais. O professor vai escrever
"não pratica nada, os pais não cobram" — e isso ajuda a coordenação e destrói
uma família.

1. **RLS na tabela** (já ligada): professor lê e escreve **somente** linhas em
   que `professor_id = fn_professor_do_usuario()`. Coordenação
   (`fn_e_coordenacao_la_teacher()`) lê tudo.
2. **`observacao` sai por dois caminhos e mais nenhum**: a RPC de leitura da
   coordenação e o contexto do Fábio.
3. **Nenhuma RPC, view ou edge function que alimente devolutiva, relatório do
   responsável ou histórico visível à família seleciona `observacao`.**

Isso é o mesmo padrão da devolutiva de aula, onde o worker não enxerga o campo
cru: a fronteira mora no banco porque tela a gente troca, e a próxima tela
esquece a regra.

---

## As RPCs

Todas `security definer`, `search_path = public`, `grant execute` só para
`authenticated`, e `revoke` de `anon` (mutante de permissão precisa `grant` de
propósito — `create or replace` preserva privilégio).

### `app_professor_feedback_mesa(p_competencia date default null)`

Devolve a mesa do professor logado. `p_competencia` nulo = mês corrente **em
BRT**.

```
{
  "competencia": "2026-08-01",
  "total": 38,
  "respondidos": 12,
  "janela_aberta": true,          -- estamos nos últimos 7 dias do mês
  "alunos": [
    { "aluno_id": 812, "nome": "Ana Beatriz", "curso_nome": "Violão",
      "teve_aula_no_mes": true, "dias_sem_aula": null,
      "feedback": "verde", "pratica_em_casa": "sim",
      "evolucao": "evoluindo", "animo": "animado",
      "observacao": "…", "respondido": true }
  ]
}
```

- Fonte da carteira: a mesma jornada canônica que `app_minha_carteira` lê — a
  mesa **não** inventa outra régua de "quem é meu aluno". Se as duas
  discordarem, a carteira é a certa e a mesa é o bug.
- **Dedupe por aluno**: a carteira tem uma linha por matrícula/disciplina, e o
  feedback é por aluno. Aluno com dois cursos aparece **uma vez**, com os cursos
  concatenados.

**`respondido` (e o que a barrinha conta):** um aluno só conta como respondido
quando tem **coração e as três perguntas**. Observação não entra na conta — é
convite. Como o salvamento é a cada toque, existe estado intermediário no banco
(coração gravado, perguntas nulas); esse aluno aparece na mesa como **começado,
não terminado**, e **não** soma na barrinha. Sem isso, a barrinha diria 38/38
com a metade das perguntas vazia — e o Fábio pararia de cobrar quem não
terminou.
- Alunos arquivados (`arquivado_em is not null`) e não-ativos ficam de fora.
- `teve_aula_no_mes`: houve aula do par professor×aluno no mês corrente.
- `dias_sem_aula`: preenchido só para quem tem `teve_aula_no_mes = false`.
- Ordenação: bloco "viu" primeiro (alfabético), depois bloco "não viu" (mais
  dias sem aula primeiro).

### `app_professor_feedback_salvar(...)`

```
app_professor_feedback_salvar(
  p_aluno_id       integer,
  p_feedback       text,                    -- verde | amarelo | vermelho
  p_pratica_em_casa text  default null,
  p_evolucao       text   default null,
  p_animo          text   default null,
  p_observacao     text   default null,
  p_competencia    date   default null      -- null = mês corrente BRT
) returns jsonb                             -- { "respondidos": 13, "total": 38 }
```

Upsert de **um** aluno pela chave única. É esta RPC que cada toque chama.

- Recusa aluno fora da carteira com `raise exception 'aluno_fora_da_sua_carteira'`
  — a mesma string que o app já trata em `alunoFicha`.
- `professor_id` vem de `fn_professor_do_usuario()`, **nunca** de parâmetro.
- `unidade_id` (not null na tabela) vem da carteira do aluno.
- Grava `teve_aula_no_mes` e `origem = 'la_teacher'` no insert; `atualizado_em`
  em todo toque.
- Devolve o progresso pra barrinha não precisar de segunda chamada.

### `app_professor_feedback_progresso()`

`{ "competencia": "2026-08-01", "total": 38, "respondidos": 12, "janela_aberta": true }`

Alimenta o card da Home, o Fábio e — depois — o mapa de aderência.

### `fn_janela_feedback_aberta(p_dia date default null)`

Helper imutável: verdadeiro nos **últimos 7 dias do mês** (`p_dia >= último dia
do mês − 6`). Existe separada pra ser testável sozinha e pra cron e RPC usarem
a mesma régua.

**Fuso:** toda data de "hoje" nasce em BRT (`(now() at time zone
'America/Sao_Paulo')::date`), nunca `current_date` cru. Entre 21h e meia-noite
o `current_date` do servidor já é amanhã — foi o que derrubou o teste 018.

---

## A edge function `transcrever-observacao`

`POST` com o áudio do gravador; devolve `{ "texto": "..." }`.

- Exige JWT de usuário autenticado.
- **Não persiste o áudio nem o texto.** O dado só nasce quando o professor
  chama `..._salvar` com o texto que ele revisou.
- Limite de duração no cliente (2 minutos) e recusa acima disso.
- Falha de transcrição não bloqueia: o campo continua digitável e o app avisa
  "não consegui transcrever, pode escrever aí".

---

## A UI

Tela nova em `src/features/feedback/`, rota dentro da área do professor.

**Componentes** (todos do DS existente — `docs/frontend-tokens.md`; nada de
recriar botão, card ou rótulo):

- `MesaFeedback` — a lista, os dois blocos, a barrinha.
- `CardAlunoFeedback` — a linha que expande no toque do coração.
- `CampoObservacao` — textarea com placeholder-convite e o botão de microfone.
- `CardFeedbackHome` — o card que sobe na Home na última semana.

**A barrinha**: reconstruída com os nossos tokens. O gradiente violeta→rosa do
LA Report **não vem junto** — é o Design System de lá. Aqui é a barra de
progresso do LA Teacher.

**Placeholder da observação** (texto exato):
> *"Algo que vale a coordenação saber — um elogio, um ponto de melhoria, uma
> mudança que você notou."*

**Estados**: salvando (o card mostra atividade), salvo (✓), falhou (marca e
oferece "tentar de novo"), transcrevendo (no campo).

**Card da Home** aparece quando `janela_aberta` **e** `respondidos < total`;
some sozinho ao fechar 100%.

---

## A governança

Três disparos, todos **ancorados no fim do mês** — nunca em dia da semana:

| Momento | Quem recebe | Ação |
|---|---|---|
| Último dia − 6 (1º dia da janela) | Todo professor com carteira | Lembrete com o percentual e o porquê |
| Último dia − 3 | Só quem está incompleto | Reforço com quantos faltam |
| Dia 1º do mês seguinte | **Coordenação** | A lista de quem não fechou o mês que acabou |

**Por que não é "a segunda e a quinta da janela".** Toda janela de 7 dias tem
exatamente uma de cada — mas a **ordem inverte**. Em agosto/2026 a janela é
25/08 (ter) a 31/08 (seg): a quinta cai no dia 27 e a segunda no dia 31, então
o reforço chegaria quatro dias **antes** do lembrete, e o lembrete no último
dia do mês. Quebra em todo mês que não termina em domingo. Ancorado no fim do
mês, ordem e espaçamento são os mesmos sempre, e sobram três dias para o
professor agir depois do reforço.

O lembrete leva o **percentual** e o **porquê** — a pedido do Alf: *"você já
respondeu X dos seus alunos; é importante pro mapa de sinais, pra gente
acompanhar a saúde do seu aluno e evitar evasão; tem gente chegando na
renovação."*

### Quem leva a mensagem

**O worker, não o cron.** A `fabio_notificacoes` não tem estado de entrada: o
`status` aceita `processando`, `enviada`, `falhou` e `pulada_*` — não existe
`pendente`. Uma linha que nasce `processando` com lease de 10 minutos e fica
horas esperando alguém buscar **não é uma fila, é uma mentira**: parece em voo
e não está. Por isso a sequência é a mesma da 066 — **RESERVA** (`processando`
+ lease) → **envia** → **CONCLUI** (`enviada` com recibo, ou `falhou` com o
erro) — e quem executa os três passos é o `fabio_notification_worker.py`, no
mesmo desenho de `briefing`, `pendencia` e `escalonamento`: unit systemd
própria com `--force`, o horário mora no timer.

**Não existe job `pg_cron` nesta entrega.** O banco expõe *quem deve ser
cobrado hoje* (função de leitura) e *reserve esta linha pra mim* (função de
reserva). Quem decide a hora é o timer; quem manda é o worker.

### A entrega à coordenação

Destino: o **grupo COORDENACAO PEDAGOGICA** no WhatsApp — o mesmo que já recebe
o escalonamento da cobrança de presença (`FABIO_GRUPO_COORDENACAO_JID`). Não se
inventa canal: a coordenação já lê governança de professor ali.

A mensagem é **uma só**, agregando todo mundo — não uma por professor — e tem
que ser **encaminhável**, no formato que o Alf escolheu para o escalonamento: o
coordenador copia o bloco de um professor e manda pra ele. Por isso vai a
relação nominal (professor, unidade, quantos de quantos), não um resumo.
Resumo não diz a ninguém o que fazer.

Conteúdo: a competência é o **mês que acabou**; entram só os professores com
carteira que **não fecharam**; a chamada de abertura diz quantos fecharam de
quantos, para a coordenação ter a régua antes da lista.

Na tabela, essa linha é diferente das outras duas: `destinatario_tipo =
'coordenacao'`, `professor_id` nulo e o JID do grupo em `destinatario_whatsapp`
— o que exige **estender** (nunca substituir) os dois CHECKs de destinatário,
mesma tática de vocabulário estendido usada em 018 e 036.

**Fora desta fatia, dito na cara:** a lista da coordenação **não** vira tela
neste spec. O painel da coordenação está em desenho, e RPC de leitura sem tela
que a chame é exatamente o defeito que esta seção existe para corrigir — função
pronta, chamador nenhum. Quando o painel existir, ele lê a mesma função.

### Idempotência

Duas travas, porque as linhas têm chaves diferentes:

- **Professor**: índice único parcial em `(professor_id, tipo, dia_referencia)`
  para `feedback_lembrete` e `feedback_reforco`.
- **Coordenação**: índice único parcial em `(tipo, dia_referencia)` para
  `feedback_coordenacao` — `professor_id` é nulo nessa linha, e em índice único
  do Postgres **nulos não colidem**: reaproveitar a chave do professor deixaria
  o grupo levar a mesma lista a cada rodada do timer.

Índice único e `on conflict` são **um contrato só**: quem mexe em um mexe no
outro, senão a trava de duplicata volta a ignorar o canal (defeito já visto no
briefing matinal).

---

## Bordas

| Caso | Comportamento |
|---|---|
| Aluno com dois professores | Cada professor responde o seu — a chave é por professor |
| Aluno com dois cursos do mesmo professor | Aparece **uma vez**, cursos concatenados |
| Aluno arquivado ou inativo | Não entra na mesa nem no denominador |
| Professor sem carteira | Empty state; e o cron não o enfileira |
| Professor entra fora da janela | Mesa aberta normalmente pela entrada em Alunos; sem card na Home |
| Mês vira com a mesa aberta | A competência é resolvida no servidor a cada chamada |
| Sem rede | Aluno marcado como não salvo, com "tentar de novo". Sem fila offline |
| Transcrição falha | Campo segue digitável, com aviso |

---

## Como se prova

Migration `073`, `073-*.test.sql` e `scripts/mutantes-073.mjs`, no padrão da
casa: tabela temporária `_res`, veredito por `json_build_object('falhas', …)`,
e a suite reaplicando em `BEGIN`/`ROLLBACK`. Âncora podre é **falha**, não
aviso.

**Mutantes obrigatórios** — cada um reintroduz um defeito real e o teste tem
que ficar vermelho:

1. `mesa` devolve carteira de outro professor (troca `fn_professor_do_usuario()`
   por parâmetro).
2. `salvar` aceita aluno fora da carteira (remove o guard).
3. `salvar` grava usando `professor_id` de parâmetro em vez do usuário logado.
4. `observacao` passa a ser selecionada num caminho family-safe.
5. Progresso conta aluno arquivado no denominador.
5b. Progresso conta como respondido quem só tem coração, com as três perguntas
   nulas — a barrinha fechando 38/38 sem ninguém ter terminado.
6. `fn_janela_feedback_aberta` abre a janela cedo demais (últimos 10 dias).
7. Dedupe removido: aluno com dois cursos conta duas vezes na barrinha.
8. `teve_aula_no_mes` gravado sempre `true`.
9. O reforço volta a cobrar quem já fechou.
10. `revoke`/`grant` das RPCs: `anon` consegue executar.
11. Os disparos voltam a ser ancorados em dia da semana — o teste varre os 12
    meses do ano e pega o mês em que o reforço cai antes do lembrete.
12. A linha da coordenação nasce com `destinatario_tipo = 'professor'` — a
    lista de quem não fechou vai para o professor em vez do grupo.
13. A dedupe da coordenação reusa a chave do professor: como `professor_id` é
    nulo ali, o grupo leva a mesma lista a cada rodada do timer.
14. A reserva conclui sem conferir o `lease_token` — mensagem entregue fica
    marcada por quem não reservou.

**Teste de fuso obrigatório:** um passo que roda com a data fixada às 22h BRT e
prova que a competência resolvida ainda é o mês corrente.

---

## Depois disto (fatias anotadas, fora deste spec)

1. **Mapa de aderência** — pedido do Alf no meio do brainstorm: medir a adesão
   dos professores ao que alimenta o mapa de sinais (semáforo, **aluno sem
   anamnese**, registro de aula) **com evolução no tempo** — *"começou com 50%,
   agora 60%, agora 70%"*. Os coordenadores gostam muito disso. A RPC de
   progresso deste spec já deixa o número do semáforo calculável.
2. **Cartão "Coração vermelho"** no Radar da coordenação — passa a ter fonte
   nativa quando esta coleta rodar um mês.
3. **Expectativa × anamnese** (sinal 10) como quarta pergunta.
4. **Dívida dos pesos** no LA Report: o pilar do professor deixa de valer zero
   assim que a coleta rodar, e aí os pesos chutados precisam ser revistos por
   quem é dono do score.
