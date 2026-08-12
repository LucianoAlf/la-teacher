# Presença canônica entre Emusys, LA Report, LA Teacher e Fábio — plano de implementação

> **Para quem executar:** usar `superpowers:executing-plans`, trabalhar uma task por vez,
> e não criar branch Supabase nem fixture sintética em produção. As migrations desta frente
> são aplicadas diretamente no projeto principal após auditoria e revisão local.

**Objetivo:** Fazer Emusys/presente, secretaria, professor no LA Teacher e professor no
WhatsApp convergirem para uma única decisão em `public.aluno_presenca`, sem transformar
ausência bruta em falta humana e sem ocultar conflitos.

**Arquitetura:** `public.aluno_presenca` permanece a única linha operacional por
`(aluno_id, aula_emusys_id)`. A auditoria reutiliza `aluno_presenca_retificacoes` e
`fabio_acao_eventos`; uma estrutura nova só registra conflitos ainda abertos. Não será
criado um ledger universal de sync, e nenhuma trilha fecha chamada. Há duas regras diferentes
e ambas devem ser usadas pelo consumidor correto:

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
| `D:/la-teacher-worktrees/presenca-canonica` | agenda do professor, tipos, badges, testes de cliente e checkpoint |
| `D:/2026/LA-performance-report/.worktrees/presenca-canonica` | **única migration canônica** do banco compartilhado, RPCs, UX/badges da secretaria e documentação da integração |
| VPS/Fábio | sem writer paralelo: consome somente a RPC endurecida deste banco |

- Não criar cópia por aplicativo nem dar `INSERT`/`UPDATE` direto de
  `aluno_presenca` a `anon`, `authenticated`, bridge ou LLM.
- Não criar migrations concorrentes nos dois repositórios: o LA Report contém o
  histórico remoto mais recente (`20260812135824`) e é o dono desta migration
  compartilhada. O LA Teacher recebe somente a mudança de contrato e cliente.
- Não escrever na API Emusys até que haja endpoint, autenticação e idempotência externos
  documentados. O trabalho atual é convergência no banco já compartilhado.
- Funções `SECURITY DEFINER` terão `search_path` fixo e grants explícitos; revogar `PUBLIC`
  explicitamente, porque `CREATE OR REPLACE` preserva privilégios.
- Não usar o runner que abre `BEGIN/ROLLBACK` em produção. Não inserir fixtures sintéticas;
  a validação usa leitura do schema, provas puras, migração versionada e observação de
  registros reais existentes sem alterá-los fora do caminho oficial.

## Gate de ambiente obrigatório

O projeto Supabase principal `ouqwbbermlzqqvtqwlul` é o alvo autorizado. Não criar branch
Supabase, não pedir custo e não reutilizar nenhuma branch de banco existente. O isolamento é
somente de Git: este worktree do LA Teacher e um worktree separado do LA Report.

### Task 1 — Congelar o ponto de partida e preparar ambientes isolados

**Files:**
- Modify: `D:/la-teacher-worktrees/presenca-canonica/RETOMADA.md`
- Create: `D:/2026/LA-performance-report/.worktrees/presenca-canonica`

- [x] Em produção, somente leitura, registrar `schema_migrations` a partir de
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

- [x] Verificar que a migration aplicada
  `20260812135033_fix_presence_json_null_confirmation` está no ancestral local. Checar
  migrations não commitadas nos worktrees principais antes de gerar qualquer timestamp.
- [x] Criar o worktree do Report a partir de `origin/main`, sem aproveitar uma frente de
  áudio/WhatsApp concorrente:

  ```powershell
  git -C D:\2026\LA-performance-report fetch --prune origin
  git -C D:\2026\LA-performance-report worktree add -b codex/presenca-canonica-report D:\2026\LA-performance-report\.worktrees\presenca-canonica origin/main
  ```

- [x] Atualizar `RETOMADA.md` somente com fatos medidos: refs, SHAs, hashes, schema e
  status dos worktrees. Não marcar migration/UI como pronta.

### Task 2 — Escrever a prova de contrato antes da migration

