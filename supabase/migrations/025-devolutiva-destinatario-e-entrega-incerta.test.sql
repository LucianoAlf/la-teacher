-- Teste da 025 — saida do aguardando_destinatario e entrega incerta.
--
-- Rodar com: npm run teste:025
--
-- O QUE ESTE TESTE PROTEGE
--  a) o isolamento entre professores, de novo: as duas RPCs novas mexem em
--     quem le a devolutiva de uma crianca.
--  b) que `aguardando_destinatario` TENHA saida — decidida ou expirada. Um
--     estado sem saida e um vazamento silencioso de trabalho.
--  c) que `entrega_incerta` NAO tire a devolutiva da tela do professor. Quem
--     esta ali e justamente quem ainda precisa ser mandado; sumir ao marcar a
--     incerteza destruiria a chance de resolve-la.
--
-- Mesma armadilha da 024: `_falhas` e temp table do role original e sob
-- `set local role authenticated` o INSERT nela e NEGADO. Tudo observado sob
-- authenticated passa por variavel; o checar() so roda com o role resetado.

create temp table _falhas(passo text, esperado text, obtido text) on commit drop;
create function pg_temp.checar(p text, e text, o text) returns void language plpgsql as $c$
begin if e is distinct from o then insert into _falhas values (p, coalesce(e,'(null)'), coalesce(o,'(null)')); end if; end $c$;

create function pg_temp.aguardando(p_id uuid) returns integer language sql as $f$
  select coalesce((select count(*)::integer
    from jsonb_array_elements(public.app_devolutivas_aguardando()) d
   where (d->>'id')::uuid = p_id), 0);
$f$;

create function pg_temp.pendente(p_id uuid) returns integer language sql as $f$
  select coalesce((select count(*)::integer
    from jsonb_array_elements(public.app_devolutivas_pendentes()) d
   where (d->>'id')::uuid = p_id), 0);
$f$;

do $t$
declare
  v_aula integer; v_unidade uuid; v_aluno integer; v_skill uuid;
  v_reg uuid; v_id uuid; v_reg2 uuid; v_id2 uuid;
  a jsonb; v_tok uuid; v_res jsonb;
  v_auth_dono uuid; v_auth_outro uuid; v_prof_outro integer; v_usuario_outro integer;
  v_dono_ve integer; v_outro_ve integer; v_ok_outro text;
  v_ok_dono text; v_na_lista_incerta integer; v_ok_marcar_incerta text;
  v_expiradas integer; v_incertas integer;
