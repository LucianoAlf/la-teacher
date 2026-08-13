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

# Sprint 0 — o registro que evapora hoje

**Por que é o primeiro:** é o único item com prazo. Um professor gravou uma
aula de verdade e o trabalho dele some se ninguém agir.

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

### CP-0.4 — Entender por que ficou 20h parado

Uma ação `aberta` que vence sem ninguém perceber é um buraco de processo, não
só um caso. Verificar: existe lembrete pro professor que não responde a
shortlist? Existe alerta pra coordenação quando uma ação está perto de expirar?

**PROVA:** resposta com evidência (RPC/worker que faz isso, ou a constatação
medida de que não existe). Se não existir, vira item pro backlog com o
tamanho estimado.

---

# Sprint 1 — o laço do reconciler

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

## O que ficou de fora de propósito

- **Tasks 5–9 do Radar do aluno** (as telas) continuam não começadas. Não
  entram aqui: este plano é correção, não frente nova.
- **Fase B das faltas consecutivas** (Fábio avisando o professor em 2 faltas,
  escalando pra coordenação em 3+) segue adiada por decisão do Alf.
