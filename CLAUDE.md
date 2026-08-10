# LA Teacher — contexto que não pode se perder

## LEIA `RETOMADA.md` ANTES DE QUALQUER COISA

Combinado com o Alf em **08/08/2026**. Este arquivo aqui guarda o que **não
muda**; o `RETOMADA.md` guarda **onde a gente está agora** — e é ele que
sobrevive ao `/compact`.

O protocolo, na risca:

1. **Eu atualizo o `RETOMADA.md`** quando o contexto pesar, quando fechar um
   bloco, ou quando ele pedir checkpoint — sempre com **fato medido**
   (`git log`, consulta no banco, saída de comando), nunca com a minha lembrança
   da conversa. Lembrança é justamente o que o `/compact` corrói.
2. **Ele roda `/compact`.** É comando dele; eu não disparo.
3. **A primeira coisa que eu faço ao voltar é ler o arquivo** e seguir do
   `PRÓXIMO PASSO` — sem reabrir o que já está marcado como decidido, e sem
   perguntar de novo o que já foi respondido.
4. **Commitar sempre.** Checkpoint não commitado não sobrevive — é o mesmo erro
   de dizer "aplicado" sem push.

Por que arquivo no repo e não banco nem memória: fica versionado junto do
código, o Hugo e o Alfredo conseguem ler, e ninguém precisa de uma sessão minha
aberta pra saber onde a coisa parou.

## Toda tela é desktop E celular — as duas se conferem, sempre

Combinado com o Alf em **10/08/2026**, depois de eu entregar o Radar tendo
olhado só a janela larga: no celular a linha do aluno virava um empilhamento de
rótulos e o rodapé do modal ficava **debaixo da TabBar**. Estava "pronto" e
estava quebrado — porque metade do uso real acontece no celular.

Antes de dizer que uma tela está pronta, ela é vista **medida** nos dois
tamanhos, não imaginada:

- **390 × 844** (celular de referência) e **1400 × 900** (desktop com sidebar).
- No celular, checar o que só existe lá: **TabBar de 72px + `safe-area`** por
  cima do conteúdo, modal/bottom-sheet que precisa passar por cima dela
  (`z-50`, não `z-40` — empatado com a TabBar, quem vem depois no DOM ganha),
  e o fato de que **não existe hover**: informação que só aparece em tooltip
  não existe no celular.
- Redimensionar a janela **durante** a conferência, não só abrir no tamanho
  certo: foi redimensionando que apareceu a tarja preta do `h-svh` (a unidade
  de viewport não acompanha o container; a moldura usa `h-full` sobre o `#root`,
  que é quem tem a altura de verdade).

Layout diferente por breakpoint é permitido e às vezes obrigatório — o que não
é permitido é o mesmo layout apertado nos dois. `CoordenacaoFrame` × `AppFrame`
já é esse princípio no esqueleto; vale para a linha e para o card também.

## O Fábio é meu

Em **03/08/2026** o Alf passou o bastão: o Alfredo saiu para outras frentes e **eu sou o dono do Fábio** (Hermes + chat bridge). Não existe mais "eu aponto, o Alfredo aplica" — eu aplico.

Antes disso o combinado era read-only, e essa memória velha já me fez recusar trabalho que era meu. Se bater a dúvida "será que eu posso mexer?": pode.

### Mexeu no Fábio? Pergunta pra ele antes de dizer que está pronto

Prática do Alfredo, que o Alf me passou em **04/08/2026**: ele conversa com os agentes — manda a pergunta, lê a resposta, e só então decide se está certo. Não valida só a arquitetura.

```bash
ssh -i ~/.ssh/id_ed25519_lahq_fabio_claude_code fabio@89.116.73.186 \
  'cd ~/fabio-chat-bridge && set -a && . ~/.hermes/.env && set +a && \
   python3 falar_com_fabio.py "quem é a aluna Fernanda?" --sem-historico'
```

`vps/fabio/falar_com_fabio.py` chama o mesmo `generate_answer()` da fila e **não** envia WhatsApp nem grava na `fabio_chat_mensagens`.

**A resposta é o produto; o contexto é insumo.** Eu já provei que o dado certo chegava no prompt e reportei como resolvido sem nunca ter perguntado nada pro Fábio. Três coisas que o teste precisa ter:

- **`--sem-historico`** — com histórico ele pode estar lendo o briefing das 8h em vez de consultar de verdade
- **o caso oposto** — aluno novo acertar é metade; aluno antigo não pode virar "novo"
- **uma pergunta comum** — pra provar que o gatilho novo não deixou o Fábio ruidoso

## Acesso à VPS (o que eu já esqueci uma vez)

```bash
ssh -i ~/.ssh/id_ed25519_lahq_fabio_claude_code fabio@89.116.73.186
```

⚠️ **A chave é essa.** Não é a `id_ed25519` padrão, e o `~/.ssh/config` **não** tem entrada para ela — o host `lahq` do config aponta para `root` com outra chave. Sem `-i` explícito o login falha com `Permission denied (publickey,password)`, e é fácil concluir errado que não tenho acesso. Já aconteceu.

Auditado em 03/08/2026: usuário `fabio`, host `la-hq`, grupos `fabio users`.

**O que eu posso:** ler e **escrever** em tudo sob `~` (dono é `fabio:fabio`), e **parar/iniciar os serviços** — eles são *user services* do systemd, então não precisa de sudo:

```bash
systemctl --user restart fabio-hermes-gateway.service
systemctl --user restart fabio-chat-bridge.service
```

**O que eu não posso:** `sudo` (pede senha). Nada fora de `~` precisa ser tocado.

