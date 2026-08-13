-- SUPERADA POR: 20260813260000_a_aula_operacional_volta_a_usar_o_indice.sql
--
-- O teste da 064 afirma um FORMATO DE PLANO que a `vw_presenca_pendencia` nao
-- tem mais: ele exige o `idx_aulas_emusys_turma_no_horario` no subplano que a
-- view deixou de ter. O indice continua criado e o orcamento de buffers que a
-- 064 inaugurou continua sendo vigiado -- agora pelo teste da 20260813260000,
-- que mede a mesma view (12,3s -> 735ms, 4M -> 252k buffers).
--
-- 064 — a pendência de presença para de levar 27 segundos
--
-- `vw_presenca_pendencia` é a fonte única de "aula sem presença forte" (013):
-- é dela que saem a cobrança da noite, a da manhã e o escalonamento pra
-- coordenação. Ela levava **27 segundos** pra 3.770 linhas.
--
-- O PLANO ENTREGA O CULPADO INTEIRO
-- 13.872.244 buffers no total; **13.793.512 deles num único SubPlan**. 99,5%
-- do custo mora numa pergunta só: "esta aula individual acontece no mesmo
-- horário de uma aula de TURMA do mesmo professor?" — a regra que evita cobrar
-- duas vezes a mesma hora do professor.
--
-- Sem índice pra essa pergunta, o Postgres caía no `idx_aulas_emusys_data`
-- (unidade_id, data_aula), que só sabe filtrar por unidade: 13.847 linhas
-- descartadas POR CHAMADA, 3.785 chamadas. O índice existia e era o errado.
--
-- O ÍNDICE É PARCIAL PORQUE A PERGUNTA É PARCIAL
-- A busca só olha aula de turma não cancelada: 21.882 das 53.112 linhas. O
-- índice parcial fica com 40% do tamanho e, mais importante, o predicado diz
-- em SQL o que a view quer — quem ler daqui a um ano entende a intenção sem
-- abrir o plano.
--
-- NÃO MUDA UMA VÍRGULA DA VIEW. Nenhuma regra, nenhum resultado: as mesmas
-- 3.770 linhas, pelo mesmo caminho lógico. Só deixa de varrer a unidade
-- inteira pra responder uma pergunta de três colunas.
--
-- Tabela compartilhada: `aulas_emusys` é o espelho do Emusys e serve LA
-- Report, Sol e Fábio também. Índice é aditivo — ninguém que já lê a tabela
-- muda de comportamento, e quem fizer a mesma pergunta ganha de graça.
--
-- Teste: 064-a-pendencia-de-presenca-para-de-levar-27s.test.sql
-- Mutantes: scripts/mutantes-064.mjs

create index if not exists idx_aulas_emusys_turma_no_horario
    on public.aulas_emusys (unidade_id, professor_id, data_hora_inicio)
 where tipo = 'turma' and not coalesce(cancelada, false);

comment on index public.idx_aulas_emusys_turma_no_horario is
'Responde "existe aula de TURMA deste professor neste horario?" — a pergunta que a vw_presenca_pendencia faz uma vez por aula individual. Sem ele a view levava 27s (99,5% do custo num SubPlan so).';

-- Tinha um `analyze public.aulas_emusys;` aqui. O mutante V5 tirou ele e o
-- teste continuou verde: o planejador escolhe o índice novo sem estatística
-- refrescada. Linha que não muda nada não fica — cerimônia num arquivo de
-- migration vira "deve ser importante" pra quem ler depois.
