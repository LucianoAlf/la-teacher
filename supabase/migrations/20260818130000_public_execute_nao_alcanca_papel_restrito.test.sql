-- Itens 1 a 5 da segunda revisão do Alfredo.
--
-- Uma revogação tem duas formas de estar errada, e as duas precisam de teste:
--   (a) não fechou o que devia — o papel restrito continua alcançando;
--   (b) fechou demais — o app perdeu acesso e alguém descobre em produção.
-- Este teste mede as duas, e a (b) é a que costuma faltar.

-- PREAMBULO-INICIO
create temporary table pg_temp._res (caso text, ok boolean, detalhe text) on commit drop;

create or replace function pg_temp.checar(p_caso text, p_ok boolean, p_detalhe text)
returns void language plpgsql as $function$
begin
  insert into pg_temp._res(caso, ok, detalhe) values (p_caso, coalesce(p_ok,false), p_detalhe);
end
$function$;
-- PREAMBULO-FIM

do $function$
declare
  v_restritos text[] := array['fabio_professor_agente','sol_acesso_restrito',
                              'mila_acesso_restrito','lia_acesso_restrito',
                              'maria_lareport_rpc','ml_jobs'];
  v_app text[] := array['anon','authenticated','service_role'];
  v_p text;
  v_alcanca integer;
  v_perdeu text[] := '{}';
  v_sobrou text[] := '{}';
  v_definer_abertas integer;
