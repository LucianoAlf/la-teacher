# Auditoria read-only — LA Teacher × Health Score V3 × presença

_2026-07-22 · Claude Code (LA Teacher) → Codex/Alfredo/Alf · resposta ao handoff `LA-performance-report/docs/auditorias/2026-07-22-handoff-health-score-v3-la-teacher-fabio-presenca.md`_

**Método:** código `la-teacher@main` + introspecção do banco vivo (`pg_get_functiondef`/`pg_get_viewdef`/grants/agregados). **Zero DDL/DML** — nada foi alterado. Evidências citadas inline.

---

## Veredito: **ADERENTE COM RESSALVAS**

O LA Teacher está aderente à arquitetura exigida: **só fala com o banco via RPC `app_*`** (leitura direta de tabela é banida no cliente), não chama a RPC V3, não recebe financeiro, identidade nunca vem do cliente. A ressalva central inverte o handoff: **o "gap crítico" do §10 está desatualizado — o `DO NOTHING` não existe mais em produção** (promoção desde 17/07, migration 009). As ressalvas reais estão em outro lugar: a view semântica **não conhece `fabio_audio`** (com prazo: áudio real volta ~3/ago), a Ficha do Aluno lê bruto, e hoje existem **duas réguas de interpretação** que precisam convergir.

---

## 1. Mapa arquivo/linha do LA Teacher

| O quê | Onde |
|---|---|
| Carteira | `src/lib/api.ts:115` → RPC `app_minha_carteira` → tela `src/pages/app/Alunos.tsx` |
| Agenda | `src/lib/api.ts:103` → RPC `app_minha_agenda_sessao`; reagrupamento no cliente `src/features/agenda/sessao.ts:43` (`agruparSessoes`); consumidores `useSessoes.ts:25`, `useSemana.ts:23`, `pendencias.ts:21,34` |
| Registro de chamada | `src/lib/api.ts:330-344` (`registrarPresencas` → RPC `app_registrar_presencas_aula`) ← UI `src/features/chamada/Chamada.tsx:242`; sessão da aula `useSessaoDaAula.ts:44` |
| Âncora de turma | `src/lib/api.ts:71-75` (`aula_id_chamada` — individual com turma-irmã não tem porta de chamada; o servidor revalida e levanta `chamada_somente_na_aula_ancora`) |
| Erros/retry da chamada | `src/lib/api.ts:306-323` (`ERROS_CHAMADA`, `chamada_ja_enviada`) — envio single-shot; **idempotência é do servidor** (curto-circuito quando roster completo já tem fonte forte) → retry de rede não duplica |
| Edição/correção | **não existe no app** pós-chamada completa (curto-circuito recusa; promoção recusa forte-sobre-forte). Correção = só `admin_corrigir_presenca` (fluxo coordenação, fora do app) |
| Ficha do aluno | `src/lib/api.ts:445` (`app_aluno_ficha`) + `percentual_presenca_contrato` `api.ts:95` → `src/pages/app/AlunoDetalhe.tsx` |
| Identidade | professor **nunca** sai do cliente — `fn_professor_do_usuario()` no servidor via `auth.uid()`; unidade nunca é escolhida; aula = `aula_emusys_id`; aluno = ids do roster |
| Leitura direta de tabelas | **nenhuma** — proibição documentada em `api.ts:6`; único `.from(` é Storage (`uploadAudio.ts:64`) |
| `alunos.percentual_presenca` legado | **não usado** (o campo da ficha é calculado na RPC — ver R3) |
| `get_health_score_*` | **zero referências no src** ✅ (e grant confirma: `authenticated=false` na RPC V3) |

## 2. Fluxo de escrita real em produção (introspecção 22/07)

