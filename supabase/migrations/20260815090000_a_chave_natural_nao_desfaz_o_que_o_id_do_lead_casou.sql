-- A chave natural não desfaz o que o ID DO LEAD casou — e o cron passa a
-- abrir as duas portas, na ordem certa.
--
-- CONTEXTO: a 20260815080000 criou `fn_reconciliar_experimental_por_lead`, que
-- casa o vínculo por (`emusys_lead_id`, data). Ela recuperou 87 vínculos numa
-- varredura do passado. Faltava plugá-la no cron — e ao ir plugar, apareceu o
-- motivo pelo qual plugar do jeito óbvio teria sido PIOR que não plugar.
--
-- O QUE FOI MEDIDO ANTES DE ESCREVER ISTO:
--   · dos 87 vínculos novos, 78 a chave natural TAMBÉM alcançaria — eles só
--     estavam fora da janela `[hoje-1, hoje+7]` do reconciliador antigo. Ou
--     seja: a maior parte do ganho da varredura veio da JANELA, não da chave.
--     A chave nova é a única que alcança 9 deles.
--   · 4 leads com linha vigente 'pendente' nos últimos 30 dias; em 3 o id do
--     lead resolveria — e a porta nova não conseguia chegar neles.
--
-- DEFEITO 1 — a chave natural desfazia o casamento do id do lead.
-- `fn_reconciliar_experimental_aulas` confere todo vínculo 'vinculado' pela
-- chave natural (unidade + professor + horário exato). Não batendo, ela conclui
-- "reagendou de verdade" e tira o vínculo de vigência. Só que trocar o
-- professor ou o horário é EXATAMENTE o caso que a porta nova existe pra
-- resolver: rodando as duas no mesmo tick, a porta nova casaria às :12 e a
-- chave natural desfaria às :12, para sempre.
--
-- O conserto não é blindar o vínculo: é **cada chave policiar o que ela
-- criou**. O vínculo `casado_por='emusys_lead_id'` passa a ser conferido pelo
-- próprio id do lead. Soberania não é imunidade — se nem pelo id ele casa mais
-- (remarcação de verdade), sai de vigência igual, e a chave natural reassume.
--
-- DEFEITO 2 — o 'pendente' trancava a porta nova.
-- Quando a aula ainda não sincronizou, a chave natural carimba uma linha
-- 'pendente/sem_par'. Como `uq_lead_exp_aula_vigente` só admite uma linha
-- vigente por lead, e a porta nova só INSERIA, aquele lead ficava fora do
-- alcance dela para sempre — mesmo depois de a aula chegar. Agora ela PROMOVE
-- a linha existente. Promover, e não criar outra: o app navega por
-- `/app/experimental/:vinculo_id` e o registro da experimental aponta pra esse
-- id — trocar a linha quebraria o link.
--
-- DEFEITO 3 — o cron só conhecia uma porta.
-- `fn_reconciliar_experimental_tick` chama as duas, a nova primeiro (num lead
-- sem vínculo, quem chega antes carimba a procedência). A porta nova é a
-- ADIÇÃO: se ela levantar exceção, a porta que já rodava há meses não cai
-- junto — o erro entra no resumo e a chave natural roda mesmo assim.
--
-- Teste: 20260815090000_....test.sql   Mutantes: scripts/mutantes-20260815090000.mjs

-- ── Porta antiga, com três remendos cirúrgicos ──────────────────────────────
-- Corpo idêntico ao da 061 (conferido caractere a caractere contra o que está
-- vivo em produção) exceto: `le.emusys_lead_id` no laço, a variável
-- `v_soberano`, o bloco 3-a e a guarda do bloco 4.

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
  v_soberano               boolean := false;
