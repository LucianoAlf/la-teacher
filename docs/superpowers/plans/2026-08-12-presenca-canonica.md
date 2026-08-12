# Presença canônica entre Emusys, LA Report, LA Teacher e Fábio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fazer Emusys/presente, secretaria, professor no LA Teacher e professor no WhatsApp convergirem para uma única decisão em `public.aluno_presenca`, sem transformar ausência bruta em falta humana.

**Architecture:** A regra nova é um resolvedor status-aware e não altera a régua histórica `fn_presenca_e_forte`. O LA Teacher é dono do resolvedor, da sincronização de gêmeos e da leitura do professor; o LA Report é dono da RPC e da UX da chamada da secretaria. Uma trigger interna cobre as duas origens que hoje não sincronizam os gêmeos (`emusys` positivo e `agenda_secretaria`), enquanto o núcleo já usado pelo professor e pelo Fábio continua seu único caminho de escrita.

**Tech Stack:** PostgreSQL/Supabase RPCs (`SECURITY DEFINER` com ACL explícita), Edge sync Emusys existente, React/TypeScript/Vite nos dois repositórios, Vitest e testes SQL em branch Supabase descartável.

---

## Limites e propriedade dos arquivos

| Repositório | Arquivos | Responsabilidade |
|---|---|---|
| `D:/la-teacher` | migration canônica, `app_minha_agenda_sessao`, `fn_sincronizar_gemeos_presenca`, tipos e agenda do professor | resolvedor, ACL, propagação de gêmeos, carimbo no Teacher e checkpoint vivo |
| `D:/2026/LA-performance-report` | migration da RPC `app_registrar_chamada_agenda`, componentes de Chamada e documentação de integração | impedir toggle destrutivo sobre Emusys/presente e exibir origem na operação da secretaria |
| VPS/Fábio | nenhum writer novo | continua chamando `fabio_registrar_presencas_aula`, já limitado a `service_role`, que chega em `fn_registrar_presencas_core` |

Não criar tabela de “fontes”, não copiar linhas entre aplicativos, não dar `INSERT`/`UPDATE` de `aluno_presenca` a `anon` ou `authenticated`, e não escrever de volta na API Emusys enquanto não houver endpoint externo documentado.

## Gate de ambiente obrigatório

O runner SQL existente faz DML dentro de `BEGIN/ROLLBACK` contra produção. Ele não será usado neste trabalho, porque o pedido proíbe dados sintéticos na produção. Antes de qualquer DDL ou teste de fixture, criar uma branch Supabase efêmera a partir de `ouqwbbermlzqqvtqwlul`, aplicar nela as migrations pendentes e excluí-la após a evidência. A criação custa **US$ 0,01344/hora** e requer confirmação explícita do usuário pela API do Supabase.

### Task 1: Preparar branch de banco e worktrees sem drift

**Files:**
- Modify: `D:/la-teacher-worktrees/presenca-canonica/RETOMADA.md`
- Create: `D:/2026/LA-performance-report/.worktrees/presenca-canonica` (git worktree, branch `codex/presenca-canonica-report`)

- [ ] **Step 1: Confirmar custo e criar a branch efêmera do Supabase**

  Use o `confirm_cost` retornado depois de apresentar o custo ao usuário:

  ```text
  organization: njrgwvvrtnflugavghdk
  project: ouqwbbermlzqqvtqwlul
  branch name: presenca-canonica-20260812
  ```

  Verificar que o status final é `ACTIVE_HEALTHY` e guardar o `project_ref` no checkpoint. Não usar as branches existentes `diag-kpis-alunos-20260805`, `p01c-staging` ou `professores-health-score-gates-20260806`, pois pertencem a outras frentes.

