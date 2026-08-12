# Presença canônica entre Emusys, LA Report, LA Teacher e Fábio — design

**Status:** decisões de produto aprovadas pelo Alf em 12/08/2026. Esta SPEC
autoriza o plano em gates; nenhuma migration, RPC, deploy, sincronização externa
ou escrita produtiva é feita somente por este documento.

## Resultado que precisa existir

Os quatro pontos de contato devem ler a mesma decisão local de presença:

- a secretaria lança no **Emusys**;
- a equipe também pode concluir ou corrigir no **LA Report**;
- o professor vê e completa no **LA Teacher**;
- o **Fábio**, pelo WhatsApp, consulta e registra a resposta do professor.

Não será criada uma cópia por sistema nem um segundo motor operacional de
presença. `public.aluno_presenca` continua sendo o registro canônico, uma linha
por `(aluno_id, aula_emusys_id)`. A exceção deliberada é uma trilha
**append-only de eventos**, obrigatória para auditoria e conflitos: ela nunca
fecha chamada, nunca é lida como estado atual e não concorre com a linha
canônica. O carimbo visível informa a origem da decisão: **Emusys**,
**Secretaria · LA Report**, **Professor · LA Teacher** ou **Professor ·
WhatsApp/Fábio**.

## Decisão de negócio aprovada

O Emusys possui uma limitação importante: ausência ainda pode significar que a
secretaria não fez o lançamento. Logo, origem e status precisam ser resolvidos
juntos, e não apenas pela origem.

| Evidência atual na linha canônica | Fecha chamada no LA Teacher e no LA Report? | Comportamento |
|---|---:|---|
| fonte humana (`agenda_secretaria`, `manual`, `professor_la_teacher`, `fabio_audio`, `professor_whatsapp`) | sim | decisão humana registrada; preserva sua origem |
| `respondido_por='emusys'` e `status_presenca='presente'` | sim | presença válida da secretaria, exibida como Emusys |
| `respondido_por='emusys'` e `status_presenca='ausente'` | não | continua pendência do LA Report até alguém confirmar falta ou presença |
| sem linha / `sistema` / estado indeterminado | não | pendência honesta |

`fn_presenca_e_forte(respondido_por)` **não será alterada**. Ela continua sendo a
régua histórica de evidência humana e é consumida por mais de uma camada
analítica. O novo contrato, de escopo explícito, será a função status-aware
`fn_presenca_fecha_chamada(status_presenca, respondido_por)`, com semântica
fechada:

```sql
p_status_presenca in ('presente', 'falta', 'falta_justificada')
and (
  fn_presenca_e_forte(p_respondido_por)
  or (p_respondido_por = 'emusys' and p_status_presenca = 'presente')
)
```

Assim, uma origem humana com `NULL` ou `indeterminado` não fecha chamada, e uma
origem desconhecida com `presente` também não. A matriz de consumidores é
obrigatória: métricas de **decisão humana/evidência humana** continuam em
`fn_presenca_e_forte`; pendências, guardas de “já chamada enviada”, contadores
operacionais e perguntas do Fábio usam `fn_presenca_fecha_chamada`.

## Arquitetura e escrita

1. **Leitura única.** `app_minha_agenda_sessao` expõe, por aluno e por aula,
   status, origem, data da resposta, evidência bruta do Emusys e o resultado do
   resolvedor. O cliente não recalcula a regra nem infere origem pelo texto.
2. **Escrita única.** As RPCs existentes continuam sendo as únicas portas de
   escrita. A chamada do professor usa `app_registrar_presencas_aula`; a equipe
   usa `app_registrar_chamada_agenda`; o Fábio usa uma porta server-side
   restrita que valida a identidade resolvida pelo WhatsApp e chega ao mesmo
   núcleo (`fn_registrar_presencas_core`). Não haverá `INSERT` direto de bridge,
   navegador ou LLM.
3. **Precedência sem apagar prova nem mudança.** Uma resposta humana promove
   uma linha fraca do Emusys e conserva `emusys_presenca_bruta` como evidência.
   Toda alteração recebida do Emusys é registrada, inclusive
   `presente → ausente`: ela atualiza a evidência bruta e abre conflito de
   revisão, mas não troca silenciosamente a decisão já resolvida por uma falta.
   Se duas decisões humanas divergem, o estado não é “escolhido” por uma regra
   oculta; ambas ficam auditadas e a UI pede revisão explícita.