begin
  for v_lead in
    select le.id, le.status, le.unidade_id, le.data_experimental, le.horario_experimental,
           le.aluno_id, le.emusys_lead_id,
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

      -- 061) O lead voltou a ser agendado, mas o vinculo dele esta 'cancelado'.
      -- Isto TEM que vir ANTES da cadeia de decisao: o ramo de estados finais
      -- (realizado/faltou/cancelado -> null) preserva o cancelado pra sempre, e
      -- o indice de vigencia POR LEAD (uq_lead_exp_aula_vigente) impede que
      -- nasca linha nova. O lead nunca mais e reconciliado, mesmo com a aula
      -- livre esperando por ele.
      --
      -- Medido em 08/08/2026: 3 experimentais da segunda-feira presas assim.
      -- A familia remarcou, o lead voltou pra 'experimental_agendada', a aula
      -- estava no espelho e sem dono, e o professor nao teria ficha.
      --
      -- So 'cancelado' ressuscita. 'realizado' e 'faltou' contam o que
      -- ACONTECEU e continuam terminais. Presenca forte barra tambem: quem
      -- estava na sala decidiu, e sincronizacao por status nao desfaz isso
      -- (mesma regra do ramo 1).
      if v_vinculo.id is not null
         and v_vinculo.estado = 'cancelado'
         and v_lead.status = 'experimental_agendada'
         and not public.fn_presenca_e_forte(v_vinculo.presenca_respondido_por) then
        update lead_experimental_aulas set substituido_em = now() where id = v_vinculo.id;
        -- 061: recarrega em vez de `v_vinculo := null`. Atribuir NULL a um
        -- record em plpgsql o deixa NÃO ATRIBUÍDO, e o próximo `v_vinculo.id`
        -- levanta `record "v_vinculo" is not assigned yet` — que o
        -- `exception when others` do laço engolia como "+1 erro". Como a
        -- única linha vigente acabou de sair, este select não acha nada e
        -- devolve o record com todos os campos nulos, atribuído.
        select * into v_vinculo
          from lead_experimental_aulas
         where lead_experimental_id = v_lead.id and substituido_em is null;
        v_revinculados := v_revinculados + 1;
      end if;

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
        -- 3-a) O vinculo casado pelo ID DO LEAD nao responde a chave natural.
        -- Trocar o professor ou o horario e exatamente o caso que a porta nova
        -- existe pra resolver; deixar a chave natural conferir isso faria a
        -- chave natural desfazer, no mesmo tick, tudo o que a porta nova acabou
        -- de casar. Quem confere um vinculo e a MESMA chave que o criou.
        --
        -- Soberania NAO e imunidade: se o proprio id do lead nao casa mais com
        -- aquela aula (remarcacao de verdade), o vinculo sai de vigencia igual.
        v_soberano := false;
        if v_vinculo.id is not null and v_vinculo.estado = 'vinculado'
           and v_vinculo.casado_por = 'emusys_lead_id' then
          perform 1
            from aulas_emusys ae
            join aula_alunos_emusys r on r.aula_emusys_id = ae.id
           where ae.id = v_vinculo.aula_local_id
             and ae.categoria = 'experimental' and not ae.cancelada
             and ae.unidade_id = v_lead.unidade_id
             and r.emusys_lead_id = v_lead.emusys_lead_id
             and (ae.data_hora_inicio at time zone 'America/Sao_Paulo')::date
                 = v_lead.data_experimental;
          if found then
            v_soberano := true;
          else
            update lead_experimental_aulas set substituido_em = now() where id = v_vinculo.id;
            -- mesmo cuidado da 061: recarrega em vez de `v_vinculo := null`.
            select * into v_vinculo
              from lead_experimental_aulas
             where lead_experimental_id = v_lead.id and substituido_em is null;
          end if;
        end if;

        -- 3) 'vinculado': o par ainda bate pela chave natural de hoje?
        if not v_soberano and v_vinculo.id is not null and v_vinculo.estado = 'vinculado' then
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
            -- 061: recarrega em vez de `v_vinculo := null`. Atribuir NULL a um
            -- record em plpgsql o deixa NÃO ATRIBUÍDO, e o próximo `v_vinculo.id`
            -- levanta `record "v_vinculo" is not assigned yet` — que o
            -- `exception when others` do laço engolia como "+1 erro". Como a
            -- única linha vigente acabou de sair, este select não acha nada e
            -- devolve o record com todos os campos nulos, atribuído.
            select * into v_vinculo
              from lead_experimental_aulas
             where lead_experimental_id = v_lead.id and substituido_em is null;
          end if;
        end if;

        -- 4) Procura pela chave natural (tolerancia ZERO, com unidade)
        if not v_soberano and (v_vinculo.id is null or v_vinculo.estado <> 'vinculado'
           or v_vinculo.aula_local_id is distinct from (
                select ae.id from aulas_emusys ae
                 where ae.categoria = 'experimental' and not ae.cancelada
                   and ae.unidade_id = v_lead.unidade_id
                   and ae.professor_id = v_lead.professor_id
                   and (ae.data_hora_inicio at time zone 'America/Sao_Paulo')
                       = (v_lead.data_experimental + v_lead.horario_experimental)
                 limit 1))
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
              -- 061: este UPDATE pode bater em `uq_lead_exp_aula_ocupada` quando a
              -- aula ja e de OUTRO lead vigente — o caso de dois leads pro mesmo
              -- aluno, que a remarcacao duplicou. Sem handler proprio a violacao
              -- sobe pro `exception when others` do laco, vira "+1 erro" e some.
              -- Foi assim que 2 experimentais ficaram invisiveis rodada apos
              -- rodada. Aula ocupada NAO e erro: e ambiguidade, e ja tem nome.
              begin
                update lead_experimental_aulas
                   set aula_local_id = v_par_id,
                       estado = 'vinculado',
                       casado_por = 'chave_natural',
                       motivo_pendencia = null,
                       vinculado_em = now(),
                       vinculado_por = 'reconciliador'
                 where id = v_vinculo.id;
                v_vinculados := v_vinculados + 1;
              exception when unique_violation then
                if v_vinculo.motivo_pendencia is distinct from 'ambiguo' then
                  update lead_experimental_aulas set motivo_pendencia = 'ambiguo'
                   where id = v_vinculo.id;
                end if;
                v_pendentes_ambiguo := v_pendentes_ambiguo + 1;
              end;
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
'Liga lead_experimentais a aulas_emusys por chave natural (unidade+professor+categoria=experimental+horario em Sao Paulo, tolerancia zero); sincroniza estado do vinculo a partir do status do lead; observa lead_experimentais.aluno_id (coluna propria) pro Contrato 3. NAO desfaz vinculo casado_por=emusys_lead_id: esse e conferido pelo proprio id do lead. Devolve resumo POR RODADA — ver 027b para o porque disso importar.';

