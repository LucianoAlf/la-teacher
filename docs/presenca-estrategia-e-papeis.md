# Presença como sinal canônico — estratégia e divisão de trabalho

_2026-07-17 · Base de evidência: [auditoria-presenca-3-sistemas.md](auditoria-presenca-3-sistemas.md) (API Emusys ao vivo + relatório por aluno de CG)._

## Por que isso importa

Presença é um dos sinais mais preditivos de retenção que temos. Evidência (Campo Grande, dado do próprio Emusys):
- **Aluno ativo: 71% de presença × aluno que evadiu: 53%.**
- **Correlação presença × churn no nível professor: r = −0,64** (29 professores).
- O número de engajamento real (~66–71%) foi **cross-validado** por duas fontes independentes (API por aula + planilha por aluno, coorte ativa).

Mas o número está **contaminado**: no Emusys "não marcado" vira "ausente". Em CG, ~50% das aulas de julho não são registradas (equipe não dá conta — escola de >1000 m²), gerando **falta fantasma**. Isso envenena o sinal de evasão e tornaria **injusta** qualquer avaliação de professor.

## Os dois KPIs (separar o que hoje é um número só)

- **Taxa de REGISTRO** (operacional/ADM): das aulas que aconteceram, quantas foram marcadas. CG jul ≈ 50%; Recreio/Barra ≈ 85–95%. Alavanca: "zerar a fila".
- **Taxa de ENGAJAMENTO** (aluno/retenção): das aulas marcadas, quantos vieram. ~66–71% em todas as unidades. Meta mensurável (65% → 70–75%).

## Regra de ouro

Sem evidência = **desconhecida**, nunca falta. Distinguir também **latência** (semana corrente ainda sendo marcada) de **buraco assentado**. Não é folha (professor recebe por aluno ativo × 4 semanas), então aplicar é de baixo risco financeiro.

## Arquitetura: evidência multi-fonte → resolução

Livro-razão de evidências (append-only) alimentado por várias fontes, + função de resolução que calcula a verdade oficial por unidade. Fontes: **Emusys/ADM**, **professor** (áudio/app), **leitor facial** (aula aconteceu, objetivo), com confiança por fonte/unidade.

## Divisão de trabalho proposta

| Frente | Dono sugerido |
|---|---|
| **Captura pelo professor** (app: conferir/corrigir, experimental; a "fila" no app) | **LA Teacher** (Claude Code) |
| **Metodologia de presença** (modelo de evidência, regra de ouro, proxy do professor validado, os 2 KPIs) | **LA Teacher** especifica → **LA Report** implementa canônico |
| **Motor canônico** (livro-razão + resolução + retenção + qualidade-de-professor) e **dashboards ADM/gerente** (a fila que zera, visibilidade) | **LA Report** (web + codex) |
| **Canal WhatsApp** (áudio→presença, lembrete diário ao professor, lista de "sem presença ontem" no grupo das ADMs) | **Fábio** (Alfredo) |
| **Ingestão do facial** (LR Porte → evidência "aula aconteceu") | a definir (infra/dados) |

## Ordem recomendada

1. **Zerar a fila** (governança operacional: fila viva + cobrança multi-fonte) → registro ~100%.
2. Com registro alto, **engajamento vira número real** → metas.
3. **Regra de ouro** limpa a falta fantasma (corrente; passado só descontamina, não recupera presença perdida).
4. **Motor presença×retenção×professor** — só depois do dado limpo, controlado por curso/recência. Aí o r=−0,64 vira decisão justa de treinamento.
