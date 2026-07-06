# LA Teacher · Sprint 3 — Motor de Registro (Pacote de Execução)
### Áudio → fila → transcrição → normalização (Alma do Fábio) → Confirmação → gravação POR ALUNO · 04/07/2026

## Mini-PRD do Sprint

**Objetivo:** ao fim do S3, o golden path acontece de verdade: o professor grava o áudio da aula (turma ou 1:1), o Fábio transcreve e estrutura nos Moldes, o professor confere e confirma, e o texto é **gravado na aula de cada aluno presente** via `registrar_aula_fabio`. A North Star começa a subir.

**Entra:** captura de áudio no PWA (offline-first) · upload + fila · Edge Function de processamento (STT + normalização com a Alma) · tela de Confirmação real (tronco+fatias, edição, cutucadas de campo faltante, checkpoint) · confirmação com gravação por aluno · correção por voz (modo complementar) · Realtime nos status.
**Não entra (S4+):** chat espelhado, canal WhatsApp do Fábio, push notification (Realtime in-app basta), briefing dinâmico, dever→responsável.

**Materiais:** `la-teacher-sql-002-motor-registro.sql` · `fabio-alma-normalizacao-v1.md` · protótipo (spec visual) · pacote do S2 (pré-requisito concluído).
**Regras transversais:** tokens semânticos (checklist anti-hex em todo prompt) · dados só via RPCs `app_*` · a Alma é arquivo versionado — a edge **lê do repo**, nunca embute cópia divergente.

---

## P5 · Captura de áudio + upload + fila (offline-first)

```
Implemente o fluxo de gravação seguindo as telas 2 (Gravação) do protótipo:

1. Hook useRecorder (src/features/registro/useRecorder.ts):
   MediaRecorder com mime por plataforma — Safari/iOS: 'audio/mp4';
   demais: 'audio/webm;codecs=opus'. Estados: idle/recording/paused.
   Timer, pausar/retomar, descartar. Limite: 10 min (aviso aos 9).
2. Entrada pelo FAB e pelo badge "Registrar" da aula: aula do contexto
   pré-selecionada (a mais próxima do horário atual sem anotação;
   "trocar" abre lista do dia).
3. Offline-first: ao parar, salvar blob + metadados em IndexedDB
   (idb-keyval). Uploader em background: sobe para o bucket
   fabio-audios no caminho {auth.uid()}/{uuid}.{ext}, com retry
   exponencial; ao concluir, chama app_enfileirar_audio(aula_id,
   storage_path, duracao) e remove do IndexedDB.
4. Navegar para a tela Processando imediatamente após parar (o upload
   segue em background); banner discreto se estiver offline
   ("gravação guardada — envio automático ao reconectar").

Aceite: gravar 30s em Android/Chrome e iOS/Safari → arquivo no bucket,
linha 'pendente' na fila; teste em modo avião → reconectar → sobe e
enfileira sozinho; descartar não deixa lixo no IndexedDB; anti-hex ok.
```

## P6 · Edge Function `fabio-processa-audio` (STT + Alma)

```
Crie supabase/functions/fabio-processa-audio (Deno) com este contrato:

ENTRADA: POST {audio_id} · Authorization: Bearer FABIO_EDGE_TOKEN
  (validar contra env; 401 se divergente).
ENVS: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, GROQ_API_KEY,
  ANTHROPIC_API_KEY, FABIO_EDGE_TOKEN.

PASSOS:
1. Carregar fila (service client). Status inválido/inexistente → 200
   com {skip}. Marcar 'transcrevendo'.
2. Baixar o áudio do Storage; transcrever via Groq
   (model whisper-large-v3-turbo, language 'pt', response_format text).
   Falha → status 'erro' + campo erro + throw. Salvar 'transcricao',
   status 'transcrito'.
3. Montar contexto da aula: vw_fabio_aulas_contexto pela aula_id da
   fila. Se tipo turma: TODAS as linhas de mesma turma_nome + data +
   horário → lista alunos[{aluno_id, aula_id, nome, presenca_status}]
   (LEMBRE: o espelho é 1 linha por aluno — cada aluno tem a própria
   aula_id, e é nela que se grava depois).
4. Detectar modo: registro-alvo com campos->>'audio_complemento_id' =
   audio_id → modo 'complementar' (incluir registro_existente no input).
5. Chamar Anthropic /v1/messages — model claude-sonnet-4-6,
   max_tokens 4096, system = conteúdo INTEGRAL de
   docs/fabio-alma-normalizacao-v1.md (ler do repo no build),
   user = JSON de entrada da Alma. Parsear a saída como JSON estrito
   (strip de cercas se houver); inválido → 1 retry com instrução de
   correção; persistir falha como status 'erro'.
6. Persistir (modo novo): inserir tronco (parent null; turma:
   aluno_id null / 1:1: aluno_id preenchido) + fatias (parent_id,
   aluno_id, aula_id DO ALUNO, campos, texto_consolidado), molde,
   checkpoint_sugerido, origem da fila, status
   'aguardando_confirmacao'. Modo complementar: UPDATE cirúrgico dos
   campos/textos retornados no registro existente.
7. Fila → 'normalizado'. Retornar {registro_id}.

Aceite: áudio de teste de turma (usar o roteiro do Exemplo 1 da Alma)
vira tronco + 4 fatias em <60s, com aula_id correta em cada fatia,
campos null onde não dito e qualidade.faltando preenchido; Realtime
dispara mudança de status; token errado → 401; simulação de falha do
STT deixa status 'erro' e o cron reprocessa.
```

