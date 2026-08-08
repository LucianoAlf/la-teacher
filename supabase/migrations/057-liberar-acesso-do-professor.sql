-- 057 — liberar o acesso de um professor
--
-- Os 44 professores JÁ EXISTEM, com aula, aluno e agenda. O que falta é só o
-- login. Por isso aqui não tem "cadastrar pessoa" como no LA Organizer: criar
-- gente nova duplicaria quem já está no sistema e quebraria o vínculo com a
-- agenda. O que existe é LIBERAR.
--
-- A corrente que o app usa é: auth.uid() → usuarios.auth_user_id → usuarios.id
-- → professores.usuario_id → professor. Esta migration é quem forja os dois
-- elos do meio.
--
-- ── IDEMPOTENTE DE PROPÓSITO ───────────────────────────────────────────────
-- Liberar duas vezes é o clique mais provável do mundo — o admin não lembra se
-- já mandou. A segunda chamada devolve `ja_liberado` e NÃO reescreve nada: se
-- reescrevesse o auth_user_id, o professor que já estava logado perderia a
-- sessão e o vínculo apontaria pra um usuário órfão.
--
-- Teste: 057-liberar-acesso-do-professor.test.sql
-- Mutantes: scripts/mutantes-057.mjs

-- ── O e-mail interno, quando não há um de verdade ──────────────────────────
create or replace function public.fn_amarrar_email_do_professor(
  p_professor_id integer,
  p_email        text
) returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_usuario integer;
begin
  select usuario_id into v_usuario from public.professores where id = p_professor_id;
  if v_usuario is null then
    return false;
  end if;
  update public.usuarios
     set email = p_email
   where id = v_usuario
     -- Só preenche o vazio. Sobrescrever e-mail de verdade por um `@la.internal`
     -- tiraria da pessoa o caminho de recuperação que ela já tinha.
     and nullif(btrim(coalesce(email, '')), '') is null;
  return found;
end
$function$;

revoke all on function public.fn_amarrar_email_do_professor(integer, text) from public, anon, authenticated;
grant execute on function public.fn_amarrar_email_do_professor(integer, text) to service_role;

-- ── Liberar ────────────────────────────────────────────────────────────────
create or replace function public.fn_liberar_acesso_professor(
  p_professor_id  integer,
  p_auth_user_id  uuid,
  p_email         text
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_prof    record;
  v_usuario integer;
begin
  select id, nome, nome_preferido, telefone_whatsapp, usuario_id, ativo
    into v_prof
    from public.professores where id = p_professor_id;

  if not found then
    raise exception 'professor_inexistente: %', p_professor_id;
  end if;
  if not v_prof.ativo then
    raise exception 'professor_inativo';
  end if;
  if nullif(btrim(coalesce(v_prof.telefone_whatsapp, '')), '') is null then
    -- Sem WhatsApp não há como entregar convite nem código. Liberar assim
    -- criaria um acesso que ninguém consegue usar, e que ninguém percebe.
    raise exception 'professor_sem_whatsapp';
  end if;

  if v_prof.usuario_id is not null then
    return jsonb_build_object(
      'ok', true, 'ja_liberado', true,
      'professor_id', p_professor_id, 'usuario_id', v_prof.usuario_id);
  end if;

  if p_auth_user_id is null or nullif(btrim(coalesce(p_email, '')), '') is null then
    raise exception 'auth_user_e_email_obrigatorios';
  end if;

  insert into public.usuarios (nome, email, telefone, perfil, cargo, ativo, auth_user_id)
  values (v_prof.nome, lower(btrim(p_email)), v_prof.telefone_whatsapp,
          'professor', 'Professor', true, p_auth_user_id)
  returning id into v_usuario;

  update public.professores set usuario_id = v_usuario where id = p_professor_id;

  return jsonb_build_object(
    'ok', true, 'ja_liberado', false,
    'professor_id', p_professor_id, 'usuario_id', v_usuario,
    'primeiro_nome', coalesce(nullif(btrim(v_prof.nome_preferido), ''),
                              split_part(btrim(v_prof.nome), ' ', 1)),
    'telefone', v_prof.telefone_whatsapp);
end
$function$;

revoke all on function public.fn_liberar_acesso_professor(integer, uuid, text) from public, anon, authenticated;
grant execute on function public.fn_liberar_acesso_professor(integer, uuid, text) to service_role;

-- ── Quem o admin vê no painel ──────────────────────────────────────────────
create or replace function public.app_professores_para_liberar()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare v_perfil text;
begin
  select u.perfil into v_perfil
    from public.usuarios u where u.auth_user_id = auth.uid() and coalesce(u.ativo, true);

  -- Painel de admin: quem não é admin não descobre a lista da equipe por aqui.
  if v_perfil is distinct from 'admin' then
    raise exception 'apenas_admin' using errcode = '42501';
  end if;

  return (
    select coalesce(jsonb_agg(jsonb_build_object(
             'professor_id',  p.id,
             'nome',          p.nome,
             'primeiro_nome', coalesce(nullif(btrim(p.nome_preferido), ''),
                                       split_part(btrim(p.nome), ' ', 1)),
             'tem_whatsapp',  (nullif(btrim(coalesce(p.telefone_whatsapp, '')), '') is not null),
             'liberado',      (p.usuario_id is not null),
             'ultimo_acesso', u.ultimo_acesso,
             -- Ordenar por quem TEM experimental essa semana não é enfeite: é a
             -- fila de quem ganha mais em entrar hoje.
             'experimentais_7d', (
               select count(*) from public.lead_experimentais le
                where le.professor_experimental_id = p.id
                  and le.status = 'experimental_agendada'
                  and le.data_experimental between (now() at time zone 'America/Sao_Paulo')::date
                                               and (now() at time zone 'America/Sao_Paulo')::date + 7)
           ) order by (p.usuario_id is not null), p.nome), '[]'::jsonb)
      from public.professores p
      left join public.usuarios u on u.id = p.usuario_id
     where p.ativo);
end
$function$;

revoke all on function public.app_professores_para_liberar() from public, anon;
grant execute on function public.app_professores_para_liberar() to authenticated;
