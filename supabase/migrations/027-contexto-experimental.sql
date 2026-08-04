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
-- Dois auxiliares que existem por causa de defeitos reais
--
-- `fn_texto_para_bigint`: o id da última mensagem chega como TEXTO dentro de um
-- JSON escrito por um LLM. `'abc'::bigint` levanta invalid_text_representation
-- -- e uma função que promete `returns boolean` passa a estourar exceção, o que
-- quebra o contrato com a edge function. Pior: dentro da SELEÇÃO, uma única
-- linha com lixo em `contexto_ia` derrubava a consulta inteira, e ninguém mais
-- era extraído. Aqui lixo vira NULL, que é a resposta honesta: "não sei até
-- onde li". `numeric_value_out_of_range` entra na mesma rede -- um id absurdo é
-- tão inútil quanto uma palavra.
--
-- `fn_bloco_tem_conteudo`: a guarda de conteúdo precisa ser SEMÂNTICA, não
-- estrutural. Ver o comentário na gravação, abaixo.

create or replace function public.fn_texto_para_bigint(p_texto text)
returns bigint
language plpgsql
immutable
parallel safe
set search_path to 'public'
as $function$
begin
  return nullif(btrim(p_texto), '')::bigint;
exception when invalid_text_representation or numeric_value_out_of_range then
  return null;
end
$function$;

revoke all on function public.fn_texto_para_bigint(text) from public, anon, authenticated;
grant execute on function public.fn_texto_para_bigint(text) to service_role;

comment on function public.fn_texto_para_bigint(text) is
'Cast text->bigint que devolve NULL em vez de levantar excecao. Existe porque o id da ultima mensagem vem de JSON de LLM.';

-- Um bloco "tem conteúdo" quando traz pelo menos um campo com valor de
-- verdade. Objeto vazio, array vazio, string vazia e null NÃO contam -- em
-- nenhum dos dois níveis.
--
-- O CASE é obrigatório, não estilo: `jsonb_each` levanta "cannot deconstruct a
-- scalar" se receber uma string, e o AND do SQL não promete curto-circuito.
-- Dentro do CASE a ordem de avaliação é garantida, então `jsonb_each` só é
-- alcançado depois de confirmado que o bloco é objeto.
create or replace function public.fn_bloco_tem_conteudo(p_bloco jsonb)
returns boolean
language sql
immutable
parallel safe
set search_path to 'public'
as $function$
  select case
    when p_bloco is null                   then false
    when jsonb_typeof(p_bloco) = 'array'   then jsonb_array_length(p_bloco) > 0
    when jsonb_typeof(p_bloco) <> 'object' then false
    else (select count(*) > 0
            from jsonb_each(p_bloco) as e(chave, valor)
           where jsonb_typeof(e.valor) <> 'null'
             and e.valor <> '""'::jsonb
             and e.valor <> '{}'::jsonb
             and e.valor <> '[]'::jsonb)
  end;
$function$;

revoke all on function public.fn_bloco_tem_conteudo(jsonb) from public, anon, authenticated;
grant execute on function public.fn_bloco_tem_conteudo(jsonb) to service_role;

comment on function public.fn_bloco_tem_conteudo(jsonb) is
'True so se o bloco jsonb tiver ao menos um campo com valor util. Esqueleto de schema (chaves presentes, valores vazios) e false.';

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
         public.fn_texto_para_bigint(le.contexto_ia -> 'procedencia' ->> 'ultima_mensagem_id')
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
  v_tem_algo boolean;
begin
  if p_contexto is null or jsonb_typeof(p_contexto) <> 'object' then
    return false;
  end if;

  -- Conteúdo de verdade: pelo menos um dos blocos úteis preenchido.
  -- `procedencia` sozinha não conta -- senão uma extração que não achou nada
  -- passaria por cima de uma que achou.
  --
  -- A checagem é SEMÂNTICA, não estrutural. A versão anterior perguntava só se
  -- a chave existia, e o modo de falha mais provável de um LLM é justamente
  -- devolver o esqueleto do schema com tudo vazio:
  --     {"recepcao": {}, "quem_e_esse_aluno": {}, "procedencia": {...}}
  -- Isso passava pela guarda e APAGAVA uma extração boa. `{"recepcao": ""}`
  -- também. `fn_bloco_tem_conteudo` olha dentro do bloco, nos dois níveis.
  --
  -- O coalesce externo é rede: se algum dia essa expressão voltar a produzir
  -- NULL, "if not NULL" NÃO dispara (PL/pgSQL só entra no IF quando a condição
  -- é TRUE) e a gravação vazia passa -- fail open, o defeito do mutante 1.
  v_tem_algo := coalesce(
       public.fn_bloco_tem_conteudo(p_contexto -> 'recepcao')
    or public.fn_bloco_tem_conteudo(p_contexto -> 'quem_e_esse_aluno')
    or public.fn_bloco_tem_conteudo(p_contexto -> 'ganchos_de_conexao')
    or public.fn_bloco_tem_conteudo(p_contexto -> 'alertas'), false);

  if not v_tem_algo then
    return false;
  end if;

  v_novo_id := public.fn_texto_para_bigint(p_contexto -> 'procedencia' ->> 'ultima_mensagem_id');
  if v_novo_id is null then
    return false;
  end if;

  -- A recência mora no WHERE do próprio UPDATE, não num SELECT antes dele.
  -- Com duas chamadas concorrentes (ids 3000 e 2000) o SELECT separado lia o
  -- MESMO valor atual nas duas, as duas passavam a guarda, e a mais velha podia
  -- escrever por último: o contexto REGREDIA. No WHERE, o segundo UPDATE relê a
  -- linha já travada pelo primeiro e simplesmente não casa -- devolve false.
  update lead_experimentais
     set contexto_ia    = p_contexto,
         contexto_ia_em = now()
   where id = p_lead_experimental_id
     and (public.fn_texto_para_bigint(contexto_ia -> 'procedencia' ->> 'ultima_mensagem_id') is null
          or public.fn_texto_para_bigint(contexto_ia -> 'procedencia' ->> 'ultima_mensagem_id') < v_novo_id);

  return found;
end
$function$;

revoke all on function public.fabio_gravar_contexto_experimental(integer, jsonb) from public, anon, authenticated;
grant execute on function public.fabio_gravar_contexto_experimental(integer, jsonb) to service_role;

comment on function public.fabio_gravar_contexto_experimental(integer, jsonb) is
'Grava contexto_ia. Recusa payload vazio (inclusive esqueleto de schema so com chaves), sem procedencia.ultima_mensagem_id, com id nao-numerico, ou mais velho que o ja gravado. A recencia e conferida no WHERE do UPDATE, entao chamadas concorrentes nao fazem o contexto regredir. Extracao ruim nunca apaga extracao boa.';
