# Presença canônica entre Emusys, LA Report, LA Teacher e Fábio — plano de implementação

> **Para quem executar:** usar `superpowers:executing-plans`, trabalhar uma task por vez,
> e não pular o RED/fixture da branch Supabase. Este plano não autoriza produção por si só.

**Objetivo:** Fazer Emusys/presente, secretaria, professor no LA Teacher e professor no
WhatsApp convergirem para uma única decisão em `public.aluno_presenca`, sem transformar
ausência bruta em falta humana e sem ocultar conflitos.

**Arquitetura:** `public.aluno_presenca` permanece a única linha operacional por
`(aluno_id, aula_emusys_id)`. Uma trilha append-only de eventos registra a história; ela
não é uma segunda fonte de verdade nem fecha chamada. Há duas regras diferentes e ambas
devem ser usadas pelo consumidor correto:

| Pergunta do consumidor | Regra obrigatória |
|---|---|
| Houve decisão/evidência humana? | `fn_presenca_e_forte(respondido_por)` — sem alteração semântica |
| A chamada está operacionalmente resolvida? | `fn_presenca_fecha_chamada(status_presenca, respondido_por)` |

O resolvedor operacional só retorna `true` quando o status é `presente`, `falta` ou
`falta_justificada`, e a origem é humana forte ou é `emusys` com `presente`. Portanto,
humano + `NULL`, humano + `indeterminado`, Emusys ausente e origem desconhecida não
fecham chamada.

**Fatos já auditados (12/08/2026):** o banco compartilhado é
`ouqwbbermlzqqvtqwlul`; `app_minha_agenda_sessao`, `vw_presenca_pendencia`,
`app_registrar_presencas_aula`, `fabio_aulas_candidatas` e
`fabio_registrar_presencas_aula` ainda usam, ao menos em parte, a noção de fonte forte.
`upsert_presenca_emusys_bruta` hoje descarta a mudança Emusys `presente → ausente`.
`app_registrar_chamada_agenda(...indeterminado)` pode apagar a linha. Esses dois
comportamentos são defeitos a corrigir, não premissas a preservar.

## Limites, posse e segurança

| Repositório | Responsabilidade desta frente |
|---|---|
| `D:/la-teacher-worktrees/presenca-canonica` | migration canônica, ledger, resolvedor, gêmeos, Fábio, agenda do professor, checkpoint |
| `D:/2026/LA-performance-report/.worktrees/presenca-canonica` | RPC da chamada da secretaria, UX/badges, documentação da integração |
| VPS/Fábio | sem writer paralelo: consome somente a RPC endurecida deste banco |

- Não criar cópia por aplicativo nem dar `INSERT`/`UPDATE` direto de
  `aluno_presenca` a `anon`, `authenticated`, bridge ou LLM.
- Não escrever na API Emusys até que haja endpoint, autenticação e idempotência externos
  documentados. O trabalho atual é convergência no banco já compartilhado.
- Funções `SECURITY DEFINER` terão `search_path` fixo e grants explícitos; revogar `PUBLIC`
  explicitamente, porque `CREATE OR REPLACE` preserva privilégios.
- Não usar o runner que abre `BEGIN/ROLLBACK` em produção. Fixtures e DDL só entram em uma
  branch Supabase descartável, sem dados sintéticos em produção.

## Gate de ambiente obrigatório

Uma branch temporária de banco do projeto custa **US$ 0,01344/hora**. Só criar depois de
nova confirmação explícita do usuário para este custo. Ela nasce de `ouqwbbermlzqqvtqwlul`,
deve ficar `ACTIVE_HEALTHY` e ser excluída ao fim da evidência. Nunca reutilizar as branches
`diag-kpis-alunos-20260805`, `p01c-staging` ou
`professores-health-score-gates-20260806`.

### Task 1 — Congelar o ponto de partida e preparar ambientes isolados

**Files:**
- Modify: `D:/la-teacher-worktrees/presenca-canonica/RETOMADA.md`
- Create: `D:/2026/LA-performance-report/.worktrees/presenca-canonica`

- [ ] Confirmar o custo, criar `presenca-canonica-20260812`, aguardar
  `ACTIVE_HEALTHY` e anotar o `project_ref` efêmero no checkpoint.