- [ ] **Step 2: Verificar migration history e hashes antes de escrever**

  Rodar em produção, somente leitura:

  ```sql
  select version, name
  from supabase_migrations.schema_migrations
  where version >= '20260811000000'
  order by version;

  select p.proname,
         pg_get_function_identity_arguments(p.oid) as args,
         md5(pg_get_functiondef(p.oid)) as definition_md5,
         p.proacl
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in (
      'app_minha_agenda_sessao', 'app_registrar_chamada_agenda',
      'app_registrar_presencas_aula', 'fabio_registrar_presencas_aula',
      'fn_registrar_presencas_core', 'fn_sincronizar_gemeos_presenca',
      'upsert_presenca_emusys_bruta', 'fn_presenca_e_forte'
    )
  order by p.proname;
  ```

  Esperado: a fonte local contém a migration aplicada `20260812135033_fix_presence_json_null_confirmation`; `fn_sincronizar_gemeos_presenca` ainda tem ACL pública e, portanto, é corrigida pela Task 3.

- [ ] **Step 3: Criar e checar o worktree do LA Report**

  Run:

  ```powershell
  git -C D:\2026\LA-performance-report fetch --prune origin
  git -C D:\2026\LA-performance-report worktree add -b codex/presenca-canonica-report D:\2026\LA-performance-report\.worktrees\presenca-canonica origin/main
  git -C D:\2026\LA-performance-report\.worktrees\presenca-canonica status --short --branch
  ```

  Expected: worktree limpo, baseado no mesmo `origin/main` conferido; nenhuma branch de WhatsApp/áudio é reutilizada.

- [ ] **Step 4: Atualizar o checkpoint com fatos, não intenção**

  Acrescentar em `RETOMADA.md` o `project_ref` efêmero, commit SHA remoto de cada repo e os hashes acima. Não marcar migration como aplicada nem UI como pronta nesta etapa.

### Task 2: Escrever o teste SQL vermelho do contrato canônico

**Files:**
- Create: the `.test.sql` paired with the CLI-generated `presenca_canonica_resolvedor_gemeos.sql` migration in `D:/la-teacher-worktrees/presenca-canonica/supabase/migrations/`
- Create: the `.test.sql` paired with the CLI-generated `chamada_agenda_preserva_emusys.sql` migration in `D:/2026/LA-performance-report/.worktrees/presenca-canonica/supabase/migrations/`

- [ ] **Step 1: Gerar os nomes de migration pelo CLI, sem inventar timestamp**

  Run em cada repositório:

  ```powershell
  supabase migration new presenca_canonica_resolvedor_gemeos
  supabase migration new chamada_agenda_preserva_emusys
  ```

  Renomear apenas os dois arquivos vazios gerados para o par `.sql`/`.test.sql`, preservando o timestamp emitido pelo CLI e mantendo a ordem: migration do LA Teacher antes da migration do LA Report.

- [ ] **Step 2: Escrever a fixture descartável e as expectativas antes da migration**

  A fixture deve criar uma unidade, professor, dois alunos, uma aula de turma e as individuais gêmeas no mesmo horário. Terminar com o resumo que o runner de teste da branch exige:

  ```sql
  select json_build_object(
    'falhas', (select count(*) from _presenca_resultados where not ok),
    'detalhe', coalesce(
      (select json_agg(json_build_object('passo', caso, 'obtido', detalhe))
         from _presenca_resultados where not ok),
      '[]'::json
    )
  ) as resumo;
  ```

  Casos mínimos do teste do LA Teacher:

  ```sql
  -- a origem sozinha não é suficiente: ausente do Emusys NÃO fecha.
  perform checar(
    'emusys ausente permanece pendente',
    not public.fn_presenca_fecha_chamada(null, 'emusys'),
    'esperava false'
  );

  -- presença positiva do Emusys fecha e é copiada para o gêmeo.
  perform public.upsert_presenca_emusys_bruta(
    v_aluno_id, v_turma_id, v_professor_id, v_unidade_id,
    v_inicio::date, (v_inicio at time zone 'America/Sao_Paulo')::time,
    'presente', v_tag || '_curso', v_tag || '_turma', null, now()
  );
  perform checar(
    'emusys presente fecha e espelha',
    public.fn_presenca_fecha_chamada('presente', 'emusys')
      and exists (select 1 from public.aluno_presenca
                  where aluno_id = v_aluno and aula_emusys_id = v_individual
                    and respondido_por = 'emusys' and status_presenca = 'presente'),
    'gêmeo Emusys presente ausente'
  );
  ```

  Acrescentar testes para `agenda_secretaria` em turma→individual, proteção de
  decisão humana já existente no gêmeo, ACL negativa de `fn_sincronizar_gemeos_presenca` para `anon` e `authenticated`, e a manutenção do acesso `service_role` somente à porta do Fábio.

