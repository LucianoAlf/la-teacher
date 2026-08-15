# Ocorrência de participação (substituição) — camada em shadow

**Data:** 15/08/2026
**Status:** design aprovado (Alf + Alfredo), sem migration viva até revisar a spec.

## Por que isto existe

No teste real do Isaque (15/08), o Fábio soube achar a *aula* ("quem fez no
lugar do Jeremias foi a Juliana" → aula das 14h, pelo Jeremias que está no
roster), mas **não teve onde registrar que quem participou foi a Juliana, não o
Jeremias**. O roster diz o **esperado**; o Emusys também. A **participação real
divergente do esperado** — substituição, reposição por outro, convidado — não
tem lugar canônico no sistema.

Isto **não é buraco de regex.** O casador determinístico
(`fabio_aulas_candidatas` → roster) é chão de verdade suficiente pra *aula*. O
que falta é **modelar participação real separada do roster esperado**.

Esta é a **primeira frente construída no modelo-Maria certo** — chão
determinístico + interpretação + shadow + validação da coordenação — pra virar
o molde das próximas. NÃO é a re-arquitetura inteira do Fábio nem tela.

## Princípios inegociáveis

1. **A aula esperada continua vindo de `fabio_aulas_candidatas`/roster.** Esta
   camada não substitui nem reescreve o roster; ela **observa** divergência.
2. **Append-only.** Nada de UPDATE apagando história. Correção de FATO é linha
   nova apontando pra anterior (`supersede_ocorrencia_id`). O ciclo de vida
   (candidata → confirmada → validada/descartada) é um **log de eventos**
   próprio, também append-only — mesmo padrão de `fabio_acoes_pendentes` +
   `fabio_acao_eventos` que já existe na casa.
3. **`candidata` não toca em nada.** Presença, falta, reposição, financeiro,
   Emusys — zero efeito colateral enquanto for shadow. O Jeremias **não** vira
   falta automática. A ocorrência só diz "houve substituição, com esta
   confiança".
4. **Só `validada` pela coordenação** pode, numa fase FUTURA (fora desta spec),
   virar efeito operacional.
5. **Extração determinística primeiro; LLM bounded como fallback/fase seguinte,
   nunca juiz soberano.**

## Escopo desta spec (o que entra / o que NÃO entra)

**Entra:**
- Tabela `fabio_participacao_ocorrencias` (fatos, insert-only).
- Tabela `fabio_participacao_ocorrencia_eventos` (ciclo de vida, insert-only).
- View `vw_fabio_participacao_ocorrencia_estado` (estado atual = último evento).
- RPCs: registrar candidata, confirmar, validar, descartar; helper de
  resolução de identidade do participante.
- Detector determinístico de substituição em `fabio_whatsapp_intents.py`.
- Gravação em SHADOW a partir do fluxo de registro por WhatsApp.
- Testes (contrato SQL em rollback + mutantes; unidade Python).

**NÃO entra (fica pra spec/fase seguinte):**
- Qualquer efeito em presença/falta/reposição/financeiro/Emusys.
- Extração por LLM (só o gancho fica previsto).
- Tela de coordenação pra validar (a validação nesta fase é RPC/consulta).
- A re-arquitetura geral do roteamento do Fábio (modelo-Maria completo).

## Modelo de dado

### `fabio_participacao_ocorrencias` (insert-only — os FATOS)

| coluna | tipo | nota |
|---|---|---|
| `id` | uuid pk | `gen_random_uuid()` |
| `aula_operacional_id` | integer not null | resolvido por `fn_aula_operacional_id` |
| `aula_id` | integer not null | o evento cru que a mensagem pinou |
| `professor_id` | integer not null | quem relatou |
| `aluno_matriculado_id` | integer not null | quem o roster esperava (Jeremias) |
| `participante_real_id` | integer null | **só** se aluno da casa E identidade única |
| `participante_real_nome` | text null | quando externo/incerto |
| `participante_real_telefone` | text null | idem, se houver |
| `tipo` | text not null | CHECK `in ('substituicao')` — extensível sem migrar de novo |
| `confianca` | text not null | CHECK `in ('alta','media','baixa')` |
| `metodo_extracao` | text not null | CHECK `in ('deterministico','llm')` — pra medir det × llm |
| `origem_message_id` | text null | `wa_message_id` que disparou |
| `origem_transcricao` | text null | a frase que gerou (auditoria + medição) |
| `supersede_ocorrencia_id` | uuid null | FK self — correção de FATO aponta pra linha anterior |
| `criado_em` | timestamptz not null | `now()` |

