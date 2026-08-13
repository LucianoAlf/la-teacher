-- Mata a régua duplicada do veredito. Ela durou 40 minutos.
--
-- EU CONSTRUÍ DUAS VEZES NO MESMO DIA. De manhã foi a `vw_aluno_pessoa`
-- (duplicata da canônica de identidade). À noite foi esta: criei
-- `fn_presenca_e_resposta` na 20260813270000 dizendo que a casa tinha duas
-- réguas de presença discordando -- e não tinha.
--
-- O QUE EU MEDI ERRADO. Comparei `fn_presenca_e_forte(fonte)` com o predicado
-- que aparecia no `EXPLAIN` da `vw_presenca_pendencia` e concluí "duas
-- réguas, 44,4% x 95,4%". O predicado no plano estava expandido porque
-- `fn_presenca_fecha_chamada` é `sql IMMUTABLE` e o planejador INLINA -- o
-- nome da função some do plano. Eu li o efeito da inlinagem como se fosse
-- código copiado à mão.
--
-- A régua canônica sempre foi UMA: `fn_presenca_fecha_chamada(status, fonte)`,
-- com SEIS consumidores -- `vw_presenca_pendencia`, `app_minha_agenda_sessao`
-- (o selo), `fabio_aulas_candidatas`, `fn_sincronizar_gemeos_presenca`,
-- `trg_sincronizar_gemeos_presenca` e `upsert_presenca_emusys_bruta`. Ela já
-- implementa exatamente a decisão do Alf de 13/08: fonte humana vale sempre,
-- Emusys vale só quando afirma presente.
--
-- A DIFERENÇA REAL entre as duas era UMA coisa: o `coalesce` com a coluna
-- antiga `status`. E ela valia **10 linhas em 47.525** -- todas do dia
-- 05/08/2026, todas com `status='presente'`, `status_presenca` nulo e
-- `emusys_presenca_bruta='presente'`.
--
-- Essas 10 não são "coluna antiga sendo usada": são LINHAS ESTRAGADAS. O
-- escritor do Emusys (`upsert_presenca_emusys_bruta`) grava as duas colunas
-- juntas quando o estado é presente -- `v_status_presenca := case when v_raw =
-- 'presente' then 'presente' else null end`. Nenhuma linha nova nasce assim.
--
-- POR QUE APAGAR EM VEZ DE MANTER "POR SEGURANÇA". Um fallback no LEITOR para
-- compensar dado inconsistente espalha a compensação por todo consumidor
-- futuro e esconde a inconsistência em vez de mostrá-la. Dado torto se
-- conserta no dado; contrato se garante com constraint. Manter esta função
-- seria a sétima régua, não a primeira.
--
-- FICA REGISTRADO O QUE PRESTOU: a `fn_presenca_status_efetivo` NÃO é apagada.
-- Ela nomeia o `coalesce(status_presenca, status)` que já estava copiado à mão
-- dentro de `upsert_presenca_emusys_bruta` -- ali ele é legítimo, porque
-- aquela função lê linhas antigas de verdade. Ter o idioma com nome é ganho;
-- ter a régua duplicada não era.

drop function if exists public.fn_presenca_e_resposta(text, text, text);

comment on function public.fn_presenca_status_efetivo(text, text) is
  'Status de presenca com o fallback da coluna antiga `status`. Nomeia o '
  'idioma que ja existia copiado dentro de upsert_presenca_emusys_bruta. NAO '
  'usar para decidir se ha veredito -- para isso a regua canonica e '
  'fn_presenca_fecha_chamada(status_presenca, respondido_por), que tem 6 '
  'consumidores e ja implementa a decisao do Alf de 13/08/2026.';
