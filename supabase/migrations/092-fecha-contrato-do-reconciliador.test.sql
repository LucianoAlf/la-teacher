-- Contrato RED/GREEN da 092. O runner envolve migration + teste em
-- BEGIN/ROLLBACK; os fixtures abaixo nunca ficam no banco vivo.

create temporary table _fabio_092_res(caso text, ok boolean, detalhe text)
on commit drop;

create or replace function pg_temp.checar_092(p_caso text, p_ok boolean, p_detalhe text)
returns void
language plpgsql
as $$
begin
  insert into _fabio_092_res values (p_caso, coalesce(p_ok, false), p_detalhe);
end
$$;

do $$
declare
  v_resultado text;
  v_def text;
  v_prof integer;
  v_acao_terminal uuid;
  v_acao_ativa uuid;
  v_path text := 'whatsapp/ZZTESTE-092/limpeza.ogg';
  v_prova jsonb;
begin
  select pg_get_function_result('public.fabio_status_audio_fila(integer,uuid)'::regprocedure)
    into v_resultado;
  perform pg_temp.checar_092(
    'status do audio devolve registro_id',
    v_resultado ilike '%registro_id uuid%',
    coalesce(v_resultado, '<NULL>')
  );

  select pg_get_functiondef('public.fabio_concluir_reconciliacao(uuid,uuid,text,jsonb)'::regprocedure)
    into v_def;
  perform pg_temp.checar_092(
    'reconciliacao valida e persiste o registro do rascunho',
    v_def ilike '%p_dados%registro_id%'
      and v_def ilike '%rascunho_invalido%'
      and v_def ilike '%registro_id = case%'
      and v_def ilike '%p_evento%v_registro_id%'
      and v_def ilike '%payload = case%'
      and v_def ilike '%tentativas%'
      and v_def ilike '%parent_id is null%',
    left(coalesce(v_def, ''), 520)
  );

  perform pg_temp.checar_092(
    'prova de limpeza existe',
    to_regprocedure('public.fabio_provar_limpeza(uuid,text)') is not null,
    'to_regprocedure'
  );
  perform pg_temp.checar_092(
    'prova de limpeza nao executavel por anon',
    not has_function_privilege('anon', 'public.fabio_provar_limpeza(uuid,text)', 'EXECUTE'),
    'ACL anon'
  );
  perform pg_temp.checar_092(
    'prova de limpeza nao executavel por authenticated',
    not has_function_privilege('authenticated', 'public.fabio_provar_limpeza(uuid,text)', 'EXECUTE'),
    'ACL authenticated'
  );
  perform pg_temp.checar_092(
    'prova de limpeza executavel pelo service_role',
    has_function_privilege('service_role', 'public.fabio_provar_limpeza(uuid,text)', 'EXECUTE'),
    'ACL service_role'
  );

  select id into v_prof from public.professores where ativo order by id limit 1;
  if v_prof is null then
    perform pg_temp.checar_092('fixture de professor ativo', false, 'nenhum professor ativo');
  else
    insert into public.fabio_acoes_pendentes(
      professor_id, wa_message_id, tipo, estado, storage_path, payload, expira_em
    ) values (
      v_prof, 'ZZTESTE-092-terminal', 'confirmar_registro', 'cancelada',
      v_path, '{}'::jsonb, now()
    ) returning id into v_acao_terminal;

    insert into public.fabio_acoes_pendentes(
      professor_id, wa_message_id, tipo, estado, storage_path, payload, expira_em
    ) values (
      v_prof, 'ZZTESTE-092-ativa', 'confirmar_registro', 'aberta',
      v_path, '{}'::jsonb, now() + interval '24 hours'
    ) returning id into v_acao_ativa;

    v_prova := public.fabio_provar_limpeza(v_acao_terminal, v_path);
    perform pg_temp.checar_092(
      'prova recusa caminho referenciado por acao ativa',
      (v_prova ->> 'pode_remover')::boolean = false
        and v_prova ->> 'motivo' = 'acao_ativa_referencia_storage',
      v_prova::text
    );

    update public.fabio_acoes_pendentes
       set estado = 'cancelada', encerrado_em = now(), atualizado_em = now()
     where id = v_acao_ativa;

    v_prova := public.fabio_provar_limpeza(v_acao_terminal, v_path);
    perform pg_temp.checar_092(
      'prova libera caminho sem referencias',
      (v_prova ->> 'pode_remover')::boolean = true
        and v_prova ->> 'codigo' = 'limpeza_provada',
      v_prova::text
    );
  end if;
end
$$;

select json_build_object(
  'teste', '092-fecha-contrato-do-reconciliador',
  'falhas', (select count(*) from _fabio_092_res where not ok),
  'detalhe', coalesce((select json_agg(json_build_object(
    'passo', caso, 'esperado', 'ok', 'obtido', coalesce(detalhe, '<NULL>'))
  ) from _fabio_092_res where not ok), '[]'::json)
) as resumo;
