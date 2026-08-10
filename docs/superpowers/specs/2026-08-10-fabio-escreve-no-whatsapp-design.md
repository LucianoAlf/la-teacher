# O mesmo motor do app, dentro do WhatsApp — design

**Decidido com o Alf em 10/08/2026.** É a casa deles: o professor não devia
precisar sair do WhatsApp pra fazer o que o Fábio hoje só sabe recusar.

---

## O problema (medido, não suposto)

A Daiana usou o Fábio no WhatsApp como qualquer professor vai usar. Ele
respondeu *"deixei o registro organizado e salvo"*, *"confirmado: o Eduardo
compareceu"* — e escreveu de verdade **1 vez em 8**. Sete relatos perdidos com
ela achando que estavam gravados. A causa: em 09/08 o canal do professor
(`api_server`) perdeu toda ferramenta de escrita, e ninguém tirou a boca junto
— o prompt continuou prometendo o que a ferramenta não fazia mais.

O conserto de 10/08 (`CAPACIDADE_PROFESSOR`) resolveu a mentira: agora ele
recusa, explica onde se faz no app e devolve o texto organizado pronto pra
colar. **Mas o professor ainda tem que sair do WhatsApp.** É a casa dele — pedir
pra ele abrir outro app pra terminar o que já começou ali é fricção que a gente
sabe, pelo próprio incidente, que ele não vai superar sozinho.

Esta spec é dar ao WhatsApp a mesma capacidade que o app tem — sem reabrir a
porta que a `api_server` acabou de fechar.

---

## O que este spec NÃO faz

- **Não dá ao Fábio (o LLM) nenhuma ferramenta de escrita nova.** Ver "A
  fronteira" — é a decisão que mais importa neste documento.
- **Não resolve o pedido de liberação de prazo à coordenação** (depois dos 7
  dias). Continua ato humano. Fica anotado em "Depois disto".
- **Não permite corrigir um registro já confirmado.** Correção só existe
  **dentro do loop de confirmação**, antes de gravar. Depois de confirmado, é
  o mesmo caminho de hoje (`p_modo='substituir'`, no app ou por reprocesso
  manual como o da Beatriz).
- **Não muda o motor de estruturação** (Hermes / molde C). Áudio continua
  virando `objetivo/atividades/obs_gerais/repertorio` + presença por aluno do
  jeito que já funciona.
- **Não constrói fila offline nem retry automático.** Se a ligação cair no
  meio da conversa, o professor manda de novo — nada foi escrito até a
  confirmação (ver "Bordas").

---

## Decisões

| Assunto | Decisão |
|---|---|
| Escopo de escrita | Registro de aula por áudio **+ chamada avulsa** (presença sem conteúdo). Fora: liberação de prazo, correção pós-confirmação |
| Confirmação | **Sempre com leitura de volta.** Fábio manda o resumo estruturado; só grava depois do "sim" (ou da correção seguida de "sim") |
| Qual aula | Fábio **pergunta quando há dúvida**, nunca chuta. Só seguem direto os casos com **uma única candidata óbvia** |
| Identidade nas RPCs | Miolo único, duas portas (ver "Arquitetura") — RPC do app usa `auth.uid()`, RPC irmã do Fábio recebe `professor_id` explícito, resolvido pelo telefone, nunca pelo texto da conversa |
| Ferramenta de escrita pro LLM | **Nenhuma.** Toda a orquestração (gatilho, qual aula, chamar a RPC, ler o resultado) é código determinístico no bridge — o mesmo andar onde já vive `_agenda_de_outro_dia` e o `CAPACIDADE_PROFESSOR` |
| Carimbo de feito | Resumo do que foi gravado + o texto da devolutiva gerada, devolvidos pro professor depois do commit |

---

## Arquitetura

