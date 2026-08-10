-- Teste da 082. As réguas são de gestão, não de engenharia: elas mudam, e o
-- histórico do que mudou é o placar da transição de registro.
--
-- Acréscimo à revisão do brief: a Task 1 (081) saiu com `grant select ... to
-- authenticated` numa VIEW e isso abriu, por horas, leitura de dado de aluno
-- pra qualquer professor autenticado. Aqui são DUAS TABELAS — o mesmo risco,
-- e medido em produção (pg_default_acl) que é PIOR: toda tabela nova criada
-- pelo `postgres` já nasce com `anon` e `authenticated` tendo
-- select/insert/update/delete concedido por ALTER DEFAULT PRIVILEGES do
-- projeto. RLS sem policy barra a LINHA, mas não apaga o GRANT — por isso o
-- passo "as tabelas de config nao sao legiveis por authenticated" abaixo, que
-- prova a ACL e não só o efeito de RLS.
create temporary table _res(caso text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_coord uuid;
  v_r     jsonb;
  v_hist  int;
begin
  select u.auth_user_id into v_coord
    from public.la_teacher_coordenacao c
    join public.usuarios u on u.id = c.usuario_id
   where u.auth_user_id is not null and coalesce(u.ativo, true)
   limit 1;

  -- ── As dez chaves existem, com fábrica ──────────────────────────────────
  insert into _res values ('as 10 chaves existem',
    (select count(*) from public.radar_config) = 10,
    format('%s chaves', (select count(*) from public.radar_config)));

  insert into _res values ('toda chave tem valor de fabrica',
    not exists (select 1 from public.radar_config where fabrica is null), 'ok');

  insert into _res values ('o default do absenteismo e 25 (benchmark do Alf)',
    (select fabrica from public.radar_config where chave='absenteismo_atencao_pct') = 25,
    (select fabrica::text from public.radar_config where chave='absenteismo_atencao_pct'));

  -- ── A porta é a função, não a tabela ─────────────────────────────────────
  -- RLS ligada e sem policy nas duas tabelas — mas isso sozinho só garante
  -- que nenhuma LINHA bate (USING ausente = falso pra sempre). O GRANT é
  -- coisa separada: sem revoke explícito, `authenticated` continua com
  -- privilégio de SELECT no catálogo (has_table_privilege), herdado do
  -- ALTER DEFAULT PRIVILEGES do projeto — mesma lição da 081, agora em
  -- tabela em vez de view.
  insert into _res values ('as tabelas de config nao sao legiveis por authenticated',
    not has_table_privilege('authenticated', 'public.radar_config', 'SELECT')
    and not has_table_privilege('authenticated', 'public.radar_config_historico', 'SELECT'),
    'ok');

  -- ── Guard ───────────────────────────────────────────────────────────────
  perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
  begin
    perform public.app_radar_config();
    insert into _res values ('quem nao e coordenacao nao le a config', false, 'passou sem guard');
  exception when others then
    insert into _res values ('quem nao e coordenacao nao le a config',
      sqlerrm like '%apenas_admin%', sqlerrm);
  end;

  perform set_config('request.jwt.claim.sub', v_coord::text, true);

  -- ── Leitura ─────────────────────────────────────────────────────────────
  v_r := public.app_radar_config();
  insert into _res values ('a leitura traz valor E fabrica',
    (v_r #>> '{itens,0,valor}') is not null and (v_r #>> '{itens,0,fabrica}') is not null,
    v_r #>> '{itens,0}');

  -- ── Escrita grava historico ─────────────────────────────────────────────
  select count(*) into v_hist from public.radar_config_historico;
  perform public.app_radar_config_salvar('absenteismo_atencao_pct', 30);

  insert into _res values ('o valor mudou',
    (select valor from public.radar_config where chave='absenteismo_atencao_pct') = 30,
    (select valor::text from public.radar_config where chave='absenteismo_atencao_pct'));

  insert into _res values ('a fabrica NAO mudou (e a referencia do que foi mexido)',
    (select fabrica from public.radar_config where chave='absenteismo_atencao_pct') = 25,
    (select fabrica::text from public.radar_config where chave='absenteismo_atencao_pct'));

  insert into _res values ('a mudanca gravou historico',
    (select count(*) from public.radar_config_historico) = v_hist + 1,
    format('%s -> %s', v_hist, (select count(*) from public.radar_config_historico)));

  insert into _res values ('o historico guarda o valor ANTERIOR',
    (select valor_anterior from public.radar_config_historico
      order by mudado_em desc limit 1) = 25,
    (select valor_anterior::text from public.radar_config_historico
      order by mudado_em desc limit 1));

  -- ── Chave desconhecida nao cria linha nova ──────────────────────────────
  begin
    perform public.app_radar_config_salvar('peso_inventado', 99);
    insert into _res values ('chave desconhecida e recusada', false, 'aceitou');
  exception when others then
    insert into _res values ('chave desconhecida e recusada',
      sqlerrm like '%chave_desconhecida%', sqlerrm);
  end;
end $$;

select json_build_object(
         'falhas', (select count(*) from _res where not ok),
         'detalhe', coalesce((select json_agg(json_build_object(
                                'passo', caso, 'esperado', 'ok', 'obtido', detalhe))
                                from _res where not ok), '[]'::json)
       ) as resumo;
