# Registro de aula com motor unico nos canais Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Corrigir o contrato de registro de aula para que app e WhatsApp confirmem o mesmo rascunho canonico, apliquem presenca padrao segura, entreguem um unico carimbo com devolutivas em rascunho e permitam revisao auditada, sem envio automatico a familias.

**Architecture:** Esta e uma onda corretiva sobre o motor ja publicado, nao uma segunda implementacao do WhatsApp. O nucleo SQL continua sendo a unica escrita de presenca, prontuario e devolutiva; app e bridge chamam as mesmas portas. A confirmacao cria uma saida duravel e idempotente; o `fabio_notification_worker.py` e o unico dono da entrega do carimbo, grava o recibo e espelha a mensagem no contexto conversacional que o bridge le.

**Tech Stack:** PostgreSQL 17/Supabase RPCs e RLS, React 18/TypeScript/Vite, Python 3 no bridge e workers da VPS, systemd user services, Node para testes SQL em `BEGIN/ROLLBACK`, Vitest para funcoes puras do frontend.

---

## Precedencia, estado live e regra de pilotagem

### Fontes autoritativas

- `docs/superpowers/specs/2026-08-10-fabio-escreve-no-whatsapp-design.md` continua valendo para identidade por telefone, dois pools, shortlist, estados, cinco portas, staging, idempotencia e reconciliador.
- `docs/superpowers/specs/2026-08-11-registro-aula-canais-unificados-design.md` altera somente: presenca padrao na confirmacao, deduplicacao de fatias, preview canonico, carimbo com devolutiva em rascunho no WhatsApp e memoria curta da saida.
- As migrations `090`, `091` e `092` e o bridge em `pilot` ja existem. Este plano **nao reimplementa G0-G5** do plano de 10/08; altera seus contratos por migrations aditivas e codigo incremental.

### Decisoes fechadas para esta onda

1. **Dono do carimbo: `fabio_notification_worker.py`.** O bridge manda somente pergunta, preview, correcao e confirmacao; ele nunca envia texto pos-commit. O worker entrega um unico carimbo por registro confirmado, com lease/recibo, e registra a copia outbound no ledger/contexto. Assim a mesma saida vale para confirmacoes feitas pelo app ou pelo WhatsApp.
2. **Presenca padrao e contrato do app e do WhatsApp.** `fn_confirmar_registro_core` materializa `presente` em toda fatia sem declaracao imediatamente antes de chamar o emissor canonico. Falta explicitamente declarada prevalece; rascunho ainda nao altera chamada. O teste mutante deve retirar esta materializacao e falhar, e outro deve provar que nao se marca ninguem antes da confirmacao.
3. **`Melhora a do Lucas` nao atualiza tabela pelo bridge.** Ele resolve uma devolutiva presente no carimbo/contexto e chama uma RPC guardada e auditada de edicao de rascunho. A RPC nunca envia a familia.
4. **Remediacao do Isaque e separada do contrato novo.** Corrigir Lucas ("quarto sistema") e encerrar o complementar vazio sao duas tarefas produtivas isoladas, cada uma com leitura antes/depois e trilha de auditoria.
5. **Piloto: estreitar, nao expandir.** Isaque permanece como unico piloto ja configurado; nenhum novo professor entra. Ate G8, o modo de entrega do novo recibo fica `off` e o piloto ja aceito drena pelo comportamento anterior. Nenhum novo E2E e feito antes dos contratos e das remediacoes passarem; o G9 exige aprovacao operacional explicita para ativar o recibo nesse unico piloto.

### Limites imutaveis

- Um audio representa uma unica aula. Mistura de horarios/turmas pergunta e nao grava.
- LLM so classifica/redige dentro de IDs e esquema fechados; nao escolhe aula, aluno, identidade ou presenca, nem escreve tabelas pedagogicas.
- Campo incerto fica vazio ou gera pergunta; nunca vira uma frase como "a transcricao disse".
- Conteudo comum fica no tronco. Somente complemento inequivoco e exclusivo de aluno fica na fatia.
- A devolutiva e rascunho para revisao do professor; familia/aluno nunca recebe mensagem neste fluxo.
- Uma migration so e aplicada apos teste local em rollback, preflight remoto, aprovacao daquele gate e verificacao imediata. Nunca usar `--include-all` para contornar conflito de historico.

## Mapa de arquivos e responsabilidades

| Arquivo | Mudanca nesta onda |
|---|---|
| `supabase/migrations/093-presenca-padrao-e-fatias-canonicas.sql` | Materializa presenca na confirmacao, normaliza fatias contra o tronco e deduplica a fonte de historico. |
| `supabase/migrations/093-presenca-padrao-e-fatias-canonicas.test.sql` | Provas SQL descartaveis de app/WhatsApp, falta explicita, gemeos e dedupe. |
| `scripts/mutantes-093.mjs` | Mata ausencia da chamada de presenca padrao e a retirada da guarda pre-confirmacao. |
| `supabase/migrations/094-falhas-e-correcoes-auditadas.sql` | Erro terminal de audio, correcao final auditada e edicao guardada de devolutiva. |
| `supabase/migrations/094-falhas-e-correcoes-auditadas.test.sql` | Provas de retry, auditoria, propriedade e bloqueio de envio. |
| `scripts/mutantes-094.mjs` | Mata retry de erro semantico, update direto e edicao sem auditoria. |
| `supabase/migrations/095-recibo-de-registro-no-whatsapp.sql` | Cria/claim/finalizacao da notificacao `registro_recibo` e espelho idempotente no contexto. |
| `supabase/migrations/095-recibo-de-registro-no-whatsapp.test.sql` | Provas do recibo unico, espera das devolutivas e replay. |
| `scripts/mutantes-095.mjs` | Mata a chave unica, a espera por rascunhos e o espelho no contexto. |
| `src/features/registro/camposCanonicos.ts` | Funcoes puras para comparar texto, retirar repeticao e rotular estado de rascunho. |
| `src/features/registro/camposCanonicos.test.ts` | Casos do Lucas/Nathalia, campo incerto e estado visual honesto. |
| `src/pages/app/AppHeader.tsx` | Prioriza o nome do perfil canonico sobre e-mail/telefone. |
| `src/pages/app/TurmaHistorico.tsx` | Segunda barreira visual contra repertorio comum repetido. |
| `src/features/registro/Confirmar.tsx` | Exibe o read-back estruturado e canonico, inclusive campos vazios e presencas, antes do commit no app. |
| `src/pages/app/Devolutivas.tsx` | Edita rascunho pelo wrapper auditado e mantem qualquer envio como acao manual separada. |
| `src/features/agenda/sessao.ts` e `src/features/agenda/SessaoRow.tsx` | Exibem rascunho aguardando confirmacao em vez de "Sem registro" quando houver prova de rascunho. |
| `src/features/registro/filaOffline.ts` e `src/features/registro/uploadAudio.ts` | Persistem causa/tentativas e oferecem retry/limpeza honestos para audio local. |
| `src/lib/api.ts` e `src/types/db.ts` | Tipos e chamadas das novas projecoes/RPCs; `db.ts` e regenerado, nunca editado manualmente. |
| `vps/fabio/fabio_registro_normalization_contract.py` | Esquema fechado, validacao e saneamento deterministico do payload recebido do normalizador. |
| `vps/fabio/fabio_whatsapp_actions.py` | Renderiza preview somente do read-back e encaminha revisao de devolutiva somente pela RPC. |
| `vps/fabio/fabio_whatsapp_reconciler.py` | Nao envia carimbo; apenas reconcilia estados e entrega controle ao outbox. |
| `vps/fabio/fabio_notification_worker.py` | Unico emissor de carimbo/devolutivas rascunho e gravador de contexto outbound. |
| `vps/fabio/fabio-registro-recibo.systemd.txt` | Timer/servico de 20 s para o evento de recibo, sem segredos no unit. |
| `vps/fabio/teste_registro_normalization_contract.py`, `teste_whatsapp_actions.py`, `teste_whatsapp_reconciler.py`, `teste_whatsapp_bridge.py` | Provas locais sem rede e mutantes de integracao. |
| `vps/fabio/README.md` e `RETOMADA.md` | Flags, dono de saida, implantacao, evidencia e rollback. |

