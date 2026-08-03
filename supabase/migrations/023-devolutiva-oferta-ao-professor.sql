-- 023 — a oferta da devolutiva ao professor
--
-- A 020 gera a devolutiva e ela fica parada em `gerada`. Ninguém avisa o
-- professor, então na prática ela não existe. Esta migration fecha esse vão
-- com as duas RPCs que o worker de notificação precisa:
--
--   fabio_devolutivas_a_oferecer(p_limite)  -> o que oferecer, por professor
--   fabio_devolutiva_oferecida(p_id, ...)   -> carimba, fechando o ciclo
--
-- O TRANSPORTE JÁ EXISTE. A 018 criou fabio_claim_notificacao_por_referencia
-- com o índice único parcial uq_fabio_notif_por_referencia. A oferta usa
-- referencia_tipo='devolutiva' + referencia_id=<id>, então dois workers
-- concorrentes (ou o mesmo worker rodando duas vezes no timer de 5 min) não
-- conseguem ofertar a mesma devolutiva duas vezes: o segundo claim não
-- reivindica.
--
-- POR QUE NÃO É UM EventSpec COMO OS OUTROS
-- briefing e pendência disparam por RELÓGIO (is_due(agora, "08:00", janela)).
-- A devolutiva fica pronta quando o professor confirma o registro, a qualquer
-- hora. Por isso é uma varredura de fila, não um horário-alvo.

-- ---------------------------------------------------------------- a oferecer

create or replace function public.fabio_devolutivas_a_oferecer(p_limite integer default 50)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with prontas as (
    select
      d.id,
      d.professor_id,
      d.aluno_id,
      coalesce(a.nome, 'Aluno')        as aluno_nome,
      d.destinatario,
      d.destinatario_nome,
      d.criado_em
    from fabio_devolutivas d
    join alunos a on a.id = d.aluno_id
    where d.status = 'gerada'
      and d.oferecida_em is null
      -- Fail closed: sem destinatário decidido e sem texto, não há o que
      -- oferecer. Melhor a devolutiva ficar parada e visível na fila do que
      -- o professor receber um aviso sobre algo que não dá para usar.
      and d.destinatario is not null
      and coalesce(nullif(btrim(d.texto_normal), ''), null) is not null
    order by d.criado_em asc
    limit greatest(1, least(coalesce(p_limite, 50), 500))
  )
  select coalesce(
    jsonb_agg(prof order by prof->>'professor_id'),
    '[]'::jsonb
  )
  from (
    select jsonb_build_object(
             'professor_id', p.professor_id,
             'total', count(*),
             'devolutivas', jsonb_agg(
                jsonb_build_object(
                  'id', p.id,
                  'aluno_id', p.aluno_id,
                  'aluno_nome', p.aluno_nome,
                  'destinatario', p.destinatario,
                  'destinatario_nome', p.destinatario_nome
                ) order by p.aluno_nome
             )
           ) as prof
    from prontas p
    group by p.professor_id
  ) agrupado;
$$;

comment on function public.fabio_devolutivas_a_oferecer(integer) is
'Devolutivas geradas que ainda nao foram oferecidas, agrupadas por professor. '
'Exige destinatario decidido E texto nao vazio -- sem isso nao ha o que oferecer.';

-- ---------------------------------------------------------------- carimbo

create or replace function public.fabio_devolutiva_oferecida(
  p_id uuid,
  p_notificacao_id uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_afetadas integer;
begin
  -- Só sai de `gerada` e só carimba uma vez. Se outro worker chegou antes,
  -- zero linhas: quem chamou descobre que a oferta não era dele e não deve
  -- enviar nada.
  update fabio_devolutivas
     set status = 'oferecida',
         oferecida_em = now(),
         atualizado_em = now()
   where id = p_id
     and status = 'gerada'
     and oferecida_em is null;
  get diagnostics v_afetadas = row_count;

  if v_afetadas = 0 then
    return jsonb_build_object('ok', false, 'motivo', 'ja_oferecida_ou_status_mudou');
  end if;
  return jsonb_build_object('ok', true, 'id', p_id, 'notificacao_id', p_notificacao_id);
end;
$$;

comment on function public.fabio_devolutiva_oferecida(uuid, uuid) is
'Carimba oferecida_em e move gerada -> oferecida. Zero linhas = alguem chegou antes.';

-- ---------------------------------------------------------------- permissões
-- Função SECURITY DEFINER nasce com EXECUTE para PUBLIC no Supabase. Isso já
-- mordeu antes (018b): um CREATE OR REPLACE reabriu o acesso a anon depois de
-- um DROP ter levado o REVOKE junto. Revogar sempre, explicitamente.

revoke all on function public.fabio_devolutivas_a_oferecer(integer) from public, anon, authenticated;
revoke all on function public.fabio_devolutiva_oferecida(uuid, uuid)  from public, anon, authenticated;
grant execute on function public.fabio_devolutivas_a_oferecer(integer) to service_role;
grant execute on function public.fabio_devolutiva_oferecida(uuid, uuid)  to service_role;