**Files:**
- Create: uma migration e `.test.sql` geradas pelo CLI em
  `D:/2026/LA-performance-report/.worktrees/presenca-canonica/supabase/migrations/`
- Create: testes de cliente no LA Teacher somente para o contrato retornado pela RPC

- [ ] Gerar os nomes pelo CLI, sem inventar timestamp, e escrever primeiro os testes de
  contrato ao lado da migration. Eles usam funções puras, inspeção de definição/ACL e,
  quando houver evidência real já existente, somente `SELECT` sobre ela. Não criar fixture
  nem chamar writer de presença fora do fluxo real.
- [ ] A prova não pode chamar RPC que escreve dentro de `WHERE`/subconsulta que leia snapshot
  anterior. Para a mudança de estado, a prova mínima é a lógica SQL testável isoladamente e
  a inspeção de que a migration substituiu o ramo sticky correto.
- [ ] Cobrir, no código e nas consultas de contrato, ao menos estes casos:

  1. humano + `NULL` e humano + `indeterminado` não fecham;
  2. Emusys `presente` fecha, Emusys `ausente`/`NULL` não;
  3. Emusys `presente → ausente` é aplicado: sem decisão humana, reabre pendência; com
     decisão humana divergente, atualiza raw e abre conflito — nunca é descartado, nunca
     vira falta humana;
  4. decisão Secretaria, Teacher e Fábio promove evidência fraca sem apagar raw Emusys;
  5. espelho turma↔individual leva o vínculo da decisão e não pisa em humano; conflito de
     humanos é contado e auditado, não sobrescrito;
  6. `vw_presenca_pendencia`, `fabio_aulas_candidatas` e guards de “já enviado” tratam
     Emusys/presente como resolvido e Emusys/ausente como pendente;
  7. `indeterminado` em `app_registrar_chamada_agenda` não apaga linha nem raw Emusys;
  8. chamada Fábio fora da ação pendente existente, `wa_message_id`, shortlist ou expiração
     válidos é recusada pela máquina de ações; e
  9. retificações humanas, ações WhatsApp e conflitos usam trilhas específicas sem criar
     evento universal para cada sync; e
  10. `anon`/`authenticated` não executam helpers internos, enquanto apenas a porta Fábio
      continua executável por `service_role`.

- [ ] Rodar a prova local/readonly e registrar a ausência atual como baseline. Não usar o
  projeto principal para fabricar RED/fixture.

### Task 3 — Implementar contrato canônico, conflitos e Fábio

**Files:**
- Modify: `src/lib/api.ts`, `src/features/agenda/sessao.ts`, `SessaoRow.tsx`
- Create: `src/features/agenda/origemPresenca.ts` e testes

**Dependência:** a migration canônica desta task é gerada e versionada no
worktree do LA Report pela Task 2; não gerar arquivo SQL em `la-teacher`.

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

- [ ] Reutilizar `aluno_presenca_retificacoes` para correções humanas e
  `fabio_acao_eventos` para a conversa. Criar `aluno_presenca_conflitos` somente para
  divergência ainda aberta, com RLS sem grants diretos: chave canônica, snapshot da decisão
  e da evidência divergente, origem, instante, estado e resolução autorizada. Ela não
  alimenta pendência nem o booleano de chamada.

- [ ] Estender a linha canônica somente com o mínimo para tornar mudança Emusys e espelho
  consultáveis pela RPC: raw anterior/instante de mudança, `espelhado_de_presenca_id` e
  referência de conflito aberto. Ao receber `presente → ausente`,
  `upsert_presenca_emusys_bruta` atualiza o raw: se era automático, remove a decisão
  automática e reabre pendência; se existe decisão humana, mantém-na e abre conflito. Uma
  correção humana explícita resolve conflito; duas decisões humanas incompatíveis não são
  escolhidas em silêncio.

