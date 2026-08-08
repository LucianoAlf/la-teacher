-- 058 — a fila do painel é por urgência, não por alfabeto
--
-- DIVERGÊNCIA ENTRE O QUE EU ESCREVI E O QUE O CÓDIGO FAZIA.
--
-- Na 057 eu comentei, e repeti no commit, que a lista vinha ordenada por quem
-- tem mais experimental marcada na semana — "a fila de quem ganha mais em
-- entrar hoje". O ORDER BY dizia outra coisa: `(usuario_id is not null), nome`.
-- Alfabético. Adriana (3 experimentais), Alan (0), Alexandre (2), Ana (1)…
--
-- Descobri carregando o painel de verdade, com o auth.uid() do Alf, e olhando a
-- ordem que voltou. Nenhum teste pegaria: a lista estava certa, completa e com
-- os campos certos — só na ordem errada. E a ordem É a funcionalidade aqui:
-- quem vai usar essa tela hoje decide por ela quem entra primeiro, e alfabético
-- faz liberar por acaso.
--
-- Teste: 058-a-fila-do-painel-e-por-urgencia.test.sql
-- Mutantes: scripts/mutantes-058.mjs

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
    select coalesce(jsonb_agg(x order by ja_tem, exp_7d desc, nome), '[]'::jsonb)
      from (
        select
          (p.usuario_id is not null) as ja_tem,
          p.nome,
          (select count(*) from public.lead_experimentais le
            where le.professor_experimental_id = p.id
              and le.status = 'experimental_agendada'
              and le.data_experimental between (now() at time zone 'America/Sao_Paulo')::date
                                           and (now() at time zone 'America/Sao_Paulo')::date + 7
          ) as exp_7d,
          jsonb_build_object(
            'professor_id',  p.id,
            'nome',          p.nome,
            'primeiro_nome', coalesce(nullif(btrim(p.nome_preferido), ''),
                                      split_part(btrim(p.nome), ' ', 1)),
            'tem_whatsapp',  (nullif(btrim(coalesce(p.telefone_whatsapp, '')), '') is not null),
            'liberado',      (p.usuario_id is not null),
            'ultimo_acesso', u.ultimo_acesso,
            'experimentais_7d', (
              select count(*) from public.lead_experimentais le
               where le.professor_experimental_id = p.id
                 and le.status = 'experimental_agendada'
                 and le.data_experimental between (now() at time zone 'America/Sao_Paulo')::date
                                              and (now() at time zone 'America/Sao_Paulo')::date + 7)
          ) as x
        from public.professores p
        left join public.usuarios u on u.id = p.usuario_id
       where p.ativo
      ) s);
end
$function$;

revoke all on function public.app_professores_para_liberar() from public, anon;
grant execute on function public.app_professores_para_liberar() to authenticated;
