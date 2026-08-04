-- 027 — a experimental passa a carregar o contexto extraído da conversa
--
-- POR QUE ISSO EXISTE
-- A conversa da Mila com a família tem 35 a 56 mensagens e cobre nome do
-- responsável, idade, nível, gosto musical e motivação. O que sobrevive disso
-- é o campo `observacoes` do Emusys: no melhor caso oito palavras digitadas com
-- pressa. Nos irmãos Andrade o campo está vazio, e a conversa dizia que os dois
-- já tocavam piano em Portugal e pediram para voltar.
--
-- `contexto_ia` é VIZINHO de `observacoes`, não substituto. O Emusys é dono do
-- `observacoes` e reescreve a cada webhook; se o extrator gravasse lá, a
-- extração sumiria no próximo evento e ninguém saberia quem escreveu o quê.

alter table public.lead_experimentais
  add column if not exists contexto_ia    jsonb,
  add column if not exists contexto_ia_em timestamptz;

comment on column public.lead_experimentais.contexto_ia is
'Contexto pedagogico extraido da conversa da Mila + observacoes, por IA. Escrito SO pelo extrator. Nunca confundir com observacoes, que e do Emusys.';

-- ─────────────────────────────────────────────────────────────────────────
-- Quem precisa de extração agora
--
-- Releitura é por ID de mensagem, não por data: a conversa continua depois do
-- agendamento (os Andrade cancelaram na manhã do dia da aula) e mensagens do
-- mesmo dia fariam o extrator se considerar atualizado.
--
-- `p_ultima_mensagem_id` chega da edge function, que é quem fala com o
-- Chatwoot. O banco não sai para a rede.

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
         nullif(le.contexto_ia -> 'procedencia' ->> 'ultima_mensagem_id', '')::bigint
    from lead_experimentais le
    left join leads  l on l.id = le.lead_id
    left join cursos c on c.id = le.curso_interesse_id
   where le.data_experimental between current_date and current_date + p_dias
     and coalesce(nullif(btrim(l.whatsapp), ''), nullif(btrim(l.telefone), '')) is not null
   order by le.data_experimental, le.horario_experimental
   limit p_limite;
$function$;

revoke all on function public.fn_experimentais_a_extrair(integer, integer) from public, anon, authenticated;
grant execute on function public.fn_experimentais_a_extrair(integer, integer) to service_role;

comment on function public.fn_experimentais_a_extrair(integer, integer) is
'Experimentais dos proximos p_dias com telefone. Devolve extraido_ate_id para a edge function decidir se relê a conversa.';

-- ─────────────────────────────────────────────────────────────────────────
-- Gravação com guarda
--
-- Falha do Gemini, JSON quebrado ou conversa sem conteúdo NÃO podem apagar uma
-- extração boa. A regra é: só grava se vier conteúdo E se a leitura for mais
-- nova que a que já está lá.

create or replace function public.fabio_gravar_contexto_experimental(
  p_lead_experimental_id integer,
  p_contexto             jsonb
)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_novo_id  bigint;
  v_atual_id bigint;
  v_tem_algo boolean;
begin
  if p_contexto is null or jsonb_typeof(p_contexto) <> 'object' then
    return false;
  end if;

  -- conteúdo de verdade: pelo menos um dos blocos úteis preenchido.
  -- `procedencia` sozinha não conta -- senão uma extração que não achou nada
  -- passaria por cima de uma que achou.
  -- coalesce no array_length: sem essa rede, jsonb_typeof(chave ausente) e
  -- NULL, "NULL = 'array'" e NULL, e NULL entra no OR abaixo -- v_tem_algo
  -- vira NULL (nao false) e o "if not v_tem_algo" seguinte NAO dispara,
  -- porque PL/pgSQL so entra no IF quando a condicao e TRUE. Isso deixava a
  -- extracao vazia passar (fail open), o mesmo defeito do mutante 1.
  v_tem_algo := (p_contexto -> 'recepcao'          is not null and p_contexto -> 'recepcao' <> 'null'::jsonb)
             or (p_contexto -> 'quem_e_esse_aluno' is not null and p_contexto -> 'quem_e_esse_aluno' <> 'null'::jsonb)
             or (jsonb_typeof(p_contexto -> 'ganchos_de_conexao') = 'array'
                 and coalesce(jsonb_array_length(p_contexto -> 'ganchos_de_conexao'), 0) > 0)
             or (jsonb_typeof(p_contexto -> 'alertas') = 'array'
                 and coalesce(jsonb_array_length(p_contexto -> 'alertas'), 0) > 0);

  if not v_tem_algo then
    return false;
  end if;

  v_novo_id := nullif(p_contexto -> 'procedencia' ->> 'ultima_mensagem_id', '')::bigint;
  if v_novo_id is null then
    return false;
  end if;

  select nullif(contexto_ia -> 'procedencia' ->> 'ultima_mensagem_id', '')::bigint
    into v_atual_id
    from lead_experimentais
   where id = p_lead_experimental_id;

  if v_atual_id is not null and v_novo_id <= v_atual_id then
    return false;
  end if;

  update lead_experimentais
     set contexto_ia    = p_contexto,
         contexto_ia_em = now()
   where id = p_lead_experimental_id;

  return found;
end
$function$;

revoke all on function public.fabio_gravar_contexto_experimental(integer, jsonb) from public, anon, authenticated;
grant execute on function public.fabio_gravar_contexto_experimental(integer, jsonb) to service_role;

comment on function public.fabio_gravar_contexto_experimental(integer, jsonb) is
'Grava contexto_ia. Recusa payload vazio, sem procedencia.ultima_mensagem_id, ou mais velho que o ja gravado. Extracao ruim nunca apaga extracao boa.';
