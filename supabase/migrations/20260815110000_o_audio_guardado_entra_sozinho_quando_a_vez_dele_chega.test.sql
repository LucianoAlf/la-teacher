-- Contrato de catalogo (execucao remota) + bloco Docker com a fila rodando de
-- verdade. O bloco fica comentado de proposito; o mutante o extrai.

create temporary table pg_temp._parqueados_res (
  caso text, ok boolean, detalhe text
) on commit drop;

create or replace function pg_temp.checar_parqueados(p_caso text, p_ok boolean, p_detalhe text)
returns void language plpgsql as $function$
begin
  insert into pg_temp._parqueados_res(caso, ok, detalhe)
  values (p_caso, coalesce(p_ok, false), p_detalhe);
end
$function$;

do $function$
declare
  v_tab oid := to_regclass('public.fabio_audios_parqueados');
begin
  perform pg_temp.checar_parqueados('a fila de espera existe', v_tab is not null, coalesce(v_tab::text, '<ausente>'));

  perform pg_temp.checar_parqueados(
    'as quatro portas existem',
    (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname in ('fabio_parquear_audio', 'fabio_audio_parqueado_proximo',
                          'fabio_audio_parqueado_consumir', 'fabio_audio_parqueado_descartar')) = 4,
    (select string_agg(p.proname, ',') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname like 'fabio_%parque%'));

  -- A idempotencia e ESTRUTURAL. Se o indice unico sumir, `on conflict` vira
  -- erro de sintaxe em producao e a reentrega do UAZAPI vira linha duplicada.
  perform pg_temp.checar_parqueados(
    'a idempotencia por wa_message_id e do indice, nao do chamador',
    exists (select 1 from pg_indexes
             where schemaname = 'public'
               and indexname = 'uq_fabio_audio_parqueado_mensagem'),
    'uq_fabio_audio_parqueado_mensagem');

  perform pg_temp.checar_parqueados(
    'consumido E descartado ao mesmo tempo e recusado pelo banco',
    exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid
             where t.relname = 'fabio_audios_parqueados'
               and c.conname = 'fabio_audios_parqueados_destino_unico'),
    'fabio_audios_parqueados_destino_unico');

  perform pg_temp.checar_parqueados(
    'authenticated/anon nao alcancam a fila nem as portas',
    not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.proname in ('fabio_parquear_audio', 'fabio_audio_parqueado_proximo',
                           'fabio_audio_parqueado_consumir', 'fabio_audio_parqueado_descartar')
         and (has_function_privilege('authenticated', p.oid, 'execute')
              or has_function_privilege('anon', p.oid, 'execute'))
    ) and not has_table_privilege('authenticated', 'public.fabio_audios_parqueados', 'select'),
    'acesso publico');
end
$function$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._parqueados_res where not ok),
  'detalhe', coalesce((
    select json_agg(json_build_object('passo', caso, 'esperado', 'true', 'obtido', detalhe) order by caso)
      from pg_temp._parqueados_res where not ok), '[]'::json)
) as resumo;