**Constraints:**
- `chk_participante_identificado`: `participante_real_id is not null OR
  coalesce(btrim(participante_real_nome),'') <> ''` — ninguém entra sem dizer
  quem participou.
- `chk_matriculado_difere_participante`: quando `participante_real_id` está
  preenchido, ele ≠ `aluno_matriculado_id` (substituir por si mesmo não é
  substituição).
- Append-only imposto por **grant** (só `INSERT`/`SELECT` a `service_role`; sem
  `UPDATE`/`DELETE` a ninguém) — o teste confere que o privilégio não existe.

### `fabio_participacao_ocorrencia_eventos` (insert-only — o CICLO DE VIDA)

| coluna | tipo | nota |
|---|---|---|
| `id` | uuid pk | |
| `ocorrencia_id` | uuid not null | FK → ocorrências |
| `evento` | text not null | CHECK `in ('registrada','confirmada','validada','descartada','corrigida')` |
| `por_tipo` | text not null | CHECK `in ('sistema','professor','coordenacao')` |
| `por_id` | text null | professor_id / usuario_id da coordenação |
| `dados` | jsonb not null default `'{}'` | motivo do descarte, id que corrige, etc. |
| `criado_em` | timestamptz not null | `now()` |

Toda ocorrência nasce com um evento `registrada`. As transições são novas
linhas. Nunca há UPDATE.

### `vw_fabio_participacao_ocorrencia_estado`

Estado atual = o último evento por `ocorrencia_id` (por `criado_em`, desempate
por `id`). Expõe `ocorrencia_id`, `estado_atual`, `estado_em`, `estado_por`.
É a fonte única de "em que pé está cada ocorrência" — ninguém lê o ciclo de
vida direto da tabela de eventos.

## Ferramentas (RPCs) — contrato

Todas `security definer`, `search_path` fixo, **só `service_role`**.

### `fabio_resolver_participante(p_professor_id, p_unidade_id, p_nome) → jsonb`
Escada de identidade do participante:
1. carteira do professor (mesmo instrumento/unidade) →
2. alunos da unidade →
3. nada → externo.

Retorno: `{ cardinalidade, candidatos:[{aluno_id,nome}], origem }` onde
`cardinalidade` = 0 (externo), 1 (única) ou >1 (ambíguo). **Não decide** —
devolve o que achou; quem decide pedir confirmação é o chamador.

### `fabio_participacao_registrar_candidata(...) → jsonb`
Entradas: `p_aula_id`, `p_professor_id`, `p_aluno_matriculado_id`,
`p_participante_real_id` (null se incerto), `p_participante_nome`,
`p_participante_telefone`, `p_confianca`, `p_metodo_extracao`,
`p_origem_message_id`, `p_origem_transcricao`.

Faz, **em shadow**: resolve `aula_operacional_id`; insere o FATO; insere evento
`registrada`. **Nada além disso** — não lê presença, não escreve presença, não
chama Emusys. Retorno: `{ ok, ocorrencia_id, estado:'candidata',
precisa_confirmar (bool), motivo_ambiguidade }`.
`precisa_confirmar = true` quando a identidade do participante é ambígua
(cardinalidade > 1) ou externa com confiança < alta.

### `fabio_participacao_confirmar(p_ocorrencia_id, p_professor_id) → jsonb`
Insere evento `confirmada` (por `professor`). Idempotente: confirmar duas vezes
não empilha efeito. **Continua sem efeito operacional** — só avança o ciclo.

### `fabio_participacao_validar(p_ocorrencia_id, p_validado_por) → jsonb`
Insere evento `validada` (por `coordenacao`). É o **portão** que uma fase
futura vai exigir antes de qualquer efeito em presença. Nesta spec, validar
apenas carimba — não dispara nada.

### `fabio_participacao_descartar(p_ocorrencia_id, p_motivo, p_por_tipo, p_por_id) → jsonb`
Insere evento `descartada` com o motivo em `dados`.

## Extração — determinística primeiro

Novo detector puro em `fabio_whatsapp_intents.py`:

```
detectar_substituicao(texto, roster_da_aula) -> {matriculado_ref, participante_nome} | None
```

Frases fortes (normalizadas, sem acento): `no lugar d[eoa]`, `quem fez foi`,
`substituiu`, `veio no lugar`, `no lugar dele/dela`. O **matriculado** é casado
contra os nomes do roster da aula (o Jeremias, que o casador já usou pra pinar
a aula); o **participante** é o outro nome citado. Se o padrão não extrai
limpo, devolve `None` — e aí (fase seguinte) entra o LLM bounded como fallback.
Nunca o contrário.

