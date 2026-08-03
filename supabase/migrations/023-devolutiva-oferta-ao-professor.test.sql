-- Teste da 023 — a oferta ao professor.
--
-- Rodar com: npm run teste:023
--
-- O que este teste existe para impedir:
--
--  a) oferecer devolutiva sem destinatario decidido ou com texto vazio. O
--     professor receberia um aviso sobre algo que nao da para usar, e pior:
--     a linha sairia da fila carimbada como oferecida.
--  b) oferecer DUAS VEZES. O worker roda de 5 em 5 minutos; se o carimbo nao
--     for atomico, o professor leva a mesma mensagem repetida a cada ciclo.
--     Aqui isso e testado nas duas camadas: o carimbo (023) e a chave por
--     referencia (018).

create temp table _falhas(passo text, esperado text, obtido text) on commit drop;
create function pg_temp.checar(p text, e text, o text) returns void language plpgsql as $c$
begin if e is distinct from o then insert into _falhas values (p, coalesce(e,'(null)'), coalesce(o,'(null)')); end if; end $c$;

-- Quantas devolutivas do professor 25 a lista traz.
create function pg_temp.na_lista(p_id uuid) returns integer language sql as $f$
  select coalesce((
    select count(*)::integer
      from jsonb_array_elements(public.fabio_devolutivas_a_oferecer(500)) prof,
           jsonb_array_elements(prof->'devolutivas') dev
     where (dev->>'id')::uuid = p_id
  ), 0);
$f$;

do $t$
declare
  v_aula integer; v_unidade uuid; v_aluno integer; v_skill uuid;
  v_reg_ok uuid; v_reg_sem_dest uuid; v_reg_vazio uuid;
  v_id_ok uuid; v_id_sem_dest uuid; v_id_vazio uuid;
  a jsonb; v_tok uuid; v_claim jsonb; v_claim2 jsonb; v_res jsonb;
