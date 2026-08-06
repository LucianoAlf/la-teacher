-- 034 — presenca da experimental mora no vinculo, no padrao do aluno
--
-- A presenca da experimental JA TEM CASA: o vinculo da 032 e uma linha por par
-- lead x aula, exatamente o papel que aluno_presenca faz para o aluno. Nao se
-- cria tabela de presenca nova.
--
-- Medido em 05/08/2026, e o motivo desta migration existir: das 813
-- experimentais nao canceladas, 599 nao tem presenca NENHUMA (74%), e em toda
-- a base existe UMA unica presenca de fonte forte. O resto e o Emusys
-- devolvendo 'presente' sem ninguem ter marcado — o mesmo fantasma que a
-- Fase 2 (012) ja matou na aula regular.
--
-- Vocabulario de fonte copiado VERBATIM do aluno_presenca_respondido_por_check.
-- A primeira versao da spec escreveu 'professor_app', que NAO EXISTE:
-- fn_presenca_e_forte devolve false pra ele e a presenca nasceria fraca em
-- silencio. O CHECK abaixo rejeita isso na ESCRITA (achado do Alfredo).

alter table public.lead_experimental_aulas
  add column presenca_status text
    check (presenca_status is null or presenca_status in ('presente','falta')),
  add column presenca_respondido_por text
    check (presenca_respondido_por is null or presenca_respondido_por in
      ('professor_whatsapp','professor_la_teacher','manual','sistema','emusys','fabio_audio')),
  add column presenca_respondido_em timestamptz,
  add column presenca_bruta_emusys text;

comment on column public.lead_experimental_aulas.presenca_respondido_por is
'Fonte da presenca, mesmo vocabulario de aluno_presenca.respondido_por. Forte = passa em fn_presenca_e_forte. NUNCA usar professor_app (nao existe).';

-- Escrita de presenca com precedencia decidida UMA VEZ, aqui (padrao da 009):
-- fonte forte sobrescreve fraca; fraca NAO sobrescreve forte; o bruto do
-- Emusys e sempre preservado, inclusive quando o professor ganha.
create or replace function public.fn_registrar_presenca_experimental(
  p_vinculo_id     bigint,
  p_status         text,
  p_respondido_por text,
  p_bruta_emusys   text default null
)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_atual_por text;
begin
  select presenca_respondido_por into v_atual_por
    from lead_experimental_aulas where id = p_vinculo_id
     for update;

  if not found then
    raise exception 'vinculo_inexistente: %', p_vinculo_id;
  end if;

  -- O bruto do Emusys e memoria, nao decisao: grava sempre que vier.
  if p_bruta_emusys is not null then
    update lead_experimental_aulas
       set presenca_bruta_emusys = p_bruta_emusys
     where id = p_vinculo_id;
  end if;

  -- Precedencia: so nao grava quando o que ja esta la e FORTE e o que chega
  -- e FRACO. Forte sobre forte grava (correcao humana posterior e legitima).
  if v_atual_por is not null
     and public.fn_presenca_e_forte(v_atual_por)
     and not public.fn_presenca_e_forte(p_respondido_por) then
    return false;
  end if;

  update lead_experimental_aulas
     set presenca_status         = p_status,
         presenca_respondido_por = p_respondido_por,
         presenca_respondido_em  = now()
   where id = p_vinculo_id;

  -- Presenca FORTE tambem move o ciclo de vida do vinculo. Fonte fraca nao
  -- promove estado — senao o fantasma do Emusys voltaria pela porta dos fundos.
  if public.fn_presenca_e_forte(p_respondido_por) then
    update lead_experimental_aulas
       set estado = case when p_status = 'presente' then 'realizado' else 'faltou' end
     where id = p_vinculo_id
       and estado not in ('cancelado');
  end if;

  return true;
end
$function$;

revoke all on function public.fn_registrar_presenca_experimental(bigint,text,text,text) from public, anon, authenticated;
grant execute on function public.fn_registrar_presenca_experimental(bigint,text,text,text) to service_role;

-- ---------------------------------------------------------------------------
-- Reconciliador da 033, REPUBLICADO com uma unica mudanca: a guarda do
-- primeiro `if` passa a cobrir tambem presenca de fonte forte. O corpo abaixo
-- foi extraido do arquivo real da 033 por script, nao transcrito a mao.
-- ---------------------------------------------------------------------------

