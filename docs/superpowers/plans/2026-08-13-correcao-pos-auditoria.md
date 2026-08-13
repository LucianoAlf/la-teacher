# Plano de correção pós-auditoria — 13/08/2026

> **Origem:** auditoria ao vivo de 13/08/2026 (VPS + banco + logs + bridge),
> feita depois da retomada do trabalho que passou pelo Codex nas PRs #4–#12.
> Cada número aqui é **fato medido**, não lembrança: saída de `journalctl`,
> consulta no Supabase `ouqwbbermlzqqvtqwlul`, execução do runner de teste SQL.
>
> **Regra que vale pra todo checkpoint:** nenhum item fecha por leitura de
> código nem por teste transacional sozinho. Fecha com **prova real na VPS** —
> serviço rodando, log observado, e quando couber, pergunta feita ao Fábio pelo
> `falar_com_fabio.py`. Verde de harness não substitui o sistema vivo.

## Como usar este documento

- Os sprints são sequenciais. **Não emenda dois checkpoints sem fechar o
  anterior** — a prova real é a porta.
- Cada checkpoint tem `PROVA:` explícita. Se a prova não puder ser produzida,
  o checkpoint **não fecha** — ele volta pro plano com o motivo escrito.
- Ao fechar cada sprint, atualizar o `RETOMADA.md` e commitar. Checkpoint não
  commitado não sobrevive.

## Regras da casa que este plano herda

- **Checkout compartilhado:** duas sessões usam o mesmo `.git`. Nunca
  `git add -A`, `git add .`, `git commit -a`, `git stash`, `git reset --hard`,
  `git clean`, `git checkout .`. Sempre `git add <arquivo1> <arquivo2>`
  nomeando exatamente os arquivos da tarefa.
- **Número de migration:** conferir no **disco** (`ls supabase/migrations`),
  nunca só no `git log` — a outra sessão pode ter escrito sem commitar.
- **Nada sintético em produção.** Fixture em banco compartilhado vaza pra quem
  lê a mesma tabela (já aconteceu: unidade "TESTE" entrou no funil do LA
  Report). Fixture só com dono, prazo e remoção provada no mesmo checkpoint.
- **Nada sai automaticamente pra família, professor ou comercial** durante os
  testes.
- **Push antes de dizer "aplicado".**

---

## Quadro dos problemas auditados

| # | Problema | Gravidade | Vivo? | Sprint |
|---|---|---|---|---|
| P5 | Registro real do professor 3 expirando sem virar aula | Alta / prazo hoje | sim | 0 |
| P1 | Laço infinito no cleanup do reconciler | Alta | sim | 1 |
| P2 | CRLF cega as âncoras multilinha dos mutantes | Alta (garantia) | sim | 2 |
| P3 | 093 e 099 BLOQUEADOS por contrato superado | Média | não | 2 |
| P4 | Mutantes que sobrevivem de verdade | A medir | ? | 3 |
| P6 | Três contagens pra mesma carteira (20 × 21 × 23) | Média | sim | 4 |
| P7 | `node_modules` quebrado — suíte unitária não roda aqui | Média | sim | 5 |
| P10 | Gateway sai com `status=1/FAILURE` em todo stop | Baixa | sim | 5 |
| P9 | 3 branches remotas com commit próprio não integrado | Baixa | — | 5 |
| P8 | Advisors: 5 `rls_disabled_in_public` + 9 `security_definer_view` | Decisão do Alf | sim | 5 |

---

# Sprint 0 — o registro que evapora hoje ✅ FECHADO 13/08

**Por que é o primeiro:** é o único item com prazo. Um professor gravou uma
aula de verdade e o trabalho dele some se ninguém agir.

> **Resultado:** os quatro checkpoints fecharam em 13/08. A professora é
> **Daiana Pacifico da Silva dos Anjos** (`professor_id` 3), ativa. O prazo foi
> estendido para **16/08 15:37 UTC** e o Fábio **reenviou a pergunta** — envio
> provado no log (`whatsapp_sent`, `professor_id: 3`, `phone_tail: 9985`,
> `msg_id 5521998250178:3EB001F81EEADBA1B8D446`). A ação segue `aberta`, com a
> transcrição intacta e **2 eventos** na trilha, incluindo
> `shortlist_reenviada_manual` gravado em `fabio_acao_eventos`. Nenhuma
> mensagem foi para família ou comercial.
>
> **Achados novos que o sprint produziu — entram no backlog, ver o fim deste
> documento:** F-A (a shortlist não usou o nome da aluna para desambiguar) e
> F-B (ação aberta não é lembrada por ninguém e expira em silêncio).

### Contexto medido

Ação `8593cf8d-4e73-4bb4-b4ba-b8d98c418580`, professor 3, criada em
**12/08 19:12 UTC**, estado `aberta`, expira **13/08 19:12 UTC** (16:12 BRT).
O Fábio mandou a shortlist (`ultima_resposta_wa_id` termina em
`shortlist_definida`) com **2 aulas candidatas** — `217860` e `205008`. O
professor nunca respondeu.

A transcrição está **inteira** no `payload`: aula da aluna Beatriz Ohana, com
aquecimento vocal, articulação, respiração intercostal, e um dado de saúde
relatado pela aluna (desvio de septo, em fase de exames para possível
cirurgia). Não é rascunho descartável.

### CP-0.1 — Salvar o texto antes de qualquer coisa

Exportar a transcrição e o contexto da ação para fora da tabela, porque a
limpeza do reconciler (P1) age em linhas expiradas.

**PROVA:** arquivo salvo fora do repo com o texto íntegro + o `id` da ação, e
`diff` conferido contra o `payload` do banco.