```
  áudio/texto no WhatsApp (professor)
        │
        ▼
  fabio_chat_bridge.py — camada determinística (NÃO é decisão do LLM)
        │
        ├─► há ação pendente pro professor? ──► tenta resolver (resposta de
        │   (fabio_acoes_pendentes)               qual-aula / confirmação)
        │
        ├─► é gatilho novo (áudio, ou texto padrão de chamada)?
        │        │
        │        ▼
        │   resolve "qual aula" (candidatas = vw_registro_pendencia, 083/084)
        │        │
        │   1 candidata ──► segue          2+ ou 0 ──► pergunta / avisa,
        │                                              grava fabio_acoes_pendentes
        │        ▼
        │   sobe áudio no bucket fabio-audios (mesma convenção do app)
        │        │
        │        ▼
        │   fabio_enfileirar_audio(professor_id, aula_id, storage_path, ...)
        │        │                    (mesmo miolo de app_enfileirar_audio)
        │        ▼
        │   fabio_fila_audios ──► trg_fabio_fila_novo ──► Hermes estrutura
        │        │                                        (molde C, sem mudança)
        │        ▼
        │   fabio_registros_aula em 'aguardando_confirmacao'
        │        │
        │        ▼
        │   bridge lê os campos, monta o resumo, manda pro professor
        │   grava fabio_acoes_pendentes (tipo='confirmar_registro')
        │
        └─► professor responde "sim" ──► fabio_confirmar_registro(professor_id, registro_id, modo)
                 │                              (mesmo miolo de app_confirmar_registro,
                 │                               inclui fn_sincronizar_gemeos_presenca — 086)
                 ▼
            carimbo de feito: resumo + texto da devolutiva (fabio_devolutivas)
```

Chamada avulsa (texto, sem áudio) segue o mesmo esqueleto, trocando o meio:
sem upload, sem fila, sem Hermes — direto pra `fabio_registrar_presencas_aula`
(mesmo miolo de `app_registrar_presencas_aula`, a RPC que `Chamada.tsx` já usa).

**O que já existe e é reusado, não recriado:** o motor de estruturação
inteiro, as três RPCs do app (`app_enfileirar_audio`, `app_confirmar_registro`,
`app_registrar_presencas_aula`), a view de pendência (083), a janela de 7 dias
com dono único (084), a sincronização de gêmeo na escrita (086), o bucket
`fabio-audios`, e a rota family-safe da devolutiva.

---

## A fronteira (por que o LLM não ganha ferramenta)

A casa já aprendeu essa lição uma vez: prompt é probabilístico, allowlist de
ferramenta não é. O `CAPACIDADE_PROFESSOR` só é confiável porque **não existe
ferramenta de escrita no toolset do canal do professor** — o texto é reforço,
a garantia real é a ausência da ferramenta. Dar ao Fábio um tool-call que
grava presença reabriria exatamente essa porta, e desta vez com um motivo pior
pra confiar demais: "ele só chama depois que confirma" é uma regra de prompt,
a mesma categoria de regra que já falhou.

Por isso a decisão: **nenhuma RPC de escrita vira ferramenta do agente.** Toda
a lógica fica no bridge, em Python determinístico:

- Detectar que a mensagem é áudio (ou bate o padrão de chamada avulsa) — checagem de forma da mensagem, não interpretação livre.
- Resolver "qual aula" contra `vw_registro_pendencia` — consulta ao banco, não ao LLM.
- Casar a resposta do professor com uma das candidatas, ou seu "sim"/correção
  com a pendência aberta — aqui o LLM pode ser usado como **classificador
  auxiliar de texto livre** (ex.: "a da Sofia com o Pedro, terça" → candidata
  X), nunca como quem decide gravar. Falha em casar = pergunta de novo, nunca
  grava.
- Chamar `fabio_enfileirar_audio` / `fabio_confirmar_registro` /
  `fabio_registrar_presencas_aula` — chamada direta do Python, com
  `service_role`.
- Gerar o texto do resumo e do carimbo a partir dos campos estruturados — aqui
  o LLM pode ajudar na prosa, nunca na decisão de gravar.

**Nas três RPCs novas:** `security definer`, `revoke execute from public,
anon, authenticated`, `grant execute to service_role`. `professor_id` é
parâmetro, mas quem o preenche é sempre o bridge, a partir do telefone já
resolvido contra `professores` — o mesmo dado que já decide `identidade_tipo`
hoje, e que o modelo não influencia.

---

## As RPCs

Miolo único por escrita, duas portas — a RPC do app continua existindo do
jeito que está; ganha uma função interna que ela chama, e a RPC irmã do Fábio
chama a mesma função interna.

### `fn_enfileirar_audio_core(p_prof integer, p_aula_id integer, p_storage_path text, p_duracao_segundos integer, p_registro_id uuid default null)`

Todo o corpo que hoje está dentro de `app_enfileirar_audio` (migration 084),
trocando `v_prof := public.fn_professor_do_usuario()` por `p_prof` recebido.