## Gates

| Gate | Resultado obrigatorio | Escrita produtiva |
|---|---|---|
| G6 | Fonte do normalizador localizada e espelhada; piloto estreitado | Nao |
| G7 | SQL 093/094/095 e frontend/bridge passam localmente, incluindo mutantes | Nao |
| G8 | Migrations aplicadas e servicos atualizados, com novo recibo desligado | Sim, somente schema aditivo e deploy aprovado |
| G9 | Remediacoes isoladas do Isaque verificadas e recibo testado no unico piloto real | Sim, mediante aprovacao do gate |
| G10 | Expansao gradual e handoff | Sim, mediante nova aprovacao |

---

## G6 - congelar a fonte real e o piloto antes de mudar contrato

### Task 1: Medir paridade da fonte e travar expansao do piloto

**Files:**

- Create: `docs/superpowers/evidence/2026-08-11-registro-aula-source-parity.md`
- Modify: `vps/fabio/README.md`
- Modify: `RETOMADA.md`

- [ ] **Step 1: Fazer inventario somente leitura do banco, Edge e VPS**

Run, sem imprimir valores de `.env`:

```powershell
git status --short
npm run teste:090
npm run teste:091
npm run teste:092
ssh -i C:/Users/Texeira/.ssh/id_ed25519_lahq_fabio_claude_code fabio@89.116.73.186 "systemctl --user status fabio-chat-bridge fabio-whatsapp-reconciler.timer --no-pager; cd ~/fabio-chat-bridge; git status --short 2>/dev/null || true; rg -n --hidden --glob '!*.log' 'FABIO_WEBHOOK_URL|sem conteudo pedagogico|normaliz' ~/.hermes ~/fabio/fabio-chat-bridge"
```

Expected: 090--092 passam; o comando registra qual processo/arquivo recebe o callback do Edge e onde o payload normalizado e montado. Se nao houver fonte legivel/versionavel do callback, parar em G6: nao e seguro alterar fatiamento por suposicao.

- [ ] **Step 2: Baixar e comparar a fonte Edge que chama o callback**

```powershell
supabase functions download fabio-registro-aula --project-ref ouqwbbermlzqqvtqwlul --workdir .\_edge-source-audit
Get-FileHash .\_edge-source-audit\supabase\functions\fabio-registro-aula\index.ts -Algorithm SHA256
```

Registre no evidence o slug, versao ativa, hash, caminho do consumidor e contrato HTTP: HMAC, campos obrigatorios, status de sucesso e status semantico terminal. Nao copie segredo nem corpo de audio para o documento.

- [ ] **Step 3: Escrever o contrato de entrada que sera usado pelos dois canais**

No evidence, registrar o objeto que o consumidor deve validar antes de criar rascunho:

```json
{
  "registro_id": "uuid",
  "aula_id": 0,
  "professor_id": 0,
  "comum": {"objetivo": null, "atividades": null, "repertorio": null, "dever_casa": null, "observacoes": null},
  "fatias": [{"aluno_id": 0, "progresso": null, "repertorio": null, "presenca": null}],
  "incertezas": [{"campo": "observacoes", "trecho": "..."}]
}
```

Somente `aula_id` e `aluno_id` vindos da aula/roster ja resolvidos sao aceitos. `incertezas` faz o campo ficar nulo; nao e texto para prontuario.

- [ ] **Step 4: Aplicar a configuracao operacional minima do piloto**

No runtime, manter o professor de piloto ja configurado e adicionar, com valor inicial `off`:

```text
FABIO_REGISTRO_RECIBO_MODE=off
```

Definir `FABIO_REGISTRO_RECIBO_PILOT_IDS` com a mesma lista ja ativa em `FABIO_WHATSAPP_REGISTRO_PILOT_IDS`, sem imprimir nenhuma das duas listas em terminal, log ou documento.

Verificar no log sanitizado somente `registro_mode=pilot`, `recibo_mode=off` e a contagem de IDs; nao registrar telefone, token nem conteudo de mensagens. Nenhuma outra pessoa e adicionada.

- [ ] **Step 5: Documentar o hard-stop e commitar somente evidencias**

```powershell
git add -- docs/superpowers/evidence/2026-08-11-registro-aula-source-parity.md vps/fabio/README.md RETOMADA.md
git diff --cached --check
git commit -m "docs: congelar fonte e piloto do registro unificado"
```

---

## G7 - contratos locais, antes de qualquer escrita produtiva

### Task 2: Tornar presenca e fatias canonicas no nucleo SQL

**Files:**

- Create: `supabase/migrations/093-presenca-padrao-e-fatias-canonicas.sql`
- Create: `supabase/migrations/093-presenca-padrao-e-fatias-canonicas.test.sql`
- Create: `scripts/mutantes-093.mjs`
- Modify: `package.json`

- [ ] **Step 1: Escrever os asserts SQL que devem falhar antes da migration**

O teste cria aula/registro descartaveis em `BEGIN/ROLLBACK` e prova estas quatro saidas:

```sql
select public._assert(
  (select campos->>'presenca' from fabio_registros_aula where id = v_fatia_sem_declaracao) = 'presente',
  'confirmacao deve materializar presente quando a fatia nao declarou presenca'
);
select public._assert(
  (select campos->>'presenca' from fabio_registros_aula where id = v_fatia_falta) = 'faltou',
  'falta explicita deve prevalecer sobre o padrao'
);
select public._assert(v_chamada_antes_confirmar = 0, 'rascunho nao pode emitir presenca');
select public._assert(v_repertorio_individual is null, 'campo igual ao tronco deve sair da fatia');
```

