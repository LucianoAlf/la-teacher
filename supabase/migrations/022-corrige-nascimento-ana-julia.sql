-- 022 — a última divergência, achada com a API do Emusys ao vivo
--
-- A 021 alinhou 11 datas contra o payload GUARDADO em emusys_api_payload.
-- Depois disso puxei as 4.825 matrículas direto da API (3 unidades) e
-- conferi 1.601 dos 1.618 alunos. Sobrou esta: Ana Julia de Oliveira Gomes,
-- evadida, Campo Grande. Não cruza a fronteira dos 15 anos (26 -> 21), então
-- não muda destinatário de devolutiva — mas divergir da fonte é divergir.
--
-- Guarda de estado igual à da 021: só age se nome e data atual baterem.

update alunos
   set data_nascimento = date '2005-05-27'
 where id = 1378
   and nome = 'Ana Julia de Oliveira Gomes'
   and data_nascimento = date '2000-05-27';

do $$
declare
  v_atual date;
begin
  select data_nascimento into v_atual from alunos where id = 1378;
  if v_atual is distinct from date '2005-05-27' then
    raise exception 'ABORTADO: id 1378 ficou com % (esperado 2005-05-27)', v_atual;
  end if;
  raise notice 'OK: Ana Julia alinhada ao Emusys';
end $$;
