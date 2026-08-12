-- Contrato da ficha manual. O runner envolve tudo em transacao e prova o rollback.

create temporary table _registro_manual_res(
  passo text,
  ok boolean,
  esperado text,
  obtido text
) on commit drop;

create or replace function pg_temp.checar_manual(
  p_passo text,
  p_ok boolean,
  p_esperado text,
  p_obtido text
) returns void
language plpgsql
as $function$
begin
  insert into _registro_manual_res values (p_passo, coalesce(p_ok, false), p_esperado, p_obtido);
end
$function$;

do $function$
declare
  v_tag text := 'zmanual' || (txid_current() % 100000000)::text;
  v_unidade uuid := gen_random_uuid();
  v_auth uuid := gen_random_uuid();
  v_auth_outro uuid := gen_random_uuid();
  v_usuario integer;
  v_usuario_outro integer;
  v_professor integer;
  v_professor_outro integer;
  v_aluno_a integer;
  v_aluno_b integer;
  v_aluno_c integer;
  v_aula integer;
  v_aula_a integer;
  v_aula_b integer;
  v_aula_c integer;
  v_emusys integer := 910000000 + (txid_current() % 80000000)::integer;
  v_roster bigint := -8800000000000000000::bigint + txid_current() * 10;
  v_inicio timestamptz := date_trunc('hour', now()) - interval '1 day';
  v_audio_raiz uuid;
  v_aberto jsonb;
  v_aberto_2 jsonb;
  v_salvo jsonb;
  v_preparado jsonb;
  v_confirmado jsonb;
  v_raiz uuid;
  v_fatia_a uuid;
  v_fatia_b uuid;
  v_presencas_antes bigint;
  v_campos_antes jsonb;
