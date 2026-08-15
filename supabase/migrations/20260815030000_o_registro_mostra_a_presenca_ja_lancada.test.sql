-- Este teste roda contra o dado VIVO do caso que originou o conserto (o registro
-- por áudio do Valdo, aula de quarta 18h, com a presença já lançada pela
-- secretaria) — nada de fixture. A função é STABLE e só lê; o runner ainda
-- assim envolve tudo em transação e confere resíduo nas duas pontas.

create temporary table pg_temp._fabio_20260815030000_res (
  caso text,
  ok boolean,
  detalhe text
) on commit drop;

create or replace function pg_temp.checar_20260815030000(
  p_caso text,
  p_ok boolean,
  p_detalhe text
) returns void
language plpgsql
as $function$
begin
  insert into pg_temp._fabio_20260815030000_res(caso, ok, detalhe)
  values (p_caso, coalesce(p_ok, false), p_detalhe);
end
$function$;

-- ── Contrato de catálogo ────────────────────────────────────────────────────
do $function$
declare
  v_fn regprocedure := to_regprocedure('public.app_registro_completo(uuid)');
  v_norm text;
begin
  if v_fn is null then
    perform pg_temp.checar_20260815030000('app_registro_completo existe', false, 'ausente');
    return;
  end if;
  v_norm := lower(regexp_replace(pg_get_functiondef(v_fn), '[[:space:]]+', ' ', 'g'));

  perform pg_temp.checar_20260815030000(
    'a tela de registro consulta a presenca ja lancada e usa a regua canonica',
    position('public.aluno_presenca ap' in v_norm) > 0
      and position('fn_presenca_fecha_chamada' in v_norm) > 0
      and position('''presenca_lancada''' in v_norm) > 0
      and position('''presenca_fonte''' in v_norm) > 0
      and position('''presenca_travada''' in v_norm) > 0,
    left(pg_get_functiondef(v_fn), 2000)
  );

  -- Exibição não pode virar escrita: a função continua STABLE e sem DML.
  perform pg_temp.checar_20260815030000(
    'segue sendo somente leitura (STABLE, sem insert/update/delete)',
    (select p.provolatile = 's' from pg_proc p where p.oid = v_fn)
      and position('insert into' in v_norm) = 0
      and position('update public.' in v_norm) = 0
      and position('delete from' in v_norm) = 0,
    (select p.provolatile::text from pg_proc p where p.oid = v_fn)
  );

  -- A régua canônica tem que continuar tratando o 'ausente' do Emusys como
  -- NÃO-fechado (falta fantasma da migração) — senão travaríamos o professor
  -- com base num dado ambíguo.
  perform pg_temp.checar_20260815030000(
    'regua canonica: secretaria fecha, emusys presente fecha, emusys ausente NAO fecha',
    public.fn_presenca_fecha_chamada('falta', 'agenda_secretaria')
      and public.fn_presenca_fecha_chamada('presente', 'agenda_secretaria')
      and public.fn_presenca_fecha_chamada('presente', 'emusys')
      and not public.fn_presenca_fecha_chamada('falta', 'emusys')
      and not public.fn_presenca_fecha_chamada('presente', 'sistema'),
    jsonb_build_object(
      'secretaria_falta', public.fn_presenca_fecha_chamada('falta', 'agenda_secretaria'),
      'emusys_presente', public.fn_presenca_fecha_chamada('presente', 'emusys'),
      'emusys_ausente', public.fn_presenca_fecha_chamada('falta', 'emusys')
    )::text
  );
end
$function$;

-- ── Comportamento com o dado real do Valdo ──────────────────────────────────
do $function$
declare
  v_registro uuid := 'fcc3e6ea-73dd-4b15-bd59-e179c672ade8'; -- tronco do áudio, aula 221905
  v_out jsonb;
  v_daniel jsonb;   -- aluno 77  — secretaria marcou PRESENTE
  v_lucas jsonb;    -- aluno 1872 — secretaria marcou FALTA
begin
  -- Sem professor autenticado a porta nem responde; simula o Valdo (prof 36).
  perform set_config('request.jwt.claims',
    json_build_object('sub','85501504-b673-4035-a8f4-9b324dabdfe8','role','authenticated')::text,
    true);

  v_out := public.app_registro_completo(v_registro);

  select f into v_daniel from jsonb_array_elements(v_out->'fatias') f
   where (f->>'aluno_id')::int = 77;
  select f into v_lucas from jsonb_array_elements(v_out->'fatias') f
   where (f->>'aluno_id')::int = 1872;

  perform pg_temp.checar_20260815030000(
    'a tela de registro recebe a presenca que a secretaria lancou, com a fonte',
    v_daniel->>'presenca_lancada' = 'presente'
      and v_daniel->>'presenca_fonte' = 'agenda_secretaria'
      and v_lucas->>'presenca_lancada' = 'falta'
      and v_lucas->>'presenca_fonte' = 'agenda_secretaria',
    jsonb_build_object('daniel', v_daniel, 'lucas', v_lucas)::text
  );

  perform pg_temp.checar_20260815030000(
    'presenca lancada pela secretaria vem TRAVADA para o professor',
    coalesce((v_daniel->>'presenca_travada')::boolean, false)
      and coalesce((v_lucas->>'presenca_travada')::boolean, false),
    jsonb_build_object(
      'daniel_travada', v_daniel->>'presenca_travada',
      'lucas_travada', v_lucas->>'presenca_travada'
    )::text
  );

  -- O conteúdo do professor (o que É dele) continua chegando igual.
  perform pg_temp.checar_20260815030000(
    'o conteudo do registro continua intacto na resposta',
    v_out->'tronco'->'campos'->>'objetivo' is not null
      and jsonb_array_length(v_out->'fatias') = 2
      and v_daniel ? 'campos' and v_lucas ? 'campos',
    left(coalesce(v_out->'tronco'->'campos'->>'objetivo',''), 80)
  );
end
$function$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._fabio_20260815030000_res where not ok),
  'detalhe', coalesce((
    select json_agg(json_build_object(
      'passo', caso, 'esperado', 'true', 'obtido', detalhe
    ) order by caso)
      from pg_temp._fabio_20260815030000_res where not ok
  ), '[]'::json)
) as resumo;
