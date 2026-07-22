# P3 — Contrato da Chamada ADM (LA Report) · SPEC curta

_2026-07-22 · Alf/Claude Code → **revisão: Alfredo** (SQL) + **shape-ack: Codex** (consumidor) · rebase do handoff `docs/codex/2026-07-19-chamada-adm-la-report.md` na camada semântica v1.3_

## Objetivo

Destravar a fase **P3** do plano de presença: a secretaria faz a chamada em lote no LA Report. O LA Teacher/DB entrega **3 RPCs** (draft em `supabase/migrations/015-chamada-adm-rpcs.sql`, **NÃO aplicada**); o Codex constrói a UI e pluga via `service_role`.

## Decisões deste contrato (a ratificar no review)

1. **Fonte nova: `adm_la_report`** — entra na matriz única `fn_presenca_e_forte` como evidência humana (secretaria fez chamada de verdade). Efeitos automáticos e DESEJADOS: sai da fila da Sol/Fábio (`vw_presenca_pendencia`), acende o selo do professor, e a semântica v1.3 classifica como confirmada (o `resultado_pedagogico` deriva da matriz).
2. **Janela da ADM: retroativa até 45 dias** (`data_aula >= current_date - 45`, aula encerrada). A ADM concilia backlog — não faz sentido a janela 15min/24h do professor. Alinhada à janela operacional da pendência.
3. **Precedência intocada (009):** promove só sobre fraca (`null/emusys/sistema`); **nunca** sobrescreve fonte humana (professor/áudio/manual) — "vale o que vem primeiro". Corrigir depois = só `admin_corrigir_presenca` (coordenação, auditada).
4. **Auditoria de autoria:** coluna nova `aluno_presenca.marcado_por` (text, null) = e-mail/identificador da ADM que marcou. Em `aluno_presenca_administrativo`, aditivos `motivo` + `marcado_por` (a tabela hoje não tem motivo — só `justificada/fonte`).
5. **Acesso: só `service_role`** (backend/edge do LA Report). Nada de `authenticated`/`anon`.
6. **Escrita nunca direta:** UI → RPC. A promoção mora na RPC (defesa dupla com a UI travando o que já veio forte).

## As 3 RPCs (shapes propostos — Codex ajusta se precisar)

### 1. `adm_chamada_do_dia(p_unidade_id uuid, p_data date) → jsonb` (read-only)

Grade do dia da unidade (aulas âncora, não canceladas) + roster + estado semântico por aluno:

```jsonc
{
  "unidade_id": "…", "data": "2026-07-22",
  "cobertura": { "aulas": 12, "com_chamada_completa": 4 },
  "aulas": [{
    "aula_id": 204140, "hora": "16:00", "curso_nome": "Bateria T", "turma_nome": "…",
    "professor_id": 14, "professor_nome": "Jordan …", "sala_nome": "…",
    "chamada_completa": false,
    "alunos": [{
      "aluno_id": 349, "nome": "Pedro …",
      "estado": "nao_marcado",              // presente | falta_confirmada | falta_provavel | nao_marcado | aula_justificada
      "proveniencia": null,                  // la_teacher | fabio_audio | manual | emusys | adm_la_report
      "marcado_por": null, "respondido_em": null,
      "editavel": true                       // false quando já há fonte humana (UI trava)
    }]
  }]
}
```

`nao_marcado` = aluno do roster **sem linha** na semântica (o gap que não se armazena). A leitura vem da `vw_aluno_presenca_semantica_v1` — **uma interpretação só** pra todo mundo.

### 2. `adm_registrar_chamada(p_aula_emusys_id int, p_itens jsonb, p_marcado_por text) → jsonb`

`p_itens = [{"aluno_id": 349, "status": "presente" | "falta"}]` (parcial permitido — só os enviados). Valida: aula existe/não cancelada/encerrada/janela 45d; âncora do slot; roster conciliado; itens ⊆ roster; `p_marcado_por` obrigatório. Upsert de **promoção** com `respondido_por='adm_la_report'`, `respondido_em=now()`, `marcado_por`. Retorna:

```jsonc
{ "aula_id": 204140, "gravados": 5, "promovidos_sobre_emusys": 3,
  "mantidos_fonte_forte": [{ "aluno_id": 16, "fonte": "professor_la_teacher" }] }
```

### 3. `adm_justificar_falta(p_aula_emusys_id int, p_aluno_id int, p_motivo text, p_marcado_por text) → jsonb`

Upsert em `aluno_presenca_administrativo` (`justificada=true, fonte='adm_la_report', motivo, marcado_por`). Semântica classifica como `aula_justificada` (fora do denominador).

## O que fica com o Codex (LA Report)

- **UI** (requisitos do handoff de 19/07 seguem valendo: lote rápido, badge de origem, placar de cobertura, travar o que veio forte, piloto CG).
- **1 ajuste na view dele:** branch `'adm_la_report'` no CASE de `proveniencia` da `vw_aluno_presenca_semantica_v1` (hoje fonte desconhecida cai em `'desconhecida'` — o `resultado_pedagogico` já sai certo pela matriz; o branch é rótulo).
- **Shape-ack:** confirmar/ajustar os JSONs acima antes de eu aplicar.

## Gates (ordem)

1. **Alfredo revisa** a migration 015 (draft já no repo) — regra de sempre: nada aplicado sem review.
2. **Codex dá o ack** nos shapes (ou manda o dele).
3. Eu aplico a 015 (com OK explícito do Alf), Codex aplica o branch da proveniência e constrói a UI.
4. Piloto Campo Grande.

## Perguntas mínimas de ratificação (respondem no review, não travam o draft)

- Janela retroativa de **45d** pra ADM — ok, ou outra?
- `marcado_por` = **e-mail** da ADM (vem do auth do LA Report) — ok?
- Justificar exige **motivo obrigatório** (≥3 chars, igual `admin_corrigir_presenca`) — ok?