### CP-0.2 — Decidir com o Alf o destino

Três saídas possíveis, e **a escolha é do Alf, não minha** — envolve falar com
um professor:

1. O Fábio reenvia a pergunta ao professor 3 agora, com prazo estendido.
2. A coordenação identifica a aula (são só 2 candidatas) e o registro é criado
   com autoria explícita de quem decidiu.
3. Deixa expirar e o texto fica arquivado como evidência.

**PROVA:** decisão registrada aqui no plano, com data.

### CP-0.3 — Executar a decisão e provar

**PROVA:** se virar registro — `fabio_registros_aula` com a fatia da Beatriz e
a origem correta, conferido por consulta. Se for reenvio — mensagem observada
saindo no log do bridge. Se for arquivamento — o texto salvo no CP-0.1 com o
motivo escrito.

### CP-0.4 — Entender por que ficou 20h parado ✅

**Resposta medida: não existe lembrete nenhum.** Varredura em
`~/fabio-chat-bridge`: o **único** arquivo que toca `fabio_acoes_pendentes` é
`fabio_whatsapp_actions.py`, que é o handler **reativo** — só roda quando chega
mensagem. Nenhum worker e nenhum timer olha ação `aberta` ou `expira_em`.

Consequência estrutural: ação que o professor não responde **não é lembrada,
não alerta ninguém e expira em silêncio** — e depois a limpeza do reconciler
apaga o objeto de áudio. Vira F-B no backlog.

### Correção de um alarme meu, registrada para não voltar

Durante o CP-0.3 eu **suspendi o envio** achando que havia troca de identidade:
`professor_phone(3)` resolve um número terminado em `9985`, e o
`wa_message_id` da ação começa com `5521998250178` —
`fabio_identidade_whatsapp('5521998250178')` responde `numero_nao_cadastrado`.

**Era alarme falso, e a medição que fecha é esta:** o prefixo `5521998250178`
aparece em **92 mensagens de 6 professores diferentes**, nos dois papéis
(`professor` e `fabio`). É a **linha do próprio Fábio**, não o número de
ninguém — por isso é constante nas duas direções. O envio proativo para a
Daiana está correto e funciona (10 envios registrados para `...9985`, mais o
deste checkpoint).

Fica escrito porque a checagem seca (`professor_phone` × prefixo do
`wa_message_id`) **parece** uma prova de troca de identidade e não é. Quem
repetir esse caminho vai tropeçar na mesma pedra.

---

# Sprint 1 — o laço do reconciler ✅ FECHADO 13/08

> **Resultado:** os sete checkpoints fecharam. Migration
> `20260813160000_limpeza_nao_se_repete.sql` aplicada e registrada no ledger.
> O laço **parou ao vivo** e a limpeza **continua funcionando** — as duas
> provas, não só a primeira.
>
> | checkpoint | prova |
> |---|---|
> | CP-1.1 | RED com **exatamente um** passo divergindo: *"acao ja limpa NAO e reivindicada de novo"*. Os outros cinco passaram — o teste isolou o defeito. |
> | CP-1.2 | GREEN, sem divergência, schema e linhas vivas idênticas. |
> | CP-1.3 | **5/5 mutantes mortos sobre baseline verde.** |
> | CP-1.4 | Cláusula no ar, comentário gravado, ACL `anon=false / authenticated=false / service_role=true`; versão `20260813160000` registrada em `schema_migrations`. |
> | CP-1.5 | `journalctl` ao vivo: `claimed:5` → **`claimed:0` e fica**, por 8 ciclos seguidos. |
> | CP-1.6 | Fixture controlado (objeto real no bucket): **exatamente um** `claimed:1, limpas:1`, depois 0 estável. Objeto sumiu do Storage, carimbo gravado, lease liberado. Fixture removido com **zero resíduo** em ações, Storage e eventos órfãos. |
> | CP-1.7 | As 5 linhas antigas já estão limpas, já têm `encerrado_em` e agora são inertes. **Decisão: ficam** como trilha da auditoria; o carimbo documenta o que houve. |
>
> Regressão no vizinho: teste da `092` (contrato do reconciliador) segue verde.
>
> **Duas lições que este sprint pagou, e que valem para o Sprint 3:**
>
> 1. **O primeiro `5/5` foi falso.** O teste base tinha quebrado (fixture com
>    `payload` nulo violando NOT NULL) e os cinco mutantes "morreram" de erro,
>    não de asserção. É a armadilha do mutante que morre de sintaxe, e ela
>    imita um placar perfeito. **Conferir o baseline VERDE antes de ler
>    qualquer placar de mutante** virou passo obrigatório.
> 2. **Um mutante impossível é informação.** Não dá para provar o `coalesce` do
>    payload porque a coluna é NOT NULL — então isso está escrito na migration
>    e no runner, em vez de fingir cobertura. Cobertura declarada e não medida
>    é pior que buraco conhecido.
>
> **Achado lateral, não consertado (entra no Sprint 3):** a mesma família de
> laço existe no caminho `bloqueadas`. Quando `fabio_provar_limpeza` recusa, o
> worker faz `continue` **sem** chamar o `concluir`, então o lease expira em
> 120s e a linha volta pra sempre. Hoje não dispara (`bloqueadas: 0` em todas
> as execuções medidas), mas uma linha permanentemente reprovada —
> `registro_confirmado_referencia_storage`, por exemplo — entraria em laço de
> 120s. Não mexi: está fora do defeito medido e merece o seu próprio RED.

### Contexto medido

`fabio-whatsapp-reconciler` roda a cada ~35s. Em 13/08:
**1493 de 1499 execuções idênticas** — `{"claimed":5,"limpas":5,"bloqueadas":0,"falhas":0}`.

