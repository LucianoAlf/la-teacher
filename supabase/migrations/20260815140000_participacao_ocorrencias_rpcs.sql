-- RPCs da camada de ocorrencia de participacao (substituicao) — SHADOW.
-- Cinco funcoes security definer, so service_role: resolver a identidade do
-- participante (escada carteira->unidade->externo, casando por TOKEN), registrar
-- a candidata em shadow (nao toca presenca/registro/Emusys), e a maquina de
-- estados (confirmar/validar/descartar) que consulta a view antes de gravar.
-- Depende do schema em 20260815130000_participacao_ocorrencias_schema.sql,
-- de public.vw_fabio_carteira_professor e de public.fn_aula_operacional_id.

-- ── Regua de identidade: mesma do casador (_nome_tokens) ─────────────────────
-- Palavra >= 3 letras, sem acento, minuscula, fora dos sobrenomes comuns que
-- colidiriam entre alunos diferentes. Casar pela string inteira nunca pegava o
-- primeiro nome ("Billy" x "Billy Paulo Vangu Junior").
create or replace function public.fn_participacao_nome_tokens(p_nome text)
returns text[]
language sql
immutable
set search_path to 'pg_catalog', 'public'
as $fn$
  select coalesce(array_agg(distinct tok), array[]::text[])
  from (
    select tok
    from regexp_split_to_table(
      translate(
        lower(coalesce(p_nome, '')),
        'áàâãäéèêëíìîïóòôõöúùûüçñ',
        'aaaaaeeeeiiiiooooouuuucn'
      ),
      '[^a-z0-9]+'
    ) as tok
    where char_length(tok) >= 3
      and tok not in (
        'junior', 'filho', 'neto', 'silva', 'santos', 'souza', 'sousa',
        'oliveira', 'pereira', 'lima', 'costa', 'ferreira', 'rodrigues',
        'almeida', 'nascimento'
      )
  ) t
$fn$;

comment on function public.fn_participacao_nome_tokens(text) is
  'Tokens que IDENTIFICAM um nome (palavra >=3, sem acento, sem sobrenome comum). Mesma regua do casador do Fabio.';

-- Dois nomes casam se compartilham ao menos um token identificador.
create or replace function public.fn_participacao_nome_casa(p_nome_a text, p_nome_b text)
returns boolean
language sql
immutable
set search_path to 'pg_catalog', 'public'
as $fn$
  select public.fn_participacao_nome_tokens(p_nome_a) && public.fn_participacao_nome_tokens(p_nome_b)
$fn$;

comment on function public.fn_participacao_nome_casa(text, text) is
  'Verdadeiro quando dois nomes compartilham um token identificador (casamento por token, nao por string inteira).';

-- ── RPC 1: resolver a identidade do participante ─────────────────────────────
-- Escada: carteira do professor -> alunos da unidade -> externo. NAO decide;
-- devolve cardinalidade (0 externo, 1 unica, >1 ambiguo), candidatos e origem.
create or replace function public.fabio_resolver_participante(
  p_professor_id integer,
  p_unidade_id uuid,
  p_nome text
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $fn$
declare
  v_candidatos jsonb;
  v_origem text;
begin
  -- 1) carteira do professor
  select jsonb_agg(jsonb_build_object('aluno_id', aluno_id, 'nome', aluno_nome) order by aluno_nome, aluno_id)
    into v_candidatos
  from (
    select distinct c.aluno_id, c.aluno_nome
    from public.vw_fabio_carteira_professor c
    where c.professor_id = p_professor_id
      and public.fn_participacao_nome_casa(c.aluno_nome, p_nome)
  ) q;

  if v_candidatos is not null then
    v_origem := 'carteira';
  else
    -- 2) alunos da unidade (qualquer professor)
    select jsonb_agg(jsonb_build_object('aluno_id', aluno_id, 'nome', aluno_nome) order by aluno_nome, aluno_id)
      into v_candidatos
    from (
      select distinct c.aluno_id, c.aluno_nome
      from public.vw_fabio_carteira_professor c
      where c.unidade_id = p_unidade_id
        and public.fn_participacao_nome_casa(c.aluno_nome, p_nome)
    ) q;

    if v_candidatos is not null then
      v_origem := 'unidade';
    else
      -- 3) nada: externo
      v_origem := 'externo';
    end if;
  end if;

  return jsonb_build_object(
    'cardinalidade', coalesce(jsonb_array_length(v_candidatos), 0),
    'candidatos', coalesce(v_candidatos, '[]'::jsonb),
    'origem', v_origem
  );
end
$fn$;

comment on function public.fabio_resolver_participante(integer, uuid, text) is
  'Escada de identidade do participante (carteira->unidade->externo), casando por token. Nao decide: devolve cardinalidade/candidatos/origem.';