create or replace function public.fn_reconciliar_experimental_aulas(
  p_dias   integer default 7,
  p_limite integer default 200
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_lead                 record;
  v_vinculo               record;
  v_par_id                integer;
  v_qtd_par               integer;
  v_processados            integer := 0;
  v_vinculados             integer := 0;
  v_pendentes_sem_par      integer := 0;
  v_pendentes_ambiguo      integer := 0;
  v_revinculados           integer := 0;
  v_estado_sincronizado    integer := 0;
  v_matriculas_registradas integer := 0;
  v_erros                  integer := 0;
begin
  for v_lead in
    select le.id, le.status, le.unidade_id, le.data_experimental, le.horario_experimental,
           le.aluno_id,
           coalesce(le.professor_experimental_id, l.professor_experimental_id) as professor_id
      from lead_experimentais le
      left join leads l on l.id = le.lead_id
     where le.data_experimental between
             (now() at time zone 'America/Sao_Paulo')::date - 1
             and (now() at time zone 'America/Sao_Paulo')::date + p_dias
     order by le.data_experimental, le.id
     limit p_limite
  loop
    v_processados := v_processados + 1;
    begin
      select * into v_vinculo
        from lead_experimental_aulas
       where lead_experimental_id = v_lead.id and substituido_em is null;

      -- 1) 'manual' e sagrado: NENHUMA sincronizacao por status pode tocar
      -- nele, nem pra so anotar cancelado_em. Isto tem que ser o PRIMEIRO
      -- if, nao um dos ramos do meio — a primeira versao deste arquivo
      -- checava "estados finais: nao toca" DEPOIS dos 4 ramos de
      -- sincronizacao, e um vinculo 'manual' cujo lead virasse 'cancelada'
      -- batia no primeiro ramo (que so excluia 'realizado'/'faltou', nao
      -- 'manual') e era rebaixado pra 'cancelado' — atropelando a decisao
      -- humana que o Contrato 2 promete nunca sobrescrever. Pego pelo
      -- mutante M3 do plano (a covardia do teste, nao da funcao, foi nao
      -- pegar isso de primeira — o indice de vigencia da 032 escondia o
      -- efeito visivel, mas o `erros` da rodada acusava).
      -- 034: 'manual' e presenca FORTE sao ambos decisao de quem estava
      -- presente na sala. Precisa continuar sendo o PRIMEIRO if — a 033 ja
      -- teve bug exatamente assim (f42203e), quando o ramo de sync de
      -- 'experimental_realizada'/'convertido' promovia 'faltou' pra
      -- 'realizado' porque so excluia 'realizado' do alvo.
      if v_vinculo.id is not null
         and (v_vinculo.estado = 'manual'
              or public.fn_presenca_e_forte(v_vinculo.presenca_respondido_por)) then
        null;  -- de proposito: status comercial nao mexe em nada disso

      -- 2) Sincroniza o ESTADO a partir do status real do lead (Contrato 2)
      elsif v_lead.status = 'cancelada' and v_vinculo.id is not null
         and v_vinculo.estado not in ('realizado', 'faltou') then
        update lead_experimental_aulas
           set estado = 'cancelado', cancelado_em = coalesce(cancelado_em, now())
         where id = v_vinculo.id;
        v_estado_sincronizado := v_estado_sincronizado + 1;

      elsif v_lead.status = 'cancelada' and v_vinculo.id is not null
            and v_vinculo.estado in ('realizado', 'faltou') then
        update lead_experimental_aulas
           set cancelado_em = coalesce(cancelado_em, now())   -- estado NAO muda
         where id = v_vinculo.id;
        v_estado_sincronizado := v_estado_sincronizado + 1;

      elsif v_lead.status in ('experimental_realizada', 'convertido') and v_vinculo.id is not null
            and v_vinculo.estado not in ('realizado', 'faltou') then
        -- 'faltou' fica de fora do alvo: 'convertido' e um status
        -- COMERCIAL (a familia matriculou) e nao apaga o que aconteceu do
        -- lado PEDAGOGICO (a familia faltou na experimental). Promover
        -- 'faltou' pra 'realizado' aqui mentiria que a aula aconteceu —
        -- achado par ao bug do aluno_origem (revisao do Alfredo, d2cb186):
        -- sem esta exclusao, o Contrato 3 nunca via t.estado='faltou'.
        update lead_experimental_aulas set estado = 'realizado' where id = v_vinculo.id;
        v_estado_sincronizado := v_estado_sincronizado + 1;

      elsif v_lead.status = 'experimental_faltou' and v_vinculo.id is not null
            and v_vinculo.estado <> 'faltou' then
        update lead_experimental_aulas set estado = 'faltou' where id = v_vinculo.id;
        v_estado_sincronizado := v_estado_sincronizado + 1;

      -- 3) Estados finais restantes: nao toca
      elsif v_vinculo.id is not null and v_vinculo.estado in ('realizado', 'faltou', 'cancelado') then
        null;  -- de proposito: nada a fazer

      else
        -- 3) 'vinculado': o par ainda bate pela chave natural de hoje?
        if v_vinculo.id is not null and v_vinculo.estado = 'vinculado' then
          perform 1 from aulas_emusys ae
           where ae.id = v_vinculo.aula_local_id
             and ae.categoria = 'experimental' and not ae.cancelada
             and ae.unidade_id = v_lead.unidade_id
             and ae.professor_id = v_lead.professor_id
             and (ae.data_hora_inicio at time zone 'America/Sao_Paulo')
                 = (v_lead.data_experimental + v_lead.horario_experimental);
          if found then
            -- nada mudou, mas ainda cai no bloco 4 abaixo (o vinculo
            -- continua sendo v_vinculo — a query de 4 vai achar o mesmo
            -- par e nao gerar linha nova por causa do guarda de idempotencia).
            null;
          else
            -- divergiu (reagendou de verdade): sai de vigencia
            update lead_experimental_aulas set substituido_em = now() where id = v_vinculo.id;
            v_vinculo := null;
          end if;
        end if;

        -- 4) Procura pela chave natural (tolerancia ZERO, com unidade)
        if v_vinculo.id is null or v_vinculo.estado <> 'vinculado'
           or v_vinculo.aula_local_id is distinct from (
                select ae.id from aulas_emusys ae
                 where ae.categoria = 'experimental' and not ae.cancelada
                   and ae.unidade_id = v_lead.unidade_id
                   and ae.professor_id = v_lead.professor_id
                   and (ae.data_hora_inicio at time zone 'America/Sao_Paulo')
                       = (v_lead.data_experimental + v_lead.horario_experimental)
                 limit 1)
        then
          select count(*) into v_qtd_par
            from aulas_emusys ae
           where ae.categoria = 'experimental' and not ae.cancelada
             and ae.unidade_id = v_lead.unidade_id
             and ae.professor_id = v_lead.professor_id
             and (ae.data_hora_inicio at time zone 'America/Sao_Paulo')
                 = (v_lead.data_experimental + v_lead.horario_experimental);

          -- Se ja existe uma linha vigente e ela esta 'pendente', essa
          -- linha JA E o lugar certo pra guardar o resultado — o unico
          -- caminho e UPDATE nela. Tentar INSERT aqui bate direto no
          -- indice de vigencia (a linha pendente conta como vigente) e o
          -- unique_violation resultante seria mal-interpretado como "aula
          -- ocupada por outro lead": achado do Alfredo (revisao do commit
          -- d2cb186) — pendente/sem_par que casa numa rodada seguinte
          -- gerava erro em vez de promocao.
          if v_qtd_par = 1 then
            select ae.id into v_par_id
              from aulas_emusys ae
             where ae.categoria = 'experimental' and not ae.cancelada
               and ae.unidade_id = v_lead.unidade_id
               and ae.professor_id = v_lead.professor_id
               and (ae.data_hora_inicio at time zone 'America/Sao_Paulo')
                   = (v_lead.data_experimental + v_lead.horario_experimental);

            if v_vinculo.id is not null and v_vinculo.estado = 'pendente' then
              update lead_experimental_aulas
                 set aula_local_id = v_par_id,
                     estado = 'vinculado',
                     casado_por = 'chave_natural',
                     motivo_pendencia = null,
                     vinculado_em = now(),
                     vinculado_por = 'reconciliador'
               where id = v_vinculo.id;
              v_vinculados := v_vinculados + 1;
            else
              begin
                insert into lead_experimental_aulas
                  (lead_experimental_id, aula_local_id, estado, casado_por, vinculado_em, vinculado_por)
                values
                  (v_lead.id, v_par_id, 'vinculado', 'chave_natural', now(), 'reconciliador');
                if v_vinculo.id is not null then
                  v_revinculados := v_revinculados + 1;
                else
                  v_vinculados := v_vinculados + 1;
                end if;
              exception when unique_violation then
                -- so chega aqui quando v_vinculo NAO era 'pendente' (ramo
                -- acima ja tratou esse caso) — ou seja, a aula realmente
                -- esta ocupada por OUTRO lead vigente.
                insert into lead_experimental_aulas (lead_experimental_id, estado, motivo_pendencia)
                values (v_lead.id, 'pendente', 'ambiguo');
                v_pendentes_ambiguo := v_pendentes_ambiguo + 1;
              end;
            end if;

          elsif v_qtd_par = 0 then
            if v_vinculo.id is not null and v_vinculo.estado = 'pendente' then
              if v_vinculo.motivo_pendencia is distinct from 'sem_par' then
                update lead_experimental_aulas set motivo_pendencia = 'sem_par' where id = v_vinculo.id;
              end if;
            else
              insert into lead_experimental_aulas (lead_experimental_id, estado, motivo_pendencia)
              values (v_lead.id, 'pendente', 'sem_par');
            end if;
            v_pendentes_sem_par := v_pendentes_sem_par + 1;

          else -- mais de uma aula bate (nao visto em producao, mas nao e chute)
            if v_vinculo.id is not null and v_vinculo.estado = 'pendente' then
              if v_vinculo.motivo_pendencia is distinct from 'ambiguo' then
                update lead_experimental_aulas set motivo_pendencia = 'ambiguo' where id = v_vinculo.id;
              end if;
            else
              insert into lead_experimental_aulas (lead_experimental_id, estado, motivo_pendencia)
              values (v_lead.id, 'pendente', 'ambiguo');
            end if;
            v_pendentes_ambiguo := v_pendentes_ambiguo + 1;
          end if;
        end if;
      end if;

    exception when others then
      v_erros := v_erros + 1;
      raise warning '[reconciliar_experimental] lead_experimental_id=% erro=%', v_lead.id, sqlerrm;
    end;

    -- 5) Contrato 3 — matricula com recibo, observando lead_experimentais.aluno_id
    -- (a coluna PROPRIA de lead_experimentais, nao leads.aluno_id)
    --
    -- Decisao explicita (revisao do Alfredo, commit d2cb186): 'faltou' e
    -- terminal do lado PEDAGOGICO (a aula nao aconteceu pro aluno), mas o
    -- COMERCIAL pode converter mesmo assim (matriculou apesar de ter
    -- faltado na experimental). O recibo tem que ser gravado — bloquear
    -- perderia rastro de uma matricula real — mas aluno_origem avisa quem
    -- ler depois (Task 4, molde do registro) que esta linha NAO e o
    -- primeiro capitulo pedagogico do aluno.
    if v_lead.aluno_id is not null then
      update lead_experimental_aulas t
         set aluno_id = v_lead.aluno_id,
             aluno_vinculado_em = now(),
             aluno_vinculado_por = 'reconciliador:emusys_sync',
             aluno_origem = case when t.estado = 'faltou'
                                  then 'conversao_sem_aula'
                                  else 'lead_experimentais.aluno_id' end
       where t.lead_experimental_id = v_lead.id
         and t.substituido_em is null
         and t.aluno_id is null;
      if found then
        v_matriculas_registradas := v_matriculas_registradas + 1;
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'processados', v_processados,
    'vinculados', v_vinculados,
    'revinculados', v_revinculados,
    'pendentes_sem_par', v_pendentes_sem_par,
    'pendentes_ambiguo', v_pendentes_ambiguo,
    'estado_sincronizado', v_estado_sincronizado,
    'matriculas_registradas', v_matriculas_registradas,
    'erros', v_erros
  );
end
$function$;

revoke all on function public.fn_reconciliar_experimental_aulas(integer, integer) from public, anon, authenticated;
grant execute on function public.fn_reconciliar_experimental_aulas(integer, integer) to service_role;

comment on function public.fn_reconciliar_experimental_aulas(integer, integer) is
'Liga lead_experimentais a aulas_emusys por chave natural (unidade+professor+categoria=experimental+horario em Sao Paulo, tolerancia zero); sincroniza estado do vinculo a partir do status do lead; observa lead_experimentais.aluno_id (coluna propria) pro Contrato 3. Devolve resumo POR RODADA — ver 027b para o porque disso importar.';