- [ ] **Step 3: Rodar o teste no banco efêmero e comprovar RED**

  Run usando o `project_ref` efêmero, numa transação da branch e não em produção:

  ```text
  migration SQL atual + o teste gerado no Step 1 para `presenca_canonica_resolvedor_gemeos`
  ```

  Expected: falha por `fn_presenca_fecha_chamada` inexistente e por ausência de espelho `agenda_secretaria`/Emusys positivo. Se falhar por fixture ou permissão de setup, corrigir apenas a fixture até a falha representar a regra ausente.

### Task 3: Implementar o resolvedor, a sincronização e a leitura do LA Teacher

**Files:**
- Create: the CLI-generated `presenca_canonica_resolvedor_gemeos.sql` migration in `D:/la-teacher-worktrees/presenca-canonica/supabase/migrations/`
- Modify: `D:/la-teacher-worktrees/presenca-canonica/src/lib/api.ts:26-72`
- Modify: `D:/la-teacher-worktrees/presenca-canonica/src/features/agenda/sessao.ts:127-168`
- Modify: `D:/la-teacher-worktrees/presenca-canonica/src/features/agenda/SessaoRow.tsx:1-151`
- Create: `D:/la-teacher-worktrees/presenca-canonica/src/features/agenda/origemPresenca.ts`
- Create: `D:/la-teacher-worktrees/presenca-canonica/src/features/agenda/origemPresenca.test.ts`

- [ ] **Step 1: Implementar o resolvedor puro com vocabulário fechado**

  A migration define exatamente esta semântica, sem substituir
  `fn_presenca_e_forte`:

  ```sql
  create or replace function public.fn_presenca_fecha_chamada(
    p_status_presenca text,
    p_respondido_por text
  ) returns boolean
  language sql
  immutable
  parallel safe
  set search_path = pg_catalog, public
  as $$
    select public.fn_presenca_e_forte(p_respondido_por)
        or (p_respondido_por = 'emusys' and p_status_presenca = 'presente')
  $$;
  ```

  Recriar `fn_sincronizar_gemeos_presenca(integer)` para selecionar somente
  linhas que passam por essa função. A condição de conflito continua permitindo
  atualizar apenas `NULL`, `emusys` e `sistema`; nunca uma origem humana forte.

- [ ] **Step 2: Cobrir as duas portas que não passam pelo core**

  Criar uma função de trigger interna e um `AFTER INSERT OR UPDATE OF
  status_presenca, respondido_por` em `public.aluno_presenca`:

  ```sql
  if pg_trigger_depth() > 1 then
    return new;
  end if;

  if new.respondido_por in ('emusys', 'agenda_secretaria')
     and public.fn_presenca_fecha_chamada(new.status_presenca, new.respondido_por) then
    perform public.fn_sincronizar_gemeos_presenca(new.aula_emusys_id);
  end if;
  return new;
  ```

  Isso evita reescrever `upsert_presenca_emusys_bruta` e evita duplicar a
  chamada que `fn_registrar_presencas_core` já faz para Teacher/Fábio. O guard
  de profundidade impede recursão ao inserir o gêmeo.

