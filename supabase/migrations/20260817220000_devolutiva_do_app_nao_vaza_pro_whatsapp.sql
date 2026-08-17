-- A devolutiva de registro feito NO APP não é empurrada no WhatsApp.
--
-- Pedido do Alf (repetido — a primeira vez não foi cumprida): "a devolutiva
-- fica dentro do app, só, a não ser que o professor peça a devolutiva lá no
-- WhatsApp".
--
-- O QUE ESTAVA ACONTECENDO (medido em 17/08/2026):
--   origem do registro | devolutivas | ofertadas no WhatsApp
--   app                |         125 |                    94
--   whatsapp           |           7 |                     0
-- Ou seja: INVERTIDO. Quem gravava no app era exatamente quem levava
-- notificação no WhatsApp. A última saiu hoje, 17/08 17:10.
--
-- POR QUE INVERTIDO: a 095 pôs uma trava aqui pra o ofertador legado não
-- competir com o `registro_recibo` — o carimbo do WhatsApp, que já carrega o
-- rascunho da devolutiva junto. A trava exclui quem TEM recibo no WhatsApp, e
-- quem tem recibo é justamente quem registrou por lá. Fechou-se um lado e o
-- outro ficou aberto: o registro do app não tem recibo, então nunca era
-- excluído.
--
-- A REGRA NOVA é estreita de propósito: só barra a origem `app`. O registro
-- feito no WhatsApp continua elegível pela mesma porta de antes (na prática já
-- não passa, porque o recibo o exclui) — eu não mato o caminho nativo do
-- WhatsApp de carona num pedido que era sobre o app.
--
-- Isto NÃO tira a devolutiva do professor: ela continua em /app/devolutivas,
-- que é onde ele confere, ajusta e decide mandar. O que some é o Fábio
-- empurrando no WhatsApp sem ele pedir.

create or replace function public.fabio_devolutivas_a_oferecer(p_limite integer default 50)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  with prontas as (
    select
      d.id,
      d.professor_id,
      d.aluno_id,
      coalesce(a.nome, 'Aluno') as aluno_nome,
      d.destinatario,
      d.destinatario_nome,
      d.criado_em
    from public.fabio_devolutivas d
    join public.alunos a on a.id = d.aluno_id
    -- O tronco é quem sabe por onde o registro entrou; a fatia herda dele.
    join public.fabio_registros_aula fatia_origem
      on fatia_origem.id = d.registro_fatia_id
    join public.fabio_registros_aula tronco
      on tronco.id = coalesce(fatia_origem.parent_id, fatia_origem.id)
    where d.status = 'gerada'
      and d.oferecida_em is null
      and d.destinatario is not null
      and nullif(btrim(d.texto_normal), '') is not null
      -- ── A trava nova: registro do app não vira notificação no WhatsApp ──
      and tronco.origem is distinct from 'app'
      and not exists (
        select 1
          from public.fabio_registros_aula fatia
          join public.fabio_notificacoes recibo
            on recibo.professor_id = d.professor_id
           and recibo.tipo = 'registro_recibo'
           and recibo.referencia_tipo = 'registro_aula'
           and recibo.referencia_id = coalesce(fatia.parent_id, fatia.id)::text
           and recibo.canal = 'whatsapp'
         where fatia.id = d.registro_fatia_id
      )
    order by d.criado_em asc
    limit greatest(1, least(coalesce(p_limite, 50), 500))
  )
  select coalesce(jsonb_agg(prof order by prof ->> 'professor_id'), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'professor_id', p.professor_id,
      'total', count(*),
      'devolutivas', jsonb_agg(jsonb_build_object(
        'id', p.id,
        'aluno_id', p.aluno_id,
        'aluno_nome', p.aluno_nome,
        'destinatario', p.destinatario,
        'destinatario_nome', p.destinatario_nome
      ) order by p.aluno_nome)
    ) as prof
    from prontas p
    group by p.professor_id
  ) agrupado;
$function$;

comment on function public.fabio_devolutivas_a_oferecer(integer) is
  'Devolutivas a oferecer por WhatsApp. NAO inclui registro feito no app: essa devolutiva fica em /app/devolutivas e o Fabio nao empurra (pedido do Alf, 17/08/2026).';