Acrescente paridade: `app_confirmar_registro` e `fabio_confirmar_registro` chamam a mesma `fn_confirmar_registro_core`, produzem a mesma presenca e preservam a protecao de fonte forte/gemeos da 086.

- [ ] **Step 2: Rodar RED**

```powershell
node scripts/rodar-teste-sql.mjs supabase/migrations/093-presenca-padrao-e-fatias-canonicas.sql supabase/migrations/093-presenca-padrao-e-fatias-canonicas.test.sql
```

Expected: falha porque 093 ainda nao define a materializacao/dedupe.

- [ ] **Step 3: Implementar as duas funcoes deterministicas e chamar somente na confirmacao**

Em 093, definir estas assinaturas e chamar ambas dentro de `fn_confirmar_registro_core`, depois de validar propriedade/status e antes de `fabio_emitir_presenca_por_registro_e_devolutiva`:

```sql
create or replace function public.fn_materializar_presenca_padrao(
  p_registro_id uuid,
  p_professor_id integer
) returns jsonb;

create or replace function public.fn_remover_campos_comuns_da_fatia(
  p_tronco jsonb,
  p_fatia jsonb
) returns jsonb;
```

`fn_materializar_presenca_padrao` atualiza somente fatias do registro pertencentes ao professor e sem `campos.presenca`; grava `presente` nelas, preserva `faltou`, e retorna os IDs alterados. Ela nao chama `fn_registrar_presencas_core`. A chamada continua exclusiva de `fabio_emitir_presenca_por_registro_e_devolutiva`, preservando as regras anti-over-marking e de gemeos.

`fn_remover_campos_comuns_da_fatia` compara `objetivo`, `atividades`, `repertorio`, `dever_casa` e `observacoes` apos `lower(btrim(...))`; valor vazio ou igual ao tronco e removido da fatia. O normalizador/updater deve usala antes de persistir e `app_historico_turma` deve filtrar o mesmo caso como defesa a legado.

- [ ] **Step 4: Fechar privilegios e projeção de historico**

Revogar `EXECUTE` das duas funcoes internas de `public`, `anon`, `authenticated` e `service_role`; somente o core `SECURITY DEFINER` as usa. Recriar `app_historico_turma` para nao retornar `repertorio_por_aluno` igual ao `repertorio_turma`, sem apagar o dado legado. Testar ACL via `has_function_privilege`.

- [ ] **Step 5: Rodar GREEN e o mutante**

```powershell
node scripts/rodar-teste-sql.mjs supabase/migrations/093-presenca-padrao-e-fatias-canonicas.sql supabase/migrations/093-presenca-padrao-e-fatias-canonicas.test.sql
node scripts/mutantes-093.mjs
```

`mutantes-093.mjs` copia 093 para diretorio temporario, remove a chamada de `fn_materializar_presenca_padrao` e, em outra execucao, move a chamada para antes da confirmacao. Cada mutante deve fazer o teste falhar; o script retorna 0 somente se ambos morrerem.

- [ ] **Step 6: Adicionar scripts e commitar**

```json
"teste:093": "node scripts/rodar-teste-sql.mjs supabase/migrations/093-presenca-padrao-e-fatias-canonicas.sql supabase/migrations/093-presenca-padrao-e-fatias-canonicas.test.sql",
"mutantes:093": "node scripts/mutantes-093.mjs"
```

```powershell
npm run teste:093
npm run mutantes:093
git add -- package.json supabase/migrations/093-presenca-padrao-e-fatias-canonicas.sql supabase/migrations/093-presenca-padrao-e-fatias-canonicas.test.sql scripts/mutantes-093.mjs
git diff --cached --check
git commit -m "feat: unificar presenca e fatias canonicas"
```

### Task 3: Fechar falhas terminais e as duas portas auditadas de correcao

**Files:**

- Create: `supabase/migrations/094-falhas-e-correcoes-auditadas.sql`
- Create: `supabase/migrations/094-falhas-e-correcoes-auditadas.test.sql`
- Create: `scripts/mutantes-094.mjs`
- Modify: `package.json`

- [ ] **Step 1: Escrever teste RED de erro terminal, correcao final e devolutiva**

Definir no teste os contratos que nao podem ser contornados:

```sql
select public._assert(v_tentativas_depois = v_tentativas_antes,
  'erro_semantico_terminal nao pode voltar para fn_fabio_retry_fila');
select public._assert(v_auditoria_correcao = 1,
  'correcao confirmada precisa de antes/depois, autor, motivo e horario');
select public._assert(v_envio_familia = 0,
  'editar devolutiva em rascunho nunca pode criar envio a familia');
select public._assert(v_recusa_estranho,
  'professor nao pode editar devolutiva ou registro de outro professor');
```

- [ ] **Step 2: Implementar modelo de falha terminal sem parse fragil de texto**

Adicionar `erro_tipo text` a `fabio_fila_audios` com valores `transitorio|semantico_terminal`, e estender o estado com `erro_terminal`. Criar:

```sql
create or replace function public.fabio_marcar_audio_erro_terminal(
  p_audio_id uuid,
  p_codigo text,
  p_detalhe text
) returns jsonb;
```

A funcao aceita somente `sem_conteudo_pedagogico` e `transcricao_incompativel`, registra codigo/detalhe sanitizado e exige `service_role`. `fn_fabio_retry_fila` seleciona apenas `pendente` e `erro` com `erro_tipo='transitorio'`; o Edge e o consumidor do callback recusam `erro_terminal` sem alterar tentativas.

- [ ] **Step 3: Implementar as duas correcoes como RPCs, nunca update direto**

Criar tabelas `fabio_registro_correcoes` e `fabio_devolutiva_edicoes` com `id`, alvo, `professor_id`, `autor_usuario_id`, `canal`, `antes`, `depois`, `motivo`, `criado_em`. Definir:

```sql
create or replace function public.fabio_corrigir_registro_confirmado(
  p_professor_id integer, p_registro_id uuid, p_campos jsonb, p_motivo text
) returns jsonb;

create or replace function public.fabio_atualizar_devolutiva_rascunho(
  p_professor_id integer, p_devolutiva_id uuid, p_texto_normal text,
  p_texto_apoio_casa text, p_motivo text
) returns jsonb;
```

A primeira aceita somente registro confirmado do professor, lista branca de `objetivo`, `atividades`, `repertorio`, `dever_casa`, `observacoes` e `progresso`, recalcula `texto_consolidado` e usa a mesma emissao de prontuario existente; nenhuma presenca e alterada. A segunda aceita somente `gerada|oferecida`, bloqueia `compartilhada|enviada`, insere versao antes/depois e atualiza `editada_em`. Ambas retornam read-back estruturado e ficam sem grant direto ao publico; wrappers app/WhatsApp autenticam o dono antes de chamar o core.

