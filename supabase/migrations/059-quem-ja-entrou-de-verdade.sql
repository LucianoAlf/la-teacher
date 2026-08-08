-- 059 — o painel para de mentir sobre quem já entrou
--
-- ⚠️ SUPERADA PELA 062 no que diz respeito à GUARDA. Esta versão libera o
-- painel pra `usuarios.perfil = 'admin'` — 11 pessoas, incluindo Marketing e
-- Comercial. A 062 trocou isso pela lista `la_teacher_coordenacao`.
-- Reaplicar este arquivo sozinho REABRE o painel pras 11. Se precisar dele,
-- rode a 062 logo depois. (O teste desta migration continua válido: ele roda
-- contra a versão daqui, de propósito.)
--
-- O DADO NÃO EXISTIA. A 057 leu `usuarios.ultimo_acesso` pra dizer se o professor
-- já tinha usado o app. Medido em produção hoje: **0 de 29** usuários têm essa
-- coluna preenchida, e a única função no banco inteiro que a menciona é a minha —
-- ou seja, ninguém escreve nela. Nunca escreveu.
--
-- O efeito: o painel carimba "liberado, ainda não entrou" em TODO MUNDO, para
-- sempre. O Matheus entrou hoje às 15:16 e continua aparecendo como quem nunca
-- abriu. Na segunda de manhã essa é exatamente a pergunta que a coordenação vai
-- fazer pro painel — "quem já usou?" — e ele responderia "ninguém", com cara de
-- resposta.
--
-- A verdade mora em `auth.users.last_sign_in_at`, que o próprio Supabase Auth
-- escreve a cada login. Não precisa de gatilho, de coluna nova, nem de rotina:
-- precisa ler onde o dado está.
--
-- É `security definer` com dono `postgres`, então enxerga `auth.users`. O
-- `search_path` fixo em 'public' não atrapalha: a referência é qualificada.
--
-- Teste: 059-quem-ja-entrou-de-verdade.test.sql
-- Mutantes: scripts/mutantes-059.mjs

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
            -- Quem o Auth diz que entrou, não quem a nossa coluna vazia diz.
            'ultimo_acesso', au.last_sign_in_at,
            'experimentais_7d', (
              select count(*) from public.lead_experimentais le
               where le.professor_experimental_id = p.id
                 and le.status = 'experimental_agendada'
                 and le.data_experimental between (now() at time zone 'America/Sao_Paulo')::date
                                              and (now() at time zone 'America/Sao_Paulo')::date + 7)
          ) as x
        from public.professores p
        left join public.usuarios u  on u.id = p.usuario_id
        left join auth.users     au  on au.id = u.auth_user_id
       where p.ativo
      ) s);
end
$function$;

revoke all on function public.app_professores_para_liberar() from public, anon;
grant execute on function public.app_professores_para_liberar() to authenticated;
