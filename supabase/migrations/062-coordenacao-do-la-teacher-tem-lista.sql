-- 062 — a coordenação do LA Teacher passa a ter lista própria
--
-- EU EMPRESTEI UM CONCEITO QUE NÃO ERA MEU.
--
-- A 057 abriu o painel da equipe pra `usuarios.perfil = 'admin'`. Esse perfil
-- é do LA Report, e lá ele quer dizer "vê a escola inteira" — Marketing,
-- Comercial, Financeiro. Medido em 08/08/2026: **11 pessoas** são admin, e as
-- 11 podiam liberar acesso de professor e disparar WhatsApp em nome do Fábio.
--
-- "Admin no LA Report" não é "coordenação pedagógica do LA Teacher". São dois
-- papéis diferentes que por acaso moram na mesma coluna de uma tabela
-- compartilhada por quatro sistemas.
--
-- A LISTA É EXPLÍCITA, E ISSO É O PONTO
-- Entrar aqui é um ato: alguém escreve o nome. Não se herda de um perfil que
-- outro sistema mantém por outros motivos. A tabela é do LA Teacher e diz uma
-- coisa só — quem cuida dos professores neste app.
--
-- `usuarios.ativo` continua valendo como desligamento: quem sai da escola sai
-- de tudo por um interruptor só. Já `perfil` deixou de mandar aqui, de
-- propósito — a coordenação não pode perder o painel porque o LA Report
-- reclassificou alguém.
--
-- RLS LIGADO E SEM POLICY: ninguém lê esta tabela pelo PostgREST. Quem
-- responde "você é da coordenação?" é a função abaixo, que é security definer
-- e só devolve um booleano sobre QUEM PERGUNTOU. Expor a lista seria entregar
-- de graça o alvo de quem quisesse escalar privilégio.
--
-- Teste: 062-coordenacao-do-la-teacher-tem-lista.test.sql
-- Mutantes: scripts/mutantes-062.mjs

create table if not exists public.la_teacher_coordenacao (
  usuario_id integer primary key references public.usuarios(id) on delete cascade,
  criado_em  timestamptz not null default now(),
  criado_por text
);

alter table public.la_teacher_coordenacao enable row level security;
revoke all on table public.la_teacher_coordenacao from public, anon, authenticated;

comment on table public.la_teacher_coordenacao is
'Quem cuida dos professores no LA Teacher. NAO e o mesmo que usuarios.perfil=admin (que e do LA Report e inclui Marketing/Comercial). Entrar aqui e um ato explicito.';

-- Os quatro de hoje, por e-mail e não por id: id de tabela compartilhada muda
-- de significado sem avisar; e-mail é a pessoa.
insert into public.la_teacher_coordenacao (usuario_id, criado_por)
select u.id, 'migration 062 — combinado com o Alf em 08/08/2026'
  from public.usuarios u
 where u.email in (
   'lucianoalf.la@gmail.com',   -- Luciano Alf — diretor geral
   'hugo@gmail.com',            -- Hugo — coordenador de tecnologia
   'juliana@lamusic.com.br',    -- Juliana — coordenadora da LA Music School
   'quintela@lamusic.com.br'    -- Quintela — coordenador da LA Music Kids
 )
on conflict (usuario_id) do nothing;

-- A pergunta é sempre sobre quem está perguntando. Não recebe id de ninguém:
-- parâmetro seria mais um jeito de descobrir a lista testando nome por nome.
create or replace function public.fn_e_coordenacao_la_teacher()
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  select exists (
    select 1
      from public.la_teacher_coordenacao c
      join public.usuarios u on u.id = c.usuario_id
     where u.auth_user_id = auth.uid()
       and coalesce(u.ativo, true)
  );
$function$;

revoke all on function public.fn_e_coordenacao_la_teacher() from public, anon;
grant execute on function public.fn_e_coordenacao_la_teacher() to authenticated, service_role;

-- O painel passa a perguntar pra lista, não pro perfil.
create or replace function public.app_professores_para_liberar()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
begin
  -- O erro continua sendo `apenas_admin`: o cliente já traduz esse nome, e
  -- trocá-lo aqui quebraria a tela sem melhorar nada pra quem lê.
  if not public.fn_e_coordenacao_la_teacher() then
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
            -- Quem o Auth diz que entrou, não a coluna vazia (059).
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