begin
  select u.auth_user_id into v_auth_dono
    from public.professores p join public.usuarios u on u.id = p.usuario_id
   where p.id = 25 and u.auth_user_id is not null limit 1;
  if v_auth_dono is null then
    insert into _falhas values ('setup','auth_user do professor 25','nenhum'); return;
  end if;

  select p.id, u.auth_user_id into v_prof_outro, v_auth_outro
    from public.professores p join public.usuarios u on u.id = p.usuario_id
   where p.id <> 25 and u.auth_user_id is not null and coalesce(p.ativo,true) limit 1;
  if v_auth_outro is null then
    select id into v_prof_outro from public.professores
     where usuario_id is null and coalesce(ativo,true) and id <> 25 order by id limit 1;
    v_auth_outro := gen_random_uuid();
    insert into public.usuarios (nome, email, ativo, auth_user_id)
    values ('Professor Vizinho (teste)',
            'vizinho.' || replace(v_auth_outro::text,'-','') || '@exemplo.invalido', true, v_auth_outro)
    returning id into v_usuario_outro;
    update public.professores set usuario_id = v_usuario_outro where id = v_prof_outro;
  end if;

  select a2.id, a2.unidade_id into v_aula, v_unidade
    from public.aulas_emusys a2 where a2.professor_id=25 order by a2.id desc limit 1;
  select id into v_aluno from public.alunos where status='ativo' order by id limit 1;
  select id into v_skill from public.fabio_skills where nome='devolutiva_aula' and ativa;

  -- ===== uma devolutiva PRESA esperando decisao =====
  insert into public.fabio_registros_aula
    (aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos, status, origem, confirmado_em)
  values (v_aula, v_unidade, 25, v_aluno, null, 'C',
          '{"progresso":"tocou junto","presenca":"presente"}'::jsonb, 'gravado_emusys','app', now())
  returning id into v_reg;
  perform public.fabio_enfileirar_devolutivas(v_reg);
  select id into v_id from public.fabio_devolutivas where registro_fatia_id = v_reg;
  a := public.fabio_devolutiva_claim('worker-teste-025', 10, 20);
  v_tok := (a->>'lease_token')::uuid;
  perform public.fabio_devolutiva_aguardar_destinatario(v_id, v_tok, 'idade impossivel: 0 anos');

  perform set_config('request.jwt.claims', json_build_object('sub', v_auth_dono)::text, true);
  set local role authenticated;
  v_dono_ve := pg_temp.aguardando(v_id);
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', v_auth_outro)::text, true);
  set local role authenticated;
  v_outro_ve := pg_temp.aguardando(v_id);
  v_res := public.app_devolutiva_definir_destinatario(v_id, 'aluno');
  v_ok_outro := v_res->>'ok';
  reset role;

  perform pg_temp.checar('1. o dono ve a presa','1', v_dono_ve::text);
  perform pg_temp.checar('2. OUTRO professor NAO ve a presa','0', v_outro_ve::text);
  perform pg_temp.checar('3. OUTRO nao decide por ele','false', v_ok_outro);
  perform pg_temp.checar('4. status intacto apos tentativa alheia','aguardando_destinatario',
    (select status from public.fabio_devolutivas where id=v_id));

  -- ===== o dono decide: volta pra fila =====
  perform set_config('request.jwt.claims', json_build_object('sub', v_auth_dono)::text, true);
  set local role authenticated;
  v_res := public.app_devolutiva_definir_destinatario(v_id, 'responsavel');
  v_ok_dono := v_res->>'ok';
  reset role;

  perform pg_temp.checar('5. dono decide','true', v_ok_dono);
  perform pg_temp.checar('6. volta pra fila como pendente','pendente',
    (select status from public.fabio_devolutivas where id=v_id));
  perform pg_temp.checar('7. override gravado','responsavel',
    (select destinatario_override from public.fabio_devolutivas where id=v_id));
  perform pg_temp.checar('8. quem decidiu fica registrado','25',
    (select destinatario_decidido_por::text from public.fabio_devolutivas where id=v_id));
  perform pg_temp.checar('9. aguardando_desde limpo','true',
    (select (aguardando_desde is null)::text from public.fabio_devolutivas where id=v_id));
  perform pg_temp.checar('10. o claim pega ela de novo','1',
    (select count(*)::text from jsonb_array_elements(
       public.fabio_devolutiva_claim('worker-teste-025b', 10, 20)->'itens') e
      where (e->>'id')::uuid = v_id));

  -- ===== destinatario invalido e ERRO =====
  update public.fabio_devolutivas set status='aguardando_destinatario', aguardando_desde=now() where id=v_id;
  perform set_config('request.jwt.claims', json_build_object('sub', v_auth_dono)::text, true);
  set local role authenticated;
  begin
    perform public.app_devolutiva_definir_destinatario(v_id, 'a_diretoria');
    v_ok_dono := 'passou sem erro';
  exception when others then
    v_ok_dono := 'levantou';
  end;
  reset role;
  -- A garantia real nao e "a funcao levantou": e que o valor invalido NAO
  -- ENTRA. Ha defesa em duas camadas -- a allowlist na funcao (mensagem boa
  -- pro app) e o CHECK fabio_devolutivas_override_check na tabela (a cerca de
  -- verdade). Por isso o mutante que remove a allowlist SOBREVIVE de
  -- proposito: a garantia continua de pe pelo CHECK. O que este passo afirma
  -- e o que importa em qualquer um dos caminhos.
  perform pg_temp.checar('11. destinatario invalido nao entra','levantou', v_ok_dono);
  perform pg_temp.checar('11b. override continua limpo depois da tentativa','true',
    (select (destinatario_override is null or destinatario_override in ('responsavel','aluno'))::text
       from public.fabio_devolutivas where id=v_id));

  -- ===== expiracao: o que ninguem decidiu sai =====
  update public.fabio_devolutivas
     set status='aguardando_destinatario', aguardando_desde = now() - interval '8 days'
   where id = v_id;
  v_expiradas := public.fabio_devolutiva_expirar_aguardando(7);
  perform pg_temp.checar('12. expira o que passou do prazo','descartada',
    (select status from public.fabio_devolutivas where id=v_id));
  perform pg_temp.checar('13. motivo da expiracao fica escrito','true',
    (select (erro like '%expirou apos 7 dias%')::text from public.fabio_devolutivas where id=v_id));

  -- dentro do prazo NAO expira
  update public.fabio_devolutivas
     set status='aguardando_destinatario', aguardando_desde = now() - interval '2 days', erro=null
   where id = v_id;
  perform public.fabio_devolutiva_expirar_aguardando(7);
  perform pg_temp.checar('14. dentro do prazo NAO expira','aguardando_destinatario',
    (select status from public.fabio_devolutivas where id=v_id));

  -- ===== entrega incerta =====
  insert into public.fabio_registros_aula
    (aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos, status, origem, confirmado_em)
  values (v_aula, v_unidade, 25, v_aluno, null, 'C',
          '{"progresso":"outro registro","presenca":"presente"}'::jsonb, 'gravado_emusys','app', now())
  returning id into v_reg2;
  perform public.fabio_enfileirar_devolutivas(v_reg2);
  select id into v_id2 from public.fabio_devolutivas where registro_fatia_id = v_reg2;
  update public.fabio_devolutivas
     set status='oferecida', texto_normal='Texto ja oferecido.', destinatario='responsavel',
         destinatario_nome='Mae', oferecida_em = now() - interval '5 days'
   where id = v_id2;

  v_incertas := public.fabio_devolutiva_marcar_entrega_incerta(3);
  perform pg_temp.checar('15. oferecida ha dias sem "ja mandei" vira incerta','entrega_incerta',
    (select status from public.fabio_devolutivas where id=v_id2));

  -- A GARANTIA QUE MAIS IMPORTA AQUI: continua na tela dele.
  perform set_config('request.jwt.claims', json_build_object('sub', v_auth_dono)::text, true);
  set local role authenticated;
  v_na_lista_incerta := pg_temp.pendente(v_id2);
  v_res := public.app_devolutiva_marcar(v_id2, 'enviada');
  v_ok_marcar_incerta := v_res->>'ok';
  reset role;
  perform pg_temp.checar('16. entrega_incerta CONTINUA na tela do professor','1', v_na_lista_incerta::text);
  perform pg_temp.checar('17. e ele ainda consegue dizer "ja mandei"','true', v_ok_marcar_incerta);
  perform pg_temp.checar('18. o "ja mandei" fecha mesmo estando incerta','true',
    (select (envio_confirmado_em is not null)::text from public.fabio_devolutivas where id=v_id2));

  -- quem JA confirmou nao vira incerta
  update public.fabio_devolutivas
     set status='oferecida', oferecida_em = now() - interval '9 days', envio_confirmado_em = now()
   where id = v_id2;
  perform public.fabio_devolutiva_marcar_entrega_incerta(3);
  perform pg_temp.checar('19. quem ja confirmou NAO vira incerta','oferecida',
    (select status from public.fabio_devolutivas where id=v_id2));

exception when others then
  reset role;
  insert into _falhas values ('excecao','sem excecao', sqlerrm);
end $t$;

reset role;

select json_build_object('teste','025-devolutiva-destinatario-e-entrega-incerta',
  'falhas',(select count(*) from _falhas),
  'detalhe', coalesce((select json_agg(json_build_object('passo',passo,'esperado',esperado,'obtido',obtido)) from _falhas),'[]'::json)) as resumo;