begin
  if to_regprocedure('public.app_abrir_rascunho_manual(integer)') is null
     or to_regprocedure('public.app_salvar_rascunho_manual(uuid,integer,jsonb,jsonb)') is null
     or to_regprocedure('public.app_preparar_rascunho_manual(uuid,integer)') is null then
    perform pg_temp.checar_manual(
      'as tres portas manuais existem', false,
      'app_abrir/app_salvar/app_preparar', 'funcao ausente'
    );
    return;
  end if;

  perform pg_temp.checar_manual(
    'colunas retrocompativeis existem',
    exists(select 1 from information_schema.columns where table_schema='public' and table_name='fabio_registros_aula' and column_name='modo_entrada' and column_default ilike '%audio%')
      and exists(select 1 from information_schema.columns where table_schema='public' and table_name='fabio_registros_aula' and column_name='versao' and column_default like '%1%'),
    'modo_entrada default audio e versao default 1',
    (select coalesce(string_agg(column_name || '=' || coalesce(column_default,'NULL'), ', ' order by column_name),'ausentes') from information_schema.columns where table_schema='public' and table_name='fabio_registros_aula' and column_name in ('modo_entrada','versao'))
  );

  perform pg_temp.checar_manual(
    'somente authenticated executa as portas publicas',
    has_function_privilege('authenticated','public.app_abrir_rascunho_manual(integer)','EXECUTE')
      and has_function_privilege('authenticated','public.app_salvar_rascunho_manual(uuid,integer,jsonb,jsonb)','EXECUTE')
      and has_function_privilege('authenticated','public.app_preparar_rascunho_manual(uuid,integer)','EXECUTE')
      and not has_function_privilege('anon','public.app_abrir_rascunho_manual(integer)','EXECUTE')
      and not has_function_privilege('anon','public.app_salvar_rascunho_manual(uuid,integer,jsonb,jsonb)','EXECUTE')
      and not has_function_privilege('anon','public.app_preparar_rascunho_manual(uuid,integer)','EXECUTE'),
    'authenticated=true, anon=false', 'ACL das RPCs'
  );

  insert into public.unidades(id,nome,codigo) values (v_unidade,v_tag,v_tag);
  insert into public.usuarios(nome,email,unidade_id,perfil,auth_user_id,ativo)
  values (v_tag, v_tag || '@example.invalid', v_unidade, 'professor', v_auth, true)
  returning id into v_usuario;
  insert into public.professores(nome,ativo,usuario_id)
  values (v_tag,true,v_usuario) returning id into v_professor;
  insert into public.usuarios(nome,email,unidade_id,perfil,auth_user_id,ativo)
  values (v_tag || ' outro', v_tag || '.outro@example.invalid', v_unidade, 'professor', v_auth_outro, true)
  returning id into v_usuario_outro;
  insert into public.professores(nome,ativo,usuario_id)
  values (v_tag || ' outro',true,v_usuario_outro) returning id into v_professor_outro;
  insert into public.alunos(nome,unidade_id,professor_atual_id)
  values (v_tag || ' Arthur',v_unidade,v_professor) returning id into v_aluno_a;
  insert into public.alunos(nome,unidade_id,professor_atual_id)
  values (v_tag || ' Nicolas',v_unidade,v_professor) returning id into v_aluno_b;

  insert into public.aulas_emusys(emusys_id,unidade_id,professor_id,data_aula,data_hora_inicio,data_hora_fim,tipo,curso_nome,turma_nome,cancelada)
  values (v_emusys+1,v_unidade,v_professor,v_inicio::date,v_inicio,v_inicio+interval '50 minutes','turma','Teclado T',v_tag,false)
  returning id into v_aula;
  insert into public.aulas_emusys(emusys_id,unidade_id,professor_id,data_aula,data_hora_inicio,data_hora_fim,tipo,curso_nome,turma_nome,cancelada)
  values (v_emusys+2,v_unidade,v_professor,v_inicio::date,v_inicio,v_inicio+interval '50 minutes','individual','Teclado T',v_tag,false)
  returning id into v_aula_a;
  insert into public.aulas_emusys(emusys_id,unidade_id,professor_id,data_aula,data_hora_inicio,data_hora_fim,tipo,curso_nome,turma_nome,cancelada)
  values (v_emusys+3,v_unidade,v_professor,v_inicio::date,v_inicio,v_inicio+interval '50 minutes','individual','Teclado T',v_tag,false)
  returning id into v_aula_b;

  insert into public.aula_alunos_emusys(id,aula_emusys_id,unidade_id,aluno_chave,aluno_id,aluno_nome,aluno_nome_normalizado)
  values
    (v_roster+1,v_aula,v_unidade,v_tag||'_a',v_aluno_a,v_tag||' Arthur',lower(v_tag||' Arthur')),
    (v_roster+2,v_aula,v_unidade,v_tag||'_b',v_aluno_b,v_tag||' Nicolas',lower(v_tag||' Nicolas')),
    (v_roster+3,v_aula_a,v_unidade,v_tag||'_ia',v_aluno_a,v_tag||' Arthur',lower(v_tag||' Arthur')),
    (v_roster+4,v_aula_b,v_unidade,v_tag||'_ib',v_aluno_b,v_tag||' Nicolas',lower(v_tag||' Nicolas'));

  -- Um preview de audio pode coexistir; a ficha manual apenas o anuncia.
  insert into public.fabio_registros_aula(aula_id,unidade_id,professor_id,molde,campos,status,origem,modo_entrada)
  values (v_aula,v_unidade,v_professor,'C','{}','aguardando_confirmacao','app','audio')
  returning id into v_audio_raiz;

  perform set_config('request.jwt.claims',json_build_object('sub',v_auth,'role','authenticated')::text,true);
  select count(*) into v_presencas_antes from public.aluno_presenca where aluno_id in (v_aluno_a,v_aluno_b);

  v_aberto := public.app_abrir_rascunho_manual(v_aula);
  v_raiz := (v_aberto->'tronco'->>'id')::uuid;
  select id into v_fatia_a from public.fabio_registros_aula where parent_id=v_raiz and aluno_id=v_aluno_a;
  select id into v_fatia_b from public.fabio_registros_aula where parent_id=v_raiz and aluno_id=v_aluno_b;

  perform pg_temp.checar_manual(
    'abrir cria raiz e uma fatia por aluno sem presenca',
    (v_aberto->'tronco'->>'modo_entrada')='manual'
      and (v_aberto->'tronco'->>'status')='rascunho'
      and jsonb_array_length(v_aberto->'fatias')=2
      and (select count(*) from public.aluno_presenca where aluno_id in (v_aluno_a,v_aluno_b))=v_presencas_antes,
    'manual, rascunho, 2 fatias, 0 presenca nova', coalesce(v_aberto::text,'NULL')
  );
  perform pg_temp.checar_manual(
    'abrir informa audio independente',
    (v_aberto->>'audio_aberto_registro_id')::uuid=v_audio_raiz,
    v_audio_raiz::text, coalesce(v_aberto->>'audio_aberto_registro_id','NULL')
  );

  v_aberto_2 := public.app_abrir_rascunho_manual(v_aula);
  perform pg_temp.checar_manual(
    'abrir e idempotente na mesma aula',
    (v_aberto_2->'tronco'->>'id')::uuid=v_raiz
      and (select count(*) from public.fabio_registros_aula where professor_id=v_professor and aula_id=v_aula and parent_id is null and modo_entrada='manual' and status in ('rascunho','aguardando_confirmacao'))=1,
    v_raiz::text, coalesce(v_aberto_2->'tronco'->>'id','NULL')
  );

  delete from public.aula_alunos_emusys where id=v_roster+2;
  begin
    perform public.app_abrir_rascunho_manual(v_aula);
    perform pg_temp.checar_manual('retomar recusa aluno removido do roster',false,'roster_divergente','abriu');
  exception when others then
    perform pg_temp.checar_manual(
      'retomar recusa aluno removido do roster',
      position('roster_divergente' in sqlerrm)>0,
      'roster_divergente',sqlerrm
    );
  end;
  insert into public.aula_alunos_emusys(
    id,aula_emusys_id,unidade_id,aluno_chave,aluno_id,aluno_nome,aluno_nome_normalizado
  ) values (
    v_roster+2,v_aula,v_unidade,v_tag||'_b',v_aluno_b,v_tag||' Nicolas',lower(v_tag||' Nicolas')
  );

  insert into public.alunos(nome,unidade_id,professor_atual_id)
  values (v_tag || ' Caio',v_unidade,v_professor) returning id into v_aluno_c;
  insert into public.aulas_emusys(
    emusys_id,unidade_id,professor_id,data_aula,data_hora_inicio,data_hora_fim,
    tipo,curso_nome,turma_nome,cancelada
  ) values (
    v_emusys+4,v_unidade,v_professor,v_inicio::date,v_inicio,v_inicio+interval '50 minutes',
    'individual','Teclado T',v_tag,false
  ) returning id into v_aula_c;
  insert into public.aula_alunos_emusys(
    id,aula_emusys_id,unidade_id,aluno_chave,aluno_id,aluno_nome,aluno_nome_normalizado
  ) values
    (v_roster+5,v_aula,v_unidade,v_tag||'_c',v_aluno_c,v_tag||' Caio',lower(v_tag||' Caio')),
    (v_roster+6,v_aula_c,v_unidade,v_tag||'_ic',v_aluno_c,v_tag||' Caio',lower(v_tag||' Caio'));
  v_aberto_2 := public.app_abrir_rascunho_manual(v_aula);
  perform pg_temp.checar_manual(
    'retomar inclui aluno sincronizado depois da primeira abertura',
    jsonb_array_length(v_aberto_2->'fatias')=3
      and exists(select 1 from public.fabio_registros_aula where parent_id=v_raiz and aluno_id=v_aluno_c)
      and (v_aberto_2->'tronco'->>'versao')::integer=2,
    '3 fatias incluindo novo roster e raiz versao 2',coalesce(v_aberto_2::text,'NULL')
  );
  delete from public.fabio_registros_aula where parent_id=v_raiz and aluno_id=v_aluno_c;
  delete from public.aula_alunos_emusys where id=v_roster+5;
  update public.fabio_registros_aula set versao=1 where id=v_raiz;

  perform set_config('request.jwt.claims',json_build_object('sub',v_auth_outro,'role','authenticated')::text,true);
  begin
    perform public.app_abrir_rascunho_manual(v_aula);
    perform pg_temp.checar_manual('outro professor nao abre a aula',false,'aula_nao_pertence_ao_professor','abriu');
  exception when others then
    perform pg_temp.checar_manual('outro professor nao abre a aula',position('aula_nao_pertence_ao_professor' in sqlerrm)>0,'aula_nao_pertence_ao_professor',sqlerrm);
  end;
  perform set_config('request.jwt.claims',json_build_object('sub',v_auth,'role','authenticated')::text,true);

  v_salvo := public.app_salvar_rascunho_manual(
    v_raiz, 1, '{}'::jsonb,
    jsonb_build_array(
      jsonb_build_object('id',v_fatia_a,'campos',jsonb_build_object('repertorio','Astrobot','atividades','Ate a metade')),
      jsonb_build_object('id',v_fatia_b,'campos',jsonb_build_object('repertorio','Meu Lanchinho','objetivo','Coordenacao'))
    )
  );
  perform pg_temp.checar_manual(
    'salvar persiste atomico e incrementa versoes',
    (v_salvo->'tronco'->>'versao')::integer=2
      and (select bool_and(versao=2) from public.fabio_registros_aula where parent_id=v_raiz)
      and (select campos->>'repertorio' from public.fabio_registros_aula where id=v_fatia_a)='Astrobot',
    'versao 2 e repertorio Astrobot', coalesce(v_salvo::text,'NULL')
  );

  select campos into v_campos_antes from public.fabio_registros_aula where id=v_fatia_a;
  begin
    perform public.app_salvar_rascunho_manual(
      v_raiz,1,'{}',jsonb_build_array(
        jsonb_build_object('id',v_fatia_a,'campos',jsonb_build_object('repertorio','PERDIDO')),
        jsonb_build_object('id',v_fatia_b,'campos','{}'::jsonb)
      )
    );
    perform pg_temp.checar_manual('versao antiga nao sobrescreve',false,'conflito_de_versao','gravou');
  exception when others then
    perform pg_temp.checar_manual(
      'versao antiga nao sobrescreve',
      position('conflito_de_versao' in sqlerrm)>0 and (select campos from public.fabio_registros_aula where id=v_fatia_a)=v_campos_antes,
      'conflito e campos intactos',sqlerrm
    );
  end;

  begin
    perform public.app_salvar_rascunho_manual(
      v_raiz,2,'{}',jsonb_build_array(
        jsonb_build_object('id',v_fatia_a,'campos',jsonb_build_object('presenca','ausente')),
        jsonb_build_object('id',v_fatia_b,'campos','{}'::jsonb)
      )
    );
    perform pg_temp.checar_manual('campos internos sao recusados',false,'campo_manual_invalido','gravou');
  exception when others then
    perform pg_temp.checar_manual('campos internos sao recusados',position('campo_manual_invalido' in sqlerrm)>0,'campo_manual_invalido',sqlerrm);
  end;

  begin
    perform public.app_salvar_rascunho_manual(
      v_raiz,2,'{}',jsonb_build_array(jsonb_build_object('id',v_fatia_a,'campos','{}'::jsonb))
    );
    perform pg_temp.checar_manual('payload parcial de fatias e recusado',false,'fatias_divergentes','gravou');
  exception when others then
    perform pg_temp.checar_manual('payload parcial de fatias e recusado',position('fatias_divergentes' in sqlerrm)>0,'fatias_divergentes',sqlerrm);
  end;

  v_preparado := public.app_preparar_rascunho_manual(v_raiz,2);
  perform pg_temp.checar_manual(
    'preparar promove para preview sem marcar presenca',
    (v_preparado->'tronco'->>'status')='aguardando_confirmacao'
      and (select bool_and(status='aguardando_confirmacao') from public.fabio_registros_aula where parent_id=v_raiz)
      and (select count(*) from public.aluno_presenca where aluno_id in (v_aluno_a,v_aluno_b))=v_presencas_antes,
    'aguardando_confirmacao e 0 presenca nova',coalesce(v_preparado::text,'NULL')
  );

  update public.fabio_registros_aula
     set campos=campos||jsonb_build_object('presenca','ausente')
   where id=v_fatia_a;
  v_salvo := public.app_salvar_rascunho_manual(
    v_raiz,3,'{}',jsonb_build_array(
      jsonb_build_object('id',v_fatia_a,'campos',jsonb_build_object('repertorio','Astrobot revisado')),
      jsonb_build_object('id',v_fatia_b,'campos',jsonb_build_object('repertorio','Meu Lanchinho'))
    )
  );
  perform pg_temp.checar_manual(
    'edicao pedagogica versionada preserva presenca explicita',
    (select campos->>'presenca' from public.fabio_registros_aula where id=v_fatia_a)='ausente'
      and (v_salvo->'tronco'->>'versao')::integer=4,
    'presenca ausente e versao 4',coalesce(v_salvo::text,'NULL')
  );

  -- Para provar a salvaguarda canônica, removemos o sinal local e deixamos a
  -- falta somente na fonte de presença humana. A confirmação deve reencontrá-la.
  update public.fabio_registros_aula set campos=campos-'presenca' where id=v_fatia_a;
  insert into public.aluno_presenca(
    aluno_id,professor_id,unidade_id,data_aula,aula_emusys_id,
    status,status_presenca,respondido_por
  ) values (
    v_aluno_a,v_professor,v_unidade,v_inicio::date,v_aula_a,
    'ausente','falta','manual'
  );
  v_preparado := public.app_preparar_rascunho_manual(v_raiz,4);
  v_confirmado := public.app_confirmar_registro(v_raiz,'novo');
  perform pg_temp.checar_manual(
    'confirmacao preserva falta humana e carimba origem do la teacher',
    (v_confirmado->>'ausentes_puladas')::integer=1
      and (v_confirmado->>'gravadas')::integer=1
      and (select campos->>'presenca' from public.fabio_registros_aula where id=v_fatia_a)='ausente'
      and (select status_presenca from public.aluno_presenca where aluno_id=v_aluno_a and aula_emusys_id=v_aula_a)='falta'
      and exists(
        select 1 from public.aluno_presenca
         where aluno_id=v_aluno_b and respondido_por='professor_la_teacher'
      )
      and exists(
        select 1 from public.aula_registros_fabio_log
         where aula_id=v_aula_b and origem='texto'
      ),
    '1 falta preservada, 1 aula gravada, presenca LA Teacher e conteudo texto',
    coalesce(v_confirmado::text,'NULL')
  );
  begin
    perform public.fn_responder_presenca_core(v_professor,v_fatia_b,'ausente');
    perform pg_temp.checar_manual('presenca atrasada nao entra depois da confirmacao',false,'status recusado','gravou');
  exception when others then
    perform pg_temp.checar_manual(
      'presenca atrasada nao entra depois da confirmacao',
      position('nao aceita mais resposta de presenca' in sqlerrm)>0,
      'status recusado',sqlerrm
    );
  end;
end
$function$;

select json_build_object(
  'falhas', count(*) filter (where not ok),
  'detalhe', coalesce(json_agg(json_build_object('passo',passo,'esperado',esperado,'obtido',obtido) order by passo) filter (where not ok),'[]'::json)
) as resumo
from _registro_manual_res;
