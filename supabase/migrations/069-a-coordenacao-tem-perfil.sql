-- 069 — a coordenação tem perfil
--
-- O DEFEITO: o painel ganhou um link "Meu perfil" que não abria nada. A
-- `app_meu_perfil` (a do professor) lê de `professores` filtrando por
-- `fn_professor_do_usuario()` — e a Juliana, o Quintela, o Hugo e o Alf NÃO são
-- professores. A RPC devolvia vazio, e a rota `/app/perfil` ainda por cima mora
-- dentro do `RequireProfessor`, que manda quem não tem vínculo pra tela de
-- "vínculo pendente". Ou seja: o dono do painel batia na porta de quem não tem
-- acesso. Eu criei esse link.
--
-- A coordenação não precisa de tabela nova: `usuarios` já guarda nome, apelido,
-- email, cargo, telefone e `avatar_url`. O que faltava era a porta.
--
-- Esta RPC NÃO substitui a do professor. São duas identidades diferentes no
-- mesmo app, e misturar as duas numa função só faria a resposta depender de um
-- `case` — que é onde nasce o perfil que mostra o dado do outro.

create or replace function public.app_meu_perfil_coordenacao()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_saida jsonb;
begin
  if not public.fn_e_coordenacao_la_teacher() then
    raise exception 'apenas_admin';
  end if;

  select jsonb_build_object(
           'usuario_id',  u.id,
           'nome',        u.nome,
           'apelido',     u.apelido,
           'email',       u.email,
           'cargo',       u.cargo,
           'telefone',    u.telefone,
           'avatar_url',  u.avatar_url,
           -- Quantas unidades essa pessoa coordena não existe como conceito
           -- hoje (a coordenação vê tudo, decisão do Alf em 08/08). Devolver o
           -- campo agora, sempre 'todas', evita que a tela invente depois.
           'alcance',     'todas as unidades')
    into v_saida
    from public.usuarios u
   where u.auth_user_id = auth.uid()
     and coalesce(u.ativo, true);

  -- Aqui havia um `if v_saida is null then raise apenas_admin`. Ele foi
  -- REMOVIDO porque o mutante que o apagava SOBREVIVEU ao teste — e o mutante
  -- estava certo: `fn_e_coordenacao_la_teacher()` lê a MESMA `usuarios` com o
  -- mesmo predicado (`auth_user_id = auth.uid()` e `ativo`). Se o guard passou,
  -- a linha existe. A checagem era defesa contra um estado inalcançável, e
  -- código que nenhum teste consegue exercitar é código que ninguém mantém.
  return v_saida;
end;
$function$;

-- `create or replace` PRESERVA privilégios: sem o revoke explícito, um grant
-- antigo sobrevive à substituição e o mutante de permissão passa batido.
revoke all on function public.app_meu_perfil_coordenacao() from public;
revoke all on function public.app_meu_perfil_coordenacao() from anon;
grant execute on function public.app_meu_perfil_coordenacao() to authenticated;

comment on function public.app_meu_perfil_coordenacao() is
  'Perfil de quem e da coordenacao, lido de usuarios (nao de professores). '
  'A app_meu_perfil e do PROFESSOR e devolve vazio pra coordenacao. '
  'So coordenacao (fn_e_coordenacao_la_teacher, 062).';
