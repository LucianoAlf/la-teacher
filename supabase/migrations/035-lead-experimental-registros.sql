-- 035 — registro da experimental: tabela propria + RPC canonica
--
-- TABELA PROPRIA, e nao molde novo em fabio_registros_aula: das 13 RPCs que
-- leem aquela tabela, 12 NAO filtram por molde (medido em 05/08/2026). Duas
-- causariam dano real: fabio_enfileirar_devolutivas mandaria devolutiva pra
-- FAMILIA de um lead (viola D1 da spec — a familia nao recebe mensagem do
-- Fabio nesta fase), e fabio_emitir_presenca_por_registro escreveria em
-- aluno_presenca, que exige aluno_id NOT NULL (e o lead ainda nao e aluno).
-- Tabela separada torna o vazamento impossivel por construcao, em vez de
-- depender de cada RPC futura lembrar de filtrar.

create table public.lead_experimental_registros (
  id                    uuid primary key default gen_random_uuid(),
  vinculo_id            bigint not null references public.lead_experimental_aulas(id),
  unidade_id            uuid not null references public.unidades(id),
  professor_id          integer references public.professores(id),

  -- BLOCO FAMILY-SAFE: o consultor pode mostrar/adaptar para a familia
  anotacao_pedagogica   text,
  devolutiva_familia    text,
  proximos_passos       text,

  -- BLOCO INTERNO: nunca sai para a familia
  leitura_de_conversao  text,

  origem                text not null default 'app'
                        check (origem in ('app','whatsapp')),
  audio_id              uuid references public.fabio_fila_audios(id),
  status                text not null default 'rascunho'
                        check (status in ('rascunho','aguardando_confirmacao','confirmado','descartado')),
  confirmado_em         timestamptz,
  confirmado_por        integer references public.usuarios(id),
  criado_em             timestamptz not null default now(),
  atualizado_em         timestamptz not null default now()
);

create unique index uq_lead_exp_registro_vigente
    on public.lead_experimental_registros (vinculo_id)
 where status <> 'descartado';

comment on column public.lead_experimental_registros.leitura_de_conversao is
'INTERNO. Nunca sai em view family-safe. Ver spec 2026-08-05-registro-aula-experimental-design.md §3.';

