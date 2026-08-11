# O mesmo motor do app, dentro do WhatsApp — design

**Status:** aprovada pelo Alf em 10/08/2026 depois da leitura do fluxo real do
app, do bridge e dos contratos publicados no Supabase. A aprovação autoriza a
produção do plano em gates; migration, código, deploy e escrita produtiva
continuam condicionados aos checkpoints explícitos desse plano.

---

## O problema

A Daiana usou o Fábio no WhatsApp como qualquer professor vai usar. Ele disse
que tinha salvado registros e presenças quando o canal do professor já não
possuía ferramenta de escrita. O `CAPACIDADE_PROFESSOR` interrompeu a mentira:
hoje o Fábio recusa, orienta o app e devolve o texto organizado. A perda deixou
de ser silenciosa, mas o professor ainda precisa sair da conversa para concluir
o trabalho.

O objetivo desta fase é permitir que o professor registre conteúdo de aula por
áudio e faça uma chamada avulsa pelo WhatsApp, usando o mesmo motor e as mesmas
guardas do app, sem entregar uma ferramenta de escrita ao LLM.

### Evidência que define o desenho

- No app, o professor escolhe a sessão **antes** de o áudio chegar ao Hermes.
  O `aula_id` define roster, tronco, fatias e alvos finais. Se ele estiver
  errado, o restante pode ficar internamente correto na aula errada.
- `vw_registro_pendencia` significa **aula sem relato**
  (`anotacoes_fabio` vazio). Ela não significa aula sem chamada e não aplica,
  sozinha, a janela de sete dias.
- As contagens do banco em 10/08 mostraram centenas de aulas sem relato na
  janela, e a grande maioria já tinha chamada forte. Também mostraram apenas
  três professores com uma candidata e 38 com duas ou mais. Os valores mudam
  com o tempo e não são regra de produto; provam que um pool único e uma lista
  completa de candidatas não escalam.
- O app usa cinco caminhos de escrita no fluxo completo, não três:
  `app_enfileirar_audio`, `app_atualizar_fatia`,
  `app_responder_presenca`, `app_confirmar_registro` e
  `app_registrar_presencas_aula`.

---

## Escopo desta fase

### Dentro

- Áudio espontâneo que o professor quer transformar em registro de aula.
- Classificação segura entre registro, conversa e intenção ambígua.
- Escolha da aula com shortlist contextual e confirmação quando necessário.
- O motor existente de transcrição, molde C, tronco e fatias por aluno.
- Leitura de volta do conteúdo e das presenças antes da gravação final.
- Correção do rascunho por texto ou áudio curto antes da confirmação.
- Chamada avulsa por texto, sem conteúdo pedagógico.
- Recibo estruturado depois do commit.
- Cancelamento, adiamento, expiração, idempotência e limpeza de rascunho.

### Fora

- Ferramenta de escrita no toolset do LLM.
- Correção pelo WhatsApp de registro já confirmado.
- Pedido de liberação de prazo à coordenação.
- Texto livre longo como entrada inicial do motor de registro.
- Revisão, edição ou envio de devolutiva para família pelo WhatsApp.
- Mudança do motor de estruturação do Hermes.
- Mudança no fluxo produtivo já existente de `fabio_devolutivas` e
  `fabio_notification_worker`.

Se o professor apontar uma aula que já possui registro confirmado, o Fábio não
deve responder “não encontrei aula”. Ele informa que a aula já tem registro e
orienta o caminho atual do app para complementar ou substituir. Não tenta
alterar o prontuário por fora deste escopo.

---

## Decisões de produto e segurança

| Assunto | Decisão |
|---|---|
| Identidade | `professor_id` vem do telefone resolvido por `fabio_identidade_whatsapp`, nunca do texto ou do LLM |
| Intenção do áudio | Classificar em `registro`, `conversa` ou `ambiguo`; em dúvida, perguntar |
| Intenção do texto de presença | Classificar em `chamada`, `conversa` ou `ambiguo`; em dúvida, perguntar |
| Autorização de escrita | O LLM nunca autoriza nem executa escrita; o bridge chama RPCs guardadas somente depois de estados determinísticos |
| Qual aula | Dois pools independentes e uma shortlist de no máximo três opções realmente compatíveis |
| Confirmação | Sempre há read-back; resposta não reconhecida nunca vira “sim” |
| Correção | Somente no rascunho, por RPC com lista branca e guarda de dono/status |
| Estado | Durável no banco; webhook não espera Hermes nem guarda contexto apenas em memória |
| Pendência | Uma ação ativa por professor, sem sequestrar conversa não relacionada |
| Idempotência | `wa_message_id` é a chave da entrada; replay devolve o mesmo estado, não duplica upload, fila ou commit |
| Carimbo | Recibo estruturado do que foi gravado; sem texto da devolutiva nesta fase |

