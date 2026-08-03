-- 020e-retomar-lease-vencido.sql
--
-- ⚠️ VAZAMENTO SILENCIOSO DA FILA (achado pelo Alfredo, e ele está certo).
--
-- `fabio_devolutiva_claim` só olhava `status = 'pendente'`. Se o worker morre —
-- deploy no meio, OOM, timeout do Hermes, VPS reiniciando — a linha fica em
-- 'gerando' com um lease que vence e ninguém nunca mais volta nela.
--
-- Eu escrevi lease com prazo E escrevi cerca de token, mas não escrevi a única
-- coisa que dá sentido ao prazo: **alguém que retome quando ele vence**. Prazo
-- sem retomada é enfeite — a linha "expira" e continua parada exatamente igual.
--
-- É o mesmo defeito que a 018 consertou no transporte (lá a janela media
-- `criado_em` em vez do lease). Aqui a janela existia e ninguém a lia.
--
-- A retomada é CERCADA de graça: o claim grava um token NOVO, então o worker
-- antigo — se voltar do além — não consegue concluir, porque toda RPC de
-- conclusão exige `lease_token = p_lease_token`. Não precisa de mecanismo
-- separado; precisa só de não esquecer de retomar.
--
-- A retomada CONSOME tentativa de propósito: junto com o teto de 5 em
-- `fabio_devolutiva_falhou`, isso impede que uma linha venenosa (que derruba o
-- worker toda vez) fique em loop eterno queimando LLM. Ela vai pra 'falhou' e
-- aparece na auditoria.

create or replace function public.fabio_devolutiva_claim(
  p_worker text, p_lote integer default 5, p_lease_minutos integer default 5)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_token uuid := gen_random_uuid(); v_itens jsonb;
begin
  with alvo as (
    select d.id from public.fabio_devolutivas d
     where
       -- fila normal
       (d.status = 'pendente'
         and (d.proxima_tentativa_em is null or d.proxima_tentativa_em <= now()))
       -- <<< 020e: órfã de worker que morreu. Sem esta linha, prazo de lease
       --           não servia pra nada: a devolutiva ficava presa pra sempre.
       or (d.status = 'gerando'
         and d.lease_expira_em is not null
         and d.lease_expira_em < now())
     order by d.criado_em
     limit greatest(p_lote, 1)
     for update skip locked
  ), tomadas as (
    update public.fabio_devolutivas d
       set status = 'gerando',
           -- token NOVO: é isto que desarma o worker antigo se ele voltar.
           lease_token = v_token,
           lease_expira_em = now() + make_interval(mins => p_lease_minutos),
           tentativas = d.tentativas + 1,
           atualizado_em = now()
      from alvo where d.id = alvo.id
    returning d.id, d.registro_fatia_id, d.aluno_id, d.professor_id, d.tentativas)
  select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) into v_itens from tomadas t;

  return jsonb_build_object('ok', true, 'worker', p_worker,
                            'lease_token', v_token, 'itens', v_itens);
end $function$;

comment on function public.fabio_devolutiva_claim is
  'Claim da fila da devolutiva. Pega pendentes E órfãs de lease vencido (020e) — prazo sem retomada é enfeite. Token novo a cada claim cerca o worker antigo.';

-- Teto de tentativas também na retomada: linha que derruba o worker toda vez
-- não pode ficar em loop. Passa do teto, vira 'falhou' e sai da fila.
create or replace function public.fabio_devolutiva_ceifar_travadas(p_teto integer default 5)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_n integer;
begin
  update public.fabio_devolutivas
     set status = 'falhou',
         erro = coalesce(erro, '') || ' | teto de tentativas atingido na retomada',
         lease_token = null, lease_expira_em = null, atualizado_em = now()
   where status = 'gerando'
     and lease_expira_em is not null and lease_expira_em < now()
     and tentativas >= p_teto;
  get diagnostics v_n = row_count;
  return v_n;
end $function$;

comment on function public.fabio_devolutiva_ceifar_travadas is
  'Tira da fila a linha que já derrubou o worker p_teto vezes. Sem isto a retomada da 020e viraria loop infinito.';

revoke all on function
  public.fabio_devolutiva_claim(text, integer, integer),
  public.fabio_devolutiva_ceifar_travadas(integer)
from public, anon, authenticated;

grant execute on function
  public.fabio_devolutiva_claim(text, integer, integer),
  public.fabio_devolutiva_ceifar_travadas(integer)
to service_role, fabio_agent;