4. **Gêmeos com proveniência.** Uma propagação leva a origem, o vínculo da
   decisão que a causou, a evidência Emusys relevante e seu momento de leitura.
   Ela não sobrescreve decisão humana já existente. Para Emusys, apenas
   `presente` é propagável: ausência bruta não cria falta “confirmada” nem fecha
   pendência do gêmeo. O retorno da operação distingue `sincronizados`,
   `mantidos_por_precedencia` e `conflitos_para_revisao`; não reporta sucesso
   genérico se houve conflito.
5. **Sem promessa de escrita no Emusys.** Hoje a integração conhecida é
   pull-only (`sync-presenca-emusys` lê `/v1/aulas/`). LA Teacher e LA Report
   passam a convergir imediatamente porque usam o mesmo banco. O caminho
   LA Teacher/Report → API Emusys fica bloqueado até existir endpoint externo,
   autenticação e idempotência documentados; só então será uma fase própria com
   outbox auditável.

## RLS, Fábio e trilha de auditoria

- As tabelas permanecem RPC-only; não se abre `INSERT` ou `UPDATE` diretamente
  para `authenticated`, `anon` ou para o bridge.
- A porta do Fábio permanece `service_role`, mas não aceita mais somente
  `professor_id + aula_id`. Ela exige uma ação pendente emitida para aquele
  telefone/professor, com nonce, shortlist de aulas/alunos, expiração e
  idempotência; uma resposta fora desse contexto é recusada e auditada.
- A porta da secretaria mantém a checagem de usuário, unidade e permissão
  `agenda.chamada`; cada correção humana preserva a trilha de retificação.
- `aluno_presenca_eventos` entra no Gate 1 como trilha append-only e sem grants
  diretos. Só pode ser reutilizada uma tabela equivalente que já exista no
  snapshot do schema; caso contrário, este é o único nome novo autorizado para
  o ledger. Cada evento guarda a
  chave da linha canônica, tipo (`evidencia_emusys_criada/alterada`,
  `decisao_humana_promovida/corrigida`, `espelho_propagado`,
  `tentativa_fabio`, `conflito_rejeitado`), antes/depois, origem, ator ou ação
  quando houver, e vínculo da decisão de origem. A tabela é auditável, não uma
  fonte de verdade para leitura operacional.

## UX obrigatória

### Chamada e carimbos

- O LA Teacher mostra o carimbo de origem no aluno e mantém o estado da sessão
  coerente com o resolvedor.
- No LA Report, uma presença positiva trazida do Emusys é válida e não pode ser
  removida por um segundo clique genérico. A equipe deve escolher uma correção
  explícita quando precisar contrariá-la; a evidência bruta não é apagada.
- A ausência vinda do Emusys permanece destacada como pendência operacional,
  exatamente como a fila que a equipe hoje resolve no Report.

### Registro de aula: áudio e preenchimento manual

Esta é a segunda frente do pedido e não será perdida enquanto a presença é
priorizada:

- na agenda, há dois botões diretos e visíveis: **microfone** para gravar e
  **caderno** para preencher manualmente; não há menu intermediário;
- o caderno abre a ficha completa em rascunho automático, com um cartão por
  aluno em turmas, mantendo campos individuais;
- a ordem dos campos é **repertório, atividades, objetivo, observações, dever
  de casa**, seguida de **progresso individual** no cartão de cada aluno;
- por campo, o professor pode copiar o conteúdo para outro aluno; também pode
  **duplicar a ficha inteira**; ao sobrescrever campo já preenchido, o app pede
  confirmação;
- o rascunho é identificado por professor + aula + aluno, salvo por RPC com
  RLS, tem versão para detectar concorrência, recupera falha de conexão sem
  fingir que salvou e pede decisão quando áudio e formulário manual editarem a
  mesma ficha;
- copiar só alcança alunos do roster da mesma aula, não copia presença e mostra
  exatamente quais campos comuns serão substituídos. Repertório, dever e
  progresso continuam individuais por padrão; “tronco” é atalho explícito, não
  uma imposição do modelo;
- o formulário manual e o fluxo de áudio usam a mesma estrutura de preview e o
  mesmo núcleo de confirmação. Eles não reduzem repertório, tarefa ou progresso
  individual a um “tronco” obrigatório.

## Implementação em gates

### Gate 0 — inventário e alinhamento