- [ ] **Step 4: Rodar GREEN e matar mutantes**

```powershell
node scripts/rodar-teste-sql.mjs supabase/migrations/094-falhas-e-correcoes-auditadas.sql supabase/migrations/094-falhas-e-correcoes-auditadas.test.sql
node scripts/mutantes-094.mjs
```

Os tres mutantes removem, respectivamente, `erro_tipo='transitorio'`, o insert de auditoria e a guarda de status de devolutiva. Cada um deve falhar em rollback.

- [ ] **Step 5: Adicionar scripts e commitar**

```powershell
npm run teste:094
npm run mutantes:094
git add -- package.json supabase/migrations/094-falhas-e-correcoes-auditadas.sql supabase/migrations/094-falhas-e-correcoes-auditadas.test.sql scripts/mutantes-094.mjs
git diff --cached --check
git commit -m "feat: auditar correcoes e encerrar falhas semanticas"
```

### Task 4: Versionar o contrato do normalizador antes de mudar a redacao

**Files:**

- Create: `vps/fabio/fabio_registro_normalization_contract.py`
- Create: `vps/fabio/teste_registro_normalization_contract.py`
- Modify: arquivo consumidor do callback identificado no G6
- Modify: `vps/fabio/fabio_chat_bridge.py`

- [ ] **Step 1: Escrever testes puros para os casos do incidente**

```python
def test_comum_nao_reaparece_no_lucas(): ...
def test_progresso_nomeado_fica_somente_na_fatia(): ...
def test_objetivo_igual_a_atividade_vira_nulo(): ...
def test_quarto_sistema_incerto_nao_vira_observacao_factual(): ...
def test_aluno_fora_do_roster_e_rejeitado(): ...
```

O primeiro usa repertorio comum "Prelude em Do e Minueto em Sol"; o segundo usa somente um progresso explicitamente associado a Lucas; o quarto usa o trecho ambiguo "quadro/quarto sistema" e espera `observacoes is None` com `incertezas` preenchida.

- [ ] **Step 2: Rodar RED**

```powershell
python vps/fabio/teste_registro_normalization_contract.py
```

Expected: importacao/funcoes ausentes antes de criar o validador.

- [ ] **Step 3: Implementar schema fechado e saneamento deterministico**

```python
def validar_e_sanear_normalizacao(
    payload: dict, *, aula_id: int, professor_id: int, roster_ids: set[int]
) -> dict:
    """Retorna comum, fatias e incertezas; nunca infere IDs nem transforma incerteza em fato."""
```

O validador rejeita chave de aluno fora do roster, remove de fatia campo equivalente ao comum, remove objetivo sem diferenca semantica minima de atividade e transforma texto marcado/incerto em `None` mais item de `incertezas`. O prompt/consumidor passa apenas `aula_id` e roster ja resolvidos; a saida aceita somente o objeto deste contrato. O bridge usa essa funcao tambem ao montar preview, portanto o preview e o dado persistido nao divergem.

- [ ] **Step 4: Atualizar o consumidor real e assegurar falha fechada**

No arquivo localizado em G6, executar a validacao antes da RPC que cria/atualiza rascunho. Se schema, assinatura HMAC ou roster falharem, responder erro terminal seguro sem criar registro. Se houver `incertezas` que afetem campo essencial, manter em `aguardando_confirmacao` com pergunta; nunca substituir por texto inventado.

- [ ] **Step 5: Rodar as provas e commitar**

```powershell
python vps/fabio/teste_registro_normalization_contract.py
python vps/fabio/teste_whatsapp_actions.py
python vps/fabio/teste_whatsapp_bridge.py
git add -- vps/fabio/fabio_registro_normalization_contract.py vps/fabio/teste_registro_normalization_contract.py vps/fabio/fabio_chat_bridge.py
# Acrescente explicitamente o arquivo consumidor ja registrado no evidence do G6; nunca use git add -A.
git diff --cached --check
git commit -m "feat: sanear fatiamento antes do registro"
```

### Task 5: Tornar a UI uma defesa secundaria e a fila local honesta

**Files:**

- Create: `src/features/registro/camposCanonicos.ts`
- Create: `src/features/registro/camposCanonicos.test.ts`
- Modify: `package.json`
- Modify: `src/pages/app/AppHeader.tsx`
- Modify: `src/pages/app/TurmaHistorico.tsx`
- Modify: `src/features/registro/Confirmar.tsx`
- Modify: `src/pages/app/Devolutivas.tsx`
- Modify: `src/features/agenda/sessao.ts`
- Modify: `src/features/agenda/SessaoRow.tsx`
- Modify: `src/features/registro/filaOffline.ts`
- Modify: `src/features/registro/uploadAudio.ts`
- Modify: `src/pages/app/Home.tsx`
- Modify: `src/features/registro/GravarAula.tsx`
- Modify: `src/lib/api.ts`

- [ ] **Step 1: Adicionar Vitest e escrever RED para as funcoes puras**

```json
"test:unit": "vitest run",
"test:unit:watch": "vitest"
```

```ts
expect(textoEquivalente(' Prelude em Do ', 'prelude EM do')).toBe(true)
expect(repertorioIndividualVisivel('Titanic', 'Titanic')).toBe(false)
expect(nomeCabecalho({ nome: 'Isaque Mendes', email: '5521...' })).toBe('Isaque')
expect(rotuloRegistro({ temRegistro: false, temRascunho: true })).toBe('Rascunho pronto')
expect(descreverFalhaFila({ ultimaFalha: 'timeout', tentativas: 2 })).toContain('2 tentativas')
```

- [ ] **Step 2: Executar RED e implementar somente helpers deterministicas**

```powershell
npm install --save-dev vitest
npm run test:unit
```

Criar `textoEquivalente`, `repertorioIndividualVisivel`, `nomeCabecalho`, `rotuloRegistro` e `descreverFalhaFila`. Nome usa `meuPerfil().nome` quando existente, depois metadata, e so por ultimo e-mail. Nenhum helper chama Supabase.

- [ ] **Step 3: Integrar os helpers nas telas e na fila offline**

