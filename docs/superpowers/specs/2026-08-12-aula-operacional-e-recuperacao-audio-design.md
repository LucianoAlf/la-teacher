# Aula operacional, recuperação do áudio e home sem promessa vazia

## Contexto observado em produção

O espelho do Emusys pode devolver mais de um evento para o mesmo professor,
unidade, curso e horário. Dois casos reais em 12/08/2026 provaram que o primeiro
evento não é necessariamente o utilizável:

- Leonardo, Guitarra às 14h: turma antiga sem roster + turma atual com roster +
  individual do mesmo aluno. A agenda escolheu a turma antiga, o áudio foi
  enfileirado nela e o normalizador recusou `aula sem roster canônico`.
- Matheus, Musicalização às 18h de 17/08: turma recorrente sem roster + aula
  individual reagendada com roster. A agenda mostrou apenas a turma vazia.

O bloco estático “Briefing do Fábio — em breve” também não entrega uma ação
presente e será ocultado de todos os professores até existir briefing real.

## Decisão

`aulas_emusys` permanece como espelho bruto e não será deduplicada nem apagada.
Uma função canônica resolve o **ID operacional** de qualquer evento por:

1. mesma unidade, professor, início, fim e curso;
2. evento não cancelado;
3. maior quantidade de alunos conciliados no roster;
4. em empate, turma antes de individual;
5. em novo empate, maior ID local, privilegiando o evento mais recente.

Uma aula vazia continua visível quando é a única candidata do slot. Ela só é
suprimida quando há concorrente compatível com roster.

## Consumidores obrigatórios

- `app_minha_agenda_sessao` escolhe a âncora pelo resolvedor;
- `vw_registro_pendencia` e `vw_presenca_pendencia` consideram somente a âncora
  operacional;
- `fabio_aulas_candidatas` usa a mesma âncora nos fluxos de registro e chamada;
- `fn_enfileirar_audio_core` canoniza o ID antes de persistir a fila, protegendo
  clientes antigos;
- o agrupamento React mantém uma defesa contra payload legado com turma vazia
  concorrente.

Não nasce uma segunda fonte de agenda, roster ou presença.

## Recuperação do incidente

Áudios em erro transitório por falta de roster podem ser religados somente
quando o resolvedor aponta outro evento compatível e esse destino possui
roster. Antes do `UPDATE`, a mudança é gravada no `audit_log` existente. A fila
volta a `pendente`, zera apenas o erro/tentativas de transporte e preserva
storage, transcrição, professor, unidade e origem.

## Simulação de 17/08

A prova visual usa a agenda real já existente do Matheus em 17/08, inclusive a
aula reagendada das 18h. Não será criado aluno fictício e a janela de chamada
do servidor não será contornada. A simulação de escrita antecipada fica fora da
produção; a tela real futura prova resolução/roster e, no horário permitido, a
mesma RPC fará a escrita auditável.

## Rollback

O rollback lógico é restaurar as definições anteriores das funções/views. Os
eventos brutos não mudam. Para uma fila religada, o `audit_log` contém o ID
anterior; qualquer reversão de dado exige decisão humana, não rollback
automático que interrompa um processamento já retomado.

## Verificação

- fixture SQL: turma vazia perde para turma com roster;
- fixture SQL: turma vazia perde para individual reagendada com roster;
- fixture SQL: turma vazia única permanece;
- ACL do helper: sem execução por `public`, `anon` ou `authenticated`;
- produção: Leonardo resolve para a aula com roster e Matheus/17/08 mostra o
  aluno das 18h;
- UI em 390×844 e 1400×900 sem o card de briefing;
- suíte, typecheck/build e inspeção da fila recuperada.