Princípio de falha fechada: **se intenção, aula, correção ou confirmação não
forem reconhecidas com segurança, o Fábio pergunta. Nunca enfileira ou grava
porque “pareceu provável”.**

---

## O motor atual do app que deve ser preservado

1. O professor abre uma sessão e o app obtém o `aula_id` âncora.
2. O app sobe o áudio em `fabio-audios` e chama `app_enfileirar_audio`.
3. A RPC valida professor, aula, cancelamento, futuro, janela e relatório
   anterior; depois cria `fabio_fila_audios`.
4. `trg_fabio_fila_novo` dispara o motor existente. O Hermes transcreve,
   estrutura o molde C e cria tronco + fatias em
   `aguardando_confirmacao`.
5. O app consulta `app_status_audio_fila` e `app_registros_pendentes` até o
   tronco aparecer para o `audio_id`.
6. Na revisão, o professor usa `app_atualizar_fatia` e
   `app_responder_presenca`.
7. `app_confirmar_registro` grava por aluno, pula ausentes, emite presença pelo
   núcleo canônico, sincroniza gêmeos e enfileira devolutivas.

O WhatsApp muda a porta de entrada e a interface de revisão. Não muda esse
motor.

---

## Arquitetura

```text
WhatsApp recebe texto/áudio
  │
  ├─ webhook valida e responde rápido
  │
  └─ bridge assíncrono
       │
       ├─ deduplica por wa_message_id
       ├─ resolve professor pelo telefone
       ├─ transcreve áudio
       ├─ consulta ação ativa sem bloquear conversa paralela
       │
       ├─ classifica intenção: conversa | registro | ambíguo
       │    ├─ conversa  ───────────────► Hermes conversacional
       │    └─ registro/ambíguo
       │         ├─ preserva original em staging idempotente
       │         └─ ambíguo ───────────► pergunta “quer registrar?”
       │
       ├─ texto com possível presença
       │    ├─ classifica: chamada | conversa | ambíguo
       │    ├─ conversa ────────────────► Hermes conversacional
       │    └─ ambíguo ────────────────► pergunta “quer bater a chamada?”
       │
       ├─ registro/chamada confirmados como intenção
       │    ├─ monta pool correto
       │    ├─ produz shortlist contextual
       │    └─ 1 compatível segue; 2–3 pergunta; >3 faz pergunta discriminante
       │
       ├─ áudio de registro
       │    ├─ baixa original da UAZAPI
       │    ├─ sobe em fabio-audios/whatsapp/...
       │    ├─ fabio_enfileirar_audio
       │    └─ ação = processando_audio
       │
       ├─ reconciliador observa fila/registro fora do webhook
       │    └─ registro pronto ─────────► read-back + ação confirmar_registro
       │
       ├─ correção reconhecida
       │    ├─ fabio_atualizar_fatia / fabio_responder_presenca
       │    └─ novo read-back
       │
       └─ “sim” reconhecido
            ├─ fabio_confirmar_registro ou fabio_registrar_presencas_aula
            └─ recibo estruturado depois do commit
```

O interceptador de ação/intenção roda em `process_one()` depois do batching e
antes de `generate_answer()`. O handler de mídia continua fora do request do
webhook, porque a UAZAPI pode reenviar a mensagem se a resposta demorar.

---

## 1. Classificação de intenção

Áudio não é sinônimo de registro. Depois da transcrição, o classificador recebe
somente a mensagem, o contexto conversacional mínimo e um contrato fechado de
saída:

```json
{
  "intencao": "registro | conversa | ambiguo",
  "evidencias": ["trechos curtos presentes na mensagem"]
}
```