`Confirmar.tsx` renderiza somente o read-back da RPC/registro em `aguardando_confirmacao`: tronco, fatias, campos vazios, presencas/faltas e destino de devolutiva. Ele nao remonta texto de audio. Ausencia de declaracao nao gera pergunta: o preview diz que sera `presente` ao confirmar; somente `faltou` explicitamente marcado altera esse resultado. `TurmaHistorico.tsx` nao mostra repertorio individual igual ao de turma mesmo para dado legado. `Devolutivas.tsx` chama o wrapper app de `app_atualizar_devolutiva_rascunho`, exibe a versao editada e persiste somente `acaoId` + impressao SHA-256 nao reversivel do mesmo payload: cancelar fica desabilitado enquanto salva e nenhuma chave e removida antes de resposta positiva inequivoca. `SessaoRow.tsx` recebe `temRascunho` da projecao de agenda e deixa claro que falta confirmar. A schema da fila IndexedDB sobe versao preservando cada blob e adiciona `ownerUserId`, `chaveIntencao`, `storagePath`, `ultimaFalha`, `tentativas` e `ultimaTentativaEm`: todo listar, renderizar, descartar e reenviar recebe a identidade da sessao atual; itens legados sem dono ficam preservados em quarentena. A operacao IndexedDB so confirma em `transaction.oncomplete`. Reenvios usam o mesmo path, possuem mutex por `item.id` e retry automatico somente para falha transitoria, com backoff observavel e no maximo tres tentativas totais; timers duplicados nao criam novo envio. Depois disso, Home e Gravador oferecem somente `Tentar agora` ou `Descartar`, com estado `aguarda sua decisao`. Nunca chama todo erro de falta de conexao.

- [ ] **Step 4: Rodar GREEN e build**

```powershell
npm run test:unit
npm run build
```

Expected: testes passam e `tsc && vite build` termina sem erro.

- [ ] **Step 5: Commitar UI sem regenerar tipos do banco antes da publicacao do schema**

`src/types/db.ts` continua intocado neste commit: ele e regenerado no G8, apos 093--095 existirem no projeto remoto e antes de publicar o frontend.

```powershell
git add -- package.json package-lock.json src/features/registro/camposCanonicos.ts src/features/registro/camposCanonicos.test.ts src/pages/app/AppHeader.tsx src/pages/app/TurmaHistorico.tsx src/features/registro/Confirmar.tsx src/pages/app/Devolutivas.tsx src/features/agenda/sessao.ts src/features/agenda/SessaoRow.tsx src/features/registro/filaOffline.ts src/features/registro/uploadAudio.ts src/pages/app/Home.tsx src/features/registro/GravarAula.tsx src/lib/api.ts
git diff --cached --check
git commit -m "fix: mostrar registro e fila de audio com estado honesto"
```

---

## G7 - entrega unica, revisavel e contextualizada

### Task 6: Criar o outbox canonico de recibo e a edicao de devolutiva

**Files:**

- Create: `supabase/migrations/095-recibo-de-registro-no-whatsapp.sql`
- Create: `supabase/migrations/095-recibo-de-registro-no-whatsapp.test.sql`
- Create: `scripts/mutantes-095.mjs`
- Modify: `package.json`

- [ ] **Step 1: Escrever teste RED do unico dono e do replay**

```sql
select public._assert(v_notificacoes_recibo = 1, 'confirmacao deve enfileirar um unico recibo por registro');
select public._assert(v_claim_antes_devolutivas = 0, 'recibo espera todos os rascunhos exigidos');
select public._assert(v_claim_replay = 0, 'recibo enviado nao pode ser reivindicado de novo');
select public._assert(v_mensagens_contexto = 1, 'recibo enviado deve espelhar uma unica saida no contexto');
select public._assert(v_agenda_tem_rascunho, 'agenda deve expor rascunho aguardando confirmacao no slot e alvo corretos');
select public._assert(v_edicao_app_autenticada, 'wrapper app deve resolver professor por auth e auditar a edicao no nucleo');
select public._assert(v_audio_replay_mesmo_id, 'replay do mesmo storage_path deve devolver o mesmo audio_id');
```

- [ ] **Step 2: Implementar outbox sobre `fabio_notificacoes`, nao uma segunda fila**

Estender a lista valida de `tipo` com `registro_recibo`. Na confirmacao, depois de presenca/devolutivas serem enfileiradas, inserir de forma idempotente `fabio_notificacoes` com chave `(professor_id, tipo='registro_recibo', referencia_tipo='registro_aula', referencia_id=registro_id, canal='whatsapp')`. Definir:

```sql
create or replace function public.fabio_claim_registro_recibo(p_limite integer default 20) returns jsonb;
create or replace function public.fabio_concluir_registro_recibo(
  p_notificacao_id uuid, p_lease_token uuid, p_envio_recibo text, p_corpo text
) returns jsonb;
create or replace function public.fabio_falhar_registro_recibo(
  p_notificacao_id uuid, p_lease_token uuid, p_erro text
) returns jsonb;
```

O claim so retorna registros confirmados cuja lista de devolutivas de alunos presentes esteja toda `gerada|oferecida`. A conclusao confere lease, marca enviada, persiste recibo de transporte e insere/atualiza uma mensagem outbound idempotente em `fabio_chat_mensagens` com `wa_message_id` igual ao recibo. Somente `service_role` executa as tres RPCs.

Antes de qualquer deploy, 095 tambem fecha tres contratos que a UI ja consome: (1) `app_minha_agenda_sessao` retorna `tem_rascunho = true` quando existe `fabio_registros_aula.status = 'aguardando_confirmacao'` ligado a aula da sessao ou ao alvo individual agrupado; (2) `app_atualizar_devolutiva_rascunho` e uma porta autenticada, resolve `professor_id` por `auth`, valida propriedade e chama somente o nucleo auditado `fabio_atualizar_devolutiva_rascunho` de `service_role`; (3) `fn_enfileirar_audio_core` e `app_enfileirar_audio` deduplicam o replay por `storage_path` do mesmo professor, retornando o `audio_id` ja existente em vez de inserir outra fila. O navegador nunca chama RPC `fabio_*` diretamente.

- [ ] **Step 3: Garantir que o ofertador legado nao duplique a mensagem**

Alterar `fabio_devolutivas_a_oferecer` para excluir devolutivas cujo registro possui `registro_recibo` pendente/processando/enviado. O worker antigo continua como fallback apenas de devolutiva historica sem recibo; ele nunca concorre com o novo tipo.

- [ ] **Step 4: Rodar GREEN e mutantes**

```powershell
node scripts/rodar-teste-sql.mjs supabase/migrations/095-recibo-de-registro-no-whatsapp.sql supabase/migrations/095-recibo-de-registro-no-whatsapp.test.sql
node scripts/mutantes-095.mjs
```

Os mutantes removem a chave de referencia, permitem claim antes das devolutivas e removem o insert em `fabio_chat_mensagens`; tambem removem a projecao `tem_rascunho`, a resolucao de professor por `auth` do wrapper e a guarda unica de `(professor_id, storage_path)`. Todos devem morrer. As provas SQL incluem uma sessao de turma e seu alvo individual, uma tentativa de editar devolutiva por outro professor e dois `app_enfileirar_audio` com o mesmo path verificando um unico `audio_id`/registro.

