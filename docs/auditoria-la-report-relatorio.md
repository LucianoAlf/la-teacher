# Auditoria do Banco LA Report — Fase 1 (Inventário)

**Projeto:** `ouqwbbermlzqqvtqwlul` · **Data:** 04/07/2026 · **Para:** Fábio (agente pedagógico) + LA Teacher (app do professor) + Painel da Coordenação
**Fonte:** export do SQL de inventário (2.015 objetos catalogados) · Fase 2 (qualidade de dados + corpo de funções) pendente de acesso vivo

---

## 1 · Sumário executivo

> **Veredito: o LA Report está muito mais pronto do que o mapa de produto supunha. A fundação do Fábio JÁ EXISTE no banco** — coluna própria, views de contexto, RPC de escrita e tabela de log. Anamnese, semáforo do aluno com histórico, pesquisa de evasão com áudio, mini-CRM (Farmer) e infraestrutura de agentes conversacionais também já existem. O trabalho de fundação encolhe de "criar 9 tabelas" para **4 criações reais + integrações**.

Números gerais: **227 tabelas** (245 mil linhas em `public`), **61 views**, **265 functions/RPCs**, **188 triggers**, **617 policies RLS**, **357 FKs**, **9 extensions**, **9 buckets**. RLS praticamente universal (só 3 tabelas sem, todas de sistema/governança). `pg_cron` + `pg_net` ativos (jobs internos), `pg_trgm` + `unaccent` (busca fuzzy — útil para normalização de nomes), `supabase_vault` para segredos.

---

## 2 · A fundação do Fábio que JÁ EXISTE 🤖

| Peça | Tipo | Contrato / detalhe |
|---|---|---|
| `aulas_emusys.anotacoes_fabio` | coluna `text` | Campo do Fábio **separado** do `anotacoes` original do Emusys — os dois textos convivem |
| `vw_fabio_aulas_contexto` | view | Contexto da aula: ids local/emusys, unidade (código+nome), data/hora… (base do briefing) |
| `vw_fabio_carteira_professor` | view | Carteira do professor por unidade (base de "meus alunos") |
| `get_fabio_aulas_do_professor` | RPC → jsonb | `(p_unidade_id, p_emusys_professor_id, p_data_aula=hoje)` — agenda do dia do professor |
| `registrar_aula_fabio` | RPC → jsonb | `(p_aula_id, p_texto, p_origem='audio', p_professor_id, p_modo='novo')` — **a escrita do Fábio** |
| `aula_registros_fabio_log` | tabela (0 linhas) | Log before/after: `texto_anterior`, `texto_novo`, `origem`, `modo` — auditoria pronta |

**Implicação:** o fluxo áudio → texto consolidado já tem porta de entrada e trilha de auditoria. O que **não** existe é o registro **estruturado** por Molde (campos JSONB, workflow de confirmação, fatiamento TURMA+fatia) — hoje o destino é texto.

---

## 3 · O que já existe, por camada

### 3.1 Núcleo acadêmico (espelho Emusys)
- **`alunos` (1.561)** — riquíssima: `motivo_saida_id`, `tipo_saida_id`, `canal_origem_id`, `data_saida` (os campos do estudo do Hugo **existem**; o problema é preenchimento), `percentual_presenca`, `health_score` + `health_score_numerico` + auditoria de atualização, `anamnese_preenchida`, `temperamento_codinome`, responsável (nome/tel/parentesco), `valor_parcela`/`valor_cheio`/descontos, `status_pagamento`, `emusys_student_id`, arquivamento estruturado.
- **`aulas_emusys` (34.885)** — data/hora, tipo, categoria, turma, curso, sala, professor, `cancelada`, `nr_da_aula` (contador de aulas!), `qtd_alunos`, `anotacoes`, `anotacoes_fabio`.
- **`aluno_presenca` (44.002)** — status + `respondido_por/em` + `mensagem_uazapi_id` + `token`: presença confirmada **via WhatsApp**, ligada a `aula_emusys_id`. É o combustível do modelo do Hugo.
- **Turmas:** `turmas`, `turmas_explicitas` (404), `vw_turmas_implicitas`, `turmas_historico` — modelo híbrido explícita/implícita. ⚠️ `turmas_alunos` **e** `alunos_turmas` coexistem (provável legado — confirmar qual é canônica).
- Lookups ricos: `motivos_saida` (com `categoria`, `conta_score_professor`, `eh_transferencia_interna`), `tipos_saida`, `cursos`, `curso_emusys_depara`, `unidades`.