- `conversa`: segue para o fluxo conversacional atual.
- `registro`: preserva o original em staging e inicia a resolução de aula.
- `ambiguo`, saída inválida, timeout ou confiança insuficiente: pergunta se o
  professor quer registrar aquilo como aula; antes de perguntar, preserva o
  original em staging para não depender da duração da URL da UAZAPI.

O classificador não recebe RPC de escrita, não cria `aula_id` e não transforma
“provável” em autorização. A resposta humana à pergunta também precisa ser
reconhecida; silêncio ou assunto diferente não inicia registro.

Durante uma shortlist, o classificador pode casar texto livre com uma candidata,
mas recebe exclusivamente os IDs permitidos e deve devolver um deles ou
`sem_correspondencia`. Um ID fora da lista é saída inválida.

### Gatilho da chamada avulsa por texto

Texto que menciona presença não é automaticamente uma chamada. Antes de
consultar o pool de chamada, o bridge aplica um contrato fechado e independente
da escolha de aula:

```json
{
  "intencao": "chamada | conversa | ambiguo",
  "evidencias": ["trechos curtos presentes na mensagem"]
}
```

- `chamada`: a mensagem declara diretamente presentes/ausentes ou que a chamada
  foi feita; só então o bridge consulta o pool de chamada e monta a shortlist.
- `conversa`: segue ao Hermes conversacional sem consultar o pool e sem abrir
  ação pedagógica.
- `ambiguo`, saída inválida, timeout ou confiança insuficiente: pergunta
  “Você quer bater a chamada de uma aula com isso?”. Quando a própria conversa
  já nomeia uma aula, pode perguntar “Você quer bater a chamada desta aula?”,
  ainda sem converter essa referência em `aula_id`.

Padrões determinísticos podem reconhecer frases como “só a Sofia faltou” ou
“todo mundo veio”, e um classificador pode cobrir variações de texto livre.
Nenhum dos dois autoriza escrita: eles apenas produzem uma das três intenções.
O pool nunca é consultado porque a mensagem “pareceu presença”.

Depois de `chamada`, o casamento com aula é outra etapa. O classificador recebe
somente IDs da shortlist e devolve um deles ou `sem_correspondencia`, exatamente
como no áudio. Ele não cria aula, não amplia o pool e não transforma
proximidade temporal em certeza.

Mensagem que mistura conteúdo pedagógico com presença não entra silenciosamente
na chamada avulsa. Dentro deste contrato de três saídas, ela é `ambiguo`. O
Fábio pergunta se a intenção é registrar o conteúdo da aula. Se for, como texto
livre longo está fora do escopo desta fase, orienta continuar pelo áudio ou pelo
app; não descarta o conteúdo para gravar apenas a presença.

---

## 2. Dois pools de aulas

### Pool de registro de conteúdo

Aulas do professor que:

- aconteceram ou começaram há no máximo 15 minutos no futuro, conforme a
  guarda atual;
- não estão canceladas;
- terminaram dentro de `fn_janela_registro_dias()`;
- ainda não possuem relato confirmado nos alvos do roster.

`vw_registro_pendencia` pode ser a fonte de “sem relato”, desde que a consulta:

- aplique explicitamente a janela;
- agrupe por `aula_ancora_id`, nunca por linha de aluno;
- não use `chamada_feita` como filtro de conteúdo.

Uma aula já registrada pode aparecer apenas como contexto para uma mensagem
que a cite. Ela não é candidata gravável nesta fase.

### Pool de chamada avulsa

Sessões do professor que:

- passaram pelas mesmas guardas de dono, cancelamento, futuro e janela;
- possuem roster utilizável;
- têm pelo menos um aluno sem presença forte concluída.

Fonte forte é a definição canônica de `fn_presenca_e_forte`, incluindo
`professor_la_teacher`, `fabio_audio`, `manual` e `professor_whatsapp`. Esse pool
não depende de `anotacoes_fabio` e não reutiliza `vw_registro_pendencia` como
filtro de elegibilidade.

---

## 3. Shortlist contextual de “qual aula”

A janela de sete dias é o universo máximo, não a lista apresentada ao
professor.

1. O banco elimina tudo que não pertence ao professor ou falha em guardas
   objetivas.
2. A transcrição e a mensagem são confrontadas com data, horário, proximidade,
   curso, turma e nomes de alunos presentes no roster.
