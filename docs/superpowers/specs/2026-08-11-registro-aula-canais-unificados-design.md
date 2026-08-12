# Registro de aula com motor único no app e no WhatsApp — design

**Status:** decisões de produto aprovadas pelo Alf em 11/08/2026. Esta SPEC substitui, neste recorte, a limitação da SPEC de 10/08 que deixava o texto completo da devolutiva fora do WhatsApp. Ainda não autoriza migration, código, deploy, correção produtiva ou envio de mensagem: autoriza somente o plano em gates após a revisão desta SPEC.

---

## Problema

O uso real do Isaque revelou quatro quebras do mesmo contrato:

1. conteúdo confirmado não garantiu presença automática quando a normalização omitiu presença;
2. transcrição incerta foi transformada em texto professor-facing, e o fatiamento repetiu conteúdo/repertório entre tronco e aluno;
3. a devolutiva foi gerada, mas o WhatsApp apenas mandou o professor abrir o app, sem conservar no contexto do Fábio o que ele havia acabado de entregar;
4. app e WhatsApp ainda têm etapas e estados que podem divergir.

O resultado desejado é **um único motor, duas portas**. App e WhatsApp usam a mesma aula, o mesmo roster, o mesmo rascunho, os mesmos núcleos de escrita, a mesma devolutiva e o mesmo recibo autoritativo. O LLM interpreta e redige dentro de contratos fechados; não escolhe a aula, não decide identidade e não escreve diretamente nas tabelas pedagógicas.

---

## Decisões de produto

| Assunto | Decisão aprovada |
|---|---|
| Unidade de entrada | Um áudio representa **uma turma e um horário**. Áudio que misture aulas para e pede áudios separados; nunca é dividido por aproximação. |
| Conteúdo comum | Sem aluno citado, a informação vai ao tronco e vale para todas as fatias presentes. |
| Conteúdo individual | Menção inequívoca a aluno cria/completa somente a fatia daquele aluno. Não repete dados comuns no aluno. |
| Campos | O motor distribui objetivo, atividades/conteúdo, repertório, dever de casa, observações e progresso no campo certo, sem repetir uma mesma informação. |
| Objetivo | Pode ser sintetizado pedagogicamente a partir do trabalho descrito, desde que seja consequência direta dele e não reescreva o conteúdo. Se não for possível formular um objetivo distinto e útil, fica vazio. |
| Transcrição incerta | Não chega ao prontuário como citação estranha nem como “a transcrição disse”. O campo fica vazio ou o professor recebe pergunta de confirmação. |
| Presença | Confirmar conteúdo marca todos do roster como presentes. Uma falta só acontece quando o professor a declara explicitamente; os demais continuam presentes. |
| Preview | Antes do commit, o professor vê o mesmo prontuário estruturado que será escrito: tronco, fatias, campos vazios, presenças/faltas e destino da devolutiva. Pode confirmar, corrigir ou cancelar. |
| Devolutiva | É gerada por aluno presente, chega como rascunho no app e no WhatsApp e pode ser revisada pelo professor. Nunca é enviada automaticamente ao aluno ou responsável. |
| Recibo | Após o commit, o Fábio envia um carimbo hierárquico, no padrão visual do briefing atual, com aula, aluno, conteúdo, presença/falta e rascunhos de devolutiva. |
| Memória | Toda saída automática relevante é salva em ledger e entra no contexto conversacional do Fábio. “Melhora a do Lucas” resolve a devolutiva recém-entregue, não uma conversa vaga. |

---

## Arquitetura e fluxo

    áudio no app ou WhatsApp
        → aula única identificada
        → normalização e fatiamento canônicos
        → preview estruturado
        → corrigir, confirmar ou cancelar
        → núcleo único de escrita
        → presenças/faltas + devolutivas family-safe
        → carimbo WhatsApp e ledger
        → contexto conversacional do Fábio

### Identidade, aula e fatiamento

- No app, a sessão escolhida continua definindo aula, roster e alvos.
- No WhatsApp, telefone resolve professor; shortlist contextual limita a escolha a IDs reais. O classificador nunca inventa aula nem aluno.
- Se houver duas ou mais aulas compatíveis, o Fábio pergunta. Se o áudio tiver sinais de duas aulas, ele pede separação em vez de confirmar qualquer uma.
- A normalização recebe somente a aula escolhida e seu roster. Ela devolve campos compartilhados e complementos por aluno, nunca texto solto que o leitor precise adivinhar onde encaixar.
- A camada determinística rejeita ou remove de cada fatia tudo que for igual ao campo comum correspondente. A tela e a RPC de histórico também deduplicam defensivamente, para que dado legado não reapareça como “Lucas: [mesmo repertório]”.

### Presença

O fato de o professor confirmar conteúdo é o sinal determinístico de que a aula ocorreu. Antes da confirmação gravar o prontuário, toda fatia sem declaração recebe presença; declaração explícita de ausência prevalece. O único escritor de presença continua sendo o núcleo canônico, incluindo sincronização dos gêmeos e proteção contra fontes fortes existentes. O mesmo contrato vale para app e WhatsApp.

### Preview e correções

