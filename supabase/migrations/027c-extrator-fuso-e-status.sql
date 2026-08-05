-- 027c — a janela do extrator perdia o fim do dia, e pegava aula cancelada
--
-- DOIS DEFEITOS ACHADOS RODANDO EM PRODUÇÃO, não lendo código.
--
-- 1. `current_date` no Postgres é UTC. Às 21:11 BRT o banco já está em 00:11 do
--    dia seguinte, então `data_experimental >= current_date` DESCARTA as
--    experimentais de hoje três horas antes de o dia acabar. Foi assim que os
--    irmãos Andrade (04/08) sumiram da seleção enquanto ainda era 04/08 no Rio.
--    Toda a rede depende do fuso de São Paulo — a janela também tem que.
--
-- 2. A seleção não olhava `status`. A Beatriz Romero (id 1312) está `cancelada`
--    e foi extraída assim mesmo: gasta chamada de Gemini e, pior, entrega ao
--    professor contexto de uma aula que não vai acontecer.
--
--    O filtro é lista de PERMISSÃO, não de bloqueio: só passa o que está
--    agendado ou reagendado. Status novo que o Emusys invente entra de fora,
--    e ficar de fora é a falha segura. `experimental_realizada` também fica
--    fora — depois da aula, quem manda é o registro do professor.

create or replace function public.fn_experimentais_a_extrair(
  p_dias   integer default 7,
  p_limite integer default 50
)
returns table (
  lead_experimental_id integer,
  nome_aluno           text,
  telefone             text,
  data_experimental    date,
  curso                text,
  observacoes          text,
  extraido_ate_id      bigint
)
language sql
stable
security definer
set search_path to 'public'
as $function$
  select le.id,
         le.nome_aluno::text,
         coalesce(nullif(btrim(l.whatsapp), ''), nullif(btrim(l.telefone), ''))::text,
         le.data_experimental,
         c.nome::text,
         nullif(btrim(le.observacoes), '')::text,
         public.fn_texto_para_bigint(le.contexto_ia -> 'procedencia' ->> 'ultima_mensagem_id')
    from lead_experimentais le
    left join leads  l on l.id = le.lead_id
    left join cursos c on c.id = le.curso_interesse_id
   where le.data_experimental
           between (now() at time zone 'America/Sao_Paulo')::date
               and (now() at time zone 'America/Sao_Paulo')::date + p_dias
     and le.status in ('experimental_agendada', 'experimental_reagendada')
     and coalesce(nullif(btrim(l.whatsapp), ''), nullif(btrim(l.telefone), '')) is not null
   -- `le.id` no fim: sem desempate, duas experimentais no mesmo dia e horário
   -- trocam de lugar entre rodadas e uma pode nunca entrar no lote.
   order by le.data_experimental, le.horario_experimental, le.id
   limit p_limite;
$function$;

revoke all on function public.fn_experimentais_a_extrair(integer, integer) from public, anon, authenticated;
grant execute on function public.fn_experimentais_a_extrair(integer, integer) to service_role;

comment on function public.fn_experimentais_a_extrair(integer, integer) is
'Experimentais AGENDADAS dos proximos p_dias, no fuso de Sao Paulo, com telefone. Devolve extraido_ate_id para a edge function decidir se rele a conversa.';
