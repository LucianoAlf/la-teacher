-- Apaga as três experimentais fictícias do teste do ciclo (07/08/2026).
--
--   Helena Vasconcelos Prado   vínculo 1182  — a ficha, a dica e a agenda
--   Rafael Moura Antunes       vínculo 1236  — o áudio virando os quatro campos
--   Isabela Freitas Rocha      vínculo 1238  — a falta em um toque
--
-- Todas na unidade "TESTE — não é aula real"
-- (00000000-0000-4000-8000-00000000ffff), com ids negativos que não colidem
-- com nada do Emusys.
--
-- A ordem é a das dependências, de fora pra dentro. Rodar quando o Alf
-- terminar de clicar:
--   node scripts/aplicar-sql.mjs scripts/limpar-experimentais-de-teste.sql
--
-- A unidade e o contato comercial NÃO são apagados: servem pro próximo teste,
-- e apagar contato comercial é o tipo de coisa que some sem ninguém notar.

begin;

create temp table _alvo on commit drop as
select v.id as vinculo_id, le.id as lead_exp_id, v.aula_local_id
  from public.lead_experimental_aulas v
  join public.lead_experimentais le on le.id = v.lead_experimental_id
 where le.id in (-90001, -90002, -90003);

delete from public.fabio_notificacoes
 where (referencia_tipo = 'lead_experimental_falta'
        and referencia_id in (select vinculo_id::text from _alvo))
    or (referencia_tipo = 'lead_experimental_registro'
        and referencia_id in (select r.id::text from public.lead_experimental_registros r
                               join _alvo a on a.vinculo_id = r.vinculo_id));

delete from public.lead_experimental_registros
 where vinculo_id in (select vinculo_id from _alvo);

delete from public.fabio_fila_audios
 where vinculo_id in (select vinculo_id from _alvo);

delete from public.lead_experimental_aulas
 where id in (select vinculo_id from _alvo);

delete from public.aulas_emusys
 where id in (select aula_local_id from _alvo);

delete from public.lead_experimentais where id in (-90001, -90002, -90003);
delete from public.leads            where id in (-90001, -90002, -90003);

-- Confere que sobrou zero antes de fechar.
do $$
declare v_sobrou integer;
begin
  select count(*) into v_sobrou from public.lead_experimentais where id in (-90001, -90002, -90003);
  if v_sobrou > 0 then
    raise exception 'sobrou % experimental(is) de teste', v_sobrou;
  end if;
end $$;

commit;