- `app_enfileirar_audio(...)` vira uma casca: resolve `v_prof :=
  fn_professor_do_usuario()`, chama `fn_enfileirar_audio_core(v_prof, ...)`.
- `fabio_enfileirar_audio(p_professor_id integer, p_aula_id integer,
  p_storage_path text, p_duracao_segundos integer default null)` — chama
  `fn_enfileirar_audio_core(p_professor_id, ...)` direto. `security definer`,
  só `service_role`.

Mesmo padrão para:

### `fn_confirmar_registro_core(p_prof integer, p_registro_id uuid, p_modo text)`
### `fn_registrar_presencas_aula_core(p_prof integer, p_aula_emusys_id integer, p_alunos_ausentes integer[])`

com `app_confirmar_registro` / `app_registrar_presencas_aula` viram casca, e
`fabio_confirmar_registro` / `fabio_registrar_presencas_aula` a porta nova.

**Teste de paridade (obrigatório, ver "Como se prova"):** rodar o mesmo
cenário pelas duas portas (uma sessão simulando `auth.uid()`, outra chamando a
RPC do Fábio com o mesmo `professor_id`) e provar que o resultado é
**idêntico**. É o que impede a dupla de divergir silenciosamente numa próxima
migration — o mesmo defeito que os gêmeos tiveram, agora entre duas portas em
vez de duas linhas.

---

## `fabio_acoes_pendentes` (tabela nova)

Guarda o estado entre uma mensagem do professor e a próxima — hoje isso não
existe no bridge; no app não precisa existir, porque o professor sempre abre a
aula antes de gravar.

| coluna | tipo | observação |
|---|---|---|
| `id` | uuid pk | |
| `professor_id` | integer not null | |
| `tipo` | text not null | `qual_aula_audio` \| `qual_aula_chamada` \| `confirmar_registro` \| `confirmar_chamada` |
| `payload` | jsonb not null | candidatas, `storage_path`, `registro_id`, `aula_id`, `alunos_ausentes` — conforme o tipo |
| `criado_em` | timestamptz default now() | |
| `expira_em` | timestamptz not null | `criado_em + 24h` |
| `resolvida_em` | timestamptz | null enquanto aberta |

**Uma pendência aberta por professor.** Índice único parcial em
`(professor_id) where resolvida_em is null`. Se chega um gatilho novo com uma
pendência já aberta, o Fábio não empilha uma segunda — devolve a pergunta que
já estava esperando resposta. Simplifica o estado (nunca duas coisas em
aberto ao mesmo tempo) ao custo de pedir pro professor responder em ordem; ver
"Bordas".

O bridge consulta esta tabela **antes** de qualquer outra coisa quando a
mensagem vem do canal do professor.

---

## O gatilho

- **Áudio** no canal do professor: sempre candidato a registro. Não depende
  de palavra-chave — foi a naturalidade da Daiana, sem anunciar "vou
  registrar", que expôs a confabulação, e o mesmo caminho natural é o que essa
  spec tem que aceitar.