As 5 linhas são artefatos do E2E (`whatsapp/10/e2e-isaque-*.webm`) de 11–12/08.
E já estão limpas: `objeto_ainda_existe = false` no `storage.objects`, e o
`payload` já carrega `limpeza.removido = true`.

**Causa exata.** `fabio_claim_acoes_limpeza` seleciona por:

```sql
where a.estado in ('cancelada','expirada','erro') and a.storage_path is not null
  and (a.lease_token is null or a.lease_expira_em < now())
```

`fabio_concluir_limpeza` grava `payload.limpeza`, zera `lease_token` e
`lease_expira_em`, e carimba `atualizado_em = now()`. **Ela não muda nenhuma
coluna do predicado.** A linha requalifica no ciclo seguinte, pra sempre.

**Custo:** ~7.500 ciclos/dia. Cada ciclo faz `fabio_provar_limpeza` (duas
vezes — uma no Python, outra dentro do `concluir`), um `DELETE` no Storage e o
`concluir`. Perto de **22 mil chamadas inúteis por dia**. E `atualizado_em`
dessas linhas é reescrito a cada 35s, o que apaga o valor de auditoria da
coluna. Os `RuntimeError: ..._rpc_failed_522` de 12/08 20:54–20:55
provavelmente nasceram desse martelo.

### CP-1.1 — Teste que reproduz o laço, antes do conserto

Teste SQL transacional que: cria uma ação em estado terminal com
`storage_path`, roda `claim` → `concluir`, e roda `claim` **de novo**.
Hoje ele tem que **falhar** (a segunda chamada devolve a mesma linha).

**PROVA:** o teste roda vermelho contra a produção atual, com a divergência
nomeada. Teste que já nasce verde não prova nada.

### CP-1.2 — Fechar o ciclo

Migration nova (número conferido **no disco**) que faz a linha sair do
predicado depois de limpa. Direção preferida: o `claim` passa a exigir que a
linha **não tenha** o carimbo de limpeza —

```sql
and not (a.payload ? 'limpeza')
```

— porque preserva o `storage_path` como evidência do que existiu, em vez de
apagá-lo. A alternativa (zerar `storage_path`) fecha o laço mas queima a
trilha.

**PROVA:** CP-1.1 vira verde.

### CP-1.3 — Mutantes que morrem

No mínimo três, e cada um tem que morrer:

- M1 — o `claim` volta a ignorar o carimbo de limpeza (reintroduz o laço).
- M2 — o `concluir` para de gravar o carimbo (laço por outra porta).
- M3 — o `claim` passa a ignorar **também** linhas ainda não limpas
  (conserta o laço quebrando a limpeza — o erro oposto, que é pior).

**PROVA:** `3/3 mortos`, **e zero STALE**. Como o Sprint 2 ainda não rodou,
escrever as âncoras deste mutante **em linha única** ou normalizando `\r\n`,
senão elas nascem podres como as do Codex.

### CP-1.4 — Aplicar em produção

**PROVA:** migration registrada em `supabase_migrations.schema_migrations`,
conferida por consulta.

### CP-1.5 — Prova real na VPS: o laço parou

Observar o `journalctl` do reconciler por **no mínimo 10 ciclos** (~6 min)
depois de aplicar.

**PROVA:** `claimed` cai pra `0` e **fica** em 0. Colar as linhas do log.

### CP-1.6 — Prova real na VPS: a limpeza NÃO morreu

O risco do conserto é fechar o laço matando a função. Criar **uma** ação
controlada, de dono conhecido, com `storage_path` de teste explícito e objeto
real no bucket, em estado terminal.

**PROVA:** o reconciler limpa ela **exatamente uma vez** (um `claimed:1` e
depois `claimed:0` estável), o objeto some do Storage, e a linha de teste é
**removida ao fim do checkpoint** com pós-verificação de zero resíduo.
Nenhuma mensagem sai pra ninguém.

### CP-1.7 — Decidir o destino das 5 linhas velhas

Elas já estão limpas e agora ficam paradas. Decidir: arquivar, marcar como
encerradas, ou deixar. **PROVA:** decisão escrita + estado final conferido.

---

# Sprint 2 — devolver visão à rede de mutantes ✅ FECHADO 13/08