O read-back vem do registro canônico em aguardando confirmação, não de uma segunda montagem de texto no bridge. Campos vazios permanecem vazios no preview. Antes da confirmação, app e WhatsApp usam as mesmas portas guardadas para alterar fatia, presença ou intenção. Depois do commit, conversa informal não reescreve prontuário: correção de conteúdo é uma operação auditada e explícita.

### Devolutiva, recibo e memória curta

Após o commit, o motor existente cria devolutivas apenas para fatias presentes e usa a fonte family-safe já existente. Cada uma chega ao professor como rascunho revisável; pedido como “melhora a do Lucas” edita somente a devolutiva identificada, registra autor/data/versão e nunca dispara envio à família.

O carimbo WhatsApp reutiliza a linguagem do briefing: blocos escaneáveis, emoji semântico, horário, nomes, presença/falta, campos estruturados e os rascunhos de devolutiva. A entrega é uma única saída autoritativa, registrada em ledger com recibo de transporte e espelhada no contexto do bridge. Assim o Fábio sabe o que enviou e consegue continuar a conversa sem perguntar a que texto o professor se refere.

---

## Estados, idempotência e falhas

### Estados essenciais

recebido → aula resolvida → processando áudio → aguardando confirmação → confirmado/gravado → devolutivas geradas → carimbo enviado.

Há ainda estados ambígua, adiada, cancelada, expirada e erro terminal. Uma pergunta paralela não resolve a ação pendente. Expiração descarta apenas rascunho não confirmado e limpa somente blob sem referência confirmada.

### Chaves e replays

- WhatsApp é idempotente por mensagem; app por áudio/registro.
- Replays não podem duplicar upload, rascunho, presença, devolutiva, recibo ou mensagem de memória.
- O ledger de eventos e o recibo de saída são a fonte para detectar uma entrega já realizada; nunca se infere entrega apenas de log local.

### Erros

Erros transitórios (rede, Storage, Edge indisponível) podem ter retentativa limitada e observável. Erro semântico, por exemplo “sem conteúdo pedagógico”, é terminal: não volta à Edge nem consome tentativas indefinidamente. A fila offline do aparelho deve comunicar que há um áudio local guardado e a causa da última tentativa, não afirmar que a conexão caiu sem evidência.

---

## Correções do incidente do Isaque

1. Corrigir o lançamento de Lucas de forma auditada para **“quarto sistema”**; não usar update direto nem sobrescrever registro final silenciosamente.
2. Encerrar o áudio complementar sem conteúdo da aula das 15h como erro terminal, sem novas tentativas.
3. Corrigir a política de presença padrão e o normalizador para que o próximo lançamento não dependa de o LLM lembrar de escrever presença.
4. Eliminar duplicação de repertório comum em fatias e a duplicação visual no histórico; separar progresso individual de atividades comuns.
5. Corrigir o cabeçalho para usar o perfil canônico quando a sessão só tiver telefone/e-mail e tornar o estado local da fila de áudio honesto e recuperável.
6. Explicar “Sem registro” como estado anterior à confirmação ou alterar o rótulo para comunicar claramente que há rascunho aguardando ação, sem afirmar perda de conteúdo.

---

## Gates de teste e liberação

1. **Contrato SQL em rollback:** presença padrão, falta explícita, alvos gêmeos, tronco/fatias, deduplicação, correção auditada, erro terminal e idempotência.
2. **Bridge/Edge local:** classificação de áudio misto, shortlist, preview, correção pré-confirmação, confirmação, carimbo, devolutiva e memória de saída. Inclui mutantes que removam cada guarda crítica.
3. **Integração sem escrita produtiva:** simulação do ciclo completo contra os contratos, sem professor, família, aula ou presença sintética persistida.
4. **Piloto real controlado:** áudio real, uma aula por vez, conferindo que app e WhatsApp chegam ao mesmo registro, mesma presença e mesmos rascunhos; nenhuma devolutiva vai à família.
5. **Rollout gradual:** aumentar professores somente depois de evidência do piloto e manter rollback por modo/feature flag.

---

## Fora de escopo

- Envio automático de devolutiva ao aluno ou responsável.
- Escolha silenciosa de aula/aluno por LLM ou proximidade.
- Divisão automática de áudio que mistura aulas.
- Escrita direta de tabelas pedagógicas pelo bridge/LLM.
- Correção pós-confirmação sem trilha de auditoria.

---

## Critérios de aceite

1. O mesmo áudio, pela mesma aula, produz o mesmo prontuário e efeitos no app e no WhatsApp.
2. Todo aluno do roster fica presente após confirmação, exceto ausência explicitamente declarada.
3. Preview, commit, carimbo e devolutiva são cada um idempotentes.
4. Nenhuma informação comum duplica em fatia/repertório, e objetivo não é uma cópia de conteúdo.
5. Texto de transcrição incerta não aparece como observação factual.
6. O professor encontra no WhatsApp o carimbo e as devolutivas em rascunho e pode pedir uma revisão referencial; o Fábio sabe qual texto editar.
7. Nenhuma família recebe mensagem sem ação explícita do professor fora deste fluxo.