3. Evidência explícita incompatível elimina a candidata. Proximidade temporal
   apenas ordena; sozinha, não autoriza escolher entre duas aulas compatíveis.
4. Exatamente uma candidata compatível, sem contradição no texto: segue.
5. Duas ou três: pergunta usando data, hora, curso/turma e, quando útil, nomes
   que diferenciem os rosters.
6. Mais de três ainda compatíveis: não despeja lista. Faz uma pergunta
   discriminante, por exemplo dia, horário ou turma, e recalcula.
7. Zero: informa que não encontrou aula elegível e não escreve. Se a mensagem
   apontar uma aula já registrada ou fora do prazo, explica o motivo correto.

Exemplo:

> “Foi a turma de Musicalização de hoje às 14h ou a aula da Sofia às 16h?”

Resposta ambígua repete ou refina a pergunta. Nunca escolhe a primeira linha.

---

## 4. Ingestão e idempotência do áudio

O WhatsApp já obtém da UAZAPI a transcrição e uma URL de mídia. Essa URL não é
tratada como armazenamento durável. Depois de classificar:

- `conversa`: mantém o comportamento atual do chat e não cria objeto no bucket
  pedagógico;
- `registro` ou `ambiguo`: preserva o original antes de esperar qualquer
  resposta humana.

Para entrar no mesmo motor do app, o bridge deve:

1. baixar o áudio original;
2. validar tipo e limite de tamanho;
3. subir no bucket privado `fabio-audios`;
4. chamar a porta guardada de enfileiramento.

Convenção de staging idempotente, que não depende de `aula_id` ainda desconhecido:

```text
whatsapp/{professor_id}/{wa_message_id}.{ext}
```

O namespace é deliberadamente diferente do path do app, que começa por
`auth.uid()`. O upload do WhatsApp acontece apenas no processo servidor com
service role. O cliente nunca recebe essa chave.

`wa_message_id` é único na ação e determina o path. Quando a aula é escolhida,
`fabio_enfileirar_audio` recebe esse mesmo `storage_path`; não é necessário
mover ou copiar o objeto. Um replay consulta a ação existente e devolve seu
estado; não cria novo objeto, áudio de fila ou registro.
`fabio_fila_audios.origem` nasce como `whatsapp`.

O WhatsApp não precisa da fila offline do navegador, mas continua dependendo
dos retries e da retomada durável do servidor. Falha temporária não obriga o
professor a reenviar antes de a política existente de retry se esgotar.

---

## 5. Cinco portas, miolo compartilhado

As assinaturas públicas atuais do app permanecem compatíveis. Cada uma resolve
o professor via sessão e chama o mesmo miolo usado pela irmã do WhatsApp.

| Operação | Porta do app | Porta do WhatsApp |
|---|---|---|
| Enfileirar áudio | `app_enfileirar_audio` | `fabio_enfileirar_audio` |
| Editar tronco/fatia | `app_atualizar_fatia` | `fabio_atualizar_fatia` |
| Responder presença do rascunho | `app_responder_presenca` | `fabio_responder_presenca` |
| Confirmar registro | `app_confirmar_registro` | `fabio_confirmar_registro` |
| Registrar chamada avulsa | `app_registrar_presencas_aula` | `fabio_registrar_presencas_aula` |

### Núcleos

- Extrair `fn_enfileirar_audio_core(p_professor_id, ...)` do corpo atual de
  `app_enfileirar_audio`.
- Extrair `fn_atualizar_fatia_core(p_professor_id, ...)` do corpo atual de
  `app_atualizar_fatia`, preservando lista branca, regeneração do texto e
  guardas de dono/status.
- Extrair `fn_responder_presenca_core(p_professor_id, ...)` do corpo atual de
  `app_responder_presenca`.
- Extrair `fn_confirmar_registro_core(p_professor_id, p_confirmado_por,
  p_registro_id, p_modo)` do corpo atual de `app_confirmar_registro`.
- **Não criar outro escritor de presença.** As duas portas de chamada fazem a
  validação compartilhada de aula âncora/roster e terminam no
  `fn_registrar_presencas_core` já existente. Se a preparação precisar ser
  extraída, ela será helper; o núcleo canônico de escrita continua único.