### 3.2 Semáforo & Health Score do aluno 💚💛❤️
- **`aluno_feedback_professor`** — o "coraçãozinho": feedback por aluno × professor × competência (mês), com `sessao_id`.
- **`aluno_feedback_sessoes`** — sessão mensal por professor com `token`, `total_alunos`, `respondidos` (coleta via link/WhatsApp).
- **`alunos_health_score_historico`** — histórico com observação e professor. ✅ (exatamente o que o app precisa: histórico, não só estado)
- **`config_health_score_aluno`** — pesos por unidade: `peso_pagamento`, `peso_tempo_casa`, **`peso_fase_jornada`**, `peso_feedback_professor`, `peso_presenca` + limites saudável/atenção.
- RPCs: `calcular_health_score_aluno(p_aluno_id) → (score, status, detalhes jsonb)`, `calcular_health_score_alunos_batch`, `atualizar_health_score`, `atualizar_percentual_presenca`.
- **Implicação:** o semáforo é **calculado e configurável** — e já reserva peso para "fase da jornada". O modelo preditivo do Hugo entra como camada nova (`risco_evasao`), não substitui esta estrutura: convivem como combinado no mapa.

### 3.3 Anamnese 📋
- **`anamneses`** — profunda: `objetivos` (jsonb), `experiencia_anterior`, `generos_musicais`, `interesse_bandas`, **`diagnosticos` (jsonb)**, `necessidade_apoio`, `cuidado_medico`, `medicacao_continua` (núcleo de inclusão!), temperamento primário/secundário/codinome, `perfil_baby`, `tipo_formulario`, `share_token`, duração da entrevista.
- `anamnese_respostas_perfil` (respostas do teste de temperamento), RPCs `get_anamnese_by_token`/`get_anamnese_publica`/`vincular_anamnese_aluno` + trigger `trg_vincular_anamnese_na_matricula` e `trg_anamnese_atualiza_aluno`.
- **Implicação:** o PWA de anamnese grava aqui e o vínculo com o aluno é automático. O Fábio tem TUDO para o briefing (objetivos, gostos, cuidado) — inclusive o dado sensível, que exige **política de exposição** (ver §6).

### 3.4 Evasão & o "porquê" 🚪
- **`evasoes_v2` (740)** + 3 backups — data, tipo, motivo, professor, `situacao_pagamento`, snapshot de telefone.
- **`pesquisa_evasao`** — pipeline completo de entrevista de saída via WhatsApp: `resposta_texto`, **`resposta_audio_url`**, `categoria_resposta`, **`sentimento`**, com RPCs `criar_pesquisa_evasao`, `pode_enviar_pesquisa_evasao`, `stats_pesquisa_evasao`.
- Views: `vw_evasao_por_motivo/tipo`, `vw_evasoes_professores`, `vw_evasoes_resumo`.
- **Implicação:** o gap do "porquê" apontado pelo Hugo **não é estrutural — é de volume/processo**. A máquina existe; falta rodar em 100% dos offboardings (+ backfill 2025).

### 3.5 Farmer / Sucesso do Aluno (mini-CRM) 🌱
- `farmer_checklists` (+ items/templates, prioridade, prazo, **lembrete_whatsapp**, periodicidade), `farmer_tarefas` (com `aluno_id`, prazo, prioridade, `contexto`), **`farmer_recados`** (colaborador → professor/aluno com `enviado/entregue/lido_em` — **confirmação de leitura via WhatsApp pronta**), `farmer_rotinas` + execução, views de alertas (aniversariantes, inadimplentes, renovações próximas).
- **Implicação:** a "Fila de Casos" do Painel pode **estender** `farmer_tarefas`/`checklists` (adicionando SLA/desfecho) em vez de nascer do zero. E o Inbox com confirmação de leitura já tem backend (`farmer_recados`).

