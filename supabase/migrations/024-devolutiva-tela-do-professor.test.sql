-- Teste da 024 — a tela do professor.
--
-- Rodar com: npm run teste:024
--
-- A GARANTIA QUE ESTE TESTE EXISTE PARA PROTEGER
-- Um professor NAO pode ler nem editar a devolutiva de outro. Nao e questao
-- de organizacao: e texto sobre a aula de uma crianca especifica, com o nome
-- dela e do responsavel. Se o filtro por professor cair, um professor ve a
-- familia do aluno de outro.
--
-- fn_professor_do_usuario() resolve por auth.uid(). Aqui isso e simulado com
-- `set local request.jwt.claims`, que e como o Supabase entrega o JWT ao
-- Postgres -- o teste exercita o MESMO caminho que o app usa.
--
-- ARMADILHA QUE JA MORDEU ESTE ARQUIVO
-- `_falhas` e temp table criada pelo role original. Sob `set local role
-- authenticated` o INSERT nela e NEGADO. Chamar pg_temp.checar() com o role
-- trocado faz o erro de permissao mascarar a divergencia real -- e se houver
-- um `exception when others then null` por perto, a falha SOME. Por isso o
-- padrao aqui e sempre: captura o resultado sob authenticated numa variavel,
-- `reset role`, e SO ENTAO checa.

create temp table _falhas(passo text, esperado text, obtido text) on commit drop;
create function pg_temp.checar(p text, e text, o text) returns void language plpgsql as $c$
begin if e is distinct from o then insert into _falhas values (p, coalesce(e,'(null)'), coalesce(o,'(null)')); end if; end $c$;

create function pg_temp.tem(p_id uuid) returns integer language sql as $f$
  select coalesce((select count(*)::integer
    from jsonb_array_elements(public.app_devolutivas_pendentes()) d
   where (d->>'id')::uuid = p_id), 0);
$f$;

do $t$
declare
  v_aula integer; v_unidade uuid; v_aluno integer; v_skill uuid;
  v_reg uuid; v_id uuid; a jsonb; v_tok uuid; v_res jsonb;
  v_auth_dono uuid; v_auth_outro uuid; v_prof_outro integer; v_prof_outro_usuario integer;
  -- tudo o que for observado sob `authenticated` passa por estas variaveis
  v_dono_ve integer; v_outro_ve integer; v_depois_enviada integer;
  v_ok_carimbo text; v_motivo_carimbo text; v_ok_edicao text; v_ok_dono_edita text;
  v_erro_acao boolean := false; v_erro_vazio boolean := false;