## P7 · Tela de Confirmação (a tela-estrela, com dados reais)

```
Implemente /app/registro/:id conforme a tela 4 do protótipo:

1. Carregar raiz + fatias (app_meus_registros / select por RLS).
2. Tronco: renderizar SÓ campos não-nulos + botão "adicionar campo"
   (atividades, objetivo, repertorio, materiais, dever_casa,
   obs_gerais); dever_casa com destaque warning.
3. Fatias em accordion: badge de presença; os TRÊS campos sempre
   visíveis — valor null renderiza a cutucada ("Não ouvi esse ponto —
   toque pra completar. Eu nunca invento ✋") em text-muted itálico.
   Edição inline salva no JSONB (update coberto pela RLS) com
   feedback; editar campo regenera o texto_consolidado da fatia no
   cliente (mesmo formato da Alma).
4. checkpoint_sugerido → card de sugestão com Aceitar/Agora não
   (aceite grava flag no campos do tronco; sem jornada → não renderiza).
5. avisos[] da normalização → banner discreto no topo.
6. Rodapé fixo: [🎤 Corrigir por voz] [✓ Confirmar] (P8/P9).

Aceite: paridade visual com o protótipo nos 2 temas; campo faltante
mostra cutucada; edição persiste e sobrevive a reload; anti-hex ok.
```

## P8 · Confirmar (gravação por aluno) + Sucesso

```
1. Botão Confirmar → app_confirmar_registro(id) com estado de envio.
2. Tela Sucesso (tela 5 do protótipo) com o retorno REAL: X gravadas ·
   Y ausentes puladas · pendências (se houver, listar com link de
   volta pra fatia). Rodapé técnico: "registrar_aula_fabio · N aulas".
3. Voltar ao início: Home releitura — status derivado da aula agora
   considera anotacoes_fabio (aula vira Registrada), contador e
   pendências atualizam.

Aceite (teste de fogo): confirmar um registro de turma com 3 presentes
+ 1 ausente → conferir no banco anotacoes_fabio preenchida nas 3 aulas
dos presentes (cada texto com o bloco do próprio aluno), NADA gravado
no ausente, aula_registros_fabio_log com 3 linhas; confirmar um 1:1
grava 1. Reconfirmar → idempotência da RPC preserva (sem duplicação).
```

## P9 · Corrigir por voz + acabamento

```
1. "Corrigir por voz": gravação curta (mesmo useRecorder, limite 2min)
   → upload → app_enfileirar_audio(aula_id, path, duracao,
   registro_id) → aguardar Realtime → re-render dos campos alterados
   com highlight + toast listando os avisos de complemento.
2. Tratamento de erro da fila: card na Home/Processando para status
   'erro' com "tentar de novo" (chama app_enfileirar_audio de novo?
   NÃO — botão dispara fn via nova linha? Simples: exibir orientação e
   deixar o cron reprocessar; botão apenas atualiza o status visível).
3. Estados vazios e microcopy final em pt-BR; revisão de acessibilidade
   básica (foco, contraste já garantido pelos tokens).

Aceite: complemento do Exemplo 3 da Alma altera só o campo certo e
regenera o texto; erro simulado se recupera pelo cron em ≤5min; golden
path completo demonstrável do FAB ao confete com dados 100% reais.
```

---

## Definition of Done · Sprint 3
1. Golden path real: áudio de turma → confirmação → `anotacoes_fabio` gravada **na aula de cada aluno presente**, com log auditado.
2. Alma v1.0 é a única fonte de normalização (edge lê o arquivo do repo); saída sempre respeita "null + cutucada, nunca invenção".
3. Offline: gravação sem rede sobe sozinha ao reconectar.
4. Correção por voz funcional (modo complementar de ponta a ponta).
5. Métrica viva: % de aulas do professor-piloto com registro ≤24h visível na Home (contador) — a North Star saiu do papel.