- [ ] Em produção, somente leitura, registrar `schema_migrations` a partir de
  `20260811000000`, assinaturas/MD5/ACL de todas as funções abaixo e o schema real de
  `aluno_presenca` e das tabelas de ações do Fábio:

  ```sql
  select p.proname, pg_get_function_identity_arguments(p.oid) as args,
         md5(pg_get_functiondef(p.oid)) as definition_md5, p.proacl
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in (
      'app_minha_agenda_sessao', 'app_registrar_chamada_agenda',
      'app_registrar_presencas_aula', 'fabio_aulas_candidatas',
      'fabio_registrar_presencas_aula', 'fn_registrar_presencas_core',
      'fn_sincronizar_gemeos_presenca', 'upsert_presenca_emusys_bruta',
      'fn_presenca_e_forte'
    )
  order by p.proname;
  ```

- [ ] Verificar que a migration aplicada
  `20260812135033_fix_presence_json_null_confirmation` está no ancestral local. Checar
  migrations não commitadas nos worktrees principais antes de gerar qualquer timestamp.
- [ ] Criar o worktree do Report a partir de `origin/main`, sem aproveitar uma frente de
  áudio/WhatsApp concorrente:

  ```powershell
  git -C D:\2026\LA-performance-report fetch --prune origin
  git -C D:\2026\LA-performance-report worktree add -b codex/presenca-canonica-report D:\2026\LA-performance-report\.worktrees\presenca-canonica origin/main
  ```

- [ ] Atualizar `RETOMADA.md` somente com fatos medidos: refs, SHAs, hashes, schema,
  `project_ref` e status da branch. Não marcar migration/UI como pronta.

### Task 2 — Escrever a prova SQL vermelha antes da migration

**Files:**
- Create: migration e `.test.sql` geradas pelo CLI para a frente LA Teacher
- Create: migration e `.test.sql` geradas pelo CLI para a frente LA Report

- [ ] Gerar os nomes pelo CLI, sem inventar timestamp, e criar a fixture descartável na
  branch: unidade, professor, roster, aula de turma e individuais gêmeas no mesmo horário.
- [ ] A fixture deve fazer cada write em statement separado antes da asserção seguinte;
  nunca chamar RPC que escreve dentro de `WHERE`/subconsulta que leia snapshot anterior.
- [ ] Provar RED para a regra ainda ausente, com ao menos estes casos:

  1. humano + `NULL` e humano + `indeterminado` não fecham;
  2. Emusys `presente` fecha, Emusys `ausente`/`NULL` não;
  3. Emusys `presente → ausente` preserva a decisão anterior, atualiza a evidência bruta e
     abre conflito de revisão — nunca é descartado, nunca vira falta humana;
  4. decisão Secretaria, Teacher e Fábio promove evidência fraca sem apagar raw Emusys;
  5. espelho turma↔individual leva o vínculo da decisão e não pisa em humano; conflito de
     humanos é contado e auditado, não sobrescrito;
  6. `vw_presenca_pendencia`, `fabio_aulas_candidatas` e guards de “já enviado” tratam
     Emusys/presente como resolvido e Emusys/ausente como pendente;
  7. `indeterminado` em `app_registrar_chamada_agenda` não apaga linha nem raw Emusys;
  8. chamada Fábio sem ação pendente, nonce, telefone, shortlist, expiração ou idempotência
     válidos é recusada e gera evento de tentativa;
  9. cada mutação/espelho/conflito escreve exatamente um evento append-only; e
  10. `anon`/`authenticated` não executam helpers internos, enquanto apenas a porta Fábio
      continua executável por `service_role`.

- [ ] Rodar apenas na branch efêmera e registrar a falha de contrato, não uma falha de
  fixture/permissão. Corrigir a fixture até o vermelho demonstrar a regra ausente.

### Task 3 — Implementar contrato canônico, conflitos, ledger e Fábio

**Files:**
- Create: migration CLI-generated `presenca_canonica_resolvedor_conflitos` e par de testes
  em `D:/la-teacher-worktrees/presenca-canonica/supabase/migrations/`
- Modify: `src/lib/api.ts`, `src/features/agenda/sessao.ts`, `SessaoRow.tsx`
- Create: `src/features/agenda/origemPresenca.ts` e testes

- [ ] Criar `fn_presenca_fecha_chamada(text, text)` como função pura, imutável e com
  vocabulário fechado:

  ```sql
  select p_status_presenca in ('presente', 'falta', 'falta_justificada')
     and (
       public.fn_presenca_e_forte(p_respondido_por)
       or (p_respondido_por = 'emusys' and p_status_presenca = 'presente')
     )
  ```

  Não alterar `fn_presenca_e_forte` nem usar `respondido_por` sozinho em decisão
  operacional.

