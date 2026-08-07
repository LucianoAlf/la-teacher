-- 054 — quem confirmou volta a ter nome
--
-- DOIS DEFEITOS NA MESMA LINHA, achados percorrendo o ciclo do Rafael a mao.
--
-- 1. `confirmado_por` NUNCA foi gravado. A RPC recebia o autor por parametro,
--    e o cliente mandava `p_confirmado_por: null` — sempre. A coluna existe
--    pra responder "quem apertou o botao que mandou a mensagem pro comercial",
--    e estava vazia em 100% das linhas (medido: 0 de 0 com autor, porque a
--    primeira confirmacao real ainda nao aconteceu; ia nascer torta).
--
-- 2. O parametro era FORJAVEL. Qualquer professor autenticado podia carimbar
--    o id de outro usuario como autor da confirmacao. E a regra da casa e a
--    oposta e esta escrita em todas as outras RPCs deste ciclo: o professor
--    nunca passa o proprio id, quem resolve e auth.uid().
--
-- O segundo defeito nao chegou a doer porque o primeiro o escondia: quem manda
-- null nunca forja nada. Consertar so o "nao grava" abriria a porta do outro.
--
-- COMPATIBILIDADE: a assinatura antiga (uuid, integer) continua existindo como
-- casca que IGNORA o segundo parametro e delega. Sem isso, toda aba aberta com
-- o bundle velho quebraria ate recarregar — e o custo de manter a casca e uma
-- linha.
--
-- Gerado por extracao (pg_get_functiondef), nao transcrito: o corpo tem ~120
-- linhas de regra (correcao da 048, lease zero da 042, presenca forte) e
-- reescrever a mao pra mudar duas linhas e como se perde uma clausula.
--
-- Teste: 054-quem-confirmou-tem-nome.test.sql
-- Mutantes: scripts/mutantes-054.mjs

CREATE OR REPLACE FUNCTION public.app_confirmar_registro_experimental(p_registro_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_vinculo_id  bigint;
  v_status      text;
  v_origem      text;
  v_prof        integer := public.fn_professor_do_usuario();
  v_usuario     integer;
  v_prof_aula   integer;
  v_presenca_ok boolean;
  v_aviso       jsonb;
  v_not_id      uuid;
begin
  if v_prof is null then
    raise exception 'sem_professor_vinculado';
  end if;

  -- Quem confirmou sai do auth.uid(), nunca de parametro. Era o unico lugar do
  -- ciclo em que o cliente informava identidade — e o cliente mandava null.
  select u.id into v_usuario from usuarios u
   where u.auth_user_id = auth.uid();

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
    -- Confirmar de novo E o caminho da CORRECAO: fn_registrar_experimental_interno
    -- atualiza a MESMA linha (indice uq_lead_exp_registro_vigente e por vinculo),
    -- entao corrigir nao cria registro novo — muda o texto deste.
    --
    -- Antes desta migration o retorno antecipado daqui matava a correcao em
    -- silencio: o professor arrumava o prontuario e a Daiana ficava com a
    -- versao velha, sem nada sinalizando.
    --
    -- Agora a idempotencia mora onde ela e estrutural: o claim so reabre linha
    -- ENTREGUE quando o conteudo mudou. Reconfirmar sem editar passa por aqui,
    -- nao gera mensagem, e devolve ja_confirmado — igual a antes.
    select public.fabio_claim_aviso_comercial(p_registro_id, 0) into v_aviso;
    return jsonb_build_object(
      'registro_id',   p_registro_id,
      'ja_confirmado', true,
      'correcao',      coalesce((v_aviso->>'claimed')::boolean, false),
      'aviso_motivo',  v_aviso->>'motivo');
  end if;

  if v_status = 'descartado' then
    raise exception 'registro_descartado: %', p_registro_id;
  end if;

  update lead_experimental_registros
     set status = 'confirmado', confirmado_em = now(), confirmado_por = v_usuario,
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

  -- p_lease_minutos => 0: a confirmacao ENFILEIRA, nao trabalha.
  -- Lease serve pra dizer "estou trabalhando nisto agora". Quem confirma nao
  -- esta: ele enfileira e vai embora. Quem trabalha e o worker, e o lease de
  -- verdade e o dele — com o token que ele mesmo usa pra fechar a linha.
  select public.fabio_claim_aviso_comercial(p_registro_id, 0) into v_aviso;
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


-- Casca de compatibilidade. O segundo parametro e ignorado de proposito: ele
-- era o buraco. Quem chamar por aqui recebe o comportamento certo.
create or replace function public.app_confirmar_registro_experimental(
  p_registro_id uuid, p_confirmado_por integer
) returns jsonb
language sql
security invoker
set search_path to 'public'
as $compat$
  select public.app_confirmar_registro_experimental(p_registro_id);
$compat$;

revoke all on function public.app_confirmar_registro_experimental(uuid) from public, anon;
grant execute on function public.app_confirmar_registro_experimental(uuid) to authenticated;
revoke all on function public.app_confirmar_registro_experimental(uuid, integer) from public, anon;
grant execute on function public.app_confirmar_registro_experimental(uuid, integer) to authenticated;
