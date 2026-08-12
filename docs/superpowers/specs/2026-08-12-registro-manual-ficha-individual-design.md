# Registro manual por ficha individual — design

**Status:** proposta técnica derivada das decisões de produto aprovadas em
12/08/2026. Este documento **não** autoriza migration, alteração de RPC ou
deploy da ficha manual; fecha o contrato para revisão antes da implementação.

## Decisão de produto preservada

Na agenda haverá dois controles diretos, sem menu intermediário:

- **microfone:** mantém o fluxo de áudio;
- **caderno:** abre a ficha manual da mesma aula.

Em uma turma, o caderno não é uma ficha única que se aplica a todos. Ele abre
um cartão por aluno, em uma lista rolável. Repertório, dever e progresso são
individuais por padrão. O professor pode usar um tronco opcional quando algo
for realmente comum, mas o tronco nunca preenche ou sobrescreve cartões por
conta própria.

## O que será reutilizado

Não haverá nova tabela de ficha manual nem uma nova fonte de presença.
`public.fabio_registros_aula` já é o agregado de rascunho usado pelo áudio:

- raiz com `parent_id is null`; em turma, as fatias têm `parent_id = raiz.id`;
- em aula individual, a própria raiz pertence ao aluno;
- `app_registro_completo`, `app_atualizar_fatia` e
  `app_confirmar_registro` já atendem preview, edição e gravação final.

O contrato novo diferencia o meio de entrada em vez de forçar a coluna
`origem`, cujo domínio atual é o canal técnico (`app` ou `whatsapp`). A
migration, quando aprovada, acrescentará em `fabio_registros_aula`:

```sql
modo_entrada text not null default 'audio'
  check (modo_entrada in ('audio', 'manual')),
versao integer not null default 1
```

Assim, dados existentes continuam sendo `audio`, e um rascunho manual não é
inferido por `audio_id is null` (isso já ocorre em dados legítimos).

## Contrato dos campos

Cada cartão individual mostra, nesta ordem, as chaves canônicas que a função
de prontuário já entende:

1. `repertorio` — Repertório
2. `atividades` — Atividades
3. `objetivo` — Objetivo
4. `observacao` — Observações
5. `dever_casa` — Dever de casa
6. `progresso` — Progresso individual

O tronco opcional usa apenas conteúdo efetivamente comum. No formato legado
ele é armazenado em `atividades`, `objetivo`, `repertorio`, `dever_casa` e
`obs_gerais`; o cartão usa as seis chaves acima. A composição existente já
evita repetir uma fatia idêntica ao tronco. A tela deixa claro que abrir ou
editar o tronco **não copia automaticamente** os valores para cartões.

`presenca`, `aula_alvo_resolvida`, recibos, origem e metadados internos nunca
fazem parte do formulário, do copiar campo ou do duplicar ficha.

## Rascunho e segurança

As novas portas autenticadas serão RPCs, e sempre descobrem o professor pelo
JWT; o cliente não informa `professor_id`, unidade, aluno de destino nem aula
individual resolvida.

### Abrir

`app_abrir_rascunho_manual(p_aula_id integer)`:

- valida professor, aula, janela de registro, cancelamento e roster usando as
  mesmas guardas do áudio;
- devolve o rascunho manual aberto daquele professor e aula, se já existir;
- caso contrário cria, numa única transação, a raiz e as fatias do roster;
- cria uma raiz individual para aula 1:1 e raiz + fatias para turma;
- nunca grava presença;
- informa separadamente se houver rascunho de áudio aberto para a mesma aula.

Um índice parcial garante no máximo uma raiz manual aberta por
`(professor_id, aula_id)`, apenas enquanto estiver em `rascunho` ou
`aguardando_confirmacao`. Isso evita dois cadernos concorrentes sem impedir o
histórico depois da confirmação.

### Salvar

`app_salvar_rascunho_manual(...)` recebe a versão da raiz, os campos do tronco
e um conjunto completo de fatias identificadas pelo servidor. Ele:

- aceita somente as seis chaves individuais e as chaves autorizadas do tronco;
- rejeita `presenca`, IDs de aluno/aula, campos desconhecidos e aluno fora do
  roster;
- atualiza raiz e fatias atomica e condicionalmente à `versao` esperada;
- incrementa a versão de cada registro atualizado;
- retorna o agregado inteiro ou `conflito_de_versao`, sem atualização parcial.

O cliente mostra comparação entre a versão do servidor e a edição local; nunca
faz overwrite silencioso.

## Autosave e funcionamento offline