- Ampliar a lista de entrada aceita por `fn_registrar_presencas_core` para
  `professor_whatsapp`. A tabela e `fn_presenca_e_forte` já reconhecem essa
  fonte; o núcleo hoje ainda a rejeita.

`fabio_registrar_presencas_aula` usa `professor_whatsapp`, porque a chamada foi
declarada diretamente pelo professor nesse canal. A presença extraída de um
registro por áudio e confirmada junto com o rascunho continua usando
`fabio_audio`, preservando a semântica atual do motor.

### Guardas obrigatórias

Todas as portas `fabio_*`:

- recebem `professor_id` exclusivamente do bridge depois da resolução do
  telefone;
- revalidam que aula/registro pertence ao professor;
- validam cancelamento, roster, status e valores permitidos;
- usam `security definer` com `search_path` fixo;
- revogam `EXECUTE` de `PUBLIC`, `anon` e `authenticated`;
- concedem `EXECUTE` apenas a `service_role`;
- nunca são registradas como ferramenta do LLM.

Os núcleos internos também têm execução direta revogada. A capacidade pública
é a casca guardada, não o miolo.

### Paridade

Cada par app/WhatsApp deve receber o mesmo cenário e produzir o mesmo efeito,
salvo diferenças explicitamente auditáveis de canal e ator. Alterar apenas uma
porta precisa quebrar o teste de paridade.

---

## 6. Estado durável em `fabio_acoes_pendentes`

A tabela guarda o fluxo conversacional e também o histórico auditável. Linhas
resolvidas, canceladas ou expiradas não são apagadas.

| Coluna | Uso |
|---|---|
| `id uuid` | Identidade da ação |
| `professor_id integer` | Ator resolvido pelo telefone |
| `canal text` | `whatsapp` nesta fase |
| `wa_message_id text` | Mensagem que iniciou o fluxo; chave idempotente |
| `ultima_resposta_wa_id text` | Projeção da última mensagem que alterou a ação |
| `tipo text` | `confirmar_intencao_audio`, `confirmar_intencao_chamada`, `escolher_aula_audio`, `escolher_aula_chamada`, `processando_audio`, `confirmar_registro`, `confirmar_chamada` |
| `estado text` | `aberta`, `processando`, `resolvida`, `adiada`, `cancelada`, `expirada`, `erro` |
| `aula_id integer` | Aula escolhida, quando existir |
| `audio_id uuid` | Linha da fila, quando existir |
| `registro_id uuid` | Tronco produzido, quando existir |
| `storage_path text` | Objeto de staging preservado para registro/ambiguidade |
| `candidatas integer[]` | Somente IDs estáveis da shortlist atual |
| `payload jsonb` | Evidência e dados auxiliares; nunca autoridade para pular revalidação |
| `expira_em timestamptz` | Prazo da resposta humana; nulo enquanto o motor processa |
| `lease_token uuid`, `lease_expira_em timestamptz` | Claim/fencing do reconciliador |
| `erro text` | Falha terminal traduzível |
| timestamps | criação, atualização e encerramento |

Restrições:

- índice único parcial para uma ação ativa (`aberta`, `processando`, `adiada`)
  por professor;
- `wa_message_id` inicial único;
- transições feitas por RPCs atômicas com `FOR UPDATE`/fencing, não por updates
  soltos do bridge;
- RLS habilitada; sem acesso de `anon` ou `authenticated`; bridge via
  service role e funções restritas.

### Ledger idempotente das mensagens

`ultima_resposta_wa_id` não basta para deduplicar toda a conversa: uma ação
pode receber escolha, duas correções e confirmação. Uma repetição antiga ainda
precisa ser reconhecida depois de mensagens mais novas.

Por isso, cada transição grava também uma linha em `fabio_acao_eventos` com
`acao_id`, FK para a mensagem de chat, `wa_message_id` único, tipo de evento,
resultado e timestamp. A RPC registra evento + transição na mesma transação.
Replay do mesmo `wa_message_id` devolve o resultado já gravado. O ledger é
histórico, não mais um dono do estado: o estado atual continua em
`fabio_acoes_pendentes`.

As tabelas de ação e evento seguem a mesma fronteira: RLS ligada, nenhum acesso
de `anon`/`authenticated` e transições somente pelas funções restritas.

### Uma pendência não sequestra a conversa

