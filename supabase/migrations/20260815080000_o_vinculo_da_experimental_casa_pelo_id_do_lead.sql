-- O vínculo da experimental casa pelo ID DO LEAD, não por chave natural.
--
-- Auditoria de 15/08/2026 (pedida pelo Alf: *"eles existem, você está buscando
-- num lugar errado"*). Eu media cobertura contra `lead_experimental_aulas`
-- (102 linhas), que é a SAÍDA da conciliação. A fonte é `lead_experimentais`,
-- com 928. Medi o resultado e chamei de universo.
--
-- COMO ESTAVA: `fn_reconciliar_experimental_aulas` casa por CHAVE NATURAL —
-- unidade + data + horário + professor (`casado_por='chave_natural'` em 82 dos
-- 104 vínculos). Trocou o professor ou mexeu no horário, não casa mais.
--
-- O ELO CERTO JÁ ESTAVA GUARDADO. O `GET /v1/aulas` do Emusys devolve, na aula
-- experimental, `alunos[].id_lead` — e o sync do LA Report **já grava** isso em
-- `aula_alunos_emusys.emusys_lead_id`. Do outro lado,
-- `lead_experimentais.emusys_lead_id`. A junção é entre DUAS TABELAS NOSSAS:
-- nada aqui chama o Emusys. Quem faz GET é o sync, e ele já rodou.
--
-- MEDIDO (30 dias, 153 experimentais):
--   vínculo hoje (chave natural) ....  59 = 39%
--   casa por emusys_lead_id ......... 121 = 79%
--
-- ⚠️ A CHAVE É (lead, DATA) — NUNCA o lead sozinho. Medido: 121 leads têm mais
-- de uma experimental e um deles tem SEIS (remarcação). Casar só por lead
-- penduraria o registro na tentativa errada da mesma criança. O lead diz QUEM,
-- a data diz QUAL TENTATIVA.
--
-- POR QUE UMA FUNÇÃO NOVA, E NÃO UM REMENDO NA ANTIGA:
-- `fn_reconciliar_experimental_aulas` tem 15 KB de casos duramente conquistados
-- (o ramo 061 da remarcação, o "manual é sagrado", o tratamento de ambiguidade,
-- a sincronização de estado). Esta porta só CRIA vínculo que não existe; toda a
-- máquina de estados continua lá, intocada. A antiga vira fallback natural para
-- o legado — junho tem 109 experimentais sem `emusys_lead_id` (o campo nasceu
-- em 21/06/2026) e só a chave natural alcança aquilo.
--
-- O QUE ESTA FUNÇÃO NÃO FAZ, DE PROPÓSITO:
--   · não toca em vínculo que já existe vigente (nem pra "melhorar" o casamento)
--   · não ressuscita cancelado/realizado/faltou — isso é da máquina de estados
--   · não mexe em `casado_por='manual'`
--   · não inventa aula: exige a linha de roster com o lead
--
-- A janela é parâmetro para servir aos DOIS usos: o cron (dias curtos) e a
-- varredura de recuperação do passado (dias longos), sem duplicar regra.

-- A procedência do casamento é vocabulário FECHADO por CHECK. O valor novo
-- precisa entrar antes da função existir, senão o insert estoura em runtime.
-- Descoberto num ensaio a seco contra produção: o teste em Docker passava
-- porque o bootstrap não tinha esta constraint — schema de teste divergindo do
-- real é verde que não vale. A constraint foi para o bootstrap junto.
alter table public.lead_experimental_aulas
  drop constraint if exists lead_experimental_aulas_casado_por_check;

alter table public.lead_experimental_aulas
  add constraint lead_experimental_aulas_casado_por_check
  check (casado_por is null or casado_por = any (array[
    'chave_natural'::text,
    'manual'::text,
    'emusys_lead_id'::text
  ]));

create or replace function public.fn_reconciliar_experimental_por_lead(
  p_dias_atras integer default 2,
  p_dias_frente integer default 7,
  p_limite integer default 200
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_lead record;
  v_par_id integer;
  v_qtd_par integer;
  v_processados integer := 0;
  v_vinculados integer := 0;
  v_ambiguos integer := 0;
  v_sem_par integer := 0;
  v_ja_vinculado integer := 0;
  v_ocupada integer := 0;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  for v_lead in
    select le.id, le.unidade_id, le.data_experimental, le.emusys_lead_id
      from public.lead_experimentais le
     where le.emusys_lead_id is not null
       and le.data_experimental between v_hoje - p_dias_atras and v_hoje + p_dias_frente
       -- Só quem NÃO tem vínculo vigente. Vínculo existente é assunto da
       -- máquina de estados, não desta porta.
       and not exists (
         select 1 from public.lead_experimental_aulas v
          where v.lead_experimental_id = le.id
            and v.substituido_em is null
       )
     order by le.data_experimental desc, le.id
     limit p_limite
  loop
    v_processados := v_processados + 1;

    -- (lead, data) — a data desempata a remarcação. `at time zone` porque
    -- data_hora_inicio é timestamptz e data_experimental é date em BRT.
    select count(*), min(ae.id) into v_qtd_par, v_par_id
      from public.aulas_emusys ae
      join public.aula_alunos_emusys r on r.aula_emusys_id = ae.id
     where ae.categoria = 'experimental'
       and not coalesce(ae.cancelada, false)
       and ae.unidade_id = v_lead.unidade_id
       and r.emusys_lead_id = v_lead.emusys_lead_id
       and (ae.data_hora_inicio at time zone 'America/Sao_Paulo')::date
           = v_lead.data_experimental;

    if v_qtd_par = 0 then
      v_sem_par := v_sem_par + 1;
    elsif v_qtd_par > 1 then
      -- Mesmo lead, mesma data, duas aulas: não escolhe no chute.
      v_ambiguos := v_ambiguos + 1;
    else
      begin
        insert into public.lead_experimental_aulas
          (lead_experimental_id, aula_local_id, estado, casado_por, vinculado_em, vinculado_por)
        values
          (v_lead.id, v_par_id, 'vinculado', 'emusys_lead_id', now(), 'reconciliador_lead');
        v_vinculados := v_vinculados + 1;
      exception
        when unique_violation then
          -- `uq_lead_exp_aula_ocupada`: a aula já é de outro lead vigente.
          -- Ambiguidade real (dois leads pro mesmo aluno), não erro — e o
          -- reconciliador antigo já sabe carimbar isso.
          v_ocupada := v_ocupada + 1;
      end;
    end if;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'processados', v_processados,
    'vinculados', v_vinculados,
    'sem_par', v_sem_par,
    'ambiguos', v_ambiguos,
    'aula_ocupada', v_ocupada,
    'ja_vinculado', v_ja_vinculado
  );
end
$function$;

comment on function public.fn_reconciliar_experimental_por_lead(integer, integer, integer) is
  'Cria vínculo de aula experimental casando (emusys_lead_id, data) — o id que o próprio Emusys manda e o sync já grava em aula_alunos_emusys. Só cria o que não existe; máquina de estados segue em fn_reconciliar_experimental_aulas. Janela parametrizada serve ao cron e à varredura do passado.';