> **Resultado:** os cinco checkpoints fecharam, e o sprint achou um problema
> **maior** que o CRLF.
>
> **CP-2.2 — a causa foi medida, não deduzida.** Template literal em JavaScript
> normaliza `\r\n` para `\n` **por especificação**: medido âncora por âncora,
> nenhuma continha `\r`, e **100% delas casavam com a versão LF** do `.sql`.
> Ou seja, o fim de linha do `.mjs` é irrelevante — só os `.sql` precisavam
> mudar. `.gitattributes` criado (`*.sql`, `*.mjs`, `*.test.sql` → `eol=lf`) e
> 61 arquivos normalizados. **`git diff --numstat` = zero arquivos:** nenhuma
> mudança de conteúdo, só fim de linha.
>
> **CP-2.3 — o placar verdadeiro, e a armadilha de novo.** A normalização
> recuperou cobertura real, mas ao ler o placar eu quase repeti o erro do
> Sprint 1: `090` e `091` passaram a reportar **10/10** e os **baselines das
> duas FALHAM** contra a produção. Vinte "mortos" que não provam nada.
>
> | suíte | baseline | antes → agora | vale? |
> |---|---|---|---|
> | `20260812163000` | ✓ verde | 17/28 → **28/28** | **sim** |
> | `094` | ✓ verde | 0/7 → **6/7** | sim — 1 sobrevivente real |
> | `20260813004713` | ✓ verde | 1/5 → **4/5** | sim — 1 sobrevivente real |
> | `090` · `091` | ✗ **falha** | "10/10" | **não — falso** |
> | `095` | ✗ falha | não verificável | não |
>
> **A trava que faltava.** Nenhum runner desta casa conferia o baseline —
> por isso a mentira passou duas vezes num dia. Criado
> `scripts/lib-baseline.mjs` com `exigirBaselineVerde()`, e **testado nos dois
> sentidos**: deixa passar com baseline verde (4/4 na suíte nova) e **barra**
> com o baseline vermelho da `091`. Ligado nos dois runners novos; estender aos
> outros 62 é item do Sprint 3.
>
> **CP-2.4 — SUPERADA sem desarmar guarda.** As duas migrations bloqueadas
> carregavam guardas de ACL válidas (medidas corretas em produção). Antes de
> marcar, as guardas foram **resgatadas** para
> `20260813170000_guardas_resgatadas_da_presenca.sql` — aplicada, registrada e
> com **4/4 mutantes mortos sobre baseline verde**. Só então `093` e
> `20260812135033` ganharam o marcador; o runner agregado já classifica a `093`
> como superada.
>
> **CP-2.5** — o mesmo `094/M6` que era `STALE — ancora do replay de devolutiva
> nao e unica` agora aparece como `OK morto`.
>
> **Achados novos para o Sprint 3, todos medidos:**
>
> - `090`, `091` e `095` têm **baseline vermelho** — a suíte inteira delas é
>   decoração hoje. Diagnosticar cada uma.
> - **`094/M4` sobrevive de verdade**: "ledger de correcao perde a unicidade da
>   acao". Sobrevivente real, com baseline verde.
> - **`20260813004713/M4` sobrevive de verdade**: remover o índice único
>   `uq_fabio_fila_audio_experimental_path` não mata. A própria migration
>   afirma que ele é "segunda barreira independente do lock" — e **nada prova
>   essa afirmação**.
> - `mutantes-095.mjs` exige alvo **local** e o runner da casa é remoto: ele
>   nunca verificou nada aqui. Bloqueio arquitetural, não âncora.
> - **3 testes órfãos que nunca entram na bateria agregada** — `097`, `098` e
>   `099` têm `.test.sql` sem `.sql` de mesmo nome, e o runner pareia por nome.
> - Estender `exigirBaselineVerde()` aos outros 62 runners.

## (plano original abaixo)

# Sprint 2 — devolver visão à rede de mutantes

**Por que vem antes de consertar defeito:** enquanto a rede está cega, qualquer
"verde" da frente recente é decoração. Consertar código com a rede cega é
repetir o erro que a auditoria achou.

### Contexto medido

O Codex reportou **5/5 mutantes** na fila experimental. Medido aqui: **1/5, 4
STALE**.

Causa provada com node:

```
20260813004713_audio_experimental_duravel.sql  CRLF=153  LF-solo=0
M2 com LF   -> false
M2 com CRLF -> true
```

`core.autocrlf=true`, **sem `.gitattributes` no repo**. Os `.sql` que vieram
das PRs do Codex chegam em CRLF no checkout; as âncoras dos mutantes são
escritas com `\n` dentro de literais JS. Âncora de **uma linha** casa; âncora
**multilinha nunca casa**. Por isso M1 mata e M2–M5 são STALE.

Isto **não é mentira do Codex**: na máquina dele (Linux, LF) as 5 casavam. É
esta máquina que degrada — e degrada em silêncio parcial, porque o script
imprime `STALE` mas o placar final passa a vista como resultado.

**Alcance: 47 arquivos `.sql` em CRLF** — e são exatamente `090`–`096` e todos
os datados de 12–13/08, ou seja o trabalho inteiro das PRs #4–#11.

Placar real medido hoje:

| suíte | resultado |
|---|---|
| 090 | 8/10 (2 âncoras podres) |
| 091 | 7/10 (3 podres) |
| 094 | **0/7 — todas podres** |
| 095 | falha de âncora (M0 e M2) |
| 20260812163000 | 17/28 |
| 20260813004713 | 1/5 |
| 093 · 20260812135033 | BLOQUEADOS (ver CP-2.4) |

### CP-2.1 — Combinar a janela com a outra sessão

A renormalização toca 47 arquivos. Em checkout compartilhado isso **precisa**
da outra sessão parada.

**PROVA:** confirmação do Alf de que a outra sessão está parada, e
`git status` limpo imediatamente antes de mexer.

### CP-2.2 — `.gitattributes` + renormalizar

Criar `.gitattributes` com, no mínimo:

```
*.sql text eol=lf
*.mjs text eol=lf
```

e renormalizar só os arquivos de `supabase/migrations/`, nomeando-os.

**PROVA:** o node que mediu o CRLF passa a reportar **0 arquivos com CRLF**;
`git diff --check` verde.

### CP-2.3 — O placar verdadeiro aparece

Rodar **todas** as suítes de mutante das migrations que estavam em CRLF.

**PROVA:** tabela nova de placar, com **zero STALE**. O que sobreviver vira
entrada do Sprint 3 — não se conserta nada aqui.

### CP-2.4 — Classificar os dois BLOQUEADOS

Ambos já foram diagnosticados na auditoria e **não são defeito vivo**:

- **093** — replaya uma versão antiga do `fabio_criar_registro` sobre o schema
  de hoje e acusa `presencas_antes=1`. Descartado como alarme falso: a função
  em produção **não referencia `aluno_presenca`**, não há trigger de presença
  em `fabio_registros_aula`, e nenhuma das **8** funções que dão `INSERT` em
  `aluno_presenca` é chamada por ela.
