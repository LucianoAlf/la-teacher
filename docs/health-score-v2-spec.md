# Health Score do Aluno v2 · Especificação Técnica
### LA Music · para Hugo (modelo) + Coordenação (Aluno 360) · 04/07/2026

## Princípio de arquitetura

> **Dois consumidores, um conjunto de sinais.** Os 14 critérios viram (a) **dimensões visíveis do Aluno 360** no Painel — diagnóstico que guia a conversa humana — e (b) **features do modelo preditivo** — que aprende os pesos com desfecho real. O número único de risco sai do modelo (`risco_evasao`); a régua manual **explica, não prevê** (lição da auditoria: o score heurístico atual apontava na direção errada — "Atenção" evadia mais que "Crítico").

Convenções: **[v1]** = já entra no modelo atual do Hugo · **[v2]** = feature nova · **[360]** = dimensão do painel · **Fase**: P = pronto no banco · T = nasce no LA Teacher · X = processo/integração a criar.

| # | Critério | Fonte confirmada (LA Report, salvo indicação) | Uso | Fase |
|---|---|---|---|---|
| 1 | 💬 Conversas ADM (WhatsApp) | `crm_conversas`/`crm_mensagens` + `agente_conversas` (Sol). Proxy inicial: nº de reclamações registradas, dias sem resposta do responsável | [v2] [360] | X (proxy fácil; sentimento = fase 2) |
| 2 | ❤️💛💚 Semáforo do Professor | `aluno_feedback_professor` (+ `aluno_feedback_sessoes`); histórico em `alunos_health_score_historico` | [v2] [360] | P (estrutura) / T (adoção: 1 toque no app + cutucada do Fábio — hoje 583 sem score) |
| 3 | ⭐ Pesquisa de satisfação (NPS) | NPS periódico da **Lia** (a criar; `pesquisa_evasao` é só de saída). Segmentar por unidade/professor/tempo de casa | [v2] [360] | X (régua da Lia) |
| 4 | 🎸 Pratica em casa | `fabio_registros_aula.campos->>'dever_casa'` + confirmação de execução (fluxo Fábio→responsável, Fase 2 do app) | [v2] [360] | T |
| 5 | 🗺️ Evolução na jornada | LA Journey (projeto `rkfszavfqplhorvfpkcq`) — ponte a definir; interino: `checkpoint_sugerido` aceito em `fabio_registros_aula` + `config_health_score_aluno.peso_fase_jornada` (intenção já existe) | [v2] [360] | X (ponte) / T (interino) |
| 6 | 📉 Absenteísmo (crônico) | `aluno_presenca` (44k, cobertura 94,1%, 100% respondida) — taxas 30/60/90d; separar falta-com-reposição × falta-seca (`aulas_emusys.tipo`) | **[v1]** [360] | P |
| 7 | 💰 Adimplência | `alunos.status_pagamento` + `movimentacoes_admin.situacao_pagamento`; futuro: API Emusys/Asaas. **Regra da Sol**: cobrança consulta `vw_risco_atual` antes de escalar | [v2] [360] | P (parcial) / X (integração fina) |
| 8 | 🎤 Participação em projetos | **Fonte a criar** — não existe tabela de projetos/banda/coral na auditoria. Interino: campo `conquista`/`observacao` dos registros do Fábio + eventos da Lia | [v2] [360] | X |
| 9 | ⏱️ Dias desde a última aula (agudo) | `aluno_presenca` (última presença=presente) — top-4 feature do modelo (ativos ~6d × evadidos ~34d) | **[v1]** [360] | P |
| 10 | 🎯 Anamnese × expectativa | `anamneses` (objetivos, generos, interesse_bandas) × jornada real; re-anamnese leve por checkpoint (Q6) | [v2] [360] | P (estrutura; adoção 10/1.561 → processo da **Sol**) / T (re-anamnese) |
| 11 | 🔄 Ciclo contratual + lealdade | `alunos` (tempo_permanencia_meses, numero_renovacoes) + `movimentacoes_admin` (renovacao_status, aviso_previo) + régua 30/15/7d da Lia | [v1 parcial] [v2] [360] | P |
| 12 | 🧾 Perfil da matrícula | `alunos` (tipo de matrícula/bolsa, valor_parcela nulo = "limbo") — evasão comprovada: bolsista parcial 26,1%, sem parcela 27,8% | [v2] [360] | P |
| 13 | 👨‍👩‍👧 Engajamento do responsável | `alunos` (responsável) + `anamneses` + leitura de relatório (Fase 3 do app: aberturas) + presença em eventos (Lia) | [v2] [360] | T/X |
| 14 | 🤖 Sinal contínuo do Fábio | `fabio_registros_aula` em série: `proximo_passo` repetido ≥N semanas (travado) · `observacao` genérica recorrente (silencioso) — métricas derivadas da Tese do Quintela | [v2] [360] | T |

## Notas de implementação (descobertas da auditoria — Fases 1–3)

1. **Join de desfecho do modelo v2**: usar `movimentacoes_admin` (motivo 39%, data de saída mais completa) — **não** `alunos.motivo_saida_id` (2/386). A âncora temporal da janela de 30 dias também melhora com `movimentacoes_admin.data`.
2. **Snapshot**: `risco_evasao` append-only (1 linha/aluno/dia) já criada na migração 001 — habilita tendência e prova de intervenção (H5+H6).
3. **Cortes por capacidade**: faixas `atencao`/`critico` configuráveis por unidade (curva precisão×recall do Hugo × capacidade semanal de Fabi/Jessica — pergunta Q8 aberta).
4. **Exposição**: professor **nunca** vê probabilidade — recebe fatores traduzidos no briefing do Fábio. Risco cru: só coordenação (RLS já aplicada na 001).
5. **Ordem de ativação sugerida**: v1 já roda com 6, 9, 11, 12 (tudo pronto) → T-features entram conforme o LA Teacher sobe (2, 4, 14) → X-features por último (1, 3, 5, 8, 13). O modelo melhora por camadas, sem esperar ninguém.

*Spec v1.0 — fundir com o rascunho de schema do Hugo antes do primeiro job em produção.*
