# Spec — Presença automática a partir do registro + sinal de presença pendente

_2026-07-17 · Aprovada por Alf + Alfredo. Base: [auditoria-presenca-3-sistemas.md](../../auditoria-presenca-3-sistemas.md), [prompt-alfredo-presenca-fabio.md](../../prompt-alfredo-presenca-fabio.md) (respostas do Alfredo)._

## Objetivo

Fechar o buraco da presença **sem criar nada redundante**: (1) a presença passa a **nascer automaticamente** da confirmação do registro do professor (áudio/app), e (2) surge um **sinal canônico de "presença pendente"** que alimenta a governança (professor no app + WhatsApp; ADM/coordenação no grupo). Regra-mãe: **informação canônica no Supabase; agentes/edge/crons apenas leem/chamam**.

## Não-objetivos (ficam pra depois)

- Health Score do aluno e o motor de retenção (presença×permanência×professor).
- Recálculo retroativo da "falta fantasma" (regra de ouro no histórico).
- Handler de correção por WhatsApp ("a Ana veio") e a agente Sol.
- Grupo de WhatsApp dedicado a professor (hoje não existe; professor usa app + `fabio_notificacoes`).

## Superfície canônica que REUSAMOS (não recriar)

- Fila de registro: `vw_registro_pendencia` → `fn_pendencias_do_professor` → `app_minhas_pendencias` / `fabio_pendencias_professor`.
- Notificação/governança: `fabio_notificacoes` (+ `categoria=governanca`), `fabio_claim_notificacao`, `fabio_marcar_notificacao_enviada/falhou`, `fn_fabio_pode_notificar`.
- Entrega em grupo: `fila_relatorios_whatsapp` → `processar-mensagens-agendadas` (pg_cron, 1/min) → `whatsapp_caixas` (função `sistema`) → UAZAPI; destinatários em `whatsapp_destinatarios_relatorio` (`relatorio_admin`, `relatorio_coordenacao`).
- Registro: `registrar_aula_fabio` (grava `anotacoes_fabio`); confirmação: `app_confirmar_registro` (já itera fatias e já lê `campos->>'presenca'`).
- Presença: `app_registrar_presencas_aula` (professor), `admin_corrigir_presenca` (coordenação), `upsert_presenca_emusys_bruta` (Emusys).
- Precedência já garantida pelo sync: só sobrescreve `respondido_por` em (`null`,`emusys`,`sistema`). Logo `professor_la_teacher`/`fabio_audio`/`manual` ficam protegidos.

## O delta

### 1. Banco (canônico) — minha parte

**1.1 Refatorar o núcleo da chamada (evitar regra duplicada).**
Extrair de `app_registrar_presencas_aula` uma função interna:

```
fn_registrar_presencas_core(
  p_aula_emusys_id integer,
  p_professor_id   integer,
  p_alunos_ausentes integer[],
  p_respondido_por text,          -- 'professor_la_teacher' | 'fabio_audio'
  p_estrito        boolean         -- true: valida janela/roster e RAISE; false: retorna status
) returns jsonb
```

Contém: resolução da âncora (turma-irmã), first-write-wins (`on conflict (aluno_id,aula_emusys_id) do nothing`), curto-circuito se já há presença respondida pela mesma fonte forte. `app_registrar_presencas_aula` passa a **chamar o core** com `p_respondido_por='professor_la_teacher'`, `p_estrito=true` (contrato externo inalterado).

**1.2 Emissão de presença a partir do registro.**

```
fabio_emitir_presenca_por_registro(p_registro_id uuid) returns jsonb
```

- Lê o tronco (`fabio_registros_aula` onde `id=p_registro_id`) e as fatias (`parent_id=p_registro_id`); no caso 1-aluno, o próprio tronco.
- Deriva **ausentes** = alunos cuja fatia tem `campos->>'presenca' = 'ausente'`; os demais do roster viram **presente**.
- Chama `fn_registrar_presencas_core(v_reg.aula_id, professor, ausentes, 'fabio_audio', p_estrito=false)` — a âncora é resolvida no core.
- **Não-fatal / idempotente:** first-write-wins não sobrescreve presença já respondida (professor/manual); reconfirmar não duplica. Retorna `{aula_id, presentes, ausentes, ja_havia, aplicado}`.

**1.3 Pendurar no gancho.**
No fim de `app_confirmar_registro` (após o loop de fatias), chamar `fabio_emitir_presenca_por_registro(p_registro_id)` dentro de bloco `EXCEPTION WHEN OTHERS` **não-fatal** (a confirmação do registro nunca falha por causa da presença) e anexar o resultado ao jsonb de retorno (`presenca: {...}`).

**1.4 Sinal de presença pendente.**

```
vw_presenca_pendencia_fabio
```