- **099** — cobra recibo pra registro com `origem='app'`. A resposta atual é
  literalmente `{"motivo": "origem_app", "skipped": true}`, que é o
  comportamento **novo e correto**, introduzido de propósito pela
  `20260812163000_recibo_so_whatsapp_e_fila_ativa`.

Os dois foram superados pela `20260812163000`. Marcar com o mecanismo que a
casa já tem: `-- SUPERADA POR: 20260812163000_recibo_so_whatsapp_e_fila_ativa.sql`
(regex `^--\s*SUPERADA POR:\s*(.+)$`, dentro dos primeiros 4000 chars).

**PROVA:** o runner agregado passa a classificar as duas como **superadas**, e
não como falha. **Cuidado medido:** marcar SUPERADA desarma a suíte junto — se
alguma dessas duas guardava mutante de segurança, ele tem que ser
**repontado** pra migration viva antes da marcação, não perdido. Conferir
antes de marcar.

### CP-2.5 — Prova real: a rede pega um defeito de verdade

Rede consertada só vale se pegar algo. Escolher **um** mutante que hoje é
STALE, aplicá-lo, e confirmar que agora ele **morre**.

**PROVA:** o mesmo mutante que era STALE aparece como `OK morto`.

---

# Sprint 3 — matar o que sobreviver ✅ FECHADO 13/08

> **Segunda passada — os dois sobreviventes caíram, e tinham a MESMA raiz.**
>
> | suíte | antes | agora |
> |---|---|---|
> | `094` | 6/7 | **7/7** |
> | `20260813004713` | 4/5 | **5/5** |
>
> **A raiz comum:** os dois mutantes mexiam em DDL com `if not exists`
> (`create table if not exists`, `create unique index if not exists`). No replay
> contra a produção esses blocos **não executam** — o objeto já existe. Alterar
> o texto deles não muda nada, então o mutante nunca podia ser pego. Era
> impossível de morrer, não "difícil".
>
> **O conserto foi o mesmo nos dois:** o mutante passou a **derrubar o objeto de
> verdade** (`drop constraint` / `drop index`, dentro da transação descartável
> do runner), e o teste ganhou o passo de catálogo que o pega. Nos dois casos o
> objeto foi medido em produção antes: a constraint `UNIQUE (tipo, acao_id)` e o
> índice `uq_fabio_fila_audio_experimental_path` **existem** — não havia defeito,
> havia cobertura fantasma.
>
> Ganho colateral que vale registrar: a `20260813004713` **afirmava em
> comentário** que o índice era "segunda barreira independente do lock". Essa
> afirmação agora é **provada** por um mutante que morre, em vez de ser só uma
> frase bonita no arquivo.
>
> **Nove runners mexem em DDL `if not exists`** e podem ter a mesma cobertura
> fantasma: `062`, `064`, `066`, `075`, `076`, `094`✅, `095`, `20260812163000`,
> `20260813004713`✅. Os dois marcados foram consertados; os outros sete ficam
> como dívida conhecida, não como surpresa.
>
> **A trava de baseline foi ligada em 60 runners** (64 no total: 4 já tinham).
> Três ficaram de fora por não seguirem o padrão `ORIGINAL`/`TESTE`:
> `059`, `095`, `20260812163000`. `node --check` em todos: **zero erro de
> sintaxe**. E ela dispara de verdade — rodar `mutantes-090` agora devolve
> `BASELINE VERMELHO` em vez do 10/10 falso de antes.
>
> **O laço latente de `bloqueadas` fica documentado, não consertado — de
> propósito.** Medido hoje: `elegiveis_hoje = 0`, `bloqueio_permanente = 0`,
> `bloqueio_temporario = 0`. Ele **não pode disparar**. E tem uma bifurcação de
> desenho que não é minha para resolver sozinho:
>
> - `acao_ativa_referencia_storage` é bloqueio **temporário** — a ação viva vai
>   terminar, e reentrar na fila depois é o comportamento certo.
> - `registro_confirmado_referencia_storage` é **permanente** — um registro
>   confirmado sempre vai referenciar aquele path, e reentrar a cada 120s é laço.
>
> Tratar os dois igual erra de um lado ou do outro. **Decisão pro Alf:** o
> permanente vira carimbo (sai da fila e fica com o motivo escrito) ou vira
> pendência visível pra alguém resolver?

## (primeira passada, 13/08)

# Sprint 3 — matar o que sobreviver 🟡 EM ANDAMENTO (13/08)