/* PARQUEADOS-DOCKER-DML-TESTS-INICIO

do $docker$
declare
  v_a jsonb; v_b jsonb; v_re jsonb;
  v_prox jsonb; v_prox2 jsonb;
  v_consumo jsonb; v_consumo2 jsonb; v_descarte jsonb;
  v_id_12h uuid; v_id_13h uuid;
begin
  -- O professor gravou a aula das 12h e depois a das 13h. Chegaram as duas com
  -- acao aberta.
  v_a := public.fabio_parquear_audio(10, 'wa:12h', 'whatsapp/10/wa-12h.ogg', 'aula das doze', 61);
  perform pg_temp.checar_parqueados('o primeiro audio entra na fila', (v_a->>'ok')::boolean and not (v_a->>'ja_existia')::boolean, v_a::text);
  v_id_12h := (v_a->>'id')::uuid;

  -- criado_em identico faria o desempate cair no id, que e aleatorio. O FIFO
  -- so e testavel com tempos distintos -- como na vida.
  update public.fabio_audios_parqueados set criado_em = now() - interval '2 minutes' where id = v_id_12h;

  v_b := public.fabio_parquear_audio(10, 'wa:13h', 'whatsapp/10/wa-13h.ogg', 'aula das treze', 55);
  v_id_13h := (v_b->>'id')::uuid;
  perform pg_temp.checar_parqueados('o segundo audio tambem entra (nao substitui o primeiro)',
    (v_b->>'ok')::boolean and v_id_13h is not null and v_id_13h <> v_id_12h, v_b::text);

  -- Reentrega do UAZAPI: mesma mensagem, nao audio novo.
  v_re := public.fabio_parquear_audio(10, 'wa:13h', 'whatsapp/10/wa-13h.ogg', 'aula das treze', 55);
  perform pg_temp.checar_parqueados('reentrega do UAZAPI nao vira segunda linha',
    (v_re->>'ok')::boolean and (v_re->>'ja_existia')::boolean
      and (select count(*) from public.fabio_audios_parqueados where professor_id = 10) = 2,
    v_re::text || ' / linhas=' || (select count(*)::text from public.fabio_audios_parqueados where professor_id = 10));

  -- Parametro faltando nao vira linha meia-boca.
  perform pg_temp.checar_parqueados('sem storage_path nao entra na fila',
    not ((public.fabio_parquear_audio(10, 'wa:vazio', '  ', null, 0))->>'ok')::boolean,
    'parametros_obrigatorios');

  -- FIFO: a vez e da aula das 12h.
  v_prox := public.fabio_audio_parqueado_proximo(10);
  perform pg_temp.checar_parqueados('a fila devolve o mais antigo primeiro (FIFO)',
    v_prox->>'wa_message_id' = 'wa:12h', coalesce(v_prox::text, '<null>'));
  perform pg_temp.checar_parqueados('a fila devolve a transcricao junto (o texto e o insumo da escolha)',
    v_prox->>'transcricao' = 'aula das doze', coalesce(v_prox::text, '<null>'));

  -- Fila de outro professor nao se mistura.
  perform pg_temp.checar_parqueados('a fila de outro professor nao vaza',
    public.fabio_audio_parqueado_proximo(99) = '{}'::jsonb,
    public.fabio_audio_parqueado_proximo(99)::text);

  -- Consumo carimba e tira da vez.
  v_consumo := public.fabio_audio_parqueado_consumir(v_id_12h, gen_random_uuid());
  perform pg_temp.checar_parqueados('consumir carimba o audio', (v_consumo->>'ok')::boolean, v_consumo::text);

  v_consumo2 := public.fabio_audio_parqueado_consumir(v_id_12h, gen_random_uuid());
  perform pg_temp.checar_parqueados('o mesmo audio nao e consumido duas vezes',
    not (v_consumo2->>'ok')::boolean, v_consumo2::text);

  v_prox2 := public.fabio_audio_parqueado_proximo(10);
  perform pg_temp.checar_parqueados('depois do consumo, a vez passa pro proximo',
    v_prox2->>'wa_message_id' = 'wa:13h', coalesce(v_prox2::text, '<null>'));

  -- Um audio ja atendido nao pode ser descartado por cima: seriam duas
  -- historias sobre o mesmo audio. O bloco pega excecao de proposito -- sem a
  -- guarda DENTRO da funcao, o CHECK do banco estoura, e explodir e tao
  -- reprovado quanto responder errado.
  begin
    v_descarte := public.fabio_audio_parqueado_descartar(v_id_12h, 'tentativa indevida');
    perform pg_temp.checar_parqueados('audio ja consumido nao pode ser descartado depois',
      not (v_descarte->>'ok')::boolean, v_descarte::text);
  exception when others then
    perform pg_temp.checar_parqueados('audio ja consumido nao pode ser descartado depois',
      false, 'estourou: ' || sqlerrm);
  end;

  -- Descarte sai da fila com motivo escrito.
  v_descarte := public.fabio_audio_parqueado_descartar(v_id_13h, 'professor pediu pra ignorar');
  perform pg_temp.checar_parqueados('descartar tira da fila com motivo',
    (v_descarte->>'ok')::boolean
      and public.fabio_audio_parqueado_proximo(10) = '{}'::jsonb
      and (select descartado_motivo from public.fabio_audios_parqueados where id = v_id_13h)
          = 'professor pediu pra ignorar',
    v_descarte::text);

  begin
    v_consumo2 := public.fabio_audio_parqueado_consumir(v_id_13h, null);
    perform pg_temp.checar_parqueados('audio descartado nao pode ser consumido depois',
      not (v_consumo2->>'ok')::boolean, v_consumo2::text);
  exception when others then
    perform pg_temp.checar_parqueados('audio descartado nao pode ser consumido depois',
      false, 'estourou: ' || sqlerrm);
  end;
end
$docker$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._parqueados_res where not ok),
  'detalhe', coalesce((
    select json_agg(json_build_object('passo', caso, 'esperado', 'true', 'obtido', detalhe) order by caso)
      from pg_temp._parqueados_res where not ok), '[]'::json)
) as resumo;
PARQUEADOS-DOCKER-DML-TESTS-FIM */