- [ ] **Step 5: Adicionar scripts e commitar**

```powershell
npm run teste:095
npm run mutantes:095
git add -- package.json supabase/migrations/095-recibo-de-registro-no-whatsapp.sql supabase/migrations/095-recibo-de-registro-no-whatsapp.test.sql scripts/mutantes-095.mjs
git diff --cached --check
git commit -m "feat: entregar recibo canonico do registro"
```

### Task 7: Fazer o notification worker ser o unico emissor do carimbo

**Files:**

- Modify: `vps/fabio/fabio_notification_worker.py`
- Modify: `vps/fabio/fabio_whatsapp_actions.py`
- Modify: `vps/fabio/fabio_whatsapp_reconciler.py`
- Modify: `vps/fabio/fabio_chat_bridge.py`
- Create: `vps/fabio/teste_registro_recibo_worker.py`
- Modify: `vps/fabio/teste_whatsapp_actions.py`
- Modify: `vps/fabio/teste_whatsapp_reconciler.py`
- Modify: `vps/fabio/teste_whatsapp_bridge.py`

- [ ] **Step 1: Escrever fake-adapter tests antes da formatacao**

```python
def test_recibo_tem_aula_fatias_presenca_e_rascunhos(): ...
def test_worker_envia_uma_vez_e_persiste_recibo(): ...
def test_bridge_nao_envia_texto_pos_commit(): ...
def test_replay_do_worker_nao_reenvia(): ...
def test_melhora_lucas_chama_apenas_rpc_auditada(): ...
```

O fixture contem dois presentes, uma falta explicita e uma devolutiva por presente. O texto esperado usa o mesmo padrao do briefing: cabecalho, horario/aula, blocos por aluno, `✅ Presenca` ou `❌ Falta`, conteudo resumido e `📝 Rascunho de devolutiva`; nao inclui telefone, token, observacao incerta nem instrucao de enviar para familia.

- [ ] **Step 2: Executar RED**

```powershell
python vps/fabio/teste_registro_recibo_worker.py
```

Expected: falha porque o worker ainda so oferece link para abrir o app.

- [ ] **Step 3: Implementar o caminho de recibo no worker**

Adicionar `run_registro_recibos(channel, dry_run, professor_id=None)`. Ele chama `fabio_claim_registro_recibo`, monta texto somente dos campos retornados pelo claim, envia por UAZAPI e chama `fabio_concluir_registro_recibo`. Falha de transporte chama `fabio_falhar_registro_recibo`; timeout depois de envio nao tenta novo texto sem consultar recibo/lease. `format_oferta_devolutiva` permanece somente para legado excluido pelo SQL.

`fabio_whatsapp_actions.py`, reconciliador e bridge removem qualquer chamada/ramo que formate recibo pos-confirmacao. Depois de confirmar, respondem apenas com estado curto estruturado, por exemplo `Registro confirmado. Estou preparando seu carimbo.`, sem duplicar os campos. O bridge le a mensagem outbound espelhada no proximo contexto, portanto entende a referencia de `melhora a do Lucas`.

- [ ] **Step 4: Ligar revisao referencial a RPC auditada**

O parser recebe somente `devolutiva_id` da ultima mensagem outbound/contexto e o texto de substituicao. Sem uma unica devolutiva candidata, pergunta qual aluno; com candidato, chama:

```python
backend.rpc("fabio_atualizar_devolutiva_rascunho", {
    "p_professor_id": professor_id,
    "p_devolutiva_id": devolutiva_id,
    "p_texto_normal": texto_revisado,
    "p_texto_apoio_casa": None,
    "p_motivo": "revisao solicitada no WhatsApp",
})
```

Em seguida, renderiza o novo rascunho retornado; nao toca em `fabio_devolutivas` por REST/SQL e nao chama UAZAPI para familia.

- [ ] **Step 5: Rodar GREEN, suite anterior e mutante de integracao**

```powershell
python vps/fabio/teste_registro_recibo_worker.py
python vps/fabio/teste_whatsapp_actions.py
python vps/fabio/teste_whatsapp_reconciler.py
python vps/fabio/teste_whatsapp_bridge.py
```

Adicionar ao mutante existente uma substituicao que chama `send_message` no bridge depois de `fabio_confirmar_registro`; o teste deve detectar dois emissores e falhar.

- [ ] **Step 6: Commit**

```powershell
git add -- vps/fabio/fabio_notification_worker.py vps/fabio/fabio_whatsapp_actions.py vps/fabio/fabio_whatsapp_reconciler.py vps/fabio/fabio_chat_bridge.py vps/fabio/teste_registro_recibo_worker.py vps/fabio/teste_whatsapp_actions.py vps/fabio/teste_whatsapp_reconciler.py vps/fabio/teste_whatsapp_bridge.py
git diff --cached --check
git commit -m "feat: enviar carimbo revisavel pelo worker"
```

### Task 8: Criar timer de recibo e documentar rollback sem segredo

**Files:**

- Create: `vps/fabio/fabio-registro-recibo.systemd.txt`
- Modify: `vps/fabio/README.md`
- Modify: `RETOMADA.md`

- [ ] **Step 1: Escrever o unit versionado**

```ini
[Service]
Type=oneshot
WorkingDirectory=%h/fabio-chat-bridge
EnvironmentFile=%h/.hermes/.env
ExecStart=/usr/bin/python3 %h/fabio-chat-bridge/fabio_notification_worker.py --event registro-recibo --channel whatsapp

[Timer]
OnBootSec=20s
OnUnitActiveSec=20s
Persistent=true
```

O arquivo deve seguir o formato dos units existentes, executar como usuario `fabio`, nao conter valores de `.env` e ser instalado como servico/timer de usuario. `FABIO_REGISTRO_RECIBO_MODE=off` faz o worker sair sem claim.

- [ ] **Step 2: Testar parsing do unit e modo desligado local**

```powershell
python vps/fabio/fabio_notification_worker.py --event registro-recibo --channel whatsapp --dry-run
```

Expected: em modo `off`, `claimed=0`, `sent=0` e nenhuma chamada UAZAPI.

- [ ] **Step 3: Documentar operacao e rollback**

Documentar: dono unico, flags, comandos `systemctl --user`, consulta de leases, como desligar somente ingress/recibo, e que o rollback nao apaga outbox/auditoria nem desliga reconciliador com acao aberta.

- [ ] **Step 4: Commit**

```powershell
git add -- vps/fabio/fabio-registro-recibo.systemd.txt vps/fabio/README.md RETOMADA.md
git diff --cached --check
git commit -m "ops: agendar recibo do registro"
```

---

## G8 - publicar somente contrato testado e novo recibo desligado

### Task 9: Aplicar migrations aditivas e fazer deploy seguro da VPS

**Files deployed:**