- [ ] Recriar `fn_sincronizar_gemeos_presenca` e seu gatilho interno para propagar somente
  decisões que passam pelo resolvedor. O espelho transporta origem e referência da decisão,
  mas não copia raw Emusys de uma aula para a outra; devolver ou registrar separadamente
  `sincronizados`, `mantidos_por_precedencia` e `conflitos_para_revisao`. O guard de
  profundidade evita recursão, mas não pode suprimir o evento de espelho.

- [ ] Aplicar a matriz de consumidores: trocar por `fn_presenca_fecha_chamada` a view
  `vw_presenca_pendencia`, `app_minha_agenda_sessao`, `fabio_aulas_candidatas` e os guards
  de idempotência/“já enviado” em `app_registrar_presencas_aula` e
  `fabio_registrar_presencas_aula`. Manter `fn_presenca_e_forte` onde a pergunta é autoria
  humana, auditoria humana ou métrica analítica.

- [ ] Endurecer o Fábio reaproveitando o mecanismo de ações existente:
  `fabio_acoes_pendentes` já contém ação, shortlist e expiração, e
  `fabio_acao_eventos.wa_message_id` já dá idempotência. A confirmação de chamada entra
  como transição dessa máquina, valida professor da ação e shortlist, e só então chega em
  `fn_registrar_presencas_core` com origem `professor_whatsapp`. Não criar nonce paralelo
  nem RPC que aceite IDs arbitrários do bridge. A resolução telefone→professor é auditada
  na borda bridge e deve ser verificada antes de alterar seu contrato.

- [ ] Fechar ACLs explicitamente após os `CREATE OR REPLACE`: revogar `PUBLIC`, `anon` e
  `authenticated` dos helpers de resolver, conflito e gêmeos; não conceder helper ao
  `service_role` se somente RPC interna precisa dele. Manter grants existentes apenas nas
  portas públicas autenticadas e na porta Fábio `service_role`; testar com
  `has_function_privilege`.

- [ ] Fazer `app_minha_agenda_sessao` devolver `tem_presenca_registrada` calculado pelo
  resolvedor, origem, data, raw Emusys, conflito aberto e a contagem relevante. O Teacher
  consome somente esses campos; rótulos puros devem cobrir Emusys, Secretaria, Teacher e
  WhatsApp, inclusive a mensagem de conflito sem fingir “falta confirmada”.

- [ ] Depois da revisão local e do diff da migration, aplicar no projeto principal pela
  ferramenta de migration e verificar sem fixture: schema, ACL, definição, explicação do
  plano e leituras de registros reais. Rodar também teste unitário novo,
  TypeScript e build. Registrar de forma separada qualquer falha preexistente de Vitest; não
  chamá-la de verde global.

### Task 4 — Corrigir a chamada da secretaria e o Report

**Files:**
- Modify: a migration canônica já gerada pela Task 2, se a revisão do contrato exigir a
  alteração de `app_registrar_chamada_agenda`
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

- [ ] Aplicar a única migration canônica do LA Report diretamente no projeto principal.
  Depois, conferir schema, funções, ACLs, conflitos e leituras de registros reais; nunca
  criar presença de teste.
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
  evidência, conflito conhecido e próximo gate. Rollback é migration corretiva/feature flag;
  nunca apagar a trilha de presença.

## Critérios de aceite

1. Emusys/presente fecha Teacher e Report com badge Emusys; Emusys/ausente permanece
   pendência humana.
2. O mesmo conceito operacional é usado em sessão, fila, Fábio e guards, enquanto métricas
   humanas continuam em `fn_presenca_e_forte`.
3. Mudança Emusys `presente → ausente` reabre pendência automática ou abre conflito apenas
   quando contradiz decisão humana; nunca fabrica falta nem descarta raw.
4. Espelhos carregam referência de proveniência, sem copiar raw entre aulas, e devolvem
   contadores de sincronização, manutenção e conflito.
5. Fábio só escreve pela ação WhatsApp existente, válida, única e idempotente.
6. Retificações humanas, ações WhatsApp e conflitos têm trilhas específicas, sem ledger
   universal ou fonte operacional paralela.
7. O professor pode escolher áudio ou ficha manual, com rascunho, versão, recuperação de
   conexão e campos realmente individuais em turma.