- [ ] **Step 3: Fechar as ACLs de helpers internos**

  A migration precisa conter, após todas as definições:

  ```sql
  revoke all on function public.fn_sincronizar_gemeos_presenca(integer)
    from public, anon, authenticated, service_role;
  revoke all on function public.fn_propagar_gemeo_por_presenca()
    from public, anon, authenticated, service_role;
  revoke all on function public.fn_presenca_fecha_chamada(text, text)
    from public, anon, authenticated;
  grant execute on function public.fn_presenca_fecha_chamada(text, text)
    to service_role;
  ```

  `app_*` mantêm seus grants atuais; `fabio_registrar_presencas_aula` permanece
  apenas `service_role`. Consultar `has_function_privilege` nos testes para
  provar tanto a negação quanto o grant esperado.

- [ ] **Step 4: Mudar a RPC da agenda para devolver decisão e origem**

  No `jsonb_agg` de `app_minha_agenda_sessao`, trocar ambas as ocorrências de
  `fn_presenca_e_forte(ap.respondido_por)` por
  `fn_presenca_fecha_chamada(ap.status_presenca, ap.respondido_por)` e devolver:

  ```sql
  'presenca_origem', ap.respondido_por,
  'presenca_respondido_em', ap.respondido_em,
  'emusys_presenca_bruta', ap.emusys_presenca_bruta,
  'tem_presenca_registrada', ap.id is not null
    and public.fn_presenca_fecha_chamada(ap.status_presenca, ap.respondido_por)
  ```

  Não alterar o fallback visual de `presenca`; a ausência Emusys já vira
  `a_confirmar` porque sua `status_presenca` é nula.

- [ ] **Step 5: Escrever primeiro o teste unitário dos rótulos**

  `origemPresenca.test.ts` deve falhar antes do módulo existir:

  ```ts
  import { describe, expect, it } from 'vitest'
  import { rotuloOrigemPresenca } from './origemPresenca'

  describe('rotuloOrigemPresenca', () => {
    it('identifica presença positiva do Emusys sem dizer que foi o professor', () => {
      expect(rotuloOrigemPresenca('emusys', 'presente')).toEqual('Emusys')
    })

    it('nomeia a origem do professor e da secretaria', () => {
      expect(rotuloOrigemPresenca('professor_la_teacher', 'presente')).toEqual('Professor · LA Teacher')
      expect(rotuloOrigemPresenca('agenda_secretaria', 'falta')).toEqual('Secretaria · LA Report')
    })
  })
  ```

- [ ] **Step 6: Fazer o cliente consumir somente a decisão do banco**

  Adicionar em `AlunoSessao` os campos opcionais retornados pela RPC:

  ```ts
  presenca_origem?: string | null
  presenca_respondido_em?: string | null
  emusys_presenca_bruta?: 'presente' | 'ausente' | null
  ```

  Criar `rotuloOrigemPresenca` como função pura, usar o rótulo nos alunos da
  sessão e atualizar o comentário de `tem_presenca_registrada` para “decisão
  que fecha chamada”, nunca “fonte forte”. O `chamadaCompleta` continua lendo
  somente esse booleano devolvido pela RPC.

- [ ] **Step 7: Rodar GREEN e fazer commit focado**

  Run na branch efêmera: teste SQL completo. Run local:

  ```powershell
  node node_modules\vitest\vitest.mjs run src/features/agenda/origemPresenca.test.ts
  node node_modules\typescript\bin\tsc
  node node_modules\vite\bin\vite.js build
  ```

  Expected: teste novo verde; TypeScript e build verdes. Registrar o teste
  unitário legado com erro de sintaxe separadamente se ele ainda falhar, sem
  atribuí-lo a esta mudança. Commit somente migration, teste e arquivos
  Teacher desta tarefa.

### Task 4: Preservar Emusys/presente na chamada do LA Report