- `supabase/migrations/093-presenca-padrao-e-fatias-canonicas.sql`
- `supabase/migrations/094-falhas-e-correcoes-auditadas.sql`
- `supabase/migrations/095-recibo-de-registro-no-whatsapp.sql`
- arquivos `vps/fabio/` dos Tasks 4, 7 e 8

- [ ] **Step 1: Fazer preflight remoto e confirmar a proxima migration**

```powershell
node scripts/consultar-sql.mjs "select version from supabase_migrations.schema_migrations order by version desc limit 10"
git status --short
npm run teste:093
npm run mutantes:093
npm run teste:094
npm run mutantes:094
npm run teste:095
npm run mutantes:095
npm run test:unit
npm run build
```

Expected: 093--095 nao existem ainda e a arvore esta limpa. Se outro ator ja usou qualquer numero, parar, reservar o proximo livre e atualizar todos os caminhos/scripts deste plano antes de aplicar; nunca reaplicar uma migration com conteudo diferente.

- [ ] **Step 2: Obter aprovacao explicita para G8 e aplicar uma migration por vez**

```powershell
node scripts/aplicar-sql.mjs supabase/migrations/093-presenca-padrao-e-fatias-canonicas.sql
node scripts/consultar-sql.mjs "select to_regprocedure('public.fn_materializar_presenca_padrao(uuid,integer)') is not null as ok"
node scripts/aplicar-sql.mjs supabase/migrations/094-falhas-e-correcoes-auditadas.sql
node scripts/aplicar-sql.mjs supabase/migrations/095-recibo-de-registro-no-whatsapp.sql
```

Depois de cada aplicacao, consultar definicao/ACL e executar o teste correspondente contra o banco antes de seguir. Falha para o gate; nao corrigir estado produtivo com SQL manual.

- [ ] **Step 3: Fazer backup preciso e copiar somente arquivos versionados**

No VPS, verificar caminho absoluto dentro de `~/fabio-chat-bridge/backups/20260811-registro-unificado/`, criar copias apenas dos arquivos a substituir, executar `python3 -m py_compile` e comparar checksums entre espelho e runtime. Drift inesperado interrompe o deploy para reconciliacao; nao sobrescrever a fonte viva.

- [ ] **Step 4: Instalar/reiniciar com recibo desligado**

```text
systemctl --user daemon-reload
systemctl --user restart fabio-chat-bridge
systemctl --user restart fabio-whatsapp-reconciler.service
systemctl --user enable --now fabio-registro-recibo.timer
systemctl --user status fabio-chat-bridge fabio-whatsapp-reconciler.timer fabio-registro-recibo.timer --no-pager
```

Confirmar nos logs somente que `recibo_mode=off`, o bridge esta ativo e nenhum carimbo novo foi enviado. O job antigo de devolutiva deve continuar sem oferecer um item pertencente ao novo outbox.

- [ ] **Step 5: Registrar evidencia factual e commitar**

```powershell
npx supabase gen types typescript --project-id ouqwbbermlzqqvtqwlul --schema public
# Aplique a saida em src/types/db.ts usando apply_patch; nao edite tipos manualmente.
npm run build
git add -- RETOMADA.md src/types/db.ts
git diff --cached --check
git commit -m "docs: registrar publicacao do contrato unificado"
```

---

## G9 - remediar os dois efeitos do Isaque e provar o unico piloto

### Task 10: Corrigir Lucas por operacao auditada, sem tocar diretamente nas tabelas

**Files:**

- Modify: `RETOMADA.md`

- [ ] **Step 1: Fazer snapshot somente leitura do registro confirmado de Lucas**

Consultar por ID de registro anotado na evidencia do incidente, confirmando professor dono, status confirmado, frase antiga, aulas/prontuarios afetados e ausencia de outra correcao posterior. Se qualquer precondicao diferir, parar e pedir decisao; nao inferir alvo por nome.

- [ ] **Step 2: Obter aprovacao especifica para a correcao produtiva**

Apresentar a diferenca exata: apenas `observacoes` muda de frase que menciona transcricao para `Conseguiu ler ate o quarto sistema decorado.`. Nenhum objetivo, atividade, repertorio, presenca, devolutiva ou outro aluno entra no patch.

- [ ] **Step 3: Executar a RPC guardada uma vez**

```sql
select public.fabio_corrigir_registro_confirmado(
  :professor_id,
  :registro_id,
  jsonb_build_object('observacoes', 'Conseguiu ler ate o quarto sistema decorado.'),
  'Correcao aprovada do termo transcrito ambiguo no incidente Isaque 2026-08-10'
);
```

Usar parametros do cliente SQL seguro, nunca interpolacao de IDs/texto no shell. Salvar somente IDs/redacao aprovada no evidence, sem dados desnecessarios de aluno.

- [ ] **Step 4: Verificar o depois e registrar auditoria**

Ler o registro, prontuario materializado e `fabio_registro_correcoes`. Esperado: exatamente uma auditoria, `antes`/`depois` corretos, mesma presenca, mesma lista de devolutivas e nenhum novo envio WhatsApp/familia.

- [ ] **Step 5: Atualizar handoff e commitar**

```powershell
git add -- RETOMADA.md
git diff --cached --check
git commit -m "docs: registrar correcao auditada do incidente Isaque"
```

### Task 11: Marcar o complementar vazio como terminal e provar que nao reanima

**Files:**

- Modify: `RETOMADA.md`

- [ ] **Step 1: Fazer leitura antes do audio complementar pelo UUID de evidencia**

Confirmar que o audio ainda pertence ao registro da aula de 15h, que o erro e semantico (nao rede/transcricao pendente), e anotar `tentativas`, status e `updated_at` antes da alteracao.

- [ ] **Step 2: Obter aprovacao especifica e chamar a porta terminal**

```sql
select public.fabio_marcar_audio_erro_terminal(
  :audio_id,
  'sem_conteudo_pedagogico',
  'Audio complementar sem informacao de aula; encerrado apos revisao aprovada.'
);
```

- [ ] **Step 3: Provar ausencia de novo retry**

Executar uma unica rodada controlada de `fn_fabio_retry_fila()` ou esperar o proximo cron observado, depois reler o audio. Esperado: `status='erro_terminal'`, `erro_tipo='semantico_terminal'`, mesmas tentativas e nenhuma nova chamada Edge para esse UUID.

- [ ] **Step 4: Registrar evidencia e commitar**

```powershell
git add -- RETOMADA.md
git diff --cached --check
git commit -m "docs: encerrar complementar vazio do incidente Isaque"
```

### Task 12: Ativar recibo apenas para Isaque e executar E2E controlado

**Files:**

- Modify: `RETOMADA.md`

- [ ] **Step 1: Obter aprovacao operacional para o unico piloto**