### 3.6 Infra de agentes & conversas 💬
- **`agentes` (1 registro)** — agente conversacional completo: `system_prompt`, `modelo`, `provider`, `tools` (jsonb), anti-spam, horário de funcionamento, modo teste.
- `agente_conversas` (sessões por telefone, `bot_ativo`, pausa por humano, `session_data`), `agente_fila_mensagens` (fila com debounce `processar_apos`).
- CRM paralelo: `crm_conversas`, `crm_mensagens(_agendadas)`, `conversa_estado_whatsapp`.
- **Implicação:** o chat espelhado do LA Teacher pode **registrar o Fábio como agente** nesta infra (multi-agente por design) em vez de criar tabelas novas de conversa.

### 3.7 Relatórios & KPIs (o Painel da Coordenação já tem motor) 📊
- **`relatorios_pedagogicos`** — relatório periódico por aluno **gerado por IA**: `periodo_tipo`, `conteudo_json`, `conteudo_editado`, `modelo_ia`, `status` + RPC `get_relatorio_pedagogico_aluno`.
- `relatorios_diarios` (snapshot diário de KPIs por unidade), `fila_relatorios_whatsapp` (fila com retry para grupos), RPCs `get_dados_relatorio_coordenacao/gerencial`.
- 30+ views de KPI prontas: `vw_kpis_professor_completo/mensal/historico/por_unidade`, `vw_ranking_professores_retencao/evasoes`, `vw_ltv_*`, `vw_funil_conversao_mensal`, `vw_dashboard_unidade`, `vw_alertas_inteligentes`, `vw_aluno_sucesso_lista/resumo`, `vw_metas_vs_realizado`, `vw_ranking_unidades`…
- Professor+LA: `professor_360_*` (avaliações, critérios, ocorrências), `professor_checkpoints` (competência + métricas + **insights_ia**), `professor_metas`, `professores_performance`, `metas_kpi`, `metas_professor_turma`.

### 3.8 Identidade & acesso 🔐
- **`usuarios`** com **`auth_user_id`** (Supabase Auth já vinculado!), `perfil`, `cargo`, `unidade_id` + `usuario_perfis` (multi-perfil por unidade) + `usuario_onboarding`.
- `professores` com `telefone_whatsapp`, `emusys_id`, `foto_url` — ⚠️ **sem vínculo direto com `usuarios`/auth** (professores hoje não logam). `colaboradores.usuario_id` existe (staff loga).
- `professores_unidades` (multi-unidade), `staff_unidade`.

### 3.9 Experimental (handoff da Mila)
- `lead_experimentais` (702) — lead, aluno, professor da experimental, curso de interesse, etapa do pipeline, `emusys_aula_id`. + `professores_experimentais`, `experimentais_professor_mensal`, `vw_performance_professor_experimental`, `motivos_nao_matricula`.

### 3.10 Buckets de Storage
`avatars`, `professor-videos`, `staff-fotos`, `crm-midia`, `whatsapp-media-campanhas`, `bi-uploads`, `inventario-fotos`, `lojinha-produtos`, `projeto-anexos`. ⚠️ **Não existe bucket de áudios de aula** — gap real.

---

## 4 · Gap Analysis — necessidade → o que existe → o que falta

