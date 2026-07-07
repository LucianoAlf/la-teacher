# Sync de grade futura (Emusys) — 07/07/2026

### Objetivo
Fazer o professor ver o **mês inteiro** de aulas na Home/Agenda, não só os próximos dias — sem depender de chamar a Emusys na hora que ele abre o app.

---

## O que foi feito

### 1. Edge function `sync-grade-futura-emusys`
Nova function, separada da `sync-presenca-emusys` (que já existia e cuida do passado). Busca `GET /aulas` da Emusys de **hoje até hoje+35 dias**, por unidade, e grava só a linha da aula em `aulas_emusys` (nunca presença, nunca `anotacoes_fabio`).

**Fronteira entre as duas funções (por que não colidem):**
- Mesma chave de upsert (`emusys_id, unidade_id`) → convergem na mesma linha, nunca duplicam.
- `sync-grade-futura`: dona de `data_aula >= hoje`. Só cancela fantasmas (aula remarcada/sumida) em `data_aula > hoje`, estrito — nunca mexe em hoje pra trás.
- `sync-presenca`: dona de hoje pra trás (aula + presença real), continua exatamente como estava.

**Problema achado e corrigido durante o teste:** a primeira versão fazia upsert linha-a-linha e estourava o tempo da edge function no volume de 1 mês (~130 aulas/dia × 3 unidades = milhares de linhas). Corrigido pra upsert em lote (blocos de 500) — depois disso, rodou o mês inteiro de Recreio em segundos.

### 2. Bug real encontrado na API da Emusys — reportado e corrigido pelo fornecedor
Aulas com `tipo=turma` vinham **sempre sem professor** no payload (`professores: []`), mesmo quando era uma turma de verdade com um professor fixo. Isso deixava ~44% da grade futura de Recreio "órfã" (sem dono, invisível pra qualquer professor na Home).

Investigamos a fundo antes de reportar: a maioria dos casos (97%) nem era problema real — era o Emusys mandando uma linha "turma" agregadora redundante ao lado das linhas "individual" (que já tinham professor). Só ~3% eram turma de grupo de verdade sem professor em lugar nenhum.

Reportamos pro suporte da Emusys. **Eles corrigiram no mesmo dia** — `/aulas` agora retorna o professor certo em `tipo=turma` também (confirmado ao vivo, batendo 100% com o que a gente já tinha deduzido via `alunos.professor_atual_id`). Depois da correção + re-sync de Recreio: taxa de "sem professor" caiu de 44% para 5,3% (o mesmo ruído residual que já existia em individual, por variação de nome no matching).

### 3. RPC `app_minha_agenda_mes` (migração 004)
`app_minha_agenda(p_data)` só pegava 1 dia — a tela de Agenda hoje monta a semana com 7 chamadas em paralelo (`useSemana.ts`), o que não escala pra 30-35 dias. A nova RPC devolve o intervalo inteiro numa chamada só, mesma view/gate de segurança (`vw_fabio_aulas_contexto` + `fn_professor_do_usuario()`), com um filtro que a RPC de dia não tinha: `cancelada = false` (passou a importar porque a grade futura grava aulas canceladas, coisa que a presença nunca fazia).

Testado com dados reais: Matheus (professor-piloto) → 25 aulas futuras corretas, 0 canceladas vazando.

### 4. Verificações de segurança feitas ao vivo (banco de produção)
- Confirmado que a `sync-grade-futura` nunca tocou presença nem anotação pedagógica (query no banco antes e depois).
- Confirmado que **movimentações reais** (evasão, matrícula) já acontecem em cima da grade futura — uma aluna evadiu hoje (12h50) e a Emusys já refletiu isso na hora (0 aulas futuras pra ela via `GET /aulas?pessoa_id=`). Nosso sync já pegou certo porque rodou depois — mas isso só por coincidência de horário, sem o cron ligado a grade fica desatualizada até rodar de novo manualmente.

---

## Estado atual

| Item | Status |
|---|---|
| Edge function `sync-grade-futura-emusys` | ✅ deployada (v2, upsert em lote) |
| Bug de professor em turma | ✅ corrigido pela Emusys, confirmado |
| RPC `app_minha_agenda_mes` (migração 004) | ✅ aplicada e testada |
| Grade futura de **Recreio** | ✅ sincronizada (2.170 aulas, 23 professores com dado pronto) |
| Grade futura de **Campo Grande / Barra** | ⬜ não rodada ainda |
| Cron automático (migração 003) | ⬜ escrita, **não aplicada** |
| Tela "meu mês" no app | ⬜ não existe — só semana/dia hoje |
| `.env` local + dev server | ✅ configurado, app rodando em `localhost:5173` |

## Achado relevante pra depois (não bloqueia nada agora)
A skill `emusys-api` revelou dois recursos que não sabíamos existir: filtro `pessoa_id` em `GET /aulas` (usado hoje pra confirmar a evasão em tempo real) e o endpoint `GET /matriculas`, que traz `disciplina.agendamentos[]` — pode ser um caminho mais direto pra "grade prevista" no futuro, sem depender de puxar milhares de aulas. Vale explorar depois.

## Próximos passos (em ordem)
1. **Ligar o cron** (aplicar migração 003) — importante não só por automação, mas porque é o que mantém a grade fiel a movimentações reais (evasão, remarcação) sem depender de rodar na mão.
2. **Rodar o sync em Campo Grande e Barra** — hoje só Recreio tem grade futura.
3. **Construir a tela "meu mês"** consumindo `app_minha_agenda_mes` — é o que fecha o objetivo original ("o professor ver o mês pra se planejar").
4. **Sprint 3 (motor de registro, migração 002):** quando for construído, vai precisar resolver "quais alunos estão numa turma" pra gravar comentário por aluno — o caminho já está validado (o payload da própria aula de turma já lista os `id_aluno`; hoje a sync só conta, não guarda a lista — vai precisar guardar quando chegar a hora).

## Arquivos deste commit
- `supabase/functions/sync-grade-futura-emusys/index.ts` (nova)
- `supabase/migrations/003-sync-grade-futura.sql` (cron — escrita, não aplicada ainda)
- `supabase/migrations/004-agenda-mes.sql` (RPC — aplicada)