**Como a confiança é atribuída** (não é palpite do modelo — é regra do
chamador): frase forte determinística **+** participante resolvido único na
carteira → `alta`; frase forte mas participante ambíguo (cardinalidade > 1) →
`media`; participante externo/não encontrado, ou extração só por LLM (fase
seguinte) → `baixa`. `media`/`baixa` sempre `precisa_confirmar`.

**Onde encaixa no fluxo:** depois que o registro por WhatsApp pina a aula
(`_start_from_candidates`/`_refine_pending_class`), roda `detectar_substituicao`
sobre a transcrição. Se achar par, chama `fabio_participacao_registrar_candidata`
em shadow **em paralelo** ao registro normal — o registro segue salvando contra
o roster (Jeremias), a ocorrência é a verdade paralela que a gente mede.

## Shadow: o que significa e como se mede

- **Significa:** ocorrências são gravadas e o ciclo avança (candidata →
  confirmada quando o professor concorda), mas **nada** lê essas linhas pra
  alterar presença/registro/Emusys.
- **Mede-se:** quantas candidatas viram confirmadas (professor concordou) ×
  quantas são descartadas (o Fábio entendeu errado), por `confianca` e por
  `metodo_extracao`. Consulta simples sobre a view de estado.
- **Critério de subir de fase (fora desta spec):** taxa de confirmação alta o
  suficiente na confiança `alta`, medido em corpus real — decisão do Alf.

## Fases (modelo-Maria)

- **Fase 0 — shadow (ESTA spec):** grava, pergunta quando ambíguo, mede. Zero
  efeito operacional.
- **Fase 1 — efeito assistido (spec futura):** ocorrência `validada` pela
  coordenação passa a marcar o matriculado como reposição/ausência-justificada
  (regra a definir) e o participante como presente. Nunca sem validação.
- **Fase 2 — LLM + proativo (spec futura):** extração por LLM promovida a
  primeira linha quando a determinística não pega; Fábio propõe sozinho.

## Erros e bordas

- **Participante = externo:** `participante_real_id` fica null, nome/telefone
  preenchidos, `precisa_confirmar = true`. A casa decide depois se vira aluno.
- **Participante ambíguo (dois "Juliana"):** o Fábio **pergunta**, não chuta —
  `precisa_confirmar = true` com `motivo_ambiguidade`.
- **Correção:** o professor diz depois "na verdade foi a Marina" → linha nova
  com `supersede_ocorrencia_id` da anterior + evento `corrigida` na antiga.
- **Reentrega do UAZAPI:** idempotência por `origem_message_id` — a mesma
  mensagem não gera duas candidatas (índice único parcial por
  `(aula_operacional_id, aluno_matriculado_id, origem_message_id)` onde
  `supersede_ocorrencia_id is null`).

## Testes

**Contrato SQL (rollback contra produção) + mutantes Docker:**
- append-only imposto: `service_role` não tem `UPDATE`/`DELETE` nas duas
  tabelas (mutante que concede o privilégio morre);
- estado derivado do último evento (mutante que lê estado de outro lugar
  morre);
- cadeia de supersede coerente;
- `candidata` não escreve em nenhuma tabela de presença/registro (o ensaio
  conta linhas antes/depois e exige zero);
- escada de identidade devolve cardinalidade certa (0/1/>1);
- idempotência por `origem_message_id`.

**Unidade Python (`teste_whatsapp_intents`):**
- `detectar_substituicao("quem fez aula no lugar do Jeremias foi a Juliana",
  roster=[Jeremias]) == {matriculado: Jeremias, participante: "Juliana"}` — a
  frase EXATA do Isaque;
- as quatro frases fortes;
- frase sem substituição → `None` (não inventa);
- participante ambíguo → o chamador marca `precisa_confirmar`.

**Falsificação:** rodar o detector contra a transcrição real logada do Isaque
(`fabio_chat_mensagens`) e confirmar o par.

## Arquivos

- `supabase/migrations/<ts>_participacao_ocorrencias_shadow.sql` (+ `.test.sql`)
- `scripts/mutantes-<ts>.mjs`
- `vps/fabio/fabio_whatsapp_intents.py` — `detectar_substituicao`
- `vps/fabio/fabio_whatsapp_actions.py` — chamada em shadow no fluxo de registro
- `vps/fabio/teste_whatsapp_intents.py` — testes do detector