**Files:**
- Create: the CLI-generated `chamada_agenda_preserva_emusys.sql` migration in `D:/2026/LA-performance-report/.worktrees/presenca-canonica/supabase/migrations/`
- Modify: `D:/2026/LA-performance-report/.worktrees/presenca-canonica/src/components/App/Agenda/Chamada/chamadaUtils.ts`
- Modify: `D:/2026/LA-performance-report/.worktrees/presenca-canonica/src/components/App/Agenda/Chamada/ChamadaAlunoCard.tsx`
- Modify: `D:/2026/LA-performance-report/.worktrees/presenca-canonica/src/components/App/Agenda/Chamada/ChamadaDrawer.tsx`
- Modify: `D:/2026/LA-performance-report/.worktrees/presenca-canonica/src/components/App/Agenda/Chamada/useChamadaAcoes.ts`
- Create: `D:/2026/LA-performance-report/.worktrees/presenca-canonica/src/components/App/Agenda/Chamada/chamadaUtils.test.ts`

- [ ] **Step 1: Escrever os testes de estado e ação antes da UI**

  Extrair uma função pura `acaoDoBotaoPresente(aluno)` para que o teste prove
  as três ações:

  ```ts
  expect(acaoDoBotaoPresente({ status_presenca: 'presente', respondido_por: 'emusys' })).toEqual('manter')
  expect(acaoDoBotaoPresente({ status_presenca: 'presente', respondido_por: 'agenda_secretaria' })).toEqual('indeterminado')
  expect(acaoDoBotaoPresente({ status_presenca: null, respondido_por: 'emusys' })).toEqual('presente')
  ```

  Rodar e observar RED por símbolo inexistente. Não testar JSX por classes; o
  teste deve validar a intenção de domínio usada pelos dois componentes.

- [ ] **Step 2: Tornar a RPC resistente a chamada direta destrutiva**

  Recriar `app_registrar_chamada_agenda(jsonb)` no migration do Report. No ramo
  `v_status = 'indeterminado'`, quando a linha existente for
  `respondido_por='emusys'` e `status_presenca='presente'`, não apagar a linha:

  ```sql
  if v_existente.respondido_por = 'emusys'
     and v_existente.status_presenca = 'presente' then
    v_erros := v_erros || jsonb_build_object(
      'aluno_id', v_aluno_id,
      'aula_emusys_id', v_aula.id,
      'erro', 'presenca_emusys_ativa'
    );
    continue;
  end if;
  ```

  O restante do toggle humano é preservado. O botão de falta continua sendo a
  correção explícita: promove a linha a `agenda_secretaria`, conserva
  `emusys_presenca_bruta` e deixa retificação quando aplicável. Acrescentar
  `presenca_emusys_ativa` ao mapa de erros.

- [ ] **Step 3: Implementar UX sem clique enganoso**

  `rotuloOrigem` passa a mostrar exatamente **“Secretaria · LA Report”**,
  **“Professor · LA Teacher”**, **“Professor · WhatsApp/Fábio”** e **“Emusys”**.
  Nos dois componentes, Emusys/presente fica com badge passivo e o botão
  Presente desabilitado/rotulado “Confirmado no Emusys”; Falta e Justificada
  continuam disponíveis como correção humana explícita. O texto de conflito
  distingue “evidência Emusys” de “decisão humana” sem apagar nenhuma das duas.

- [ ] **Step 4: Rodar GREEN em Report e commit focado**

  Run:

  ```powershell
  npm ci
  npm run test -- src/components/App/Agenda/Chamada/chamadaUtils.test.ts
  npm run build
  ```

  Expected: teste novo verde e build sem erro de tipo. Se o projeto usar outro
  comando de teste, descobrir primeiro com `npm run`; não trocar o script por
  suposição. Commit somente migration, testes e arquivos da chamada.

### Task 5: Provar integração, revisar segurança e publicar em ordem

