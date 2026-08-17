-- POR QUE ESTE TESTE SEMEIA, EM VEZ DE AFIRMAR SOBRE O CORPUS:
--
-- A primeira versão afirmava "a RPC não devolve nada de origem app" contra a
-- produção — e passava até com a trava ANULADA (mutante sobreviveu). Motivo: a
-- oferta é uma FILA que o worker drena a cada 5 minutos, então em quase todo
-- instante a RPC devolve zero por já ter sido esvaziada, não pela regra.
-- Amostra que não alcança o caso é verde decorativo.
--
-- E o par é semeado CLONANDO uma linha real (temp table + troca só da origem),
-- não montando uma à mão: `fabio_registros_aula` tem NOT NULLs que eu
-- descobriria um a um (aula_id, unidade_id…), e a linha inventada não seria a
-- linha que a produção tem. Roda dentro do BEGIN/ROLLBACK do runner, que
-- confere resíduo zero.

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
  v_fn oid := to_regprocedure('public.fabio_devolutivas_a_oferecer(integer)');
  v_modelo uuid;
  v_prof integer;
  v_aluno integer;
  v_tronco_app uuid := gen_random_uuid();
  v_tronco_wa  uuid := gen_random_uuid();
  v_fatia_app  uuid := gen_random_uuid();
  v_fatia_wa   uuid := gen_random_uuid();
  v_dev_app uuid;
  v_dev_wa  uuid;
  v_ids uuid[];
begin
  perform pg_temp.checar('a RPC existe', v_fn is not null, coalesce(v_fn::text, '<ausente>'));
  if v_fn is null then return; end if;

  -- Um tronco real que já tenha aluno conciliado serve de molde.
  select t.id, t.professor_id, f.aluno_id
    into v_modelo, v_prof, v_aluno
    from public.fabio_registros_aula t
    join public.fabio_registros_aula f on f.parent_id = t.id
    join public.alunos a on a.id = f.aluno_id
   where t.parent_id is null and f.aluno_id is not null
   limit 1;

  perform pg_temp.checar('achei registro real pra clonar',
    v_modelo is not null, format('modelo=%s prof=%s aluno=%s', v_modelo, v_prof, v_aluno));
  if v_modelo is null then return; end if;

  create temporary table _clone on commit drop as
    select * from public.fabio_registros_aula where id = v_modelo;

  -- tronco APP
  update _clone set id = v_tronco_app, origem = 'app', parent_id = null,
                    status = 'confirmado';
  insert into public.fabio_registros_aula select * from _clone;
  -- tronco WHATSAPP (mesmo molde, só a origem muda)
  update _clone set id = v_tronco_wa, origem = 'whatsapp';
  insert into public.fabio_registros_aula select * from _clone;
  -- fatias, cada uma sob o seu tronco
  update _clone set id = v_fatia_app, origem = 'app',
                    parent_id = v_tronco_app, aluno_id = v_aluno;
  insert into public.fabio_registros_aula select * from _clone;
  update _clone set id = v_fatia_wa, origem = 'whatsapp', parent_id = v_tronco_wa;
  insert into public.fabio_registros_aula select * from _clone;

  -- Duas devolutivas ELEGÍVEIS (gerada, nunca oferecida, com destinatário e texto).
  insert into public.fabio_devolutivas
         (registro_fatia_id, aluno_id, professor_id, destinatario, destinatario_nome,
          texto_normal, status)
       values (v_fatia_app, v_aluno, v_prof, 'aluno', 'Fulano',
               'texto de ensaio app', 'gerada') returning id into v_dev_app;
  insert into public.fabio_devolutivas
         (registro_fatia_id, aluno_id, professor_id, destinatario, destinatario_nome,
          texto_normal, status)
       values (v_fatia_wa, v_aluno, v_prof, 'aluno', 'Fulano',
               'texto de ensaio whatsapp', 'gerada') returning id into v_dev_wa;

  select coalesce(array_agg((dev ->> 'id')::uuid), '{}'::uuid[])
    into v_ids
    from jsonb_array_elements(public.fabio_devolutivas_a_oferecer(500)) prof,
         jsonb_array_elements(prof -> 'devolutivas') dev;

  -- ── O pedido do Alf ──────────────────────────────────────────────────────
  perform pg_temp.checar('devolutiva de registro do APP NAO e oferecida no WhatsApp',
    not (v_dev_app = any(v_ids)), format('app na oferta=%s', v_dev_app = any(v_ids)));

  -- ── A trava e ESTREITA: nao mata o caminho nativo do WhatsApp ────────────
  -- Sem esta, "desligar tudo" passaria no teste e eu nao veria a diferenca.
  perform pg_temp.checar('devolutiva de registro do WHATSAPP continua elegivel',
    v_dev_wa = any(v_ids), format('whatsapp na oferta=%s', v_dev_wa = any(v_ids)));

  -- Portas e volatilidade continuam como estavam.
  perform pg_temp.checar('anon NAO executa',
    not has_function_privilege('anon', v_fn, 'EXECUTE'), 'anon');
  perform pg_temp.checar('authenticated NAO executa',
    not has_function_privilege('authenticated', v_fn, 'EXECUTE'), 'authenticated');
  perform pg_temp.checar('a RPC e STABLE (nao escreve)',
    (select provolatile from pg_proc where oid = v_fn) = 's',
    (select provolatile::text from pg_proc where oid = v_fn));
end
$function$;

select json_build_object(
  'total',  (select count(*) from pg_temp._res),
  'falhas', (select count(*) from pg_temp._res where not ok),
  'casos',  (select json_agg(json_build_object(
                      'caso', caso,
                      'veredito', case when ok then 'OK' else 'FALHOU' end,
                      'detalhe', detalhe) order by caso)
               from pg_temp._res)
) as resumo;