1. Confirmar no schema remoto as assinaturas e ACLs de
   `app_minha_agenda_sessao`, `app_registrar_chamada_agenda`,
   `app_registrar_presencas_aula`, `fn_registrar_presencas_core`,
   `fn_sincronizar_gemeos_presenca` e `upsert_presenca_emusys_bruta`.
2. Garantir que a migration já aplicada em produção
   `20260812135033_fix_presence_json_null_confirmation` esteja no ancestral da
   branch de publicação. Ela corrige JSON nulo da confirmação e não substitui
   este trabalho.
3. Confirmar que nenhuma frente paralela criou migration concorrente.

### Gate 1 — contrato SQL e RPCs

1. Criar a migration versionada com o resolvedor status-aware, a matriz de
   consumidores e as mudanças mínimas nas RPCs/leitura, sem alterar a
   semântica de `fn_presenca_e_forte`.
2. Criar a trilha append-only de eventos e gravar nela cada mutação, espelho,
   conflito e tentativa WhatsApp antes de liberar UI.
3. Fazer cada porta de escrita chamar o sincronizador de gêmeos uma vez, sob a
   mesma precedência, inclusive a secretaria; preservar vínculos de origem e
   retornar contadores de sincronização e conflito.
4. Estender/rever a porta WhatsApp com ação pendente, nonce, expiração,
   shortlist e idempotência, sem abrir RLS de tabela. Revogar grants públicos
   de helpers internos e conceder somente os papéis já necessários.

### Gate 2 — cliente e Report

1. Consumir os novos campos da RPC no LA Teacher e exibir o carimbo.
2. Ajustar a ferramenta de chamada do LA Report para diferenciar confirmação
   Emusys de correção humana e não apagar evidência bruta.
3. Implementar a ficha manual seguindo o contrato acima, em uma branch própria
   ou em commits separados, para não conflitar com o motor de áudio em curso.
   A implementação começa por contrato de rascunho/RPC, conflito de versão e
   teste de recuperação offline; não apenas pelo mockup.

### Gate 3 — prova

Testes SQL com fixtures descartáveis ou ambiente de integração, nunca inserções
de teste na produção, cobrem ao menos:

- Emusys/presente fecha a chamada nos dois clientes e exibe a origem;
- Emusys/ausente permanece pendência no Report e no Teacher;
- secretaria, professor app e WhatsApp promovem estado fraco sem apagar a
  evidência Emusys;
- `presente → ausente` no Emusys preserva a decisão resolvida, muda a evidência
  bruta e abre conflito de revisão;
- a decisão propagável chega ao gêmeo com vínculo de origem, não pisa em
  decisão humana já feita e reporta separadamente sync, manutenção e conflito;
- tentativa WhatsApp sem ação pendente válida, nonce, telefone, expiração ou
  idempotência é recusada e vira evento auditável;
- toda mutação relevante produz exatamente um evento append-only; não há
  escrita direta de navegador/bridge nas tabelas;
- um clique na presença Emusys positiva não destrói a linha;
- cards individuais, copiar campo e duplicar ficha preservam os dados
  individuais, não copiam presença e pedem confirmação para sobrescrita;
- rascunhos manuais recuperam reconexão, detectam versão concorrente e mostram
  conflito áudio/manual antes de gravar uma versão final.

Depois: revisão de Security Advisor/ACL, preview do Report e do LA Teacher em
390×844 e 1400×900, piloto real controlado e só então produção. O rollback é
feito por migration corretiva e feature flag de UI; nunca por apagar a trilha de
presença.

## Critérios de aceite

1. Um `presente` do Emusys aparece como chamado no LA Teacher e no LA Report,
   com carimbo Emusys.
2. Um `ausente` do Emusys continua disponível para decisão da equipe, sem ser
   falsamente considerado presença/falta humana.
3. Cada decisão humana e cada decisão Emusys positiva refletida entre gêmeos
   preserva a precedência, a origem e o vínculo de quem a originou.
4. Mudanças contraditórias do Emusys e conflitos humanos são visíveis para
   revisão; nenhuma falta humana é fabricada ou escolhida silenciosamente.
5. Fábio consulta e escreve pelo mesmo contrato, só dentro de ação WhatsApp
   válida, sem acesso SQL direto ou RLS ampliada.
6. Toda mutação e tentativa relevante fica na trilha append-only, sem criar uma
   segunda fonte operacional.
7. O professor pode escolher áudio ou formulário manual, e turmas mantêm
   repertório, tarefa e progresso de cada aluno com rascunho, versão e proteção
   contra cópia indevida.