## Mapa da VPS

| Caminho | O que é |
|---|---|
| `~/.hermes/` | O cérebro. `.env`, `config.yaml`, `SOUL.md`, `PERMISSOES.md`, `AGENTS.md` |
| `~/.hermes/skills/` | **Sistema de skills já existe.** A da casa é `la-music`; o resto é genérico |
| `~/.hermes/hermes-agent/skills/` + `optional-skills/` | Skills do agente |
| `~/.hermes/.skills_prompt_snapshot.json` | Snapshot do prompt montado a partir das skills (~44 KB) |
| `~/fabio-chat-bridge/` | Ponte app ↔ WhatsApp (a fila do chat) |
| `~/la-teacher/` | Cópia do repo na VPS |
| `~/backups/`, `~/.hermes/backups/` | Backups — o `.env` e o `config.yaml` têm histórico de `.bak` |

## Os outros repositórios: SEMPRE `git pull` antes de mexer

Combinado com o Alf em **05/08/2026**: *"toda vez que você for mexer em algum
outro repositório, você vê se tem commit que andou"*. Ele **não** vai me avisar —
é obrigação minha checar, não dele lembrar.

```bash
git -C D:/la-performance-report fetch -q && git -C D:/la-performance-report status -sb | head -1
```

Se estiver atrás, `git pull` **antes** de editar qualquer linha. Editar em cima de
uma cópia velha e dar push é como o trabalho de outra pessoa é apagado sem que
ninguém veja.

| Caminho local | Repo | Ritmo |
|---|---|---|
| `D:/la-performance-report` | `LucianoAlf/LAperformanceReport` | **anda muito** — o Alf mexe direto |
| `D:/anamnese-la-music` | `LucianoAlf/anamnese-la-music` | esporádico |
| `D:/la-journey` | `LucianoAlf/la-journey` | em construção |

⚠️ **Clone, nunca cópia.** Cópia de arquivo envelhece em silêncio; clone se
atualiza com `pull` e acusa divergência. O `.env` de cada um fica no próprio
clone, fora deste repo.

## Duas sessões, o mesmo checkout — não é worktree separada

Descoberto em **10/08/2026**: quando duas sessões minhas trabalham ao mesmo
tempo neste repositório, elas não são cópias isoladas — é o **mesmo
checkout**. A prova veio do próprio git: a outra sessão commitou e deu push, e
o `main` **local** desta sessão já refletia o commit dela sem eu rodar
`git pull` — as duas leem o mesmo `.git/refs/heads/main`.

Isso quase custou caro uma vez: eu ia criar a migration `083`, e o número já
estava ocupado no **disco** por um arquivo que a outra sessão ainda não tinha
commitado — `git log` não via, `ls supabase/migrations` via. Renumerei antes
de aplicar (ver `numero-de-migration-livre-no-log-ocupado-no-disco` na
memória). Da próxima vez pode não sobrar tempo de perceber.

**O que isso muda no que é seguro fazer:**

- **NUNCA** `git add -A`, `git add .`, `git commit -a`, `git stash` (sem
  `-u` já é arriscado; com `-u` guardaria o trabalho não commitado da outra
  sessão junto do meu), `git reset --hard`, `git clean`, `git checkout .` —
  todos operam na árvore de trabalho **inteira**, que agora é compartilhada.
  Sempre `git add <arquivo1> <arquivo2> ...` nomeando exatamente os arquivos
  da tarefa.
- Antes de criar um número de migration (ou qualquer arquivo numerado) novo,
  `ls` no disco — nunca só `git log`.
- Antes de commitar, `git status` e conferir que só os arquivos esperados
  estão staged.
- Arquivo novo ou estranho aparecendo no `git status`: **não mexe**. Não é
  lixo — é trabalho em andamento do outro lado. Vale a regra geral de nunca
  apagar o que não criei sem entender primeiro, em dobro.
- Despachando subagente: repetir estas regras no despacho, sempre — regra da
  casa não viaja sozinha (ver `regra-da-casa-nao-viaja-no-subagente`).

**Para trabalho grande planejado com antecedência** (não descoberto no meio,
como desta vez): preferir `git worktree` por sessão — cada uma com índice e
árvore de trabalho próprios, elimina o risco por completo — e abrir PR pra
integrar em vez de as duas martelando o `main` direto. Ver skill
`superpowers:using-git-worktrees`.

## A mesma função pode morar em mais de um repo

Em 05/08/2026 a `notificar-anamnese` existia em **três**: aqui, no
`anamnese-la-music` e no `LAperformanceReport` — e as duas cópias eram versões
antigas. Um `supabase functions deploy` a partir delas desfaria o conserto em
silêncio.

A fonte é **este repo**. Nos outros ficou um `LEIA-ANTES-DE-DEPLOYAR.md` sem
`index.ts` — assim o deploy falha em vez de sobrescrever. Antes de mexer numa
edge function, vale um `git grep` pelo nome dela nos outros clones.

## O banco é compartilhado

LA Teacher, Fábio, Sol e LA Report vivem no **mesmo projeto Supabase**: `ouqwbbermlzqqvtqwlul` (LA Performance Report). A edge function `fabio-registro-aula` é publicada de lá, e o motor de relatório (`gerar-relatorio-pedagogico`) também. Juntar dados entre esses sistemas é SQL, não integração.

`pg_cron` 1.6.4 e `pg_net` 0.19.5 estão instalados, e o padrão da casa para rotina é cron → `net.http_post` → edge function (ver `processar-conversa-evasao-cada-minuto`).