-- ── RPC 2: registrar candidata em SHADOW ─────────────────────────────────────
-- Ponto de entrada do WhatsApp. Resolve aula_operacional_id, insere o FATO e o
-- evento 'registrada'. NAO le nem escreve presenca/registro/Emusys. Idempotente
-- por origem_message_id (guard + indice unico parcial): reentrega do UAZAPI nao
-- duplica.
create or replace function public.fabio_participacao_registrar_candidata(
  p_aula_id integer,
  p_professor_id integer,
  p_aluno_matriculado_id integer,
  p_participante_real_id integer,
  p_participante_nome text,
  p_participante_telefone text,
  p_confianca text,
  p_metodo_extracao text,
  p_origem_message_id text,
  p_origem_transcricao text
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $fn$
declare
  v_aula_op integer;
  v_id uuid;
  v_estado text;
  v_precisa boolean;
begin
  -- WhatsApp exige message_id (mesma constraint do schema, resposta amigavel).
  if p_origem_message_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'origem_message_id_obrigatorio');
  end if;

  v_aula_op := public.fn_aula_operacional_id(p_aula_id);

  -- IDEMPOTENCIA-INICIO: mesma mensagem+aula+matriculado vigente devolve a existente.
  select o.id into v_id
  from public.fabio_participacao_ocorrencias o
  where o.aula_operacional_id = v_aula_op
    and o.aluno_matriculado_id = p_aluno_matriculado_id
    and o.origem_message_id = p_origem_message_id
    and o.supersede_ocorrencia_id is null
  limit 1;

  if v_id is not null then
    select estado_atual into v_estado
      from public.vw_fabio_participacao_ocorrencia_estado where ocorrencia_id = v_id;
    return jsonb_build_object(
      'ok', true,
      'ocorrencia_id', v_id,
      'estado', coalesce(v_estado, 'candidata'),
      'precisa_confirmar', ((p_participante_real_id is null) or (p_confianca is distinct from 'alta')),
      'motivo_ambiguidade', null,
      'ja_existia', true
    );
  end if;
  -- IDEMPOTENCIA-FIM

  v_precisa := (p_participante_real_id is null) or (p_confianca is distinct from 'alta');

  insert into public.fabio_participacao_ocorrencias
    (aula_operacional_id, aula_id, professor_id, aluno_matriculado_id,
     participante_real_id, participante_real_nome, participante_real_telefone,
     tipo, confianca, metodo_extracao, origem, origem_message_id, origem_transcricao)
  values (v_aula_op, p_aula_id, p_professor_id, p_aluno_matriculado_id,
     p_participante_real_id, p_participante_nome, p_participante_telefone,
     'substituicao', p_confianca, p_metodo_extracao, 'whatsapp', p_origem_message_id, p_origem_transcricao)
  returning id into v_id;

  insert into public.fabio_participacao_ocorrencia_eventos (ocorrencia_id, evento, por_tipo, por_id)
  values (v_id, 'registrada', 'sistema', null);

  return jsonb_build_object(
    'ok', true,
    'ocorrencia_id', v_id,
    'estado', 'candidata',
    'precisa_confirmar', v_precisa,
    'motivo_ambiguidade', case when v_precisa then 'participante_ambiguo_ou_externo' else null end,
    'ja_existia', false
  );
end
$fn$;

comment on function public.fabio_participacao_registrar_candidata(integer, integer, integer, integer, text, text, text, text, text, text) is
  'Registra a candidata de substituicao em SHADOW (fato + evento registrada). Nao toca presenca/registro/Emusys. Idempotente por origem_message_id.';