**Files:**
- Modify: `D:/la-teacher-worktrees/presenca-canonica/docs/superpowers/specs/2026-08-12-presenca-canonica-e-entrada-manual-design.md`
- Modify: `D:/la-teacher-worktrees/presenca-canonica/RETOMADA.md`
- Modify: `D:/2026/LA-performance-report/.worktrees/presenca-canonica/docs/CHAMADA-AGENDA.md`
- Modify: `D:/2026/LA-performance-report/.worktrees/presenca-canonica/docs/REGRAS-DE-NEGOCIO.md`
- Modify: `D:/2026/LA-performance-report/.worktrees/presenca-canonica/docs/MAPA-SISTEMA.md`
- Modify: `D:/2026/LA-performance-report/.worktrees/presenca-canonica/docs/MAPA-INTEGRACAO-EMUSYS.md`

- [ ] **Step 1: Aplicar as migrations na branch Supabase e repetir a prova de integração**

  Aplicar primeiro a migration do LA Teacher, depois a do LA Report. Reexecutar
  as fixtures nas seguintes transições: Emusys/presente, Emusys/ausente,
  secretaria/presente, Teacher/falta e WhatsApp/presente. Conferir a linha
  gêmea, a origem, a evidência bruta e as permissões depois de cada caso.

- [ ] **Step 2: Conferir Advisor e ACLs**

  Rodar Security e Performance Advisors na branch; consultar explicitamente:

  ```sql
  select has_function_privilege('anon', 'public.fn_sincronizar_gemeos_presenca(integer)', 'execute') as anon,
         has_function_privilege('authenticated', 'public.fn_sincronizar_gemeos_presenca(integer)', 'execute') as authenticated,
         has_function_privilege('service_role', 'public.fabio_registrar_presencas_aula(integer,integer,integer[])', 'execute') as fabio_service_role;
  ```

  Expected: `anon=false`, `authenticated=false`, `fabio_service_role=true`.
  Não aceitar novo aviso de `SECURITY DEFINER` exposto sem justificativa e
  teste de autorização.

- [ ] **Step 3: Verificar interfaces renderizadas nos dois tamanhos**

  Abrir a agenda do LA Teacher e a Chamada do Report em **390×844** e
  **1400×900**. Registrar screenshots que mostrem, respectivamente, Emusys
  presente fechado com carimbo, Emusys ausente pendente, e a correção humana
  com origem preservada. HTTP 200 não substitui esse teste interativo.

- [ ] **Step 4: Publicar em gates e validar produção sem criar fixture**

  Só após PRs revisados: merge do LA Teacher, deploy da migration do Teacher;
  merge do LA Report, deploy da migration do Report; deploys de frontend; e
  observação de um caso real controlado já existente. Não enviar WhatsApp
  automático nem produzir presença sintética. Se a API Emusys não documentar
  uma escrita idempotente, manter explicitamente o fluxo local-only.

- [ ] **Step 5: Atualizar documentação e checkpoint final**

  Documentar o resolvedor, origem, limite de saída Emusys, migrations, hashes,
  URL/commit de cada PR, status de branch e evidência de produção. Alterar o
  status da SPEC para refletir somente fatos medidos. Fazer commits separados
  de documentação em cada repositório e push antes de encerrar.

## Plano separado: entrada manual por aluno

O formulário manual é um subsistema independente de presença e será executado
em `docs/superpowers/plans/2026-08-12-entrada-manual-registro-aula.md`, em
worktree `codex/entrada-manual-registro-aula`. Ele só poderá usar as mesmas
RPCs de rascunho/confirmar do motor de áudio; não cria nova tabela pedagógica,
nem mistura tronco comum com repertório, dever ou progresso individual. Antes
de iniciar, auditar as assinaturas de `app_criar_registro_*`,
`fn_atualizar_fatia_core` e `app_confirmar_registro` e escrever testes RED para
rascunho automático, copiar campo, duplicar ficha e confirmação de sobrescrita.
