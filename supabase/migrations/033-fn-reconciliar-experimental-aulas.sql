-- SUPERADA POR: 061-a-experimental-remarcada-ressuscita.sql (via 034)
--
-- Esta versao da funcao nao roda mais em producao. O teste dela continua util
-- — ele instala esta versao dentro do rollback e a exercita —, mas contra os
-- dados de hoje ele ACUSA, e com razao: aqui ainda existe o `v_vinculo := null`
-- que deixa o record nao atribuido, e o UPDATE que promove um 'pendente' nao
-- tem handler pra aula ja ocupada. Os dois viraram "+1 erro" mudo por rodadas
-- seguidas ate a 061. Ver vermelho aqui e o teste funcionando.
-- 033 — reconciliador do vinculo lead_experimentais <-> aulas_emusys
--
-- Roda por cron (a cada N minutos, sem pressa: e leitura/escrita local, sem
-- API externa). Por lead na janela, em ordem:
--
--   1. status='cancelada'/'experimental_realizada'/'experimental_faltou'/
--      'convertido' -> sincroniza o ESTADO do vinculo vigente (Contrato 2)
--   2. estado do vinculo em ('manual','realizado','faltou','cancelado') ->
--      NAO TOCA (decisao humana e fato consumado sao finais)
--   3. estado='vinculado' -> confirma se o par ainda bate; se nao, substitui
--   4. estado='pendente' ou sem vinculo -> procura pela chave natural
--   5. observa lead_experimentais.aluno_id (Contrato 3)
--
-- Devolve um resumo por RODADA (nao por lead) — o mesmo defeito que fez o
-- extrator de contexto rodar 11 vezes sem fazer nada so foi visto porque
-- havia log por rodada. Sem isso, "rodou e nao fez nada" fica invisivel.

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
      if v_vinculo.id is not null and v_vinculo.estado = 'manual' then
        null;  -- de proposito: nada a fazer, nem cancelado_em

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
