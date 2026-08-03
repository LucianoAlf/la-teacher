# Auditoria — devolutiva de aula do Fábio

**Data:** 03/08/2026  
**Auditado:** `d431f59` — spec `docs/superpowers/specs/2026-08-03-devolutiva-aula-design.md`  
**Escopo:** revisão do diff de design. Nenhuma migration, worker, app ou dado foi alterado nesta auditoria.

## Veredito

**A direção melhorou e os quatro contratos aceitos estão certos, mas ainda não libero migration/worker.** O commit é somente de spec; não há implementação para validar ainda.

Entraram corretamente:

- correção na origem para presença 1:1, em vez de só esconder a devolutiva;
- fencing do lease e backoff explícito;
- `aguardando_destinatario` antes de chamar o LLM;
- outbox atômico entre `gerada` e a oferta.

## P0-1 — o gate de presença não fecha o caminho real até o professor

O diagnóstico de `31/31` registros sem a chave `presenca` é grave e a regra de sequenciamento é necessária. Mas “apareceu um registro pós-patch com a chave” não prova que todos os ingressos produzem presença válida.

O app atual também mascara ausência: `presencaDaFatia` devolve `presente` para qualquer valor diferente de `ausente`. E a RPC vigente usa `coalesce(..., 'presente')` no ramo turma; o ramo 1:1 nem consulta presença.

**Contrato necessário antes de subir:**

1. presença deve ser um enum obrigatório no produtor (`presente` ou `ausente`), sem `coalesce` que transforme desconhecido em presente;
2. provar ponta a ponta os dois formatos — turma e 1:1 — no ingress que o Matheus realmente usa;
3. o predicado/outbox deve falhar fechado: só `campos->>'presenca' = 'presente'` é elegível. Ausente e ausente de dado não enfileiram.

Um único registro observado é gate para experimento, não prova suficiente para abrir a regra global.

## P0-2 — “pendência” nova não tem contrato de resolução no app

Se o 1:1 sem presença virar pendência, o app atual não sabe tratá-lo: `PendenciaConfirmacao` só carrega `fatia_id`, a tela busca esse ID apenas na lista de fatias e mostra `Aluno` quando não acha. Registro raiz 1:1 não é fatia. Também não há, nesse fluxo, ação explícita para informar presença e repetir a confirmação.

Sem isso, a proteção vira bloqueio silencioso para o Matheus.

**Contrato necessário:** retorno genérico por alvo (`registro_alvo_id`, `tipo_alvo: raiz|fatia`, `campo_obrigatorio: presenca`, valores permitidos) e uma ação de UI/RPC que grave a escolha e reenvie a confirmação. Testar 1:1 e turma com presença ausente no payload até a resolução humana.

## P1-1 — outbox atômico não resolve a ambiguidade depois do envio

Criar a notificação com `gerada` evita devolutiva órfã; está certo. Mas, se o canal aceitar a oferta e o worker cair antes de persistir o recibo, o retry pode oferecer de novo.

Antes do worker, especificar claim/token também para a tentativa de entrega, chave de idempotência por `devolutiva_id` quando o canal suportar, e persistência do ID/recibo do canal. `oferecida` só deve nascer desse recibo; não prometer “exactly once” onde o transporte não prova isso.

## P1-2 — `aguardando_destinatario` precisa de saída durável

Bloquear antes do prompt é correto. Falta definir como a pergunta chega ao professor, como a resposta fica ligada àquela devolutiva e qual dado destrava a geração. Sem `destinatario_override` (ou equivalente), origem da decisão e recibo da escolha, a linha pode ficar parada indefinidamente ou voltar a gerar com destinatário inferido.

## Próxima entrega

Atualizar a spec com os dois P0 e os dois P1 acima. Depois, entregar migration, RPCs, worker e testes de integração do piloto Matheus para auditoria do diff. Só então faz sentido discutir aplicação.

## Evidência conferida

- `supabase/migrations/006-fix-origem-confirmacao.sql`: 1:1 atual grava sem consultar presença; turma usa `coalesce(..., 'presente')`.
- `src/features/registro/texto.ts`: ausência de valor é apresentada como `presente`.
- `src/lib/api.ts` e `src/features/registro/Confirmar.tsx`: pendência é modelada/renderizada como fatia, não como raiz individual resolvível.