| # | Necessidade (Fábio / LA Teacher / Painel) | Já existe | Falta de verdade |
|---|---|---|---|
| 1 | Agenda do professor | `aulas_emusys` + `get_fabio_aulas_do_professor` + `vw_fabio_aulas_contexto` | Nada estrutural — só consumir |
| 2 | Escrita do relatório (texto) | `registrar_aula_fabio` + `anotacoes_fabio` + log | Verificar corpo da RPC (Fase 2) |
| 3 | **Registro estruturado por Molde** (campos JSONB, status de confirmação, TURMA+fatias por aluno) | — (destino atual é texto) | ⭐ **Criar** `fabio_registros_aula` (workflow: rascunho→aguardando→confirmado→gravado) |
| 4 | **Áudio** (upload, fila offline, transcrição) | Padrão de fila existe (`fila_relatorios_whatsapp`, `agente_fila_mensagens`) | ⭐ **Criar** bucket `fabio-audios` + tabela `fabio_fila_audios` |
| 5 | **Risco preditivo** (modelo do Hugo) | Insumos prontos (`aluno_presenca`, `alunos`) | ⭐ **Criar** `risco_evasao` (snapshot diário: probabilidade, faixa, fatores) + job |
| 6 | Chat espelhado app⇄WhatsApp | `agentes` + `agente_conversas` + `agente_fila_mensagens` | Registrar o Fábio como agente; avaliar coluna `canal` |
| 7 | Semáforo do aluno | `aluno_feedback_professor` + sessões + histórico + config + RPCs | Só UI no app (1 toque) — zero banco |
| 8 | Anamnese no perfil + briefing | `anamneses` completa + vínculo automático | Política de exposição do dado sensível (view segura p/ professor) |
| 9 | Briefing pré-aula (revisitação) | Views fabio + `anotacoes(_fabio)` + anamnese + presença | Composição pelo agente (skill), não banco |
| 10 | Fila de Casos c/ SLA (Painel) | `farmer_tarefas`/`checklists` (prazo, prioridade, aluno, contexto) | Estender: `sla_em`, `desfecho`, `origem_alerta` (evita tabela nova) |
| 11 | Inbox professor c/ confirmação de leitura | `farmer_recados` (enviado/entregue/lido) | Expor no app; avaliar generalização p/ comunicados |
| 12 | Login do professor + RLS | `usuarios.auth_user_id` + `usuario_perfis` | ⭐ **Criar vínculo** `professores.usuario_id` (ou perfil professor) + policies do app |
| 13 | Jornada do aluno (checkpoint/marco) | `config_health_score_aluno.peso_fase_jornada` (intenção) | Ponte com projeto LA Journey (`rkfszavfqplhorvfpkcq`): cache local vs API — decidir |
| 14 | Contador "aula X de 40" | `aulas_emusys.nr_da_aula` + `alunos.numero_renovacoes` | Validar semântica do `nr_da_aula` (Fase 2) |
| 15 | Pesquisa de saída (o porquê) | Pipeline completo c/ áudio + sentimento | Processo (100% offboarding) + backfill 2025 |
| 16 | Relatórios periódicos por aluno | `relatorios_pedagogicos` (IA, JSONB, workflow) | Fábio vira o gerador; conectar aos registros de aula |
| 17 | Painel da Coordenação (KPIs) | 30+ views prontas + `relatorios_diarios` | Front desktop consome; pouquíssimo banco novo |

**Criações reais: 4** (itens 3, 4, 5, 12) **+ 2 extensões leves** (10, 11) **+ 1 decisão de arquitetura** (13).

---

## 5 · Plano de fundação revisado (substitui o "schema teacher" de 9 tabelas)

1. **`fabio_registros_aula`** — o coração: `aula_emusys_id` FK, `aluno_id` FK (null = tronco TURMA), `parent_id` (fatia→tronco), `molde` (A/B/C), `campos` JSONB (só o que foi dito), `status` (rascunho→aguardando_confirmacao→confirmado→gravado_emusys), `origem` (app/whatsapp), `audio_id` FK, `confirmado_em/por`, `checkpoint_sugerido` JSONB. Ao confirmar → chama `registrar_aula_fabio` (texto consolidado) + atualiza status.
2. **`fabio_fila_audios`** + bucket privado `fabio-audios` — `storage_path`, `status` (pendente→transcrevendo→normalizado→erro), `tentativas`, `transcricao`, `registro_id` FK.
3. **`risco_evasao`** — `aluno_id`, `probabilidade`, `faixa`, `fatores` JSONB, `modelo_versao`, `calculado_em` (append-only, 1 snapshot/dia) + job pg_cron/VPS.
4. **Vínculo de acesso** — `professores.usuario_id → usuarios.id` + policies RLS do app (professor enxerga só sua carteira via `vw_fabio_carteira_professor` como fonte de verdade).
5. **Extensões leves** — `farmer_tarefas`: + `sla_em`, `desfecho`, `origem_alerta`; `agentes`: registrar Fábio; `agente_conversas`: + `canal` (whatsapp/app) se necessário.

*Prefixo `fabio_` em `public` (padrão da casa, já iniciado por `aula_registros_fabio_log`) em vez de schema separado — decisão revista à luz do banco real: o LA Report já organiza por prefixo (`farmer_`, `crm_`, `professor_360_`, `agente_`).*

---

## 6 · Atenções e riscos encontrados