Quando chega nova mensagem e existe ação ativa:

- resposta reconhecível à pergunta: avança a ação;
- “cancela”, “deixa pra lá”: cancela e inicia limpeza;
- “depois”: marca `adiada`, mantém o prazo original e deixa a conversa seguir;
- pergunta ou conversa não relacionada: segue ao Hermes conversacional e a
  ação continua aberta;
- novo pedido inequívoco de registro/chamada: o Fábio lembra a ação existente
  e pede concluir ou cancelar; não empilha uma segunda.

Nenhuma mensagem genérica é consumida como confirmação só porque havia uma
pendência.

Perguntas de escolha e read-back expiram 24 horas depois de serem enviadas.
“Depois” não renova esse prazo. `processando_audio` não usa prazo de resposta
humana: permanece sob lease/retry do reconciliador; ao virar
`confirmar_registro`, recebe novo `expira_em = now() + 24 hours`.

---

## 7. Máquina de estados

### Registro por áudio

```text
mensagem
  → classificar intenção
  → preservar original em staging
  → se ambíguo, confirmar intenção
  → escolher aula
  → ingerir e enfileirar
  → processando_audio
  → reconciliador encontra aguardando_confirmacao
  → read-back
  → confirmar_registro
      ├─ corrigir → read-back novamente
      ├─ cancelar → descartada
      └─ sim → commit → resolvida
```

O reconciliador é timer/worker independente. Ele observa `fabio_fila_audios` e
`fabio_registros_aula`, usa lease e pode retomar depois de restart. O webhook e
`process_one()` não ficam dormindo ou fazendo poll bloqueante.

### Chamada avulsa

```text
texto com possível presença
  → classificar chamada | conversa | ambiguo
  → se ambiguo, confirmar intenção
  → escolher aula pelo pool de chamada
  → montar preview de presentes/ausentes
  → confirmar_chamada
      ├─ corrigir lista → novo preview
      ├─ cancelar → cancelada
      └─ sim → fabio_registrar_presencas_aula → resolvida
```

### Expiração e limpeza

- Confirmação de intenção ou escolha de aula expirada antes do enfileiramento:
  encerra a ação, remove o objeto de staging e não deixa fila ou rascunho
  pedagógico.
- Confirmação expirada depois do processamento: marca tronco e fatias como
  `descartado`, encerra a ação e remove o objeto do Storage somente depois de
  provar que ele não referencia registro confirmado nem outra ação ativa.
- Metadados da ação, fila, transcrição e motivo do descarte permanecem como
  auditoria; o blob não confirmado não fica órfão no bucket.
- Limpeza é idempotente. Replay de cancelamento/expiração não apaga conteúdo
  confirmado.

A frase correta para o professor é: “Nada foi gravado no prontuário final antes
da sua confirmação.” Storage, fila e rascunho operacional podem existir antes.

---

## 8. Read-back, correção e confirmação

O read-back sempre começa pela identidade da sessão: data, hora e curso/turma.
Depois apresenta:

- conteúdo comum;
- fatia de cada aluno;
- presença declarada ou pendência de presença;
- aviso de que ainda não foi gravado no prontuário.

### Confirmação

Aceita somente classe fechada de respostas afirmativas. Negação, correção,
resposta ambígua, mensagem vazia ou assunto diferente não confirmam.

### Correção

O classificador de correção recebe o rascunho, o roster da aula e os campos
editáveis permitidos. A saída deve apontar IDs existentes e patch de lista
branca. O bridge valida e chama `fabio_atualizar_fatia` ou
`fabio_responder_presenca`; nunca atualiza tabela diretamente. Depois lê o
estado autoritativo do banco e envia novo resumo.

Se a correção vier em áudio enquanto existe ação de confirmação, a transcrição
é tratada como resposta à ação atual. Ela não abre nova escolha de aula, não é
subida de novo ao bucket e não cria outra linha na fila.

Correção que cita aluno fora do roster, campo desconhecido ou intenção não
determinada vira pergunta. Não há tentativa de “achar o aluno mais parecido” e
gravar.

---

## 9. Janela e autoria da confirmação

### Janela

- Registro por áudio: elegibilidade é validada antes do enfileiramento, como no
  app. `fabio_confirmar_registro` não rejeita um rascunho válido apenas porque
  o relógio cruzou o limite enquanto Hermes processava. A ação humana continua
  limitada por `expira_em`.