begin
  -- ── (1) Nao sobrou funcao security definer aberta ao PUBLIC ───────────────
  select count(*) into v_definer_abertas
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.prosecdef
     and exists (select 1 from unnest(coalesce(p.proacl,'{}')) a where a::text like '=%');
  perform pg_temp.checar('ZERO security definer aberta ao PUBLIC (eram 38)',
    v_definer_abertas = 0, format('%s ainda aberta(s)', v_definer_abertas));

  -- ── (2) O app NAO perdeu nada: os tres papeis do PostgREST seguem entrando ─
  -- Esta e a metade que costuma faltar numa revogacao. `get_convite_anamnese`
  -- e `salvar_anamnese_online` sao chamadas por `anon` (formulario publico da
  -- familia): se elas cairem, a anamnese para de funcionar pra quem nao tem
  -- login, e ninguem descobre no mesmo dia.
  foreach v_p in array v_app loop
    if not has_function_privilege(v_p, 'public.get_convite_anamnese(text)', 'EXECUTE')
       or not has_function_privilege(v_p, 'public.salvar_anamnese_online(text,jsonb,jsonb)', 'EXECUTE')
       or not has_function_privilege(v_p, 'public.get_faturas_alunos_financeiro_v1(uuid,integer,integer,text,text,date)', 'EXECUTE')
       or not has_function_privilege(v_p, 'public.is_admin()', 'EXECUTE') then
      v_perdeu := v_perdeu || v_p;
    end if;
  end loop;
  perform pg_temp.checar('anon/authenticated/service_role NAO perderam acesso',
    cardinality(v_perdeu) = 0,
    case when cardinality(v_perdeu) = 0 then 'os tres seguem entrando'
         else 'PERDERAM: ' || array_to_string(v_perdeu, ', ') end);

  -- Ninguem pode ter ficado ORFA: funcao security definer sem nenhum grantee
  -- alem do dono e funcao que parou de ser chamavel — o modo de falha (b), o
  -- que so aparece em producao. E o que a trava do laco de revogacao evita.
  -- 53 ja eram assim ANTES desta fatia (helpers internos, chamados por outras
  -- definer ou por trigger). A 54a e NOSSA e de proposito: `fabio_agente_resolver`
  -- nao recebe grant de ninguem — quem a chama sao as ferramentas, que rodam
  -- como dono. "Sem grantee" ali e a garantia de que nao existe oraculo de
  -- token, nao um descuido. O que nao pode e esse numero passar de 54: passou,
  -- a revogacao orfanou alguem de verdade. Exigir zero seria acusar estado
  -- pre-existente e transformar o teste em ruido.
  select count(*) into v_alcanca
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.prosecdef
     and p.proacl is not null
     and not exists (select 1 from unnest(p.proacl) a
                      where a::text not like 'postgres=%'
                        and a::text not like 'supabase_admin=%');
  perform pg_temp.checar('a revogacao NAO orfanou ninguem (53 antes + o resolver)',
    v_alcanca <= 54, format('%s sem grantee alem do dono', v_alcanca));

  -- ── (3+5) Item 5: auditoria dos papeis restritos que ja existiam ──────────
  --
  -- A primeira versao desta assercao exigia ZERO e caiu — e estava ERRADA.
  -- Medido: sol alcanca 5, mila 1, lia 1, maria 18, e todas sao do PROPRIO
  -- dominio (sol_caixa_*, maria_lareport_*, fn_presenca_pendencia_elegivel).
  -- Isso e o padrao certo, o mesmo do Fabio com as 2 dele. O que nao pode
  -- existir e alcance por HERANCA — funcao que o papel toca sem ninguem ter
  -- concedido nominalmente a ele. E isso que a revogacao do PUBLIC fecha, e e
  -- isso que se mede aqui.
  foreach v_p in array v_restritos loop
    if not exists (select 1 from pg_roles where rolname = v_p) then
      continue;   -- papel que nao existe neste banco nao e falha
    end if;
    select count(*) into v_alcanca
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f' and p.prosecdef
       and has_function_privilege(v_p, p.oid, 'EXECUTE')
       -- ...sem grant nominal para ele: alcance que sobrou e heranca
       and not exists (select 1 from unnest(coalesce(p.proacl, '{}')) a
                        where a::text like v_p || '=%');
    if v_alcanca > 0 then
      v_sobrou := v_sobrou || format('%s(%s)', v_p, v_alcanca);
    end if;
  end loop;
  perform pg_temp.checar('NENHUM papel restrito alcanca nada por HERANCA',
    cardinality(v_sobrou) = 0,
    case when cardinality(v_sobrou) = 0 then 'todo alcance e nominal'
         else 'herdam: ' || array_to_string(v_sobrou, ', ') end);

  -- Fixa o mapa de hoje: se um papel restrito GANHAR funcao nova, o teste cai e
  -- alguem decide de proposito, em vez de descobrir depois.
  -- Sol foi de 5 pra 6 nesta fatia, DE PROPOSITO: `get_cron_health` era o unico
  -- uso herdado real medido no pg_stat_statements, e virou grant nominal antes
  -- da revogacao. O mapa fixado acusou a mudanca — que e exatamente pra isso
  -- que ele existe.
  perform pg_temp.checar('mapa de alcance nominal fixado (sol 6 / mila 1 / lia 1 / maria 18)',
    (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.prokind='f' and p.prosecdef
        and exists (select 1 from unnest(coalesce(p.proacl,'{}')) a
                     where a::text like 'sol_acesso_restrito=%')) = 6
    and (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
          where n.nspname='public' and p.prokind='f' and p.prosecdef
            and exists (select 1 from unnest(coalesce(p.proacl,'{}')) a
                         where a::text like 'maria_lareport_rpc=%')) = 18,
    'contagem nominal por papel');

  -- ── (4) O corte fino do papel do Fabio: SO as duas ferramentas ────────────
  select count(*) into v_alcanca
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.prosecdef
     and has_function_privilege('fabio_professor_agente', p.oid, 'EXECUTE');
  perform pg_temp.checar('o papel do Fabio executa EXATAMENTE 2 security definer',
    v_alcanca = 2, format('%s funcao(oes)', v_alcanca));

  perform pg_temp.checar('e sao as duas ferramentas letivas, nominalmente',
    has_function_privilege('fabio_professor_agente',
      'public.fabio_prof_aulas_periodo(text,date,date,text)', 'EXECUTE')
    and has_function_privilege('fabio_professor_agente',
      'public.fabio_prof_presencas_periodo(text,date,date)', 'EXECUTE'),
    'aulas + presencas');

  -- ── O financeiro e a escrita, nominalmente fora ───────────────────────────
  perform pg_temp.checar('financeiro fora do alcance do papel do Fabio',
    not has_function_privilege('fabio_professor_agente',
      'public.get_faturas_alunos_financeiro_v1(uuid,integer,integer,text,text,date)', 'EXECUTE'),
    'get_faturas_alunos_financeiro_v1');
  perform pg_temp.checar('cancelar aula fora do alcance do papel do Fabio',
    not has_function_privilege('fabio_professor_agente',
      'public.app_falta_professor_cancelar_aulas(integer,date,uuid,text)', 'EXECUTE'),
    'app_falta_professor_cancelar_aulas');
  perform pg_temp.checar('escrita de projecao fora do alcance do papel do Fabio',
    not has_function_privilege('fabio_professor_agente',
      'public.materializar_projecao_contrato(integer,bigint)', 'EXECUTE'),
    'materializar_projecao_contrato');

  -- ── Contraprova: a regua funciona ─────────────────────────────────────────
  -- Se `service_role` tambem aparecesse zerado, o teste estaria medindo errado
  -- e o verde acima seria um verde de medicao quebrada.
  select count(*) into v_alcanca
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.prosecdef
     and has_function_privilege('service_role', p.oid, 'EXECUTE');
  perform pg_temp.checar('contraprova: service_role continua alcancando muita coisa',
    v_alcanca > 20, format('%s funcao(oes)', v_alcanca));
end
$function$;

select json_build_object(
  'total',  (select count(*) from pg_temp._res),
  'falhas', (select count(*) from pg_temp._res where not ok),
  'detalhe', (select json_agg(json_build_object(
                      'passo', caso, 'esperado', 'OK', 'obtido', detalhe)
                      order by caso)
               from pg_temp._res where not ok),
  'casos',  (select json_agg(json_build_object(
                      'caso', caso,
                      'veredito', case when ok then 'OK' else 'FALHOU' end,
                      'detalhe', detalhe) order by caso)
               from pg_temp._res)
) as resumo;