- **Dado sensível na `anamneses`** (`diagnosticos`, `medicacao_continua`, `cuidado_medico`): criar **view segura para o app do professor** que traduz em "sinal de cuidado" sem expor conteúdo clínico (guardrail do PRD). Acesso integral só coordenação.
- **Duplicações a sanear:** `turmas_alunos` × `alunos_turmas`; `evasoes_v2` + 3 backups na base quente; `alunos.health_score` (varchar) × `health_score_numerico`.
- **`professores` sem auth** — pré-requisito absoluto do app (item 12).
- **`audit_log` 75k / `cron.job_run_details` 234k** — housekeeping recomendado (retenção).
- **RLS onipresente** (617 policies): ótimo sinal; Fase 2 precisa mapear as policies das tabelas que o app consome para desenhar as do professor sem conflito.
- **Presença via token UAZAPI**: entender o fluxo atual antes de o app tocar em presença.

---

## 7 · Fase 2 — pendências (acesso vivo via MCP ou SQL v2)

1. Corpo de `registrar_aula_fabio`, `get_fabio_aulas_do_professor` e definição completa das 2 views fabio (contrato exato).
2. Qualidade de dados: % preenchimento de `alunos.data_saida/motivo_saida_id/canal_origem_id`, cobertura de `aluno_presenca` por unidade/professor, semântica de `nr_da_aula`.
3. Policies RLS das tabelas-núcleo (quem lê o quê hoje).
4. Conteúdo de `agentes` (o registro existente é a Sol? Mila?), `governanca.*` e RPCs `maria_*` (fronteiras entre agentes).
5. Amostra de `relatorios_pedagogicos.conteudo_json` (formato a herdar nos Moldes).

---

## 8 · Impacto no Mapa de Produto (→ v1.1)

- Arquitetura: "criar schema teacher" → **"integrar ao existente + 4 criações"** (§5).
- Sprints: S2 ganha o item "vínculo professor↔auth"; S3 usa `registrar_aula_fabio` como porta final de escrita; chat (S4) pluga na infra `agentes`.
- Painel da Coordenação: nasce sobre as 30+ views prontas + `farmer_*` estendido — esforço bem menor que o estimado.
- Perguntas ao Hugo atualizadas: H3 respondida (é tudo aqui no LA Report); **nova H8:** quem construiu as peças `fabio_*`/`registrar_aula_fabio` e qual o comportamento do `p_modo`; **nova H9:** onde roda o job que popularia `risco_evasao`.

*Auditoria Fase 1 concluída · Claude + Alf · Grupo LA Music*

---

# ADENDO · Fase 2 — Contratos, qualidade de dados e governança (04/07/2026)

## 9 · Contratos do Fábio (agora conhecidos por inteiro)

**`registrar_aula_fabio(p_aula_id, p_texto, p_origem='audio', p_professor_id, p_modo='novo')`** — qualidade profissional:
- Valida origem (`audio`/`texto`) e modo (`novo`/`substituir`/`complementar`); rejeita texto vazio.
- **Idempotente**: texto idêntico ao gravado → `status='sem_mudanca'`, não polui o log.
- `complementar` concatena com separador `--- (complemento) ---`.
- Grava **somente** em `anotacoes_fabio` (comentário no código: *"jamais em anotacoes"*) — separação Emusys × Fábio garantida por design.
- Trilha completa em `aula_registros_fabio_log` (before/after + origem + modo). `SECURITY DEFINER` com `search_path` fixado.
- **Implicação:** a skill de áudio e o app chamam esta RPC como porta única de escrita; o `p_modo='complementar'` já habilita o "corrigir por voz" da tela de Confirmação.

**`get_fabio_aulas_do_professor(p_unidade_id, p_emusys_professor_id, p_data_aula=hoje)`** → `{data_aula, total, aulas[]}` da `vw_fabio_aulas_contexto` — a agenda do dia pronta em uma chamada.

**`vw_fabio_aulas_contexto`** — completíssima: horários em BRT, turma/curso/sala, professor resolvido com `professor_match_fonte` (via `professores_unidades.emusys_id` com fallback), aluno via presença, `presenca_status`, `anotacoes` + `anotacoes_fabio`, e **`qualidade_contexto`** (autodiagnóstico: `professor_sem_vinculo_la` / `aula_sem_aluno_presenca` / `presenca_sem_aluno_la` / `ok`).