begin
  select a2.id, a2.unidade_id into v_aula, v_unidade
    from public.aulas_emusys a2 where a2.professor_id=25 order by a2.id desc limit 1;
  select id into v_aluno from public.alunos where status='ativo' order by id limit 1;
  select id into v_skill from public.fabio_skills where nome='devolutiva_aula' and ativa;
  if v_aula is null or v_aluno is null then
    insert into _falhas values ('setup','aula e aluno','faltou'); return;
  end if;

  -- ============ caso bom: destinatario decidido + texto ============
  insert into public.fabio_registros_aula
    (aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos, status, origem, confirmado_em)
  values (v_aula, v_unidade, 25, v_aluno, null, 'C',
          '{"progresso":"tocou a escala inteira","presenca":"presente"}'::jsonb,
          'gravado_emusys','app', now())
  returning id into v_reg_ok;
  perform public.fabio_enfileirar_devolutivas(v_reg_ok);
  select id into v_id_ok from public.fabio_devolutivas where registro_fatia_id = v_reg_ok;

  perform pg_temp.checar('1. antes de gerar NAO esta na lista','0', pg_temp.na_lista(v_id_ok)::text);

  a := public.fabio_devolutiva_claim('worker-teste', 10, 20);
  v_tok := (a->>'lease_token')::uuid;
  perform public.fabio_devolutiva_gerada(v_id_ok, v_tok,
    'A aula de hoje rendeu bastante.', 'apoio interno', 'responsavel', 'Mae da Crianca', 8, v_skill, 1);

  perform pg_temp.checar('2. gerada COM destinatario e texto entra na lista','1',
    pg_temp.na_lista(v_id_ok)::text);

  -- ============ a fronteira que nao pode vazar ============
  -- ATENCAO A ORDEM: isto tem que rodar ENQUANTO a devolutiva esta na lista.
  -- Na primeira versao deste teste as duas checagens estavam no fim, depois
  -- do carimbo -- e ai a lista ja estava vazia, entao o `like` nao achava
  -- nada e passava sempre. O mutante que devolvia o texto junto SOBREVIVEU.
  -- Verificacao sobre conjunto vazio nao verifica nada.
  perform pg_temp.checar('3. lista nao expoe texto_apoio_casa','false',
    (public.fabio_devolutivas_a_oferecer(500)::text like '%apoio interno%')::text);
  perform pg_temp.checar('4. lista nao expoe texto_normal','false',
    (public.fabio_devolutivas_a_oferecer(500)::text like '%rendeu bastante%')::text);

  -- ============ fail closed: sem destinatario ============
  insert into public.fabio_registros_aula
    (aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos, status, origem, confirmado_em)
  values (v_aula, v_unidade, 25, v_aluno, null, 'C',
          '{"progresso":"outro","presenca":"presente"}'::jsonb, 'gravado_emusys','app', now())
  returning id into v_reg_sem_dest;
  perform public.fabio_enfileirar_devolutivas(v_reg_sem_dest);
  select id into v_id_sem_dest from public.fabio_devolutivas where registro_fatia_id = v_reg_sem_dest;
  update public.fabio_devolutivas
     set status='gerada', texto_normal='tem texto', destinatario=null
   where id = v_id_sem_dest;
  perform pg_temp.checar('5. SEM destinatario nao e oferecida','0',
    pg_temp.na_lista(v_id_sem_dest)::text);

  -- ============ fail closed: texto so espacos ============
  insert into public.fabio_registros_aula
    (aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos, status, origem, confirmado_em)
  values (v_aula, v_unidade, 25, v_aluno, null, 'C',
          '{"progresso":"mais um","presenca":"presente"}'::jsonb, 'gravado_emusys','app', now())
  returning id into v_reg_vazio;
  perform public.fabio_enfileirar_devolutivas(v_reg_vazio);
  select id into v_id_vazio from public.fabio_devolutivas where registro_fatia_id = v_reg_vazio;
  update public.fabio_devolutivas
     set status='gerada', destinatario='aluno', destinatario_nome='Fulano', texto_normal='   '
   where id = v_id_vazio;
  perform pg_temp.checar('6. texto so com espacos nao e oferecida','0',
    pg_temp.na_lista(v_id_vazio)::text);

  -- ============ o carimbo ============
  v_res := public.fabio_devolutiva_oferecida(v_id_ok, null);
  perform pg_temp.checar('7. carimbo funciona','true', (v_res->>'ok'));
  perform pg_temp.checar('8. status virou oferecida','oferecida',
    (select status from public.fabio_devolutivas where id = v_id_ok));
  perform pg_temp.checar('9. oferecida_em preenchido','true',
    (select (oferecida_em is not null)::text from public.fabio_devolutivas where id = v_id_ok));
  perform pg_temp.checar('10. sai da lista depois de oferecida','0',
    pg_temp.na_lista(v_id_ok)::text);

  -- O passo 10 sozinho nao prova que `oferecida_em is null` faz alguma coisa:
  -- o carimbo tambem muda o status, e o filtro de status ja bastaria. Aqui a
  -- linha volta pra `gerada` MANTENDO oferecida_em -- e nao pode reaparecer.
  -- Sem isso, um reprocessamento que mexa no status reoferece pro professor.
  update public.fabio_devolutivas set status='gerada' where id = v_id_ok;
  perform pg_temp.checar('11. gerada COM oferecida_em nao reaparece','0',
    pg_temp.na_lista(v_id_ok)::text);
  update public.fabio_devolutivas set status='oferecida' where id = v_id_ok;

  -- ============ a corrida: segundo worker no mesmo ciclo ============
  v_res := public.fabio_devolutiva_oferecida(v_id_ok, null);
  perform pg_temp.checar('12. segunda oferta NAO passa','false', (v_res->>'ok'));
  perform pg_temp.checar('13. motivo explicito','ja_oferecida_ou_status_mudou', (v_res->>'motivo'));

  -- ============ a outra camada: chave por referencia (018) ============
  v_claim := public.fabio_claim_notificacao_por_referencia(
    25, 'devolutiva_pronta', 'informativa', 'whatsapp', 'corpo da oferta',
    'devolutiva', v_id_ok::text, 'Devolutiva pronta', 10);
  perform pg_temp.checar('14. primeiro claim da notificacao reivindica','true',
    (v_claim->>'claimed'));
  v_claim2 := public.fabio_claim_notificacao_por_referencia(
    25, 'devolutiva_pronta', 'informativa', 'whatsapp', 'corpo da oferta',
    'devolutiva', v_id_ok::text, 'Devolutiva pronta', 10);
  perform pg_temp.checar('15. segundo claim da MESMA referencia nao reivindica','false',
    (v_claim2->>'claimed'));


exception when others then
  insert into _falhas values ('excecao','sem excecao', sqlerrm);
end $t$;

select json_build_object('teste','023-devolutiva-oferta-ao-professor',
  'falhas',(select count(*) from _falhas),
  'detalhe', coalesce((select json_agg(json_build_object('passo',passo,'esperado',esperado,'obtido',obtido)) from _falhas),'[]'::json)) as resumo;