-- ── Porta nova: agora também PROMOVE o pendente ─────────────────────────────

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
  v_pendente_id bigint;
  v_processados integer := 0;
  v_vinculados integer := 0;
  v_promovidos integer := 0;
  v_ambiguos integer := 0;
  v_sem_par integer := 0;
  v_ocupada integer := 0;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  for v_lead in
    select le.id, le.unidade_id, le.data_experimental, le.emusys_lead_id
      from public.lead_experimentais le
     where le.emusys_lead_id is not null
       and le.data_experimental between v_hoje - p_dias_atras and v_hoje + p_dias_frente
       -- Sem vínculo vigente, OU com um vigente que ainda está 'pendente'.
       -- O pendente é a linha que a chave natural carimba quando a aula ainda
       -- não sincronizou; como o índice de vigência só admite uma linha por
       -- lead, ignorá-la trancava esta porta pra sempre naquele lead. Estado
       -- final (vinculado/realizado/faltou/cancelado) segue sendo assunto da
       -- máquina de estados da porta antiga, não desta.
       and not exists (
         select 1 from public.lead_experimental_aulas v
          where v.lead_experimental_id = le.id
            and v.substituido_em is null
            and v.estado <> 'pendente'
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
      select v.id into v_pendente_id
        from public.lead_experimental_aulas v
       where v.lead_experimental_id = v_lead.id
         and v.substituido_em is null
         and v.estado = 'pendente';

      begin
        if v_pendente_id is not null then
          -- PROMOVE a mesma linha. Linha nova quebraria o link que o app já
          -- abriu (/app/experimental/:vinculo_id) e o registro que aponta pra ele.
          update public.lead_experimental_aulas
             set aula_local_id = v_par_id,
                 estado = 'vinculado',
                 casado_por = 'emusys_lead_id',
                 motivo_pendencia = null,
                 vinculado_em = now(),
                 vinculado_por = 'reconciliador_lead'
           where id = v_pendente_id;
          v_promovidos := v_promovidos + 1;
        else
          insert into public.lead_experimental_aulas
            (lead_experimental_id, aula_local_id, estado, casado_por, vinculado_em, vinculado_por)
          values
            (v_lead.id, v_par_id, 'vinculado', 'emusys_lead_id', now(), 'reconciliador_lead');
          v_vinculados := v_vinculados + 1;
        end if;
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
    'promovidos', v_promovidos,
    'sem_par', v_sem_par,
    'ambiguos', v_ambiguos,
    'aula_ocupada', v_ocupada
  );