- [ ] Criar `aluno_presenca_eventos` como ledger append-only com a chave da linha canônica,
  tipo de evento, estado/origem antes e depois, raw Emusys antes/depois, instante, ator ou
  ação Fábio quando houver e referência da decisão de origem. Confirmar os tipos exatos a
  partir do snapshot da Task 1; ativar RLS e não conceder escrita direta a cliente. Helpers
  internos são as únicas inserções permitidas. O ledger não alimenta `pendência` nem o
  booleano de chamada.

- [ ] Estender a linha canônica somente com o mínimo para tornar conflitos consultáveis
  pela RPC: vínculo da decisão de origem no espelho, instante da última evidência Emusys e
  indicador/referência de conflito aberto. Ao receber `presente → ausente`,
  `upsert_presenca_emusys_bruta` deve gravar o raw e evento novo, manter a decisão resolvida
  já existente e abrir conflito. Uma correção humana explícita resolve o conflito e cria
  novo evento; duas decisões humanas incompatíveis não são escolhidas em silêncio.

- [ ] Recriar `fn_sincronizar_gemeos_presenca` e seu gatilho interno para propagar somente
  decisões que passam pelo resolvedor. O espelho deve transportar origem, referência da
  decisão, raw Emusys e instante; devolver ou registrar separadamente
  `sincronizados`, `mantidos_por_precedencia` e `conflitos_para_revisao`. O guard de
  profundidade evita recursão, mas não pode suprimir o evento de espelho.

- [ ] Aplicar a matriz de consumidores: trocar por `fn_presenca_fecha_chamada` a view
  `vw_presenca_pendencia`, `app_minha_agenda_sessao`, `fabio_aulas_candidatas` e os guards
  de idempotência/“já enviado” em `app_registrar_presencas_aula` e
  `fabio_registrar_presencas_aula`. Manter `fn_presenca_e_forte` onde a pergunta é autoria
  humana, auditoria humana ou métrica analítica.

- [ ] Endurecer o Fábio sobre o mecanismo de ações já existente: a RPC de registro recebe
  uma ação pendente de presença, valida `nonce` de uso único, professor resolvido pelo
  telefone, shortlist aula/aluno, expiração e chave idempotente, registra tentativa aceita
  ou recusada no ledger e só então chega em `fn_registrar_presencas_core` com origem
  `professor_whatsapp`. A assinatura final é decidida após o snapshot das tabelas/RPCs de
  ação; nunca acrescentar uma RPC que aceite IDs arbitrários do bridge.

- [ ] Fechar ACLs explicitamente após os `CREATE OR REPLACE`: revogar `PUBLIC`, `anon` e
  `authenticated` dos helpers de resolver, ledger e gêmeos; não conceder helper ao
  `service_role` se somente RPC interna precisa dele. Manter grants existentes apenas nas
  portas públicas autenticadas e na porta Fábio `service_role`; testar com
  `has_function_privilege`.

- [ ] Fazer `app_minha_agenda_sessao` devolver `tem_presenca_registrada` calculado pelo
  resolvedor, origem, data, raw Emusys, conflito aberto e a contagem relevante. O Teacher
  consome somente esses campos; rótulos puros devem cobrir Emusys, Secretaria, Teacher e
  WhatsApp, inclusive a mensagem de conflito sem fingir “falta confirmada”.

- [ ] Aplicar GREEN na branch e depois localmente: testes SQL, teste unitário novo,
  TypeScript e build. Registrar de forma separada qualquer falha preexistente de Vitest; não
  chamá-la de verde global.

### Task 4 — Corrigir a chamada da secretaria e o Report

**Files:**
- Create: migration CLI-generated `chamada_agenda_preserva_evidencia_emusys` e testes
  em `D:/2026/LA-performance-report/.worktrees/presenca-canonica/supabase/migrations/`
- Modify: componentes de `src/components/App/Agenda/Chamada/` encontrados no worktree
- Modify: `docs/CHAMADA-AGENDA.md`, `docs/REGRAS-DE-NEGOCIO.md`,
  `docs/MAPA-SISTEMA.md`, `docs/MAPA-INTEGRACAO-EMUSYS.md`

- [ ] Primeiro, extrair e testar funções puras de badge/ação. Emusys/presente retorna
  `manter`; Emusys/ausente retorna `pendente`; origem humana só retorna ação de revisão
  quando houver intenção explícita, não toggle implícito.