- Chamada avulsa: não existe rascunho pedagógico equivalente. A janela é
  revalidada no commit por `fn_registrar_presencas_core`; se fechar antes do
  “sim”, a chamada é recusada e o professor recebe orientação.

Portanto, não existe mutante genérico “as duas confirmações recusam fora da
janela”. Os testes preservam a semântica de cada fluxo.

### Autoria

`confirmado_por` continua sendo FK para `usuarios.id`:

- app: recebe o usuário autenticado atual;
- WhatsApp: usa `professores.usuario_id` quando o professor possui vínculo;
- professor sem login: pode permanecer nulo, sem apagar a autoria real.

A prova autoritativa do WhatsApp fica em `fabio_acoes_pendentes`: professor,
canal, `registro_id`, mensagem que iniciou e `ultima_resposta_wa_id` que
confirmou. O telefone bruto não é copiado para o payload. Assim o ator continua
auditável mesmo quando não existe usuário do app.

---

## 10. Recibo de sucesso e devolutiva

Depois de a RPC confirmar o commit, o bridge monta o recibo apenas com dados
autoritativos retornados ou relidos do banco:

- aula;
- quantidade de alunos gravados;
- ausentes pulados;
- presença aplicada ou erro não fatal;
- confirmação de que o registro ficou visível para a coordenação.

Exemplo:

> “Pronto: registrei a aula de hoje às 14h. Gravei o conteúdo para 4 alunos e
> pulei 1 ausente. A chamada também ficou registrada.”

O bridge **não** espera dez segundos por `fabio_devolutivas`, não envia o texto
family-safe e não marca devolutiva como oferecida. O
`fabio_notification_worker` continua sendo o único dono dessa oferta e mantém a
revisão no app. Trazer revisão de devolutiva ao WhatsApp exige outra spec.

Nenhum carimbo de sucesso é enviado antes da resposta positiva da RPC. Falha
ou resultado parcial produz mensagem honesta com o que foi e não foi aplicado.

---

## 11. `CAPACIDADE_PROFESSOR`

O texto atual diz que o WhatsApp não grava nada. Depois desta fase ele precisa
ser substituído por uma fronteira precisa:

- o canal consegue registrar aula e chamada somente pelo fluxo guardado de
  escolha, read-back e confirmação;
- o LLM continua sem ferramenta de escrita;
- qualquer outra alteração de sistema continua indisponível;
- o Fábio nunca promete sucesso antes do recibo autoritativo;
- se o fluxo não fechou, diz “ainda não gravei”.

O prompt é explicação. A garantia continua sendo a ausência de ferramenta de
escrita no toolset e os estados determinísticos do bridge.

---

## Bordas e falhas

| Caso | Comportamento |
|---|---|
| Áudio conversacional | Segue ao Hermes; nenhuma ação de registro nasce |
| Intenção ambígua | Pergunta se é registro; default nunca é enfileirar |
| Texto de presença ambíguo | Pergunta se o professor quer bater chamada; não consulta o pool antes disso |
| Texto mistura conteúdo + presença | Trata como `ambiguo`, pergunta se a intenção é registrar conteúdo e nunca grava só a chamada |
| Muitas candidatas | Faz pergunta discriminante; não envia lista inteira |
| Aula já registrada | Explica e orienta complemento/substituição no app |
| Nenhuma aula elegível | Explica prazo/cancelamento/ausência de sessão sem inventar alvo |
| Webhook repetido | Retoma a mesma ação por `wa_message_id` |
| Worker reinicia | Lease expira e outro ciclo retoma |
| Hermes/Storage temporariamente indisponível | Retry durável; mensagem de erro somente ao esgotar política |
| Correção fora do roster/lista branca | Recusa e pergunta de novo |
| Mensagem não relacionada com pendência aberta | Conversa normal; não confirma e não cancela |
| Professor cancela | Ação cancelada, rascunho descartado e limpeza segura |
| RPC recusa dono/status/janela | Traduz o erro; nunca expõe mensagem SQL crua |
| Commit parcial com presença não fatal | Recibo separa registro de conteúdo do resultado da presença |

---

## Como se prova

### SQL e segurança