**`vw_fabio_carteira_professor`** — carteira ativa com contatos, responsável, curso, tipo de matrícula, dia/horário e diagnóstico de qualidade. ⚠️ **Expõe `valor_parcela`** — criar view derivada **sem campos financeiros** para o app do professor (guardrail: financeiro é domínio da Maria).

## 10 · Baseline da North Star 📊

> **Taxa de registro atual (90 dias): 45,9%** — 11.511 de 25.067 aulas com anotação. É o número que o Fábio nasce para transformar (meta: >90% em ≤24h).

Contexto adicional: 34.885 aulas espelhadas (mar–jul/2026) · **individual 20.068 (58%) × turma 14.802 (42%)** — turma no MVP validada com dado · `anotacoes_fabio` virgem (0) · `nr_da_aula` preenchido em 34.210 (0–307; semântica de contador cumulativo, confirmar com Emusys).

## 11 · Qualidade de dados — alertas 🚨

| # | Alerta | Evidência | Ação |
|---|---|---|---|
| 1 | **`evasoes_v2` é LEGADA** (confirmado por Alf 04/07) | Registros até 24/02/2026; fonte atual a confirmar — candidata forte: `movimentacoes_admin` (tipo_evasao, motivo, mes_saida, renovação, trancamento) | Fase 3: mapear dependências (views de evasão + `pesquisa_evasao` têm FK/leitura na legada → KPIs possivelmente congelados) e migrar para a canônica |
| 2 | **`is_ex_aluno` é flag morto** | 0 marcados em 1.561; a verdade está em `status` (ativo 1.175 · inativo 184 · evadido 179 · trancado 23) | Fase 3: medir `data_saida`/`motivo` filtrando por `status` (a medição da Fase 2 ficou cega por esse flag) |
| 3 | `canal_origem_id` quase vazio | 69/1.561 (4,4%) | Confirma o Hugo; captação no funil comercial (Mila) |
| 4 | `motivo_saida` incompleto | `evasoes_v2`: 241/740 (33%) — melhor que o "1/166" do estudo (Hugo olhou `alunos`; o dado real está em `evasoes_v2`), mas 67% vazio | Backfill planilhas 2025 + processo de offboarding |
| 5 | **Anamnese: adoção embrionária** | `anamnese_preenchida`: 10/1.561 | Estrutura pronta ≠ processo rodando; o briefing do Fábio vira motor de adoção |
| 6 | Semáforo desequilibrado | atenção 731 · **NULL 583** · crítico 241 · **saudável 6** (bate 100% com o slide do Hugo) | Recalibrar com o modelo preditivo; 37% sem score |
| 7 | `pesquisa_evasao` em piloto | 4 respondidas (3 com áudio) | Pipeline funciona; escalar para 100% dos offboardings |
| 8 | Presença bruta 66% | presente 29.131 × ausente 14.871 | Ler fino (inclui não-respondidos?) antes de virar KPI de tela |

## 12 · Governança de agentes — o padrão da casa é a Lia 🤖

- `governanca.agente_grupos`: a **Lia** opera em grupos WhatsApp com **modos** (`responder` no grupo "Sucesso do aluno"; `so_registrar` nos grupos de equipe por unidade), campos `gatilho`, `escopo`, `allow_any_participant`.
- `governanca.agente_usuarios`: ACL por telefone/nome/departamento/nível/unidade + `pode_editar` + `colaborador_id`.
- Tabela `agentes`: só um agente antigo inativo ("agente de volta às aulas", gpt-4o-mini) — **a infra `agente_conversas`/fila está livre para o Fábio**.
- **Implicação:** o Fábio entra na governança **no padrão Lia** (grupos de professores por unidade com modo próprio + ACL de professores em `agente_usuarios`), e registra-se em `agentes` para o chat espelhado.

## 13 · Identidade — confirmação do gap crítico 🔐

46 professores ativos · 52 com WhatsApp · **emusys_id via `professores_unidades`** (não em `professores`) · **0 professores com login** (usuários hoje: 16 perfil "unidade" + 11 admin, 27 com `auth_user_id`). O vínculo professor↔auth segue como criação obrigatória nº 1 do app.

## 14 · `relatorios_pedagogicos` — formato a herdar

5 rascunhos mensais; `conteudo_json` = `{visao_geral, instrumentos, pontos_atencao, proximos_passos, sem_dados}`. Os Moldes A/B/C alimentam essas chaves diretamente — o relatório periódico do Fábio nasce compatível com o que já existe.

