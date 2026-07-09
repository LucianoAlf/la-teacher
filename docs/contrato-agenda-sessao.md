# Contrato: Agenda por Sessão (v3) · `app_minha_agenda_sessao`
### Fonte de verdade da agenda do professor · 08/07/2026 · negociado entre app (Claude Code) e banco (Claude Web), aprovado pelo Alf

## Por quê

O Emusys representa a mesma aula real de formas redundantes: **1 aula tipo `turma`**
(explodida em 1 linha/aluno na presença) **+ 1 aula `individual` por aluno** no mesmo
horário (a "aula do aluno", com matrícula e `emusys_id` próprios). Mostrar cru = 15
linhas para 6 aulas (UX nota 1/10). Além disso, `turma_nome` (ex.: `C_Ter_15`) é
**rótulo de sala/horário reusado** — não delimita a turma pedagógica.

## O modelo

- **1 sessão = 1 aula real.** Turma agrupada pela **aula tipo `turma`** (não pelo rótulo),
  com alunos nomeados; individuais avulsas viram sessões próprias.
- **`aula_id_ancora`** = a aula da sessão → o áudio da gravação é enfileirado nela
  (`app_enfileirar_audio`).
- **`aula_id_alvo`** (por aluno) = a aula individual DELE → **é nela que a fatia do
  Fábio grava** (`fabio_registros_aula.aula_id` da fatia). **NUNCA gravar fatia na
  âncora**: o `anotacoes_fabio` da aula de turma é um campo só para N alunos — texto
  de um vazaria para os outros (bug real do teste do P7).
- `tem_registro` considera `anotacoes_fabio` **OU** `anotacoes` (legado manual).
- `presenca` é a real (`aluno_presenca.status`). **"ausente" em aula futura = presença
  não lançada, NÃO "faltou"** (sync retroativo) — a UI distingue por `data_hora_fim`:
  passou + ausente → "faltou"; futura → neutro ("aguardando").

## Shape (array ordenado por hora; sem vínculo → `{erro:'sem_professor_vinculado'}`)

```json
{
  "hora": "15:00", "hora_fim": "15:50",
  "data_hora_inicio": "…", "data_hora_fim": "…",
  "curso": "Canto T", "turma_nome": "C_Ter_15",
  "tipo": "turma" | "individual",
  "aula_id_ancora": 202878,
  "n_alunos": 3, "n_registradas": 0,
  "alunos": [ { "aluno_id": 186, "nome": "Joanna…", "aula_id_alvo": 202885,
                "presenca": "presente" | "ausente", "tem_registro": false } ]
}
```

## Regras de UI (implementadas em `src/features/agenda/sessao.ts`)

- Turma: **"Canto · turma de 3 — Joanna, Luiza e Sofia"** · individual: nome da pessoa.
- `curso` amigável (sufixo técnico ` T` fora da tela); `turma_nome` não é destaque.
- Status por sessão: registrada (todos com registro) → **agora** (dentro de
  início–fim: badge Registrar + dot pulsante) → pendente (passou e há presente sem
  registro; parcial mostra "1 de 3") → futura. Sessão onde só faltantes ficaram sem
  registro **não** é pendência.
- Contador do dia conta **sessões** ("X de 6"), nunca linhas cruas.

## Encaminhamentos registrados

1. **P6/Hermes (motor):** o prompt do P6 em `prompts/sprint3.md` foi escrito ANTES
   deste contrato. Ao montar o contexto e criar fatias, o motor deve usar a MESMA
   regra: fatia do aluno → `aula_id_alvo` (individual), nunca a âncora. Atualizar no
   `fabio-backup`/dossiê antes de o Hermes processar de verdade.
2. **Caso-limite:** turma com **1 aluno** na presença não vira sessão de turma
   (regra `>1`); aparece pela individual paralela. Turma de 1 **sem** individual
   some da agenda — não ocorre na carteira-piloto; evolução futura (anotação por
   `aluno_presenca`).
3. Migração espelhada em `supabase/migrations/007-agenda-por-sessao.sql`
   (aplicada no banco como `la_teacher_008/008b/008c`). A RPC antiga
   `app_minha_agenda` (P3) foi **dropada na migração 008** (carteira fonte
   única) — estava órfã; o app usa somente a de sessão.