1. Paridade das cinco duplas app/WhatsApp.
2. Assinaturas atuais das RPCs `app_*` continuam compatíveis.
3. `anon` e `authenticated` não executam nenhuma `fabio_*` nem núcleo interno.
4. Com `p_professor_id = P`, nenhuma porta consegue escrever aula ou registro
   pertencente a Q; o bridge é responsável por obter P da identidade telefônica.
5. `fn_registrar_presencas_core` aceita `professor_whatsapp`, considera a fonte
   forte e continua acionando `fn_sincronizar_gemeos_presenca`.
6. Correção só altera campos permitidos de rascunho pertencente ao professor.
7. Confirmação de registro preserva a janela do enfileiramento; chamada avulsa
   revalida janela no commit.
8. Índices de ação impedem duas ativas e dois inícios com o mesmo
   `wa_message_id`.
9. Ledger de eventos torna escolha, correção, cancelamento e confirmação
   idempotentes mesmo quando uma mensagem antiga é repetida depois de outra.
10. Transições inválidas, lease antigo e confirmação de ação expirada falham.
11. Expiração descarta apenas rascunho não confirmado e nunca apaga blob ainda
    referenciado.
12. Tabelas novas têm RLS e grants explícitos; não dependem do comportamento padrão
    de exposição da Data API.

### Bridge

1. Áudios reais de conversa, registro e ambiguidade.
2. Saída inválida/timeout do classificador vira pergunta.
3. Texto de presença classifica somente `chamada`, `conversa` ou `ambiguo`;
   ambiguidade pergunta antes de consultar o pool.
4. Texto com conteúdo + presença não cai silenciosamente em chamada avulsa.
5. Classificador não consegue devolver `aula_id` fora da shortlist.
6. Data, horário, curso/turma e alunos citados reduzem candidatas sem escolha
   silenciosa por proximidade.
7. Mais de três compatíveis gera pergunta discriminante.
8. “Não, a Sofia veio” usa RPC de presença, relê o banco e manda novo resumo.
9. Pergunta paralela não resolve a pendência.
10. “Cancelar” e “depois” seguem os estados definidos.
11. Replay do mesmo webhook não duplica upload, fila, rascunho ou confirmação.
12. O webhook termina antes da transcrição; poll/reconciliação acontece no
    worker.
13. Recibo só sai depois do commit e não contém texto da devolutiva.
14. `CAPACIDADE_PROFESSOR` continua recusando escritas fora deste fluxo.

### Mutantes mínimos

1. Remover guarda de dono de qualquer uma das cinco portas.
2. Permitir `anon`/`authenticated` executar uma `fabio_*`.
3. Deixar uma porta do app e uma do WhatsApp chamarem miolos diferentes.
4. Permitir `aula_id` fora da shortlist.
5. Tratar `ambiguo` como `registro`.
6. Consultar o pool de chamada antes de classificar o texto como `chamada`.
7. Fazer texto com conteúdo + presença cair em chamada avulsa.
8. Reutilizar `vw_registro_pendencia` como pool de chamada.
9. Filtrar registro por `chamada_feita=false`.
10. Retirar `professor_whatsapp` das fontes fortes ou da sincronização de gêmeos.
11. Aceitar patch de correção fora da lista branca.
12. Resolver ação com lease vencido ou mensagem repetida duas vezes.
13. Expirar ação e deixar rascunho/blob órfão.
14. Enviar carimbo antes da RPC ou anexar texto de `fabio_devolutivas`.

---

## Critério de aceite da SPEC

Esta SPEC está pronta para virar plano quando o Alf confirmar que:

1. áudio ambíguo pergunta, nunca enfileira por default;
2. os dois pools e a shortlist contextual refletem a experiência desejada;
3. correções pré-confirmação passam pelas cinco portas guardadas;
4. expiração descarta rascunho e limpa o blob sem apagar evidência confirmada;
5. conversa paralela não é capturada pela pendência;
6. recibo não duplica nem antecipa a devolutiva existente;
7. correção pós-confirmação e devolutiva completa no WhatsApp permanecem fora
   desta fase.

Somente depois dessa aprovação entra `writing-plans` para produzir o plano de
implementação em gates. Até lá, nenhuma migration, código de bridge, alteração
na VPS ou deploy é autorizado.
