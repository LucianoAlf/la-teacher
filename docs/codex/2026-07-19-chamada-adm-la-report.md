# Ferramenta de Chamada (ADM) no LA Report — handoff Codex

_2026-07-19 · Alf → Codex · **mesma fonte única do Fábio, da Sol e do LA Teacher**_

> **⚠️ STATUS (22/07):** este handoff segue **válido como produto** — é a fase **P3** do plano de presença do próprio Codex (LA Report/secretaria). Mas foi escrito ANTES da auditoria cruzada, e 3 âncoras técnicas serão rebaseadas na SPEC da presença:
> 1. a "régua única" `fn_presenca_e_forte` vira a **matriz única de fontes** (convergência com `vw_aluno_presenca_semantica_v1` + `presenca_politicas_confiabilidade` do Codex — auditoria §5);
> 2. os 4 estados daqui se mapeiam nos **estados semânticos** (`presente`, `falta_confirmada`, `falta_provavel`/não-marcado, `aula_justificada`);
> 3. justificar/corrigir dialoga com `aluno_presenca_retificacoes` + `admin_corrigir_presenca`, que **já existem**.
>
> O que **não muda**: as 3 RPCs que o LA Teacher fornece, os requisitos de UX, o piloto em CG e as proibições. **Não executar antes da SPEC aprovada.** Ver `docs/auditorias/2026-07-22-auditoria-read-only-la-teacher-presenca-hs-v3.md` (decisões do Alf no §9).

## TL;DR

Construir no LA Report a **tela de chamada em lote** pra secretaria/ADM das 3 unidades. Motivo: o Emusys não distingue *"aluno faltou"* de *"ninguém marcou"* (tudo vira `ausente` — o **fantasma**), não tem "marcar ausente" na UI (só "Marcar Presença Manual"; o resto é default) e **a API dele não aceita escrita de presença** (conferido em 19/07: só cancelar/reagendar/CRM). Estamos migrando a operação pro ecossistema LA — a chamada passa a nascer aqui.

Você **não** constrói banco: a fundação já existe (Fases 1–3 do LA Teacher) e o Alf/Claude Code fornece as RPCs. Você constrói a **UI/UX** — que precisa ser mais fácil que o Emusys, senão a equipe não adota.

## Por que agora (você já sente isso no Health Score)

- O pilar **"Presença dos alunos"** do teu Health Score v3 está `PROVISORIO` com *"cobertura semântica inferior a 95% do roster esperado"* — é o fantasma contaminando teu KPI.
- Cobertura real (aulas encerradas, últimos 45d, % com ≥1 presente marcado): **Campo Grande 31%** 🚩 · Barra 61% · Recreio 64%. Desde 1º/jun Recreio/Barra marcam quase 100%; CG não dá conta pelo volume — a ferramenta existe pra isso.
- Prova do fantasma na API (probe 19/07, ~985 linhas de aluno nas 3 unidades): `presenca` é binário `presente|ausente`; **zero** linhas "ausente com horário" — quem não é marcado cai como `ausente` igual a quem faltou de verdade.

## O modelo — 4 estados (e por que o banco já está pronto)

| Estado | Como vive na base compartilhada |
|---|---|
| ✅ Presente | linha em `aluno_presenca` com **fonte forte** e status presente |
| ❌ Falta (marcada de propósito) | linha com fonte forte e status falta |
| ⚪ Não-marcado (esquecido) | **derivado, não se armazena**: ausência de linha forte — é o que `vw_presenca_pendencia` calcula |
| 📝 Justificada | `aluno_presenca_administrativo` (já existe; a view expõe `justificada`) |