- `app_registrar_presencas_aula` → `fn_registrar_presencas_core` (painel: chama_core=true, do_nothing=**false**, do_update=**true**). **Conflito "Emusys primeiro, professor depois": o professor VENCE** — o upsert de promoção grava status, `respondido_por='professor_la_teacher'` e `respondido_em=now()` sobre linha fraca (`null/emusys/sistema`), e **nunca** sobre outra fonte forte. Migration: `supabase/migrations/009-presenca-do-registro.sql:106-128`.
- **Sync nunca toca linha humana:** `upsert_presenca_emusys_bruta` (chamada pelo edge `sync-presenca-emusys/index.ts:1279` do LA Report) tem `WHERE respondido_por IS NULL OR IN ('emusys','sistema')` — o UPDATE inteiro é pulado em linha humana. Testes §12 #14/#15 do handoff **passam por construção**. Bônus: catraca anti-rebaixamento (presente do Emusys nunca vira ausente por sync posterior).
- **Evidência Emusys sobrevive à promoção:** a promoção não toca `emusys_presenca_bruta` nem `sincronizado_emusys_em` (comprovado: 1 linha humana carrega carimbo de sync = era Emusys e foi promovida). Perda residual: linhas pré-16/07 (antes da captura da bruta) perdem o status original ao promover — janela histórica pequena (P2c).
- `admin_corrigir_presenca`: gate interno `usuario_tem_permissao(usuario,'professores.editar',unidade)` + motivo ≥3 chars + **trilha em `aluno_presenca_retificacoes`** antes do update (vira `respondido_por='manual'`). Verificado com usuário real: professor do piloto (usuario 32) **não** passa no gate ✅.
- Empírico (30d): o sync grava **5.601 linhas no mesmo dia da aula** × 3.212 depois → a corrida sync-antes-do-professor é **comum**, não caso raro. A promoção não é luxo; é o que impede a perda diária da resposta humana.

## 3. Divergências encontradas (handoff × realidade)

- **D1 — §9.2/§10 desatualizados.** Prod não usa `DO NOTHING`; "a segunda chamada não reescreve a primeira" é impreciso: a segunda chamada **é aceita enquanto houver aluno sem fonte forte** (completar chamada parcial); só é recusada (`chamada_ja_enviada`) com roster completo forte. O que permanece impossível é **retificação pelo professor** (forte-sobre-forte) — e isso é decisão de negócio pendente (Q1), não bug.
- **D2 — semântica não conhece `fabio_audio`** (`sem_conhece_fabio_audio=false`; proveniências vivas em jul: `emusys`, `la_teacher`, `manual`). Quando o pipeline de áudio voltar a emitir (~3/ago), evidência humana cairia no balde errado — em CG, direto na fila de revisão operacional. **P1 com prazo.** (`professor_whatsapp` idem, sem volume ainda.)
- **D3 — duas réguas de interpretação convivem:** `fn_presenca_e_forte` (migration 012 — selo do app, `vw_presenca_pendencia` 013, RPC do Fábio 014) × `vw_aluno_presenca_semantica_v1` + `presenca_politicas_confiabilidade` (Codex). Hoje concordam em todos os casos existentes; divergirão no `fabio_audio`. Precisa de **uma matriz única de fontes** (§5).
- **D4 — Ficha do Aluno lê bruto** (`app_aluno_ficha`: le_aluno_presenca=true, le_semantica=false) → o professor vê falta-fantasma de CG como "falta". Migrar para a camada semântica (`falta_provavel`/`indeterminado` distintos de `falta_confirmada`).
- **D5 —** assinatura real da correção: `admin_corrigir_presenca(p_aluno_presenca_id uuid, p_status_presenca text, p_motivo text)` (difere do §9.3 no nome dos parâmetros; cosmético).
- ~~**D6 — retificações não guardam a autoria de origem**~~ **RETIRADO (22/07):** achado meu estava ERRADO — as colunas `respondido_por_anterior`/`respondido_em_anterior` existem e são preenchidas pelo trigger `completar_origem_retificacao_presenca`, que eu não vi na introspecção (li só o corpo da função, não os triggers da tabela). Correção do Codex, confirmada.
- **D7 — política × decisão do Alf:** `ausencia_emusys → falta_confirmada` em Barra/Recreio é confiança-por-unidade **para o KPI** (versionada, com CG em revisão). O Alf rejeitou confiança-por-unidade **para alerta** ("não posso confiar que estarão sempre 100%"). Não é contradição se ficar explícito que são planos diferentes — KPI versionado × alerta sempre-ligado (a fila da Sol/`vw_presenca_pendencia` cobra "chamada não lançada" em TODAS as unidades, sempre). Precisa de decisão formal (Q2).

## 4. Riscos