- **Texto com padrão de chamada avulsa** ("bati a chamada", "só a Sofia
  faltou", "todo mundo veio hoje"): candidato a chamada avulsa. É reconhecimento
  por padrão, do mesmo jeito imperfeito que `asks_today`/`_has_pedagogical_history_intent`
  já são hoje — revisão contra conversas reais é parte da entrega (ver "Como se
  prova"), não uma promessa de cobertura total. Frase que não bate com nenhum
  padrão simplesmente vira conversa normal — o professor não perde nada, só não
  ganha o atalho.

## Resolução de "qual aula"

Candidatas = aulas do professor dentro da janela de `fn_janela_registro_dias()`
sem presença forte declarada (mesma fonte de `vw_registro_pendencia`, 083/084) —
um pool só, usado tanto pra áudio quanto pra chamada avulsa.

- **1 candidata:** segue direto.
- **2+:** pergunta ("foi a aula de [X] às [Y], ou a de [Z]?"), grava
  `fabio_acoes_pendentes` com as candidatas no payload, espera.
- **0:** avisa que não achou aula pendente de registro na janela e **para** —
  não tenta adivinhar, não escreve nada.

## O loop de confirmação

1. Registro estrutura (`aguardando_confirmacao`) ou chamada avulsa é montada
   → bridge lê os campos, monta um resumo legível (conteúdo + presença por
   aluno, ou só presença) e manda pro professor.
2. `fabio_acoes_pendentes` grava tipo `confirmar_registro`/`confirmar_chamada`.
3. Professor responde:
   - **Confirma** ("sim", "isso mesmo") → chama a RPC irmã, grava.
   - **Corrige** ("não, a Sofia veio") → aplica a correção nos `campos` (fonte
     é a fala do próprio professor, mesmo critério usado nas 4 correções da
     recuperação da Daiana) e manda o resumo de novo — volta ao passo 2.
   - **Não bate com nem confirmação nem correção reconhecível** → pergunta de
     novo, nunca grava por default.

## O carimbo de feito

Depois do commit: busca a devolutiva em `fabio_devolutivas` e devolve resumo +
texto dela pro professor. Como a geração da devolutiva pode não estar pronta
no instante do commit, o bridge espera até ~10s; se não chegar, manda a
confirmação do registro **agora** e o texto da devolutiva **como mensagem
seguinte**, assim que ela existir — nunca trava a conversa esperando.

---

## Bordas

| Caso | Comportamento |
|---|---|
| Professor não responde à pergunta de qual aula, ou ao read-back | Pendência expira em 24h. Nada foi escrito — nenhum registro criado, nenhuma presença gravada. A cobrança de 083/084 já vai continuar sinalizando essa aula como pendente; não duplicamos o alerta |
| Novo gatilho chega com pendência já aberta | Fábio repete a pergunta em aberto; não empilha uma segunda pendência |
| RPC estoura guarda (`janela_de_gravacao_encerrada`, `aula_cancelada`, `aula_nao_pertence_ao_professor`) | Traduzido pro professor com a mesma linguagem do `CAPACIDADE_PROFESSOR` (orientar coordenação); nunca mostra o erro técnico cru |
| Whisper erra a estrutura (ex.: caso Júlia/Clara) | Não é caminho de erro — é o que o read-back cobre. Professor corrige antes de confirmar |
| Professor manda áudio sem ter nenhuma aula pendente | Avisa e não escreve — mesmo comportamento do caso "0 candidatas" |
| Chamada avulsa cita aluno que não é da turma daquela aula | RPC recusa (mesma trava que `app_registrar_presencas_aula` já tem); Fábio traduz o erro, não tenta adivinhar quem o professor quis dizer |

---

## Como se prova

Migration nova (número a conferir no disco antes de aplicar — outra sessão
pode estar numerando em paralelo, ver `CLAUDE.md`) + `.test.sql` +
`scripts/mutantes-0XX.mjs`, padrão da casa.

**Mutantes obrigatórios:**

1. `fabio_enfileirar_audio` grava usando `aula_id` que não pertence ao
   `professor_id` recebido (guarda de dono removida).
2. `fabio_confirmar_registro`/`fabio_registrar_presencas_aula` aceitam fora da
   janela de `fn_janela_registro_dias()`.
3. `revoke`/`grant`: `authenticated` ou `anon` conseguem executar qualquer uma
   das três RPCs `fabio_*`.
4. **Teste de paridade quebrado:** alterar só o miolo chamado pela porta do
   app (ou só o chamado pela porta do Fábio) e prover que o teste de paridade
   acusa a divergência.
5. Segunda linha em `fabio_acoes_pendentes` pro mesmo professor sem a primeira
   estar `resolvida_em` — o índice único parcial tem que bloquear.
6. Pendência com `expira_em` no passado ainda é aceita como resposta válida.
7. `fabio_registrar_presencas_aula` não aciona `fn_sincronizar_gemeos_presenca`
   — regressão da 086 pela porta nova.
8. Confirmação grava mesmo com resposta do professor que não é "sim" nem uma
   correção reconhecível (deveria perguntar de novo).

Do lado Python (bridge): cenários conversacionais ao vivo, no padrão de
`teste_auditoria_carimbo.py` — incluindo o adversarial "professor manda áudio
sem aula pendente" e o "dois candidatos, professor responde ambíguo".

---

## Depois disto (fatias anotadas, fora deste spec)

1. **Pedido de liberação de prazo à coordenação**, depois dos 7 dias — hoje é
   ato humano; o Fábio já orienta a procurar a coordenação (`CAPACIDADE_PROFESSOR`).
2. **Correção de registro já confirmado** pelo WhatsApp — hoje só existe
   correção dentro do loop, antes de confirmar.
3. **Texto livre longo** como entrada (professor digita um parágrafo em vez de
   mandar áudio) — o motor de estruturação provavelmente aceita, mas não foi
   medido nesta spec.