- **Régua única:** `public.fn_presenca_e_forte(respondido_por)` — forte = `professor_la_teacher`, `fabio_audio`, `manual`, `professor_whatsapp` (+ a fonte nova da ADM, ver contrato). Fraca = `emusys`/`sistema`/null. **Nunca reimplementar essa regra.**
- **Precedência (migration 009):** primeira fonte forte vence; forte nunca sobrescreve forte; forte promove sobre o default fraco do Emusys. É o *"vale o que vem primeiro"* do Alf — ADM marcando e professor gravando áudio não conflitam.
- **Badge de origem de graça:** `respondido_por` diz quem deu (secretaria, professor no app, áudio do Fábio, Emusys).
- **A grade JÁ está no banco:** `aulas_emusys` (aula/professor/horário/sala, inclui HOJE e futuro — a agenda do LA Teacher vive disso) + `aula_alunos_emusys` (roster). **Não construir agendamento agora** — a chamada nasce sobre a grade sincronizada; agendamento nativo é etapa posterior da migração.

## Contrato — quem faz o quê

**Claude Code (LA Teacher/DB) fornece, com review do Alfredo antes de aplicar:**

1. `adm_chamada_do_dia(p_unidade_id, p_data)` → jsonb: aulas do dia da unidade com roster e estado atual por aluno (`presente|falta|nao_marcado|justificada` + fonte + quem/quando marcou). Read-only.
2. `adm_registrar_chamada(p_aula_id, p_itens jsonb, p_marcado_por text)` → grava em lote (`p_itens = [{aluno_id, status: 'presente'|'falta'}]`) com fonte nova **`adm_la_report`**, respeitando a precedência 009. Retorna resumo (gravados/ignorados-por-já-ter-fonte-forte).
3. `adm_justificar_falta(p_aula_id, p_aluno_id, p_motivo, p_marcado_por)` → `aluno_presenca_administrativo`.
4. Migration acompanhante: incluir `adm_la_report` na `fn_presenca_e_forte` + coluna de auditoria `marcado_por` (nullable) em `aluno_presenca`.

Acesso: `service_role` (backend/edge do LA Report), padrão dos demais consumidores. Nomes/shapes finais a combinar — **manda teu shape ideal** como o Alfredo fez com a RPC do Fábio, que o contrato nasce do consumidor.

**Codex (LA Report) constrói a UI. Requisitos de produto (o "o quê"; o "como" é teu):**

- **Chamada em lote, mais rápida que o Emusys:** lista de aulas do dia por unidade → abre o roster → default inteligente + toque pra alternar presente/falta → salvar. Poucos toques pra fechar uma aula.
- **Justificar falta** com motivo, na mesma tela.
- **4 estados visíveis** com o badge da origem (secretaria/professor/áudio/Emusys). Extensível — o Alf já prevê outros estados no futuro.
- **Cobertura do dia à vista:** "X de Y aulas com chamada feita" por unidade — vira o placar das meninas e o teu KPI de cobertura sobe junto.
- **Respeitar o que já veio forte:** aluno com presença do professor/áudio aparece travado/informativo (a RPC também protege — defesa dupla).
- **Piloto em Campo Grande** (onde dói), depois as 3 unidades.

## O que NÃO fazer

- Não escrever direto em `aluno_presenca` — só via RPCs (a precedência mora nelas).
- Não recriar "o que é presença" — `fn_presenca_e_forte` é a régua única.
- Não criar view de pendência nova — `vw_presenca_pendencia` é a canônica (Sol, Fábio e coordenação bebem dela).
- Não escrever de volta no Emusys — a API não aceita (e a migração vai desligá-lo).

## O que ganha de graça quando entrar

- **Sol:** a fila "sem chamada" esvazia sozinha — zero mudança no lado dela.
- **Health Score:** cobertura semântica sobe, sai o `PROVISORIO` do pilar presença.
- **LA Teacher:** o selo honesto do professor passa a refletir a chamada da ADM também.
- **Fábio:** menos pendência pra cutucar professor.

## Referências (repo LA Teacher)

- Régua: `supabase/migrations/012-selo-honesto-presenca.sql` (`fn_presenca_e_forte`)
- Fila canônica: `supabase/migrations/013-vw-presenca-pendencia.sql`
- Precedência: `supabase/migrations/009-presenca-do-registro.sql`
- Docs gêmeos: `docs/hugo/2026-07-18-base-presenca-governanca-sol.md` · `docs/2026-07-18-fabio-governanca-presenca-professor-alfredo.md`