-- ---------------------------------------------------------------------------
-- Funcao INTERNA: faz o trabalho, so service_role executa.
--
-- O indice unico REJEITA (unique_violation); ele nao transforma a segunda
-- tentativa em edicao — quem faz isso e codigo (achado do Alfredo). E
-- unidade_id/professor_id sao DERIVADOS do vinculo: se viessem do cliente,
-- nasceria registro de aula de uma unidade carimbado em outra. Por isso nao
-- existe parametro pra eles.
-- ---------------------------------------------------------------------------
create or replace function public.fn_registrar_experimental_interno(
  p_vinculo_id            bigint,
  p_anotacao_pedagogica   text,
  p_devolutiva_familia    text,
  p_proximos_passos       text,
  p_leitura_de_conversao  text,
  p_origem                text default 'app'
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_estado       text;
  v_unidade_id   uuid;
  v_professor_id integer;
  v_registro_id  uuid;
begin
  select v.estado, ae.unidade_id, ae.professor_id
    into v_estado, v_unidade_id, v_professor_id
    from lead_experimental_aulas v
    join aulas_emusys ae on ae.id = v.aula_local_id
   where v.id = p_vinculo_id and v.substituido_em is null
     for update of v;

  if not found then
    raise exception 'vinculo_inexistente_ou_sem_aula: %', p_vinculo_id;
  end if;

  -- Travas de estado (spec §6): sem aula nao ha o que registrar, e aula que
  -- nao aconteceu nao tem capitulo pedagogico. Declarar falta e caminho
  -- proprio (fn_registrar_presenca_experimental), nao formulario.
  if v_estado = 'pendente' then
    raise exception 'experimental_sem_aula_vinculada';
  elsif v_estado = 'faltou' then
    raise exception 'experimental_faltou_nao_tem_registro';
  elsif v_estado = 'cancelado' then
    raise exception 'experimental_cancelada';
  end if;

  select id into v_registro_id
    from lead_experimental_registros
   where vinculo_id = p_vinculo_id and status <> 'descartado';

  if found then
    update lead_experimental_registros
       set anotacao_pedagogica  = p_anotacao_pedagogica,
           devolutiva_familia   = p_devolutiva_familia,
           proximos_passos      = p_proximos_passos,
           leitura_de_conversao = p_leitura_de_conversao,
           origem               = p_origem,
           atualizado_em        = now()
     where id = v_registro_id;
  else
    insert into lead_experimental_registros
      (vinculo_id, unidade_id, professor_id, anotacao_pedagogica, devolutiva_familia,
       proximos_passos, leitura_de_conversao, origem, status)
    values
      (p_vinculo_id, v_unidade_id, v_professor_id, p_anotacao_pedagogica, p_devolutiva_familia,
       p_proximos_passos, p_leitura_de_conversao, p_origem, 'aguardando_confirmacao')
    returning id into v_registro_id;
  end if;

  return v_registro_id;
end
$function$;

-- ---------------------------------------------------------------------------
-- Camada publica: resolve o usuario, confere posse, delega.
--
-- SEGURANCA: security definer + grant a authenticated + id cru = qualquer
-- usuario logado registrando a experimental de qualquer professor. O padrao da
-- casa esta escrito na 001, secao 6: "o professor NUNCA passa o proprio id;
-- tudo resolve via auth.uid() -> fn_professor_do_usuario". (Achado do Alfredo.)
-- ---------------------------------------------------------------------------
create or replace function public.app_registrar_experimental(
  p_vinculo_id            bigint,
  p_anotacao_pedagogica   text,
  p_devolutiva_familia    text,
  p_proximos_passos       text,
  p_leitura_de_conversao  text,
  p_origem                text default 'app'
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_prof      integer := public.fn_professor_do_usuario();
  v_prof_aula integer;
begin
  if v_prof is null then
    raise exception 'sem_professor_vinculado';
  end if;

  select ae.professor_id into v_prof_aula
    from lead_experimental_aulas v
    join aulas_emusys ae on ae.id = v.aula_local_id
   where v.id = p_vinculo_id and v.substituido_em is null;

  if not found then
    raise exception 'vinculo_inexistente_ou_sem_aula: %', p_vinculo_id;
  end if;

  -- A aula tem que ser DELE. Sem isto, qualquer autenticado registra a
  -- experimental de qualquer professor.
  if v_prof_aula is distinct from v_prof then
    raise exception 'aula_de_outro_professor';
  end if;

  return public.fn_registrar_experimental_interno(
           p_vinculo_id, p_anotacao_pedagogica, p_devolutiva_familia,
           p_proximos_passos, p_leitura_de_conversao, p_origem);
end
$function$;

-- A garantia e de PERMISSAO, nao de convencao: escrita direta na tabela fica
-- sem grant, entao nao existe caminho que contorne as travas acima.
revoke all on table public.lead_experimental_registros from public, anon, authenticated;
grant select on table public.lead_experimental_registros to service_role;
revoke all on function public.fn_registrar_experimental_interno(bigint,text,text,text,text,text) from public, anon, authenticated;
grant execute on function public.fn_registrar_experimental_interno(bigint,text,text,text,text,text) to service_role;
revoke all on function public.app_registrar_experimental(bigint,text,text,text,text,text) from public, anon;
grant execute on function public.app_registrar_experimental(bigint,text,text,text,text,text) to service_role, authenticated;

comment on table public.lead_experimental_registros is
'Registro pedagogico da aula experimental. Escrita SO por app_registrar_experimental (que confere posse) ou fn_registrar_experimental_interno (service_role). Ver spec 2026-08-05-registro-aula-experimental-design.md.';
