# Pro Alfredo — fechar o buraco da presença (Fábio ↔ presença ↔ governança)

_Mini-PRD / perguntas. Objetivo: presença **automática** a partir do registro do professor (áudio/app) + governança no WhatsApp (professor, ADM, coordenação). Regra: **informação canônica pra todos os agentes — nada redundante**._

## O que eu JÁ mapeei no banco (Supabase) — pra não recriarmos

- **Fila de registro (existe):** view `vw_registro_pendencia` → `fn_pendencias_do_professor` → consumida por `app_minhas_pendencias` (app) e `fabio_pendencias_professor` (Fábio). É "aula terminou, aluno não-ausente, **sem `anotacoes_fabio`**". Nível unidade: `fabio_pente_fino_unidade`.
- **Fila de notificação (existe):** tabela `fabio_notificacoes` (tipo/categoria, inclui `categoria=governanca`) + `fabio_claim_notificacao` + `fabio_marcar_notificacao_enviada/falhou` + `fn_fabio_pode_notificar` (respeita silêncio/preferências). Hoje só roda `briefing_matinal/informativa`.
- **Entrega em GRUPO de WhatsApp (existe):** `fila_relatorios_whatsapp` (jid do grupo, texto, agendada_para, status) + `whatsapp_destinatarios_relatorio` (jid por unidade/tipo).
- **Pipeline de áudio (existe):** `app_enfileirar_audio` → `fabio_fila_audios` → trigger `trg_fabio_fila_dispara` / `fn_fabio_chama_edge` → edge `fabio-registro-aula`.
- **Registro (existe):** `registrar_aula_fabio(aula, texto, ...)` grava `aulas_emusys.anotacoes_fabio` (com trava anti-sobrescrita). **⚠️ NÃO toca em `aluno_presenca`.**
- **Presença (existe):** `app_registrar_presencas_aula` (professor), `admin_corrigir_presenca` (coordenação), sync `upsert_presenca_emusys_bruta` (Emusys).
- **Conciliação da coordenação (existe):** `get_conciliacao_presencas` + `admin_revisar_presenca_conciliacao`.

## As LACUNAS confirmadas (o que falta ligar)

1. **Áudio → presença: NÃO existe.** O registro por áudio grava só o texto; ninguém marca presença dos alunos citados. É o "presença automática" que a gente quer.
2. **Não achei fila de "presença faltando"** (só a de registro). A cobrança hoje é de registro, não de presença.

## Perguntas pra você (o que eu NÃO enxergo — VPS/Hermes/agentes)

1. **Crons (Hermes/VPS):** quais rodam hoje? Especificamente — (a) o que lê `fabio_notificacoes` e envia; (b) o que lê `fila_relatorios_whatsapp` e posta nos grupos; (c) existe o de "alunos que faltaram ontem → grupo"? Cadência e onde rodam?
2. **Fábio no áudio (edge `fabio-registro-aula` / agente):** ao processar o áudio, ele **extrai quais alunos estiveram presentes/ausentes**? Se não, dá pra extrair com o que já temos? A ideia: ao registrar, **chamar também uma RPC de presença** com os alunos identificados. Isso deve nascer no **edge (você)** chamando uma **RPC canônica (eu)**? Confirma o desenho.
3. **Sol (assistente da ADM):** o que é, onde roda, o que lê/escreve, como posta no grupo das ADMs? Já existe ou é a construir?
4. **Grupos de WhatsApp:** os JIDs (grupo do professor / ADM / coordenação) ficam em `whatsapp_destinatarios_relatorio`? Como se roteia uma mensagem pra um grupo específico hoje?
5. **Onde a lógica nova deve viver:** minha premissa é **RPC canônica no Supabase** (emissão de presença + o sinal de "presença faltando"), e os **agentes/edge/crons CHAMAM**. Concorda? Tem algo já no VPS que eu deva **reusar** em vez de criar RPC?
6. **Fallback de correção:** se o Fábio não pegar um aluno no áudio, o professor corrige (app OU "a Ana veio" no zap). Como o WhatsApp captura essa correção hoje (tem um handler)?

## Próximo passo (meu, com as suas respostas)
Desenho a spec só do **delta**: (1) áudio/registro → **emitir presença** (RPC canônica), (2) **sinal de presença-faltando** pra governança (estendendo o que já existe), (3) a **tela do professor** no app (ver a própria fila + fechar num toque). Tudo reusando `vw_registro_pendencia`, `fabio_notificacoes` e `fila_relatorios_whatsapp`.