end
$function$;

revoke all on function public.fn_reconciliar_experimental_por_lead(integer, integer, integer) from public, anon, authenticated;
grant execute on function public.fn_reconciliar_experimental_por_lead(integer, integer, integer) to service_role;

comment on function public.fn_reconciliar_experimental_por_lead(integer, integer, integer) is
'Cria (ou promove um pendente) vinculo de aula experimental casando (emusys_lead_id, data) — o id que o proprio Emusys manda e o sync ja grava em aula_alunos_emusys. Nao toca em estado final; a maquina de estados segue em fn_reconciliar_experimental_aulas. Janela parametrizada serve ao cron e a varredura do passado.';

-- ── O tick do cron: as duas portas, nesta ordem ─────────────────────────────

create or replace function public.fn_reconciliar_experimental_tick(
  p_dias   integer default 7,
  p_limite integer default 200
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_por_lead jsonb;
  v_natural  jsonb;
begin
  -- A porta nova PRIMEIRO. Num lead sem vínculo, quem chega antes é quem
  -- carimba a procedência — e o id que o Emusys manda vale mais que unidade +
  -- professor + horário. `p_dias_atras = 1` para cobrir exatamente a mesma
  -- janela da porta antiga (`[hoje-1, hoje+p_dias]`), nem um dia a mais.
  begin
    v_por_lead := public.fn_reconciliar_experimental_por_lead(1, p_dias, p_limite);
  exception when others then
    -- A porta nova é a ADIÇÃO. Se ela quebrar, a porta que já roda há meses
    -- não pode cair junto — o erro aparece no resumo e alguém conserta.
    v_por_lead := jsonb_build_object('ok', false, 'erro', sqlerrm);
  end;

  v_natural := public.fn_reconciliar_experimental_aulas(p_dias, p_limite);

  return jsonb_build_object(
    'ok', true,
    'por_lead', v_por_lead,
    'chave_natural', v_natural
  );
end
$function$;

revoke all on function public.fn_reconciliar_experimental_tick(integer, integer) from public, anon, authenticated;
grant execute on function public.fn_reconciliar_experimental_tick(integer, integer) to service_role;

comment on function public.fn_reconciliar_experimental_tick(integer, integer) is
'Uma rodada da conciliacao da experimental: porta do id do lead primeiro, chave natural depois. A ordem e o contrato — quem chega antes num lead sem vinculo carimba a procedencia. Falha da porta nova nao derruba a antiga. E o que o cron reconciliar-experimental-aulas chama.';

-- ── O agendamento passa a abrir as duas portas ──────────────────────────────
-- O comando do cron mora só no banco; deixá-lo aqui é o que faz o repo contar
-- a verdade sobre o que roda de 15 em 15 minutos. Guardado por `to_regclass`
-- porque o ensaio em Docker não tem pg_cron.
--
-- O acesso a `cron.job` vai por EXECUTE, e não direto: plpgsql resolve os nomes
-- de tabela ao PLANEJAR o comando, então um `if to_regclass(...) is not null and
-- exists (select ... from cron.job)` estoura no ambiente sem pg_cron mesmo com a
-- guarda — a guarda e o acesso moram na MESMA expressão. Descoberto no ensaio.
-- Sem linha correspondente, o EXECUTE não faz nada (e não estoura como
-- `alter_job(null, ...)` faria).
do $cron$
begin
  if to_regclass('cron.job') is not null then
    execute $sql$
      select cron.alter_job(jobid, command => 'select public.fn_reconciliar_experimental_tick(7, 200)')
        from cron.job
       where jobname = 'reconciliar-experimental-aulas'
    $sql$;
  end if;
end
$cron$;
