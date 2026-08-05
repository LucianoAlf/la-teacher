-- 027d — o lote de 5 pegava sempre os MESMOS 5, e ninguém mais era extraído
--
-- ONZE RODADAS COM `succeeded` E ZERO TRABALHO FEITO.
--
-- O log de rodada da edge function é quem contou, e ele contou nas onze:
--     processados: 5 | gravados: 0 | pulados: 5 | itens: sem_mensagem_nova
--
-- A causa é a ordem em que as duas decisões acontecem:
--
--   1. o `limit p_limite` desta função escolhe o lote (por data da experimental)
--   2. só DEPOIS, já na edge function, é que dá pra saber se a conversa ganhou
--      mensagem nova — porque isso exige chamar o Chatwoot
--
-- Então o lote é preenchido pelos 5 primeiros por data, todos já extraídos, e a
-- edge function pula os 5. Os outros 11 da janela nunca chegam a entrar: sem
-- contexto no dia da aula, sem erro em lugar nenhum, sem nada quebrado. É a
-- mesma classe de defeito de "verificação sobre conjunto vazio sempre passa" —
-- o verde vem de não ter feito nada.
--
-- O CONSERTO É A ORDENAÇÃO, e ele tem dois andares:
--
--   `(contexto_ia_em is not null)` — quem NUNCA foi extraído passa na frente.
--   Um aluno com aula amanhã que já tem contexto está atendido; o professor já
--   tem o que precisa dele. Quem não tem nada é que corre risco de chegar no
--   dia da aula sem contexto nenhum.
--
--   `contexto_ia_em asc` — entre os já extraídos, o mais antigo primeiro. Isto
--   é o que faz a fila GIRAR. Ordenar os já-extraídos por data de novo traria o
--   defeito de volta pra dentro do grupo: os 5 primeiros venceriam toda rodada,
--   seriam pulados toda rodada, e ninguém seria relido nunca. A rotação é o que
--   garante que uma conversa que ganhou mensagem nova acabe sendo revisitada.
--
-- A data da experimental continua desempatando dentro de cada grupo, e o `id`
-- continua no fim para a ordem ser total.

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
   order by (le.contexto_ia_em is not null),  -- nunca extraído passa na frente
            le.contexto_ia_em asc,            -- entre os extraídos, o mais velho (gira a fila)
            le.data_experimental, le.horario_experimental, le.id
   limit p_limite;
$function$;

revoke all on function public.fn_experimentais_a_extrair(integer, integer) from public, anon, authenticated;
grant execute on function public.fn_experimentais_a_extrair(integer, integer) to service_role;

comment on function public.fn_experimentais_a_extrair(integer, integer) is
'Experimentais AGENDADAS dos proximos p_dias, no fuso de Sao Paulo, com telefone. Ordena quem nunca foi extraido na frente e gira a fila pelos mais antigos, para o lote nao pegar sempre os mesmos. Devolve extraido_ate_id para a edge function decidir se rele a conversa.';