## 15 · Fase 3 (mini) — pendências residuais

1. Medição corrigida por `status`: `data_saida`/`motivo_saida_id` de inativos+evadidos+trancados (o flag morto cegou a Fase 2).
2. Por que `evasoes_v2` parou em 24/02/2026 (pergunta operacional, não SQL).
3. Semântica exata de `nr_da_aula` (contador por turma? por matrícula?).
4. Leitura fina da presença 66% (metodologia do status `ausente`).

*Fase 2 concluída · o plano de fundação (§5) permanece válido — acrescida a view segura da carteira (sem financeiro) e a entrada do Fábio na `governanca` no padrão Lia.*

---

# ADENDO · Fase 3 — Cadeia da evasão fechada + residuais (04/07/2026)

## 16 · Veredito da evasão: crise cancelada, um bug real

- ✅ **`movimentacoes_admin` é a canônica confirmada e VIVA**: evasões contínuas em 2026 — jan 44 · fev 28 · mar 25 · abr 21 · mai 38 · **jun 50** · jul 22 (até dia 03). É o livro-razão de movimentações: `evasao(713)`, `renovacao(441)`, `nao_renovacao(193)`, `aviso_previo(112)`, `trancamento(66)`, com `tipo_evasao` granular (interrompido, não renovou, banda, 2º curso, transferência).
- ✅ **As 10 views de KPI já migraram** (evasões, retenção, performance, alertas, dashboard) — nenhum KPI congelado.
- 🐛 **Único dependente da legada: `maria_lareport_evasoes_mes_detalhe`** — a RPC da **Maria**. Desde março, qualquer resposta dela sobre evasões do mês vem da tabela morta (parada em 24/02). **Ação: refatorar a RPC para `movimentacoes_admin`** (1 function, baixo risco).
- ⚠️ **Dado de gestão no caminho:** junho foi o pico de evasões do ano (50) e julho abriu forte. Cruzar com o funil do modelo do Hugo (147 em risco) e a régua da Lia — pode ser sazonalidade de meio de ano, mas merece olhar humano já.

## 17 · Onde vive o "porquê" (correção de rota do backfill)

`alunos.motivo_saida_id` é deserto: **2 preenchidos em 386 ex-alunos** (o slide do Hugo olhou aqui). O motivo real vive em `movimentacoes_admin`: **334/853 com `motivo_saida_id` (39%) + 215 com texto livre**. Consequências: (a) backfill 2025 mira `movimentacoes_admin`; (b) o modelo v2 do Hugo faz join com ela — inclusive para a **data canônica de saída** (`alunos.data_saida` cobre só 54% dos evadidos; `movimentacoes_admin.data/mes_saida` é mais completa e afeta a âncora temporal da janela de 30 dias).

## 18 · Descoberta estrutural: o espelho de aulas é POR ALUNO

A série do `nr_da_aula` revelou: em turmas, `aulas_emusys` tem **uma linha por aluno na mesma data** (T_Ter_16 em 30/06: nr 132, 140, 17, 68, 16, 1…). Logo:

1. **`nr_da_aula` é contador individual do aluno** (máx. 307 = veterano de anos; 0 = sem contador). O "aula X" do app é viável **por aluno** — turmas são multi-nível por natureza.
2. **O motor de gravação em turma grava por aluno**: confirmar o tronco ⇒ para cada fatia, montar `tronco + fatia do aluno` e chamar `registrar_aula_fabio` na `aula_id` daquele aluno — exatamente a visão da Tese do Quintela (o responsável recebe "aula + bloco geral + fatia do filho"). **Ajuste marcado para o Sprint 3** (motor de registro); a migração 001 e o Sprint 2 não mudam.

## 19 · Presença: combustível aprovado

**Cobertura de 94,1%** das aulas (90d) com presença lançada, e **100% dos registros com respondido_em** (nada marcado no automático). A taxa de 66% de presença é real, não artefato — o modelo do Hugo está bem alimentado. `alunos_historico` fica como arquivo consolidado (categoria_saida preenchida; `data_saida` só nos registros recentes).

*Fase 3 concluída — auditoria encerrada. Pendência única remanescente: planilha operacional de evasões (Alf, segunda) para conferência do backfill.*