begin
  select u.auth_user_id into v_auth_dono
    from public.professores p join public.usuarios u on u.id = p.usuario_id
   where p.id = 25 and u.auth_user_id is not null limit 1;
  if v_auth_dono is null then
    insert into _falhas values ('setup','auth_user do professor 25','nenhum'); return;
  end if;

  -- Hoje SO o Matheus (professor 25) tem login: 43 professores ativos estao
  -- sem usuario vinculado. Sem um segundo professor autenticado nao da para
  -- testar o isolamento, que e a garantia principal. Entao ele e criado AQUI
  -- DENTRO -- o runner e dono da transacao e da ROLLBACK, e o recibo de
  -- linhas vivas + digest de schema no fim prova que nada sobrou.
  select p.id, u.auth_user_id into v_prof_outro, v_auth_outro
    from public.professores p join public.usuarios u on u.id = p.usuario_id
   where p.id <> 25 and u.auth_user_id is not null and coalesce(p.ativo,true) limit 1;
  if v_auth_outro is null then
    select id into v_prof_outro from public.professores
     where usuario_id is null and coalesce(ativo,true) and id <> 25 order by id limit 1;
    if v_prof_outro is null then
      insert into _falhas values ('setup','um segundo professor','nenhum'); return;
    end if;
    v_auth_outro := gen_random_uuid();
    insert into public.usuarios (nome, email, ativo, auth_user_id)
    values ('Professor Vizinho (teste)',
            'vizinho.teste.' || replace(v_auth_outro::text,'-','') || '@exemplo.invalido',
            true, v_auth_outro)
    returning id into v_prof_outro_usuario;
    update public.professores set usuario_id = v_prof_outro_usuario where id = v_prof_outro;
  end if;

  -- ===== uma devolutiva do professor 25 =====
  select a2.id, a2.unidade_id into v_aula, v_unidade
    from public.aulas_emusys a2 where a2.professor_id=25 order by a2.id desc limit 1;
  select id into v_aluno from public.alunos where status='ativo' order by id limit 1;
  select id into v_skill from public.fabio_skills where nome='devolutiva_aula' and ativa;

  insert into public.fabio_registros_aula
    (aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos, status, origem, confirmado_em)
  values (v_aula, v_unidade, 25, v_aluno, null, 'C',
          '{"progresso":"segurou a baqueta certo","presenca":"presente"}'::jsonb,
          'gravado_emusys','app', now())
  returning id into v_reg;
  perform public.fabio_enfileirar_devolutivas(v_reg);
  select id into v_id from public.fabio_devolutivas where registro_fatia_id = v_reg;
  a := public.fabio_devolutiva_claim('worker-teste-024', 10, 20);
  v_tok := (a->>'lease_token')::uuid;
  perform public.fabio_devolutiva_gerada(v_id, v_tok,
    'Texto original do Fabio.', 'apoio de casa', 'responsavel', 'Mae', 9, v_skill, 1);

  -- ===== o DONO ve =====
  perform set_config('request.jwt.claims', json_build_object('sub', v_auth_dono)::text, true);
  set local role authenticated;
  v_dono_ve := pg_temp.tem(v_id);
  reset role;

  -- ===== O OUTRO nao ve, nao carimba, nao edita =====
  perform set_config('request.jwt.claims', json_build_object('sub', v_auth_outro)::text, true);
  set local role authenticated;
  v_outro_ve := pg_temp.tem(v_id);
  v_res := public.app_devolutiva_marcar(v_id, 'copiada');
  v_ok_carimbo := v_res->>'ok';
  v_motivo_carimbo := v_res->>'motivo';
  v_res := public.app_devolutiva_salvar_texto(v_id, 'TEXTO INVASOR');
  v_ok_edicao := v_res->>'ok';
  reset role;

  perform pg_temp.checar('1. o dono ve a devolutiva dele','1', v_dono_ve::text);
  perform pg_temp.checar('2. OUTRO professor NAO ve','0', v_outro_ve::text);
  perform pg_temp.checar('3. OUTRO nao consegue carimbar','false', v_ok_carimbo);
  perform pg_temp.checar('4. motivo explicito','nao_encontrada_ou_nao_e_sua', v_motivo_carimbo);
  perform pg_temp.checar('5. OUTRO nao consegue editar','false', v_ok_edicao);
  perform pg_temp.checar('6. texto NAO foi alterado pelo invasor','Texto original do Fabio.',
    (select texto_normal from public.fabio_devolutivas where id = v_id));

  -- ===== o dono edita e carimba =====
  perform set_config('request.jwt.claims', json_build_object('sub', v_auth_dono)::text, true);
  set local role authenticated;
  v_res := public.app_devolutiva_salvar_texto(v_id, 'Texto que o professor ajustou.');
  v_ok_dono_edita := v_res->>'ok';
  perform public.app_devolutiva_marcar(v_id, 'copiada');
  perform public.app_devolutiva_marcar(v_id, 'compartilhada');
  reset role;

  perform pg_temp.checar('7. dono edita','true', v_ok_dono_edita);
  perform pg_temp.checar('8. texto novo gravado','Texto que o professor ajustou.',
    (select texto_normal from public.fabio_devolutivas where id = v_id));
  perform pg_temp.checar('9. editada_em carimbado','true',
    (select (editada_em is not null)::text from public.fabio_devolutivas where id = v_id));
  perform pg_temp.checar('10. copiada_em carimbado','true',
    (select (copiada_em is not null)::text from public.fabio_devolutivas where id = v_id));
  perform pg_temp.checar('11. compartilhada_em carimbado','true',
    (select (compartilhada_em is not null)::text from public.fabio_devolutivas where id = v_id));

  -- ===== "mandei" tira da lista =====
  perform set_config('request.jwt.claims', json_build_object('sub', v_auth_dono)::text, true);
  set local role authenticated;
  perform public.app_devolutiva_marcar(v_id, 'enviada');
  v_depois_enviada := pg_temp.tem(v_id);

  -- ===== erro tem que ser ERRO, nao no-op silencioso =====
  -- As duas capturas gravam em VARIAVEL, nunca em _falhas: sob este role o
  -- insert na temp table seria negado e o erro de permissao mascararia o
  -- resultado real.
  begin
    perform public.app_devolutiva_marcar(v_id, 'apagar_tudo');
  exception when others then
    v_erro_acao := true;
  end;
  begin
    perform public.app_devolutiva_salvar_texto(v_id, '   ');
  exception when others then
    v_erro_vazio := true;
  end;
  reset role;

  perform pg_temp.checar('12. depois de enviada sai da lista','0', v_depois_enviada::text);
  perform pg_temp.checar('13. envio_confirmado_em carimbado','true',
    (select (envio_confirmado_em is not null)::text from public.fabio_devolutivas where id = v_id));
  perform pg_temp.checar('14. acao desconhecida levanta erro','true', v_erro_acao::text);
  perform pg_temp.checar('15. salvar texto vazio levanta erro','true', v_erro_vazio::text);

exception when others then
  reset role;
  insert into _falhas values ('excecao','sem excecao', sqlerrm);
end $t$;

reset role;

select json_build_object('teste','024-devolutiva-tela-do-professor',
  'falhas',(select count(*) from _falhas),
  'detalhe', coalesce((select json_agg(json_build_object('passo',passo,'esperado',esperado,'obtido',obtido)) from _falhas),'[]'::json)) as resumo;