-- ── RPC 3: confirmar (professor concorda) ────────────────────────────────────
-- So de candidata; de confirmada e idempotente; do resto recusa.
create or replace function public.fabio_participacao_confirmar(
  p_ocorrencia_id uuid,
  p_professor_id integer
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $fn$
declare
  v_estado text;
begin
  select estado_atual into v_estado
    from public.vw_fabio_participacao_ocorrencia_estado where ocorrencia_id = p_ocorrencia_id;

  if v_estado is null then
    return jsonb_build_object('ok', false, 'estado', null, 'motivo', 'ocorrencia_inexistente');
  end if;

  if v_estado = 'confirmada' then
    return jsonb_build_object('ok', true, 'estado', 'confirmada');   -- idempotente: nao empilha
  end if;

  if v_estado <> 'candidata' then
    return jsonb_build_object('ok', false, 'estado', v_estado, 'motivo', 'so confirma candidata');
  end if;

  insert into public.fabio_participacao_ocorrencia_eventos (ocorrencia_id, evento, por_tipo, por_id)
  values (p_ocorrencia_id, 'confirmada', 'professor', p_professor_id::text);

  return jsonb_build_object('ok', true, 'estado', 'confirmada');
end
$fn$;

comment on function public.fabio_participacao_confirmar(uuid, integer) is
  'candidata->confirmada (professor). Idempotente de confirmada. SHADOW: so avanca o ciclo, sem efeito operacional.';

-- ── RPC 4: validar (coordenacao — portao de fase futura) ─────────────────────
-- So de confirmada; de validada e idempotente; do resto recusa.
create or replace function public.fabio_participacao_validar(
  p_ocorrencia_id uuid,
  p_validado_por uuid
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $fn$
declare
  v_estado text;
begin
  select estado_atual into v_estado
    from public.vw_fabio_participacao_ocorrencia_estado where ocorrencia_id = p_ocorrencia_id;

  if v_estado is null then
    return jsonb_build_object('ok', false, 'estado', null, 'motivo', 'ocorrencia_inexistente');
  end if;

  if v_estado = 'validada' then
    return jsonb_build_object('ok', true, 'estado', 'validada');   -- idempotente
  end if;

  if v_estado <> 'confirmada' then
    return jsonb_build_object('ok', false, 'estado', v_estado, 'motivo', 'so valida confirmada');
  end if;

  insert into public.fabio_participacao_ocorrencia_eventos (ocorrencia_id, evento, por_tipo, por_id)
  values (p_ocorrencia_id, 'validada', 'coordenacao', p_validado_por::text);

  return jsonb_build_object('ok', true, 'estado', 'validada');
end
$fn$;

comment on function public.fabio_participacao_validar(uuid, uuid) is
  'confirmada->validada (coordenacao). Portao de fase futura. Nesta fase apenas carimba, sem efeito.';

-- ── RPC 5: descartar ─────────────────────────────────────────────────────────
-- De candidata/confirmada; de descartada e idempotente; validada/corrigida
-- recusam (validada so se desfaz por correcao, nunca por descarte).
create or replace function public.fabio_participacao_descartar(
  p_ocorrencia_id uuid,
  p_motivo text,
  p_por_tipo text,
  p_por_id text
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $fn$
declare
  v_estado text;
begin
  select estado_atual into v_estado
    from public.vw_fabio_participacao_ocorrencia_estado where ocorrencia_id = p_ocorrencia_id;

  if v_estado is null then
    return jsonb_build_object('ok', false, 'estado', null, 'motivo', 'ocorrencia_inexistente');
  end if;

  if v_estado = 'descartada' then
    return jsonb_build_object('ok', true, 'estado', 'descartada');   -- idempotente
  end if;

  if v_estado not in ('candidata', 'confirmada') then
    return jsonb_build_object('ok', false, 'estado', v_estado, 'motivo', 'so descarta candidata ou confirmada');
  end if;

  insert into public.fabio_participacao_ocorrencia_eventos (ocorrencia_id, evento, por_tipo, por_id, dados)
  values (p_ocorrencia_id, 'descartada', coalesce(p_por_tipo, 'sistema'), p_por_id,
          jsonb_build_object('motivo', p_motivo));

  return jsonb_build_object('ok', true, 'estado', 'descartada');
end
$fn$;

comment on function public.fabio_participacao_descartar(uuid, text, text, text) is
  'candidata/confirmada -> descartada, com motivo em dados. Recusa validada (so correcao desfaz) e corrigida.';

-- ── Portas fechadas: so service_role executa. ────────────────────────────────
-- Funcao ganha EXECUTE a PUBLIC por default; tiramos e devolvemos so a service_role.
revoke all on function public.fn_participacao_nome_tokens(text) from public, anon, authenticated;
revoke all on function public.fn_participacao_nome_casa(text, text) from public, anon, authenticated;
revoke all on function public.fabio_resolver_participante(integer, uuid, text) from public, anon, authenticated;
revoke all on function public.fabio_participacao_registrar_candidata(integer, integer, integer, integer, text, text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.fabio_participacao_confirmar(uuid, integer) from public, anon, authenticated;
revoke all on function public.fabio_participacao_validar(uuid, uuid) from public, anon, authenticated;
revoke all on function public.fabio_participacao_descartar(uuid, text, text, text) from public, anon, authenticated;

grant execute on function public.fn_participacao_nome_tokens(text) to service_role;
grant execute on function public.fn_participacao_nome_casa(text, text) to service_role;
grant execute on function public.fabio_resolver_participante(integer, uuid, text) to service_role;
grant execute on function public.fabio_participacao_registrar_candidata(integer, integer, integer, integer, text, text, text, text, text, text) to service_role;
grant execute on function public.fabio_participacao_confirmar(uuid, integer) to service_role;
grant execute on function public.fabio_participacao_validar(uuid, uuid) to service_role;
grant execute on function public.fabio_participacao_descartar(uuid, text, text, text) to service_role;