| Nível | Risco | Situação |
|---|---|---|
| **P0** | — | **nenhum aberto.** O P0 do handoff (perda da resposta humana) está consertado em prod desde 17/07; congelar em teste automatizado (T abaixo) |
| **P1a** | Semântica ignora `fabio_audio` — evidência humana mal classificada quando o áudio voltar | corrigir **antes de 3/ago** |
| **P1b** | Ficha do Aluno exibe bruto como resultado pedagógico | migrar leitura p/ semântica |
| **P1c** | Duas réguas de fonte sem matriz única | convergir (§5) |
| ~~P2a~~ | ~~retificações sem autoria de origem~~ — **RETIRADO** (já existia via trigger; ver D6) | — |
| **P2b** | `admin_corrigir_presenca` executável por `authenticated` | **seguro hoje** (gate interno verificado); recomendação: teste de permissão no CI ou restringir grant |
| **P2c** | Promoção sobre linha pré-16/07 perde status original do Emusys | janela histórica; aceitar e documentar |

## 5. Proposta de contrato de escrita e leitura

**Escrita (formalizar o que já existe — nada de segunda presença):**
1. Toda escrita via RPC: professor `app_registrar_presencas_aula` → core; Fábio `fabio_emitir_presenca_por_registro` → core; sync **só** `upsert_presenca_emusys_bruta`; correção **só** `admin_corrigir_presenca`.
2. Regra de conflito canônica (= estado atual, congelar em teste): **humana promove sobre automática; humana nunca sobre humana (exceto retificação auditada); sync nunca sobre humana; autoria e `respondido_em` reais sempre gravados.**
3. Aditivos: retificações += `respondido_por_anterior`/`respondido_em_anterior` (D6). Camada de submissão append-only completa: **opcional** — as garantias do §10 do handoff já estão atendidas sem tabela nova; se quiserem payload bruto por chamada, que seja log aditivo, sem entrar no caminho de leitura.

**Leitura (matriz única de fontes):**
4. `vw_aluno_presenca_semantica_v1` aprende `fabio_audio` (e `professor_whatsapp`) como **evidência humana confirmada** (mesmo tratamento de `la_teacher` — inclusive fora da fila de revisão de CG).
5. Fonte→classe vive em **um lugar só** (catálogo `presenca_fontes` ou a própria `fn`); `fn_presenca_e_forte` e a semântica derivam da mesma matriz. Papéis preservados: **pendência/selo = operacional** ("chamada lançada?"); **semântica = pedagógico** (resultado); Fábio/Sol/`vw_presenca_pendencia` (013/014) **inalterados**.

## 6. RPC `app_meu_health_score_v3` (desenho)

```sql
create or replace function public.app_meu_health_score_v3(
  p_competencia   date default date_trunc('month', now())::date,
  p_unidade_id    uuid default null,          -- null = todas as unidades com vínculo
  p_periodicidade text default 'mensal'
) returns jsonb
language plpgsql stable security definer set search_path to 'public';
-- corpo: v_prof := fn_professor_do_usuario(); null -> raise 'sem_professor_vinculado' (42501)
--   unidades := vínculos reais do professor; p_unidade_id não-nulo é validado contra elas (42501 se alheia)
--   para cada unidade: delega get_health_score_professor_v3_consumidor_pedagogico(...)
--   repassa estado_publicacao/score_exibivel/ranking_habilitado SEM transformar;
--   sem_base fica sem_base (nunca coalesce->0); payload V3 já não tem financeiro
-- grants: revoke public/anon; grant execute to authenticated
```

UI: bloco no **Perfil** (`src/pages/app/Perfil.tsx`) — score parcial rotulado "diagnóstico", `sem_base` literal, **sem ranking**; futuro: card na Home. Testes: multiunidade, usuário sem professor, unidade alheia, `sem_base ≠ 0`, anon bloqueado.

## 7. Plano de implementação (aditivo, nesta ordem — nada executado ainda)