- [ ] Recriar `app_registrar_chamada_agenda(jsonb)` para que `indeterminado` nunca delete
  a linha. Para raw Emusys existente, ele restaura a evidência preservada ou marca estado
  operacional pendente conforme o contrato; para Emusys/presente ativo ele devolve
  `presenca_emusys_ativa` e não remove nada. Falta/justificada são correções humanas
  explícitas, preservam raw e geram evento/retificação. A função deve usar o mesmo
  resolvedor e abrir/resolver conflito quando aplicável.
- [ ] Mostrar badges exatos: **Emusys**, **Secretaria · LA Report**,
  **Professor · LA Teacher** e **Professor · WhatsApp/Fábio**. Emusys/presente é passivo
  (“Confirmado no Emusys”); falta e justificada são correções explicitamente nomeadas. Raw
  Emusys contraditório mostra “revisar divergência”, nunca substituição silenciosa.
- [ ] Rodar RED/GREEN da mudança, `npm ci`, comando de teste real descoberto pelo projeto e
  build. Commitar somente migration, testes, chamada e documentação do Report.

### Task 5 — Implementar formulário manual sem misturar dados individuais

**Files (a confirmar por descoberta após brainstorming):** agenda/registro do LA Teacher,
migration/RPC de rascunho e testes de estado/UX.

- [ ] Fazer uma mini-SPEC de implementação antes da tela, baseada no mockup aprovado: dois
  botões diretos na agenda (microfone e caderno), sem menu; caderno abre a ficha completa.
- [ ] Criar RPCs de criar/atualizar rascunho com chave `professor + aula + aluno`, versão de
  concorrência e RLS. A UI faz autosave com estado de conexão explícito, não confirma save
  offline; ao reconectar, compara versões e oferece resolver o conflito áudio/manual.
- [ ] Em turma, renderizar um cartão por aluno com ordem **repertório, atividades, objetivo,
  observações, dever de casa, progresso individual**. “Tronco” é opcional e não substitui os
  campos por aluno.
- [ ] Implementar os dois atalhos aprovados: copiar campo e duplicar ficha. Ambos só listam
  alunos do roster da mesma aula, exibem os campos a substituir, exigem confirmação se houver
  conteúdo e nunca copiam presença. Testar repertório/dever/progresso diferentes em alunos
  da mesma turma.
- [ ] Versionar a conversão rascunho→preview final e testar colisão áudio/manual, recuperação
  de rede e overwrite. Só então integrar ao núcleo de confirmação do registro de aula.

### Task 6 — Prova integrada, publicação em gates e checkpoint

**Files:** SPEC, `RETOMADA.md` e documentação de integração nos dois repos.

- [ ] Aplicar primeiro a migration do Teacher e depois a do Report na branch temporária;
  reexecutar as fixtures completas e conferir gêmeos, ledger, raw, conflito e ACLs depois de
  cada transição.
- [ ] Rodar Security e Performance Advisors. Provar, por consulta, que `anon` e
  `authenticated` não executam helpers, que a porta Fábio mantém `service_role` e que nenhum
  `SECURITY DEFINER` novo ficou em `PUBLIC` por omissão.
- [ ] Carregar interfaces autenticadas em 390×844 e 1400×900: Emusys/presente fechado,
  Emusys/ausente pendente, conflito aberto, correção humana com origem e formulário manual
  por aluno. HTTP 200 não é validação interativa.
- [ ] Publicar em gates: PR/merge do Teacher, migration Teacher, PR/merge do Report,
  migration Report, deploys e consulta de produção sem fixture. Parar a cada gate se houver
  migration concorrente ou divergência de hash.
- [ ] Atualizar `RETOMADA.md` com SHA, versions de migration, funções/ACL efetivas, links de
  evidência, conflito conhecido e próximo gate. Excluir a branch temporária somente após a
  prova e registrar a exclusão. Rollback é migration corretiva/feature flag; nunca apagar a
  trilha de presença.

## Critérios de aceite

1. Emusys/presente fecha Teacher e Report com badge Emusys; Emusys/ausente permanece
   pendência humana.
2. O mesmo conceito operacional é usado em sessão, fila, Fábio e guards, enquanto métricas
   humanas continuam em `fn_presenca_e_forte`.
3. Mudança Emusys `presente → ausente` e qualquer conflito humano são visíveis, auditados e
   não fabricam falta humana nem descartam evidência.
4. Espelhos carregam proveniência e devolvem contadores de sincronização, manutenção e
   conflito.
5. Fábio só escreve dentro de ação WhatsApp válida, única e idempotente.
6. A trilha append-only registra cada evento relevante sem virar fonte operacional paralela.
7. O professor pode escolher áudio ou ficha manual, com rascunho, versão, recuperação de
   conexão e campos realmente individuais em turma.