O autosave envia a RPC em lotes curtos depois de o professor pausar a digitação.
Ele mostra **Salvo** apenas após resposta positiva do servidor.

No IndexedDB atual (`la-teacher`), uma store nova `rascunhos-manuais` (versão
4) guarda somente cache de transporte: usuário autenticado, raiz, versões,
campos locais, instante e estado da tentativa. Ela é separada de
`fila-audios`. Sem conexão, o rótulo é **Não salvo neste dispositivo**; na
reconexão a mesma RPC resolve a versão. Cache local não é registro canônico.

## Copiar e duplicar na turma

As duas ações aprovadas coexistem em cada cartão:

- **Copiar campo:** escolhe um dos seis campos e um ou mais alunos do roster da
  mesma aula. O modal lista os destinos e só pede confirmação quando um valor
  não vazio será substituído.
- **Duplicar ficha:** leva os seis campos daquele aluno para destinos escolhidos
  e mostra exatamente quais campos preenchidos serão sobrescritos antes do
  commit.

Ambas só alteram o estado do rascunho local; passam pelo autosave versionado e
nunca incluem presença, tronco, aluno fora do roster ou dados de outra aula.

## Áudio e manual na mesma aula

Os dois caminhos podem coexistir. O caderno não apaga, converte nem mescla um
rascunho de áudio. Se houver áudio aberto, o caderno apresenta uma decisão
explícita:

1. abrir o preview do áudio; ou
2. continuar/criar a ficha manual independente.

Na confirmação final, permanece a escolha já existente de `novo`,
`substituir` ou `complementar`. Não há merge automático de texto entre os dois
rascunhos.

## Presença: fronteira obrigatória

Salvar, copiar, duplicar ou deixar um rascunho manual aberto não altera
`aluno_presenca`.

Já **Confirmar e gravar** é a afirmação humana do professor de que a aula
ocorreu, conforme a decisão de produto vigente: ela usa o mesmo núcleo
canônico de confirmação do áudio, gera presença de professor somente nesse
momento e conserva a origem exibida no LA Teacher/LA Report/Fábio.

Há uma correção de segurança funcional que precisa preceder a habilitação da
ficha manual: `fn_materializar_presenca_padrao` não pode transformar em
`presente` um aluno que já tenha uma falta humana canônica (secretaria,
professor ou Fábio). Nesse caso a confirmação deve preservar a ausência,
evitar gravar conteúdo para aquele aluno e devolvê-lo como item explícito de
revisão. Uma ausência bruta, ainda inconclusiva, do Emusys continua podendo ser
promovida pelo professor na confirmação final. Essa regra usa
`aluno_presenca`; não cria outro estado de presença dentro da ficha.

## Fluxo de tela

```
Agenda
  ├─ Microfone → /app/gravar/:aulaId (sem mudança de fluxo)
  └─ Caderno   → /app/registro-manual/:aulaId
                   → autosave RPC + cache local
                   → preview canônico /app/confirmar/:registroId
                   → confirmar e gravar pelo núcleo existente
```

Em `SessaoRow`, os dois botões têm o mesmo bloqueio de horário/permissão de
registro e interrompem a abertura acidental da tela de chamada. O preview
reutiliza a apresentação de tronco e fatias já existente, mas identifica
`modo_entrada=manual` e exibe os cartões por aluno antes da gravação.

## Provas obrigatórias antes de liberar

1. RPC rejeita aluno, aula, unidade, professor, campo ou presença forjados.
2. Duas abas com a mesma ficha recebem conflito de versão; nenhuma perde campos
   silenciosamente.
3. Cache offline não diz que salvou antes da confirmação do servidor e se
   recupera na reconexão.
4. Copiar campo e duplicar ficha alcançam somente o roster, pedem confirmação
   ao sobrescrever e nunca levam presença.
5. Tronco não replica campos para cartões sem ação explícita.
6. Áudio e manual coexistem sem merge, exclusão ou confirmação implícita.
7. Confirmar rascunho preserva falta humana canônica, mas a presença resultante
   da confirmação final se reflete nos três consumidores pelo escritor único.
8. Testes de UI em 390×844 e 1400×900 confirmam microfone e caderno diretos,
   lista rolável de alunos, modal de cópia e estados de autosave.

## Fora de escopo desta entrega

- transcrição, normalização semântica ou correção do modelo de áudio;
- nova integração de escrita na API Emusys;
- presença em autosave ou em ações de cópia;
- merge automático de áudio com manual;
- nova tabela de prontuários, presença ou ledger paralelo.
