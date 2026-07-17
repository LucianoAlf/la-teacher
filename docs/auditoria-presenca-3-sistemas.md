# Auditoria — Presença: Emusys ↔ LA Teacher ↔ LA Report

_Data: 2026-07-17 · Gatilho: problemas reportados pelo professor Matheus Felipe (prof 25)._

## O que o Matheus reportou

1. **Não conseguiu registrar a aula experimental** (Letícia, Canto, 16/07 17h).
2. **Presença errada e travada**: Anna Clara (Teclado turma, 16/07 18h) marcada "presente" sem ter ido, sem conseguir editar.

---

## Como os 3 sistemas escrevem presença (o que o código faz)

| Sistema | Como grava | `respondido_por` | Sobrescreve? |
|---|---|---|---|
| **Emusys** (SIS incumbente) | Edge `sync-presenca-emusys` (roda ~15/15 min + horários fixos) → RPC `upsert_presenca_emusys_bruta` | `emusys` | Só linhas `null`/`emusys`/`sistema` |
| **LA Teacher** (app do professor) | Chamada em lote → RPC `app_registrar_presencas_aula` (`on conflict do nothing`) | `professor_la_teacher` | Não sobrescreve nada |
| **LA Report** (coordenação) | Correção → RPC `admin_corrigir_presenca` (trilha em `aluno_presenca_retificacoes`) | `manual` | Sobrescreve (é a correção) |

### Precedência real (verificada no código)

`upsert_presenca_emusys_bruta` só faz `UPDATE` `WHERE respondido_por IS NULL OR respondido_por IN ('emusys','sistema')`.
→ **Hierarquia efetiva: `manual` > `professor_la_teacher` > `emusys`/`sistema` > `null`.**

**Boas notícias que isso garante:**
- Correção da coordenação (`manual`) é **protegida** — o sync do Emusys **não reverte**.
- Chamada do professor, uma vez gravada, é **respeitada** pelo sync.

---

## O problema real: uma corrida de inserção

Não há sobrescrita entre fontes de peso — **quem insere primeiro numa aula ganha a linha**.

- O Emusys sincroniza presença cedo (mesmo dia) e, como a secretaria é a fonte incumbente, **insere primeiro em ~99,9% dos casos**.
  - Últimos 60 dias: `emusys` = **20.524** registros × `professor_la_teacher` = **15** (só o piloto, 13–16/07).
- Quando o Emusys insere primeiro → o app vê "chamada já registrada" → tela **só-leitura** → **professor trancado** (não faz a chamada nem corrige).
- O professor só "ganha" nas aulas que o Emusys ainda não cobriu.

### Evidência (aulas do Matheus, 16/07)

| Aula | Origem | Quando | Resultado |
|---|---|---|---|
| Canto 15h (Gabriel) | `professor_la_teacher` | 17/07 16:59 | Chamada do app **funcionou** (Emusys não cobriu) |
| Canto 16h (Julia+Marina) | `emusys` | 16/07 23:51 | Professor trancado |
| Teclado 18h (Anna Clara+Braz) | `emusys` | 16/07 23:51 | Professor trancado; **Anna Clara presente sem ter ido** |

---

## Caso Anna Clara

- A presença "presente" veio do **Emusys** (23:51), não do Matheus. Ele **nunca teve chance** de marcar falta — a tela já estava travada quando ele abriu.
- Correção: `presente → falta` via `admin_corrigir_presenca` (grava `manual`, protegido do sync).
- Status: **pendente** — a escrita foi bloqueada pela trava de segurança do harness do Claude Code; precisa de regra de permissão ou execução manual do SQL.

## Caso Experimental (Letícia)

- Aula `categoria = 'experimental'`. A lead **não tem cadastro** em `alunos` (correto — é prospect); roster com `aluno_id = null`.
- A chamada **trava qualquer aula com aluno sem cadastro** → **experimental nunca registra pelo app**. Pior: o app **nem sabe** que é experimental (a RPC `app_minha_agenda_sessao` não expõe `categoria`), então mostra alerta vermelho de "sem cadastro conciliado" e cobra como pendência eterna.
- **3/3** das experimentais do Matheus em 45 dias caíram nisso.
- Já existe pipeline próprio de experimental (`lead_experimentais.status = experimental_realizada`, `emusys_experimentais_raw`, `professor_presenca` na aula) — a presença da experimental provavelmente **já é medida por fora da chamada**.