Critério (refina o do Alfredo pra funcionar apesar do sync do Emusys sempre gravar): aula **encerrada** (passou a janela operacional), **não cancelada**, **roster sincronizado** (aluno_id não-nulo), **professor conhecido**, e **sem presença CONFIRMADA** — i.e. nenhuma linha em `aluno_presenca` com `respondido_por in ('professor_la_teacher','fabio_audio','manual')` para aquela aula. (Linha só-`emusys` = ainda pendente de confirmação humana; é o caso de Campo Grande.) Expõe professor/unidade/aula/alunos/dias_em_atraso, no mesmo shape de `vw_registro_pendencia`.

Leitor pro app/Fábio (reusando o padrão de pendências, sem duplicar): estender `app_minhas_pendencias` com uma seção `presenca`, ou `fn_presenca_pendencia_do_professor(p_professor_id)`.

**1.5 (Opcional/fase 2) Gerador de governança.** Função que varre `vw_presenca_pendencia_fabio` e enfileira `fabio_notificacoes` (professor, `categoria=governanca`) + `fila_relatorios_whatsapp` (ADM/coord). Pode nascer no cron do Alfredo lendo a view diretamente.

### 2. Fábio / edge — parte do Alfredo (contrato)

- Ao estruturar as fatias, **preencher `campos.presenca`** por aluno (`'presente'`/`'ausente'`). É o único requisito novo do lado do edge; nada de escrever `aluno_presenca` direto.
- Shape esperado por fatia: `campos.presenca ∈ {'presente','ausente'}` (ausência de chave ⇒ tratado como `presente`, como o `coalesce` atual já faz).

### 3. App (LA Teacher) — minha parte

- **Confirmação já emite presença** (server-side, via 1.3) — o app só reflete o resultado (`presenca` no retorno).
- **Tela do professor:** consumir `app_minhas_pendencias` (seção presença) — mostrar as aulas com presença pendente e permitir **fechar a chamada em 1 toque** (chama `app_registrar_presencas_aula`). É a materialização do "conferir/fechar" (modelo Emusys-manda: sem beco, lista sempre editável).
- Wrapper em `src/lib/api.ts` pra a nova seção de pendências; `rpcSolta` enquanto db.ts não regenera.

### 4. Governança — reusa o existente (Alfredo/cron)

- **Professor:** `fabio_notificacoes` (`categoria=governanca`, respeitando `fn_fabio_pode_notificar`). Requer **destravar o worker** do modo `briefing_only` na VPS.
- **ADM/coordenação:** `fila_relatorios_whatsapp` + `whatsapp_destinatarios_relatorio` (`relatorio_admin`/`relatorio_coordenacao`).
- Fonte única de ambos: `vw_presenca_pendencia_fabio` (+ `vw_registro_pendencia` pra o registro). Nada de lógica nova de "quem está pendente" fora do banco.

## Modelo de dados / precedência

- Novo valor `respondido_por='fabio_audio'` — fonte forte (protegida do sync). Hierarquia: **manual > professor_la_teacher / fabio_audio > emusys/sistema > null**.
- **Sem novas tabelas.** Novos objetos: `fn_registrar_presencas_core`, `fabio_emitir_presenca_por_registro`, `vw_presenca_pendencia_fabio`, (opcional) `fn_presenca_pendencia_do_professor`.

## Verificação (como testar)

1. Registro com fatias marcando 1 aluno `presenca='ausente'` → `app_confirmar_registro` → conferir `aluno_presenca`: os presentes com `respondido_por='fabio_audio'`, o ausente como `falta`, e nada sobrescrito se já havia `manual`/`professor`.
2. Idempotência: reconfirmar não duplica nem altera.
3. Não-fatal: aula fora da janela/roster incompleto → registro confirma mesmo assim; `presenca.aplicado=false`.
4. `vw_presenca_pendencia_fabio`: uma aula CG só com linha `emusys` aparece como pendente; depois de `fabio_audio`/`professor`, some.
5. App: pendência aparece, fechar em 1 toque grava e some da fila.

## Dependências / questões abertas

- Alfredo: edge passa a preencher `campos.presenca`; destravar o worker de governança.
- Definir a **janela operacional** de "presença pendente" (ex.: pendente a partir de X h após o fim da aula; cobrável até Y dias).
- Confirmar `fn_aula_individual_do_aluno` / `fn_compor_texto_prontuario` (usados por `app_confirmar_registro`) seguem estáveis.

## Fases

1. **DB core + emissão + hook** (1.1–1.3) — presença passa a nascer do registro. _[maior valor, menor superfície]_
2. **Sinal de pendência + app** (1.4, 3) — professor vê e fecha.
3. **Governança WhatsApp** (1.5, 4) — Alfredo pluga cron nas views.
