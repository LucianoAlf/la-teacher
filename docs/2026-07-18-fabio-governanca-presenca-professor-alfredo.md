# Governança de presença — lado professor (Fábio) · handoff Alfredo

_2026-07-18 · Alf → Alfredo · **espelho do doc do Hugo (Sol) — mesma fonte única**_

## TL;DR

O Fábio lê a **mesma** view `public.vw_presenca_pendencia`, só que **filtrada por professor**. É a MESMA fonte que a Sol usa no lado ADM → Fábio e Sol nunca divergem. Nada de reimplementar "o que é presença".

---

## O pulo do gato — não cobrar presença, cobrar CONTEÚDO

O professor **não precisa "dar presença"**. Ele grava o áudio / lança o conteúdo, e a presença sai **automática** (`fabio_audio`, Fase 1). Então:

> O Fábio cutuca o **conteúdo**; a **presença é consequência**. *"Grava o áudio que eu já dou a presença."*

Isso amarra as duas listas do professor:
- **Registro pendente** (aula sem prontuário) — o que o Fábio já usa hoje: `public.fabio_pendencias_professor(prof_id)` → `vw_registro_pendencia`.
- **Presença pendente** (aluno sem presença forte) — a nova fonte compartilhada: `public.vw_presenca_pendencia`.
- **Gravar o áudio resolve os DOIS** (cria o registro + emite `fabio_audio` → presença). Por isso o CTA é sempre "grava o conteúdo", nunca "marca presença".

## A regra (a mesma da Sol e do selo do app)

`public.fn_presenca_e_forte(respondido_por)`: **forte** = `professor_la_teacher` / `fabio_audio` / `manual` / `professor_whatsapp`; **fraca** = `emusys` / `sistema` / `null`.

## Queries (por professor)

**Dentro da janela (≤ 3 dias — o que o Fábio cutuca no professor):**
```sql
select data_aula, hora, curso_nome, aluno_primeiro_nome, dias_em_atraso
from public.vw_presenca_pendencia
where professor_id = :prof and not justificada and dias_em_atraso <= 3
order by data_aula desc, hora;
```

**Escala pra coordenação (> 3 dias — Fábio para, sobe pro grupo da coordenação):**
```sql
select professor_nome, count(distinct aluno_id) as alunos, max(dias_em_atraso) as atraso
from public.vw_presenca_pendencia
where professor_id = :prof and not justificada and dias_em_atraso > 3
group by professor_nome;
```

**Exemplo real (Matheus, prof 25, em 18/07):** 16/07 = **3 alunos (1 dia → dentro da janela, Fábio cutuca)**; backlog 29/06→13/07 = **5 a 19 dias → coordenação**.

## O fluxo (como o Alf desenhou)

1. **Fim do dia** — DM do Fábio: *"essas aulas ficaram sem lançamento; grava o áudio que eu já dou a presença."* (lista dentro da janela)
2. **Manhã seguinte** — lembrete + a relação do dia + a governança (alunos que ficaram sem presença/conteúdo).
3. **3 dias sem ação** — escala pra **coordenação** (mesma view, `dias_em_atraso > 3`). O Fábio **para de cutucar**; a bola vai pro grupo da coordenação (onde o Alf está) — a Sol/coordenação assume dali.

## Tom (obrigatório — `docs/contrato-de-alerta-v1.md`)

Fábio = **parceiro de sala, leve, sem cobrança policial**. O gatilho **F1** já está no catálogo do contrato ("aula sem registro há 24h → *me manda um áudio de 30s que eu resolvo 😉*"). A presença entra como **consequência** do registro, não como cobrança separada — mantém o Fábio "do lado do professor".

## Divisão de competência

- **Eu (LA Teacher/DB):** a view `vw_presenca_pendencia` + o selo honesto no app (feito). Backend-only (service_role).
- **Alfredo (Fábio/Hermes):** o Fábio lê a view filtrada por professor (service_role no VPS) → compõe o DM + a escala. Combina com o `fabio_pendencias_professor` (registro) que já existe.
- **Hugo (Sol):** a MESMA view, agregada por unidade → grupos das ADMs (ver `docs/hugo/2026-07-18-base-presenca-governanca-sol.md`).

## Referências

- View: `supabase/migrations/013-vw-presenca-pendencia.sql`
- Regra: `supabase/migrations/012-selo-honesto-presenca.sql` (`fn_presenca_e_forte`)
- Doc gêmeo (Sol/Hugo): `docs/hugo/2026-07-18-base-presenca-governanca-sol.md`
- Contrato de tom/SLA: `docs/contrato-de-alerta-v1.md`
- Estratégia/KPIs: `docs/presenca-estrategia-e-papeis.md`
- Acesso ao lado Fábio: SSH read-only já configurado (ponteiro na memória do projeto).