## Política de presença já vigente

`presenca_politicas_confiabilidade` (decidida por Alf em 15/07, v1): ausência no Emusys = `falta_confirmada`; unidade do Matheus (`2ec861f6`) exige revisão operacional. → **O Emusys já é tratado como fonte autoritativa** de presença — o que conflita com a ideia da chamada como ação primária do professor.

---

## A decisão de negócio central: quem é a fonte de verdade da presença?

- **A. Emusys manda (status quo de fato):** o app vira "conferir/contestar", não "fazer". Parar de cobrar chamada como pendência quando o Emusys já resolveu.
- **B. Professor manda:** o app é a fonte. O sync para de escrever presença nas aulas dos professores no app (ou dá precedência ao professor); a secretaria deixa de lançar essas.
- **C. Híbrido com janela:** o professor tem uma janela (ex.: até X h após a aula) pra lançar; depois o Emusys assume.

## Correções de UX (independentes da decisão acima)

1. **Experimental** — reconhecer `categoria='experimental'` e dar fluxo próprio (ou aviso honesto); sem alerta vermelho, sem pendência eterna.
2. **Lockout "já registrada"** — explicar o **porquê** (veio do Emusys) e oferecer caminho de contestação, em vez de beco sem saída.
3. **Default-present + envio num toque** — a confirmação deveria listar quem vai como presente, pra evitar envio errado.

---

# Verificação direta no Emusys (GET /aulas, jun+jul 2026, 3 unidades)

Fonte: API Emusys ao vivo (token por unidade). A API só expõe `presente`/`ausente` — **não existe "não registrada"**. Proxy de "aula foi registrada" = presença do **professor** na mesma aula (`professores[].presenca`). Validação: em NENHUMA unidade apareceu "professor ausente com aluno presente" (0 casos) — logo `professor ausente ≡ aula não registrada`.

## Registro × presença real

| Unidade | Jun registrado | Jun real | Jul registrado | Jul real |
|---|---|---|---|---|
| Campo Grande | 92,1% | 66,5% | **50,3%** | 69,1% |
| Recreio | 96,2% | 72,0% | 88,7% | 66,6% |
| Barra | 92,7% | 66,3% | 82,7% | 64,5% |

Julho por semana (não-registro): CG 30%→48%→63% (W27→W29); Recreio 2,9%→3,5%→22,8%; Barra 3,1%→4,2%→39,4%. A W29 é a semana corrente (latência de marcação).

## Conclusões

1. **Presença real ~65–72% em todas as unidades e meses** — os alunos não diferem por unidade. Engajamento real ~65% (meta 80–85%).
2. **Campo Grande quebrou o registro em julho** (92% jun → 50% jul; semanas assentadas 30–48% vs ~3% das outras). Processo de marcação, não comportamento de aluno.
3. **Latência de marcação** infla o não-registro da semana corrente em todas as unidades — leitura recente (~7–10 dias) é sempre incompleta.
4. **Falta fantasma:** só CG/julho ≈ 1.300 slots não registrados viram falta (COALESCE→ausente no sync); pela taxa real, ~800 estavam presentes. Envenena evasão e ponto.

## Implicações pra arquitetura (com evidência)

- **Regra de ouro:** sem evidência = **desconhecida**, nunca falta. Precisa distinguir também **latência** (desconhecida-recente pode virar presença) de **buraco assentado**.
- O proxy do professor (e o **leitor facial** de CG) é o que separa "aula aconteceu, aluno faltou" de "ninguém marcou".
- CG/julho é uma **quebra operacional** a resolver já (alguém parou de marcar) — a fonte professor (áudio/app) + facial fecham esse buraco com dado real.