| # | Entrega | Tipo |
|---|---|---|
| ~~M1~~ | ✅ **FEITO pelo Codex (22/07)** — migration `20260722153000_presenca_fontes_humanas_ficha_semantica.sql`: `fn_presenca_e_forte` virou a matriz única (mesma lista de fontes da 012) + semântica `v1.3` conhece `fabio_audio`/`professor_whatsapp`. Prazo de 3/ago atendido | — |
| ~~M2~~ | ~~Retificações += autoria de origem~~ — **RETIRADO** (já existia; ver D6) | — |
| ~~M3~~ | ~~`app_meu_health_score_v3` + grants~~ — **ADIADO** (decisão 22/07: HS não aparece no app do professor; futuro = app dos coordenadores, lado LA Report). Desenho do §6 fica arquivado pra quando for a hora | — |
| ~~R1~~ | ✅ **FEITO pelo Codex (22/07)** — `app_aluno_ficha.presenca_recente` agora vem da semântica: `data, horario, status(=estado_origem, compat), resultado_pedagogico, situacao_chamada, confianca, proveniencia, revisao_operacional_*, curso` | — |
| ~~F1~~ | ~~Bloco V3 no Perfil~~ — **ADIADO** (mesma decisão) | — |
| F2 | Ficha exibe `falta_provavel`/`indeterminado` sem ambiguidade | frontend |
| T | Congelar os 24 testes do §12 do handoff como suite SQL (harness `BEGIN/ROLLBACK`) — #14/#15 hoje passam por construção; #13 passa por curto-circuito | testes |
| — | UI da chamada com estados novos — **sem correção pelo professor** (decisão 22/07); correção segue exclusiva da coordenação via fluxo auditado | aguarda SPEC da presença |

## 8. Perguntas de negócio (decisão do Alf)

1. **Correção pelo professor:** hoje é impossível pelo app (só coordenação, via fluxo auditado). Professor deve poder retificar a própria chamada? Até quando (mesmo dia? 24h?) — e depois disso, só coordenação?
2. **Duas políticas explícitas:** confirmar que convivem — (a) KPI: `ausente` Emusys = `falta_confirmada` em B/R com CG em revisão (versionado, tabela de políticas); (b) alerta/governança: "chamada não lançada" cobrada **sempre, em todas as unidades** (fila da Sol nunca cala por confiança). É como está montado; falta o carimbo.
3. **Health Score no app:** libera já como "diagnóstico parcial" no Perfil do professor, ou espera o primeiro fechamento oficial de ciclo?
4. **Ficha do Aluno:** ok exibir a verdade semântica ao professor (falta *provável* ≠ falta confirmada), sabendo que em CG isso vai escancarar o buraco de registro?

## 9. Decisões do Alf (22/07) — as 4 perguntas fechadas

1. **Professor NÃO corrige a própria chamada.** Mantém como está: promoção recusa forte-sobre-forte; retificação é exclusiva da coordenação (`admin_corrigir_presenca`, auditada). A SPEC da presença não inclui "editar chamada" no app do professor.
2. **Carimbadas as duas políticas.** (a) KPI: `ausente` Emusys = `falta_confirmada` em Barra/Recreio, CG em revisão operacional (versionado em `presenca_politicas_confiabilidade`); (b) governança/alerta: "chamada não lançada" cobrada **sempre, em todas as unidades** (`vw_presenca_pendencia` → Sol/Fábio). Convivem oficialmente.
3. **Health Score NÃO entra no app do professor por enquanto.** Futuro: aplicativo dos **coordenadores** (lado LA Report). M3/F1 adiados; o desenho da `app_meu_health_score_v3` (§6) fica arquivado como referência.
4. **Princípio da ficha: "informação certa por professor, dentro do que já desenhamos."** Aplicação prática: R1/F2 seguem — a Ficha do Aluno migra pra camada semântica (falta **confirmada** ≠ falta **provável/não conferida**), que é o dado certo; em CG isso vai expor o buraco de registro, e é essa a verdade que a governança já ataca.

---

_Evidências: painéis de introspecção e agregados rodados em 22/07 no projeto `ouqwbbermlzqqvtqwlul` (SELECT-only). Handoffs irmãos: `docs/hugo/2026-07-18-...sol.md`, `docs/2026-07-18-fabio-...alfredo.md`, `docs/codex/2026-07-19-chamada-adm-la-report.md` — a ferramenta de chamada ADM (fase P3 do plano do Codex) segue de pé, rebaseada neste contrato._