Confirmar uma aula real elegivel, uma turma/horario e consentimento do professor. Nao criar professor, aluno, aula, presenca ou audio sinteticos. Definir o inicio e a janela de observacao; familia permanece fora do teste.

- [ ] **Step 2: Fazer snapshot antes do fluxo**

Para a aula aprovada, registrar somente contagens/IDs de rascunhos, presencas, devolutivas, notificacoes `registro_recibo` e mensagens outbound. Verificar `FABIO_REGISTRO_RECIBO_MODE=off` antes do audio.

- [ ] **Step 3: Habilitar recibo para o unico piloto e enviar um audio de uma unica aula**

Alterar para `FABIO_REGISTRO_RECIBO_MODE=pilot`, manter a mesma lista de IDs de piloto e reiniciar apenas os units necessarios. O professor ve o preview canonico, com campos vazios realmente vazios, presencas/faltas e uma fatia por aluno. Se houver aula misturada ou duvida, o resultado esperado e pergunta/nenhuma escrita final.

- [ ] **Step 4: Confirmar e verificar todos os efeitos uma vez**

Depois de confirmacao positiva, provar na sequencia:

1. `fn_confirmar_registro_core` foi a porta chamada, independentemente de o inicio ser app ou WhatsApp;
2. todos os alunos sem falta explicita ficaram presentes e gemeos respeitaram fonte forte;
3. comum nao reaparece em fatia/historico; objetivo nao e copia da atividade; trecho incerto ficou vazio/perguntado;
4. ha uma devolutiva `gerada|oferecida` por presente, zero por falta, e zero envio a familia;
5. ha exatamente uma notificacao `registro_recibo`, uma mensagem WhatsApp e uma mensagem outbound no contexto com o mesmo recibo;
6. repetir/reentregar webhook ou worker nao cria segunda presenca, devolutiva, carimbo ou mensagem;
7. pedido referencial de melhora para um aluno presente cria uma linha de `fabio_devolutiva_edicoes`, devolve novo rascunho e nao envia para familia.

- [ ] **Step 5: Comparar com o app e fechar o gate**

Executar o mesmo caminho por preview/confirmacao no app para a mesma aula somente se houver um segundo caso real aprovado; comparar forma do registro, presencas e rascunhos, nunca reutilizar a mesma aula para duplicar escrita. Separar no relatorio: codigo no ar, worker saudavel e E2E real aprovado.

- [ ] **Step 6: Desligar expansao, registrar e parar para G10**

Manter `pilot` somente para Isaque. Registrar tempo, IDs, contagens, mensagens de status e qualquer divergencia em `RETOMADA.md`; nao promover para `on` sem aprovacao nova.

---

## G10 - revisao final e expansao gradual

### Task 13: Revisar, monitorar e pedir a proxima autorizacao

**Files:**

- Modify: `RETOMADA.md`
- Modify: `vps/fabio/README.md`

- [ ] **Step 1: Rodar verificacao fresca completa**

```powershell
npm run teste:090
npm run teste:091
npm run teste:092
npm run teste:093
npm run mutantes:093
npm run teste:094
npm run mutantes:094
npm run teste:095
npm run mutantes:095
npm run test:unit
npm run build
python vps/fabio/teste_registro_normalization_contract.py
python vps/fabio/teste_registro_recibo_worker.py
python vps/fabio/teste_whatsapp_actions.py
python vps/fabio/teste_whatsapp_reconciler.py
python vps/fabio/teste_whatsapp_bridge.py
```

- [ ] **Step 2: Fazer preflight observavel do banco e VPS**

Verificar migrations, ACL/RLS das RPCs novas, notificacoes com lease vencido, audio `erro_terminal`, acao pendente, orfaos de Storage e estado dos tres units. Monitorar codigos/contagens, nao corpos de audio/mensagens.

- [ ] **Step 3: Fazer revisao independente da diff**

Invocar `superpowers:requesting-code-review`. A revisao deve confirmar: uma unica saida de carimbo, ausencia de acesso direto de bridge a tabelas pedagogicas, nenhuma regressao da fonte forte, nenhuma mensagem a familia, e nenhuma reimplementacao das portas 090/091.

- [ ] **Step 4: Preparar rollback verificavel**

Rollback de entrada: manter `FABIO_WHATSAPP_REGISTRO_MODE=pilot` ou `off`. Rollback de carimbo: `FABIO_REGISTRO_RECIBO_MODE=off` e restart do timer; leases ja aceitos sao tratados pelo worker, sem apagar outbox/auditoria. Nao fazer rollback de schema destrutivo; qualquer reversao de dado e uma migration forward aprovada.

- [ ] **Step 5: Atualizar handoff e pedir autorizacao de expansao**

Registrar commits, hashes, migrations, servicos, resultados e rollback testado. Apresentar explicitamente a decisao: manter Isaque, incluir um professor adicional ou promover geral. Nenhuma opcao e escolhida por inferencia.

## Matriz final de aceite

| Requisito | Prova |
|---|---|
| Mesmo motor no app e WhatsApp | 093 testa os dois wrappers no mesmo core; G9 compara read-backs reais aprovados. |
| Presenca padrao sem over-marking | 093 + mutantes; rascunho nao marca, falta prevalece, core emite fontes/gemeos. |
| Fatiamento sem redundancia | contrato Python + 093 + UI defensiva. |
| Incerto nao vira fato | fixture `quadro/quarto sistema` e preview com campo vazio/pergunta. |
| Preview e dado sao o mesmo rascunho | bridge usa read-back/contrato canonico; nao ha segunda montagem. |
| Um carimbo, com memoria | 095 lease/recibo/contexto + mutante contra segundo emissor. |
| Devolutiva e revisavel, nunca enviada | 094 status/auditoria + worker fake + E2E. |
| Complementar vazio para de retentar | 094 + Task 11 antes/depois. |
| Correcao do Lucas e auditavel | 094 + Task 10 com diferenca exata. |
| Piloto nao se expande por acidente | G6 flag `off`, G9 unico ID e G10 pede nova autorizacao. |

## Sequencia de commits

1. `docs: congelar fonte e piloto do registro unificado`
2. `feat: unificar presenca e fatias canonicas`
3. `feat: auditar correcoes e encerrar falhas semanticas`
4. `feat: sanear fatiamento antes do registro`
5. `fix: mostrar registro e fila de audio com estado honesto`
6. `feat: entregar recibo canonico do registro`
7. `feat: enviar carimbo revisavel pelo worker`
8. `ops: agendar recibo do registro`
9. `docs: registrar publicacao do contrato unificado`
10. dois commits documentais separados para as remediacoes do Isaque.

Nenhum commit mistura schema nao revisado, deploy da VPS e evidencia produtiva. Parar em qualquer gate mantem o sistema seguro e e um checkpoint valido; somente G10 autoriza discutir expansao.