> **Feito nesta passada.** A bateria `09` saiu de **2 FALHARAM** para
> **0 FALHARAM** (3 passam · 3 superadas · 1 não reaplicável).
>
> **Os três baselines vermelhos, diagnosticados:**
>
> | | causa medida | destino |
> |---|---|---|
> | `090` | `create table` sem `if not exists` — não replayável por construção | fica como "sem harness reaplicável" |
> | `091` | `42P13` — a `092` mudou a assinatura de `fabio_status_audio_fila` de propósito | `SUPERADA POR: 092` |
> | `095` | `42P10` — `ON CONFLICT` sem o predicado do índice parcial | `SUPERADA POR: 20260812004430` |
>
> **O incidente que estava escondido atrás disso.** O `42P10` da `095` não é
> teoria: em **12/08 00:40 UTC** o log registrou
> `notify_worker_registro_recibo_entregue_mas_nao_fechado`, status
> `delivered_unclosed` — o recibo **foi entregue** ao professor 10 e a função
> que fecha quebrou. Só não virou duplicata porque um caminho de recuperação a
> fechou com o marcador sintético `recovered-delivered-unclosed` (1 notificação
> afetada, `tentativas=1`). O Codex corrigiu **quatro minutos depois**, na
> `20260812004430_fix_registro_recibo_partial_conflict.sql`, que é o que a
> produção usa hoje.
>
> **E os dois achados eram a mesma história.** O teste daquela correção é o
> `097-registro-recibo-partial-conflict.test.sql` — um dos **três órfãos**. Ele
> nunca rodou, por dois motivos somados: nome que não pareia com o da migration
> (o runner pareia por nome) **e** `begin;/rollback;` próprios, que o runner
> recusa porque é ele o dono da transação. Duas camadas de silêncio sobre a
> guarda de um defeito que já tinha mordido a produção.
>
> **Os três órfãos foram pareados e convertidos** ao formato da casa,
> preservando exatamente o que afirmavam. Não há mais teste órfão no repo.
>
> **Um mutante pagou por si.** Ao escrever `mutantes-20260812004430`, o **M1**
> — que reintroduz literalmente o defeito de 12/08 — **sobreviveu**. Motivo: o
> teste original reproduzia o upsert *inline* e nunca tocava em
> `fabio_concluir_registro_recibo`, então apagar o predicado **dentro da
> função** era invisível. Virou passo novo no teste; agora **2/2**.
>
> **Nove guardas de ACL estavam apagadas** (090, 091, 095). Todas medidas em
> produção antes: **as nove portas estavam corretas**, não havia vazamento — mas
> ninguém olhava, e regressão nenhuma seria percebida. Resgatadas para
> `20260813180000_guardas_resgatadas_do_whatsapp.sql`, aplicada, registrada,
> **5/5 mutantes**.
>
> **Correção de um erro meu, registrada.** Eu afirmei que havia defeito **vivo**
> no `ON CONFLICT` depois de rodar `EXPLAIN` contra produção. O `EXPLAIN` usava
> o texto **do arquivo 095**, que é a versão velha — a função viva já carrega o
> predicado. Não há defeito vivo. Testar o texto do repo e concluir sobre a
> produção é o mesmo erro de sempre, com roupa nova.
>
> **Ainda aberto neste sprint:** `094/M4` (unicidade da ação no ledger) e
> `20260813004713/M4` (o índice único que a migration chama de "segunda
> barreira independente do lock" e nada prova); estender
> `exigirBaselineVerde()` aos 62 runners restantes; e o laço latente do caminho
> `bloqueadas` herdado do Sprint 1.

## (plano original abaixo)

# Sprint 3 — matar o que sobreviver

**Depende do CP-2.3.** Só dá pra escrever depois que o placar verdadeiro
existir. Hoje já se sabe que há sobreviventes reais fora do CRLF —
`20260812163000` marcou **17/28**, e nem todos os 11 restantes são âncora
podre.

### CP-3.1 — Triar os sobreviventes

Cada mutante sobrevivente é uma de duas coisas: **defeito real** (o código não
protege o que o mutante quebra) ou **teste fraco** (o código protege, o teste é
que não vê). Classificar um por um, com evidência.

**PROVA:** lista com a classificação e o porquê de cada um.

### CP-3.2..N — Um checkpoint por defeito real

Cada um: teste vermelho → conserto → teste verde → mutante morre → aplicar →
**prova real na VPS**.

**PROVA por item:** o comportamento observado no sistema vivo, não só o teste.

---

# Sprint 4 — as duas decisões, RESPONDIDAS POR MEDIÇÃO (13/08)

> As duas decisões que travavam o CP-4.3 foram respondidas auditando o banco e
> cruzando com a **API do Emusys ao vivo**. Não sobrou escolha de gosto.

## A origem: não é acidente de sincronismo, é o contrato da tabela

A única chave única de `public.alunos` além da PK:

```
idx_alunos_telefone_unidade_nome_curso_unique
UNIQUE (telefone, unidade_id, nome, curso_id)
```

**`curso_id` está na chave.** `alunos` não é uma tabela de pessoas — é uma
tabela de **pessoa × curso**. Uma pessoa com dois cursos *tem* que virar duas
linhas; é o que a tabela declara. E `emusys_student_id` **não tem índice único
nenhum**.

A view não inventa nada: ela reflete fielmente esse grão. Consertar a view
seria maquiar o sintoma.

## Cruzamento com a fonte (API Emusys)

| caso | banco | API Emusys (fonte) |
|---|---|---|
| `3183` @ CG | 2 cadastros (ids 265, 1465) | **1 pessoa** — Luiza Pimentel Oliveira Barbosa, 2017-05-18, **2 matrículas** (Canto T, Teclado T) |
| `1001` @ BARRA | 2 cadastros | **1 pessoa** — Pietro Matola Abreu, 2011-02-26, 2 matrículas |
| `1001` @ RECREIO | 3 cadastros | **1 pessoa** — Júlia Salarini Gama, 2016-03-03, 6 matrículas |

O `1001` demonstra os dois problemas de uma vez: **pessoas diferentes com o
mesmo número em unidades diferentes** (a skill da API já avisa: *"IDs são POR
UNIDADE/ESCOLA"*), e **cada uma delas partida em vários cadastros** pelo grão
por curso.

## DECISÃO 1 — a chave de identidade é `(unidade_id, emusys_student_id)`

Medido sobre 1.616 cadastros ativos:

| chave | pessoas |
|---|---|
| `(unidade_id, emusys_student_id)` | **1.400** |
| só `emusys_student_id` | 1.311 → **fundiria 89 pessoas diferentes** |
| `(unidade_id, emusys_student_id, data_nascimento)` | **1.400** — idêntico |

- Usar o id **sozinho** não é opção: junta Pietro com Júlia. A memória da casa
  estava certa ao desconfiar dele.
- **`data_nascimento` não precisa entrar**: o par já é exato, e os 1.400 não se
  movem ao acrescentá-la. Ela serve como **asserção de sanidade**, não como
  parte da chave.
- Separação dos 224 grupos: **137 mesma unidade** (duplicata real, mesmo nome e
  mesma data de nascimento) × **87 unidades diferentes** (colisão de
  namespace). **Zero** grupos de mesma unidade apontando para pessoas
  diferentes — nenhum contraexemplo.

**Validação contra o número decidido:** na carteira do professor 25,
`count(distinct (unidade_id, emusys_student_id))` = **20** — exatamente o que o
Alf decidiu contar e o que o Fábio responde.

## DECISÃO 2 — aditivo, e o alvo não é a view

A raiz está em `alunos`, não em `vw_fabio_carteira_professor`. A view é
`security_definer` e lida por outros sistemas do banco compartilhado; mudar o
formato dela pode quebrar o LA Report, e ainda por cima não atacaria a causa.

**Caminho:** uma RPC nova de contagem por pessoa, deduplicando pelo par, sem
tocar nas linhas existentes. O `_fetch_professor_roster` passa a receber um
número calculado em vez de o modelo contar uma lista.

## Correção de um número meu

Eu reportei antes **305 cadastros excedentes**. Aquele número somava `n-1`
sobre grupos de `emusys_student_id` duplicado e portanto **misturava colisão de
namespace com duplicata real**. O excedente verdadeiro é **216**
(1.616 cadastros − 1.400 pessoas).

## O que isto abre, e que NÃO é decisão minha

Os 216 excedentes **não são sujeira**: são o grão que a tabela declara. Não dá
para "limpar" sem contrariar o schema. A pergunta que fica pro Alf é de
arquitetura, não de faxina:

> `alunos` continua sendo **pessoa × curso** — e a gente só passa a contar
> certo por cima —, ou vira **pessoa**, com as matrículas numa tabela ao lado?

Contar certo pelo par funciona nos dois cenários, então o CP-4.3 **não fica
bloqueado** por essa pergunta.

---

# (histórico) Sprint 4 — a carteira fala um número só 🟡 PREMISSA INVERTIDA (13/08)

> **O Fábio estava certo e a view é que infla.** Eu abri este sprint achando o
> contrário. A medição desmontou a premissa.
>
> **CP-4.2 — decidido pelo Alf em 13/08: carteira conta ALUNO**, não matrícula.
>
> **CP-4.1 — de onde vinha cada número, medido:**
>
> | número | o que é |
> |---|---|
> | 23 | linhas da view (matrícula × grão) |
> | 21 | `aluno_id` distintos |
> | **20** | **pessoas de verdade** ← o que o Alf decidiu contar |
>
> O 21 vira 20 por causa disto, achado na carteira do professor 25:
>
> - `aluno_id 265` — Luiza Pimentel Oliveira Barbosa — Teclado
> - `aluno_id 1465` — Luiza Pimentel Oliveira Barbosa — Canto
>
> Mesma pessoa: mesmo nome, **mesma data de nascimento (2017-05-18)**, **mesmo
> `emusys_student_id` (3183)**, mesma unidade, as duas `ativo` e nenhuma
> arquivada. São dois cadastros para a mesma criança.
>
> **O tamanho real do problema, medido na base inteira:**
> **224 grupos de `emusys_student_id` duplicado, 305 cadastros excedentes, e 60
> grupos com 3 ou mais.** Não é o caso da Luiza — é sistêmico.
>
> **Mas o 20 do Fábio não é contrato — é aritmética de modelo.** O
> `_fetch_professor_roster` **não deduplica**: manda as 23 linhas e pronto. O
> Fábio recebeu a lista com nomes repetidos e contou. Perguntei três vezes, com
> frases diferentes: **20, 20, 20** — estável, e certo. Só que nada garante isso
> numa carteira maior, nem quando o duplicado vier com grafia diferente do nome
> em vez de id repetido. Resposta certa, mecanismo frágil.
>
> **Duas decisões antes de eu construir o CP-4.3:**
>
> 1. **A chave de identidade.** `emusys_student_id` foi o que provou a
>    duplicidade aqui, e é o candidato natural. Mas a memória da casa diz que
>    esse campo **já colidiu entre pessoas diferentes** — então usá-lo sozinho
>    troca um erro por outro. Vale casar `emusys_student_id` **e**
>    `data_nascimento`?
> 2. **Onde o número honesto mora.** `vw_fabio_carteira_professor` é
>    `security_definer` e lida por outros sistemas do banco compartilhado —
>    mexer no formato dela pode quebrar o LA Report. O caminho seguro é
>    **aditivo**: uma RPC/coluna nova de contagem por pessoa, sem tocar nas
>    linhas que já existem.
>
> **E fica dito:** deduplicar na contagem **esconde** os 305 cadastros
> excedentes. O número passa a fechar e o problema continua lá, mexendo em
> presença, em relatório e em qualquer coisa que conte aluno. A limpeza dos
> cadastros é frente própria — e é do Alf, não minha.

## (plano original abaixo)

# Sprint 4 — a carteira fala um número só

### Contexto medido

Perguntei ao Fábio ao vivo (`--sem-historico`): *"quantos alunos o professor
Matheus tem na carteira dele?"* → **"20 alunos"**.

A view canônica `vw_fabio_carteira_professor`, para `professor_id = 25`:
**23 linhas**, **21 alunos distintos**, todos com `aluno_status = 'ativa'`.

Três números pra mesma pergunta. As 23 linhas × 21 alunos é grão (matrícula ×
aluno). O 20 do Fábio não bate com nenhum dos dois.

### CP-4.1 — Achar de onde sai o 20

Rastrear o caminho que o Fábio usa. Não é o mesmo da view — e a diferença de
**1** contra os distintos é suspeita de filtro escondido, não de grão.

**PROVA:** a consulta exata que produz 20, nomeada.

### CP-4.2 — Decidir qual é o número certo

**Decisão de negócio, é do Alf.** "Carteira" conta matrícula ou aluno? Aluno
com duas matrículas conta uma ou duas vezes?

**PROVA:** decisão escrita aqui, com data.

### CP-4.3 — Uma fonte só

Fazer o Fábio e o app lerem a mesma coisa, com o grão decidido.

**PROVA:** perguntar de novo ao Fábio pelo `falar_com_fabio.py
--sem-historico` e receber **o mesmo número** da view. Mais o caso oposto: um
segundo professor, pra provar que não foi acerto de um caso só.

---

# Sprint 5 — higiene

### CP-5.1 — `node_modules` (P7)

`node_modules` está pela metade (22 entradas, `.bin` vazio) e o `npm ci` falha
com `EPERM: unlink ...esbuild.exe` — arquivo travado por outro processo. **Não
forcei**, por ser checkout compartilhado. Consequência: **os 65/65 unitários
reportados pelo Codex não foram reproduzidos aqui.**

**PROVA:** `npm run test:unit` rodando, com o placar real colado.

### CP-5.2 — Gateway sai com `1/FAILURE` (P10)

Todo `stop` do `fabio-hermes-gateway` registra
`Main process exited, code=exited, status=1/FAILURE`. O serviço sobe e roda
(`NRestarts=0`, ativo desde 12/08 23:22), então é cosmético — mas é ruído que
**mascara falha real** no log, e é justo o log onde a gente vai procurar
quando algo quebrar.

**PROVA:** um ciclo `restart` completo com saída limpa no `journalctl`.

### CP-5.3 — Branches remotas (P9)

Três branches com commit próprio não integrado, todas **muito** atrás da
`main`:

| branch | à frente | atrás |
|---|---|---|
| `claude/compassionate-heisenberg-e778a8` | 1 | 420 |
| `fabio/atualiza-docs-estado-real` | 1 | 493 |
| `fabio/edge-carteiro-registro-aula` | 1 | 493 |

Revisar diff e finalidade de cada uma. Com esse atraso, quase certamente é
merge manual ou descarte — **não** merge direto.

**PROVA:** decisão por branch, escrita.

### CP-5.4 — Advisors (P8)

650 avisos no projeto compartilhado. Os de nível ERROR:

- **5 `rls_disabled_in_public`** — `calendario_escolar`, `projecao_aulas`,
  `projecao_recaculo_log`, `lead_experimentais_arquivadas`,
  `lead_experimental_aulas_arquivadas`.
- **9 `security_definer_view`** — inclui `vw_fabio_carteira_professor`,
  `vw_registro_pendencia`, `vw_saude_presenca_professor`.

O banco é compartilhado com LA Report e Sol. **Não mexer sozinho** — as duas
tabelas de `lead_experimental*` e as views de carteira são lidas por outros
sistemas.

**PROVA:** escopo aprovado pelo Alf antes de qualquer `alter`. Sem aprovação,
o checkpoint fecha como "mapeado, não tocado".

---

## Backlog produzido pelo próprio plano

### F-A — a shortlist não usa o que a transcrição já diz

O Fábio perguntou à Daiana qual era a aula, e **o sistema já sabia**. A
transcrição diz *"na aula da Beatriz Ohana"*, e o roster resolve sozinho:

| `aula_id` | quando | unidade | alunos na presença |
|---|---|---|---|
| **217860** | 12/08 (qua) 15:00 | BARRA | **Beatriz Ohana De Carvalho Paula** (única) |
| 205008 | 06/08 (qui) 20:00 | CG | 6 alunos, **nenhum** Beatriz |

`reduzir_shortlist` filtra por dia/hora/turma (`_compatible`) e **não cruza
nome de aluno citado na fala contra o roster das candidatas**. Resultado: uma
pergunta desnecessária, que virou 20h de silêncio e quase custou o registro.

Isso é exatamente o *"sem virar perturbação"* que o Alf pediu. Cuidado ao
consertar: nome de aluno citado deve **desempatar** candidatas, não escolher
sozinho quando não houver correspondência — e homônimo tem que continuar
perguntando (já mordeu a casa antes).

### F-B — ação aberta não é lembrada por ninguém

Medido no CP-0.4: só o handler reativo toca `fabio_acoes_pendentes`. Não há
lembrete pro professor nem alerta pra coordenação quando a ação se aproxima de
`expira_em`. O trabalho do professor pode evaporar sem que ninguém saiba.

Provável casa: o worker de devolutiva já é uma máquina de avisos ao professor
(há tarefa aberta de generalizá-lo). Avaliar antes de criar timer novo.

### F-C — a régua de precedência agora tem duas portas

O Alf informou em 13/08 que o motor do WhatsApp passou a gravar conteúdo de
aula **com baixa automática de presença, igual ao aplicativo**. Isso significa
que app e WhatsApp escrevem registro **e** presença. A precedência já
documentada (manual > professor/fabio_audio > emusys) tem que valer para as
duas portas, e o CP-4 (carteira) e o Sprint 3 precisam ser lidos com isso em
mente. **Não auditado ainda** — entra como frente própria.

## O que ficou de fora de propósito

- **Tasks 5–9 do Radar do aluno** (as telas) continuam não começadas. Não
  entram aqui: este plano é correção, não frente nova.
- **Fase B das faltas consecutivas** (Fábio avisando o professor em 2 faltas,
  escalando pra coordenação em 3+) segue adiada por decisão do Alf.
