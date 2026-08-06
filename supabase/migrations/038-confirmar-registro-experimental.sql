-- 038 — confirmar o registro: presenca + aviso na MESMA transacao
--
-- Meia confirmacao e o pior estado possivel: presenca gravada e comercial sem
-- saber, sem nada sinalizando. Por isso as duas escritas vivem numa funcao so
-- — se o aviso falhar, a confirmacao inteira volta atras.
--
-- Sem esta migration, as quatro anteriores sao pecas corretas que nao se
-- falam: o registro nasce 'aguardando_confirmacao' e nada o move dali, a
-- presenca depende de alguem chamar a funcao a mao, e o aviso nunca entra
-- na fila.

create or replace function public.app_confirmar_registro_experimental(
  p_registro_id    uuid,
  p_confirmado_por integer
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_vinculo_id  bigint;
  v_status      text;
  v_origem      text;
  v_prof        integer := public.fn_professor_do_usuario();
  v_prof_aula   integer;
  v_presenca_ok boolean;
  v_aviso       jsonb;
  v_not_id      uuid;
begin
  if v_prof is null then
    raise exception 'sem_professor_vinculado';
  end if;

  select r.vinculo_id, r.status, r.origem, ae.professor_id
    into v_vinculo_id, v_status, v_origem, v_prof_aula
    from lead_experimental_registros r
    join lead_experimental_aulas v on v.id = r.vinculo_id
    join aulas_emusys ae on ae.id = v.aula_local_id
   where r.id = p_registro_id
     for update of r;

  if not found then
    raise exception 'registro_inexistente: %', p_registro_id;
  end if;

  -- Mesma guarda da app_registrar_experimental: confirmar tambem e escrita.
  -- Confirmar grava presenca de fonte FORTE, promove o estado do vinculo e
  -- dispara aviso ao comercial — nao e leitura.
  if v_prof_aula is distinct from v_prof then
    raise exception 'aula_de_outro_professor';
  end if;

  if v_status = 'confirmado' then
    -- Idempotente: confirmar duas vezes nao duplica aviso nem regrava presenca.
    return jsonb_build_object('registro_id', p_registro_id, 'ja_confirmado', true);
  end if;

  if v_status = 'descartado' then
    raise exception 'registro_descartado: %', p_registro_id;
  end if;

  update lead_experimental_registros
     set status = 'confirmado', confirmado_em = now(), confirmado_por = p_confirmado_por,
         atualizado_em = now()
   where id = p_registro_id;

  -- Presenca com a fonte certa: registro pelo app e professor_la_teacher;
  -- por audio e fabio_audio. Ambos passam em fn_presenca_e_forte — e NENHUM
  -- deles e 'professor_app', que nao existe no vocabulario e faria a presenca
  -- nascer fraca em silencio. (Bloqueio do Alfredo na revisao da spec.)
  select public.fn_registrar_presenca_experimental(
           v_vinculo_id, 'presente',
           case when v_origem = 'whatsapp' then 'fabio_audio' else 'professor_la_teacher' end)
    into v_presenca_ok;

  select public.fabio_claim_aviso_comercial(p_registro_id) into v_aviso;
  v_not_id := (v_aviso->>'notificacao_id')::uuid;

  return jsonb_build_object(
    'registro_id',      p_registro_id,
    'presenca_gravada', v_presenca_ok,
    'notificacao_id',   v_not_id,
    'aviso_claimed',    (v_aviso->>'claimed')::boolean,
    'aviso_motivo',     v_aviso->>'motivo'
  );
end
$function$;

revoke all on function public.app_confirmar_registro_experimental(uuid,integer) from public, anon;
grant execute on function public.app_confirmar_registro_experimental(uuid,integer) to service_role, authenticated;

comment on function public.app_confirmar_registro_experimental(uuid,integer) is
'Confirma o registro da experimental: marca confirmado, grava presenca de fonte forte e enfileira o aviso ao comercial NA MESMA TRANSACAO. Meia confirmacao (presenca sim, aviso nao) e pior que nenhuma. Resolve auth.uid() e exige que a aula seja do professor logado.';
