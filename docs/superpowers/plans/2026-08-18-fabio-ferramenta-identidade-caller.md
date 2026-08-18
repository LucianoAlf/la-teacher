# Ferramenta com identidade do caller — plano

**Spec:** `docs/superpowers/specs/2026-08-18-fabio-ferramenta-identidade-caller-design.md`
**Goal:** o professor pergunta livremente sobre a própria vida letiva, e a
identidade vem de quem chama — nunca do modelo, nunca do texto.

## Constraints globais (valem em toda tarefa)

- **Nada vivo sem smoke + auditoria do Alfredo nos grants.**
- Token: nunca inteiro em log (só 8 chars do hash); nunca gravado cru.
- Nenhuma ferramenta aceita `professor_id`.
- Financeiro / outro professor / repasse / mensalidade / contrato: **não existe
  função**, não é regra de prompt.
- Teste SQL no harness `scripts/rodar-teste-sql.mjs` (BEGIN/ROLLBACK + resíduo).
- Verde só vale com **mutante morto por asserção**, baseline re-rodado por mim.
- Duas sessões, mesmo checkout: `ls supabase/migrations` no disco antes de
  numerar; `git add` nomeando arquivo por arquivo.

---

### Tarefa 1 — sessão do agente (tabela + cunhagem + resolução)

**Arquivos:** `supabase/migrations/<ts>_sessao_do_agente_por_token.sql` (+ `.test.sql`)

- `fabio_agente_sessoes`: `id`, `token_hash text not null unique`,
  `professor_id int not null`, `criado_em`, `expira_em`, `usos int`,
  `max_usos int`, `revogado_em`, `origem_mensagem_id uuid`.
- `fabio_agente_cunhar_sessao(p_professor_id, p_mensagem_id)` → devolve o token
  **cru uma única vez** e grava só o hash. `security definer`, service_role.
- `fabio_agente_resolver(p_token)` → `professor_id` ou erro. Valida hash, TTL,
  `usos < max_usos`, `revogado_em is null`; **incrementa `usos`**.

**Casos de teste:** token válido resolve; expirado recusa; revogado recusa;
estourou usos recusa; token inventado recusa; hash é o que está gravado (o cru
não aparece na tabela); dois professores não colidem.
**Mutantes:** tirar TTL; tirar limite de usos; tirar revogação; comparar cru em
vez de hash; não incrementar uso.

---

### Tarefa 2 — papel restrito + grants (⚠️ auditoria do Alfredo antes de vivo)

**Arquivos:** `supabase/migrations/<ts>_papel_do_fabio_professor.sql` (+ `.test.sql`)

- `create role fabio_professor_agente login` — **sem** `bypassrls`.
- `revoke all on all tables in schema public from fabio_professor_agente`
  e `alter default privileges` — o Supabase dá privilégio por padrão, e foi
  exatamente assim que a camada append-only quase nasceu frouxa (15/08).
- `grant execute` **só** nas RPCs da fatia 1.

**Casos de teste (o que o papel NÃO pode):** zero SELECT em tabela; `rolbypassrls`
false; não executa `fabio_professor_resumo_aulas` direto (só a versão por token);
não executa nada de financeiro; executa as duas RPCs da fatia.
**Mutantes:** conceder SELECT numa tabela; ligar bypassrls; conceder execute na
RPC crua.

---

### Tarefa 3 — as duas RPCs escopadas por token

**Arquivos:** `supabase/migrations/<ts>_ferramentas_letivas_por_token.sql` (+ `.test.sql`)

- `fabio_prof_aulas_periodo(p_token, p_inicio, p_fim)`
- `fabio_prof_presencas_periodo(p_token, p_inicio, p_fim)`
- Resolvem o token, delegam para as RPCs canônicas com o `professor_id` resolvido.
- Período sem sentido (fim < início, janela > 92 dias) → recusa estruturada.

**Casos de teste:** o número do Valdo (36 aulas, 25 CG / 11 Recreio) sai igual ao
da RPC canônica; token de outro professor devolve os dados DELE, nunca do
primeiro; token inválido recusa; nenhuma assinatura aceita `professor_id`.
**Mutantes:** ignorar o token e usar um id fixo; trocar a delegação por leitura
crua de tabela; aceitar janela infinita.

---

### Tarefa 4 — MCP próprio (`vps/fabio/fabio_professor_mcp.py`)

Só as duas ferramentas, conectando com o papel restrito. Descrições dizem ao
Fábio **o que ele NÃO consegue** (financeiro, outro professor), pra ele mandar
pro caminho certo em vez de improvisar.
**Teste:** nenhuma ferramenta expõe `professor_id` no schema; a lista de
ferramentas é exatamente 2.

---

### Tarefa 5 — bridge cunha e injeta

`_carregar_sessao_agente(row)` cunha o token do professor da LINHA e injeta como
handle opaco, com instrução de nunca exibir. Log com 8 chars do hash.
**Teste:** o token nunca aparece em log; canal app não cunha; falha ao cunhar
não derruba a resposta; o fio provado (a mensagem chega ao prompt com o handle).

---

### Tarefa 6 — allowlist do canal + MEDIR o que o agente enxerga

`platform_toolsets.api_server`: trocar `no_mcp` pelo nome do nosso MCP.
**Não confiar no config:** perguntar ao Fábio, pelo canal do professor, por
financeiro e por outro professor — e conferir na lista real de ferramentas que
o `lareport` não está lá.

---

### Tarefa 7 — falsificação fim a fim + rollout

Valdo 36 aulas pela ferramenta; financeiro recusado; outro professor impossível;
token expirado recusado. Só então decidir aposentar o bloco injetado.
